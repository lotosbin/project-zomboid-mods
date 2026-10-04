# A-Life 对外扩展点清单（v1.3.15 实测）

> 对象：Project A-Life 核心（工坊 3803984183 / `ProjectALifeNPCs` / v1.3.15 / `versionMin=42.21.0`）
> 路径缩写：`L = $CORE/42.20/media/lua/`，`$CORE = .../mods/ProjectALifeNPCs`
> 结论来源：全项目 grep + 逐函数 read（只读分析）
>
> **一句话总结**：A-Life **没有** `ProjectALife.Extensions` / `addProvider` / `contribute` / `Compat.register`。
> 真正对外开放的注册器只有 **`ModuleRegistry.register`** 与 **6 个 `Voice*Register` hook**；
> 其余全是**只读观测面**或**自装 Adapter 模式**。

---

## 1. 扩展注册机制（全项目只有 4 个入口）

| 入口 | 位置 | 签名 | 用途 |
| --- | --- | --- | --- |
| `ModuleRegistry.register` | `L/shared/ProjectALife/Behaviours/ALifeModuleRegistry.lua:101` | `(definition) -> true \| false, reason` | 注册行为模块（**唯一官方注册器**） |
| `X.configure(adapters)` | **54 处**，如 `ALifeWatchdog.lua:84`、`ALifeActorRegistry.lua:153`、`ALifeOrphanGuard.lua:108`、`ALifeMirrorTransport.lua:9` | `(adapters) -> …` | 依赖注入接缝（可替换时钟/寻敌/回传） |
| `VoiceCatalog.registerProfile` / `registerEntry` | `L/shared/.../Audio/ALifeVoiceCatalog.lua:254 / :297` | `(id, specification)` / `(profileId, value, entry)` | 新语音档案与台词 |
| `Compat.known[id] = {name,verdict,note}` | `L/shared/.../Compat/ALifeModCompat.lua:13-84` | 纯数据表 | **仅提示文案，不是注册 API**（第三方无法写入） |

### 1.1 `Compat.known` 的 34 条现状（29 显式 + 5 个 VariableSkin 循环）

| verdict | 模组 id |
| --- | --- |
| `incompatible` | `ProjectALifeReconstructed`(:15)、`BanditsWeekOne`(:64) |
| `unsupported` | `AmmoLootDropGunsOfMarzB42`(:46)、**`Bandits2`(:66)**、`KnoxEventExpandedNpc`(:68)、`KnoxEventExpandedNpcLegacy`(:70) |
| `adapted` | `CyesPushDoors`(:20)、`hf_point_blank`(:24)、`WanderingZombies`(:28)、`PROJECTRVInterior42`(:30)、`PixelStrikeIndicator`(:34)、`ProjectExile`(:48)、`improvedhairmenubuild42`(:73) |
| `partial` | `WeaponLoadout`(:18)、`moreTraitsDefinitive`(:22)、`GaelGunStore_B42`(:26)、`Advanced_trajectorys_Realistic_Overhaul`(:32)、`AutoAll`(:36)、`WeaponModifiersFrameworkB42`(:44) |
| `compatible` | `GunsOfMarz`(:38)、`GoMAttachmentWorkbench`(:40)、`ImprovisedSilencers`(:42)、`MarzGuns`(:50)、**`NeatUI_Framework`(:53)、`Neat_Rocco`(:55)、`Neat_Crafting`(:57)、`Neat_Building`(:59)、`NeatLockpicking`(:61)**、`FantasyWorkshopVS42_4.0`(:76)、`VariableSkin`×5(:80) |

语义：`adapted` = 已写补丁适配器；`partial` = 只堵住部分接缝（原文例子："Hooks registered before the shield are not covered"）；
`unsupported` = 未测试。

### 1.2 两条**硬红线**（`ALifeModCompat.lua`）

```lua
-- :203-205  probePaths 命中即判 incompatible + 弹窗
lines[#lines+1] = string.format("%s (%s) -> incompatible: ships its own copy of A-Life's %s; "
    .. "it replaces or runs beside A-Life's file and breaks on updates. "
    .. "A translation should ship only Translate files", id, id, path)
-- :217-234  重绑定这三个表同样判 incompatible
rebound[#rebound+1] = "ProjectALife.EquipEventShield"  -- 无 withCleanup 则 NPC 完全无法生成
```

