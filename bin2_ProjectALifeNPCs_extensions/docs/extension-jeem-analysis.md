# 标杆扩展 ①：Project A-Life - Jeem Extension 逆向分析

> 对象：工坊 `3806944055` / Mod ID `ProjectALifeJimmy` / 作者 jeemlettuce / v0.4.6 / 10,743 订阅
> 依赖：`require=\ProjectALifeNPCs`、`loadModAfter=\ProjectALifeNPCs`
> 分析基准：A-Life 核心 1.3.15（工坊 3803984183）；全程只读
> 路径约定：**J** = `.../108600/3806944055/mods/ProjectALifeJimmy`，**A** = `.../108600/3803984183/mods/ProjectALifeNPCs`

---

## 1. 打包结构

- 布局 `J/{42/, common/}`；版本目录名 **`42`**（A-Life 用 `42.20`）。
  `common/` 只有一个 0 字节 `.gitkeep` —— 对比 A-Life 在 `common/alife_runtime/catalog/` 放
  `faction_registry.alife`(315 KB) 与 `npc_profiles.alife`(3.8 MB)。
  **J 不发布任何 `.alife`**（这是它和 Aftermath 的根本区别）。
- `42/mod.info:1-9` 全字段：`name` / `id=ProjectALifeJimmy` / `author=jeemlettuce` / `modversion=0.4.6` /
  `versionMin=42.20.0` / `require=\ProjectALifeNPCs` / `loadModAfter=\ProjectALifeNPCs` / `poster=poster.png` / `description`。
  **无 `incompatible`、无 `icon`、无 `pack`**；`require` 值带反斜杠前缀（PZ 转义写法）。
  注意：**J 的 `versionMin`(42.20.0) 比 A-Life 的 `42.21.0` 还低一档**。
- 清单：141 文件 / 3.1 MB / **132 个 Lua = 52,591 行**（shared 43 文件 16.4k、client 41 文件 17.3k、server 48 文件 18.9k）。
- assets 极少：`42/poster.png`(1.8 KB)、`42/media/ui/ALifeJimmy/{Bases_64,Faction_64}.png`；
  **无 scripts / 无模型 / 无音效**。文本面：`Translate/EN/{IG_UI,ContextMenu,Sandbox}.json` + `42/media/sandbox-options.txt`。

---

## 2. 实现了什么 / 存在哪里

| 域 | 主要文件 | 数据结构 | 存储 |
| --- | --- | --- | --- |
| 基地 | `shared/.../Features/BaseAreas/{Store,Protection}.lua`、`client/.../BaseAreas/{Menu,Manager,SelectTool}.lua` | `bases[id]={id,name,ownerKind,owner,createdBy,posts,stores,storesV}`、`areas[]={id,baseId,role,x1..z}`（`Store.lua:2-9`） | ModData `ProjectALifeJimmy.BaseAreas`（`Store.lua:26,101-110`），`ModData.transmit`（`Store.lua:752`） |
| 居民 | `server/.../Residents/{Server,Manage,Adopt,Missions,Tasks,Schedule,Stores,News,Bodies,Sweep,Grief,FactionPage}.lua` | 复用 A-Life 记录本体（同 uid、同装备），重贴为隐藏前哨 `jimmy_player_base` 的驻军（`Server.lua:1-16`） | `ProjectALifeJimmy.Residents`（`Server.lua:799`）、`.ResidentStores`、`.Missions` |
| 任务 | `server/.../Residents/Missions.lua` | `data.list[id]`（`Missions.lua:91-97`）；类型 scavenge/patrol/hunt/trade/patrolArea/escort；离屏时快照成 A-Life 小队 | `ProjectALifeJimmy.Missions`（`Missions.lua:40`） |
| 声望 | `server/.../Features/Standing/Standing.lua` + `Services/Standing.lua` + `Grudges`/`CrewStanding` | `players[key]={factions,groups,events}`（`Services/Standing.lua:1-7,13`），label 阶梯 hostile/careful/neutral/friendly/allied | 自存 `ProjectALifeJimmy.Standing`，**并写回 A-Life 的声望表**（`Standing.lua:70-74`），cause=`jimmy_standing`（`Standing.lua:38`） |

---

## 3. 如何挂进 A-Life

