# 招募一名 A-Life NPC：Jeem / 原生 双路径 API 逆向报告

> 分析对象（只读，未修改任何被测文件）
> **`J:`** = `/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600/3806944055/mods/ProjectALifeJimmy`
> **`CORE:`** = `/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600/3803984183/mods/ProjectALifeNPCs`
> 版本基准：A-Life **1.3.15**（`CORE/42.20/mod.info:4`）、Jeem **0.4.6**（`J/42/mod.info:4`）
> 旧报告（`extension-jeem-analysis.md` 等）仅作索引，**本文所有行号均已重新核实**。

---

## 结论速览

| 能力 | 入口（file:line） | 评级 | 降级方案 |
|---|---|---|---|
| 判断 Jeem 是否可用 | `ProjectALifeJimmy` 表：`J:shared/ProjectALifeJimmy/Core.lua:6` | 稳定接口 | `getActivatedMods():contains("ProjectALifeJimmy")` 兜底 |
| Jeem 功能开关 | `J.enabled("residents")` `Core.lua:1094` | 稳定接口 | 直接 `J.opt("Residents_Enabled", true)` |
| 造一个 NPC | `ActorRegistry.create` `CORE:.../ALifeActorRegistry.lua:374` | 半稳定 | 无（必须用） |
| 让实体真的出现 | `SpawnService.request` `CORE:.../ALifeSpawnService.lua:136` | 半稳定 | 无（必须用） |
| 原生跟随玩家 | `DecisionLoop.setOrder{kind="follow",player=}` `CORE:.../ALifeDecisionLoop.lua:1242` | 半稳定 | 无（唯一原生跟随） |
| 防人口回收 | `memory.admin.persistent=true` `CORE:.../ALifeSpawnService.lua:32` | 半稳定 | `memory.persistent`（弱一档） |
| Jeem 收编为居民 | `J.Residents.recruit(player,uid,baseId,force)` `J:.../Residents/Server.lua:566` | 半稳定 | 失败即退回原生 follow |
| Jeem 跟随/等待 | `J.Friendlies.order(player,record,"follow"/"hold"/"clear")` `J:.../Friendlies/Friendlies.lua:100` | 半稳定 | Jeem 内唯一实现，无替代 |
| Jeem 解散居民 | `J.Residents.dismiss(player,baseId)` `Server.lua:784` | 半稳定 | `R.leave(base,"dismissed")` `:705` |
| Jeem 基地（居民必填） | `BaseAreas.createBase(args,who)` `J:.../BaseAreas/Store.lua:389` | 半稳定 | `BaseAreas.basesFor` 取已有基地 `:338` |
| Jeem 拉到「同盟」 | `J.StandingService.set/addGroup` `J:.../Services/Standing.lua:146,178` | 内部细节 | `F.debugSet`（需管理员）`:175` |
| 服务端→指定玩家推送 | `sendServerCommand(p, "我们的modId", cmd, args)` | 稳定接口 | — |

---

## 1. 版本与入口

**`CORE/42.20/mod.info:1-8` 全字段**：`name=Project A-Life [ALIFE NPCS]`、`id=ProjectALifeNPCs`、`author=Vice`、`modversion=1.3.15`、`versionMin=42.21.0`、`poster=poster.png`、`icon=icon.png`、`description=...`。**无 `require`、无 `loadModAfter`、无 `incompatible`**——A-Life 是依赖树根，扩展必须自己声明 `require=\ProjectALifeNPCs`。
`CORE` 只有一个 `mod.info`（`42.20/`），没有 `common/mod.info`。

**`J/42/mod.info:1-9` 全字段**：`name=Project A-Life - Jeem Extension`、`id=ProjectALifeJimmy`、`author=jeemlettuce`、`modversion=0.4.6`、`versionMin=42.20.0`、`require=\ProjectALifeNPCs`、`loadModAfter=\ProjectALifeNPCs`、`poster=poster.png`、`description=...`。注意 **Jeem 的 `versionMin`(42.20.0) 低于 A-Life 自身的 `versionMin`(42.21.0)** —— 这是版本错配风险的直接来源。

**全局表初始化**：`J:shared/ProjectALifeJimmy/Core.lua:6` `ProjectALifeJimmy = ProjectALifeJimmy or {}`，第 7-14 行立即写 `J.version="0.4.6"`、`J.TAG`、`J.MODULE="ProjectALifeJimmy"`、`J.status/installers/wrapped`。该文件在 `shared/` 下，**模组启动（进主菜单前）就会执行**，早于任何世界。

**没有 `ready` / `initialized` 标志**。可用的等价判据有三层，按可靠性排序：

```lua
local J = ProjectALifeJimmy
local ok = type(J) == "table"                       -- Core.lua:6，启动即有
    and type(J.enabled) == "function" and J.enabled("residents")   -- Core.lua:1094 + Residents.lua:266
    and type(J.Residents) == "table" and type(J.Residents.recruit) == "function"  -- 需 server 文件已加载
```
- `J.features["residents"]` 由 **shared** 文件注册（`J:shared/.../Features/Residents/Residents.lua:266-267`），启动即有；
- `R.recruit` 定义在 **server** 文件（`J:server/.../Residents/Server.lua:566`），**只在世界开始后才存在**（Jeem 自己在 `Core.lua:1336-1339` 注释确认："in single player and on MP clients, ... our own server/ files only load when a game starts"）。
- `J.status[feature]` 与 `J.pendingInstalls`（`Core.lua:1349-1365`）是 installer 的完成度，不是全局 ready 标志。

---

## 2. 原生 A-Life：现有的「招募/跟随」能力

### 2.1 结论：A-Life **没有**任何玩家雇佣/同伴机制

对 `hire`/`recruit`/`companion`/`follower`/`playerOwned`/`pet`/`escort` 在 `CORE/42.20/media/lua` 全量 grep，**命中全部落在对话框白（`shared/ProjectALife/Talk/Data/*.lua`）与建筑贴图字段上**。唯一沾边的是对话意图：
- `CORE:.../Talk/ALifeTalk.lua:432-437` `Talk.accept(record, player, ask, now)`：`ask == "JOIN_GROUP"` / `"WALK_TOGETHER"` / `"STAY_NIGHT"` 时**只调用 `Talk.tolerate`（8 分钟不开火）**，不产生跟随、不入队、不写归属。`ALifeTalkMenu.lua:154` 注释直说："this does not recruit or command them"。

**结论：A-Life 侧「跟随」只有一条路 —— `DecisionLoop.setOrder`。** Jeem 作者在 `J:.../Friendlies/Friendlies.lua:4-6` 明确写了同一判断："A-Life reads these phrases ... but nothing happens ... A-Life *does* have orders (DecisionLoop.setOrder: follow a player / hold a spot ...), used only by squad leaders"。

### 2.2 `DecisionLoop.setOrder` 精确签名