`probePaths`（`:114-127`）会探测 **12 个 A-Life 旧路径**，用于识别"自带 A-Life 文件副本"的模组。

> ⚠️ **对我们最重要的一条**：**绝不要在 A-Life 的目录树下放 Lua 文件**，也不要 rebind
> `ProjectALife.CreatorScreen` / `ProjectALife.EquipEventShield` / `ProjectALife.Animations`。
> 翻译类模组只允许发 `media/lua/shared/Translate/<LANG>/*.json`。

### 1.3 Adapter 模式（14 个文件，无注册表、无分发器）

每个文件手写，并以 `Events.OnGameStart.Add(Adapter.install)` + **行尾立即 `Adapter.install()`** 自装
（`ALifePointBlankAdapter.lua:35-38`）。规范骨架：

```lua
ProjectALife = ProjectALife or {}
local Adapter = { installed = false }
function Adapter.isOurs(c)            -- :6-18 判定 A-Life NPC 的标准双路
    local data = c:getModData()
    return type(data) == "table" and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
        or (c:GetVariable("ALifeUID") or "") ~= ""
end
function Adapter.install()            -- :20-33 幂等替换 + 保留 original
    if Adapter.installed then return true end
    local m = SomeMod
    if type(m) ~= "table" or type(m.Fn) ~= "function" then return false end
    local original = m.Fn
    m.Fn = function(...)
        if Adapter.isOurs(select(2, ...)) then return false end
        return original(...)
    end
    Adapter.installed = true
    return true
end
```

---

## 2. 数据层扩展点

**可以新增阵营/NPC 档案；不能新增关系层。**

### 2.1 三条合法路径

1. **本地文件**：`alife_custom_factions.ini` / `alife_custom_profiles.ini`
   （`Custom.fileName`，`ALifeCustomFactions.lua:8`），经 `Custom.load()→parse()→fromRecords()`
   （`:259 / :253 / :217`）overlay 到 shipped 目录（`ALifeCatalog.lua:128-150`，**在 pcall 内**）。
2. **运行时 API**：`Custom.save(faction)` / `saveMany` / `delete(id)`（`:321 / :332 / :367`）；
   **MP 客户端自动改走** `CustomFactionClient.upsert`（`:321-330`）——客户端不能直写。
3. **分享码导入**：`FactionShare.decodePack(source)` / `importAsNew(source,newId)` / `adoptAsNew(pack,newId)`
   （`ALifeFactionShare.lua:464 / :495 / :502`）。编码头 `ALIFEPACK1`（`:197`），旧码 `PALF2`（`:198`）；
   容量上限 `maxBytes = 500000`（`:9`），`chainLimit=16`、`niceLength=1024`（`:200-201`）。

**关系层不可扩展**：`RelationLayers.shifts`（`:22-48`）是职业→bloc 的硬编码表；
第三方只能用 `.alife` 的 `stance.<key>` 增写键，键由 `professionKey("player:")`/`blocKey("bloc_")`/`folderKey("folder:")` 生成（`:6-8`）。
`FactionSpawnRules` 同理是纯函数库（24 个函数，`:11-273`），无注册口。

### 2.2 `.alife` 格式完整规格（`Codec.schema`，`ALifeRecordCodec.lua:15-72`）

```
@alife-records 1                      -- 头 Codec.HEADER:5；版本 > Codec.VERSION(=1) → record_version(:208-210)
                                      -- 空行忽略；"--" 开头为注释(:211)
faction alife_kettle                  -- 记录头 <kind> <id>：kind 须 ^%a+$，id 须 ^[%w_%-%.]+$(:221, validId:104)
  about.title Kettle Works Crew       -- 字段：缩进 INDENT="  "(:7)，group.field value
  stance.player neutral
  habits.flee on                      -- flags：schema 第 3 元素做 布尔→词 映射(:93-96, valueText:141)
end                                   -- 记录尾：裸 end(:217)
```

