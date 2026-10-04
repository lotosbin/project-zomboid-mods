# A-Life 联动扩展头脑风暴

> 输入依据（全部可复核）：
> ① 工坊 A-Life 生态 31 条实测元数据 → `alife-ecosystem-map.md`
> ② 本机 **1,150 个已安装模组**的 `mod.info` 清单（`/tmp/installed_mods.tsv`，可重新生成）
> ③ A-Life 核心模组的**官方兼容清单** `shared/ProjectALife/Compat/ALifeModCompat.lua`（29 条，含 verdict/note）
> ④ A-Life 的扩展点 API 面 → `alife-extension-api.md`
> ⑤ 本仓库既有资产：ViewpointMac、Neat 手柄支持、Companion Dogs 羊驼系列、Lingering Voices CN、
>    Extensive Power/Health Rework、Energy Routing、Nested Containers、Tikitown、ZombieBuddy 补丁基建
>
> 目的：找出**没人做、做得到、且与本仓库优势重合**的扩展方向。

---

## 0. 先分清三种扩展形态（决定风险与工期）

| 形态 | 做法 | 风险 | 参考标杆 | 典型工期 |
| --- | --- | --- | --- | --- |
| **H1 数据扩展** | 只提供 `.alife` 阵营/NPC/装备 provider、沙盒选项、翻译、动画 XML | 极低（不写逻辑，不碰 A-Life 内部表） | **Aftermath**（79 个 `.alife`，41 个 Lua） | 数天~2 周 |
| **H2 逻辑扩展** | 调用 `ProjectALife.*` 公开表、`Registry.register` 注册行为模块、挂 `Events` | 中（要跟 A-Life 版本演进） | **Jeem Extension**（132 文件 / 52,591 行） | 数周~数月 |
| **H3 表现/兼容扩展** | UI 覆盖层、渲染适配、monkey-patch 守卫、`Compat.known` 注册 | 低~中（可 `pcall` 降级，不改变 A-Life 逻辑） | Hostility Dots、Viewpoint Tracer Fix、Clean Context Menu Fix | 数天~2 周 |

> **建议路径**：先用 **H1/H3** 拿两三个"小胜"验证分发链路，再决定是否投 **H2**。

---

## 1. 官方兼容清单：**只有 A-Life 作者能写，第三方只能自检**（但它是重要信号）

> **重要修正**（来自 `alife-extension-api.md` 的实测）：`Compat.known` **不是注册 API**，
> 它是 A-Life 自己文件里的纯数据表（34 条），第三方**无法写入**它。
> 所以下面这一节的价值不在于"挂接点"，而在于 ①它替我们标出了哪些模组已安全/危险；
> ②它规定了**两条硬红线**（见 1.1）。

A-Life 内置 `Compat.known`（`ALifeModCompat.lua:13-84`，29 条显式 + 5 条 VariableSkin 循环），每条 = `name` + `verdict`
（`compatible` / `adapted` / `partial` / `unsupported` / `incompatible`）+ 一句给玩家看的人话 `note`。

**现状里有三条与本仓库直接相关**：

| A-Life 已登记的条目 | verdict | 与本仓库的关系 |
| --- | --- | --- |
| `NeatUI_Framework` / `Neat_Crafting` / `Neat_Building` / `Neat_Rocco` / `NeatLockpicking` | **compatible** | 本仓库有 `bin2_neat_controller_support`，**但清单里没有任何手柄相关条目** |
| `CompanionDogs`（**未登记**） | — | Companion Dogs × A-Life 由第三方补丁（3807738026）覆盖，本仓库是该生态扩展作者 |
| `Bandits2` | **unsupported**（"another NPC system on zombie bodies; not tested together"） | ⚠️ 本机**同时装了 Bandits2 及 4 个 Bandits 附属**，这是明确的冲突风险 |
| `ProjectALifeReconstructed` | **incompatible**（两个 A-Life 同时启用会互相覆盖） | — |
| `KnoxEventExpandedNpc` | **unsupported**（它替换 `IsoPlayer`/`BodyDamage`/`CombatManager` 引擎类） | — |

**由此产生的扩展形态**：
> **"A-Life 兼容/适配补丁集"** —— 把本仓库的模组逐个做成 `Compat.known` 可识别、且实际不打架的形态，
> 并以**独立补丁模组**的形式分发（不修改 A-Life 本体）。这是 H3 里风险最低、可见度最高的一类，
> 也是"作者向"的信用积累（A-Life 作者在清单里写 `note` 时，等于替你的模组背书）。

