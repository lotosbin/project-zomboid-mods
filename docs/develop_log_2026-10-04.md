# 开发日志 - 2026-10-04

## 课题：从零开发"活世界 NPC"模组 —— 以工坊 3803984183 Project A-Life 为标杆的拆解与复刻路线

### 一、任务与选题依据

用户诉求是"**学习开发类似模组并生成报告**"，并给出了唯一的锚点：Steam 创意工坊物品 `3803984183`。

选题前先做的第一件事是**确认它到底是什么**，而不是先猜：

```bash
curl -s -X POST "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
     -d "itemcount=1&publishedfileids[0]=3803984183"
```

返回：`title = Project A-Life [ALIFE NPCS]`、`consumer_app_id = 108600`（Project Zomboid）、
`tags = [Build 42, Multiplayer]`、`file_size = 35,333,466 B`、
**`subscriptions = 121,195` / `favorited = 12,372` / `views = 168,828`**，
`time_created = 2026-09-19`、`time_updated = 2026-10-01`。

选它作为学习标杆的三个理由：
1. **它是纯 Lua 实现的极限样本**——作者明确承诺"no .ps1, .exe, .bat, .jar or .dll…Only Lua code,
   textures, models, sounds and plain-text data"，意味着它的每一项能力都能被 Lua 学习者在自己的模组里复现；
2. **它覆盖了 NPC 模组的全部难点**：实体载体、AI 决策、动画表现、多人同步、离屏世界模拟、内容管线；
3. **本机已订阅**，可以拿到逐字节的真实源码，而不是靠工坊描述推测。

### 二、方法：6 路并行取证 + 主代理交叉复核

| 子代理 | 负责范围 | 产出关键 |
| --- | --- | --- |
| A 核心运行时 | `Core/*`、`Shells/*`、`Executor` | Executor 的真实性质、生命周期三态、镜像协议 |
| B AI 决策战斗 | `Decisions/*`、`Behaviours/*`、`Combat/*`、`Movement/*`、`Senses/*`、`Fear/*` | 模块注册表 + 优先级链 + 战斗负向证据 |
| C 世界离线层 | `Offline/*`、`World/*`、`Outposts/*`、`Records/*` | 离屏账本、道路图三源、据点建造、持久化 |
| D 内容管线 | 打包结构、`sandbox-options.txt`、Creator、本地化、Compat | `.alife` 格式、分享码、内容哈希键 |
| E 引擎字节码 | `projectzomboid.jar` + 游戏自带 Lua | B42 无可用 NPC AI、白名单暴露、活 list |
| F 外部资料 | 官方/社区文档与工具 | 真实可访问的延伸阅读（另见报告第 10 章） |

硬性纪律：**每条结论要么带模组内 `文件:行号`，要么带 `javap` 原始输出**；不接受"看起来像"。

### 三、侦察阶段（主代理亲自做的部分）

1. **定位落盘位置**：`~/Library/Application Support/Steam/steamapps/workshop/content/108600/3803984183/`
   （Steam 客户端已订阅到本机，35 MB 完整源码在盘）。
2. **摸清目录约定**：`mods/ProjectALifeNPCs/{common,42.20}/`，`mod.info` 里 `versionMin=42.21.0`。
   → 顺带用字节码证实了 `common/` 是**引擎承认的版本无关目录**（`PZModFolder{common, version}`），
   不是社区约定。
3. **量化规模**（这决定了对"能不能一个人做"的判断）：

   ```
   分层：shared 93 文件/63,721 行 | server 109/63,244 | client 46/19,553  →  合计 248 文件/146,518 行
   子系统：Audio 27,216 | Talk 19,469 | Interface 12,039 | World 11,175 | Combat 10,436 | …
   ```
4. **亲手验证作者的两句公开承诺**：
   - "只有 Lua/纹理/模型/声音/文本" → `find` 无任何可执行文件，**成立**；
   - "每个尸体都有 `ProjectALifeOwned == true`" → `grep` 出 50 处引用，**写入点只有 5 个**，
     其中 `ALifeShellSimulation.lua:34`（`markCorpse`）把它**置 nil**，**不成立**。

### 四、分析结论（浓缩为八条）

1. **肉体**：NPC = 被"去僵尸化"的原版 `IsoZombie`（`createZombie` 造壳 → `setUseless(true)` +
   关掉 crawler/fakeDead/reanimate 一族 + `setTarget(nil)` → 打 `modData` 布尔 + `SetVariable` 字符串双标记）。
2. **骨架**：真正的"像人"来自 **225 个自定义动画节点 XML**——把玩家动画（`Bob_Walk`、`Bob_Reload_Rifle_Load`…）
   注册进僵尸的动画状态目录，用 `ALifeActor`/`ALifePace`/`BumpType` 等自定义变量作为条件，
   Lua 侧用 `setBumpType()` 触发、读 `BumpAnimFinished` 收尾。