### 3.1 引用的公开表（50+ 个）

`ActorRegistry`(125 处)、`DecisionLoop`(45)、`ObstacleTraversal`(40)、`Catalog`(35)、`Relations`(32)、
`Watchdog`、`OutpostRegistry`、`Talk`、`SquadLedger`、`Population`、`Speech`、`Reputation`、`Movement`、
`Executor`、`Perception`、`ModuleRegistry`、`ProfileHydrator`、`Entrances`、`OutpostBuilder`、`Persistence` …

### 3.2 挂接方式：**既有 monkey patch，也有纯调用**

**136 处 `J.wrap`，覆盖 49 个 A-Life 表、约 110 个函数**。机制（`Core.lua:1043-1056`）：

```lua
function J.wrap(feature, ownerPath, key, make)
    local id = feature .. ":" .. ownerPath .. "." .. key
    if J.wrapped[id] then return true end          -- 每 feature+路径幂等
    local owner = J.resolve(ownerPath)             -- "ProjectALife.X" 逐段取 _G
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then
        J.status[feature] = "missing " .. id       -- 缺函数=禁用该功能，不抛错
        return false
    end
    local original = owner[key]
    owner[key] = make(original)                    -- 存原函数再替换（可链式叠加）
    J.wrapped[id] = original
    return true
end
```

最重的 patch：`ObstacleTraversal` **17 个**、`Relations` 7、`Talk`/`Reputation`/`RenderProtocol`/
`ProfileHydrator`/`Movement`/`Executor`/`AIFence` 各 5。

典型手法：
- `Core.lua:111-127` 包住 `Talk.respond`；
- `Promotion.lua:238-245` 包 `Reputation.onPlayerDamagedActor/onPlayerKilledActor/ModuleRobbery.finish`；
- `AlifeFixes.lua:885-938` **修 A-Life 自身的 bug**；
- `Core.lua:1181-1197` **抢占 `Relations.adapters.reputation` 单槽**，并把自己垫在 `previous` 之前。

### 3.3 事件使用

核心路由 `OnClientCommand`（`Core.lua:1316-1325`）；另有 `OnServerCommand`×7、`OnTick`×33、
`EveryOneMinute`×19、`EveryTenMinutes`×14、`OnGameStart`×13、`OnInitGlobalModData`×11、`OnServerStarted`×4、
`OnReceiveGlobalModData`×3、`OnFillWorldObjectContextMenu`×3，以及 `OnZombieDead`/`OnZombieCreate`/
`OnHitZombie`/`LoadGridsquare`/`OnFillContainer`/`OnKeyStartPressed` 各 1。
**刻意不用 `OnZombieUpdate`/`OnPlayerUpdate`**（把每帧热路径让给 A-Life 自己）。

### 3.4 复用 A-Life 数据的方式

不直接读 `.alife`，而走公开读取器 —— `ProjectALife.Catalog.faction/npc`（`A/.../Records/ALifeCatalog.lua:201-208`，
其 `current` 由 `alife_runtime/catalog/*.alife` 解析）。
Creator 商店用 `ProjectALife.CustomFactions` + `CustomFactionAuthority`、
`ProjectALife.CustomProfiles` + `CustomProfileAuthority`（`Adopt.lua:57-67,71-85`），
自建 id 前缀 `jimmy_pf_`/`jimmy_pp_`（`Adopt.lua:51-54`）。
**未见 `ALIFEPACK1-…` 分享码读写**。

> 命名对照：分析中提到的 `ALifeCatalog`/`ALifeCustomFactions` 是**文件名**，
> 对应的**表名**是 `ProjectALife.Catalog` / `ProjectALife.CustomFactions`。

### 3.5 身份识别

**不写** `ProjectALifeOwned`/`ProjectALifeActor`，只**读** `data.ProjectALifeUID` 或
`GetVariable("ALifeUID")`（`Core.lua:668-671`）。
自己往 A-Life NPC 的 modData 打 **50+ 个小写 `jimmy*` 键**：
`jimmySafety`、`jimmyResident`、`jimmyWeapon`、`jimmyMission`、`jimmyOrder`、`jimmySurrender`、
`jimmyWounds`、`jimmyLimp`、`jimmyAimFactors` …

