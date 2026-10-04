# 功能设计：开局自带友好 NPC（Start With NPC）

> 目标模组：`ALifeStartWithNPC` v0.1.0（本目录 `Contents/mods/ALifeStartWithNPC/42.20/`）
> 定位：**Jeem Extension 的扩展**（`require=\ProjectALifeNPCs,\ProjectALifeJimmy`）
> 需求原话："扩展 jeem extension 模组的增加 start with npcs 的可能性，即玩家出生时带一名友好 npc"
> 建档：2026-10-04 · 状态：**已进游戏实测（T1/T2）→ 发现并修复 1 个 Kahlua 兼容 bug → 待复测**

---

## 1. 三条决定架构的实测事实

写这个功能前，先把"能不能做、该怎么做"三个问题用源码证掉：

| # | 问题 | 实测结论 | 证据 |
| --- | --- | --- | --- |
| 1 | Jeem 有没有"开局给 NPC"的现成入口？ | **没有**。全项目 `OnCreatePlayer` 出现 0 次，`OnGameStart` 的 8 处全是 UI/installer；居民 100% 来自 `R.recruit` | `ProjectALifeJimmy` 全量 grep |
| 2 | 能不能直接调 `R.recruit` 给玩家发居民？ | **不能凭空造人**。它要求 `ActorRegistry.read(uid)` 已存在该 actor，还要求 base / 床位容量 / `isAlly`（声望）；`force=true` 仅在 `who.admin` 时生效 | `Residents/Server.lua:566-629` |
| 3 | A-Life 有没有"跟随"能力？ | **有原生 follow，不要自建行为模块**：`DecisionLoop.setOrder(uid, generation, {kind="follow", player=...})`。自建模块会被 `orders`（priority=10，最早跑）抢跑 | `ALifeDecisionLoop.lua:1242`、`ALifeModuleTravel.lua:12` |

→ 由此得到**唯一正确的分层**：
**① 用 A-Life 公开 API 造一个友好 NPC（必做） → ② 可选交给 Jeem 变居民（锦上添花）**。

---

## 2. 架构（5 个文件）

```
Contents/mods/ALifeStartWithNPC/42.20/
├── mod.info                          require=\ProjectALifeNPCs,\ProjectALifeJimmy
├── poster.png                        512x512 PNG（已按工坊硬规则校验）
└── media/
    ├── sandbox-options.txt           9 个选项，表名 ALifeStartWithNPC.*（绝不占用 ALife.*）
    └── lua/
        ├── shared/ALifeStartWithNPC/Config.lua   读沙盒 / 日志 / 键名与阈值
        ├── shared/ALifeStartWithNPC/Pick.lua     从 Catalog 挑友好阵营 + 可用档案（带校验与三级回退）
        ├── server/ALifeStartWithNPC/Grant.lua    核心：造人 → 等激活 → 下 follow 或转居民
        ├── server/ALifeStartWithNPC/Bootstrap.lua 事件接线（SP 直连 / MP 命令 / 每分钟兜底）
        └── client/ALifeStartWithNPC/Request.lua   联机时向服务端请求一次
```

| 文件 | 关键点 |
| --- | --- |
| `Config.lua` | `Config.opt()` 对 `SandboxVars` 缺失的情况做了 pcall 保护；`MODULE` 名 = mod id（A-Life 红线） |
| `Pick.lua` | 一级：选项显式指定的 id（校验存在性）；二级：`stance.player` 为 friendly/neutral 的阵营；三级：任意可用阵营保底 |
| `Grant.lua` | 全部引擎/模组调用包 `pcall`；失败只降级不抛错 |
| `Bootstrap.lua` | 刻意的"只调度不执行"：真正能不能干由 `Grant.run` 的 ready 判定决定 |
| `Request.lua` | `isClient()` 才发请求；纯单机不发（避免自言自语） |

---

## 3. 核心链路（全部来自实测行号）

### 3.1 第一段 · 造人（两条路线共用）