3. **大脑**：57 个行为模块挂在注册表上，按优先级链"第一个返回非 nil 者胜"，每个模块 `pcall` 隔离；
   配四层开关（全局 / 模块 / 每 NPC 覆写 / 行为档案）。
4. **节奏**：10 Hz 主节流 + 子系统计数配额 + 决策 12 ms 硬预算 + 每 NPC 冷却闸 + 三车道 LOD
   （45 格内 150 ms、110 格内 1500 ms、更远交给离屏账本）。
5. **世界**：小队是挂在 ModData 的纯 Lua 表，用**游戏小时**推进，沿**预生成**道路图插值行走；
   离屏战斗是属性对拼；复仇契约跨天记忆；玩家靠近时通过 `RenderProtocol` **渐进实体化**（一次一人、间隔 1250 ms）。
6. **多人**：复用原版"僵尸归属"，owner 客户端模拟、服务端仲裁 + 每秒镜像；一切客户端上报过
   "距离 + 频率 + 绑定"三重校验；身份 = `UID + generation`。
7. **内容**：自研行式文本 `@alife-records 1` + 单一 `Codec.schema` 同时驱动磁盘目录、Creator 表单与分享码；
   118 个沙盒选项；本地化用"英文原文内容哈希"生成键。
8. **代价**：40% 的代码量是内容（音频 + 对话），**这是"活人感"的真正成本**，也是单人最该裁剪的部分。

### 五、引擎取证（本次最有"复用价值"的负向结论）

来自 `javap` 反编译 `projectzomboid.jar`（Java 25 字节码，须 JDK ≥ 25）：

- **B42 没有任何可用 NPC AI**：`IsoSurvivor`(3,277 B) 只有 3 个方法 + 3 个构造器，`void update` 命中 0；
  `OnNPCSurvivorUpdate` / `OnAIStateEnter/Execute/Exit` 是**死事件**（全 jar 只在注册表里出现）。
- 僵尸 AI 已迁 ECS：`StateMachineComponent` + `initializeStates()` 里 118 次 `registerAIState`；
  `updateActiveState()` 退化为 3 条指令。
- **`setUseless(true)` 覆盖面有限**：`useless` 只被 `ZombieIdleState`/`WalkTowardState`/
  `ZombieGroupManager`/`NetworkZombieVariables` 读取，**不阻止 attack/hitreaction/thump**。
  → 这解释了 A-Life 为何要额外做 `setNoTeeth` / `setZombiesDontAttack` 以及**每帧重申的围栏**。
- **Lua 是白名单暴露**（`exposeAll()` 共 1,001 类）：`AnimationPlayer`、`StateMachineComponent`、
  `ActionState`、`GlobalModData` 本体全部不在名单；Lua 动画入口只有 `PlayAnim` + `setVariable`。
- **`IsoCell.getZombieList()` 直接返回引擎内部 ArrayList 本体**（`getfield; areturn`）：
  不可增删，遍历须立即拷贝——这是很多模组偶发崩溃的根因。
- **没有 NPC 存档层**：`zombie/savefile/` 只有玩家数据库；`getModFileWriter` 会写回 mod 自身目录，
  Workshop 场景不可靠。

### 六、交付物

| 文件 | 内容 |
| --- | --- |
| `bin2_ProjectALifeNPCs_extensions/docs/pz-alife-mod-dev-report.md` | 主报告：档案与规模 → 交付物结构 → 架构总览 → 15 个机制拆解（全部带 `文件:行号` 与真实代码）→ 引擎边界（第 5 章）→ 分阶段路线图 → 最小可行骨架代码 → 22 条工程陷阱 → 与本仓库的结合 → 参考资料 |
| `bin2_ProjectALifeNPCs_extensions/docs/b42-npc-engine-capability-audit.md` | 引擎能力取证：每条结论附命令与原始输出，区分【已证实】/【未验证】 |
| `docs/rolling_log.md` | 追加本轮过程与结论（含 9 条核心发现表） |
| 本文件 | 当日开发日志 |

### 七、经验沉淀

1. **"作者文档" ≠ "代码契约"**。工坊描述里的兼容性承诺被一次 `grep` 推翻（见结论 4 的 `markCorpse`）。
   这与仓库此前踩过的 `workshop-txt-guide.md` 错字段是同一类错误：**回到代码或字节码验证**。
2. **一份数据格式服务多个消费者**。A-Life 用同一个 `schema` 驱动磁盘目录 + 编辑器表单 + 分享码编解码，
   这是把"内容平台"做起来的成本优势；反之每多一个消费者就多一套读写代码。
