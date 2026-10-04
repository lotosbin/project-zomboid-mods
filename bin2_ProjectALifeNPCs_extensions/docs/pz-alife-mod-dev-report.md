# 活世界 NPC 模组开发学习报告
## —— 以 Project A-Life [ALIFE NPCS]（工坊 3803984183）为标杆的从零复刻路线

> 报告日期：2026-10-04
> 分析对象：Steam 创意工坊 `3803984183` / Mod ID `ProjectALifeNPCs` / 作者 Vice / 版本 1.3.15~1.3.16 / B42.21
> 分析依据：**本机已订阅安装的真实模组文件**（`steamapps/workshop/content/108600/3803984183`，248 个 Lua 文件 / 146,518 行）+
> Steam 官方 `ISteamRemoteStorage/GetPublishedFileDetails` 元数据 + 游戏自身 Java 字节码（`javap`）+ 外部权威资料
> 适用读者：想开发"有生命感 NPC / 活世界模拟"类 PZ 模组的开发者

**目录**（共 10 章 + 附录）

- **0. 一页速览（TL;DR）** —— 结论表，先看这个
- **1. 情报档案** —— Steam 元数据 / 作者承诺 / 代码规模实测
- **2. 交付物结构与打包** —— `common` + 版本目录、可直接照抄的布局
- **3. 技术路线总览** —— 分层架构图与一句话概括
- **4. 关键机制拆解（15 节）** —— 4.1 僵尸载体｜4.2 动画状态机｜4.3 调度器｜4.4 多人同步｜4.5 内容管线｜4.6 声明核实｜4.7 决策｜4.8 感知听觉｜4.9 移动破障｜4.10 战斗｜4.11 恐惧·小队·声望｜4.12 世界离线模拟｜4.13 据点｜4.14 持久化｜4.15 生命周期
- **5. 引擎边界** —— B42 给了什么、不给什么（字节码取证）
- **6. 从零开发路线图** —— P0~P6 分阶段 + 单人裁剪线 + 翻车点
- **7. 最小可行骨架** —— 可直接起步的目录与代码
- **8. 工程陷阱与最佳实践（22 条）**
- **9. 与本仓库的结合** —— 差距分析 + 可执行的第一步
- **10. 参考资料与延伸阅读**（附链接核实方法与实测状态）
- **附录 A. 证据索引** —— 按主题定位到具体文件与行号

**如果你只有 10 分钟**：读第 0 章 → 第 4.1 / 4.2 节（僵尸载体 + 动画状态机，这是全部技术的地基）
→ 第 5.1 节（B42 没有现成 NPC AI）→ 第 6.3 节（单人 MVP 该砍到什么程度）。

---

## 0. 一页速览（TL;DR）

| 问题 | 结论 |
| --- | --- |
| 它是什么 | 把 S.T.A.L.K.E.R. 式 A-Life（离屏持续模拟的阵营/小队世界）搬进 Zomboid：148 派系、据点、巡逻、遭遇、掠夺、无线电、离屏战斗、记忆与复仇 |
| 核心实现路线 | **纯 Lua**（无 .exe/.jar/ZombieBuddy），NPC 直接建立在**原版僵尸实体**之上，用 `modData` 打所有权标记"接管"它 |
| 最独特技术 | **扩展僵尸的动画状态机**：自建 225 个 `AnimSets/zombie/<state>/*.xml` 动画节点，把玩家动画（`Bob_Walk`/`Bob_Reload_Rifle_Load`…）挂到僵尸身体上，靠 `SetVariable("ALifeActor","true")` 等自定义变量驱动 |
| 最大工程难点 | **离屏模拟**（无实体的小队在世界层按道路推进、打离屏战斗、复仇）+ **多人同步**（服务端权威 + 客户端动画镜像） |
| 代码规模 | 248 文件 / 146,518 行 Lua；shared 93 文件 63.7k 行、server 109 文件 63.2k 行、client 46 文件 19.6k 行；外加 225 个动画 XML、455 个服装、101 个模型 |
| 体量判断 | 这是**团队级项目**（作者自述 "Vice and the A-Life team"），不是单人几周的产物；单人复刻必须**大幅裁剪范围**（本报告第 6 章给出裁剪版路线图） |
| 市场表现 | 工坊条目创建于 2026-09-19，2026-10-01 最后更新；订阅 121,195、收藏 12,372、浏览 168,828（Steam API 实测；条目创建于 2026-09-19，最后更新 2026-10-01） |
| 对个人开发者的启示 | 真正卖钱的不是"NPC 会开枪"，而是**世界在你不在场时仍然运转**；以及**可被玩家二创的数据层**（阵营编辑器 + COPY/LOAD CODE + 118 个沙盒选项） |

---

## 1. 情报档案（可复核的事实）

### 1.1 Steam 侧元数据（来源：Steam Web API）

查询命令（无需 API Key，公开接口）：

```bash
curl -s -X POST "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
     -d "itemcount=1&publishedfileids[0]=3803984183"
```

| 字段 | 值 |
| --- | --- |
| title | Project A-Life [ALIFE NPCS] |
| Mod ID | `ProjectALifeNPCs` |
| 作者 | Vice（SteamID `76561198364056883`） |
| tags | `Build 42`、`Multiplayer` |
| 文件体积 | 35,333,466 B（≈33.7 MiB） |
| 订阅 / 收藏 / 浏览 | 121,195 / 12,372 / 168,828 |
| 创建 / 最后更新 | 2026-09-19 / 2026-10-01（`time_created`/`time_updated`） |
| 当前版本 | 1.3.16（描述）/ `mod.info` 内 `modversion=1.3.15` |
| 支持版本 | `versionMin=42.21.0`，B42.21 |
| 支持模式 | 单机 / 合作 / 多人 |

### 1.2 作者对外的技术承诺（原文摘录，可作为"合规红线"参考）

> "Project A-Life uses no PowerShell scripts and no third-party software. Just subscribe and play:
> no .ps1, .exe, .bat, .jar or .dll files etc, no ZombieBuddy/java installs, nothing that runs outside the game.
> Only Lua code, textures, models, sounds and plain-text data."

> "Every A-Life body has: `zombie:getModData().ProjectALifeOwned == true` — Skip those in your zombie loops."

这两句话在代码里已被逐条核实（见 4.1、4.9）。

### 1.3 本机代码规模统计（实测）

```
== 分层（42.20/media/lua） ==
shared : files= 93  lines=63,721
server : files=109  lines=63,244
client : files= 46  lines=19,553
总计   : files=248  lines=146,518   (9.4 MB 纯 Lua 源码)

== 子系统（shared+client+server 合并，按行数） ==
Audio       files=16  lines=27,216     ← 语音档案数据
Talk        files=30  lines=19,469     ← 对话/无线电文本数据
Interface   files=25  lines=12,039     ← 含 Creator 编辑器
World       files=31  lines=11,175
Combat      files=11  lines=10,436
Behaviours  files=22  lines=10,349
Shells      files=14  lines= 9,730
Core        files=16  lines= 8,053
Outposts    files=12  lines= 7,354
Admin       files= 4  lines= 7,272
Movement    files= 6  lines= 6,084
Records     files=20  lines= 5,336
Offline     files= 5  lines= 2,868
Decisions   files= 6  lines= 2,822
Senses      files= 8  lines= 2,662
Fear        files= 6  lines= 1,506
Compat      files=14  lines= 1,103
```

**读法**：真正的"AI 逻辑"只占一小部分；**大头是内容与表现层**（音频 27k + 对话 19k + UI 12k ≈ 40%）。
这直接说明：想做同类模组，**内容管线（数据驱动 + 编辑器）比算法更决定成败**。

---

## 2. 交付物结构与打包（可直接照抄）

```
3803984183/                                  ← 工坊物品根（订阅后落盘）
└── mods/
    └── ProjectALifeNPCs/
        ├── common/                          ← 【版本无关层】B42 支持的多版本共享目录
        │   ├── alife_runtime/
        │   │   ├── catalog/faction_registry.alife   ← 阵营主数据（自定义格式）
        │   │   └── catalog/npc_profiles.alife       ← NPC 档案主数据
        │   └── media/
        │       ├── AnimSets/{zombie,player}/…       ← 225 个自定义动画节点 XML
        │       ├── actiongroups/alife_actiongroups.txt
        │       ├── sound/{project_alife_radio,announcer,world}/…
        │       └── textures/ProjectALife{Icon,Line}.png
        └── 42.20/                           ← 【版本目录】按游戏 build 号命名
            ├── mod.info                     ← name/id/author/modversion/versionMin=42.21.0/poster/icon/description
            ├── poster.png  icon.png
            └── media/
                ├── lua/{shared,client,server}/ProjectALife/…   ← 主代码
                ├── sandbox-options.txt          ← 716 行 / 118 个选项
                ├── AnimSets/alife-creator/…     ← Creator UI 的动画预览
                ├── models_X/ (101 文件, 6.6M)  scripts/ (9)  textures/ (26)
                ├── clothing/ (455 文件, 1.8M)  sound/  fileGuidTable.xml
                └── lua/shared/Translate/EN/…    ← 仅英文，其它语言由社区单独出补丁
```

**可直接复用的三条打包经验**

1. **`common/` 放跨版本共享资源、`42.20/` 放版本相关代码**。游戏查找模组文件的顺序是
   `getVersionDir()/file` → 找不到再 `getCommonDir()/file`（结论来自
   `LuaManager$GlobalObject.getModFileReader` 的字节码，本仓库 `docs/rolling_log.md` 已记录该证据）。
   → 好处：一次美工/音频资源，多版本复用，升级 B42.22 时只需复制版本目录。
2. **`Changelog.txt` 只从"版本目录 → `common/`"找**，放在工坊物品根目录游戏读不到。
3. **一个版本目录 = 一个游戏 build 号**（`42.20`），`mod.info` 里的 `versionMin` 才是真正的门槛
   （本例 `versionMin=42.21.0`，即 B42.20 玩家装了也提示不兼容）。

---

## 3. 技术路线总览

```
                      ┌─────────────────────────────────────────────┐
   玩家视角            │  上下文菜单 / 对话 / 无线电 / 地图覆盖 / Creator │
                      └───────────────┬─────────────────────────────┘
                                      │ Events.OnClientCommand / OnServerCommand
   ┌──────────────────────────────────▼──────────────────────────────┐
   │ client/ (46 文件)                                                 │
   │   ALifeAnimationClient  ← 按服务端下发的镜像指令驱动本地动画         │
   │   ALifeSquadMap(Overlay) ← 管理员地图上画小队点                     │
   │   Interface/Creator/*    ← 阵营/NPC 全功能编辑器（328KB 主体）       │
   └──────────────────────────────────┬──────────────────────────────┘
                                      │ ALifeMirrorTransport（自研镜像协议）
   ┌──────────────────────────────────▼──────────────────────────────┐
   │ server/ (109 文件)  —— 唯一权威                                    │
   │                                                                  │
   │  Core      Runtime/Executor/ActorRegistry/Lifecycle/Watchdog      │
   │  Shells    ShellAdapter/ProfileHydrator/ShellState  ← 僵尸→NPC     │
   │  Decisions DecisionLoop/Risk/TargetPolicy/Relations/Reputation    │
   │  Behaviours 22 个 Module*（Leader/Gunner/Medic/Breach/Robbery…）   │
   │  Senses    Perception/Investigation/Clues/Stealth                 │
   │  Movement  Movement/ObstacleTraversal(132KB)/Entrances/DoorPolicy  │
   │  Combat    CombatCore/Fire/Strike/Approach/LineOfFire/SquadTactics │
   │  Fear      ThreatWatch/Panic/Withdraw/Survival                    │
   │  World     6 个 Director + SpawnPolicy/Service + Population        │
   │  Offline   OfflineDirector/SquadLedger/OfflineCombat/Revenge       │
   │  Outposts  OutpostDirector(92KB)/Builder/Architect/Radio/Gossip    │
   │  Records   Custom{Faction,Profile}Authority + Persistence          │
   └──────────────────────────────────┬──────────────────────────────┘
                                      │ 共享数据与表现
   ┌──────────────────────────────────▼──────────────────────────────┐
   │ shared/ (93 文件)                                                 │
   │   Shells/ALifeAIFence(136KB) ← 接管原版僵尸 AI 的"围栏"            │
   │   Shells/ALifeAnimations(64KB) + 225 个 AnimSet XML ← 人类动画     │
   │   Core/ALifeExecutor(132KB) ← 自研调度器/时间片预算                 │
   │   World/RoadGraph + MapZones(140KB) ← 离屏模拟所需的世界数据        │
   │   Records/* ← 阵营/NPC 档案的数据模型与编解码（COPY/LOAD CODE）      │
   │   Talk/Data/* ← 16k 行对话、（Audio 27k 行语音档案）               │
   └─────────────────────────────────────────────────────────────────┘
```

**一句话概括该架构**：*以僵尸为肉体、以自定义动画状态机为骨架、以服务端权威的模块化 AI 为大脑、
以"导演 + 离屏账本"为世界，以数据驱动 + 编辑器为内容供给。*

---

## 4. 关键机制拆解（全部附真实代码与行号）

### 4.1 NPC 的肉体：把一只僵尸"改造成人"

`ALifeShellAdapter.lua:94-118`（服务端）——这是整个模组的**原点**，一段代码决定了"僵尸不再是僵尸"：

```lua
shell:setUseless(true)          -- 关掉原版僵尸 AI 的驱动
shell:setCanWalk(true)
shell:setCrawler(false)
shell:setBecomeCrawler(false)
shell:setFakeDead(false)
shell:setForceFakeDead(false)
shell:setReanimate(false)
shell:setReanimatedPlayer(false)
pcall(function() shell:setTarget(nil) end)
setVariable(shell, "ALifeActor", true)      -- 交给自定义动画状态机
setVariable(shell, "ALifeUID", actor.uid)
setVariable(shell, "ALifeGeneration", actor.generation)
local data = shell:getModData()
data.ProjectALifeOwned     = true           -- 对外公开的"所有权"标记
data.ProjectALifeUID       = actor.uid      -- 与逻辑 actor 关联的稳定 ID
data.ProjectALifeGeneration= actor.generation
data.ProjectALifeSpawnedAtMs = getTimestampMs()
data.ProjectALifeConduct   = actor.memory and actor.memory.conduct or nil
data.ProjectALifeFlashlight= ShellAdapter.carriesLight(actor) or nil
```

共享层的对应实现 `shared/.../Shells/ALifeAIFence.lua:626-641`：

```lua
local function markOwned(shell)
    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeOwned = true
        data.ProjectALifeActor = true
    end)
    local ok = pcall(function() shell:SetVariable("ALifeActor", "true") end)
    if not ok then pcall(function() shell:setVariable("ALifeActor", "true") end) end
end
```

**要点（可直接抄的 5 条）**

1. **载体选择**：不要试图从零造一个 `IsoGameCharacter` 子类（Lua 造不出来），而是**劫持原版僵尸**——
   僵尸已经具备寻路、碰撞、动画、受击、掉落、网络同步、存档序列化。
2. **必须先"断电"**：`setUseless(true)` + `setTarget(nil)` + 关掉 crawler/fakeDead/reanimate 一族开关，
   否则原版僵尸 AI 会与你的 AI 抢方向盘。
3. **两个标记**：`modData.ProjectALifeOwned`（Lua 世界可见、可被其它 mod 兼容判断，50 处引用）
   + `SetVariable("ALifeActor","true")`（**动画状态机可见**，见 4.2）。二者缺一不可。
4. **稳定身份**：僵尸实体随区块卸载会消失，所以逻辑身份（`ALifeUID` + `generation`）放在 actor 账本里，
   实体只是"当前附身对象"。`generation` 用来识别"同一个 UID 的第 N 次实体化"。
5. **全 pcall 化**：所有引擎调用都包 `pcall`，失败则走降级/回收路径（`ShellAdapter.lowerFailed` → `removeFromWorld`）。
   这是 PZ 模组在版本漂移下能长期存活的必要条件。

### 4.2 最独特的技术：改写僵尸的动画状态机（225 个自定义动画节点）

僵尸默认只会"蹒跚/撕咬/翻栅栏"。A-Life 让它**走路、换弹、开枪、包扎、坐下、敬礼、挥手**——
做法是在僵尸的动画集目录里**注册新的动画节点**，并用自定义变量把它们挂进状态机。

`common/media/AnimSets/zombie/pathfind/alife_human_walk.xml`（真实文件全文节选）：