```lua
-- 1) 造记录。operationId 自带幂等：同 op + 同 fingerprint 返回已有记录
local actor, err = ProjectALife.ActorRegistry.create({
    operationId = opId, fingerprint = fp,      -- ALifeActorRegistry.lua:374（必填校验 :375-380）
    profileId = profileId, factionId = factionId,
    worldPosition = { x = x, y = y, z = z },   -- 实体就生在这里（ALifeShellAdapter.lua:46）
    activity = "idle", intent = "hold",
    memory = {
        spawnStance = "friendly",              -- 友好的最小代码侧做法（ALifeRelations.lua:30-39）
        persistent = true,                     -- Population.expendable(...) 为 false（ALifePopulation.lua:132）
        admin = { persistent = true },         -- 唯一能挡 SpawnService.dehydrate 的标记（ALifeSpawnService.lua:32-36, 308）
        home = { x = x, y = y, z = z },
        groupId = "starter:" .. opId,
    },
})

-- 2) 请求实体化。内部同步 createShell + hydrateShell，实体在返回前就已存在
local request, rerr = ProjectALife.SpawnService.request(actor.uid, opId .. ":spawn", fp .. ":spawn", 2500)
if request == nil then                          -- ALifeSpawnService.lua:136
    -- 失败回滚：只有还 dormant 才能 remove，避免留孤儿
    local cur = ProjectALife.ActorRegistry.read(actor.uid)
    if cur and cur.lifecycle == "dormant" then
        ProjectALife.ActorRegistry.remove(cur.uid, cur.revision, "start_with_npc_rejected")
    end
end
```

要点：
- 出生点**精确**用 `worldPosition`；但朝向被 A-Life 硬编码为南（`ALifeShellAdapter.lua:57`），我们 spawn 后自行 `setDir`。
- 档案/阵营必须在 Catalog 里真实存在，否则 hydrate 失败（`profile_missing`）——所以 `Pick.lua` 先做存在性校验。
- 实体**同步**出现；账本 `lifecycle` 要到下一次 tick 才变 `active`（`settleTick` → `Registry.activate`）。

### 3.2 第二段 · 行为（二选一）

**Mode 1（默认）· 跟随**——用 A-Life 原生 follow，等 actor 变 `active` 后下指令：

```lua
local record = ProjectALife.ActorRegistry.read(uid)
if record ~= nil and record.lifecycle == "active" then
    ProjectALife.DecisionLoop.setOrder(uid, record.generation, {
        kind = "follow", player = player, source = "player",   -- ALifeDecisionLoop.lua:1242
    })
end
```

> 为什么不自己写跟随模块：`orders` 模块 `priority = 10`（最小=最先），任何自建模块都会被它先拦下；
> 而且 Jeem 自己就是为了修正 `followGap = 1.8` 才去包 `Decisions.followTarget` 的（`Jimmy/Core.lua:137`）。

**Mode 2 · Jeem 居民**——拿到/建立一个基地后 `recruit`：

```lua
local who  = ProjectALifeJimmy.BaseAreas.who(player)
local mine = ProjectALifeJimmy.BaseAreas.basesFor(who.key, who.faction, who.admin)
local base = mine and mine[1]
if base == nil and Config.createCamp() then
    base = ProjectALifeJimmy.BaseAreas.createBase({      -- Store.lua:389
        x1 = px - 8, y1 = py - 8, x2 = px + 8, y2 = py + 8,
        name = "Start Camp", role = "grounds" }, who)
end
-- 绕过床位统计：R.capacity 直接读 base.bedsOverride（Server.lua:1104-1108, 1254-1260）
base.bedsOverride = math.max(tonumber(base.bedsOverride) or 0, count + 2)
local n, why = ProjectALifeJimmy.Residents.recruit(player, uid, base.id, true)   -- Server.lua:566
```

- `force = true`：**单机恒可用**（`J.isAdminPlayer` 在 SP 恒为 true，`Core.lua:916-920`）；多人非管理员会被 `not_allied` 拦 → 我们**自动降级为跟随**。
- 居民语义是"守基地"，与跟随互斥，因此**转居民成功后不再下 follow 命令**。