3. **性能是架构约束，不是后期优化**。10 Hz 节流、计数配额、毫秒预算、冷却闸、弱键表、三级可观测性——
   这六件事是"100 NPC 可用"的前提，任何一件留到最后补都会推倒重来。
4. **负向证据同样值钱**。"全项目 0 处 `DoAttack`/`Ballistics`" 这一条，直接决定了一个学习者
   该不该花两周去研究原版弹道（答案：不该，NPC 没有 `IsoPlayer` 的射击框架）。

### 八、明确的"未做"与待验证项

- **未启动游戏**做运行时实验；因此 `inactive/makeInactive(true)` 能否完全阻断 `update`、
  `getObjectListForLua()` 是否真为拷贝、`OnTick` 是否严格每渲染帧，这三条仍是【推断】而非【证实】。
- **未实测帧率**：所有性能数字来自其代码常量与作者写在沙盒提示里的自述（同屏敌意上限实测 120、硬上限 220）。
- **第 7 章骨架代码未运行过**：它是按 A-Life 的真实模式重写的教学代码，落地前必须自行验证。
- **未实际制作**任何 A-Life 衍生模组（翻译补丁、NPC 原型等），本日只完成"研究与报告"阶段。

### 九、下一步建议

1. **低风险起步**：做 A-Life 的中文翻译补丁（它只发英文 + 内容哈希键），借机吃透它的数据层；
2. **能力建设**：在 `learn/` 下按报告第 7 章骨架做 P0（壳实验）+ P1（单 NPC + 调度器），严格按验收标准；
3. **路线分叉**：够用型 NPC 走纯 Lua；需要改原版 AI 状态/用未暴露类时，复用 `bin2_viewpoint/`
   已跑通的 ZombieBuddy Java 补丁脚手架，并接受每次游戏更新都要重新验证字节码特征串的成本。

---

# 第二部分：A-Life 生态研究、扩展路线与目录归档

用户追加了三件事：把研究资料整理进 `bin2_ProjectALifeNPCs_extensions/`、
研究工坊 `3806944055` 与 `3806063445`、并头脑风暴与其他模组的联动扩展。

## 十、目标模组的真实身份（先侦查再动手）

用同一条 Steam API 命令拉两个 id，合并成一次请求即可：

```bash
curl -s -X POST "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
  -d "itemcount=2&publishedfileids[0]=3806944055&publishedfileids[1]=3806063445"
```

结果出人意料地好：**两个都是 A-Life 的扩展模组**，而且**本机都已订阅**——

| id | 名称 | 作者 | 订阅 | 形态 |
| --- | --- | --- | --- | --- |
| 3806944055 | Project A-Life - Jeem Extension | jeemlettuce | 10,743 | 基地/居民/任务/声望，**132 Lua / 52,591 行** |
| 3806063445 | Project A-Life: Aftermath | Shinyu | 5,921 | **一物品三 mod**（Marz / '93 / MFS 三个枪械变体），**79 `.alife` + 41 Lua，零美术资产** |

→ 于是本轮从"学习怎么写扩展"直接升级为"**读两个量产级扩展的源码**"。

## 十一、为写报告补做的生态调研（关键的一步）

为了让"该做什么"有依据，我做了两件原本没计划的事：

1. **枚举本机已安装模组**：扫 `workshop/content/108600/*/mods/*/*/mod.info`，
   **1,150 个模组**（去重后）写成 `/tmp/installed_mods.tsv` —— 这是所有"联动候选"的真实素材库，
   避免把不存在的模组写进头脑风暴。
2. **拉 A-Life 生态全景**：工坊搜索 `searchtext=Project+A-Life` 抓到 31 个 id
   （页面标题是 JS 渲染的，HTML 里只有 id），再用 API 批量拉元数据排序。

**这一步直接推翻了我自己上一轮的结论**：我原本建议"第一步做中文翻译补丁"，
实测发现**中文汉化已有 ≥6 份**（3805566620 / 3807333066 / 3807277264 / 3806186038 / 3807243560 /
3808256808 / 3808304775 …），另有 RU×2、ES、PT-BR×2、TH×2、KO×2、IT×2、JP、TR。
→ 已在报告与路线图里显式标注"该建议作废"。

同时发现真正的扩展只有 4 个（Jeem / Aftermath / Companion Dogs 兼容 / Hostility Dots），
以及一条与本仓库直接相关的信号：`3811640626 Project Viewpoint - 3D Tracer Fix for Project A-Life`
（1,120 订阅）说明 **Viewpoint × A-Life 的交集已经有人在做**，而本仓库正是 ViewpointMac 的维护者。

## 十二、两个标杆扩展的核心结论