```xml
<animNode>
    <m_Name>ALifeHumanPathWalk</m_Name>
    <m_AnimName>Bob_Walk</m_AnimName>          <!-- 直接借用玩家骨骼动画 -->
    <m_Priority>30</m_Priority>
    <m_ConditionPriority>30</m_ConditionPriority>
    <m_Looped>true</m_Looped>
    <m_SpeedScale>ALifeWalkSpeed</m_SpeedScale> <!-- 速度缩放可被 Lua 变量驱动 -->
    <m_Conditions><m_Name>bMoving</m_Name><m_Type>BOOL</m_Type><m_Value>true</m_Value></m_Conditions>
    <m_Conditions><m_Name>ALifeActor</m_Name><m_Type>BOOL</m_Type><m_Value>true</m_Value></m_Conditions>
    <m_Conditions><m_Name>ALifePace</m_Name><m_Type>STRING</m_Type><m_Value>walk</m_Value></m_Conditions>
    <m_Events><m_EventName>Footstep</m_EventName><m_TimePc>0.15</m_TimePc><m_ParameterValue>walk</m_ParameterValue></m_Events>
    <m_Events><m_EventName>Footstep</m_EventName><m_TimePc>0.60</m_TimePc><m_ParameterValue>walk</m_ParameterValue></m_Events>
</animNode>
```

`common/media/AnimSets/zombie/bumped/alife_reload_rifle.xml`（换弹：由 `BumpType` 字符串触发，动画结束回写变量）：

```xml
<animNode>
    <m_Name>ALifeLongarmRefill</m_Name>
    <m_AnimName>Bob_Reload_Rifle_Load</m_AnimName>
    <m_Priority>5</m_Priority>
    <m_Looped>false</m_Looped><m_EarlyTransitionOut>true</m_EarlyTransitionOut>
    <m_SpeedScale>0.78</m_SpeedScale><m_BlendTime>0.18</m_BlendTime><m_BlendOutTime>0.28</m_BlendOutTime>
    <m_Conditions><m_Name>BumpType</m_Name><m_Type>STRING</m_Type><m_Value>ALifeLongarmRefill</m_Value></m_Conditions>
    <m_Events><m_EventName>SetVariable</m_EventName><m_Time>End</m_Time>
              <m_ParameterValue>BumpAnimFinished=true</m_ParameterValue></m_Events>
</animNode>
```

覆盖情况（实测统计）：**225 个 XML**，按原版动画状态目录分类：

| 目录 | 数量（示例） | 用途 |
| --- | --- | --- |
| `bumped/` | ~110 | 主动作库：`alife_attack_{punch,knife,1h,2h,spear,rifle,handgun,floor,stomp,chainsaw}`、`alife_reload_*`、`alife_rack_*`、`alife_draw_*`、`alife_bandage_*`、`alife_sit_*`、`alife_{yes,no,shrug,salute,wave,insult,thumbs_up}` |
| `pathfind/` / `walktoward/` / `walktoward-network/` | 各 22 | 移动：`alife_human_{walk,run,sprint}`、带武器行走（步枪/手枪/长矛/双手近战）、潜行、跛行、`alife_horde_sprint1..5` |
| `climbfence/` / `climbwindow/` | 12 | 翻栅栏/翻窗（含持枪版本） |
| `hitreaction/` `hitreaction-hit/` `getup-fromOn{Back,Front}/` `lunge/` `lunge-network/` `idle/` | 24 | 受击、起身、冲刺、12 种持械待机 |
| `lua/…/client/…/Creator` 配套 `42.20/media/AnimSets/alife-creator/*/preview.xml` | 11 | Creator 编辑器里预览动作 |

Lua 侧的驱动方式（`shared/ProjectALife/Shells/ALifeAnimations.lua`，API 调用频次实测）：

| 调用 | 次数 | 含义 |
| --- | --- | --- |
| `shell:resetModelNextFrame()` | 9 | 强制重建模型/动画状态（换装、换武器后必须） |
| `shell:setPrimaryHandItem / setSecondaryHandItem` | 12 | 手持物（影响动画分支） |
| `shell:setBumpType("ALife*")` | 2 | **主动作触发通道**：把自定义动作名喂给状态机 |
| `shell:setBumpFall / setBumpDone / setBumpFallType` | 5 | 动作结束/失败状态机握手 |
| `shell:setHitReaction / setKnockedDown / setOnFloor / setFallOnFront` | 4 | 受击表现 |
| `shell:GetVariable / SetVariable` | 4 | 与 XML 条件/事件双向通信 |
| `shell:getActionStateName()` | 2 | 读取当前动作状态，做互斥判断 |

**结论（本节是全报告最值钱的一条）**：
"让僵尸做出人的动作"不需要 Java、不需要自制骨骼，只需要
① 在 `media/AnimSets/zombie/<原版状态目录>/` 放 `animNode` XML，把玩家动画（`Bob_*`）挂进去，
② 用 `SetVariable("ALifeActor","true")` 给你的 NPC 打上"走这套动画"的标签，
③ Lua 侧用 `setBumpType()` 触发动作、读 `GetVariable("BumpAnimFinished")` 判断动作结束。
这是**纯数据 + 纯 Lua** 就能达成的效果，也是该模组"看起来像真人"的根本原因。

### 4.3 调度器：10Hz 心跳 + 时间片预算（这是"不卡"的关键）

入口极简，`server/ProjectALife/Core/ALifeServerBootstrap.lua` 全文核心（真实文件）：

```lua
require "ProjectALife/Core/ALifeRuntime"
require "ProjectALife/Core/ALifeLifecycle"
require "ProjectALife/Core/ALifeSettings"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Interface/ALifeStatusService"
require "ProjectALife/Admin/ALifeDebugService"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Core/ALifeExecutor"

if not ProjectALife.ServerBootstrapRegistered and type(Events) == "table" then
    ProjectALife.ServerBootstrapRegistered = true
    local Runtime = ProjectALife.Runtime

    local function add(name, callback)                    -- 事件注册防抖封装
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
    end

    local function start() Runtime.safeStart(ProjectALife.Settings.runtimeOptions()) ... end

    add("OnGameStart", start)
    add("OnServerStarted", start)
    add("OnTick", function()                              -- 唯一的每帧入口
        local ok, reason = pcall(Runtime.tick)
        if not ok then
            Runtime.lastError = "bootstrap_tick:" .. tostring(reason)
            ProjectALife.Telemetry.emit("runtime_fault", { subsystem = "bootstrap", error = reason })
        end
    end)
    add("EveryOneMinute", function() ... Runtime.flush() ... end)
    add("OnSave",          function() ... ProjectALife.OrphanGuard.recordSaved() ... end)
    add("OnZombieDead",    function(shell) Runtime.timeHook("hook_death", ProjectALife.Lifecycle.onShellDeath, shell) end)
    add("OnCreatePlayer",  function(first, second) ProjectALife.Reputation.sync(second or first) end)
    ProjectALife.AIFence.register(); ProjectALife.StatusService.register()
    ProjectALife.DebugService.register(); ProjectALife.Executor.register()
end
```

`shared/ProjectALife/Core/ALifeExecutor.lua`（2,860 行）的默认节拍（真实配置表，文件头）：

```lua
settings = {
    tickIntervalMs        = 100,   -- 逻辑 10Hz，不是每帧
    reportIntervalMs      = 1000,
    mirrorIntervalMs      = 1000,  -- 服务端每秒广播一次全员镜像
    auditIntervalMs       = 500,
    decisionBudgetMinimum = 6,     -- 每次调度至少处理 6 个决策
    reportRateLimitMs     = 200,
    reportOwnerQuietMs    = 2000,
    deathStampGraceMs     = 60000,
    ...
}
```

**先纠正一个常见误解**：`ALifeExecutor`（2,860 行 / 132 KB）**不是协程池**——全文 `coroutine` 命中 0 次，
`Events.` 也命中 0 次（它自己在 `:2825-2857` 注册事件）。它实际是
**"谁有权驱动这个 NPC"的权限仲裁器 + 分帧配额执行器**。
主循环 `Executor.tick()`（`:2624-2648`）：100 ms 节流 → `audit(500ms)` / replicas / prune →
按固定顺序跑子系统链，每个子系统**带独立配额**：

```lua
-- 实测配额（Core/ALifeRuntime.lua:686-790）
动作/外壳  = clamp(ceil(#order / 5), 2, 24)
spawn      = 1        population = 5      lifecycle = 8
orphan     = 16       movement   = 4      animations = 8      admin_queue = 1
-- 决策配额（ALifeExecutor.lua:2593-2596）
budget = max(6, min(24, ceil(#order / 3)))
```

再加一层"毫秒硬预算"：`Decisions.lanes.budgetMs = 12` + `budgetSpent()` 到点即 `break`
（`ALifeDecisionLoop.lua:1301, 1452-1455, 1466-1488`），以及 `ActionLedger` 的
`priorityBudget=8` 优先道 + `Ledger.cursor` 游标轮转（`ALifeActionLedger.lua:283-315`）。
每个子系统调用都被 `pcall` 隔离（`Executor.step`，`:2573-2578`）。

**性能设计要点（可直接搬）**

1. **逻辑与渲染解耦**：`OnTick` 只做"到点才干活"，`tickIntervalMs=100`（10Hz）——
   NPC 拟真不需要 60Hz，这是把 100+ NPC 塞进单机 CPU 的第一道保险。
2. **预算制**：`decisionBudgetMinimum` 等预算参数 + `EveryOneMinute` 做批量 flush，
   把昂贵的世界运算（离屏推进、存档写入）摊到低频钩子。
3. **弱引用表防泄漏**：`ALifeAIFence` 的所有 per-实体记账都用
   `setmetatable({}, { __mode = "k" })`（弱键），实体被引擎回收后记账自动消失：

   ```lua
   local Fence = {
       owned    = setmetatable({}, { __mode = "k" }),
       rejected = setmetatable({}, { __mode = "k" }),
       voicedShells = setmetatable({}, { __mode = "k" }),
       nextVoiceSweepAtMs = setmetatable({}, { __mode = "k" }),
       ...
   }
   ```

   → **这是 PZ 长时段模组最容易被忽视的崩溃源**：用普通 table 缓存实体 → 区块卸载后表越滚越大 → 存档卡死/内存爆。
4. **三层可观测性**：`Telemetry`（事件级）、`Watchdog`（卡死检测）、`BlackBox`（黑匣子，`shared/.../Admin/ALifeBlackBox.lua` 64KB）
   + `Admin/ALifeDebugService.lua`（168KB）+ `ALifeDiagnostics.lua`。**出问题能自证**是这类模组能被社区接受的前提。
5. **作者在沙盒提示里写下的真实性能预算**（`Translate/EN/Sandbox.json` 原文摘录，含金量极高）：

   > "IF THE GAME STUTTERS, TURN THIS DOWN FIRST. Everything this mod costs in frame time comes from
   > how many people the world is carrying, and this one setting decides that."
   >
   > "Insane deliberately goes past the mod's own hard caps: up to **220 live hostiles (tested ceiling 120)**,
   > **24 outposts (12)**, **4 per town (2)**, **12 outdoor camps (6)** and **8-strong scout parties (3)**.
   > It is not tested at those numbers -- expect a heavier server, expect bugs, and back up your save first."

   默认值：**18 个离屏小队、每个据点 2 个任务小队**；作者的测试上限是 120 个同屏敌意 NPC。
   → 也就是说，**一个人规模的模组，性能红线大约在"同屏 100 量级 NPC + 20 个离屏小队"**。
6. **护栏阈值可以直接抄**（全部为实测默认值）：

   | 护栏 | 阈值 | 位置 |
   | --- | --- | --- |
   | 主 tick 节流 / 预算 | `tickIntervalMs=100`、`tickBudget=8` | `Core/ALifeRuntime.lua:70-71` |
   | 卡顿分级 | `hitchThresholdsMs={16,33,50,100}`、`hitchWindowMs=60000` | `ALifeRuntime.lua:79-80, 482-600` |
   | 超时归因 | 单 tick > 100 ms → overruns + `slowestSubsystem` + 10 s 限流上报 `runtime_slow_tick` | `ALifeRuntime.lua:791-805` |
   | 决策慢 tick | 30 s 窗口均值 ≥ `slowTickMs=8` → `[ALIFE-PERF] decisions` | `ALifeDecisionLoop.lua:1331, 1359-1369` |
   | 外壳帧采样 | 每 30 帧采样，60 s 窗口上报 `npcs/avg/max/over4/over8/over16` | `ALifeAIFence.lua:131-132, 164-177` |
   | 观察降频 | `observeEvery=30`（每 30 帧才仔细观察一次） | `ALifeAIFence.lua:660, 2536-2540` |
   | Telemetry 限流 | 环形缓冲 capacity 96；lifecycle 500/突发 40；offline 突发 5、30/分 | `Admin/ALifeTelemetry.lua:4, 10-15` |
   | 沙盒实时上限 | `capsFor` clamp 0~500，`applyLiveCaps` 热更新 | `Core/ALifeSettings.lua:540-606` |
   | 模板缓存 | `memoLimit=256` 的 lower/ground 记忆表（重复查表不重算） | `ALifeAIFence.lua:34-38, 705-740` |

### 4.4 多人同步：搭原版"僵尸归属"的车，而不是另造一套

PZ 多人里每个僵尸本来就归属于某个客户端模拟（`getOwnerPlayer()`）。A-Life 没有另起炉灶，而是
**复用这套归属模型 + 服务端仲裁 + 自研镜像协议**：

```lua
-- shared/ProjectALife/Core/ALifeExecutor.lua
function Executor.serverTick(now)                      -- 服务端：只做对账与广播
    if not Executor.serverDelegates() then return 0 end
    Executor.settleDeaths(now)                         -- 结算死亡
    Executor.auditOwners(now)                          -- 审查归属漂移
    if Executor.adapters.transmit == nil and ProjectALife.MirrorTransport.available() then
        return ProjectALife.MirrorTransport.tick(now)  -- 优先走专用镜像通道
    end
    if now - Executor.lastMirrorAtMs < Executor.settings.mirrorIntervalMs then return 0 end
    Executor.lastMirrorAtMs = now
    local store = mirrorStore()
    local built = Executor.buildMirror()               -- 打包所有 actor 的姿态
    ... store.records, store.died = ... ; transmitMirror()
end

function Executor.authorityFor(shell)                  -- 客户端：我有没有权模拟它
    if shell ~= nil and Executor.byShell[shell] ~= nil then
        local uid = Executor.byShell[shell]
        if not Executor.entryMatches(shell, uid, Executor.executed[uid]) then return false end
        return ProjectALife.ShellSimulation.isOwner(shell) == true
    end
    ...
end

function Executor.engineOwner(shell)                   -- 直接问引擎：这具身体归谁
    if shell == nil or type(shell.getOwnerPlayer) ~= "function" then return nil end
    return shell:getOwnerPlayer()
end
```

防作弊/防错位的硬编码阈值（真实表，`ALifeExecutor.lua:359` 附近）：

```lua
Executor.authority = {
    unownedTrustRadius = 80,     -- 无主 NPC：只信 80 格内的客户端上报
    playerHitMaxRange  = 80,     -- 超过 80 格的"我打中了"不接受
    noiseReporterRadius= 100,
    noisePerPlayerMs   = 150,    -- 每玩家噪声上报限流
}
```

绑定校验（防"抢别人 NPC"）：

```lua
function Executor.entryMatches(shell, uid, entry)
    if entry == nil or entry.shell ~= shell then return false end
    local currentUid, generation = identityOf(shell)
    return currentUid == uid and generation == entry.generation   -- UID + 世代号双校验
end
```

**镜像通道 `ALifeMirrorTransport`（299 行）的真实参数**：

```lua
-- shared/ProjectALife/Core/ALifeMirrorTransport.lua:5-8, 195-233
intervalMs = 1000, interestRadius = 250, maxRecipients = 4,
budgetMs = 6, fullIntervalMs = 30000, requestIntervalMs = 2000
-- 增量帧结构
frame = { stream, sequence, full, records, removed, present, catalog, warfare, bases, died }
sendServerCommand(player, "ProjectALife", "executorMirror", frame)          -- :204
sendClientCommand("ProjectALife", "executorMirrorRequest", {})             -- :233 客户端主动请求
-- 序列断档 → requestFull() 并累计 gaps（:242-247）
```

兜底通道：`Executor.MIRROR_TAG = "ProjectALife.Mirror.v1"` + `ModData.transmit`（`ALifeExecutor.lua:314-323`）
配合 `Events.OnReceiveGlobalModData`（`:2839`）。

**非权威端绝不做本地预测**——外壳入口直接短路，只跑外观（`shared/.../ALifeAIFence.lua:1023-1028`）：

```lua
if (Executor.serverDelegates()) or (spectatorSide() and not ShellSimulation.isOwner(shell)) then
    Fence.applyCosmetic(shell)
    return true
end
```