### 3.3 友好度：让它开局就是「同盟」

需求原话："npc 的初始好感度要是同盟"。这里必须分清两套词汇，否则会写错：

| 系统 | 档位 | 能到"同盟"吗 |
| --- | --- | --- |
| **A-Life 关系**（`Relations` / `Reputation`） | `hostile / careful / neutral / friendly` | ❌ 不能：`allied` 会被归一化成 `friendly`（`ALifeRelations.lua:22`、`ALifeReputation.lua:131`）。而且 `memory.spawnStance` 的白名单只收 friendly/neutral/careful/hostile —— **写 "allied" 会被拒绝**，反而退回按阵营关系计算（可能敌对） |
| **Jeem 声望**（`StandingService`） | `hostile / careful / neutral / friendly / **allied**`（`Services/Standing.lua:14`） | ✅ 这才是"同盟"的所在，`thresholds = {25, 75, 150, 250}` |

**实现**（`Grant.makeAllied`，v0.1.3 起）：

```lua
-- 首选官方路径：它按档位换算点数，并**先清掉 A-Life 声望里那条记录**
local ok, label = pcall(ProjectALifeJimmy.Standing.debugSet, player, factionId, "allied")

-- 退路（联机非管理员会被 debugSet 以 AdminsOnly 拒绝）：复刻它的三步
local steps = S.index["allied"] - S.index[S.defaultLabel(factionId)]
local points = steps == 0 and 0 or (steps > 0 and S.thresholds[steps] or -S.thresholds[-steps])
S.set(key, factionId, points - S.poolBonus(key, factionId))
store.players[key][factionId] = nil            -- ← 关键一步，见下
ProjectALifeJimmy.Standing.apply(key, factionId)     -- 写回 A-Life 声望
S.addGroup(key, groupId, factionId, 400)             -- 组声望（R.isAlly 的另一条判据）
```

> ⚠️ **`provoked` 坑（差点静默失效）**：A-Life 声望里若已有该玩家/该阵营的一条
> `cause = "provoked"` 记录，`F.apply` 会因为" provoked 且目标标签不是 hostile "而**拒绝覆盖**它，
> 同盟就永远设不上。官方 `Standing.debugSet` 里那句 `store.players[key][factionId] = nil` 正是为此。
> 我们的退路已复刻这一步（`ModData.getOrCreate(Reputation.TAG)` → 清条目 → 置 dirty → `F.apply`）。

第 3 步的作用：Jeem 的 Standing 特性（`Features/Standing/Standing.lua:123` `F.apply`）会把标签写进
A-Life 的声望存档（foreign faction 写 `status = label`，own faction 直接写 `status = "allied"`），
所以这一下**同时**把 A-Life 侧的关系顶到它能表达的上限（friendly）。

**带来的两个好处**：

1. A-Life 侧仍是 `memory.spawnStance = "friendly"`（上限），NPC 绝不会对玩家翻脸；
2. Jeem 侧是 `allied` ⇒ `R.isAlly(key, record)` 通过 ⇒ **居民收编改走正规（非 force）路径**，
   联机里**非管理员**玩家也能收编（force 只在 `who.admin` 时生效，这是之前联机的隐患）。

**副作用（已写进沙盒 tooltip）**：Jeem 的声望是**按阵营**记录的，所以变成同盟的是整个阵营，而不只是这一名 NPC。
可用 `ALifeStartWithNPC.MakeAllied = false` 关闭，改为正常地慢慢赢得信任。

---

## 4. 我们依赖的 API 与稳定性评级