`CORE:.../Decisions/ALifeDecisionLoop.lua:1242-1276`

```lua
function Decisions.setOrder(uid, generation, order)   -- 返回 true | false, why
    -- 校验 1: actor 必须存在且 lifecycle=="active"、generation 完全相等
    --   否则 false, "order_actor_stale"                     (:1244-1246)
    -- 校验 2: kind 白名单：{ follow = true, hold = true, patrol = true }
    --   否则 false, "order_invalid"                          (:1247-1249)
    -- 校验 3: kind=="follow" 必须给 order.player（**IsoPlayer 对象**，不是字符串）
    --   否则 false, "order_player_missing"                   (:1250)
    -- 校验 4: kind~="follow" 必须给 order.anchor（表 {x,y,z}）
    --   否则 false, "order_anchor_missing"                   (:1251-1253)
    -- 校验 5: source=="leader" 且当前状态是 combat 时拒绝
    --   false, "order_member_engaged"                        (:1255-1257)
```

**合法 `kind` 只有 3 个：`follow` / `hold` / `patrol`**（没有 guard/escort/patrolArea；`guard` 是 `memory.stance` 的取值，另一套体系，见 `ALifeModuleStances.lua:896-902`）。

`order` 表字段（`:1261-1268`）：`kind`、`player`（follow 用）、`anchor`（hold/patrol 用）、`untilMs`（毫秒时间戳，nil = 不过期）、`source`（**`"leader"` 才保留，其它一切值都会被归一化成 `"player"`**）、`quiet`（true 则播放静默，不放 follow/stop/salute 动画与 ORDER_ACK 语音，`:1271-1274`）。

**执行侧**：`Decisions.orders` 由模块 `orders` 消费 —— `CORE:.../Behaviours/ALifeModuleTravel.lua:12-62`（`id="orders"`，优先级最高 `ALifeModuleRegistry.lua:44 orders = 10`），`Travel.lua:19` 先判 `order.generation ~= actor.generation` 直接返回 nil。
→ **关键前置：NPC 的 `behaviorProfile.overlays` 必须含 `orders`**。内建 profile 都带（`ALifeBehaviorProfiles.lua:63/71/80/89/98`，`ALL_OVERLAYS` 第 13 项 `:13`），**自建 profile 漏了它 follow 会静默失效**。可用 `memory.moduleOverrides = { orders = "on" }` 强行打开（`J:shared/.../Residents/Residents.lua:33-34` 就是这个手法）。

**玩家跟随还需要什么附加状态？** 不需要 `followTarget`、不需要 `Army`、不需要写 modData。`followTarget` 是**内部执行函数**（`:166-179`，`followGap=1.8`、`followHold=2.2`）；`orderedTarget`（`:181-193`）在 `kind=="follow"` 时 `positionOf(order.player)` 取玩家坐标，`Travel.lua:55-59` 距离 ≤2.2 就 `follow_close` 挂机。

唯一真正的附加要求：`DecisionLoop.orders` 是**纯内存表**（`:1215`），**不进存档**，读档后所有 follow 命令全丢 —— 必须在每次进档后重下（见 §6）。

### 2.3 `ActorRegistry.create` / `SpawnService.request` 精确参数表

`create` —— `CORE:.../Core/ALifeActorRegistry.lua:374-430`：

| 字段 | 要求 | 备注 |
|---|---|---|
| `operationId` | string，1..128 | **幂等键**：同 id+同 fingerprint 直接返回旧记录 `:383-389`；同 id 不同 fingerprint → `nil,"operation_conflict"` |
| `fingerprint` | string，1.. | 与 operationId 配对 |
| `profileId` / `factionId` | string，1.. | **必须真实存在于 Catalog**，否则 `actor_specification_invalid` |
| `worldPosition` | `{x,y,z}` 三个有限数 | 只做「是数字」校验，不做地形校验 |
| `uid` | string，1..64，可选 | 不传则 `"palife:<ts>:<seq>"` `:142-151` |
| `activity` / `intent` | 可选，默认 `"idle"` / `"hold"` | |
| `memory` | 表，可选 | 写 `spawnStance`、`persistent`、`admin.persistent`、`groupId`、`home` 的地方 |

返回 `record(深拷贝), replayed(bool)`；失败 `nil, why`（`"actor_specification_invalid"`、`"uid_invalid"`、`"operation_conflict"`、`"actor_record_invalid"`、`"actor_persistence_failed"`）。**新记录初始 `lifecycle="dormant"`、`generation=0`、`revision=1`**（`:394-405`）。

`request` —— `CORE:.../World/ALifeSpawnService.lua:136-196`：`SpawnService.request(uid, operationId, fingerprint, timeoutMs)` →
- 三参数校验失败 → `nil,"spawn_request_invalid"`；
- 幂等：`pending`/`settled` 已有同 operationId 且 uid/fingerprint 一致 → 返回旧 request（`:141-147`）；
- `lifecycle ~= "dormant"` → `nil,"actor_not_dormant"`（**同一 NPC 不能重复 spawn**）；
- **同步** `createShell`（`:156`）→ **同步** `hydrateShell`（`:162`）→ 交 `Watchdog.beginSpawn`（`:171`）异步等落地。
- 返回 `request{ uid, generation, operationId, fingerprint, shell, action, status="spawning" }`；**`request.shell` 当场可用**（`ALifeDebugService.lua:2071` 拿到就 `Animations.apply`）。

**什么时候实体才真正 active**：`settleRequest`（`:226-253`）在 Watchdog action 完成后调 `Registry.activate(...)`，`lifecycle` 变 `"active"`。合法取值只有 `dormant / spawning / active / dead`（`ALifeActorRegistry.lua:21-26`）。
**等待方式**（照抄 `ALifeStartWithNPC/Grant.lua:412-440`）：`Events.OnTick` 里轮询 `Registry.read(uid).lifecycle`，`"active"` 才下 order，`"dead"`/`nil` 或超过 ~600 tick 放弃。**不要在 `request` 后立刻 `setOrder`** —— `"spawning"` 会被判 `order_actor_stale`。

### 2.4 人口预算与「被回收」风险

**存在上限**：`ALife.Population_HostileCeiling`（`CORE/42.20/media/sandbox-options.txt:46-50`，默认 **32**，范围 4..160）→ `Settings.current.maximumHostileActors`（`ALifeSettings.lua:48-49,165`）。`Population.tick` 在 `capacityUsed(false) >= maximumHostileActors` 时**拒绝新 spawn**（`ALifePopulation.lua:481-485`）；`Director.maximumLivingActors`（`ALifeDirector.lua:26,440-442`）同理。即「**新的 dormant 生不出来**」，不是「已有的被删」。

**真正会「删掉」我们 NPC 的三条路径**：