"我是不是 owner"最终由引擎事实决定：`Sim.isOwner` = `isClient() and not shell:isRemoteZombie()`
（`Shells/ALifeShellSimulation.lua:201-206`）。血量这类关键状态用**单向指令 + ACK**
（`executorHealth` → owner 回 `shellHealthAck`，服务端校验 `getOwnerPlayer() == player` 才确认，`:250-282`）。

**多人设计结论（本节 5 条）**

1. **权威模型不要自创**：跟原版一样"谁拥有身体谁模拟"，服务端只做 **归属审查 + 死亡结算 + 状态广播**。
2. **身份 = UID + generation**，绝不依赖实体指针或实体 ID（实体随时消失/复用）。
3. **一切来自客户端的上报都要过"距离 + 频率 + 绑定"三重校验**，否则联机就是外挂天堂。
4. **死亡是最难的同步点**：A-Life 为此写了 `diedFrame / pushDeath / trackDeath / settleDeaths / corpseState`
   一整套状态机，并给 `deathStampGraceMs = 60000`（60 秒宽限）容错网络抖动。
   单人开发时**不要把死亡同步留到最后做**，它通常是联机 bug 的最大来源。
5. 事件选型实测分布（`grep -rhoE "Events\.[A-Za-z0-9_]+"` 频次）：
   `OnGameStart(47)`、`OnTick(45)`、**`OnServerCommand(39)`**、`OnServerStarted(16)`、**`OnClientCommand(12)`**、
   `OnPreUIDraw(11)`、`OnZombieUpdate(6)`、`OnWeaponSwing(6)`、`OnPreFillWorldObjectContextMenu(6)`、
   `OnPlayerDeath(6)`、`OnHitZombie(6)`、`OnZombieDead(4)`、`EveryOneMinute(4)`
   → **联机通信靠 `OnServerCommand`/`OnClientCommand` 自建协议**，这是 PZ MP 模组的通行做法。

### 4.5 内容管线：自定义文本格式 + 单一 Codec + 创作者编辑器

这是本模组**最容易被低估、却最值得抄**的部分。它把"AI 系统"变成了"内容平台"。

#### 4.5.1 阵营/NPC 数据：不是 JSON，是自研的行式文本格式

`common/alife_runtime/catalog/` 下两个文件承载全部内容：

| 文件 | 行数 | 体积 | 条目 |
| --- | --- | --- | --- |
| `faction_registry.alife` | 12,477 | 315,025 B | **148 个 `faction`** |
| `npc_profiles.alife` | 157,591 | 3,797,856 B | **780 个 `member`** |

格式（真实头部，`faction_registry.alife:1-20`）：

```
@alife-records 1

faction alife_kettle
  about.title Kettle Works Crew
  about.heading Industrial Salvagers
  about.blurb A large salvage gang out of the works yard...
  stance.player neutral
  reinforce.rule any
  reinforce.means ground
  reinforce.squad 3
  presence.peaceable false
  presence.encounters roamer|scavenger_crew|camp|broken_car
  presence.odds 0.35
  habits.flee on
  habits.scavenge on
end
```

`member`（NPC 档案）的字段分组：`who.*`（faction/title/odds/voice/trade）、
`body.*`（sex/tone/hitPoints/might/stamina/alertness/marksmanship）、`look.*`（hair/beard + Tint RGB）、
`mind.*`、`kit.*`、`radio.*`、`loot.*`、`attire.<槽位>`、`arms.main/side/closeIn`、`rounds.main/side`。

**为什么要自研格式（作者的取舍，值得学）**

1. **一份 schema 驱动三种用途**：`Records/ALifeRecordCodec.lua:15-68` 的 `Codec.schema` 用
   "人类字段名 → 点号路径"映射把**磁盘目录、Creator 表单、分享码**统一在一套定义上：

   ```lua
   Codec.schema = {
       ["faction.spawn"]  = {"presence", { ... }},
       ["member.general"] = {"who", { name = "who.title", ... }},
       ...
   }
   ```
   `ALifeCatalogParser.lua:8-15` 只有 3 行，直接转发给 `decode`。
2. **780 条档案 3.8 MB 逐行读**（`ALifeCatalog.lua:16-45`：
   `getModFileReader("ProjectALifeNPCs", relative, false)`），比把它编译成 Lua 表更省内存、加载更快。
3. **可人肉 diff / 可社区 PR**：文本格式让 148 个阵营的内容更新不必碰代码。

#### 4.5.2 对话与语音：**数据占了 40% 的代码量**

| 数据 | 规模 | 格式 |
| --- | --- | --- |
| `Talk/Data/*.lua` 18 个文件 | 16,184 行 / ~16,091 条 | 行式 DSL：`r("DONT_SHOOT","Lower yours and I'll lower mine.","tmp=seasoned,veteran|st=neutral,careful")` |
| 前缀分布 | `r(` 6,541 应答、`s(` 3,857 场景、`b(` 3,742 bark、`seg(` 1,260、`y(`/`n(` 272/269、`i(` 150 意图 | 门控字段 `reg/role/tmp/st`（逗号列表）+ `mood/day/hour`（区间） |
| `Audio/ALifeVoiceWorkbenchProfiles.lua` | 16,848 行 / 1.13 MB / **133 个 `registerProfile`** | 纯数据：`label/tone/gender/sourcePack/readyClips/coveredEvents/usableCounts/sampleSounds` |
| `Audio/ALifeVoiceProjectProfiles.lua` | 6,213 行 / 0.59 MB / **42 个档案** | 同上（延迟注册 `VoiceProjectRegister(Catalog)`） |

门控条件写在字符串里、由运行时 `parseGate` 解析（`ALifeDialogueData.lua:24-45`）。
`ALifeVoiceCatalog.lua:13-55` 定义事件契约（`priority/chance/cooldownMs/groupCooldownMs/actorLockMs/interrupt`），
`ALifeVoiceAssignment.lua:9-49` 把 factionId → `{male,female}` 语音档案池，`ALifeFactionVoiceStyles.lua:5-27`
再把 factionId → 风格 → "事件 → 台词池"。

> **给单人开发者的冷水**：27,216 行音频数据 + 19,469 行对话是"活人感"的真正来源，
> 也是单人**最不可能一次补齐**的部分。裁剪方案见第 6 章（先用 3 个派系 × 30 条 bark 验证闭环）。

#### 4.5.3 世界数据：预生成的压缩块

`World/ALifeMapZones.lua` 只有 **57 行**却是 140 KB——每行是一条超长分号压缩的 `x,y,w,h` 串，
自带统计 `counts = { roads = 5097, towns = 2670, water = 889 }`（全文 8,633 个 `;`）。
`ALifeRoadGraphShipped.lua` 359 行，`schema = 4, signature = "shipped:Muldraugh, KY;schema=4"`，
共 119 个 `id = "` 的节点/边条目。

→ **这是"离线模拟能在没有实体时沿道路行走"的数据基础**，且明确是**预生成导出**（非手工标注）：
   先用工具从地图数据提取路网/城区/水域，压缩成脚本文件随模组发布，运行时零解析成本。

#### 4.5.4 创作者编辑器（Creator）：值得做，但要这样组织

`client/ProjectALife/Interface/Creator/` 16 个文件，主体 `ALifeCreatorCore.lua` 334 KB。
**全项目 0 处 `ISScrollingListBox`**——滚动全靠 panel 自身 `setScrollChildren/addScrollBars/setScrollHeight`。

用到（按出现次数）：`ISPanel(62)`、`ISButton(11)`、`UIFont(175)`、`Clipboard(9)`、`MainScreen(6)`、
`ISModalDialog(5)`、`ISUI3DModel(3)`、`ISTickBox(3)`、`ISColorPickerHSB(3)`、`ISSliderPanel(2)`、
`ISComboBox(2)`、`ISUIRadio/ISUIElement/ISTextEntryBox/ISLabel/ISColorPicker` 各 1。

构建模式（**Core 只做原语，业务页分文件挂同一个表**）：

```lua
-- ALifeCreatorCore.lua:6095-6107
Creator.buildIdentityPage(window, formW)
Creator.buildAppearancePage(window, formW)
Creator.buildFacesPage(window, formW)
Creator.buildLoadoutPage(window, formW)
Creator.buildCombatPage(window, formW, compact)
Creator.buildBehaviorPage(window, formW)
Creator.buildModulesPage(window, formW)
```

```lua
-- 每个子模块首行 require Core，然后把函数挂到同一张表
require "ProjectALife/Interface/Creator/ALifeCreatorCore"
function Creator.buildLoadoutPage(window, formW) ... end
-- 唯一的汇总点：ALifeCreatorScreen.lua:1-13 逐个 require，并挂 Events
```

表单原语是 Core 里的工厂：`addButton(724)`、`addLabel(753)`、`addTextEntry(768)`、`addCombo(777)`、
`addTick(806)`、`slider(1075)`——底层都是 `ISPanel:new` + 自绘 `prerender` +
一个 `displayBackground=false` 的 `ISButton` 当点击热区（Core:976）。

#### 4.5.5 COPY CODE / LOAD CODE：把模组依赖变成用户能看懂的提示

分享码格式（`ALifeFactionShare.lua:416-426`）：

```lua
function Share.toCode(text)
    local units, count = Share.toUnits(text)
    if count > Share.maxBytes then return nil, "pack_too_large" end
    local tokens, size = Share.compress(units, count)          -- 自研 LZ 压缩
    return Share.codeHeader .. "-" .. string.format("%d", count) .. "-"
        .. string.format("%d", Share.checksum(units, count)) .. "-"
        .. Share.base64(tokens, size)                          -- ALIFEPACK1-<字节数>-<校验和>-<base64>
end
```

- 导入先 `unfence` 去掉 Markdown 的三反引号围栏；**> 32,000 B 不写剪贴板，改落盘**
  `Zomboid/Lua/ALifeFactionCode.txt`（Core:5075-5080）。
- 导出时把依赖写进 `needs` 块（mod id / workshop / title / items）；
  导入时 `Share.missingFor` 用 `getScriptManager():FindItem(fullType)` 反查 `script:getModID()`，
  缺什么就弹 `ISModalDialog`「Import it anyway?」，并把完整清单打印到 console.txt（Core:5176-5205）。

#### 4.5.6 沙盒选项：118 个旋钮 = 118 个"玩家可自救"的开关

`42.20/media/sandbox-options.txt`：716 行 / **118 选项 / 6 页**，首行 `VERSION = 1,`。

```lua
option ALife.Preset_World = {
    type = enum, numValues = 5, default = 3,
    page = ProjectALife_1General, translation = ProjectALife.PresetWorld,
    _tooltip = ProjectALife.PresetWorld_tooltip,
    valueTranslation = ProjectALife.PresetWorld,
}
```

类型分布：`boolean 48` / `integer 45` / `enum 13` / `double 12`；
页分布：`4Behavior 31` / `2Population 23` / `5Combat 22` / `6Raids 20` / `1General 15` / `3Encounters 7`。
**B42 没有独立 page 声明块**——页标题由 `page = ProjectALife_1General` 直接走翻译键 `Sandbox_ProjectALife_1General`。

#### 4.5.7 本地化：**对英文原文做内容哈希**（很聪明的偷懒法）

`Translate/EN/` 只有 2 个 JSON（B42 格式）：`IG_UI.json`（1,046 行 / 1,044 键）、`Sandbox.json`（312 行 / 310 键）。

```json
{
    "IGUI_ALifeUI_21188c281b8c66a2": "Edit NPC...",
    "IGUI_ALifeUI_19f832dc31da0a46": "Persistent",
```

`ALifeText.lua:20-45` 用两条 djb2 变体（`a*33+c mod 2147483647`、`b*131+c mod 2147483629`）
对英文原文算出 16 位十六进制键，`Text.ui(en, vars)` = `getTextOrNull("IGUI_ALifeUI_"..hash(en))`，
查不到回退英文原文；带 `ctx` 时把上下文并入哈希。

- **优点**：代码里只写英文，改文案不会撞键，翻译只需产出 `Translate/<LANG>/IG_UI.json`。
- **代价**：键不可读，翻译必须"跑一遍中文游戏 → 从日志回捞 `IGUI_ALifeUI_*`"。
- 本仓库已有的中文翻译流程（见 `docs/pz_translation_json_format.md`）可直接对接：
  本模组只发英文，其余语言由社区单独发补丁——这本身就是一个可参与的低门槛切入点。

#### 4.5.8 兼容层：探测 + 存原函数 + 守卫 + 幂等 install

14 个适配器（shared 9 + client 4）+ 一张 `known` 清单（`ALifeModCompat.lua`，19 KB）：
每条含 `name` + `verdict`（`compatible/adapted/partial/unsupported/incompatible`）+ 一句人话 `note`。
**Guns of Marz 没有适配器文件**——它是声明式 `compatible`（`ALifeModCompat.lua:38-39,50-51`）；
`BanditsWeekOne`、`ProjectALifeReconstructed` 声明 `incompatible`。
`Compat.activeSet()` 用 `getActivatedMods()` 判定，`Compat.shipsFile()` 用 `getModFileReader`
探测别的 mod 是否真带了某文件（`:114-135`，用于区分同名 fork）。

最小适配器全文（`ALifeCyesPushDoorsAdapter.lua`，39 行）：

```lua
local Adapter = { installed = false }
ProjectALife.CyesPushDoorsAdapter = Adapter

function Adapter.isOurs(character)
    if character == nil or type(character.getModData) ~= "function" then return false end
    local hasData = type(character.hasModData) ~= "function" or character:hasModData() == true
    if hasData then
        local data = character:getModData()
        if type(data) == "table" and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true) then
            return true
        end
    end
    local uid = type(character.GetVariable) == "function" and character:GetVariable("ALifeUID") or nil
    return uid ~= nil and uid ~= ""            -- 变量兜底：尸体上布尔会被清掉
end

function Adapter.install()
    if Adapter.installed then return true end
    local doors = CyesPushDoors
    if type(doors) ~= "table" or type(doors.getImpactTargetType) ~= "function" then return false end
    local original = doors.getImpactTargetType
    doors.getImpactTargetType = function(object)
        if object ~= nil and Adapter.isOurs(object) then return nil, "alife-npc" end
        return original(object)
    end
    Adapter.installed = true
    return true
end
```

更精巧的一例：`ALifeWeaponRefreshGuard.lua:12-26` 先遍历 `getLoadedLua(i)` 找到另一个 mod 的
`WeaponSystems/Utils/Animations.lua` 才 `require` 并替换 `CallSyncHandWeaponFields`——
既不硬依赖也不误伤。

### 4.6 【核实】作者公开声明 vs 代码实际行为：`ProjectALifeOwned` 只对了一半

工坊描述里写着"**每个** A-Life 尸体都有 `zombie:getModData().ProjectALifeOwned == true`"，实测**不成立**：

| 项 | 实测 |
| --- | --- |
| 全项目引用 | 50 处 |
| **写入点** | 只有 5 个：`ShellAdapter.lua:108`、`AIFence.lua:628`、`AnimationClient.lua:255`、`:338`（写 `true`）；`ShellSimulation.lua:34`（`markCorpse` **写 `nil`，即清除**） |
| 其余 45 处 | 全部是读取（服务端 33 / 共享 7 / 客户端 5） |

```lua
-- shared/ProjectALife/Shells/ALifeShellSimulation.lua:34 附近
data.ProjectALifeOwned = nil          -- 尸体上布尔被清掉，只留 ProjectALifeCorpseOf / ProjectALifeCorpseAtMs
```

**结论**：活体 NPC 上该标记成立；**尸体上会被显式置 nil**。因此任何"靠 `ProjectALifeOwned` 认领尸体"
的第三方兼容代码都会失效——正确判据是 `ProjectALifeOwned or ProjectALifeActor` **再加
`GetVariable("ALifeUID")` 兜底**，这也正是该项目 12 个适配器里 `isOurs()` 一律写成三元表达式的原因。

> **方法论提示**：这条差异是本报告的"元经验"——**模组作者的公开文档 ≠ 引擎/代码的真实契约**。
> 本仓库既有的 `docs/rolling_log.md` 也已踩过同类坑（`guides/workshop-txt-guide.md` 里 5 条字段描述与实际解析不符）。
> 凡是准备依赖别的模组的公开约定，都要回到**代码或引擎字节码**验证一次。

### 4.7 决策架构：模块注册表 + 优先级链 + 三车道时间预算

**不是行为树，也不是一个大状态机**，而是三层结构（这是最值得照抄的 AI 骨架）：

**(a) 全局模块注册表**——57 个模块分布在 20 个 `ALifeModule*.lua` 里，`shared/ProjectALife/Behaviours/ALifeModuleRegistry.lua:101-141`：