| API | 评级 | 依据 |
| --- | --- | --- |
| `ActorRegistry.create/read/remove` | 【稳定】 | 返回值式错误码 + `operationId` 幂等 + `revision` 乐观锁 |
| `SpawnService.request(uid, op, fp, timeoutMs)` | 【稳定】 | 4 参数、类型校验、失败自动回滚 |
| `DecisionLoop.setOrder(uid, generation, order)` | 【稳定】 | 只接受 `follow/hold/patrol`，校验 generation，Jeem/官方菜单都在用 |
| `Catalog.faction/npc` | 【稳定】 | nil 安全查表 |
| `memory.spawnStance` | 【半稳定】 | 无版本守卫，但入口有白名单校验（`Relations.spawnStance`） |
| `memory.admin.persistent` / `memory.persistent` | 【半稳定】 | 字段名是内部约定 |
| `BaseAreas.who/basesFor/createBase/transmit` | 【半稳定】 | 有具名校验与失败原因 |
| `Residents.recruit` | 【半稳定】 | 有正式 command 注册与官方菜单调用者，40 种具名失败原因 |
| `J.enabled / J.playerKey` | 【稳定】 | Jeem 全项目自用的小工具 |
| `Runtime.started` | 【半稳定】 | 唯一权威 ready 标志，但属内部状态字段 |
| `Registry.setWorldValue/getWorldValue` | 【稳定】 | 存档级键值，新档天然为空 |

**红线遵守情况**：没有在 A-Life / Jeem 目录里放任何文件；没有 rebind 任何 `ProjectALife.*` 表；
网络 module 用自己的 mod id；沙盒表用自己的 `ALifeStartWithNPC.*`；文本用自己的 `Sandbox_ALifeStartWithNPC.*` 前缀。

---

## 5. 幂等与存档设计（四层，防重复发放）

| 层 | 机制 | 作用 |
| --- | --- | --- |
| 1 | `player:getModData()[KEY_GRANTED]` | 同一角色**同一存档**内只发一次（最快路径） |
| 2 | 角色级令牌 `KEY_TOKEN` + `operationId = MODULE:key:token:index` | 同一角色重进存档 → 令牌不变 → `operationId` 相同 → **A-Life 幂等返回旧记录，绝不重复造人**；新角色 → 令牌新 → 正常发放 |
| 3 | `ActorRegistry.setWorldValue(SAVE_TAG, true)` | `GrantOnRespawn = false` 时实现"每个存档只给第一个角色"；拿不到该 API 时退回 `ModData.getOrCreate` |
| 4 | `SpawnService.request` 的 `actor_not_dormant` 拒绝 | 万一前几层都失效，重复请求会被 A-Life 自己挡回 |

---

## 6. 时序与就绪判定

```
OnCreatePlayer（纯单机） / OnClientCommand:requestGrant（联机）
   └─ Bootstrap.start(player)：注册 OnTick 轮询（同一时刻只允许一个轮询）
        └─ Grant.run(player)：
             ① 选项开关 / 已发放？
             ② worldReady()：ProjectALife.Runtime.started == true
                             且 player:getCurrentSquare() ~= nil
             ③ 取玩家身边已加载的方块（绕圈找空位，多个 NPC 用不同角度避免叠人）
             ④ Pick.choose() 选阵营/档案
             ⑤ 逐个 create + request
             ⑥ 成功后写 KEY_GRANTED（+ 可选存档级标记）
        └─ Grant.tick()（每 tick）：等 lifecycle == "active" → 下 follow 或 recruit
   └─ 90s 内没就绪 → 放弃本轮，转 EveryOneMinute 兜底重试（最多 5 次）
```

为什么不直接在 `OnCreatePlayer` 里造人：那一刻 `Runtime.started` 往往还是 false，
`SpawnService.request` 会返回 `runtime_not_started`（`ALifeDebugService.lua:1547` 同源判定）。

---

## 7. 已知限制与副作用（必须让玩家知道）