- kind 仅 **`faction`**(:16) 与 **`member`**(:36)。
- 转义 `\\ \n \r \t`，首尾空格写 `\s`（`escapes:10`，`escape:117-126`）。
- 标量自动转型：`"true"/"false"`→bool，数字串→number（`scalar:108-115`）。
- 保留字：`id / kind / source / line`（`:9`）。
- **字段路由表**（左=文件里的名字，右=内存路径）：
  faction 六段 `general/spawn/support/modules/relations/memberModules`；
  member 九段 `general/clothing/outfitEnabled/outfitSeason/outfitA..F/tintA..F/weapons/ammo/weaponAttachments/modules/moduleOverrides`
  （`:69-72` 动态生成 outfit/tint 六套）。
  典型键：`body.hitPoints`、`body.might`、`body.marksmanship`、`look.hair`、`kit.bottomless`、
  `loot.gunOdds`、`radio.caller`、`arms.main`、`rounds.main`。
- **校验错误码**（`decode` 返回 `nil, "source:line:code"`）：
  `record_version, stray_end, unclosed_record, wrong_kind, duplicate_record, outside_record, bad_line,
  bad_field, duplicate_field`（`:209-285`）；`lenient=true` 时全部降级进 `rejects` 数组（`:183,192-196`）。
- **跨记录校验**（`ALifeCatalog.lua:45-66`）：`faction.general.name` 与 `member.general.name` 必填；
  `member.general.faction` 必须已存在，否则进 `orphanedProfiles` 并被剔除。
- **删除 = 写 `general.deleted true`**（`:153-173`），不是物理删除。
- 第三方**不能换文件名**：`RecordMigration.validFileName` 只接受 `^alife_[%w_]+[%.%w]+$`（`ALifeRecordMigration.lua:29-31`）。

#### ⚠️ 两种字段命名都能通过解码器（**实测发现，容易踩坑**）

`Codec.schema` 把"人类可读名"映射到内存路径
（`member.general = { "who", { name = "who.title", faction = "who.faction" } }`，`ALifeRecordCodec.lua:23-25, 38-39`），
但**文件里直接写内存路径也成立**：

| 文件侧名（A-Life 自带数据用） | 内存路径名（Aftermath 等扩展用） | 内存中的落点 |
| --- | --- | --- |
| `about.title` | `general.name` | `general.name` |
| `who.title` | `general.name` | `general.name` |
| `who.faction` | `general.faction` | `general.faction` |
| `who.trade` | `general.profession` | `general.profession` |

证据：A-Life 自带 `common/alife_runtime/catalog/*.alife`（148 阵营 / 780 成员）用文件侧名；
Aftermath 的 79 个 `.alife`（42 阵营 / 2,767 成员）用内存路径名，而它有 5,921 订阅且实测能正常合并。
→ **写 provider 时两种任选，但同一文件内要统一**。

另外：**值可以省略**（`  look.beard`、`  presence.towns`、`  reinforce.vehicle` 表示空值），
A-Life 自带数据里有 **666 处**这种写法，解析器接受。

> **本地校验工具**：`../tools/alife_lint.py` 按上述规格实现，并已用真实数据回归：
> A-Life 核心目录 → `files=2 records=928 factions=148 members=780 errors=0 warnings=0`；
> Aftermath 三变体 → `files=79 records=2809 factions=42 members=2767 errors=0`。
> 用法：`python3 tools/alife_lint.py <文件或目录> [--require-identity] [--strict]`。

---

## 3. 行为层扩展点（唯一官方注册器）

### 3.1 `Registry.register(definition)` 完整契约

| 字段 | 语义 | 校验 / 默认 |
| --- | --- | --- |
| `id` | string，唯一非空 | 否则 `false,"id_invalid"`；重复 `false,"duplicate_module:"..id`（:104,:121） |
| `kind` | 枚举 `doctrine\|orders\|reaction\|craft\|upkeep`（`Registry.kinds:15-21`） | 旧值经 `kindMigration:23-29` 折算：behavior→doctrine、decision→upkeep、response→reaction、positioning→craft；未知 `false,"kind_invalid"` |
| `dispatch` | 枚举 `decision\|response\|positioning`（`dispatchKinds:31`） | 缺省查 `defaultDispatch:32-36`：orders→decision、reaction→response、upkeep→decision。**craft/doctrine 无默认 → `dispatch=nil` → 注册成功但永不执行** |
| `priority` | number，**越小越先**（`sortModules:67-74` 升序；同值按 id 字典序） | 缺省查 `Registry.priorities[id]` 否则 **500**（:131-132） |
| `primary` | bool，true 则仅当该 NPC `memory.conduct == id` 时允许（:187-190） | 默认 false |
| `evaluate` | **必填 function**，`(actor, shell, context) -> result`；**返回首个非 nil 值即决定**并中止链（:216,225-226） | 否则 `false,"evaluate_invalid"`；调用被 `pcall` 包裹，异常写 `Registry.lastError`（:228） |
| `label` / `summary` | string，仅 UI/调试 | 默认 id / "" |
| `defaultEnabled` | false 则初始禁用（:138） | — |
| `allows` | **不是契约字段**（全项目无人这么注册）| 授权走 `Registry.allows`(:184) → `BehaviorProfiles.allows(actor,id)`(:199-201) |