```lua
function Registry.register(definition)
    local kind = Registry.resolveKind(definition.kind)   -- doctrine/orders/reaction/craft/upkeep
    local dispatch = definition.dispatch or defaultDispatch[kind]
    local module = { id = id, kind = kind, dispatch = dispatch,
        primary = definition.primary == true,
        priority = tonumber(definition.priority) or Registry.priorities[id] or 500,
        evaluate = definition.evaluate }
    Registry.modules[id] = module; Registry.order[#Registry.order + 1] = module
    sortModules(); invalidate()
```

**(b) 按 dispatch 分派优先级链**——`dispatchKinds = {decision, response, positioning}`；
优先级表（数字越小越先问）：`orders=10, flee=30, stealth=30, panic=34, warning=40, withdraw=45,
cover=50, strafe=60, medic=85, healing=90, patrolRest=92, stance=95, investigate=100, search=117,
scavenge=118, spread=150, groupMarch=200`。

```lua
-- Registry.lua:212 —— "第一个返回非 nil 的模块胜"，每个模块都被 pcall 隔离
for index = 1, count do
    local module = chain[index]
    if (only == nil or module.id == only) and Registry.allows(actor, module.id) then
        local ok, result = pcall(module.evaluate, actor, shell, context)
        if ok then
            if result ~= nil then return result, module.id end
        else
            Registry.lastError = module.id .. ": " .. tostring(result)   -- 单模块出错不拖垮整帧
        end
    end
end
```

**四层开关**（第一天就该设计好，否则无法单独关掉某个行为做调试）：
`Registry.setEnabled(id)`（`:147`）→ 全局 `ProjectALife.ModuleSwitches.get(id)`（`:156-165`）→
每 NPC 覆写 `memory.moduleOverrides[id]`（`:173-182`）→ 行为档案 `ProjectALife.BehaviorProfiles.allows`（`:199-201`）；
`primary=true` 的模块（leader/conduct）还要求 `memory.conduct == id` 才放行（`:184-190`）。

**(c) 每 NPC 的"状态机"只是一个轻量表** `{kind, intent, cooldownUntilMs}`，写进 modData 供外部观测
（`Decisions/ALifeDecisionLoop.lua:125-131`）：

```lua
local function stampState(shell, state)
    local data = Combat.dataOf(shell)
    data.ProjectALifeBehaviorState  = state.kind
    data.ProjectALifeBehaviorIntent = state.intent
```

**(d) 决策频率 = 三车道 + 硬预算**（`ALifeDecisionLoop.lua`，这才是 100+ NPC 不卡的根本）：

```lua
Decisions.lanes = {
    hotRadius = 45,   hotIntervalMs = 150,     -- 玩家 45 格内：150ms 想一次
    farRadius = 110,  farIntervalMs = 1500,    -- 110 格内：1.5s
    refreshMs = 1000, budgetMs = 12, roundMinimum = 2,
    passiveHotMs = 250, passiveFarMs = 2500, passiveMidMs = 1000,
}
-- Decisions.tick (ALifeDecisionLoop.lua:1457)
if processed >= maximum - reserve or (processed > 0 and spent()) then break end
```

外层统一预算：`Runtime.tickIntervalMs = 100`、`decisionBudget = clamp(#Decisions.order / 5, 4, 24)`
（`Core/ALifeRuntime.lua:693-695`）；`Decisions.profileTick`（`:1359`）做 30 秒窗口统计，
均摊 ≥ 8 ms 时打印 `[ALIFE-PERF] decisions`。

> **一句话工程结论**：**"每个 NPC 每帧思考一次"是 PZ 模组的性能自杀方式**。
> 正确姿势 = 按距离分车道决定思考频率 + 全局每帧毫秒预算 + 每 NPC 冷却闸 + 单模块 pcall 隔离。

### 4.8 感知与听觉：自研射线优先，引擎 `CanSee` 只作带熔断的备选

**视线（LOS）双通道**（`shared/ProjectALife/Senses/ALifeSight.lua:24-37`）：

```lua
local result = LosUtil.lineClear(cell, x, y, z, x2, y2, z2, false)   -- 原版射线工具
-- 用 LosUtil.TestResults.Blocked / ClearThroughClosedDoor 分类（:6-22）
```

引擎 `shell:CanSee(candidate)` 是**第二选择**，且做了严格限流 + 熔断
（`Senses/ALifePerception.lua:556-595`）：每 33 ms 一帧、每帧上限 48 次（`:494-497`），
触顶返回 `"held"`，连续失败进入 3 秒熔断。可见性回退链：
`LineOfFire.tileRayClear`（`Combat/ALifeLineOfFire.lua:159-167`，同样基于 `LosUtil.lineClear`）
→ `hasClearBoundary`（`:218`）→ 贴身接触判定 `sightByContact`（`:548`，2.25 平方内 + `isBlockedTo`）。

**记忆与衰减**：帧级缓存 `rememberSight/rememberedSight`（`:523-537`），
`sightReentryHoldMs=250`、`sightFaultHoldMs=3000`；长期记忆挂 `actor.memory.*`。

**听觉：没有"只听玩家喊话"的偷懒实现**，而是自研声源标记表（`Senses/ALifeInvestigation.lua:32-52`）：

```lua
-- 声源条目：超上限丢最旧
{ kind = ..., x = ..., y = ..., z = ..., radiusSquared = ..., untilMs = ...,
  group = ..., consumed = ..., target = ..., source = ... }
```

- 喊话：`Investigation.noteShout`（`:229`，半径 45、存活 25 s）→ `shoutReactions`（`:163`，
  `shoutReactRadius=30`、`shoutHeardCap=1`），30 ms 间隔 + `shoutIntervalMs=1500` 防刷。
- 枪声：开火路径直接注入 `investigation.note(x, y, z, weapon:getSoundRadius() or 40, 15000, groupId)`
  （`Combat/ALifeCombatStrike.lua:870-880`）。
- 事件：`Events.OnWeaponSwing`（`ALifeInvestigation.lua:156`）→ 玩家挥击即制造噪声；
  `Events.OnClientCommand`（`:260`）接收客户端上报的 shout。
- 警觉等级（`shared/ProjectALife/Senses/ALifeAwareness.lua:3-34`）：
  `asleep .12 / busy .3 / houseNight .35 / resting .45 / watch 1.0`，哨兵强制 1.0。

### 4.9 移动与破障：原版寻路 + 132 KB 的"对抗原版状态机"补丁

**寻路直接用原版**（`Movement/ALifeMovement.lua:240,252,258,317-328,370-390`）：

```lua
behavior:pathToLocationF(x, y, z)
shell:changeState(PathFindState.instance())                     -- :258
...
pcall(function() shell:setTarget(nil) end)
shell:changeState(ZombieIdleState.instance())                   -- :387-390
```

用到的原版状态单例：`PathFindState`(6 次)、`ZombieIdleState`(11)、`ClimbOverFenceState`(2)、
`ClimbThroughWindowState`(2)。

**翻越/开门/破门**（`Movement/ALifeObstacleTraversal.lua`，132 KB）：

| 目标 | 真实 API | 行号 |
| --- | --- | --- |
| 开窗 | `shell:faceThisObject(window)` / `shell:openWindow(window)` / `window:ToggleWindow(shell)` | :208-212 |
| 翻窗 | `window:canClimbThrough(shell)` → `shell:climbThroughWindow(window)` / `climbThroughWindowFrame(frame)` | :221-243 |
| 开门 | `instanceof(o, "IsoDoor"/"IsoThumpable")` → `object:ToggleDoorSilent()` | :250-259, :486 |
| 门禁判定 | `isLocked / isLockedByKey / isObstructed / isBarricaded` | :284, :476-477 |
| 破障 | `beginBreach` 自研耐久 `integrityOf/giveWay/swingsNeeded` + **占位认领** `Traversal.breachClaims[claimKey]` | :986-1038, :1013-1020 |

**最脏的一段是"收拾原版攀爬/翻窗残留状态"**（`:1116-1147`）——必须清理这 13 个原版变量名：

```
ClimbingFence, ClimbFenceStarted/Finished/Outcome/Flopped,
ClimbWindowStarted/End/Finished/Outcome/Flopped, VaultOverRun, VaultOverSprint, BlockWindow
```

然后 `shell:changeState(ZombieIdleState.instance())`、`setIgnoreMovement(false)`、
`setHideWeaponModel(false)`、`setVariable bPathfind/bMoving=false`、`resetModelNextFrame()`。

另一个入口 `Fence.leaveNativeState`（`shared/.../ALifeAIFence.lua:682-688`）用
`shell:getActionStateName()` 读状态名，再 `clearAggroList()` 打断原版 `lunge / turnalerted / attack / thump`。

> **复刻警告**：不写这层"状态清洗守卫"，症状就是**永久卡窗、飞天、滑步**。
> 建议第一天就把它抽成独立模块（对应 `AIFence.leaveNativeState` + `Traversal.leaveNativeState`）。
> 另注：**全项目没有一处 `IsoStairs`/`setIsOnStairs`**——楼层切换完全交给原版寻路的第三个坐标参数。

**多人约束**：`isServer()` 下 `climbThroughWindow` 不可用，必须走客户端权威（`ObstacleTraversal.lua:223`）；
多个 NPC 抢同一扇门窗要加占位认领（`breachClaims`、`Traversal.reservations`、`Tactics.claimsFor`），
否则会出现"叠人打转"。

### 4.10 战斗：**完全自研弹道，引擎只负责"演"**

**关键负向证据**（全仓库 grep 命中数为 0）：`DoAttack`、`setAimTarget`、`setAttackType`、
`setUseHandWeapon`、`Ballistics`/`IsoBullet`、`getStateMachine`/`changeState(string)`、
`getStats():setPanic`、`IsoStairs`、`ISInventoryPane`、`IsoGameCharacter`（改用 `instanceof(x, "IsoZombie"/"IsoPlayer")`）。

命中率完全自算（`Combat/ALifeCombatStrike.lua:820-845`）：

```lua
local dist = math.sqrt(Combat.distanceSquared(shell, target))
local chance = Combat.baseHitChance(weapon, shell, dist)
aiming = tonumber(data.ProjectALifeAiming) or 5
local burstPenalty = math.max(0, burstIndex - 1) * 900 * rangePenaltyScale
chance = math.max(800, math.min(10000, chance + math.floor((aiming - 5) * 220) - math.floor(burstPenalty)))
chance = math.floor(chance * Combat.aimScaleFor(shell, target))
chance = math.floor(chance * Combat.rangeFalloff(weapon, shell, dist))
if type(ZombRand) == "function" then rangedHit = ZombRand(10000) < chance end
```

伤害结算（`ALifeCombatStrike.lua:270-320, :609-620`）——自研标量血 + 原版体伤/血迹：

```lua
if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.setHealth(target, remaining)
else target:setHealth(remaining) end
healthSystem.onDamage(attacker, target, zone, remaining, maximum)
bodyDamage:AddDamage(BodyPartType.Torso_Upper, power * 8)
if remaining <= 0 then pcall(function() target:Kill(attacker) end) end
-- 打玩家则走原版：Combat.adapters.applyDamage (:514-516)
```

表现层（"演出"）：`ALifeCombatFire.lua:406-419 presentShot` → `shotDescriptor` +
`muzzleLight`（`IsoLightSource` / `cell:addLamppost`，`:373-404`）+ 客户端 `Tracer.shot`；
`missCue` 用 `sendPlaySound` 或 `square:playSound`（`:421-433`）。

血量/伤口**双轨制**：服务端自研标量血（`ShellSimulation.setHealth/maximumFor/standardHealth`，
`serverHealthScale=0.06`，并有 `trueHealth/reconcileHealth/bookShielded` 做联机对账）；
伤口/流血/倒地写 modData（`ALifeHealth.lua:117-154`）：`ProjectALifeWounds`、`ProjectALifeLastWoundZone`、
`ProjectALifeBleedOutAtMs`、`ProjectALifeDownedUntilMs`、`ProjectALifeHandsBusyUntilMs` 等，
并用原版 `target:addBlood(BloodBodyPartType.X, true, true, false)`（`:95-112`）。

武器/弹药也是自研管理：`item:getCurrentAmmoCount()` / `setCurrentAmmoCount(rounds)` /
`item:setContainsClip(...)`（`Combat/ALifeWeapons.lua:24, :54-55, :179, :230, :475`）、
`weapon:getWeaponReloadType()`、`weapon:getWeaponPart("Scope")`、`getSoundRadius`、`getAimingTime`。

> **为什么不用引擎攻击**：NPC 是僵尸壳，没有 `IsoPlayer` 的射击框架；硬接原版弹道要跟
> `IsoPlayer` 的瞄准/后坐/弹道链死磕。自研命中 + 引擎表现是**成本最低、可控性最高**的组合——
> 代价是必须自己保证"看起来像真的"（曳光、枪口火光、声音半径、点射节奏）。

### 4.11 恐惧、小队战术、关系与声望

**恐惧：完全自研，不用原版恐慌**（`getStats():setPanic` / `Moodles` 命中 0 次）。
`Fear/ALifeModulePanic.lua:166-201`：

```lua
if not Registry.allows(actor, "panic") then return false, "module_off" end
if Panic.exempt(memory.conduct) then return false, "calm_by_identity" end  -- 精锐不慌
if Panic.holdingPost(actor) then return false, "holding_post" end
local taken = Panic.fearRoll(memory, key, now, options.percent, Panic.roll100())
if not taken then ... return false end
data.ProjectALifeFearUntilMs = now + Panic.settings.fearHoldMs
```

去重维度：`memory.panicSpentFor/panicSpentAtMs`（同一场交战只慌一次）、`squad.panicAtMs`（小队冷却）、
`memory.fearSpentAtMs/fearMemoryMs`；分流 `Panic.scrambleFor` → `cover` / `freeze` 二选一；
触发源 `Panic.onAimedAt`（玩家 `isAiming`）、`Panic.onShot`。模块：`id="panic", kind="reaction", priority=34`。
逃跑 `flee`（无枪 + 面对持枪者）、脱离 `withdraw`（`dispatch="positioning"`）。

**小队命令是一张纯表**（`Behaviours/ALifeModuleLeader.lua:65-76` → `DecisionLoop.setOrder`）：

```lua
accepted = decisions.setOrder(uid, actor.generation, {
    kind = kind, anchor = anchor, untilMs = untilMs, quiet = true, source = "leader" }) == true
```

`setOrder`（`ALifeDecisionLoop.lua:1242-1275`）只接受 `follow|hold|patrol`，**校验 generation 防复活体串号**，
且 **leader 命令不得打断正在交火的成员**（`:1254-1256 order_member_engaged`）。
小队状态 = 每成员 `actor.memory` 的同名字段 + `Leader.groups[groupId]`
（`beatMs=1500 / orderMs=20000 / rallyDistance=20`）。

**"分工"不是角色名，而是按稳定哈希分环位**（`Combat/ALifeSquadTactics.lua:66-73, :218-219`）：

```lua
function Tactics.role(actor)
    return ({ "assault", "flank_left", "flank_right", "support" })[roleIndex(actor) + 1]
```

再由 `Tactics.combatDestination`、`holdArcSlot`、`ringShared/claimsFor` 把角色落成具体落点
（含 `role == 3 → rear = -2` 的错位排布）。**医疗/破门是独立模块**，由注册表优先级竞争产生，
而不是队长点名——这是"涌现行为"而非"脚本演出"的关键设计。

**关系四态**：`friendly|neutral|careful|hostile`（`Decisions/ALifeRelations.lua:23-43`），
基线 = 出生立场 + 阵营/职业关系层；记忆挂 `actor.memory.spawnStance`、`memory.robberyTruce[key]`。

**声望是"玩家维度"的全局持久化，不放在 NPC 身上**（`Decisions/ALifeReputation.lua:44-63`）：

```lua
if ModData ~= nil and type(ModData.getOrCreate) == "function" then
    result = ModData.getOrCreate(Reputation.TAG)
end
if result.schema == nil then result.schema = Reputation.SCHEMA; result.players = {}
elseif result.schema ~= Reputation.SCHEMA then return nil, "reputation_schema_unsupported:" .. tostring(result.schema) end
```

带 **schema 版本守卫**；`provokedForgetHours = 24`；事件驱动 `onPlayerDamagedActor / onPlayerKilledActor /
onPlayerProvoked / onPlayerDied` + 升级表 `Reputation.escalation` + 联机 `snapshotFor/sync/send/flush`。

**目标身份回收防护**（`Decisions/ALifeTargetPolicy.lua:35-62`）——PZ 会复用实体对象，必须做：

```lua
-- 身份三件套
identityOf = ProjectALifeUID + ProjectALifeGeneration + getOnlineID()
function TargetPolicy.canAttack(...) ... if not sameIdentity(...) then return false, "target_recycled" end
```

**复仇** = `Perception.noteAttacker / retaliationTarget / grudgeHolds`（`Senses/ALifePerception.lua:106-176`）
+ `Perception.grudgeShieldMs = 10000`。