| # | 限制 / 副作用 | 说明与缓解 |
| --- | --- | --- |
| 1 | **居民模式会占用一个 Jeem 基地名额**（默认 `Base_MaxBases = 2`） | 可用 `Resident_CreateCamp = false` 关掉自动建营地；此时若玩家没有基地，自动降级为跟随同伴 |
| 2 | **居民不跟随** | 居民语义是守基地（岗位/作息），这是 Jeem 的设计；要跟随请用模式 1 |
| 3 | **多人非管理员可能降级** | `recruit(force=true)` 只在 `who.admin` 时跳过 `not_allied`；失败即降级为跟随，不会报错 |
| 4 | 朝向硬编码为南 | A-Life `createZombieShell` 固定 `IsoDirections.S`；我们 spawn 后自行 `setDir` |
| 5 | 出生点可能不在玩家正脚下 | 我们绕圈找**已加载**方块；若周围全未加载会返回失败并等下一次 tick |
| 6 | 联机下客户端要能看见居民行为 | 依赖 Jeem 的 Relay wrap（它装在 installer 里），所以模式 2 会等在 `pendingInstalls == 0` 之后才动手 |
| 7 | 数量上限 5 | 每个都是完整 A-Life NPC（有 AI/装备/背包），多了会吃性能 |

---

## 8. 测试清单（进游戏前请按此逐项验证）

**准备**：启用模组 `ALifeStartWithNPC` + `ProjectALifeNPCs` + `ProjectALifeJimmy`，`DebugLog = true`。

| # | 场景 | 期望 |
| --- | --- | --- |
| T1 | **单机新档**，默认选项 | 出生后 1 秒内控制台出现 `grant complete: 1/1 npcs (mode=1)`；身边 2 格内出现一名 NPC；**它开始跟着你走** |
| T2 | 同上，**立刻保存并退出，再读档** | **不会**再刷一个；控制台无新的 `grant complete` |
| T3 | 新档 → 让 NPC 被咬死 → 观察 | NPC 正常死亡掉落（A-Life 自己的掉落），不报错；不会被 OrphanGuard 缴械 |
| T4 | 开 `GrantOnRespawn`，角色死亡后重生 | 新角色**再次获得** NPC（令牌变了 → 新记录） |
| T5 | 关 `GrantOnRespawn`，死亡后重生 | **不再发放**（存档级标记生效） |
| T6 | `Mode = 2`（居民），新档 | 自动建 `Start Camp`；NPC 成为居民并在营地里站岗；控制台有 `recruited ... into base` |
| T7 | `Mode = 2` 且 `Resident_CreateCamp = false`，玩家无基地 | 控制台提示降级，NPC 仍然存在并跟随 |
| T8 | `Count = 3` | 3 个 NPC 出现在不同方位，不重叠；控制台 `3/3` |
| T9 | `FactionId =` 写一个不存在的 id | 控制台 `faction_not_found:xxx`，**不刷 NPC**、不报错崩溃 |
| T10 | `Enabled = false` | 什么都不发生（无日志噪声） |
| T11 | **多人主机** | 客户端发 `requestGrant`，主机侧完成发放；客户端能看到 NPC |
| T12 | **专用服务器**（非管理员客户端） | 若居民转换失败，客户端侧仍出现跟随同伴 |
| T13 | 不带 Jeem（只带 A-Life）启动 | `mod.info` 的 `require` 会拦下；若强行加载，`makeResident` 报 `jimmy_unavailable` 并降级 |
| T14 | 帧率/日志检查 | `[ALifeStartWithNPC]` 日志无 `[ERROR]`；无 Lua 报错栈 |

**性能观察**：`Count = 5` 时观察 `[ALIFE-PERF]` 是否出现明显变化；每 tick 我们只做一次 `next(pending)` 判空 + 队列推进，开销可忽略。

---

## 8.5 首次进游戏实测（2026-10-04）

**结果：失败一次，已修。**