**Aftermath（纯数据扩展的教科书）**
- 三变体的 `common/equipment/**` 79 个文件**逐字节完全相同**（md5 全等），
  分叉只靠 4 个常量（`modId/edition/backend/tag`）+ 一个 Backend 模块。
- 门控只有一行：`getActivatedMods():contains(id)`；`kind` 字段区分
  `faction_upsert` / `npc_upsert`（受身份门控）与 `npc_merge` / `npc_overlay`（通用 overlay）。
- 数据注入靠**猴补 `ProjectALife.Catalog.load`**（改 `Catalog.shipped` → `baseLoad(true)` 重建），
  并有热载兜底与 `provider scan loaded/inactive/errors` 三态日志。
- **`incompatible=` 的真因**：不是资产冲突，而是同一份 GoM 口径数据被三套互斥解释器处理。
- 最隐蔽的升级破坏点：**780 条出厂 NPC id 耦合** —— A-Life 改名后 merge 会静默 skip、不报错。

**Jeem（重型逻辑扩展的代价）**
- **136 处 `J.wrap`** 覆盖 49 个 A-Life 表 / 约 110 个函数；installer 每分钟重试、逐 feature 幂等。
- 工程化很漂亮（命名空间、`upstream=` 预留让位、三态降级），但**过半挂接点是内部实现细节**：
  直接复制 A-Life 声望存档 schema、抢 `Relations.adapters.reputation` 单槽、
  包住 17 个 `ObstacleTraversal` 内部函数、对冲走位常量（`followGap 1.8 / followHold 2.2`）。
- 结论：**新扩展只应依赖 4 个稳定接口**（`ModuleRegistry.register`、`Catalog` 读取器、
  `CustomFactions`/`CustomProfileAuthority`、`TalkIntents.choices`），其余一律软挂接。

## 十三、扩展点 API 盘点（决定"能不能做"）

- A-Life **没有扩展 SDK**：无 `Extensions`/`addProvider`/`contribute`/`Compat.register`。
  唯一官方注册器是 `ModuleRegistry.register` 与 6 个 `Voice*Register` hook。
- `Compat.known` 是硬编码数据（34 条），第三方改不了；它反而给出两条硬红线：
  **不得在 A-Life 目录树下放 Lua**、**不得 rebind `CreatorScreen`/`EquipEventShield`/`Animations`**。
- 血量必须走 `Sim.setHealth/trueHealth/maximumFor`；擦 `ProjectALifeOwned/UID` 会被 OrphanGuard 缴械再清理；
  第三方网络命令必须用自己的 module 名（`"ProjectALife"` 是白名单 + 管理员校验）。
- 已知陷阱：`kind="craft"|"doctrine"` **没有默认 dispatch** → 漏写 `dispatch` 会注册出永不执行的死模块。

## 十四、头脑风暴与路线（结论）

按"价值 × 成本 × 风险 × 竞品 × 与本仓库优势重合度"排出优先级：

| 排序 | 方向 | 竞品 | 结论 |
| --- | --- | --- | --- |
| ★★★ | **装备/武器 provider 包**（Hot Brass / Heavy Ordnance / 军装） | 部分 | 先做，跑通数据扩展链路 |
| ★★★ | **A-Life 手柄支持** | **无** | 吃本仓库独有优势 |
| ★★★ | Viewpoint × A-Life 官方适配 | 有 1 个 | 备选 |
| ★★ | RoadGraph 烘焙包（地图适配） | **无** | 空白区 |
| ★★ | 据点电力/通讯联动 | **无** | 与自有电力模组联动 |
| ✗ | 翻译 | 饱和 | **不做** |
| ✗ | 与 Bandits2 共存 | 官方 unsupported | **不做**（只做冲突检测提示） |

## 十五、顺手产出的实用工具

把实测规格落成 `tools/alife_lint.py`（`.alife` 校验器）。**写工具的过程立刻暴露了我对规格的三处误解**：

1. 值可以省略（`  look.beard`、`  presence.towns`）——核心数据里有 **666 处**这种写法，我第一版正则直接判错；
2. 必填字段我用了内存路径（`general.name`），而自带数据用文件侧名（`who.title`）；
3. 更意外的是 **Aftermath 用内存路径名也成立** → 说明**两种命名都被解码器接受**，
   这是一个此前任何文档里都没有的发现。

回归验证（用真实数据，不是造样例）：

| 数据集 | 结果 |
| --- | --- |
| A-Life 核心 `common/alife_runtime/catalog` | `files=2 records=928 factions=148 members=780 errors=0 warnings=0` ✅ 与已知真值一致 |
| Aftermath 三变体 `mods/` | `files=79 records=2809 factions=42 members=2767 errors=0` ✅ |
| 蓄意构造的坏文件 | 抓出 `bad_field` + `unclosed_record`，exit 1 ✅ |