**优先级表全量**（`Registry.priorities:43-65`）：
`orders 10, flee 30, stealth 30, panic 34, sniper 38, warning 40, ambusher 42, withdraw 45, cover 50,
weave 55, strafe 60, medic 85, healing 90, patrolRest 92, stance 95, investigate 100, regroup 110,
search 117, scavenge 118, spread 150, groupMarch 200`；未列 = 500。
实际注册里显式覆盖的：`panic 34`（Panic:309）、`cqbsweep 92`（Breach:1253）、`doorstack 60`（Breach:1077）。

**dispatch 真实触发点只有 5 处**：`ALifeDecisionLoop.lua:402`（response）、`:593/:601`（decision，带 `only`）、
`ALifeCombat.lua:1406` 与 `ALifeCombatApproach.lua:30`（positioning，带 `only`）。

### 3.2 四层开关（从外到内）

1. `SandboxVars.ALife.*` → `Settings.applyModuleSwitches`（`ALifeSettings.lua:301-328`）映射 18 个沙盒键 → `registry.setEnabled`
2. `Registry.disabled[id]`（`setEnabled:147-154`；`defaultEnabled=false` 走 `:138`）
3. `ProjectALife.ModuleSwitches.values[id]`（`ALifeModuleSwitches.lua:6-46`，**31 个开关**）；`Switches.set`（`:55-67`）会级联 `invalidate()`
4. 每 NPC `actor.memory.moduleOverrides[id] = "on"|"off"`（`Registry.override:173-182`）；外加 `primary` conduct 门与 `BehaviorProfiles.allows` overlay

### 3.3 最小可运行示例（照 `ALifeModuleStrafe.lua:1-22` 同构）

```lua
require "ProjectALife/Behaviours/ALifeModuleRegistry"   -- 必须先 require
ProjectALife = ProjectALife or {}
local Registry = ProjectALife.ModuleRegistry
local Mod = { id = "mymod_hold" }
ProjectALife.ModuleMyHold = Mod
function Mod.active() return Registry.isEnabled("mymod_hold") end
Registry.register({
    id = "mymod_hold", kind = "reaction", dispatch = "response",  -- dispatch 必须显式给
    priority = 36, label = "Hold fast",
    summary = "拒绝在暴露位置还击。",
    evaluate = function(actor, shell, context)
        if context == nil or context.target == nil then return nil end   -- nil = 让下一个模块决定
        return { action = "hold" }                                       -- 非 nil = 抢占
    end,
})
```

---

## 4. NPC / 实体层扩展点

### 4.1 枚举所有 A-Life NPC：用 `ActorRegistry`，**不要**扫 `getCell():getZombieList()`

| API | 位置 | 签名 |
| --- | --- | --- |
| `Registry.each(cb)` | `ALifeActorRegistry.lua:450` | `(callback) -> visited`；按 `Registry.order` 迭代**活记录**，cb 返回 true 提前终止 |
| `Registry.list()` | `:444` | `() -> {record…}`，**深拷贝，昂贵** |
| `Registry.read(uid)` | `:432` | `(uid) -> copy(record)`（别名 `copyingRead:437`） |
| `Registry.peek(uid)` | `:438` | `(uid) -> record`（**无拷贝，只读**） |
| `Registry.update(uid, expectedRevision, mutation)` | `:463` | 乐观锁；revision 不符返回 `"actor_revision_conflict"` |
| `Registry.create(spec)` | `:374` | 需 `operationId` + `fingerprint` 幂等 |
| `Registry.remove/markDead/activate/makeDormant` | `:636/:710/:678/:691` | 生命周期迁移 |