| 现象 | `console.txt` 里刷了 **499 条** `[ALifeStartWithNPC][ERROR] tick failed: Object tried to call nil in tick`，每帧一条 |
| --- | --- |
| 堆栈 | `Grant.lua:215` ← `Bootstrap.lua:114`（即 `Grant.tick` 的调用点） |
| 根因 | 第 215 行是 `if next(Grant.pending) == nil then return end`。**Kahlua 没有 `next()`** —— Jeem 的 `Core.lua:231` 明确写着 `-- Kahlua has no next(): use this for "is this table empty?"`。于是这一句每帧抛错 |
| 影响 | `Grant.tick` 永远跑不完 → 待处理队列（等实体激活 → 下 follow 命令）永远不推进；`Grant.run` 本身不受影响，但整个 tick 线程每帧报错刷屏 |
| 修法 | 引入 `Grant.pendingCount` 显式计数（入队 +1 / 出队 -1），用 `if Grant.pendingCount <= 0 then return end` 替代，**彻底不用 `next()`，也不靠遍历判空** |
| 附带加固 | `os.time` 兜底包 `pcall`（不假设 Kahlua 暴露它）；预防性复核了 `table.sort`（Kahlua 排序不稳定，本模组未用）与 `%`（Kahlua 是截断取模，本模组未用） |

### Kahlua ≠ Lua 5.1：写 PZ 模组必须记住的三条（有据可查）

| # | 限制 | 证据 | 我们怎么规避 |
| --- | --- | --- | --- |
| 1 | **没有 `next()`** | Jeem `Core.lua:231` 注释；本模组的 499 条报错 | 用 `for _ in pairs(t)` 或显式计数 |
| 2 | **`table.sort` 不稳定**（快排会打乱相等项） | Jeem `Core.lua:906`、`Server.lua:798/288/180` 均注释过 | 本模组不使用 `table.sort`；未来要排序必须带唯一 tiebreaker |
| 3 | **`%` 是截断取模**，不是 Lua 5.1 的向下取整 | Jeem 注释 "a mod b the Lua 5.1 way (floored)... The game's Kahlua truncates instead" | 本模组不使用 `%`（只用 `string.format("%d")` 格式串） |

## 8.6 第二次实测（v0.1.1，`console.txt` 语义）

**T1 —— 通过 ✅**（两个独立会话各一次）

```
[ALifeStartWithNPC] grant #1: faction=alife_kettle profile=kettle_breaker (friendly:neutral)
[ALIFE-LIFECYCLE] hydrate uid=palife:...:1 generation=1 op=ALifeStartWithNPC
                  at=10712,9404,0 bodyAt=10712,9404,0 nearest=2 loaded=true ... inList=true side=sp
[ALifeStartWithNPC] spawned palife:...:1 at 10712,9404 (faction=alife_kettle profile=kettle_breaker)
[ALifeStartWithNPC] grant complete: 1/1 npcs (mode=1)
```

- A-Life 自己的 `[ALIFE-LIFECYCLE] hydrate` 是**第三方证据**：实体落在离玩家 **2 格**、`loaded=true`、
  `inList=true`（在僵尸列表里）、`side=sp`。
- 修复后**再无** `[ALifeStartWithNPC][ERROR]`（日志里 499 条报错全部来自修复前的 v0.1.0 会话）。
- 附带验证：该 NPC 是**标准 A-Life NPC**，玩家随后用 Jeem 界面手动收编成功
  （`[ALIFE-JIMMY] residents: sp:0 invited 1 (alife_kettle, group starter:ALifeStartWithNPC:...) to base base:1`），
  说明与 Jeem 的互操作性成立。

**尚未验证**（各自需要一次操作）：

| 测试 | 为什么还没结论 |
| --- | --- |
| T2 读档不重复 | 日志里两次发放的令牌不同（`1791083734047` vs `1791084258537`）⇒ 是**两个不同角色**，不能算 T2；v0.1.3 已加 `already granted ... skipping` 日志，一眼可验 |
| T1 的"跟随"部分 | v0.1.1 还没打印 follow 结果；v0.1.3 已加 `follow order accepted for <uid>` |
| 同盟是否生效 | 同盟是 v0.1.2 才有的；日志里最后一个会话仍是 v0.1.1 |
| T3~T14 | 未执行 |

## 8.7 第三次实测：多人联机（v0.1.3，结论：本模组正常，报错另有其人）