1. **dormant TTL 回收（最危险）**：`ALifePopulation.lua:426-434` —— `lifecycle=="dormant"` **且** `expendable(actor)` **且** 离玩家 >60 格（`spawnDistance`）**且** 休眠时长 ≥ `Population.dormantTtlHours`（`:182` 默认 8；沙盒 `ALife.Population_DormantTtlHours` 默认 8，`sandbox-options.txt:381-385`）→ `Registry.remove(uid, revision, "dormant_ttl")`，**记录彻底消失，装备、名字全丢**。
2. **dehydrate（不掉记录，只是休眠）**：`SpawnService.dehydrate`（`:300-310`）被 `adminPersistent`（`memory.admin.persistent == true`）挡住并返回 `false,"actor_persistent"`；`Population.lua:519` 的 `dehydrateDistance=90` 与 `:521-526` 的 `window_edge` 都走这里。
3. **死记录裁剪**：`Registry.pruneDead`（`:328-372`）超过 `maximumDeadRecords=256`（`:9`）删最旧死记录，但**显式排除 `adminPersistent`**（`:341`）。

**白名单机制 —— 没有 `SquadLedger`/`OutpostRegistry` 级的「玩家小队」豁免，只有 memory 标记**：

```lua
-- CORE:.../World/ALifePopulation.lua:128-136
local function expendable(actor)
    local memory = actor.memory
    if type(memory) ~= "table" then return true end
    local admin = type(memory.admin) == "table" and memory.admin or nil
    return memory.persistent ~= true            -- ← 只要这一条就能免疫 TTL 回收
        and not (admin ~= nil and admin.persistent == true)   -- ← 这一条再免疫 dehydrate
        and memory.adminAnchor ~= true
        and memory.encounter == nil
end
```
→ **必须同时写 `memory.persistent = true` 和 `memory.admin = { persistent = true }`**，两者管的是不同函数。Jeem 的居民写的是 `memory.persistent, memory.jimmyPersistent = true, true` + `memory.encounter = "outpost:"..site.id`（`J:.../Residents/Server.lua:425,424`），恰好把 `expendable` 四个条件全打掉。

**额外注意**：`Population.stationed(actor)`（`:358-363`）决定它「到岗」还是「走过来」；`R.arriveClear=60` 之类的离线瞬移是 Jeem 自己的，不是 A-Life 的。

---

## 3. Jeem：招募居民的最小调用序列（重点）

### 3.1 客户端 `recruit` 完整链路

```
[客户端] 右键 NPC 周围 2 格
  Menu.lua:11  Menu.radius = 2
  :31-57  Menu.npcsNear(square)  遍历 5x5 格，读 shell modData.ProjectALifeUID（关键身份键）
  :63-64  if not J.enabled("residents") then return end
  :74     if not R.residentOf(npc.record) then
  :79     send(p, "recruit", { uid = npc.uid, baseId = base.id })
  :14-20  send(): MP 客户端 => sendClientCommand(player, J.MODULE, command, args)
                  SP/主机   => J.commands[command](player, args)  直接本地调用
[服务端] Core.lua:1316-1325  OnClientCommand 路由：module=="ProjectALifeJimmy" 才处理，pcall 包住
  Server.lua:2251-2257   J.command("recruit", ...) → R.recruit(player, args.uid, args.baseId, args.force==true)
[回包]  Server.lua:43-51  say()
      MP: J.notice → J.reply(player,"notice",{key,args}) → sendServerCommand(player,"ProjectALifeJimmy","notice",…)
      SP: player:setHaloNote(...)
  Notices.lua:7-15  客户端 OnServerCommand 收 "notice" 并本地翻译显示
```

### 3.2 `R.recruit` 的校验清单（服务端）

`J:server/.../Residents/Server.lua:566-629`，返回 `人数` 或 `nil, why`，**失败字符串**即 `why`：

| 顺序 | 检查 | 失败 why | 行号 |
|---|---|---|---|
| 1 | 功能开关 | `"off"` | :567 |
| 2 | 基地存在 | `"no_base"` | :570 |
| 3 | **权限** `canManage(base, key, faction, admin)` | `"not_yours"` | :571 |
| 4 | ActorRegistry 可用 | `"unavailable"` | :573 |
| 5 | 记录存在且非 dead | `"busy"` | :575 |
| 6 | 不是居民 | `"resident"` | :577 |
| 7 | 不是前哨驻军（`memory.outpostId`） | `"garrison"` | :578 |
| 8 | 不是来访商人 | `"trader"` | :579 |
| 9 | **声望** `R.isAlly()` | `"not_allied"` | :581 |
| 10 | **不在战斗中** `Talk.inCombat` | `"busy"` | :583 |
| 11 | **床位/上限** | `"beds_unknown"` / `"no_beds"` / `"full_cap"` / `"full"` | :587-592 |
| 12 | 小队不在迁移中 | `"moving"` | :594 |
| 13 | 基地 site 可建 | `"unavailable"`/`"no_areas"`/`"create_failed"`/`"update_failed"` | :596,369-386 |

**没有距离校验** —— `Menu.radius=2` 只是客户端「站在旁边右键」的限制，服务端 `R.recruit` 不检查玩家与 NPC 的距离。我们自己的 UI 可从任意距离调用（要在自己的 UI 里把关）。
**不存在「必须站在 NPC 旁边按 E」**：Jeem 用的是右键上下文菜单。
`force = true` **只在 `who.admin == true` 时生效**（`:580`），单机下 `J.isAdminPlayer` 恒 true（`Core.lua:916-920`）。

### 3.3 直接服务端调用：最小可行序列

```lua
-- 全在服务端（专用服 / 主机 / 单机；单机也是同一份代码路径）
local J = ProjectALifeJimmy
local B, R = J.BaseAreas, J.Residents

local who  = B.who(player)                                  -- Store.lua:761-764 → {key, faction, admin}
local mine = B.basesFor(who.key, who.faction, who.admin)    -- Store.lua:338-345
local base = mine[1]
if base == nil then                                          -- 玩家还没有基地 → 就地造一个
    base = B.createBase({ x1 = x-8, y1 = y-8, x2 = x+8, y2 = y+8, name = "Camp", role = "grounds" }, who)
    -- Store.lua:389；失败返回 nil, "too_many_bases"/"overlap..."/"no_faction"...
end
if (tonumber(base.bedsOverride) or 0) < 4 then base.bedsOverride = 4 B.transmit() end  -- 绕过床位统计

-- 声望：目标 NPC 的阵营（或其 crew）必须 friendly 以上才能非 force 收编
local n, why = R.recruit(player, uid, base.id, false)       -- Server.lua:566
if n == nil then n, why = R.recruit(player, uid, base.id, true) end   -- 仅 admin 生效
-- 成功：n = 编入的人数（整个 crew，不只是 uid 那一个！见 crewOf :499-）
-- 失败：why ∈ {off,no_base,not_yours,unavailable,busy,resident,garrison,trader,
--              not_allied,moving,beds_unknown,no_beds,full_cap,full,no_areas,create_failed}
```