**判定"是否 A-Life NPC"的规范双路**（`ALifeOrphanGuard.lua:36-50`）：
`data.ProjectALifeOwned == true and type(data.ProjectALifeUID) == "string"`，
或 `shell:GetVariable("ALifeUID")` 为 string 且 `GetVariable("ALifeActor") == "true"`。
快速确认在场用 `ShellAdapter.zombieListedFast(shell)`（`ALifeShellAdapter.lua:316`，`zombies:contains(shell)`）。

> 注意：`getCell():getZombieList()` 全项目 18 处调用都做了 `pcall` + `contains` 快路径或预算分片。

### 4.2 写入契约（`ALifeShellAdapter.createShell:82-140`）

```lua
SetVariable("ALifeActor"|"ALifeUID"|"ALifeGeneration")            -- :106-108
getModData().ProjectALifeOwned / .ProjectALifeUID / .ProjectALifeGeneration
           / .ProjectALifeSpawnedAtMs / .ProjectALifeConduct / .ProjectALifeFlashlight  -- :108-118
```
另 `ALifeAIFence.markOwned:626-637` 与客户端 `ALifeAnimationClient.lua:255,338` 会补戳。
**唯一清除点**：`ALifeShellSimulation.lua:34-37`（回收时 `ProjectALifeOwned=nil`、`ALifeActor="false"`）。

**OrphanGuard 惩罚机制**（`ALifeOrphanGuard.lua`）：`tick(budget)` 每 tick 只扫 16 个（:155-193）；
6 秒生成宽限靠 `ProjectALifeSpawnedAtMs`（`ownedByRuntime:65-70`）；
ghost 存储 TTL 168 世界小时、上限 600（`:196`）。
**uid 丢失时先 `OrphanGuard.disarm(shell,isMarked)` 缴掉双手物品**（`:139-153`）再清理。

### 4.3 血量**必须**走 `ShellSimulation`

```lua
-- ALifeShellSimulation.lua:87-105
function Sim.setHealth(shell, health)
    if Sim.bookShielded(shell, health) then return true end   -- 受击护盾期
    shell:setHealth(health)
    data.ProjectALifeHealthCeiling = health                    -- 记录上限
    if isServer() then data.ProjectALifeHealthRevision = ... + 1   -- MP 对账版本号
        data.ProjectALifeHealthPendingUntilMs = nowMs() + 3000
        data.ProjectALifeHealthAck = nil end
end
```
读真值 `Sim.trueHealth(shell)`（`:115`，回退 `pendingHit`/`fallShield`/ceiling）；
上限 `Sim.maximumFor(shell)`（`:75`，读 `ProjectALifeMaximumHealth`）。

### 4.4 AIFence 动画变量（**第三方写同名变量会被下一帧覆盖**）

`Fence.fenced` 是弱键表（`:843`）；合法生命周期口只有 `Fence.track(shell):2403` /
`Fence.untrack:2429` / `Fence.lower(shell,reason):846`。
它每帧回写：`ALifeActor, ALifeWalkSpeed, ALifeRunSpeed, ALifeSprintSpeed, ALifeStrafe, ALifeStrafeX,
ALifeStrafeY, ALifeWeaponHeld, ALifeAimWalk, ALifeArms, ALifeGrip, ALifeCombatSpeed, ALifePace,
ALifeSneak, ALifeLimp`（`:924-926, 2221-2260, 2491-2512`）。

### 4.5 必须避免的 8 件事

| # | 禁止操作 | 后果 / 证据 |
| --- | --- | --- |
| 1 | `shell:setHealth()` 直写 | 绕过 ceiling + HealthRevision/Ack → 联机血量撕裂（`ALifeShellSimulation.lua:87`） |
| 2 | 清空 `getModData()` / 删 `ProjectALifeOwned`/`UID` | 判为 ghost → 缴械 + 清理（`ALifeOrphanGuard.lua:36, 90, 139, 155`） |
| 3 | 直写 `ActorRegistry.records` / `Watchdog.bindings` | 绕过 revision 乐观锁与身份校验（`:463`；`ALifeWatchdog.lua:106-137`） |
| 4 | 绕过 `Lifecycle`/`Registry.markDead` 调 `removeFromWorld()`/`setDead()` | 记录悬空 → `Watchdog` 记 `shell_identity_mismatch`（`ALifeWatchdog.lua:61-70`） |
| 5 | 自己 `SetVariable("ALife*")` | 每帧被 AIFence 覆盖 |
| 6 | 每 tick 全量遍历 `getZombieList()` | 用 `ActorRegistry.each` + `zombieListedFast` |
| 7 | 复用已存在的模块 id | `register` 静默返回 `false,"duplicate_module:…"`（`:121`） |
| 8 | MP 客户端直接 `Custom.save()` 落盘 | 必须走 `CustomFactionClient/Authority`（`ALifeCustomFactions.lua:321-330`；`ALifeCustomFactionAuthority.lua:365`） |