---

## 4. 如何避免冲突（工程化程度很高，值得抄）

- **命名空间**：表 `ProjectALifeJimmy`；ModData 全前缀 `ProjectALifeJimmy.*`（20 个 TAG）；
  NPC 键 `jimmy*`；阵营 id `jimmy_pf_/jimmy_pp_`；文本键 `IGUI_ALJ_`/`ContextMenu_ALJ_`；
  命令 module `"ProjectALifeJimmy"`（`Core.lua:11`）；日志前缀 `[ALIFE-JIMMY]`（`Core.lua:10`）。
- **存在性探测**：`type(ProjectALife) ~= "table"` 直接退出（`Core.lua:1340-1344`）；
  wrap 前必须类型命中；`J.call` 用 pcall 包所有对象方法（`Core.lua:250-253`）；
  `J.feature{upstream=}` 预留"上游已实现则自动让位"（`Core.lua:1077-1085`，当前无人使用）。
- **幂等**：`J.wrapped[id]`（`Core.lua:1044`）、installer 的 `entry.done`、
  `J.commandRouterAdded`（`Core.lua:1316`）、`adapters.jimmyChain`（`Core.lua:1185`）。
- **降级与重试**：installer 全程 pcall，`EveryOneMinute` **每游戏分钟重试未挂上的钩子**（`Core.lua:1380-1384`）。
  未用 `getActivatedMods()`；只用 `getModFileReader` 在专用服务器补读自带英文文本（`Core.lua:1226-1252`）。

---

## 5. 多人

server 管世界状态、shared 管 AI 决策、client 管 UI 与本机模拟 NPC；
权限用 `J.isAuthority()`/`J.isMultiplayerClient()`（`Core.lua:30-36`）。
module 恒为 `"ProjectALifeJimmy"`，**cmd 约 34 个**：
`base`、`recruit`、`dismissResidents`、`missionStart`、`missionRecall`、`residentRoutine`、
`factionAction`、`factionReport`、`giftGive`、`tradeDo`、`npcInjured`、`npcTreated`、`npcSafety`、
`intimidate`、`emote`、`hitZombie`、`status`、`diag`、`selftest_*` 等。
服务端→客户端 `sendServerCommand(player, J.MODULE, cmd, args)`（`Core.lua:1310-1314`），
全局 ModData `ModData.transmit(KEY)`。

---

## 6. 自己的配置与存档

- **沙盒选项**：`42/media/sandbox-options.txt` 头 `VERSION = 1`，**134 个 `option ALifeJimmy.*`**，
  分页 `ProjectALifeJimmy_1People … 5Behaviour`；读取 `SandboxVars.ALifeJimmy`（`Core.lua:21-27`）。
- **ModData**：20 个独立 TAG，**无统一 schema 号**，靠就地迁移：
  `storesV`、`area.roomEdge`、旧 `area→base` 升级（`Store.lua:44,73-92`）。
- **文件读写**：不写任何自己的文件；只读自己 mod 目录的 JSON
  （`getModFileReader(J.MODULE, "42/media/lua/shared/Translate/EN/IG_UI.json")`）。

---

## 7. 脆弱点清单（**这是全篇最有价值的部分**）