### 4.12 世界层：7 个导演 + 离屏小队账本

**离屏小队就是一张挂在 ModData 的表，没有任何实体**（`Offline/ALifeSquadLedger.lua:4-5,166-184`）：

```lua
TAG = "ProjectALife.Squads.v1", SCHEMA = 1   -- ModData.getOrCreate(TAG)，默认上限 24 队 / 8 人
local squad = { id = id, revision = 1, state = "offline", x = ..., y = ..., nodeId = ...,
    route = {}, task = { kind = "idle" },
    members = { { profileId, health, identitySeed, gear } },
    supplies = 35, morale = 0.65, foundedHours = ..., decisionDueHours = ... }
```

**时间尺度用游戏小时，不用真实秒**（`Offline/ALifeOfflineDirector.lua:63-68`）：
`worldHours()` 取 `getGameTime():getWorldAgeHours()`；真实秒只用于节流：
`tickSeconds=20`、每队错峰 `squadClocks[id].nextMs`、单切片预算 `squadsPerSlice=2` / `squadSliceMs=3`（`:41-42`）。

**"沿道路以步行速度前进"**（`:158-160, 790-822`）：

```lua
travelTilesPerHour = 150
if q.legHours == nil then q.legHours = legHours(len, Offline.settings.travelTilesPerHour) end
local t = (hours - q.legStartedHours) / q.legHours
if t >= 1 then q.x, q.y, q.nodeId = node.x, node.y, to
else local p = Graph.interpolate(from, to, t); q.x, q.y = p.x, p.y end
```

**道路图三级来源**（`:180-216`）：
① `ModData["ProjectALife.RoadGraph.v1"]` 缓存（**带 `getWorld():getMap()..schema` 签名失效**）；
② 随包烘焙数据 `ALifeRoadGraphShipped.lua`（`signature="shipped:Muldraugh, KY;schema=4"`）；
③ 否则运行时构建：`Graph.buildStep(budgetMs)` 状态机 `gather→cluster→link→anchor→connect`，
gather 用 `getWorld():getMetaGrid():getZonesIntersecting()` 拉 zone 矩形；
寻路是 Dijkstra 打表 `Graph.routesFrom/treeFrom/route`。

**离屏战斗是属性对拼，不是概率抽奖**（`Offline/ALifeOfflineCombat.lua:66-74,144-155`）：

```lua
power  = Σ(health/100 * weaponScore(profile)) * (0.65 + morale * 0.7) * wobble(0.82~1.18)
ratio  = powerWin / powerLose
loserCasualties  = ratio > 2   and 2 or 1
winnerCasualties = ratio < 1.3 and 1 or 0
cooldownUntil = hours + 6
```

`meetDistance=25`、`playerKeepOut=110`（玩家附近不结算）；结果进 `pending` 队列，
每 tick 只应用 `applyPerBeat=10` 条。武器分档见 `:23-29`（AssaultRifle 10 … Bat 3）。

**跨天复仇**（`Offline/ALifeRevenge.lua:98-122`）：

```lua
local contract = { playerKey = ..., dueHours = hours + 48 + roll() * 25,
    lastKnown = { x, y }, backupSize = 2 + math.floor(roll() * 4), casualties = tally.count }
Ledger.update(fresh.id, fresh.revision, function(q) q.revenge = contract end, true)
-- 全员阵亡则把契约转交 squad.homeOutpostId
```

**实体化两阶段**（`Offline/ALifeRenderProtocol.lua:132-149, 332-347`）：玩家进 80 格才把账本译成实体规格，
**一次只放 1 名成员、间隔 1250 ms**；玩家离开 120 格或名单空 3 秒才回收，
回收时 `dehydrate(uid, "render_out")` 把血量/坐标/路径写回账本；`state="wiped"` 且过 24 游戏小时才删除。

**7 个导演由一个 tick 轮转驱动**（`Core/ALifeRuntime.lua:70, 626-629, 718-764`），
按 `ticks % 10 == slot` 分槽：slot1 Offline、2 Outposts、3 BaseHeat、4 Raid、5 Meta、6 Encounter、7 Populate。

| 导演 | 职责 | 周期/阈值 | 驱动来源 |
| --- | --- | --- | --- |
| `Director` | 野外小队生成 | `encounterIntervalHours=6` + `encounterChance=0.15` | 时间窗 + `spawnMultiplier` |
| `EncounterDirector` | 遭遇（含 raid/fullscale_raid） | `intervalMinutes=60`, `chance=0.25` | `BaseHeat.target(player).mult` × `WorldPressure.at(hours)` × 早期 × outbreak |
| `RaidDirector` | 大规模突袭 3 波 + 直升机 | `minDay=14`, `cooldownDays=14`, `checkEveryMinutes=10` | 先派 3 人侦察 `scoutBuildupHours=6` |
| `PopulateDirector` | 城内持久人口 | `scanBudgetMs=4`, `auditMs=30000` | `percent={rare=10,uncommon=20,common=35}` |
| `MetaDirector` | 枪声/直升机/车祸等非实体事件 | `minGapMinutes=90` | 天数曲线 |

压力函数是纯时钟衰减：`Pressure.at = 1（≤3 天）→ 0.35（≥21 天）`（`World/ALifeWorldPressure.lua:18-23`）。
`BaseHeat` 每 10 游戏分钟扫描玩家 40 格，按路障/金属/载具/建墙加权，`decayPerDay=0.10`，
超 30 分锚定据点，突袭后 3 天宽限（`World/ALifeBaseHeat.lua:9-22, 91-128`）。

> **这是"活世界感"的全部秘密**：世界不是等玩家来触发，而是有**自己的时钟、自己的账本、自己的因果**——
> 离屏小队会互相打、会记仇、会隔几天带更多人回来。玩家看到的只是这个模拟偶尔"实体化"的一小部分。

### 4.13 据点系统：脚本放原版对象 + 数据驱动 op 列表

九种预设全是 Lua 表（`shared/ProjectALife/Outposts/ALifeOutpostPresets.lua`）：
`police_station(:64)`、`sturdy_house(:99)`、`fortified_field_base(:125)`、`forest_camp(:185)`、
`field_hospital(:217)`、`supply_depot(:253)`、`holdout_house(:292)`、`alexandria(:313)`、
`bridge_checkpoint(:343)`；`class` 只有 `building|clearing`。
**注意：没有 `tier` 字段**——分层是靠 `garrison.max` / `lifetime` / `minDay` 表达的（描述里的"Tier"是玩家说法）。

运行时站点记录（`Outposts/ALifeOutpostRegistry.lua:4, 112-127`）：

```lua
TAG = "ProjectALife.Outposts.v1"
site = { id, revision = 1, presetId, state = "proposed",
    cityKey, bounds = { x1, y1, x2, y2, z }, factionId, hostileToPlayers,
    props = {}, garrison = {}, squads = {}, backups = 0, commsDisabled = false, thefts = 0 }
```

**建造不是"NPC 施工"，而是脚本直接放原版对象**（`Outposts/ALifeOutpostBuilder.lua:437, 604, 682, 1019`）：

```lua
local object = IsoObject.new(getCell(), square, texture); square:AddTileObject(object)
object = IsoThumpable.new(getCell(), square, sprite, north, info)   -- 路障 600 HP
object = IsoDoor.new(getCell(), square, sprite, north)
object = IsoRadio.new(getCell(), square, texture)                   -- 失败降级 IsoObject
-- 服务端同步：object:transmitCompleteItemToClients()
```

计划是**数据驱动的 op 列表**（`mark_entrance / lock_door / barricade_door / barricade_window`，`:170-193`）；
调度 `Director.tick` 每 `intervalMinutes=30` 掷 `chancePercent=20` 提出新据点，
状态机 `proposed → built → garrison`（`ALifeOutpostDirector.lua:24-33, 2041-2072`）。

### 4.14 持久化：世界态进 ModData，分享内容才落盘

| 数据 | 存放 | 键/文件 |
| --- | --- | --- |
| 小队账本 | `ModData.getOrCreate` | `ProjectALife.Squads.v1` |
| 世界态 | 同上 | `ProjectALife.World.v1`（`ALifePersistence.lua:4, 36-37`） |
| 据点 | 同上 | `ProjectALife.Outposts.v1` |
| 区域锁 / 路网缓存 | 同上 | `ProjectALife.RegionLocks.v1` / `ProjectALife.RoadGraph.v1`（带地图签名） |
| 玩家自定义阵营 | 文件 | `Zomboid/Lua/alife_custom_factions.ini`、`alife_server_factions.ini` |

写文件走 `Migration.writeFile` → `getFileWriter(fileName, true, false)`（`Records/ALifeRecordMigration.lua:29-72`）。
**迁移策略是"永不就地改写，一律旁置"**：`isCurrent()` 判定老格式，
生成 `.old.N.ini` / `.bad.ini` 备份，`migration.recordLine` 用正则识别新旧记录行（`:8-27, 41-58, 165-191`）。

服务端权威四道门（`Records/ALifeCustomFactionAuthority.lua:221-267`）：
`Codec.decode` 语法 → 逐 section 白名单（`Custom.typedSections/textSections`）→
形状与 id 正则 `^[%w_%-]+$`（`#factions == 1` 且 `faction.id == expectedId`）→
`MAX_TEXT_BYTES = 2,000,000` 限制 → 通过后 `applySync → catalog.reset/load` 热重载；
文本按 `MAX_CHUNK_BYTES = 8000` 切片存 ModData。

**Admin/可观测**：`Admin/ALifeDebugService.lua` 是唯一命令入口
（`Events.OnClientCommand`，约 90 条白名单命令：`debugSquadMap / debugBuildOutpost / debugEncounterMarks /
debugActors / debugPurgeActors / debugRepair / debugTownCensus / debugCatalog / raidStart / debugForceSupport` …），
诊断类命令另有 `diagnosticsAllowed(player)` 权限门（`:361-378, 185-198`）。
`Admin/ALifeBlackBox.lua` 是**每实体 48 槽环形缓冲**（`ringSize=48`），
记录移动/寻路/卡死/重复 uid，异常自动 `saveReport` 落盘，并有 `dup-uid` 这类检测器。
小队地图：猴补丁 `ISWorldMap.ShowWorldMap` + `ISPanel:derive` 叠加层，
数据走 `sendClientCommand(player, "ProjectALife", "debugSquadMap", {})` 请求、服务端 `squadMapReply` 返回。

### 4.15 生命周期：**"卸载 ≠ 死亡"**（A-Life 最容易被忽视的一半工程量）

这是本模组最"重工业"的部分，也是最容易在个人项目里崩掉的地方。三种"NPC 不见了"必须严格区分：

| 状态 | 判定依据 | 真实阈值 | 处置 |
| --- | --- | --- | --- |
| **区块卸载** `unloadedLoss` | `getCurrentSquare() == nil` 且目标格 `cell:getGridSquare() == nil`；或 `Population.windowEdge(pos) < 4` | — | 记为 **lost**，不是死亡；回到范围后可恢复 |
| **引擎剔除** `culledLoss` | 专用服 + 未死 + 不在房间/无屋顶 + 所有玩家距离 > `cullSightTiles = 70` | 70 格 | 判为引擎剔除（`parkEngineCulls = true`），保留账本 |
| **真死亡** | `Lifecycle.onShellDeath` | — | 走完整死亡流水线（见下） |

丢失判定的完整参数（`Core/ALifeWatchdog.lua:6-27`）：
`lossGraceMs=2000`、`recheckMs=250`、`maximumMisses=3`、`maximumRecoveries=2`、
`maximumStep=20`、`recoveryStabilityMs=10000`、`settleAfterMs=5000`、
`lostTtlMs=1800000`（30 分钟）、`lostRadius=3`、`lostCap=64`。
恢复走 `Watchdog.forceRecovery` → `Ledger.cancelActor` + `ShellAdapter.recoverShell`（`:587-611`）。

**死亡流水线**（`Core/ALifeLifecycle.lua:340-413`）：

```
Lifecycle.onShellDeath
  → DeathInventory.restore                     -- 归还手持物，否则掉落不全
  → 禁止 reanimate（setReanimate(false) 等）
  → Registry.markDead                          -- 失败则进 Lifecycle.pending 重试队列（:282-306, 415-456）
  → finishPhysicalDeath                        -- Decisions.forget / DeathDrops.process / Watchdog.unbind / markCorpse
  → trackCorpse
  → KillAttribution.resolve                    -- 击杀归因（谁打死的）
  → 报复 / 声望结算 / 被偷战利品掉地            -- :230-280
```

**尸体回收**：`Lifecycle.settings = { corpseRemovalMs = 1200000, corpsePlayerDistance = 30, corpseBudget = 2 }`
（`:25-30`）；`sweepCorpses` 逐格扫 `square:getDeadBodys()`，匹配 `ProjectALifeUID` 后
`square:removeCorpse(body, false)`（`:77-96, 121-150`），`Lifecycle.tick(8)` 每 tick 最多 8 个。

**OrphanGuard 防的"孤儿"到底是什么**：
modData 上仍带 `ProjectALifeOwned/UID`，但 Registry/Watchdog 已不再认领它
（Actor 已 dead，或 `generation` 不匹配）的僵尸 —— 即"失去主人却未被回收的残留体"。
识别 `identity`（`Core/ALifeOrphanGuard.lua:37-50`）、归属判定 `ownedByRuntime`（`:65-88`，
含 6000 ms 出生宽限、`isDead`、被抓住的尸体、Actor lifecycle + generation 一致性）；
处置为 `cleanup` 删除（`:90-106`，发 `orphan_shell_removed`）或 `disarm` 仅卸下武器（`:139-153`）；
每 tick 扫 16 个（`ALifeRuntime.lua:739`）。

**跨存档"幽灵方块"**（防止 NPC 在存档边缘被复制出来）：
`Persistence.bucket("savedShells")` 记录已死/残留的方块 + outfit + session，
`recordSaved`（`:222-249`，`ghostTtlHours = 168`、`ghostCap = 600`）、
`savedGhost`（`:275-308`，`ghostSightMs = 10000`、`ghostJumpTiles = 8`），由 `Events.OnSave` 触发。

**还原的三条出口**（决定"这个模组能安全卸载"的承诺是否成立）：

| 出口 | 实现 | 结果 |
| --- | --- | --- |
| 死亡 | `ShellSimulation.lua:26-43`：清 `Owned/Actor`、写 `ProjectALifeCorpseOf`、`SetVariable("ALifeActor","false")` | 变成普通尸体 |
| 卸任 | `AIFence.lua:846-857`：`setUseless(false)` / `setNoTeeth(false)` / `setZombiesDontAttack(false)` | **退回普通僵尸**（作者承诺"移除此模组后残留 NPC 变回僵尸"就靠这条） |
| 移除 | `ShellAdapter.lua:244-253` | 彻底删除 |

**清理与校验**：`ShellAdapter.lua:217-238` 按 `"ProjectALife"` 前缀清空 modData 并复位 17 个变量名；
`shellAlive` 用 `square:getMovingObjects():contains()` + `cell:getZombieList():contains()` **双查**（`:260-322`），
并给新生成的壳 2000 ms 出生宽限（`:283-292`）——否则刚出生的 NPC 会被自己的存活性检查误判为丢失。

> **教训**：个人项目最常见的崩溃不是 AI 不会打架，而是 **NPC 随机消失 / 存档后翻倍 / 幽灵残留**。
> 这些全部来自"卸载、剔除、死亡"三者混淆。请把这三态建模成显式状态机，并把每个阈值写成可配置常量。

---

## 5. 引擎边界：B42 到底给了什么、不给什么（全部来自字节码取证）

> 本章结论全部来自 `javap` 反编译 `projectzomboid.jar` 与游戏自带 `media/lua`，
> 完整命令与原始输出见配套文档 **[b42-npc-engine-capability-audit.md](b42-npc-engine-capability-audit.md)**。
> 环境：本机 PZ 42.21.0、`projectzomboid.jar` 为 Java 25 字节码（class 主版本 69，需 JDK ≥ 25 的 `javap`）。

### 5.1 结论一：**B42 没有任何可用的 NPC AI**

```bash
unzip -l projectzomboid.jar | grep -E 'zombie/' | grep -iE 'npc|survivor|companion|humanai'
```

只有 5 个非 RDS 类：`IsoSurvivor(3,277 B)`、`SurvivorDesc(21,442 B)`、`SurvivorFactory`、
`SurvivorFactory$SurvivorType`、`SurvivorGroup`；其余 39 个是 `randomizedWorld/randomizedDeadSurvivor/RDS*`
（**尸体摆放场景**，无行为）。