---

## 5. 事件与消息层

**唯一 module 名 = `"ProjectALife"`**（全项目字面量硬编码，无命名空间常量）。

- **Client→Server**（`sendClientCommand`，23 处）：`requestStatus, playerDied, shellHit, weaponNoise, shout,
  outpostRadioList/Use/Disable, debugSquadMap, debugMetaEvent, debugOutpostDelete, debugModuleQA, debugBlackbox,
  debugTownCensus, alifeDiagnostics, debugPurgeActors, debugSquadDelete, debugResetCreator, debugPurgeArea,
  debugForceSupport, debugBuildOutpost, raidStart, creatorUpload, creatorProfileUpsert/Delete/Hello,
  creatorFactionUpsert/Delete/Hello/Reset, ... talkSay/talkChoose/talkSession/talkEmote/talkHelped/talkState` 等
- **Server→Client**（`sendServerCommand`，12 处）：`status, supportArrival, supportSpotlight,
  outpostRadioListResult, radioTalk, MetaEvent, reputationSync, talkResult, executorLootResult,
  executorMirror, executorReportRefused, RaidStart, RaidWave, debugSpawnResult, <cmd>Result`

**门禁（关键）**：`ALifeDebugService.handle:2598-2600` 用**白名单** `commands[command] ~= true` 直接拒绝
→ **第三方不能在 `"ProjectALife"` 下加自己的 cmd**。
`gameplay` 白名单可绕开管理员校验（`:2615-2625`，含 `shellHit/weaponNoise/shout/playerDied/*Radio*/creator*Hello`），
非 gameplay 需 `authorized(player)`；限流 `gameplay 60ms` / 其他 `Service.minimumIntervalMs`（`:2684-2691`）。
talk 另有 `Talk.commandIntervalMs = {talkSay=800, talkChoose=800, talkSession=1000, talkEmote=400, talkHelped=3000, talkState=250}`（`ALifeTalk.lua:723`）。

> **第三方必须使用自己的 module 名（= 自己 mod id）。**

**MirrorTransport 帧**（`ALifeMirrorTransport.lua:195-199`）：
`{stream, sequence, full, records, removed, present, catalog={npcs,factions}, warfare, bases, died}`；
接收端只强校验 `records/present/sequence/stream`（`:239-240`）→ **额外顶层字段能存活但无人读取**，
想夹带第三方数据必须自带接收端；且 `Transport.adapters.send`（`:201-204`）会**整体替换**发送路径，**不能叠加**。
可用 adapters 键：`nowMs, players, position, owns, bases, send, request`（`:17,32,39,57,85,201,231`）。

**核心自身监听事件**（去重计数）：OnGameStart 26、OnTick 24、OnServerCommand 22、OnServerStarted 8、
OnMainMenuEnter 7、OnClientCommand 7、OnPreUIDraw 6、OnKeyPressed 5、OnConnected 5、OnZombieUpdate 4、
OnWeaponSwing 4、OnHitZombie 4、OnPreFillWorldObjectContextMenu 3、OnPlayerDeath 3、OnZombieDead 2、
OnGameBoot 2、OnFillWorldObjectContextMenu 2、OnDisconnect 2、EveryOneMinute 2、OnPostUIDraw 1 等。

---

## 6. UI / 沙盒 / 本地化 / 语音

- **上下文菜单**：`Events.OnPreFillWorldObjectContextMenu.Add(fill)`（`ALifeContextMenu.lua:520-521`），
  根项 `[A-LIFE] Project A-Life`（`:423`）。**无注册器、无优先级** → 第三方必须自己挂
  `OnFillWorldObjectContextMenu`，顺序 = 注册顺序。