**重要副作用（写代码前必须知道）**：`R.recruit` 收编的是 **`crewOf(record)` 整个小队**（`:584`），不是单个 uid。返回值 `n` 是人数。想只收一人，得先把它从原小队里摘出来（`ProjectALife.SquadLedger.remove`，见 `Server.lua:598`），或者接受「一整队」。

**声望前置的两种满足方式**（`R.isAlly` `:491-497`）：① 玩家与该 NPC `factionId` 的声望标签 == `"allied"`；② 玩家与其 `memory.groupId` 的**组点数 ≥ 50**（`R.allyGroupPoints`，`:22`）。
做法（照抄 `Grant.lua:187-259`）：`J.StandingService.addGroup(key, groupId, factionId, 400)`（`Services/Standing.lua:178`）把组点数顶到 `S.clamp = 400`（`:16`），跨过 `thresholds = {25,75,150,250}`（`:15`）全部四档 → 任何默认档位都到 `"allied"`。玩家 key 用 `J.playerKey(player)`（`Core.lua:838-846`）：MP 是用户名，**SP 是 `"sp:<n>"`**。

### 3.4 上限、沙盒选项、费用

| 沙盒项 | 默认 | 行号 | 作用 |
|---|---|---|---|
| `ALifeJimmy.Residents_Enabled` | `true` | `J/42/media/sandbox-options.txt:57-61` | `J.enabled("residents")` 的唯一依据 |
| `ALifeJimmy.Base_MaxResidents` | `12`（0..30） | `:130-134` | `R.capacity` 的硬上限 |
| `ALifeJimmy.Residents_NeedBeds` | `true` | `:112-116` | 为 true 时容量 = `min(cap, 床位数)` |
| `ALifeJimmy.Residents_Grief` | `true` | `:88-92` | 死亡哀悼/结仇 |
| `ALifeJimmy.Friendlies_Enabled` | `true` | `:256-260` | 跟随/等待/走开 指令开关 |
| `ALifeJimmy.Base_MaxPosts` | `8` | `:51-55` | 岗哨位数量（「当守卫」用） |

`R.capacity(base)`（`Server.lua:1254-1260`）：`cap = J.opt("Base_MaxResidents", 12)`；若 `Residents_NeedBeds ~= false` 则 `min(cap, R.beds(base))`，`beds` 为 nil 时返回 nil → `"beds_unknown"`。**`base.bedsOverride` 可强制绕过床位统计**（参考实现 `Grant.lua:390-393` 就是这么干的）。

**费用：Jeem 招募不收费，也没有货币字段。** 只有「声望代价」：`R.recruitCostEach, R.recruitCostMax = 3, 12`（`:562`）—— 按 3 分/人、封顶 12 分扣**玩家与该 NPC 原阵营**的声望（`J.emit("standingDeed", {points=-cost, kind="recruit"})`，`:621`）。另外 `R.stores.addSupplies(base.id, #crew * bringPerMember)`（`:616`）是**加**补给，不是扣钱。
→ **我们的经济模组必须自己扣钱**；Jeem 侧无法接入结算，也没有可绕过的货币字段。

---

## 4. 双向绑定、解除雇佣、死亡清理

### 4.1 绑定写在哪

| 方向 | 位置 | 键 | 依据 |
|---|---|---|---|
| **NPC → 玩家/基地** | NPC 的 A-Life actor 记录 `record.memory`（随 A-Life 存档持久化） | `jimmyResident = { baseId, index, since, recruitedBy, fromFaction, fromGroup }` | `retag` `Server.lua:456-459`；`info` 由 `:601-602` 构造 |
| 同上 | `memory` | `groupId = "jimmybase:<baseId>"`、`stance="garrison"`、`encounter="outpost:<siteId>"`、`outpostId`、`adminMode/behavior="guard"`、`behaviorProfile="patrol"`、`moduleOverrides` | `retag` `:424-451` |
| 同上（**跟随**） | `memory` | `jimmyOrder = { kind="follow"/"hold", player=<玩家key字符串>, untilHours, anchor, ally }` | `Friendlies.order` `Friendlies.lua:123-129`；overlay key 见 `Relay.lua:14-18` |
| **玩家 → 基地** | 不需要写在玩家身上！ | 归属靠 `base.createdBy` / `base.owner`（玩家 key 或阵营名）+ `BaseAreas.canManage` | `Store.lua:330-335` |
| 玩家 modData | — | **Jeem 不往玩家 modData 写任何东西**；声望在 `ModData["ProjectALifeJimmy.Standing"]`（`Services/Standing.lua:13,24-28`） | |

→ **对我们扩展的含义**：玩家侧「我雇了谁」的记录**不能依赖 Jeem**，必须自己在玩家 modData（或我们自己的 ModData 表）里存 `{ uid = ..., baseId = ..., mode = "follow"|"resident"|"guard" }` 列表。

### 4.2 解除雇佣

| 目标 | 函数 | 效果 | 行号 |
|---|---|---|---|
| 解散全基地居民 | `R.dismiss(player, baseId)` | `canManage` 校验后 `R.leave(base,"dismissed",nil)` | `Server.lua:784-790` |
| 解散实现 | `R.leave(base, reason, grudgeKey)` | 每人对 `free()`：清掉 23 个 `jimmy*`/stance 键、还原原阵营外观（`R.adoption.restore`）、改回 `adminMode/behavior="patrol"`、`groupId` 换成新组、`persistent=true` | `:705-719` + `free` `:656-681` |
| 只踢一人 | `R.leaveOne(player, uid)` | 返回 true 或 `nil,"not_resident"/"not_yours"/"busy"` | `:722-733` |
| 搬家 | `R.move(player, uid, toBaseId)` | | `:755-781` |
| 取消跟随/等待 | `J.Friendlies.order(player, record, "clear")`（或 `F.expire()` 到期自动清） | `F.order` kind=="clear" 时 `crew` 全写 `jimmyOrder = nil`；owner 侧 `F.sync` 把 `decisions.orders[uid]` 置 nil 并复位 state | `Friendlies.lua:100-136`、`:207-216` |
| 清 A-Life 原生 order | `DecisionLoop.orders[uid] = nil` + `Decisions.states[uid] = {kind="idle",...}` | 内部字段，**不建议直写**；优先走 `Friendlies.order(...,"clear")` | `ALifeDecisionLoop.lua:1144`（`forget` 内部）、`Friendlies.lua:209-212` |
| 清原生 order（官方入口式） | `Decisions.forget(uid, generation, reason)` | 会一并清 state/order/voice/lanes | `:1289-1293` |

### 4.3 被招募 NPC 死亡后的清理