## 十六、归档结果

`bin2_ProjectALifeNPCs_extensions/`（新建）：

```
README.md
docs/  pz-alife-mod-dev-report.md · b42-npc-engine-capability-audit.md · alife-ecosystem-map.md
       alife-extension-api.md · extension-jeem-analysis.md · extension-aftermath-analysis.md
       integration-brainstorm.md · roadmap.md
tools/ alife_lint.py
```

两份原在 `docs/` 的报告已移入并修正了全部相对链接（`../../docs/…`），
`docs/rolling_log.md` 与本文档同步更新了路径引用。

**待用户决策**：首发路线选 ①手柄支持 还是 ②provider 包（见 `roadmap.md` 阶段 0）。

---

# 第四部分：实现 `ALifeStartWithNPC`（开局自带友好 NPC）

## 二十一、需求与选型

用户要求："扩展 jeem extension 模组的增加 start with npcs 的可能性，即玩家出生时带一名友好 npc"。

这直接把路线从"研究"推进到"实现"，并且天然落在 `bin2_ProjectALifeNPCs_extensions/Contents/` 里。

## 二十二、先证再做：三条决定架构的实测结论

1. **Jeem 没有"开局给 NPC"的现成入口**：`OnCreatePlayer` 在 Jeem 全项目出现 0 次，居民 100% 由 `R.recruit` 产生。
2. **`R.recruit` 不能凭空造人**：它要求 `ActorRegistry.read(uid)` 已存在该 actor，还要求 base、床位容量、
   `isAlly`（声望）三重门槛；`force=true` 只在 `who.admin` 时生效（单机恒 true，多人非管理员会被拦）。
3. **A-Life 自带原生跟随**：`DecisionLoop.setOrder(uid, generation, {kind="follow", player=...})`。
   自建"跟随模块"是错方向——`orders` 模块 priority=10 会抢跑（Jeem 自己也只敢包 `followTarget` 修距离）。

→ 唯一正确的分层：**用 A-Life 造一个友好 NPC（必做） → 可选交给 Jeem 变居民（增强）**。

## 二十三、实现要点

- **造人**：`ActorRegistry.create` → `SpawnService.request`（后者内部同步建实体），失败时按 `dormant` 条件回滚。
  友好性用一行 `memory.spawnStance = "friendly"`（它是 `Relations.baselineStance` 的第一优先级来源）。
- **防回收**：要同时给 `memory.persistent`（挡 Population）与 `memory.admin.persistent`（挡 dehydrate）。
- **跟随**：等 `lifecycle == "active"` 后下原生 follow 指令。
- **居民化（可选）**：`BaseAreas.who/basesFor/createBase` + 直接写 `base.bedsOverride` 绕过床位统计 +
  `Residents.recruit(..., true)`；失败自动降级为跟随，不报错。
- **幂等四层**：角色 modData 标记 / 角色令牌进 `operationId`（A-Life 幂等）/ 存档级 `setWorldValue` /
  `actor_not_dormant` 兜底。
- **时序**：绝不直接在 `OnCreatePlayer` 造人（那时 `Runtime.started` 常为 false），改为 `OnTick` 轮询就绪，
  90 秒上限，超时转每分钟兜底重试 5 次。

## 二十四、工程事故与修正（值得记住的三条）

| # | 问题 | 怎么发现的 | 教训 |
| --- | --- | --- | --- |
| 1 | `Pick` 模块误写成 `local Pick = ALifeStartWithNPC`（应为 `require` 模块） | 人工复查 | **语法检查抓不到"语义错了但语法对"的 bug**，交付前必须再读一遍关键行 |
| 2 | 只设 `memory.persistent` 挡不住 `dehydrate` | 子代理指出 + 回代码核对 `adminPersistent()` | 同一语义在不同子系统可能有**不同的字段**，别想当然 |
| 3 | 沙盒 `Mode` 文案与代码语义写反 | 写测试清单时对照代码发现 | **选项文案必须与代码分支一一对照着写**，否则玩家设了没效果 |

## 二十五、产出与状态

- `Contents/mods/ALifeStartWithNPC/42.20/`：`mod.info`、`poster.png`（512×512 已过工坊硬规则）、
  `sandbox-options.txt`（9 项）、EN/CN 翻译、5 个 Lua（`Config`/`Pick`/`Grant`/`Bootstrap`/`Request`）。
- `docs/start-with-npc-design.md`：功能设计 + 我们依赖的 API 稳定性评级 + 已知限制 + **14 项测试清单** + 未验证项。
- `tools/lua_syntax_check.mjs`：用仓库自带 fengari 做 Lua 语法检查（本机无 lua 解释器）。