- **沙盒命名**：`option ALife.<Group>_<Name> = { type, default, page, translation, _tooltip, valueTranslation, min/max/numValues }`
  （`sandbox-options.txt:1-30`），共 **118** 项、6 个 page。
  **第三方必须用自己的表名**（如 `MyMod_…`）：沙盒名会落成 `SandboxVars.<第一段>`，
  用 `ALife.*` 会与核心同表冲突，且 `Settings.applyModuleSwitches` 会误读。
- **本地化**：`Text.ui(en)` → key = `"IGUI_ALifeUI_" .. Text.hash(en)`，hash 是两个 32 位累加器各取 8 位 hex 拼接
  （`ALifeText.lua:77-85, 115-118`）；前缀白名单 `IGUI_/RD_/Sandbox_`（`:5`，`prefixOk:11-18`）。
  **键由英文源串内容决定** → 第三方翻译只需提供同 key，**绝不能改英文源串或 rebind `ProjectALife.Text`**；
  扩展自己新增的文本请用 `IGUI_<YourMod>_` 前缀。
- **语音（最开放的扩展点）**：`Voice.play(shell, event, options)`（`ALifeVoice.lua:378`，
  `Voice.react = Voice.play` :499）、`Voice.preview(...)`（`:324`）、`Voice.configure(adapters)`（`:229`）。
  6 个 hook：`VoiceWorkbenchRegister / ProjectRegister / LegacyRegister / DialogueRegister /
  LootEventsRegister / FactionVoiceRegister`，均以 `function(Catalog)` 调用并有 `if type(...)=="function"` 守卫
  （`ALifeVoiceCatalog.lua:143-144, 311-321`）。

---

## 7. 官方"扩展指南"证据

**不存在** README / 扩展文档 / `loadModAfter` 提示（全项目 grep 为空）。
`42.20/mod.info` 仅 7 行，无 `require=`；包内无 `workshop.txt`。

唯一的"给扩展作者的说明"是**反向禁令**（`ALifeModCompat.lua`）：
`:203-215`（"A translation should ship only Translate files"）、
`:217-234`（不得 rebind `ProjectALife.CreatorScreen`/`EquipEventShield`/`Animations`）、
`:258-278`（弹窗文案 + "Disable or unsubscribe it"）。

作者公开契约 = `ProjectALifeOwned`（跳过僵尸循环）+ `GetVariable("ALifeUID")`/`"ALifeActor"`，
被 14 个 adapter、`OrphanGuard`、`CombatCore/Strike/Fire/LineOfFire`、`TargetPolicy`、`Perception`、
`Reputation` 共同依赖（如 `ALifeCombatCore.lua:235,448,635`）。

---

## 8. 稳定性总表

### 【稳定】有类型校验 / pcall / 多路径回退，且被大量内部代码共用（= 事实契约）

| 扩展点 | 为什么稳 |
| --- | --- |
| `getModData().ProjectALifeOwned/ProjectALifeActor/ProjectALifeUID` + `GetVariable("ALifeUID"/"ALifeActor")` | 14 adapter + OrphanGuard + Combat + Perception + Reputation 共用；每处 pcall；作者公开承诺。**只读** |
| `Catalog.faction(id)` / `Catalog.npc(id)` | `ALifeCatalog.lua:201-209` 带 network overlay + nil 安全 |
| `ActorRegistry.each/read/peek` | 有 copy + revision；`peek` 明确标注只读快路径 |
| `ModuleRegistry.register/get/isEnabled/list` | 返回值式错误码 + `pcall(evaluate)` + `lastError`；无破坏性副作用 |
| `Voice.play` / `Catalog.registerProfile/registerEntry` | 全参数类型校验，返回 `(false, reason)` |
| `SandboxVars.ALife.*` | 纯读 |
| `Text.ui/radio/lineKey` | 引擎查找 pcall + 缓存 + miss 降级返回英文原串 |

### 【半稳定】公开但无版本守卫，字段名是内部约定