**Jeem 没有直连 `OnZombieDead`**。它靠「每分钟扫一遍居民名单，谁不见了且 `lifecycle=="dead"` 就是死了」：
- `Grief.onDied(actor, kind, key, cause)`（`J:.../Residents/Grief.lua:39-43`）由自己的总线 `J.on("actorDied", ...)` 驱动（`:143-146`）；
- `Grief.tick` 每分钟对比 `G.known[baseId]` 快照（`:101-132`），对死者 `G.mourn`（写 `memory.jimmyGrief = {name, untilHours, killer}`）；
- 居民数归零 → `R.tick`（`Server.lua:2059-2066`）`OutpostRegistry.expire(site.id,…,"jimmy_empty")` 并清 `base.siteId`。

**我们的清理钩子**：不要依赖 `jimmyGrief`（内部实现）。可靠做法是**自己定期对雇佣名单 `ActorRegistry.read(uid)`**：`nil` 或 `lifecycle=="dead"` 即视为阵亡，从名单删除并通知玩家。与 Jeem 巡检同构，不依赖它的私有键。

---

## 5. 网络同步

**只在服务端建记录不够**。原因：

1. `ActorRegistry` / `DecisionLoop` / `SpawnService` 全在 `server/` 下，MP 客户端**没有这张表**（Jeem 自己在 `Server.lua:431` 注释："the registry is server ModData an MP client doesn't have"）。
2. A-Life 往运行 NPC 的那台客户端同步 memory 时**只同步 `PROTECTED` 白名单键**（`CORE:.../shared/ProjectALife/Core/ALifeExecutor.lua:136-160`）：`admin, persistent, encounter, outpostId, squadId, groupId, home, stance, garrisonPost, holdPost, …`。
   **`jimmyResident`、`jimmyOrder`、`jimmyTarget` 都不在白名单里** —— 这正是 Jeem 要写 `Relay` 的原因：把私有键塞进 `memory.admin.jimmy`（`admin` 是 PROTECTED，整表复制），再由客户端 `applyMirror` 后解开（`Relay.lua:14-18,30-53,83-92`，wrap 点 `:115-155`）。
   → **我们写在 `record.memory` 上的自定义键，MP 下运行该 NPC 的客户端看不到**；要么用 `memory.admin.<我们的名字>`，要么走我们自己的推送。

**服务端 → 指定玩家推送最小代码**（module 必须是**我们自己的 mod id**）：

```lua
-- 服务端
local MODULE = "bin2_npc_extension"        -- 绝不能借用 "ProjectALife"（A-Life Debug 服务领地）或 "ProjectALifeJimmy"
local function pushRoster(player, rows)
    if type(sendServerCommand) ~= "function" then return end
    sendServerCommand(player, MODULE, "roster", { list = rows })   -- rows[i] = { uid, name, mode, dead }
end
-- 客户端
if Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= "bin2_npc_extension" or command ~= "roster" then return end
        if type(args) ~= "table" or type(args.list) ~= "table" then return end
        MyMod.roster = args.list          -- 然后刷新 UI
    end)
end
```
**NPC 名字**：不要指望客户端能算。`J.nameOf(record, fallback)`（`J:shared/.../Core.lua:203-213`）读 `memory.name`/`memory.displayName`，再退到 `Catalog.npc(profileId).general.name` —— 前者在服务端 record 上，后者需要 Catalog（客户端也有 Catalog，但 record 没有）。**在推送 payload 里把名字一起发过去最稳。**

---

## 6. 存档幂等与恢复

**Jeem 的居民状态是「免费」持久化的**：`jimmyResident` 写在 A-Life actor 记录的 `memory` 里，而记录由 A-Life 自己存进 `ModData["ProjectALife.World.v1"]`（`CORE:.../Core/ALifePersistence.lua:3-12`，`Registry.persistSnapshot` `ALifeActorRegistry.lua:87-129`）。**读档后居民身份、所属 base、岗哨全部自动还原**（`R.tick` 每分钟再 `registry().update` 把 site 的 `state` 掰回 `"garrisoned"`，`Server.lua:2068-2075`）。

**Jeem 自己只存三个 ModData 键**：`BaseAreas`（`Store.lua:26`，`ModData.transmit` 同步 `:752-754`）、`Residents`（`Server.lua:798-803`，**只放 `grievances` 和 `hungrySince`，不含居民名单**）、`Missions`（`Missions.lua:40`）与 `Standing`（`Services/Standing.lua:13`）。

**不会自动恢复的**：`DecisionLoop.orders` 是纯内存（`ALifeDecisionLoop.lua:1215`），所有 `follow`/`hold` 读档即失效。Jeem 靠 `Friendlies.sync` 每秒从 `memory.jimmyOrder` 重下（`Friendlies.lua:174-218`）—— **这是我们必须模仿的模式**。

**「这个存档已经给过了」的标记习惯**（三选一，按我们的场景）：

```lua
-- 角色级（最常用；参考实现 ALifeStartWithNPC/Grant.lua:449-457, 545）
local md = player:getModData()
if md["bin2_npc_extension.granted"] == true then return true end
...
md["bin2_npc_extension.granted"] = true

-- 存档级（每档只给第一个角色）：优先用 A-Life 的 worldState，天然新档为空
ProjectALife.ActorRegistry.setWorldValue("bin2_npc_extension.save.v1", true)   -- :587-591
ProjectALife.ActorRegistry.getWorldValue("bin2_npc_extension.save.v1")         -- :583-586
-- 兜底：ModData.getOrCreate("bin2_npc_extension.Save.v1").everGranted = true
```
**幂等键**：`ActorRegistry.create` 的 `operationId` 自带幂等（`:383-389`）。因此「重进存档再造一次」不会翻倍 —— 会直接返回旧记录。**但也因此不会造新的**：想让重生玩家再拿一个 NPC，`operationId` 里必须带一个**每角色唯一**的 token，并在角色死亡时清掉该 token（否则新 operationId 对应的新记录造出来，`SpawnService.request` 会用得上；旧记录仍在 registry 里）。

---

## 7. 单人 vs 多人

- **单人下 `server/` 文件是会加载的**：PZ 的 `server/` lua 在「纯单机 / 主机 / 专用服」三种模式都加载，只在专用服的客户端不加载。Jeem 注释确认（`Core.lua:1336-1339`）。
- 权威判定：`J.isAuthority()`（`Core.lua:30-32`）= `not isClient()`；`J.isMultiplayer()`（`:789-791`）；`J.isMultiplayerClient()`（`:34-36`）。
- **单机下调用服务端函数不需要特殊处理**：`Menu.lua:14-20` 就是「MP 客户端发命令，否则直接 `J.commands[cmd](player, args)`」，照抄这个 `send()` 分发器即可。
- 我们自己的 server/ 文件要同时挂 `Events.OnServerStarted` 与 `Events.OnGameStart`（Jeem `Core.lua:1375-1377` 的做法）。
- **单机下 `J.isAdminPlayer` 恒 true**（`Core.lua:916-917`），`force=true` 永远生效 —— 单机测试很容易，**联机普通玩家会失败**，必须在专用服上验非管理员账号。