| # | 脆弱点 | 说明 |
| --- | --- | --- |
| 1 | **直接写 A-Life 声望存档的内部形状** | `store.players[key][factionId]={status,cause,atHours}` + `reputation.dirty` + `reputation.sync(player)`（`Standing.lua:70-74,110-140`），字段一改即静默失效 |
| 2 | **硬编码存档 TAG** | `ModData.getOrCreate("ProjectALife.Reputation.v1")`（`Standing.lua:570`），A-Life 改 TAG 即断 |
| 3 | **抢适配器单槽** | `Relations.adapters.reputation` 是"仅一个函数"的槽（`Core.lua:1172-1197`），与任何第三方扩展互斥 |
| 4 | **决策模块私有契约** | `evaluate` 签名、`kind/priority/defaultEnabled` 含义、`BehaviorProfiles.definitions[i].overlays`/`universalOverlays` 被直接改写（`Core.lua:1142-1170`） |
| 5 | **大量未文档化函数被包** | `ObstacleTraversal.*`(17)、`Entrances.openings`、`OutpostBuilder.execute/repairOpenings/barricadeWindow`、`OfflineCombat.apply`、`ModuleCareful.onHitByPlayer/writeTurned`、`ModuleRobbery.finish`、`SquadLedger.requestReinforcement`、`ProfileHydrator.plan/seasonalDress`、`Executor.order/applyReport/auditOwner`、`Watchdog.bindings` |
| 6 | **依赖行为细节而非接口** | `DecisionLoop.followGap 1.8 / followHold 2.2` 的补偿（`Core.lua:129-176`）、`Population.windowBoundsAt`、`Settings.current`、`BehaviorSettings.movement` 字段名 |
| 7 | **`AlifeFixes` 本身会过期** | 它修的是特定版本的 A-Life bug；上游修好后这些 wrap 会继续吃掉新逻辑。作者在 `AlifeFixes.lua:1-3` 注明"用 `scripts/check-alife.sh` 复查"，但**该脚本未随包发布** |
| 8 | **字符串格式耦合** | Creator 回写的 `"0.480,0.310,0.150"` 发色被当特征匹配（`Adopt.lua:227`） |
| 9 | **版本错配** | 写于 A-Life 1.3.14，实际已 1.3.15；J 的 `versionMin` 还低于 A 的 |

---

## 8. 写 A-Life 扩展的最小可行模板（照 J 的真实做法）

### 目录

```
MyExt/
├── 42/
│   ├── mod.info
│   ├── media/lua/shared/MyExt/Core.lua
│   ├── media/lua/server/MyExt/Feature.lua
│   ├── media/lua/shared/Translate/EN/IG_UI.json
│   └── media/sandbox-options.txt
└── common/.gitkeep          # 要发布 .alife 数据时改放 common/alife_runtime/catalog/
```

### `mod.info`

```ini
name=My A-Life Extension
id=MyExt
modversion=0.1.0
versionMin=42.20.0
require=\ProjectALifeNPCs
loadModAfter=\ProjectALifeNPCs
```

### 引导与软挂接（`media/lua/shared/MyExt/Core.lua`）

```lua
MyExt = MyExt or {}; local J = MyExt
J.MODULE, J.installers, J.wrapped, J.status = "MyExt", {}, {}, {}

function J.resolve(path)
    local node = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

function J.wrap(feature, ownerPath, key, make)
    local id = feature .. ":" .. ownerPath .. "." .. key
    if J.wrapped[id] then return true end
    local owner = J.resolve(ownerPath)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then
        J.status[feature] = "missing " .. id; return false
    end
    J.wrapped[id] = owner[key]
    owner[key] = make(owner[key])
    return true
end

function J.feature(id, install) J.installers[#J.installers + 1] = { id = id, fn = install } end

local function installAll()
    if type(ProjectALife) ~= "table" then return print("[MYEXT] A-Life absent") end
    for _, e in ipairs(J.installers) do
        if not e.done then
            local ok, err = pcall(e.fn)
            if ok and J.status[e.id] == nil then e.done, J.status[e.id] = true, "ok"
            else J.status[e.id] = J.status[e.id] or ("error " .. tostring(err)) end
        end
    end
end
J.installAll = installAll
if Events.OnServerStarted then Events.OnServerStarted.Add(installAll) end
if Events.OnGameStart then Events.OnGameStart.Add(installAll) end
if Events.EveryOneMinute then Events.EveryOneMinute.Add(installAll) end
return J
```

### 三个真实扩展点（`media/lua/server/MyExt/Feature.lua`）

```lua
require "MyExt/Core"
local J = MyExt

J.feature("greet", function()
    -- 扩展点 A：A-Life 官方决策模块注册表
    local reg = ProjectALife and ProjectALife.ModuleRegistry
    if reg and type(reg.register) == "function" then
        pcall(reg.register, { id = "myext_greet", kind = "upkeep", priority = 20, defaultEnabled = true,
            evaluate = function(actor, ctx) return nil end })
        for _, p in ipairs(ProjectALife.BehaviorProfiles.definitions or {}) do
            if type(p.overlays) == "table" then p.overlays.myext_greet = true end
        end
    end
    -- 扩展点 B：包住公开函数（存原函数再替换，可链式）
    J.wrap("greet", "ProjectALife.Talk", "respond", function(original)
        return function(player, listener, text, now, choice, ...)
            if text == "hello" then return "Hello yourself.", "answered" end
            return original(player, listener, text, now, choice, ...)
        end
    end)
    -- 扩展点 C：往共享的对话菜单加选项
    local intents = ProjectALife and ProjectALife.TalkIntents
    if type(intents) == "table" and type(intents.choices) == "table" then
        table.insert(intents.choices, { id = "myext_hi", text = "IGUI_MyExt_Hi" })
    end
end)
```