`javap -p IsoSurvivor` → 只有 `Despawn()`、`getObjectName()`、`reloadSpritePart()` + 3 个构造器，
`grep -c 'void update'` = **0**。但构造器是**活的**：`getCell().getSurvivorList().add(this)`、
`triggerEvent("OnCreateSurvivor", this)`、`initWornItems("Human")` / `initAttachedItems("Human")`。

→ **`IsoSurvivor` 是"能生成、能穿衣、但没有大脑"的空壳**——B41 的 NPC AI 被摘掉了。
这解释了为什么整个社区都在"拿僵尸当人用"。

**死事件清单**（只在 `LuaEventManager` 注册，全 jar 无触发点，Lua 侧引用 0）：

| 事件 | 状态 |
| --- | --- |
| `OnNPCSurvivorUpdate`、`OnAIStateEnter`、`OnAIStateExecute`、`OnAIStateExit` | **死的**（只有 `LuaEventManager` 命中） |
| `OnAIStateChange` ← `zombie/ai/StateMachine` | **唯一活着的 AI 事件** |
| `OnTriggerNPCEvent` / `OnMultiTriggerNPCEvent` ← `zombie/iso/IsoMetaCell` | 只在**离屏元格子**触发，不在玩家所在格 |

### 5.2 结论二：僵尸 AI 已迁到 ECS，且"关 AI 开关"不完整

`javap -p -c IsoZombie`（495 行）关键事实：

- 驱动入口：`update()` → `private updateInternal()`，**`OnZombieUpdate` 就在 `updateInternal` 内触发**。
- `private updateActiveState()` 已退化成 **3 条指令**（只剩 `GameTime.isZombieInactivityPhase()` → `makeInactive(boolean)`）。
- 状态容器换成 `zombie/characters/component/StateMachineComponent`
  （`getStateMachine()` / `registerAIState(String,State)` / `getDefaultState()` / `getAdvancedAnimator()` / `getActionContext()`），
  在 `IsoGameCharacter.registerECSComponents()` 注册；`IsoZombie.registerECSComponents()` 只额外加 `NetworkZombieComponent`。
- `initializeStates()` 有 **118 次 `registerAIState`**，状态名包括
  `idle attack attack-network bumped climbfence climbwindow eatbody fakedead* falldown* getup* grappled
  hitreaction* knockeddown-* lunge* onground pathfind reanimate sitting staggerback* thump turn
  walktoward* vehicleCollision*` …
- **没有 `bDead` 字段/方法**（`grep -nE 'bDead|setDead'` = 0）；死亡走继承的 `isDead()`。

**最关键的一条**：`setUseless(true)` 是**真开关，但覆盖面有限**——
`useless` 字段的读取方只有 `ZombieIdleState`、`WalkTowardState`、`ZombieGroupManager`、`NetworkZombieVariables`：

```bash
grep -ral isUseless /tmp/pzall     # 仅上述 4 处
```

→ 它**不阻止** `attack` / `hitreaction` / `thump`。这正是 A-Life 为什么还要额外做
`setNoTeeth(true)`、`setZombiesDontAttack(true)`、以及**在 `OnZombieUpdate` 里每帧重申压制**
（`AIFence.nativeStatePolicy` → `changeState(ZombieIdleState.instance())`）。

### 5.3 结论三：角色的"人类能力"只能这样白嫖

`IsoGameCharacter` 可用：`getHealth/setHealth`、`setKnockedDown`、`setPath2(Path)`、`setMoving`、
`isClimbingThroughWindow(IsoWindow)`、`getInventory`、`getPrimaryHandItem/setPrimaryHandItem`、
`isSpeaking/setSpeaking`、`PlayAnim/PlayAnimWithSpeed/PlayAnimUnlooped`、
`setVariable(String,String|boolean|float)`、`getAnimationStateName/getActionStateName`、`getAnimationPlayer()`。

**没有公开的 `shoot()` / `reload()` / `openDoor()` / `useItem()`**；
`checkReloading()` 是 private，开火/开门由 ActionState + TimedAction 驱动。
所以正确做法是复用 Lua 侧现成的 **~200 个 `IS*TimedAction`**
（`media/lua/shared/TimedActions/`，如 `ISBaseTimedAction`、`ISOpenDoor`、`ISClimbThroughWindow`）。

### 5.4 结论四：**Lua 是白名单暴露**，动画类全被挡在外面

`LuaManager$Exposer.shouldExpose` 就是 `exposed:HashSet.contains(cls)`；
`exposeAll()` 常量池共 **1,001 个类**（含 `IsoZombie/IsoPlayer/IsoGameCharacter/IsoSurvivor/SurvivorFactory/
IsoCell/IsoGridSquare/IsoDeadBody/ModData/LuaEventManager`）。

**不在名单**（`grep -cE 'AnimationPlayer|AdvancedAnimator|ActionState|ActionContext'` = 0）：
`AnimationPlayer`、`AdvancedAnimator`、`AnimEvent`、`ActionState`/`ActionContext`、
`StateMachineComponent`、`GlobalModData` 本体。

→ `getAnimationPlayer()` 拿得到对象却**调不了方法**。Lua 唯一的动画入口是角色上的转发方法
（游戏自己的 Lua 也这么用：`media/lua/shared/Vehicles/TimedActions/ISOpenVehicleDoor.lua:21`
`self.character:PlayAnim("Idle")`）。

> **可复用的排查姿势**：判断"Lua 能不能调 X"，先查 `LuaManager$Exposer.exposeAll()` 的类常量池，
> 再**沿父类继承链**查方法——`javap` 只列**声明**方法，
> `getModData` 实际声明在 `zombie.iso.IsoObject` 上（IsoObject→IsoMovingObject→IsoGameCharacter→IsoZombie），
> 不往父类查就会误判"僵尸不能存 modData"。

### 5.5 结论五：事件、线程与"活 list"

从 `LuaEventManager` 常量池提取出 **264 个事件名**，NPC 相关的真实触发点：

| 事件 | 真实触发类 | 说明 |
| --- | --- | --- |
| `OnZombieUpdate` | `IsoZombie`（`updateInternal` 内） | **每只僵尸的主更新钩子**——A-Life 的 `AIFence` 就挂这里 |
| `OnPlayerUpdate` | `IsoPlayer`（`updateInternal2` 内） | — |
| `OnTick` | `GameWindow`、`IngameState` | 主线程 |
| `EveryTenMinutes/EveryOneMinute/EveryHours/EveryDays` | `GameTime` | 主线程 |
| `OnAIStateChange` | `zombie/ai/StateMachine` | 唯一活着的 AI 事件 |
| `OnZombieCreate` | `VirtualZombieManager` | — |
| `OnZombieDead` | `IsoZombie` + `IsoGameCharacter` | — |
| `OnCreateLivingCharacter` | `IsoPlayer` + `IsoSurvivor` | NPC 生成可挂 |
| `OnCreateSurvivor` | `IsoSurvivor` | 空壳生成时 |
| `OnPostMapLoad` | `CellLoader` | — |
| `OnObjectAdded` | **只在 `network/packets/AddItemToMapPacket`** | 容易误解，别当通用地图事件 |
| `LoadGridsquare/ReuseGridsquare` | `WorldStreamer`/`IsoChunk`/`IsoChunkMap`/`ErosionMain`/`ServerMap$ServerCell` | 区块生命周期 |
| `OnSave/OnPostSave/OnServerStartSaving/OnServerFinishSaving` | `GameWindow` 等 | 存档 |
| `OnInitGlobalModData` | `GlobalModData` | — |
| `OnCharacterDeath` | `IsoGameCharacter` + `IsoAnimal` | — |

**线程语义（已证实）**：`IsMainThread()` = 与 `KahluaThread.debugOwnerThread` 同线程；
`triggerEvent(String)` 里若非主线程则走 **`QueueEvent` 入队**，由主线程 `RunQueuedEvents()` 延后执行
→ **非主线程事件回调里的参数对象可能已过期，绝不要缓存实体引用**。

**性能护栏（极其重要的一条）**：

```bash
javap -p -c zombie/iso/IsoCell.class | grep -A2 getZombieList
# 字节码 = getfield zombieList; areturn  → 返回引擎内部 ArrayList 本体，不是副本
```

对比 `getObjectListForLua()` 才带 `ForLua` 语义。→ **Lua 遍历 `getCell():getZombieList()` 是直接读活 list**：
引擎同帧 add/remove 会导致 `ConcurrentModificationException` 或漏项；
**绝不能 add/remove/clear**，只读并**立刻拷进自己的表**。
而且它没有分帧/限流/可见性过滤（返回整个 cell），也没有并发问题（`OnTick` 全在主线程）——
**预算必须自己管**：重决策放 `EveryTenMinutes`，`OnTick` 只做常数时间 + 自己的轮转指针。

### 5.6 结论六：**没有 NPC 存档层**，持久化要自己设计

- `IsoZombie`/`IsoGameCharacter` **没有自己的 `getModData()`**，它来自 `zombie.iso.IsoObject`
  （`getModData():KahluaTable` / `hasModData` / `transmitModData`，继承链 IsoObject→IsoMovingObject→IsoGameCharacter→IsoZombie）。
- 全局：`zombie/world/moddata/GlobalModData`（`getOrCreate/exists/remove/add/transmit/save/load`）
  + Lua 门面 `zombie/world/moddata/ModData`（**在暴露名单内**）。
- 文件读写：`LuaManager$GlobalObject.getFileWriter(String,boolean,boolean)` 的基准目录是
  `LuaManager.getLuaCacheDir()`，且校验 `LuaManager.ALLOWED_FILE_EXTENSIONS`；
  `getModFileWriter(modId,name,...)` 会用 `ChooseGameInfo.getModDetails(modId).getCommonDir()`
  → **写回 mod 自身目录，Workshop 场景不可靠**。推荐 `getFileWriter("MyMod/x.txt", true, true)` 或 ModData。
- `zombie/savefile/` 只有 `PlayerDB`/`ServerPlayerDB`/`ClientPlayerDB`/`AccountDBHelper`/
  `SavefileNaming`/`SavefileThumbnail` → **没有任何 NPC 存档层**。

### 5.7 结论七：纯 Lua 还是 ZombieBuddy（Java 补丁）？决策表

本机已装 ZombieBuddy（`JAVA_DIR/ZombieBuddy.jar`，**实测版本 2.3.4**，不是旧文档里的 2.3.2；
工坊内容 `3619862853`，文档 `<mod>/doc/ModdingGuide.md`、`doc/LuaAPI.md`）。
它提供 Lua 侧 `ZombieBuddy.Events.getAll/getByName/getByFile`、`ZombieBuddy.Watches.Add/Remove/Clear`
（监控任意 Java 方法 + 参数），Java 侧 `Exposer.exposeClass/exposeMethod/exposeClassToLua/exposeAnnotatedClasses`
+ `@Exposer.LuaClass`、`@LuaMethod(name=..., global=true)`、`PatchEngine` + `me.zed_0xff.zombie_buddy.Patch`。

| 需求 | 纯 Lua + 僵尸载体 | ZombieBuddy Java 补丁 |
| --- | --- | --- |
| 生成/销毁/换装/动画/说话 | ✅ | — |
| 每帧决策/感知/寻路 | ✅（`OnZombieUpdate` + `getZombieList` + `pathToLocationF`） | — |
| **改写原版僵尸 AI 的某个状态** | ❌（只能 `setUseless`/`setTarget(nil)`/`setKnockedDown` 压制） | ✅ `@Patch StateMachine/ZombieIdleState` |
| **新增 AI 状态 / 加 ECS 组件** | ❌（`registerAIState`、`StateMachineComponent` 未暴露） | ✅ |
| 直接用 `AnimationPlayer` / `ActionState` | ❌ 未暴露 | ✅ `Exposer.exposeClass` |
| **每只僵尸的独立逐帧回调** | ❌ 只有全局 `OnZombieUpdate` | ✅ 插桩 `IsoZombie.update` |
| 交付成本 | 低（无构建、无审批、无版本脆性） | 高（构建 + 签名/审批 + 版本脆性） |

**A-Life 的选择是纯 Lua**——它用"每帧重申的围栏 + 自研一切"换来了"订阅即玩、零第三方依赖"，
这正是它敢在工坊描述里写"只有 Lua、纹理、模型、声音和纯文本数据"的底气。

### 5.8 引擎结论（10 条）

1. B42 **没有任何可用 NPC AI**；`IsoSurvivor` 是留壳。
2. **必须自己实现**：感知、决策、群体调度、寻路节流、目标选择、逐帧轮转、存档结构、交互 UI、性能预算。
3. 僵尸是唯一现成活动载体；冻住它需要 `setUseless(true)` + `setTarget(null)` + `setKnockedDown(true)`/`inactive` 组合。
4. **能白嫖**：模型/贴图/装备（`initWornItems`）、`PlayAnim` + `setVariable`、`getPath2/setPath2`、
   `pathToLocationF`、`IsoGridSquare` 查询、`IsoDeadBody`、约 200 个 `IS*TimedAction`、`GameTime`、`ModData`/`GlobalModData`。
5. **走不通**：`OnAIStateEnter/Execute/Exit`、`OnNPCSurvivorUpdate`（死事件）；
   `OnTriggerNPCEvent`（只在离屏）；`AnimationPlayer`/`StateMachineComponent`/`ActionState`（未暴露）；
   `getZombieList()`（活 list，别改、别在遍历里缓存对象）。
6. **没有 NPC 存档层**，自建（`IsoObject.getModData()` / `GlobalModData` / `getFileWriter` 注意扩展名白名单）。
7. 线程安全但**不是免费**：非主线程事件延后执行，回调参数别缓存。
8. 决策树：批量简单 NPC → 纯 Lua + 僵尸载体；要新 AI / 精确动画 / 改原版状态 → ZombieBuddy Java 补丁。
9. 判断"Lua 能不能调 X"的固定姿势：先查 `exposeAll()` 类常量池，再沿父类链查方法。
10. **未验证项（诚实标注）**：① `inactive`/`makeInactive(true)` 是否足以完全阻断 `update`（未做运行时实验）；
    ② `getObjectListForLua()` 是否真为拷贝（按命名 + 签名推断）；
    ③ `OnTick` 是否严格每渲染帧（由调用点推断）。**本次未启动游戏**，全部结论来自字节码与游戏自带 Lua。

---

## 6. 从零开发路线图（单人可执行的裁剪版）

### 6.1 先接受三个现实

1. **这不是一个人几周的活**：146,518 行 Lua + 225 个动画节点 + 780 个 NPC 档案 + 27,216 行语音数据。
   作者署名 "Vice and the A-Life team"。
2. **但它的核心闭环可以被一个人复刻到"可用"**：僵尸载体 → 调度 → 感知 → 战斗 → 数据化阵营 → 关系记忆。
   这部分约 **3,000~6,000 行 Lua**，是 2~4 个月的业余工作量。
3. **永远不要一开始就做离屏模拟 + Creator + 语音**。这三块是"锦上添花"，但会吃掉 70% 工期。

### 6.2 分阶段路线图（每阶段都有可验收产物）

| 阶段 | 目标 | 关键交付 | 验收标准（可实测） | 参考工时 |
| --- | --- | --- | --- | --- |
| **P0 壳实验** | 证明"僵尸可以被人驱动" | 一个把僵尸去僵尸化、用 `pathToLocationF` 走到指定点的脚本 | 生成 1 只僵尸 → 它不咬人、不自己游荡、按你的坐标走 50 格；存档重载后无报错 | 1~2 天 |
| **P1 单 NPC 骨架** | 逻辑身份与实体解耦 + 调度器 | `ActorRegistry`（uid/generation）、`ShellAdapter`（生成/清洗/回收）、10 Hz 调度 + 预算、`OnZombieUpdate` 接管、状态清洗守卫 | 10 个 NPC 同时走动；帧率无可见下降；区块卸载再回来 NPC 不重复、不消失残留 | 1~2 周 |
| **P2 战斗最小闭环** | 一场交火"看起来像真的" | `LosUtil.lineClear` 视线 + 声源标记表 + 自研命中 `ZombRand(10000) < chance` + `setHealth/Kill`/`AddDamage`/`addBlood` + 曳光/枪口光/声音 | 3v3 交火有压制、有掩体、有倒地；能追踪击杀归属；打玩家走原版伤害 | 2~4 周 |
| **P3 数据化阵营** | 改数据即可加派系 | `.alife` 式行式格式 + 单一 `Codec.schema` + `Catalog` 加载 + `Relations` 四态 + 声望持久化（带 schema 守卫） | 新增一个派系只需编辑文本文件；声望跨存档保留；破坏存档格式有明确报错 | 1~2 周 |
| **P4 离屏小队** | **世界的灵魂** | `SquadLedger`（ModData 表）+ 预生成道路图 + `getWorldAgeHours()` 推进 + 离屏对拼 + 复仇契约 + `RenderProtocol` 渐进实体化/回收 | 在 A 镇打散一支小队，3 天后在 B 镇被他们伏击（全程无实体但位置在变） | 2~4 周 |
| **P5 据点与导演** | 世界有"地方"和"节奏" | 据点预设表 + Builder（脚本放 `IsoThumpable/IsoDoor/IsoRadio`）+ `OutpostDirector` + `Encounter/RaidDirector` + `BaseHeat` | 地图上出现据点；骚扰频率随玩家行为变化；突袭分波次 | 2~4 周 |
| **P6 表现与规模** | 从"能玩"到"像模组" | AnimSet 动画库（先做 walk/run/aim/reload/hitreaction 5 类）、bark 对话（先 3 派系 × 30 条）、Creator 编辑器、本地化、兼容层、Admin 工具、沙盒选项 | 玩家能自己做派系并分享给别人；控制台有可读诊断 | 长期 |