---

## 8. 兼容与探测

**判断 Jeem 是否启用（可靠写法）**：

```lua
local function jeemReady()
    local J = rawget(_G, "ProjectALifeJimmy")
    if type(J) ~= "table" then return false end
    if type(J.enabled) == "function" then
        local ok, on = pcall(J.enabled, "residents")
        if ok and on == false then return false end        -- 玩家主动关了居民功能
    end
    return type(J.Residents) == "table" and type(J.Residents.recruit) == "function"
end
```
推荐**表探测优先**（`ProjectALifeJimmy ~= nil` + 函数存在），因为 shared 文件在启动即注册（`Core.lua:6`）。
`getActivatedMods():contains("ProjectALifeJimmy")` 只能作**辅助**：A-Life 自己的读法是 `getActivatedMods():get(i)` 逐个取再 `string.gsub(id,"^\\+","")`（`CORE:.../Compat/ALifeModCompat.lua:86-100`），Jeem 也**完全没用过 `getActivatedMods`**。我们若要用，必须做同样的反斜杠剥离。

**判断 A-Life 是否启用**：`type(ProjectALife) == "table"`（Jeem 在 `Core.lua:1341-1344` 就是这个写法）。更强的判据：`type(ProjectALife.ActorRegistry) == "table" and type(ProjectALife.SpawnService.request) == "function"`（这两个是 server 文件，世界开始后才有）。

**A-Life 官方 `Compat.known` 对我们的约束**（`CORE:.../shared/ProjectALife/Compat/ALifeModCompat.lua:13-78`）：
- **里面没有 `ProjectALifeJimmy` 条目**，也没有我们 `bin2_npc_extension` 的条目 —— 我们不在它的已知名单上，**不会被它主动警告，也没有豁免**。
- `Compat.ownIds = { ProjectALifeNPCs = true, ProjectALifeReconstructed = true }`（`:112`），另有 `Compat.probePaths`（`:114-128`）与 `Compat.foreignCopies(active)`（`:185`）用来点名「自带 A-Life Lua 副本」的模组。
**红线（必须遵守）**：
1. **绝不能把 A-Life 的 lua 文件复制进我们的包**（会被 `foreignCopies` 点名，旧副本还会 shadow 新版本，实测后果见参考实现 `Grant.lua:261-300`）；
2. **命令行 module 名只能用我们自己的 mod id**。`"ProjectALife"` 是 A-Life 自己的命令通道（`ALifeStatusService.lua:162,167`、`ALifeDebugService.lua:2599,3801`、`ALifeExecutor.lua:1245`），第三方复用会撞车；`"ProjectALifeJimmy"` 同理归 Jeem。
可选：`ProjectALife.ModCompat.known["bin2_npc_extension"] = { name=…, verdict="compatible", note=… }`（沿用 `:80-84`），并可用 `Compat.isActive(id)`（`:107-109`）检测别人。

---

## 9. 稳定性评级

| 接口 | 评级 | 理由 |
|---|---|---|
| `ActorRegistry.create / read / update / remove / setWorldValue / getWorldValue` | **半稳定** | 参数表与 `nil, why` 约定稳定，但 `specification` 字段形状无正式承诺 |
| `SpawnService.request` | **半稳定** | 同上；返回的 `request.shell` 顺序被 Debug 服务依赖 |
| `DecisionLoop.setOrder` | **半稳定** | `kind` 白名单与 5 个失败串是明写的，但**只有 ModuleLeader 一个内部调用者**，非公开 API |
| `DecisionLoop.orders / states` 直写 | **内部实现细节** | 纯内存表，随时可能重构；优先走 `setOrder` / `Friendlies.order` |
| `Population.expendable` 依赖的 `memory.persistent` / `memory.admin.persistent` | **半稳定** | 是 A-Life 保护机制的唯一开关，但语义是内部命名 |
| `Registry.pruneDead` 的 `adminPersistent` 豁免 | **内部实现细节** | 只影响死记录 |
| `J.Residents.recruit / dismiss / leave / residents / residentOf / capacity` | **半稳定** | `recruit` 的返回 `人数 | nil,why` 与 15 个失败串非常稳定（测试套件依赖），但它是 Jeem 内部模块函数 |
| `R.retag` 写的 20+ 个 `jimmy*` memory 键 | **内部实现细节** | 版本一改就变；我们**只读 `R.residentOf`，绝不自己复制这套键** |
| `J.Friendlies.order / F.sync / F.maxFollowers` | **半稳定** | 「跟随我」在 Jeem 内的唯一实现，**无替代品**；`F.followSpot` 直接对冲 A-Life 的 `Movement.goalRefused`，属实现细节 |
| `J.BaseAreas.who / basesFor / createBase / canManage / transmit / baseAt` | **半稳定** | 语义清晰、被全 Jeem 复用；`createBase` 的 `args` 形状未文档化 |
| `J.BaseAreas.bedsOverride` | **内部实现细节** | 绕过床位统计的侧门，字段名无语义保证 |
| `J.StandingService.set / addGroup / groupPoints / labelFor` | **半稳定** | 数据形状公开（`players[key].factions/groups`） |
| `J.StandingService.data()` 直写 / `Features/Standing/F.apply` 写回 A-Life 声望 | **内部实现细节** | 复制了 A-Life 私有声望 schema（`Standing.lua:123-140`） |
| `J.playerKey / username / isAdminPlayer / enabled / opt / notice / reply / aiUids / nameOf` | **稳定接口** | 纯读取 + 网络原语，被 Jeem 全量复用 |
| `ModData.transmit`（BaseAreas 那类同步） | **稳定接口** | PZ 引擎原语 |
| `sendServerCommand(player, 我们自己的modId, cmd, args)` | **稳定接口** | 引擎原语 |

**没有替代品、必须用的**：`ActorRegistry.create`、`SpawnService.request`、`DecisionLoop.setOrder`（原生跟随）、`J.Residents.recruit`（Jeem 居民）、`J.Friendlies.order`（Jeem 跟随）。
**有更稳替代路径的**：①「解散」不要走 `R.leave`，走 `R.dismiss`/`R.leaveOne`；②「取消跟随」走 `Friendlies.order(...,"clear")` 而不是直删 `DecisionLoop.orders`；③「拉同盟」优先 `StandingService.addGroup`（自身数据），而不是直写 A-Life 声望表；④「知道 Jeem 有没有启用」优先读 `ProjectALifeJimmy` 表，而不是 `getActivatedMods`。

---

## 10. 风险清单