---

## 9. 稳定性评级

| 挂接点 | 评级 | 依据 |
| --- | --- | --- |
| `ModuleRegistry.register` + `BehaviorProfiles.overlays` | **【稳定接口】** | A-Life 自带注册表（`A/.../Behaviours/ALifeModuleRegistry.lua:13`），J 以 `pcall` 注册；唯一风险是表形状 |
| `Catalog.faction/npc/current`、`Catalog.load/reset` | **【稳定接口】** | `A/.../Records/ALifeCatalog.lua:89-234`，命名即公开读取器 |
| `CustomFactions.serializeFactions` / `CustomProfiles.save/saveMany`、`CustomProfileAuthority.upsert/replace` | **【稳定接口】** | Creator 对外入口（`ALifeCustomFactions.lua:161-171`） |
| `TalkIntents.choices` 插入 | **【稳定接口】** | A-Life 自己在客户端/服务端都遍历该表（`ALifeTalkMenu.lua:129`、`ALifeTalk.lua:771`） |
| `Relations.adapters.*` 槽位 | 【半稳定】 | 槽是官方设计，但"只能一个函数"被 J 用链式抢占 |
| `Reputation.TAG`、`Reputation.dirty`、`Reputation.sync` | 【半稳定】 | 字段公开但存档内容非接口 |
| `Reputation.onPlayerDamagedActor/onPlayerKilledActor/escalate`、`Talk.respond/onHelped/observations/varsFor`、`DecisionLoop.think/followTarget`、`Movement.begin/adminDestination/goalRefused`、`ActorRegistry.read/update/each`、`OutpostRegistry.create/count`、`Population.stationed/restoresInPlace`、`RenderProtocol.tick/memoryFor/retireOutOfSeason`、`ProfileHydrator.plan/seasonalDress`、`Settings.current`、`BehaviorSettings.movement` | 【半稳定】 | 被 J 依赖了返回次序/参数表，无正式承诺 |
| `store.players[key][factionId]` 直接写入、`reputation.sync(player)` 手动触发、`"ProjectALife.Reputation.v1"` 硬编码 | **【内部实现细节】** | 复制了 A-Life 私有存档 schema |
| `ObstacleTraversal.*`(17)、`Entrances.openings`、`OutpostBuilder.execute/repairOpenings/barricadeWindow`、`OfflineCombat.apply`、`ModuleRobbery.finish`、`ModuleCareful.onHitByPlayer/writeTurned`、`SquadLedger.requestReinforcement`、`Executor.order/applyReport/auditOwner`、`Watchdog.bindings`、`Population.windowBoundsAt` | **【内部实现细节】** | 名字带内部语义，随 A-Life 重构最易崩；A-Life 一升级这些 wrap 会静默走 `missing` 分支 |
| `followGap 1.8 / followHold 2.2` 补偿逻辑 | **【内部实现细节】** | 直接对冲 A-Life 走位常量，常量一变行为退化 |

---

## 10. 结论

Jeem Extension 的**工程化程度很高**（命名空间、幂等 wrap、installer 每分钟重试、逐功能开关、
预留给上游的 `upstream=` 字段），这些都值得模仿。

但它把 A-Life 当成**"可 patch 的源码"**而不是"稳定 API"：
**136 个挂接点里过半是内部实现细节**。

> **给我们的策略**：新扩展只应依赖上表的**四项【稳定接口】**
> （`ModuleRegistry`、`Catalog` 读取器、`CustomFactions`/`CustomProfileAuthority`、`TalkIntents.choices`），
> 其余一律用"存在性探测 + `pcall` + 缺失即禁用"的**软挂接**，绝不去复制 A-Life 的私有存档形状。