---

## 2. 联动点子清单（按"可落地性 × 竞争力"排序）

### A 类：与本仓库独有资产联动（先发优势最大）

| # | 点子 | 挂接的 A-Life 系统 | 依赖的真实模组 | 竞品 | 难度 |
| --- | --- | --- | --- | --- | --- |
| A1 | **A-Life × Viewpoint 官方适配**：NPC 曳光/枪口火光/受击表现在 3D 视角下的正确渲染 | `ALifeCombatFire.presentShot` 的 tracer + `IsoLightSource`；`ALifeAnimationClient` | Viewpoint（本仓库 `bin2_viewpoint` = ViewpointMac） | **已有** 3811640626（1,120 订阅，10-02） | H3 中 |
| A2 | **A-Life 手柄支持**：对话/警告/抢劫选择/无线电/据点电台菜单 + Creator 编辑器的手柄操作 | A-Life 的 `Talk/*`、`Interface/ALifeContextMenu`、`Interface/Creator/*` | `bin2_neat_controller_support` + `guides/controller-support-development.md` | **无** | H3 中 |
| A3 | **Companion Dogs × A-Life 深度联动**：NPC 收养/携带狗、狗为小队侦察与警戒、医疗兵治狗、阵营对狗的态度 | `Behaviours/ALifeModuleGunner·Healing`、`Senses/ALifePerception`、`Decisions/ALifeRelations` | `CompanionDogs` + 本仓库 `bin2_companion_alpaca`/`bin2_blocky_alpaca` | 有基础兼容（3807738026） | H2 大 |
| A4 | **据点电力/通讯联动**：切断据点电力 → 电台静默 → 停止派出小队（把 A-Life 的 `commsDisabled` 接到真实电网） | `Outposts/ALifeOutpostRadio`、`OutpostDirector`（`commsDisabled`）、`World/ALifeRaidDirector` | `bin2_extensive_power_rework`、`bin2_energy_routing_system`、WPControl(3681482725)、BetterGeneratorInfo(3576056135) | **无** | H2 中 |
| A5 | **电台/语音内容联动**：A-Life 的 5 个无线电频道与 175 个语音档案接入本仓库的中文电台内容 | `Talk/ALifeKnoxCountyRadio`、`Audio/ALifeVoiceCatalog`（事件契约） | `bin2_lingering_voices_cn`、SurvivorInnerVoice(3793128772) | 部分（语音包） | H1 小 |
| A6 | **Tikitown / 自建地图适配**：为自有地图标注据点与路网 | `World/ALifeRoadGraphShipped`、`ALifeMapZones`、`Outposts/ALifeOutpostPresets` | `bin2_tikitown`、Tikitown_CN(3448869708)、CustomMapLabels(3559737194) | **无** | H1 中 |

### B 类：地图与路网（明确的生态空白）

| # | 点子 | 依据 | 难度 |
| --- | --- | --- | --- |
| B1 | **RoadGraph 烘焙包**：A-Life 随包路网只标注了 `Muldraugh, KY`（`signature="shipped:Muldraugh, KY;schema=4"`），其它地图靠运行时 `Graph.buildStep` 现算（`gather→cluster→link→anchor→connect`，用 `getMetaGrid():getZonesIntersecting()`）。为热门地图**预烘焙**路网数据可显著降低首次进入的开销 | 核心模组 `ALifeRoadGraphShipped.lua`、`ALifeRoadGraph.lua:723-755`；本机已装 Chinatown、Cathaya Valley、Tikitown、Echo Creek 等地图 | H1+H3 中 |
| B2 | **据点候选点位包**：9 种据点预设是通用模版，但"哪些建筑值得设点"由运行时挑选；为特定地图手工标注（警察局/军事基地/医院）能显著提升沉浸感 | `Outposts/ALifeOutpostPresets.lua`（9 预设）、`ALifeOutpostDirector` | H1 小 |

### C 类：枪械/装备生态补全（纯数据，风险最低，可复制 Aftermath 的成功）

Aftermath 已覆盖 **Guns of Marz / Modern Firearms / Guns of '93** 三套。本机还装着它**没覆盖**的：