**本模组在联机下工作正常** ✅（`coop-console.txt`，coop 会话）

```
[ALifeStartWithNPC] Bootstrap loaded (v0.1.3)
[ALifeStartWithNPC] grant requested by IsoPlayer{ Name:null, ID:2 } (client)   ← 服务端收到客户端请求
[ALifeStartWithNPC] grant #1: faction=alife_kettle profile=kettle_shooter
[ALifeStartWithNPC] spawned palife:...:8 at 6410,5498
[ALifeStartWithNPC] standing with alife_kettle is now ALLIED                  ← 同盟（0.1.2+）
[ALifeStartWithNPC] follow order accepted for palife:...                      ← 跟随
[ALifeStartWithNPC] grant complete: 1/1 npcs (mode=1)
（另一名玩家同流程，profile=kettle_foreman，位置不同 ⇒ 每玩家各一份）
```

- 2 名玩家、2 次发放、**`spawn failed` 0 次**。
- 注意最后加载的版本号是 v0.1.3 ⇒ **T2（读档跳过）与同盟都在本会话被间接验证**：
  `console.txt` 里出现了 `this character was already granted earlier; skipping (no duplicate NPC)`。

**真正的报错源**（**不是本模组**）

```
ERROR: Missing translation "UI_Alife_Animations_20"
java.lang.RuntimeException: no such location "UI_Alife_Animations_20" at AttachedLocationGroup.checkValid
  ALifeAnimations.presentWeapon (ALifeAnimations.lua:560)
  ALifeProfileHydrator.defaultApply (:673) → hydrate (:923)
  ALifeShellAdapter.hydrateShell (:241) → SpawnService.request (:162)
  ← 调用方栈：Grant.spawnOne / run / attempt / pollFn
```

- 堆栈里那个 `ALifeAnimations.lua` 标注的模组是 **`MOD:Project A-Life [中文汉化]`**，不是 A-Life 本体。
- 该模组（工坊 `3807277264`）**自带 233 个 Lua 文件**，且**命中 A-Life `probePaths` 的 4/4 个旧路径**：
  `shared/ProjectALife/Data/ALifeCatalog.lua`、`shared/ProjectALife/Dialogue/ALifeDialogueData.lua`、
  `server/ProjectALife/Runtime/ALifeRuntime.lua`、`shared/ProjectALife/Presentation/ALifeAnimations.lua` ——
  即 **A-Life 1.3 重构前的整包旧副本**（现在的布局是 `Records/`、`Interface/`、`Core/`、`Shells/`）。
- 归因统计（同一会话）：`hydrateShell` 失败 **40 次**，其中经本模组 **28 次**、**A-Life 自己的生成 12 次** ⇒
  **A-Life 自己也中招**，只是本模组把噪声放大得更明显。
- A-Life 自己在 `ALifeModCompat` 里对这种模组的判定与后果写得很清楚：
  `incompatible: ships its own copy of A-Life's file ... breaks on updates`、
  `old copy ... NPCs throw errors and stutter until that mod's A-Life Lua files are removed`。
- 该异常被 A-Life 内部的 `pcall` 捕获（`ALifeProfileHydrator.lua:892`），**不致命**，但每次都刷 ERROR 栈。

**处理建议**：禁用/退订 `3807277264`；需要中文用 `3805566620`（0 个 Lua 文件，符合 A-Life 的"只发 Translate"要求）。

**顺带排除的另一个"报错"**：日志开头的
`AdvancedAnimator$1.visitFileFailed > NoSuchFileException .../media/actiongroups`
是引擎对**所有**缺少 `media/AnimSets` 与 `media/actiongroups` 目录的模组的通用噪声 ——
本仓库自己的 `NestedContainersTake`、`CompanionDogsAlpaca` 各报 8 条，A-Life 的两个官方扩展
（Jeem、Aftermath）同样没有这两个目录。与本模组无关。

**0.1.4 因此新增两项防御**：