1. **版本错配（最高）**：Jeem `versionMin=42.20.0` < A-Life `versionMin=42.21.0`（`J/42/mod.info:5` vs `CORE/42.20/mod.info:5`）；Jeem 写于 A-Life 1.3.14，当前 1.3.15。`R.recruit` 的 15 个失败串只要有一个改动，我们的 UI 文案就会露出英文 key。
2. **私有存档形状**：`memory.jimmyResident.*`、`memory.admin.jimmy.*`（Relay）都是 Jeem 私有 schema，A-Life 一次 memory 重构就会静默失效。**我们只读不写**。
3. **人口回收（会真丢人）**：不写 `memory.persistent = true` + `memory.admin.persistent = true`，离玩家 >60 格且 8 小时后记录被 `"dormant_ttl"` **物理删除**（`ALifePopulation.lua:426-434`）。写了这两个标记的副作用：死记录被 `pruneDead` 永久豁免，registry 只增不减。
4. **读档丢命令**：`DecisionLoop.orders` 不持久化（`:1215`）。任何「跟随我」必须在 `OnGameStart`/每次进档后重下，且用 Jeem 那种「内存 → A-Life order」的同步循环（`Friendlies.sync`），不要一次性下完就忘。
5. **人口天花板挡路**：`maximumHostileActors` 默认 32（`ALifeSettings.lua:48`）。密集基地 + 我们的雇佣兵会把新 spawn 全挡住（`ALifePopulation.lua:481-485`），表现为「花钱了但人出不来」。必须在 UI 上做失败分支（`SpawnService.request` 返回 nil 时回滚我们已扣的钱，并把 `Registry.remove(uid,...,"rejected")` 清干净，条件：`lifecycle=="dormant"`）。
6. **`orders` overlay 缺失**：`setOrder` 返回 true 但 NPC 毫无反应。必须检查目标 NPC 的 `behaviorProfile.overlays.orders`，或给它 `memory.moduleOverrides.orders = "on"`。
7. **抢单槽**：`DecisionLoop.orders[uid]` 是**一人一槽**。squad leader 的 `source="leader"` 与我们的 `source="player"` 会互相顶掉；`Travel.lua:18-25` 只在 `source=="leader"` 且 `stance=="blockade"` 时自动清槽。**同一 NPC 不要既下 follow 又当居民守卫**（`retag` 会清 `jimmyOrder`，`Server.lua:453`）。
8. **`R.recruit` 收编整队**：返回值是 crew 人数而不是 1（`:584`），会意外搬进一整队，并按人数扣声望（封顶 12）。
9. **多人不同步**：自定义 memory 键不在 `Executor.PROTECTED`（`ALifeExecutor.lua:136-160`），不会同步到运行该 NPC 的客户端；「雇了谁」必须自己推送，不能靠客户端读 registry。
10. **`force=true` 的权限陷阱**：`force` 仅对 `who.admin == true` 生效（`Server.lua:580`）；单机恒 admin 会掩盖联机失败，必须在专用服上跑非管理员账号。
11. **Jeem 缺失时的沉默降级**：`J.enabled("residents")` 返回 false 而不报错，不写日志玩家只会看到「点了没反应」。

---

## 最小可行代码骨架