| # | 点子 | 目标模组（实测已装） |
| --- | --- | --- |
| C1 | **Hot Brass 弹药链 provider**：NPC 携带可回收弹壳/弹药材料，与弹药制作联动 | `HBAC`/`HBAmmoCraft`(3610677934)、`HBTacReload`(3610677934)、`HotBrass`(3637364024) |
| C2 | **Heavy Ordnance / SWMG 重武器 provider**：让 NPC 队伍出现机枪/重武器角色 | `HeavyOrdnance`(3802070967)、`SWMG`(3722064198) |
| C3 | **服装/护甲 provider 包**：阵营外观吃玩家装的军装与战术装备 | `VanillaOutfitsExpanded`、`KATTAJ1_ClothesCore/Military`、`EFTBP`(3432928943)、`SCP_Foundation_Pack`、`[J&G] Umbrella Corp Uniform`(3675741487)、`MilPonchoB42` |
| C4 | **武器配件/挂具 provider**：`alicesWeaponSling`(3775549577)、`Tuna_GunRacks`(3784677588)、`DarkWpnSlings`(3488113291) | 同左 + A-Life 的 attachments 逻辑 |

> C 类可直接复用 Aftermath 的 `providers/*.alife` 目录约定（`common/equipment/providers/`）与"依赖感知加载"
> ——**这是全清单里投入产出比最高的一类**。

### C+ 类：**兼容层**（已被生态验证的模板，且仍有空白）

> 补录（2026-10-04）：发现了 [ALifeStackCompat](extension-stackcompat-analysis.md)
> （3808789424，226 订阅，**仅 1 个 Lua / 294 行**）——它已经把兼容层做成了产品：
> 借 `setVariable("Bandit", true)` 让 3 个模组免费跳过 A-Life NPC，再 wrap 另外 3 个。
>
> **它没覆盖的正是我们的机会**：
> - **`Bandit` 标记反噬**：该标记是 Bandits2 的所有权标记，`Bandits2`/`BanditsFixPlus`/`NPCBases`
>   会把 A-Life NPC **当成强盗**接管；`CompanionDogs` 会把它判为「友方强盗 NPC」。
> - 需要**栈兼容 2.0**：带启用条件地借用标记，或对认领型模组做反向守卫。
>
> **新工程原则（建议纳入约定）**：借用第三方标记前，必须列出**全部读取者**并逐个判定
> 是「跳过语义」还是「认领语义」；有任一认领语义就不能无条件借用。

### D 类：系统机制联动（价值高但要动逻辑）

| # | 点子 | 说明 | 风险 |
| --- | --- | --- | --- |
| D1 | **玩家基地 = 阵营据点**：A-Life 阵营把玩家基地当据点对待（围攻、谈判、勒索） | 与 `SafehouseFactionControl`(3776063020)、`BuildingCraft` 生态联动 | 中 |
| D2 | **畜牧/农场联动**：据点占据农场后会掠夺/饲养 B42 动物，动物会被 NPC 抢 | 与 B42 畜牧 + `Animalsdonotattack*` 系列 | 中 |
| D3 | **元事件实体化**：A-Life 的 `MetaDirector`（枪声/直升机/车祸）用**玩家安装的真实载具模组**实体化增援 | 本机有 KI5 军用车辆（`62daimlerFerret`、`67commando`、`OT-64 SKOT` 等）+ `damnlib`、`Military_Tool_Kit` | 中 |
| D4 | **生命系统联动**：让 NPC 血量走本仓库的 `bin2_extensive_health_rework` 模型（而非 A-Life 自研标量血） | 需处理 A-Life 的 `trueHealth/reconcileHealth` 联机对账 | **高** |
| D5 | **尸潮/僵尸行为联动**：A-Life 已被 `WanderingZombies` 适配；可与 `L4D2 Zombie Siege`、尸潮类模组联动 | — | 中 |
| D6 | **任务内容包**：Jeem 扩展（0.4.6，WIP）有 missions/基地/声望系统 → 做任务内容与基地预设包 | 扩展别的扩展，需跟 Jeem 演进 | 中 |

### E 类：明确不建议做（避免踩坑）

| 方向 | 为什么不做 |
| --- | --- |
| **翻译** | 已彻底饱和：中文 ≥6 份、RU×2、ES、PT-BR×2、TH×2、KO×2、IT×2、JP、TR…（见 `alife-ecosystem-map.md`） |
| **与 Bandits2 / KnoxEventExpandedNpc 共存** | A-Life 官方 verdict = `unsupported`：前者"另一套建立在僵尸身体上的 NPC 系统，未一起测试"，后者替换引擎类 `IsoPlayer`/`BodyDamage`/`CombatManager`。要做也只能做**冲突检测提示**，不要试图"融合" |
| **自建第二套 NPC 系统** | A-Life 作者明确建议"一个存档只用一个 NPC mod"；重复造轮子且会互相抢僵尸身体 |
| **复制 Jeem 的基地/任务系统** | 已在做（10,743 订阅），且是 H2 重型工程 |