1. **开局兼容自检**：复用 A-Life 自己的 `ProjectALife.Compat.foreignCopies(active)`，
   把"自带 A-Life Lua 副本"的模组**点名打进 console.txt**（并在水合失败时再报一次），
   并在提示里直接给出结论："A translation must ship only Translate files"。
2. **生成重试节流**：两次生成尝试至少间隔 `Config.SPAWN_RETRY_MS = 2000`，每玩家每会话最多
   `Config.MAX_SPAWN_ATTEMPTS = 5` 次 —— 避免"数据没就绪"时每帧 `create/remove` 并刷日志
   （节流闸位于 `worldReady` 之后，所以只有"真的尝试生成"才计数）。

## 9. 未验证项（诚实声明）

1. **T1 已通过**（见 8.6）；T2 与 T1 的跟随部分需要按 0.1.3 的新日志复测一次；T3~T14 仍全部待执行。
2. `PlayerLocator.position(player)` 的返回结构按"含 x/y 的表"使用；若实际是别的形状，会自动退回 `player:getX()`。
3. `DecisionLoop.setOrder` 我未实测其返回值语义（本实现把 `false` 与异常都当作"没接受"并记日志，不影响流程）。
4. `memory.admin.persistent` 能挡 `dehydrate` 是**读代码得出**的（`ALifeSpawnService.lua:32-36, 308`），未做运行时验证。
5. `base.bedsOverride` 是直接写字段绕过床位统计（Jeem 自己读它但不校验来源），属于【半稳定】用法。

---

## 10. 后续（v0.2 候选）

- [ ] 进游戏跑完 T1~T14，把结果回填到本文件与 `rolling_log`
- [ ] 自定义跟随距离：包 `Decisions.followTarget` 调整 `followGap`（Jeem 已有先例 `J.exactFollow`），或加一个"贴身/松散"选项
- [ ] 给玩家一条 `HaloText`/`IG_UI` 提示（现在只有控制台日志）
- [ ] 背包/武器预设：让开局 NPC 携带指定装备（走 `ProfileHydrator` 的公开面或 Catalog 档案选择）
- [ ] 与 `bin2_companion_alpaca` 联动：开局带一名 NPC + 一只羊驼
- [x] 发布准备：`workshop.txt`（多行 description、tag 白名单、`visibility=private`）、`preview.png`（256×256）、
      `changelog.txt` 已就位；staging 软链已建；探针实测 `readWorkshopTxt=true` / `validatePreviewImage=OK`
- [ ] 首次上传（建议先 private 验证，确认无问题再改 `visibility=public` 重传）

---

## 11. staging 已就位：怎么进游戏测试

```bash
# 两条软链（已建好）
~/Zomboid/Workshop/ALifeStartWithNPC  ->  <repo>/bin2_ProjectALifeNPCs_extensions            # 工坊待上传目录
~/Zomboid/mods/ALifeStartWithNPC       ->  <repo>/bin2_ProjectALifeNPCs_extensions/Contents/mods/ALifeStartWithNPC   # 本地加载

# 上传前校验（用游戏自己的解析器，不会真的上传；需 Steam 已登录）
bash bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/ALifeStartWithNPC
```

**探针实测结果（2026-10-04）**：

```
readWorkshopTxt       = true
id                    = null  (未发布：workshop.txt 里没有 id=)
title                 = A-Life: Start With NPC [Jimmy add-on] - 开局自带友方 NPC (Build 42)
visibility            = 2            # private
tags                  = [Build 42, QoL, Misc, Multiplayer, WIP]
contentFolder         = .../Contents  exists=true
validatePreviewImage  = OK
```

进游戏步骤：Mods 里启用 `ALifeStartWithNPC` + `Project A-Life` + `Jeem Extension` → 开新档 →
看 `console.txt` 是否有 `[ALifeStartWithNPC] grant complete: 1/1 npcs (mode=1)`。
> 注意：`workshop.txt` 目前是 `visibility=private`，属于**首次上传前的安全默认**（避免把未实测版本直接公开）。