```lua
-- ===== shared/MyRecruit/Api.lua（shared：两分支共用，探测 + 小工具）=====
MyRecruit = MyRecruit or {}
local M = MyRecruit
M.MODULE = "bin2_npc_extension"        -- 必须是自己的 mod id
M.KEY_HIRED = "bin2_npc_extension.hired"   -- 玩家 modData 键

function M.jeem()                       -- 有 Jeem 才返回表
    local J = rawget(_G, "ProjectALifeJimmy")
    if type(J) ~= "table" then return nil end
    if type(J.Residents) ~= "table" or type(J.Residents.recruit) ~= "function" then return nil end
    if type(J.enabled) == "function" then
        local ok, on = pcall(J.enabled, "residents")
        if ok and on ~= true then return nil end
    end
    return J
end

function M.alife()
    local A = rawget(_G, "ProjectALife")
    if type(A) ~= "table" then return nil end
    if type(A.ActorRegistry) ~= "table" or type(A.SpawnService) ~= "table" then return nil end
    return A
end

function M.aiUids()                     -- 哪些 NPC 的 AI 跑在本机（照 Friendlies:179）
    local J = M.jeem()
    if J and type(J.aiUids) == "function" then return J.aiUids() end
    local A = M.alife()
    local out, wd = {}, A and A.Watchdog
    for uid in pairs((wd and wd.bindings) or {}) do out[#out + 1] = uid end
    table.sort(out)
    return out
end

-- ===== server/MyRecruit/Hire.lua（仅服务端）=====
require "MyRecruit/Api"
local M = MyRecruit
require "MyRecruit/Api"

-- 1) 造一名友方 NPC（两分支共用的「造人」步骤）
local function spawnOne(player, opId, factionId, profileId, x, y, z)
    local A = M.alife()
    if A == nil then return nil, "alife_absent" end
    local fingerprint = M.MODULE .. ":v1"
    local actor, err = A.ActorRegistry.create({
        operationId = opId, fingerprint = fingerprint,
        profileId = profileId, factionId = factionId,
        worldPosition = { x = x, y = y, z = z },
        activity = "idle", intent = "hold",
        memory = {
            spawnStance = "friendly",              -- Relations.baselineStance 第一优先级
            persistent  = true,                    -- 免疫 Population 的 dormant_ttl 回收
            admin       = { persistent = true },    -- 免疫 SpawnService.dehydrate
            home        = { x = x, y = y, z = z },
            groupId     = "bin2hire:" .. tostring(opId),
        },
    })
    if actor == nil then return nil, tostring(err) end
    local req, reqErr = A.SpawnService.request(actor.uid, opId .. ":spawn", fingerprint .. ":spawn", 2500)
    if req == nil then                           -- 回滚：只有 dormant 才允许 remove
        local cur = A.ActorRegistry.read(actor.uid)
        if cur and cur.lifecycle == "dormant" then
            pcall(A.ActorRegistry.remove, cur.uid, cur.revision, "bin2hire_rejected")
        end
        return nil, tostring(reqErr)
    end
    return actor.uid, nil                         -- 此时 lifecycle == "spawning"
end

-- 2) 等 active 后下命令（每 tick 推进；不要一 request 就 setOrder）
M.pending = M.pending or {}
function M.tickPending()
    local A = M.alife()
    if A == nil then return end
    for uid, job in pairs(M.pending) do
        job.tries = (job.tries or 0) + 1
        local rec = A.ActorRegistry.read(uid)
        if rec == nil or rec.lifecycle == "dead" or job.tries > 600 then
            M.pending[uid] = nil
            if job.onFail then job.onFail() end
        elseif rec.lifecycle == "active" then
            M.pending[uid] = nil
            M.assign(job.player, uid, rec, job.mode)
        end
    end
end

-- 3) 分支派发：有 Jeem 走 Jeem，没 Jeem 走原生
function M.assign(player, uid, record, mode)
    local J = M.jeem()
    local A = M.alife()

    if mode == "resident" or mode == "guard" then
        if J == nil then mode = "follow" end          -- 降级：没有 Jeem 就当跟随
    end

    if mode == "follow" then
        if J ~= nil and type(J.Friendlies) == "table"
                and type(J.Friendlies.order) == "function" then
            -- Jeem 路径：写 memory.jimmyOrder，由 owner 机器同步成 A-Life order（推荐）
            local ok, n = J.Friendlies.order(player, record, "follow")
            if ok then return true end
            -- 声望不够会返回 false,"not_friendly" —— 落到原生路径
        end
        -- 原生路径
        if A.DecisionLoop == nil or type(A.DecisionLoop.setOrder) ~= "function" then return false end
        local ok, accepted = pcall(A.DecisionLoop.setOrder, uid, record.generation, {
            kind = "follow", player = player, source = "player",   -- source 非 "leader" => 归一化成 "player"
        })
        return ok and accepted == true
    end

    if J ~= nil then                                   -- resident / guard
        local B, R = J.BaseAreas, J.Residents
        local who  = B.who(player)
        local mine = B.basesFor(who.key, who.faction, who.admin)
        local base = mine[1]
        if base == nil then
            local px, py = player:getX(), player:getY()
            base = B.createBase({ x1 = px - 8, y1 = py - 8, x2 = px + 8, y2 = py + 8,
                name = "Hired Camp", role = "grounds" }, who)
        end
        if base == nil then return false end
        if (tonumber(base.bedsOverride) or 0) < 4 then base.bedsOverride = 4 pcall(B.transmit) end
        -- 声望垫到 allied（组点数 400 > 阈值 250）
        local S = J.StandingService
        if S and type(S.addGroup) == "function" and record.memory and record.memory.groupId then
            pcall(S.addGroup, who.key, record.memory.groupId, record.factionId, tonumber(S.clamp) or 400)
        end
        local n, why = R.recruit(player, uid, base.id, false)
        if n == nil then n, why = R.recruit(player, uid, base.id, true) end   -- force 仅 admin 生效
        if n == nil then return false, why end
        if mode == "guard" and type(R.reassign) == "function" then
            base.posts = base.posts or {}
            base.posts[#base.posts + 1] = { x = math.floor(player:getX()), y = math.floor(player:getY()), z = 0 }
            pcall(B.transmit)
            pcall(R.reassign, base.id)
        end
        return true, n
    end

    return false, "jeem_absent"
end

-- 4) 解散
function M.dismiss(player, uidOrBaseId)
    local J = M.jeem()
    local A = M.alife()
    if J ~= nil then
        local R = J.Residents
        if R.residentOf and R.residentOf(A.ActorRegistry.read(uidOrBaseId)) then
            return R.leaveOne(player, uidOrBaseId)
        end
        if J.Friendlies and J.Friendlies.order then
            local rec = A.ActorRegistry.read(uidOrBaseId)
            if rec then return J.Friendlies.order(player, rec, "clear") end
        end
    end
    local rec = A and A.ActorRegistry.read(uidOrBaseId)          -- 无 Jeem：清原生 order
    if rec and A.DecisionLoop and A.DecisionLoop.orders then
        A.DecisionLoop.orders[uidOrBaseId] = nil
        if A.DecisionLoop.states then
            A.DecisionLoop.states[uidOrBaseId] = { kind = "idle", intent = "order_released", cooldownUntilMs = 0 }
        end
        return true
    end
    return false, "not_found"
end

-- 5) 每档/每会话恢复 follow（orders 不持久化，必须重下）
function M.restore(player)
    local md = player:getModData()
    local hired = type(md[M.KEY_HIRED]) == "table" and md[M.KEY_HIRED] or {}
    local A = M.alife()
    if A == nil then return end
    for uid, job in pairs(hired) do
        local rec = A.ActorRegistry.read(uid)
        if rec == nil or rec.lifecycle == "dead" then
            hired[uid] = nil                              -- 阵亡清理
        elseif job.mode == "follow" and rec.lifecycle == "active" then
            M.assign(player, uid, rec, "follow")           -- 幂等重下
        end
    end
end

if Events and Events.OnTick then Events.OnTick.Add(function() pcall(M.tickPending) end) end
if Events and Events.EveryOneMinute then
    Events.EveryOneMinute.Add(function()
        for i = 0, (getNumActivePlayers and getNumActivePlayers() or 1) - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then pcall(M.restore, p) end
        end
    end)
end
return M
```

---

## 未验证 / 需进游戏确认

1. **`R.recruit` 对 `force=false` 的成功率**：`R.isAlly` 只认 `factionId` 的 `"allied"` 标签或 `groupId` 的 ≥50 组点数（`Server.lua:491-497`）。`StandingService.addGroup(key, groupId, factionId, 400)` 是否真能把 `groupPoints` 顶到 400（`Services/Standing.lua:178-190` 的 clamp / poolShare 语义未逐行验证），必须在游戏里打日志确认 `S.groupPoints(key, groupId)` 的返回值。
2. **`R.recruit` 的床位判定**：`R.beds(base)`（`Server.lua:1104`）返回 nil 时直接 `"beds_unknown"`（`:1258`）。`base.bedsOverride` 的**确切读取优先级**未逐行确认（参考实现 `Grant.lua:390` 断言读的是它，但 `R.beds` / `R.keptBeds` / `R.countBeds` 三者的优先级要实测）。
3. **`F.followSpot` 对冲 `Movement.goalRefused` 是否必需**：`Friendlies.lua:267-297` 是在 A-Life 1.3.14 上打的补丁。1.3.15 是否已修未知 —— 若已修，这段 wrap 会继续吃掉新逻辑（Jeem 自己的 `AlifeFixes` 就有这个「过期」问题）。**我们不要 wrap，只调用 `Friendlies.order`。**
4. **`memory.admin.persistent = true` 的副作用**：除免疫 dehydrate/TTL/pruneDead 之外是否还有别的读取点（`adminHeld` `ALifePopulation.lua:251-253`、`edgeParks` `:270-280` 已确认），需要一份 grep 复盘。
5. **`setOrder` 的 `untilMs` 单位**：`:1266` 只做 `tonumber`，`Travel.lua:27` 用 `context.now >= order.untilMs` 比较。`context.now` 的量级（ms 还是 game-hours）需实测；Jeem `Friendlies.sync:194` 传的是 `nowMs + (untilHours-hours)*3600000`，即 ms。
6. **客户端选中 NPC 的通道**：`Menu.npcsNear`（`Menu.lua:47`）从 shell modData 读 `ProjectALifeUID`。我们若走列表选中，需要另一条「玩家选了哪个 NPC」的通道。