**状态：源码级验证 + Lua 语法校验 + 海报硬规则校验已通过；尚未在游戏中运行。**
下一步就是按测试清单 T1~T14 进游戏实测，并把结果回填。

## 二十六、staging 与工坊校验

加载 `pz-workshop-item-publishing` skill 后按其规范补齐物品根文件，并建立软链：

- `workshop.txt`：`version=1`、多行 `description=`（含依赖/两种模式/生效标志/诚实声明）、
  `tags=Build 42;QoL;Misc;Multiplayer;WIP`（取自游戏 `media/WorkshopTags.txt` 白名单）、**`visibility=private`**（首次上传前安全默认）
- `preview.png` 256×256（与 512 的 `poster.png` **分开排版**，不是缩放同一张）
- `changelog.txt`：首行 `版本 0.1.0 (2026-10-04)`，并如实写明"尚未进游戏验证"等待办
- 软链：`~/Zomboid/Workshop/ALifeStartWithNPC` 与 `~/Zomboid/mods/ALifeStartWithNPC`

用游戏自己的解析器实测（Steam 已登录，探针不上传）：

```
readWorkshopTxt       = true
visibility            = 2            # private
tags                  = [Build 42, QoL, Misc, Multiplayer, WIP]
contentFolder         = .../Contents  exists=true
validatePreviewImage  = OK
id                    = null         # 首次上传前不带 id
```

结论：**物品已经具备直接进上传向导的条件**；剩下的是"进游戏实测 → 上传"（均为待办）。

## 二十七、T1/T2 实测报错与修复（Kahlua 没有 next()）

用户复测反馈"T1、T2 有报错"。`console.txt` 里是 499 条同样的错：

```
[ALifeStartWithNPC][ERROR] tick failed: Object tried to call nil in tick java.lang.RuntimeException
STACK TRACE
  Lua((MOD:A-Life: Start With NPC [Jimmy add-on])).tick(Grant.lua:215)
  Lua((MOD:A-Life: Start With NPC [Jimmy add-on])).Add(Bootstrap.lua:114)
```

**根因**：`Grant.lua:215` = `if next(Grant.pending) == nil then return end`。
**游戏的 Kahlua 运行时没有 `next()`** —— Jeem 的 `Core.lua:231` 早就写明了这个限制。
这是"用 Lua 5.1 的习惯写 PZ Lua"的典型翻车：语法没问题（fengari 校验通过），运行时才炸。

**修复**：引入 `Grant.pendingCount` 显式计数（`pendingAdd`/`pendingRemove`），
tick 开头改成 `if Grant.pendingCount <= 0 then return end`；顺带给 `os.time` 兜底加 `pcall`。
同时按 Kahlua 的另两个已知坑做了预防性复核（`table.sort` 不稳定、`%` 是截断取模）——本模组都没用到。

**反证一个担心**：日志里 `overrides media/sandbox-options.txt` 不代表覆盖——
用户同时装着 5 个提供该文件的模组且 A-Life 一切正常 ⇒ 引擎按模组累加合并，我的选项不会顶掉别人的。

**版本**：0.1.1。**下一步**：重启游戏（Lua 只在启动时加载）复测 T1/T2。

## 二十八、追加需求：开局好感度改为「同盟」（0.1.2）

用户要求"npc 的初始好感度要是同盟"。查证后确认这是个**容易做错**的点：

- A-Life 的 stance 词表里 `allied` 会被归一化成 `friendly`，且 `memory.spawnStance` 的白名单
  不接受 `allied` —— 如果直接把 "allied" 写进去，会被拒绝并**退回按阵营关系计算**（可能是敌对），比不改更糟。
- 真正的「同盟」档位在 Jeem：`Services/Standing.lua:14` 的阶梯
  `{ hostile, careful, neutral, friendly, allied }`，阈值 `{25, 75, 150, 250}`。

**做法**：新增 `Config.makeAllied()` 与 `Grant.makeAllied(player, actor)`：
把该 NPC 阵营的声望置为 `S.clamp`(400)（跨过全部阈值 ⇒ 任何默认档位都到 allied）→ 补足该小队的组声望 →
调 `J.Standing.apply(key, factionId)` 立刻写回 A-Life 声望存档。A-Life 侧仍保持 `spawnStance="friendly"`（上限）。

**附带收益**：同盟声望让 `R.isAlly` 成立，于是把居民收编改成**先走非 force 的正规路径**，
修掉了"联机非管理员会被 not_allied 拦住"的隐患（force 只在 admin 时生效）。