### 6.3 单人 MVP 的推荐裁剪线

> **只做 P0 + P1 + P2 + P3 的"薄版"**：
> 3 个派系（友好/中立/敌对）、每派系 1 支 4 人小队、会巡逻、会交火、会记住玩家（声望）、
> 死亡会掉落、存档安全可增删。
>
> 这条线**依然能提供 80% 的"活人感"体验**，因为玩家感知最强的三件事是：
> ① 有人不被我触发也在动；② 他们会说话/警告我；③ 他们记得我做过什么。
> **离屏模拟（P4）是"世界感"的放大器，但不是入场券。**

### 6.4 最容易翻车的四处（按风险排序）

| 风险 | 症状 | 预防 |
| --- | --- | --- |
| **原版状态残留** | 永久卡窗、飞天、滑步、翻栅栏后僵住 | P0 就把 `leaveNativeState` 状态清洗抽成独立模块；清理 13 个攀爬变量 + 打断 `lunge/turnalerted/thump` |
| **实体引用泄漏** | 玩 1 小时后内存暴涨、存档卡死 | 所有 per-实体缓存用 `setmetatable({}, {__mode="k"})` 弱键表；逻辑身份与实体分离 |
| **每帧全量思考** | 20 个 NPC 就把服务器 tick 掐死 | 三车道频率（150 ms / 1500 ms）+ 每 tick 毫秒预算 + 每 NPC 冷却闸 |
| **联机死亡同步** | 尸体复活、幽灵 NPC、血量撕裂 | 自研标量血 + `trueHealth/reconcileHealth` 对账；死亡给宽限期（本例 60 s）；UID+generation 双校验 |

---

## 7. 最小可行骨架（可直接起步的代码轮廓）

> 以下代码是**按 A-Life 的真实模式重写的教学骨架**，去掉了所有业务细节，保留关键架构。
> 目标：让你第一天就有一个"能走动、能被调度、存档安全"的 NPC 底座。

### 7.1 目录

```
MyNPCs/
├── common/                         # 版本无关：动画与共享数据（无 mod.info 也可被引擎承认）
│   └── media/AnimSets/zombie/pathfind/mynpc_human_walk.xml
└── 42.20/
    ├── mod.info
    ├── poster.png
    └── media/
        ├── sandbox-options.txt
        └── lua/
            ├── shared/MyNPCs/Identity.lua
            ├── server/MyNPCs/Bootstrap.lua      # 事件注册（唯一入口）
            ├── server/MyNPCs/Scheduler.lua      # 10Hz + 帧预算
            ├── server/MyNPCs/Registry.lua       # 逻辑 actor 账本（uid/generation）
            ├── server/MyNPCs/Shell.lua          # 僵尸壳：生成/清洗/回收
            ├── server/MyNPCs/Guard.lua          # 原版状态清洗守卫
            ├── server/MyNPCs/Brain.lua          # 模块注册表 + 优先级链
            └── server/MyNPCs/Modules/*.lua      # 行为模块（巡逻/交战/逃跑…）
```

### 7.2 `mod.info`

```ini
name=My NPCs
id=MyNPCs
author=you
modversion=0.1.0
versionMin=42.21.0
poster=poster.png
description=Minimal living-world NPC scaffold.
```

### 7.3 逻辑身份（`shared/MyNPCs/Identity.lua`）

```lua
-- 说明：身份是"账本"里的字符串，不是实体；实体只是当前附身对象。
local Identity = {}

function Identity.newUid()
    -- 用游戏时间 + 随机数生成稳定 UID；避免依赖实体 ID
    return string.format("npc_%d_%d", getTimestampMs(), ZombRand(1000000))
end

-- 实体上的标记：modData 布尔 + SetVariable 字符串（动画状态机需要后者）
function Identity.stamp(shell, uid, generation)
    local data = shell:getModData()
    data.MyNPCsOwned      = true
    data.MyNPCsUID        = uid
    data.MyNPCsGeneration = generation
    shell:SetVariable("MyNPCActor", "true")     -- 动画 XML 的条件项
    shell:SetVariable("MyNPCUID", uid)
end

-- 万能判定：布尔或变量，二者其一成立即认领（尸体上布尔可能已被清）
function Identity.isOurs(character)
    if character == nil then return false end
    local ok, data = pcall(character.getModData, character)
    if ok and type(data) == "table"
        and (data.MyNPCsOwned == true or data.MyNPCsUID ~= nil) then
        return true
    end
    local uid = character.GetVariable and character:GetVariable("MyNPCUID") or nil
    return uid ~= nil and uid ~= ""
end

return Identity
```

### 7.4 僵尸壳（`server/MyNPCs/Shell.lua`）

```lua
local Identity = require "MyNPCs/Identity"
local Shell = {}

-- 生成并"断电"：这 12 行决定僵尸不再像僵尸
function Shell.spawn(actor, x, y, z)
    local shell
    local ok = pcall(function()
        shell = createZombie(x, y, z, nil, 0, IsoDirections.S)
    end)
    if not ok or shell == nil then return nil, "create_failed" end

    local cleaned = pcall(function()
        shell:setUseless(true)            -- 关掉原版僵尸 AI 驱动
        shell:setCanWalk(true)
        shell:setCrawler(false)
        shell:setBecomeCrawler(false)
        shell:setFakeDead(false)
        shell:setForceFakeDead(false)
        shell:setReanimate(false)
        shell:setReanimatedPlayer(false)
        shell:setTarget(nil)
        shell:clearAggroList()
    end)
    if not cleaned then
        pcall(function() shell:removeFromWorld(); shell:removeFromSquare() end)
        return nil, "clean_failed"
    end

    Identity.stamp(shell, actor.uid, actor.generation)
    shell:setHealth(actor.health or 1)     -- 自研血量（0~1）
    return shell
end

-- 回收：区块卸载/玩家离开时把状态写回账本
function Shell.despawn(shell, actor, reason)
    pcall(function()
        local data = shell:getModData()
        data.MyNPCsUID = nil                -- 清逻辑标记（保留实体自身的清理给引擎）
        shell:removeFromWorld()
    end)
    actor.x, actor.y, actor.z = shell:getX(), shell:getY(), shell:getZ()
    actor.health = shell:getHealth()
    actor.state = "offline"
end

return Shell
```

### 7.5 原版状态清洗守卫（`server/MyNPCs/Guard.lua`）—— **别跳过这一块**

```lua
local Guard = {}

-- 这些是原版攀爬/翻越流程残留的变量名，不清就会卡窗、飞天、滑步
Guard.nativeClimbVars = {
    "ClimbingFence", "ClimbFenceStarted", "ClimbFenceFinished", "ClimbFenceOutcome",
    "ClimbFenceFlopped", "ClimbWindowStarted", "ClimbWindowEnd", "ClimbWindowFinished",
    "ClimbWindowOutcome", "ClimbWindowFlopped", "VaultOverRun", "VaultOverSprint", "BlockWindow",
}

-- 原版僵尸的"攻击性状态"，必须打断，否则 NPC 会突然扑人
Guard.nativeAggroStates = { lunge = true, turnalerted = true, attack = true, thump = true }

function Guard.leaveNativeState(shell)
    pcall(function()
        local stateName = shell:getActionStateName()
        if stateName ~= nil and Guard.nativeAggroStates[stateName] == true then
            shell:clearAggroList()
            shell:setTarget(nil)
            shell:changeState(ZombieIdleState.instance())
        end
        for _, name in ipairs(Guard.nativeClimbVars) do
            shell:clearVariable(name)
        end
        shell:setVariable("bPathfind", "false")
        shell:setVariable("bMoving", "false")
        shell:setIgnoreMovement(false)
        shell:setHideWeaponModel(false)
        shell:resetModelNextFrame()
    end)
end

-- 每帧只对"可疑状态"的 NPC 调用，避免全量开销
function Guard.isSuspect(shell)
    local ok, name = pcall(shell.getActionStateName, shell)
    return ok and name ~= nil and Guard.nativeAggroStates[name] == true
end

return Guard
```

### 7.6 调度器（`server/MyNPCs/Scheduler.lua`）—— 性能的命门

```lua
local Scheduler = {
    -- 与 A-Life 同量级的默认参数
    tickIntervalMs   = 100,    -- 逻辑 10 Hz
    budgetMs         = 12,     -- 每 tick 上限
    lanes = {
        hotRadius = 45,  hotIntervalMs = 150,     -- 玩家近处：150 ms 思考一次
        farRadius = 110, farIntervalMs = 1500,    -- 稍远：1.5 s
    },
    lastTickAtMs = 0,
}

local function nowMs() return getTimestampMs() end

function Scheduler.shouldTick()
    local now = nowMs()
    if now - Scheduler.lastTickAtMs < Scheduler.tickIntervalMs then return false end
    Scheduler.lastTickAtMs = now
    return true
end

-- 返回"这个 NPC 现在该思考吗"
function Scheduler.thinkDue(actor, playerX, playerY, now)
    local dx, dy = actor.x - playerX, actor.y - playerY
    local dist2 = dx * dx + dy * dy
    local lane
    if dist2 <= Scheduler.lanes.hotRadius ^ 2 then lane = Scheduler.lanes.hotIntervalMs
    elseif dist2 <= Scheduler.lanes.farRadius ^ 2 then lane = Scheduler.lanes.farIntervalMs
    else lane = nil end                       -- 更远：交给离屏账本，不做实体思考
    if lane == nil then return false end
    if actor.cooldownUntilMs ~= nil and now < actor.cooldownUntilMs then return false end
    actor.cooldownUntilMs = now + lane
    return true
end

-- 带预算的批量执行：到点就停，本帧绝不超支
function Scheduler.runBatch(actors, task)
    local started = nowMs()
    local processed = 0
    for _, actor in ipairs(actors) do
        if nowMs() - started >= Scheduler.budgetMs then break end
        local ok, err = pcall(task, actor)
        if not ok then
            print("[MyNPCs] task error: " .. tostring(err))   -- print log 使用英文
        end
        processed = processed + 1
    end
    return processed
end

return Scheduler
```

### 7.7 行为模块注册表（`server/MyNPCs/Brain.lua`）—— 替代"巨型 if"

```lua
local Brain = { modules = {}, order = {}, priorities = {
    flee = 30, panic = 34, withdraw = 45, cover = 50,
    patrol = 120, idle = 200,
} }

function Brain.register(def)
    assert(type(def.id) == "string", "module id required")
    assert(type(def.evaluate) == "function", "module evaluate required")
    def.priority = def.priority or Brain.priorities[def.id] or 500
    Brain.modules[def.id] = def
    Brain.order[#Brain.order + 1] = def
    table.sort(Brain.order, function(a, b) return a.priority < b.priority end)
end

-- 第一个返回非 nil 的模块胜；每个模块独立 pcall，坏模块不拖垮整帧
function Brain.think(actor, shell, context)
    for _, module in ipairs(Brain.order) do
        local ok, result = pcall(module.evaluate, actor, shell, context)
        if not ok then
            print("[MyNPCs] module " .. module.id .. " error: " .. tostring(result))
        elseif result ~= nil then
            actor.behaviorState  = module.id
            actor.behaviorIntent = result.intent
            return result, module.id
        end
    end
    return nil, nil
end

-- 巡逻模块示例
Brain.register({
    id = "patrol", priority = 120,
    evaluate = function(actor, shell)
        if actor.route == nil or #actor.route == 0 then return nil end
        local waypoint = actor.route[1]
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then
            behavior:pathToLocationF(waypoint.x, waypoint.y, waypoint.z or 0)
            shell:changeState(PathFindState.instance())
        end
        return { intent = "patrol", waypoint = waypoint }
    end,
})

return Brain
```

### 7.8 引导入口（`server/MyNPCs/Bootstrap.lua`）

```lua
require "MyNPCs/Scheduler"
require "MyNPCs/Registry"
require "MyNPCs/Shell"
require "MyNPCs/Guard"
require "MyNPCs/Brain"

MyNPCs = MyNPCs or {}

if not MyNPCs.BootRegistered and type(Events) == "table" then
    MyNPCs.BootRegistered = true

    local function add(name, callback)
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
    end

    local function tick()
        if not MyNPCs.Scheduler.shouldTick() then return end
        local now = getTimestampMs()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local px, py = player:getX(), player:getY()

        local batch = {}
        MyNPCs.Registry.each(function(actor)
            if MyNPCs.Scheduler.thinkDue(actor, px, py, now) then batch[#batch + 1] = actor end
        end)
        MyNPCs.Scheduler.runBatch(batch, function(actor)
            local shell = actor.shell
            if shell == nil then return end
            if MyNPCs.Guard.isSuspect(shell) then MyNPCs.Guard.leaveNativeState(shell) end
            MyNPCs.Brain.think(actor, shell, { now = now })
        end)
    end

    -- 主循环：只在这里做"到点才干活"
    add("OnTick", function()
        local ok, err = pcall(tick)
        if not ok then print("[MyNPCs] tick failed: " .. tostring(err)) end
    end)
    add("OnGameStart",     function() MyNPCs.Registry.load() end)
    add("OnServerStarted", function() MyNPCs.Registry.load() end)
    add("OnSave",          function() MyNPCs.Registry.save() end)
    -- 每只 NPC 的独立更新钩子（原版僵尸也走这里，务必先判断 isOurs）
    add("OnZombieUpdate", function(zombie)
        if MyNPCs.Identity and MyNPCs.Identity.isOurs(zombie) then
            pcall(MyNPCs.Guard.leaveNativeStateIfNeeded, zombie)
        end
    end)
end
```

### 7.9 配套的动画节点（`common/media/AnimSets/zombie/pathfind/mynpc_human_walk.xml`）

```xml
<?xml version="1.0" encoding="utf-8"?>
<animNode>
    <m_Name>MyNPCHumanWalk</m_Name>
    <m_AnimName>Bob_Walk</m_AnimName>          <!-- 借用玩家动画 -->
    <m_Priority>30</m_Priority>
    <m_ConditionPriority>30</m_ConditionPriority>
    <m_Looped>true</m_Looped>
    <m_BlendTime>0.18</m_BlendTime>
    <m_Conditions><m_Name>bMoving</m_Name><m_Type>BOOL</m_Type><m_Value>true</m_Value></m_Conditions>
    <m_Conditions><m_Name>MyNPCActor</m_Name><m_Type>BOOL</m_Type><m_Value>true</m_Value></m_Conditions>
    <m_Events><m_EventName>Footstep</m_EventName><m_TimePc>0.15</m_TimePc>
              <m_ParameterValue>walk</m_ParameterValue></m_Events>
</animNode>
```

### 7.10 沙盒选项（`42.20/media/sandbox-options.txt`）

```lua
VERSION = 1,

option MyNPCs.Enabled = {
    type = boolean, default = true,
    page = MyNPCs_1General, translation = MyNPCs.Enabled,
    _tooltip = MyNPCs.Enabled_tooltip,
}

option MyNPCs.SquadCap = {
    type = integer, min = 1, max = 24, default = 6,
    page = MyNPCs_1General, translation = MyNPCs.SquadCap,
    _tooltip = MyNPCs.SquadCap_tooltip,
}
```

配套 `media/lua/shared/Translate/EN/Sandbox.json`：

```json
{
    "Sandbox_MyNPCs_1General": "My NPCs - GENERAL",
    "Sandbox_MyNPCs.Enabled": "Enable NPCs",
    "Sandbox_MyNPCs.SquadCap": "Max live NPCs"
}
```

---

## 8. 工程陷阱与最佳实践清单（从 A-Life 代码里反推出来的）