---

## 3. 优先级矩阵（价值 × 成本 × 风险 × 竞品）

| 排序 | 方向 | 价值 | 成本 | 风险 | 竞品 | 与本仓库优势重合度 |
| --- | --- | --- | --- | --- | --- | --- |
| ★★★ | **C 类 provider 包（C1~C4）** | 高（直接提升战斗观感） | **低**（纯 `.alife` 数据） | 极低 | 部分（Aftermath 覆盖 3 套枪械） | 中（需读数据格式） |
| ★★★ | **A2 A-Life 手柄支持** | 高（无人做 + 补齐短板） | 中 | 低 | **无** | **极高**（本仓库就是手柄专家） |
| ★★★ | **A1 Viewpoint × A-Life 官方适配** | 中高 | 中 | 低 | 有 1 个（1,120 订阅） | **极高**（本仓库是 ViewpointMac 作者） |
| ★★ | **B1 RoadGraph 烘焙包** | 中高（地图党刚需） | 中 | 低 | **无** | 低 |
| ★★ | **A4 据点电力/通讯联动** | 中高（机制新鲜） | 中 | 中 | **无** | 高（自有电力模组） |
| ★★ | **A3 Companion Dogs 深度联动** | 中高 | 高（H2） | 中 | 有基础版 | **高**（CD 扩展作者） |
| ★ | A5 电台语音、A6 Tikitown 适配、B2 据点包 | 中 | 低 | 低 | 无 | 中 |
| ★ | D1~D6 | 中高 | 中高 | 中高 | 各异 | 中 |

**结论**：**C 类 + A2 是最优首发组合** ——
C 类用最低成本验证"数据 provider"的分发链路与 A-Life 的加载契约；
A2 用本仓库的独有专长切进一个**完全没有竞品**的空白位。

---

## 4. 推荐的首发项目（三选一，可叠加）

### 方案 1（推荐）：**A-Life 手柄支持扩展** `H3`
- **为什么**：无竞品；本仓库有 `bin2_neat_controller_support` 与成套手柄开发文档（`guides/`、`docs/joypad.md`）；
  A-Life 的交互密集（对话/警告/抢劫/无线电/据点电台/Creator 编辑器）恰恰是手柄最痛的场景。
- **风险**：只要 UI 层，可与 A-Life 版本演进解耦；`Compat.known` 里补一条手柄条目即可。
- **最小可行**：先覆盖"对话选项 + 上下文菜单 + 无线电菜单"，Creator 编辑器放第二阶段。

### 方案 2：**A-Life 装备 provider 包（Hot Brass / Heavy Ordnance / 军装）** `H1`
- **为什么**：Aftermath 已验证这条路（5,921 订阅）；它没覆盖的模组本机都装着；纯数据、可增量提交。
- **风险**：极低，最坏情况是"某条目格式不被识别"，有 `Authority.validate` 可本地校验。

### 方案 3：**Viewpoint × A-Life 官方适配** `H3`
- **为什么**：本仓库是 ViewpointMac 作者，天然权威；已有第三方做了 3D 曳光（说明需求真实）。
- **风险**：要跟 Viewpoint 与 A-Life 双向演进；若第三方补丁已够用，价值会被摊薄 → 建议先比对它做了什么。

---

## 5. 下一步的"验证清单"（动手前先做，避免白干）

1. **读 `alife-extension-api.md`**：确认要用的每个挂接点是【稳定】还是【内部实现】。
2. **用 `Compat.known` 的现状定位自己**：先决定你的模组 id（建议 `ProjectALife<YourName>` 前缀），
   再决定是否需要让 A-Life 认识你（第三方无法直接写入 A-Life 的 `Compat.known`，
   但可以在**自己的模组**里做冲突检测与提示）。
3. **provider 路线**：先拿 Aftermath 的 `common/equipment/providers/*.alife` 当模板，
   用 `tools/` 里的校验脚本验证字段（待建），再进游戏实测。
4. **手柄路线**：先复现 A-Life 对话菜单，确认 NeatUI 系列的钩子不冲突（A-Life 已声明 Neat 系列 compatible）。
5. **始终记录**：每次实测写进本目录 `docs/rolling_log` 或仓库 `docs/rolling_log.md`（本仓库约定）。