**如实记录的副作用**：Jeem 声望按阵营记录 ⇒ 同盟的是整个阵营；已写进沙盒 tooltip，并提供 `MakeAllied` 开关。
**版本**：0.1.2（含新的第 10 个沙盒选项），Lua 语法与翻译 JSON 校验均通过。

## 二十九、T1 实测通过（读日志）+ 0.1.3 修正

用户继续测试后，`console.txt` 给出了明确结果：

**T1 通过**（两个会话各一次）：`grant #1 → spawned → grant complete: 1/1 npcs (mode=1)`，
且 A-Life 自己的生命周期日志作为第三方证据：
`[ALIFE-LIFECYCLE] hydrate ... nearest=2 loaded=true inList=true side=sp` ——
实体落在离玩家 2 格、区块已加载、已在僵尸列表中。修复后**零报错**。
另一个会话里玩家用 Jeem 界面手动收编成功（`[ALIFE-JIMMY] residents: sp:0 invited 1 ...`），
证明生成的 NPC 与 Jeem 完全互操作。

**日志也暴露了证据缺口**：两次发放的令牌不同 ⇒ 是两个不同角色 ⇒ **T2 其实还没被验证**；
follow 与同盟也都没有日志（分别是 v0.1.1 未打印、v0.1.2 未跑到）。于是 0.1.3 补了三条可观测日志，
把"要玩家自己判断"变成"日志一眼可验"。

**0.1.3 的实质修正**：同盟改为优先调官方 `Standing.debugSet(player, factionId, "allied")`。
原因是我在读它时发现一个**会让功能静默失效的必要条件**：A-Life 声望里若那条记录是 `cause = "provoked"`，
`F.apply` 会拒绝覆盖，同盟永远设不上——官方实现里那句 `store.players[key][factionId] = nil` 就是为此。
我们的退路（联机非管理员会用到）已复刻该步。

## 三十、多人联机报错排查（0.1.4）：元凶是"汉化整合包"

用户报"多人联机模式有报错"。日志把问题一分为二：

**本模组联机正常**：`coop-console.txt` 里 2 名玩家各得 1 名 NPC，流程完整；`spawn failed` 0 次。

**真正的报错**：`no such location "UI_Alife_Animations_20"`。堆栈里出错的 `ALifeAnimations.lua`
标注的是 **`MOD:Project A-Life [中文汉化]`**（工坊 `3807277264`）——它自带 **233 个 Lua 文件**，
命中 A-Life `probePaths` 的 **4/4** 个旧路径，是 **A-Life 1.3 重构前的整包旧副本**。
归因：`hydrateShell` 失败 40 次 = 经我 28 次 + **A-Life 自家 12 次** ⇒ A-Life 自己也中招。
A-Life 自己的兼容层早已把这类模组判为 incompatible（"a translation should ship only Translate files"）。

**我做的两件事**：
1. 复用 A-Life 的 `Compat.foreignCopies(activeSet())` 在开局做兼容自检，把元凶点名写进 console.txt
   （并在水合失败时再报一次）——**用别人的检测器**比自己写启发式可靠（我第一次自己写的判据就把
   A-Life/Jeem/Aftermath 误判成"自带副本"，因为它们的命名空间里也含 ProjectALife）；
2. 生成重试节流（2 秒一次 / 每玩家 5 次），修掉"失败后每帧重试"的隐患。

## 三十一、联机"死亡重新发放"失效与修复（0.1.5）

用户报："多人模式，开启死亡重新发放，没有重新发放"。

排查出**三个叠加原因**（都在本模组内）：客户端请求守卫永久（每 playerIndex 只发一次）、
服务端 `OnCreatePlayer` 只在纯单机处理、以及**没有任何死亡钩子**。

第三条里最隐蔽的一点：A-Life 的 `ActorRegistry.create` 用 `operationId` 做幂等，
而我的 `operationId` 里含本角色的一次性令牌。**令牌不变 ⇒ 幂等命中 ⇒ 返回那条已经死掉的记录**，
随后 `SpawnService.request` 以 `actor_not_dormant` 失败。也就是说：
**即使清掉了"已发放"标记，只要不清令牌，仍然发不出新 NPC。**

修法：服务端三种模式都处理 `OnCreatePlayer`；客户端每次角色创建都请求一次（服务端幂等）；
新增死亡钩子清标记 + **清令牌** + 清尝试计数；并把所有 per-角色 状态从"按 IsoPlayer 对象缓存"
改为存进玩家 modData（联机重生可能复用同一个 player 对象）。

**教训**：**幂等键不能跨生命周期复用**。上一轮我把 `operationId` 当作"防重复"的功臣，
这一轮它在重生场景里就变成了"防重生"的元凶 —— 凡是按角色实例的幂等，都必须在死亡/重生边界显式失效。