| # | 规则 | 依据 |
| --- | --- | --- |
| 1 | **NPC = 去僵尸化的 `IsoZombie`**，不要试图从 Lua 造自定义角色类 | `ShellAdapter.lua:44-118` |
| 2 | **必须同时打两种标记**：`modData` 布尔（Lua 可见）+ `SetVariable` 字符串（动画状态机可见） | `AIFence.lua:626-641` |
| 3 | **所有引擎调用包 `pcall`**，失败走降级/回收；模组要跨 B42.x 小版本存活 | 全项目普遍写法 |
| 4 | **per-实体缓存必须用弱键表** `{__mode="k"}`，否则长时段必爆 | `AIFence.lua:12-30` |
| 5 | **逻辑身份 ≠ 实体**：`uid + generation`（联机再加 `getOnlineID()`） | `Executor.entryMatches`、`TargetPolicy.identityOf` |
| 6 | **目标必须做"对象回收"校验**，否则会打到已被引擎复用的对象 | `TargetPolicy.canJump` 的 `target_recycled` |
| 7 | **决策要分车道 + 毫秒预算 + 冷却闸**，绝不可每帧全量 | `Decisions.lanes`、`Scheduler.budgetMs` |
| 8 | **单模块 pcall 隔离**，坏模块只记 `lastError`，不中断整链 | `Registry.lua:212-229` |
| 9 | **状态清洗必须独立成模块**，并清理 13 个原版攀爬变量 | `ObstacleTraversal.lua:1116-1147` |
| 10 | **多人时门窗/破障要占位认领**，否则叠人打转 | `breachClaims`、`reservations`、`Tactics.claimsFor` |
| 11 | **`isServer()` 下部分客户端动作不可用**，要走客户端权威 + 上报 | `ObstacleTraversal.lua:223` |
| 12 | **血量/伤口走自研标量 + 联机对账**，不要只信 `setHealth` | `ShellSimulation.trueHealth/reconcileHealth` |
| 13 | **持久化优先 `ModData.getOrCreate`**（随存档走），只有分享内容才落盘 | `ALifePersistence.lua:4,36-37` |
| 14 | **数据结构带 `schema` 版本号**，不兼容时明确报错而不是静默读坏 | `Reputation.SCHEMA`、`Codec` |
| 15 | **数据迁移永不就地改写**，一律 `.old.N` / `.bad` 旁置 | `RecordMigration.lua:8-72` |
| 16 | **服务端必须重新校验客户端提交的内容**（语法→白名单→形状/id 正则） | `CustomFactionAuthority.validate` |
| 17 | **缓存带世界签名**（`map..schema`），换图/换版本自动失效 | `OfflineDirector.lua:180-216` |
| 18 | **时间推进用 `getWorldAgeHours()`**，不要用真实秒（快进/挂机才不漏算） | `OfflineDirector.lua:63-68` |
| 19 | **坐标系统一用 tile**，转换函数收口一处，否则出"部队瞬移"类玄学 bug | `ALifeMapZones` 全域 tile |
| 20 | **日志与诊断要预留**：Telemetry + Watchdog + BlackBox（环形缓冲）+ 管理员命令 | `Admin/*`、`BlackBox.lua` |
| 21 | **公开给第三方的兼容契约要写清"死体例外"**，或者干脆双标记判定 | 本报告 4.6 的实测差异 |
| 22 | **沙盒选项是最便宜的"玩家自救"**：给性能、频率、上限都留旋钮 | 118 个选项的真实分布 |

---

## 9. 与本仓库的结合：差距分析与可执行的第一步

### 9.1 现有能力盘点（本仓库已有）

| 已有资产 | 与"活世界 NPC"的关系 |
| --- | --- |
| `bin2_companion_alpaca/`、`bin2_blocky_alpaca/`（Companion Dogs 扩展） | **动物同伴**：贴图/模型/心情（Moodle）管线已跑通，但**不是人类 NPC、没有 AI 决策** |
| `bin2_neat_controller_support/`、`guides/controller-support-development.md` | 手柄 UI 层经验，可作为 NPC 交互菜单（招募/命令）的输入基础 |
| `bin2_viewpoint/`（ZombieBuddy 补丁 + `build.sh` + JDK ≥ 25 流程）、`bin2_workshop_upload_fix/` | **ZB Java 补丁脚手架已具备**——若走"改原版 AI 状态/暴露未暴露类"路线，可直接复用构建与离线自测框架 |
| `bin2_*_cn/` 一批翻译补丁、`bin2_lingering_voices_cn`、`docs/pz_translation_json_format.md` | **翻译补丁工作流成熟**，可直接对接 A-Life 的内容哈希键体系 |
| `bin2_nested_containers_take/`、`bin2_titles` 等 | 与 NPC 无关，但共用同一套打包/发布 SOP |
| `docs/b42-npc-engine-capability-audit.md`（本轮新增） | **引擎能力的取证文档**，写 NPC 代码前先读它 |
| 本报告 | 架构与复刻路线 |

**结论**：本仓库已经具备"打包发布、翻译、手柄 UI、Java 补丁"四块基建，
**唯独缺"AI 行为与世界模拟"这一块**——正好是本报告第 6 章要补的。

### 9.2 建议的三步走（按风险从低到高）

**第一步（1~2 天，零风险，立刻可做）：做 A-Life 的中文翻译补丁**

理由：它只发英文（`Translate/EN/` 两个 JSON），且键是**英文原文的内容哈希**
（`IGUI_ALifeUI_<16 位 hex>`）。这既符合本仓库最擅长的补丁模组模式，又能让你**在不写一行逻辑的前提下**
把它的数据层摸透（118 个沙盒选项 + 1000+ UI 键的含义）。

做法：
1. 中文环境下启动游戏，把 console.txt 里出现的 `IGUI_ALifeUI_*` 键与英文原文导出；
2. 生成 `media/lua/shared/Translate/CN/IG_UI.json` 与 `Sandbox.json`；
3. 按 `pz-workshop-item-publishing` 规范打包成独立补丁（**不修改原模组**，用 `require=ProjectALifeNPCs`）。

**第二步（1~2 周）：按第 7 章骨架做 P0 + P1**

把 `learn/` 目录当作孵化区（本仓库约定：`learn/` 是开发/学习区），先只做：
"一只能按坐标走动、有 UID 账本、存档安全的 NPC"，**不要碰战斗**。
验收标准严格按 6.2 表格的 P0/P1。

**第三步（按需）：决定路线分叉**

- 只要"会巡逻、会交火、会记忆"的够用型 NPC → **继续纯 Lua**，走 P2/P3；
- 需要"改原版僵尸 AI 状态 / 每只僵尸独立逐帧回调 / 用未暴露的动画类" →
  复用 `bin2_viewpoint/` 的 **ZombieBuddy 补丁脚手架**（构建 + 离线自测 + 审批流程都已跑通）。
  但要承担版本脆性：**每次 PZ 更新都要重新验证字节码特征串**。

### 9.3 本报告的可复核性说明

- 所有"机制"结论都附了**模组内的 `文件:行号`**，可直接打开 `steamapps/workshop/content/108600/3803984183/` 对照。
- 所有"引擎"结论都来自 `javap` 字节码，配套原始命令与输出见同目录的 `b42-npc-engine-capability-audit.md`。
- **未做**的事（明确声明）：① 未启动游戏做运行时实验（因此第 5.8 节的"未验证项"仍是未验证状态）；
  ② 未在游戏内实际运行 A-Life 观察帧率（源码已订阅在盘，但未启动游戏），性能数字全部来自其代码常量与作者的沙盒提示文本；
  ③ 第 7 章骨架代码是**按真实模式重写的教学代码，未在游戏中运行过**，落地前必须自己验证。

---

## 10. 参考资料与延伸阅读

### 10.1 核实方法（先看这里，再看链接）

本报告在 **2026-10-04** 用 `curl` 对下列 URL 逐条实测 HTTP 状态码
（`web_fetch` 工具在本机被 DNS 拦截，改用 bash 的 curl 反而可达）：

```bash
for u in "$@"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 15 \
         -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" "$u")
  echo "$code  $u"
done
```

**核实过程中被推翻的"常见推荐"（请勿再引用）**：

| 曾经流传的地址 | 实测 | 结论 |
| --- | --- | --- |
| `https://demiurgequantified.github.io/pz-zdoc/` | **404** | 该站点不存在；`pz-zdoc` 的真实仓库是 `cocolabs/pz-zdoc` |
| `https://github.com/demiurgequantified/pz-zdoc` | **404** | 同上 |
| `https://github.com/asledgehammer/PipeWrench-Modeler`、`.../PipeWrench-Template` | **404** | 已迁移；PipeWrench 模板现由 `shughes-uk` / `KogenGuyll` / `Konijima` 等维护 |
| `https://theindiestone.com/forums/index.php?/forum/28-modding/` | **404** | 版块编号已变；只用论坛首页 |
| `https://pzpw.dev/` | **000** | 已不可达 |

状态码含义：`200` 可访问；`403` 为 Cloudflare/风控拦截**脚本**（浏览器正常）；
`000` 为连接失败。

### 10.2 官方来源

- [Project Zomboid 官方 Modding 入口](https://projectzomboid.com/modding/) — ✅ 200。官方给 mod 开发者的起始页。
- [Project Zomboid 官方新闻 / 更新日志](https://projectzomboid.com/blog/news/) — ✅ 200。
  **B42 每次小版本的行为变更看这里**（NPC/AI 相关改动尤其要跟）。
- [The Indie Stone 官方论坛](https://theindiestone.com/forums/) — ✅ 200。
  注意：旧的 Modding 子版块编号（`forum/28-modding/`）已 404，请从首页进入。
- [Steam 创意工坊 — Project A-Life [ALIFE NPCS]（分析对象）](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) — ✅ 200。
- [Steam 创意工坊 — ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) — ✅ 200。
  本机已装的 Java 补丁框架（实测 2.3.4），是"改原版 AI 状态 / 暴露未暴露类"的唯一现成路径。
- Steam Web API（本报告元数据来源，**无需 API Key**）：
  `POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/`
  参数 `itemcount=1&publishedfileids[0]=<id>` — ✅ 实测可用。

### 10.3 API 文档与工具

- [PZ-Wiki-Modding/PZ-API-Docs](https://github.com/pz-wiki-modding/PZ-API-Docs) — ✅ 200，**最近更新 2026-09-24**。
  把 PZ API 文档汇总成单页，是 B42 时代**最新鲜**的公开 API 索引。
- [cocolabs/pz-zdoc（ZomboidDoc）](https://github.com/cocolabs/pz-zdoc) — ✅ 200，33 stars，但**最后提交 2023-05-13**。
  用途是"为 PZ 编译 Lua 库 + 生成 API 文档"，**面向 B41，B42 需自行验证**（⚠️ 时效风险）。
- [MrBounty/PZ-Mod---Doc](https://github.com/MrBounty/PZ-Mod---Doc) — ✅ 200。社区整理的模组开发笔记
  （含"如何使用 global modData"等基础章节，适合入门）。
- [PZ Wiki — Mod data](https://pzwiki.net/wiki/Mod_data) — ⚠️ curl 403（Cloudflare），**浏览器可访问**。
  PZ Wiki 的其它页面（`Modding` / `Lua_Event` / `Mod_structure` / `Sandbox_options`）同样"脚本 403、浏览器可开"。
- 反编译与静态分析（本报告引擎章节所用方法的工具链）：
  `unzip` 抽单个 class + **JDK ≥ 25 的 `javap -p -c -constants`**
  （`projectzomboid.jar` 是 Java 25 字节码，class 主版本 69；JDK 17 会报 `class file has wrong version 69.0`）。
  完整流程见本仓库 `pz-engine-deepdive` skill。

### 10.4 社区模板与工程化

- [shughes-uk/PipeWrench-Template](https://github.com/shughes-uk/PipeWrench-Template) — ✅ 200。
  为 PZ 模组提供 TypeScript 类型支持（PipeWrench 系列）。
- [Konijima/pzpw-template](https://github.com/Konijima/pzpw-template) — ✅ 200。PipeWrench 项目脚手架模板。
- [github.com/asledgehammer](https://github.com/asledgehammer) — ✅ 200。PipeWrench 生态作者的 GitHub 主页
  （**具体 Modeler/Template 仓库地址已 404 迁移，请从主页进入**）。
- [Reddit r/projectzomboid](https://www.reddit.com/r/projectzomboid/) — ⚠️ curl 403，浏览器可访问。
  查"NPC 模组是否冲突"这类实战经验的地方。

### 10.5 概念参考（"活世界"设计思想）

- [Wikipedia — S.T.A.L.K.E.R.: Shadow of Chernobyl](https://en.wikipedia.org/wiki/S.T.A.L.K.E.R._Shadow_of_Chernobyl) — ✅ 200。
  A-Life 系统的来源背景（GSC Game World 的离屏世界模拟设计）。
- [Wikipedia — S.T.A.L.K.E.R.（系列）](https://en.wikipedia.org/wiki/S.T.A.L.K.E.R._(series)) — ✅ 200。
- [Game AI Pro（免费章节合集）](https://www.gameaipro.com/) — ✅ 200（浏览器 UA；纯 curl 会 406）。
  其中 "Simulation Level of Detail"、"Agent Coordination" 等章节，正是 A-Life"离屏账本 + 渐进实体化"
  的理论对应物——**做 P4 阶段（离屏小队）之前建议先读**。

### 10.6 本仓库已沉淀的相关资料（优先读这些）

| 文档 | 用途 |
| --- | --- |
| [pz-alife-mod-dev-report.md](pz-alife-mod-dev-report.md)（本文件） | 架构拆解 + 复刻路线 + 骨架代码 |
| [b42-npc-engine-capability-audit.md](b42-npc-engine-capability-audit.md) | **写 NPC 代码前必读**：B42 引擎给什么/不给什么（逐条附 `javap` 证据） |
| [develop_log_2026-10-04.md](../../docs/develop_log_2026-10-04.md) | 本课题的过程日志 |
| [pz_translation_json_format.md](../../docs/pz_translation_json_format.md) | B42 JSON 翻译格式（可用于 9.2 节的第一步） |
| [pz-dev-tooling.md](../../docs/pz-dev-tooling.md) | 开发工具链 |
| [workshop_create.sop.md](../../workshop_create.sop.md) | 工坊物品打包/发布 SOP（`workshop.txt` 真实字段、`preview.png` 硬规则） |
| `.dsh/skills/pz-workshop-item-publishing/` | 发布 skill（打包、校验、上传向导） |
| `.dsh/skills/pz-engine-deepdive/` | 引擎层取证/修补 skill（`javap`、ZombieBuddy 补丁、离线自测） |

### 10.7 一条元建议

**这份报告里的"外部链接"都可能失效，但两类内容不会过期**：

1. **模组内的 `文件:行号`**——只要你保留订阅，就能逐条对照；
2. **`javap` 的命令与判据**——只要游戏还是 Java 字节码，你就能自己重跑一遍，得出属于你当前版本的结论。

> 这也是本报告反复强调的方法论：**能自己证实的东西，不要依赖文档。**

---

## 附录 A：证据索引（按主题定位）

| 主题 | 首选证据位置 |
| --- | --- |
| NPC 如何从僵尸"诞生" | `server/ProjectALife/Shells/ALifeShellAdapter.lua:44-118` |
| 动画状态机注入 | `common/media/AnimSets/zombie/**/*.xml`（225 个）+ `shared/ProjectALife/Shells/ALifeAnimations.lua` |
| 调度与预算 | `shared/ProjectALife/Core/ALifeExecutor.lua`、`server/ProjectALife/Core/ALifeRuntime.lua:686-790` |
| 决策模块链 | `shared/ProjectALife/Behaviours/ALifeModuleRegistry.lua:101-229` |
| 战斗（自研弹道） | `server/ProjectALife/Combat/ALifeCombatStrike.lua:820-845` |
| 破障与状态清洗 | `server/ProjectALife/Movement/ALifeObstacleTraversal.lua:986-1147` |
| 离屏小队 | `server/ProjectALife/Offline/ALifeSquadLedger.lua`、`ALifeOfflineDirector.lua:63-68,790-822` |
| 多人镜像 | `shared/ProjectALife/Core/ALifeMirrorTransport.lua:5-8,195-247` |
| 生命周期三态 | `server/ProjectALife/Core/ALifeWatchdog.lua:534-585`、`ALifeOrphanGuard.lua`、`ALifeLifecycle.lua:25-30` |
| 内容格式与分享码 | `shared/ProjectALife/Records/ALifeRecordCodec.lua:15-68`、`ALifeFactionShare.lua:416-426` |
| 沙盒与本地化 | `42.20/media/sandbox-options.txt`、`shared/ProjectALife/Core/ALifeText.lua:20-45` |
| 引擎能力边界 | [b42-npc-engine-capability-audit.md](b42-npc-engine-capability-audit.md) |

---

*本报告由 6 路并行子代理取证 + 主代理交叉复核撰写。模组内结论可对照本机已订阅的
`steamapps/workshop/content/108600/3803984183/` 逐行验证；引擎结论可用 `javap` 复现。
明确"未做"的事见第 9.3 节。*