| 扩展点 | 风险点 |
| --- | --- |
| `X.configure(adapters)`（54 处） | `Watchdog.configure:84-96` 会校验 5 个必填键并返回 false，但**多数 configure 直接赋值无 pcall**；键名随时可改 |
| `Compat.known[id]={…}` | 纯数据，加一行安全，但只影响提示文案（且第三方改不了核心的那份） |
| `Registry.register` 的 `dispatch` 语义 | craft/doctrine 无默认 → 漏写 `dispatch` 会注册出**永不执行的死模块** |
| `ModuleSwitches.set(id,enabled)` | 公开且有 `invalidate()`，但 `values` 表是硬编码 |
| `Events.OnPreFillWorldObjectContextMenu` / `OnFillWorldObjectContextMenu` | 无优先级机制，顺序不稳 |
| 6 个 `VoiceXxxRegister(Catalog)` hook | 有 `type()=="function"` 守卫，但 hook 名本身是内部约定 |
| `.alife` 格式 | 有版本号与 `record_version` 拒绝 + `lenient` 降级，但 schema 是内部表 |
| `FactionShare.decodePack/importAsNew` | 有 checksum/链长/字节上限校验，但 header 升级后旧码走 `retiredReason` |

### 【内部实现】直用会被升级或对账机制打死

| 扩展点 | 为什么 |
| --- | --- |
| `ActorRegistry.records` / `Watchdog.bindings` / `AIFence.fenced` / `Executor.executed` | 无访问器封装，直写绕过 revision 乐观锁与 `shell_identity_mismatch` 校验 |
| `ShellSimulation.setHealth` 的 ceiling / `HealthRevision`/`Ack` 语义 | 内部 MP 对账协议 |
| `DebugService.commands` 白名单 / `authorized()` / 限流 | 白名单 + 管理员校验，第三方 cmd 必被拒 |
| `MirrorTransport` 帧结构与 `Transport.adapters.send` | 帧可加字段但无接收方；`send` 是整体替换而非叠加 |
| `ALifeText.hash` 派生的 UI 键 | 由英文源串内容决定，改串即失配 |
| rebind 任何 `ProjectALife.*` 表 | `ALifeModCompat.lua:217-234` 判 incompatible 并弹窗 |

---

## 9. 给扩展作者的 10 条铁律

1. **只读 ModData，不改 ModData。** `ProjectALifeOwned/UID/Generation/SpawnedAtMs` 由
   `ShellAdapter.createShell:108-118` 与 `AIFence.markOwned:626` 独占写入；擦掉会被
   `OrphanGuard.disarm:139` 缴械再清理。
2. **判定 NPC 用双路谓词**：`data.ProjectALifeOwned==true or data.ProjectALifeActor==true`，
   回退 `GetVariable("ALifeUID")`；两路都套 `pcall`（`ALifePointBlankAdapter.lua:6-18`）。
3. **血量和上限只走 `Sim.setHealth / Sim.trueHealth / Sim.maximumFor`**
   （`ALifeShellSimulation.lua:87/115/75`）。直接 `shell:setHealth()` 会在联机里制造永久性数值撕裂。
4. **枚举 NPC 用 `ActorRegistry.each`**，别每 tick 扫 `getCell():getZombieList()`；
   确认真实性用 `ShellAdapter.zombieListedFast`。
5. **改生命周期用 `ActorRegistry.update(uid, expectedRevision, mut)`**（`:463`）并处理
   `actor_revision_conflict`；不要直写 `records`，不要自己 `removeFromWorld()`。
6. **绝不重绑定 `ProjectALife.*` 的表或函数**，也绝不在 A-Life 目录下放置 Lua
   （`ALifeModCompat.lua:203-234`）。翻译只发 `media/lua/shared/Translate/<LANG>/*.json`。
7. **注册行为模块时 `dispatch` 必须显式写**（craft/doctrine 无默认，否则死模块），
   `priority` 越小越先跑，`evaluate` 返回 nil 放行、非 nil 抢占；不要依赖未文档化的 `allows` 字段。
8. **网络命令用你自己的 module 名**（= 你的 mod id）。`"ProjectALife"` 是白名单 + 管理员校验的领地
   （`ALifeDebugService.lua:2598-2625`）。
9. **适配第三方模组时照抄 Adapter 骨架**：`installed` 幂等标志 + 保存 `original` + `isOurs` 前置拒绝 +
   `Events.OnGameStart` 与加载时各装一次（`ALifePointBlankAdapter.lua:20-38`）；不要改 A-Life 自己的逻辑。
10. **沙盒与本地化都用自己前缀**：沙盒不要写 `option ALife.*`（会污染 `SandboxVars.ALife`）；
    文本用 `IGUI_<YourMod>_`，因为 A-Life 的 `IGUI_ALifeUI_<hash>` 键由英文源串内容哈希生成，改源串即全部失配。