**方法沉淀**：排错时要**把 Lua 栈里每一帧标注的模组名读出来**（PZ 的栈会标 `MOD:<名字>`），
再用"同一错误在 A-Life 自家调用下出现几次"做归因统计 —— 这比争论"是不是我的 mod 造成"有效得多。

> **勘误**：本文第一部分"九、下一步建议"第 1 条"做中文翻译补丁"**已作废**（生态实测显示中文汉化已有 ≥6 份），
> 请以第二部分的优先级表为准。

---

# 第三部分：3808789424「A-Life x zombie mods - stack compatibility」研究

## 十七、对象与体量

`ALifeStackCompat` v1.3 / 226 订阅 / 13 KB / **1 个 Lua 文件 294 行**，
全部内容放在 `common/`（连 `mod.info` 都在 `common/` 下，**没有版本目录**）——
这利用了之前用字节码验证过的规则：`PZModFolder{common, version}`，`common/media` 就是资源根。

它让 6 个第三方僵尸行为模组跳过 A-Life NPC：TrippingZombies、Claimable Outposts、The Mutants、
UV Defense、KillCount、Zombie Dismemberment（前三个靠一个标记，后三个靠 monkey patch）。

## 十八、三个核心发现

### 18.1 `Bandit` 是生态级既成契约（全量 grep 才知道）

本机 1,150 个模组里**至少 10 个读取** `getVariableBoolean("Bandit")`，语义分两类：

- **跳过型**（对 A-Life NPC 有利）：`PZTheMutants/PZM_ForeignOwnership.lua:79`（注释直接写
  "Bandits documents this animation variable as its external runtime marker"）、
  `InjuredZombiesStumble.lua:8`、`SZedPlus_Spawn.lua:184`、`ZoneLootRefill` 的 BanditsCompat/Protection；
- **认领型**（有反噬风险）：`Bandits2` 本体（`BanditUpdate.lua:199` 写入；`BanditZombie.lua:74` 读到后
  `GetBrain(zombie)` 并缓存为 bandit）、`BanditsFixPlus`（7 处）、`NPCBases`、
  **`CompanionDogs/core/Identity.lua:20`**（`isFriendlyBanditNPC`：读到标记且无 `md.brain` → 判为友方强盗 NPC）。

### 18.2 因此「借标记」是一把双刃剑（本模组描述里没写）

`setVariable("Bandit", true)` 让 A-Life NPC 对跳过型模组隐身，同时把它**拉进 Bandits2 的语义**。
而 A-Life 官方 `Compat.known` 对 `Bandits2` 的判定正是 `unsupported`。
本机同时装着 Bandits2 + BanditsFixPlus + NPCBases + CompanionDogs（+ 我们自己的羊驼扩展），
**所以不能无条件照抄这一行**。

### 18.3 服务端打标竞态（作者 v1.1 的血泪教训）

专用服务器上 `OnZombieUpdate` 根本没进到本模组：**118 次 A-Life 生成，打标 0 个**。
改成 `OnZombieCreate` 入队 + 每 10 tick 复查（最多 90 次）+ 每 300 tick 全量 sweep；
**根因是 A-Life 在 `createZombie(...)` 之后才写 modData 标记**（对应 `ShellAdapter.lua:82-140` 的顺序），
所以创建当刻身体「还不是」A-Life NPC。客户端仍走 `OnZombieUpdate`。

## 十九、结论与新增工程原则

1. 这个模组是「兼容层」产品的**完整可抄模板**：`isOurs` 三路回退 → `tagBody` 幂等打标 →
   每目标一个 `wrapXxx()` 返回 `wrapped/absent` → 启动日志 + `EveryTenMinutes` 计数。
2. 它未覆盖的部分就是空白：**`Bandit` 标记的认领型反噬**、单人下 ZD 不生效。
3. **新增工程原则**：借用第三方标记前，必须列出**全部读取者**并逐个判定
   「跳过语义 vs 认领语义」；只要有认领语义，就不能无条件借用（要么加启用条件，要么用更窄的专用标记）。
4. 检索方法补记：工坊 `searchtext=Project+A-Life` 会漏掉标题不含 "Project" 的生态模组
   （本模组就是例子），应跑 `Project+A-Life` / `A-Life` / `ALife` 三种检索取并集。

## 二十、产出

- 新建 `bin2_ProjectALifeNPCs_extensions/docs/extension-stackcompat-analysis.md`
- 回填：生态地图（补录为第 32 条 + 新增"检索盲区"一节）、`README`（文档树 + 第三个标杆）、
  `integration-brainstorm.md`（新增 **C+ 类：兼容层**）、`roadmap.md`（阶段 2 改为"模板已存在，可直接接手"+ 决策记录）
