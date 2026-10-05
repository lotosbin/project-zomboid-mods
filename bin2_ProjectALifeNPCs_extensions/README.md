# bin2_ProjectALifeNPCs_extensions

> **Project A-Life [ALIFE NPCS]（工坊 3803984183）的扩展研究与开发目录**
> 归属：`bin2` 系列。当前状态：**第一个模组已落地**（`ALifeStartWithNPC`，代码完成、待进游戏验证）
> 建档：2026-10-04

---

## 1. 这个目录是干什么的

本项目有两个目标，按顺序推进：

1. **研究**：把 A-Life 及其生态（核心 + Jeem 扩展 + Aftermath + 兼容补丁）彻底拆解成"可动手的规格"，
   回答"扩展怎么写、挂哪里、哪里会崩"。
2. **开发**：基于研究结论，产出**本仓库自己的 A-Life 扩展模组**（模组 id 待定，候选 `ProjectALifeBin2Ext`）。

研究结论已经否掉了两个方向（**翻译已饱和**、**与 Bandits2 共存不可行**），
并把首发候选收敛到"手柄支持"与"装备 provider 包"两条（见 `docs/integration-brainstorm.md`）。

---

## 2. 目录导览

```
bin2_ProjectALifeNPCs_extensions/
├── README.md                      ← 本文件
├── docs/
│   ├── pz-alife-mod-dev-report.md              【核心】A-Life 主拆解报告（10 章：机制/引擎边界/路线图/骨架/陷阱）
│   ├── b42-npc-engine-capability-audit.md      【配套】B42 引擎能力取证（javap 原始证据）
│   ├── alife-ecosystem-map.md                  A-Life 工坊生态 31 条实测 + 赛道饱和度分析
│   ├── alife-extension-api.md                  A-Life 对外开放的扩展点清单（含稳定性评级 + .alife 完整规格）
│   ├── extension-jeem-analysis.md              标杆扩展 ①：Jeem Extension（基地/居民/任务/声望，52.6k 行）
│   ├── extension-aftermath-analysis.md         标杆扩展 ②：Aftermath（79 个 .alife provider + 3 变体，零美术资产）
│   ├── extension-stackcompat-analysis.md       标杆扩展 ③：ALifeStackCompat（13 KB 兼容层，294 行）
│   ├── start-with-npc-design.md                【实现】开局自带 NPC 的功能设计与测试清单
│   ├── integration-brainstorm.md               联动扩展头脑风暴（A~E 类，含不建议做的方向）
│   └── roadmap.md                              落地路线与决策记录
└── tools/
    ├── alife_lint.py              ← `.alife` 数据校验器（真实数据回归：核心 148 阵营/780 成员 0 错误）
    └── lua_syntax_check.mjs       ← Lua 语法检查（本机无 lua 解释器，用仓库自带的 fengari）
```

---

## 3. 三条必须先知道的事实

| # | 事实 | 依据 |
| --- | --- | --- |
| 1 | **B42 没有可用的 NPC AI**：`IsoSurvivor` 是空壳，`OnNPCSurvivorUpdate`/`OnAIStateEnter` 是死事件；A-Life 是"把僵尸去僵尸化"自建一切 | `b42-npc-engine-capability-audit.md` |
| 2 | **A-Life 的扩展能力是"隐式"的**：没有官方 SDK，靠 `ProjectALife.*` 全局表 + `.alife` 数据格式 + `Compat.known` 兼容清单 + modData 契约（`ProjectALifeOwned`/`ProjectALifeActor`/`ALifeUID`） | `alife-extension-api.md` |
| 3 | **翻译赛道已饱和**（中文 ≥6 份），真正的扩展只有 4 个（Jeem / Aftermath / Companion Dogs 兼容 / Hostility Dots） | `alife-ecosystem-map.md` |

---

## 4. 两个标杆扩展教给我们的事（一句话版）

- **Aftermath**（5,921 订阅，41 个 Lua + **79 个 `.alife`**）：证明了**纯数据扩展**最划算 ——
  用 `common/equipment/providers/*.alife` 按"身份提供者是否启用"条件加载，一份代码分叉出 3 个枪械变体，
  用 `incompatible=` 保证互斥。→ **H1 数据扩展**。
- **Jeem Extension**（10,743 订阅，132 文件 / **52,591 行**）：证明了**逻辑扩展**的天花板与代价 ——
  基地/居民/任务/声望是一整套并行系统，等价于"再造半个 A-Life"，且必须持续跟核心版本演进。
  → **H2 逻辑扩展**，非团队不要轻易碰。

详见 `docs/extension-aftermath-analysis.md` 与 `docs/extension-jeem-analysis.md`。

第三个标杆 **[ALifeStackCompat](docs/extension-stackcompat-analysis.md)**（3808789424，仅 294 行）更贴近下一步：
它是兼容层这类产品的完整模板，并揭示了生态最深的隐藏契约 —— `Bandit` 动画变量
（至少 10 个已装模组读它，一部分是跳过语义、一部分是认领语义）。

---

## 5. 与其他文档的关系

| 你想知道 | 去看 |
| --- | --- |
| A-Life 本身怎么实现的 | `docs/pz-alife-mod-dev-report.md` |
| B42 引擎到底能给什么 | `docs/b42-npc-engine-capability-audit.md` |
| 该做什么、不该做什么 | `docs/integration-brainstorm.md` |
| 怎么挂、挂哪里会崩 | `docs/alife-extension-api.md` |
| 发工坊的规范 | `.dsh/skills/pz-workshop-item-publishing/`、`workshop_create.sop.md` |
| 引擎层取证/补丁 | `.dsh/skills/pz-engine-deepdive/` |
| 过程记录 | 仓库 `docs/rolling_log.md`、`docs/develop_log_*.md` |

---

## 5.5 第一个模组：`ALifeStartWithNPC`（开局自带友好 NPC）

```
Contents/mods/ALifeStartWithNPC/42.20/
├── mod.info  poster.png  media/sandbox-options.txt（10 个选项）
└── media/lua/{shared,server,client}/ALifeStartWithNPC/*.lua   （5 个文件）
```

- **做什么**：新角色开局在身边生成 1~5 名**友好** A-Life NPC；默认用 A-Life **原生 follow** 让它们跟着你，
  也可切换为 Jeem Extension 的**居民**（守营地，有岗位/任务/声望）。
- **怎么做**：`ActorRegistry.create(memory.spawnStance="friendly")` → `SpawnService.request` →
  等 `lifecycle=="active"` → `DecisionLoop.setOrder{kind="follow"}`（居民模式则调 `Residents.recruit`）。
- **设计文档与测试清单**：`docs/start-with-npc-design.md`（含 14 项待执行测试、已知限制、未验证项）
- **现状**：源码级验证 + Lua 语法校验 + 海报硬规则校验已通过；**尚未在游戏中运行**。

## 5.6 staging 与工坊校验（已就位）

```bash
# 工坊待上传目录（上传向导里会看到这个文件夹）
~/Zomboid/Workshop/ALifeStartWithNPC -> <repo>/bin2_ProjectALifeNPCs_extensions
# 本地加载目录（游戏 Mods 列表里会出现）
~/Zomboid/mods/ALifeStartWithNPC -> <repo>/.../Contents/mods/ALifeStartWithNPC

# 上传前校验（用游戏自己的解析器；需 Steam 已登录；不会真的上传）
bash bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/ALifeStartWithNPC
```

实测（2026-10-04）：`readWorkshopTxt=true`、`tags=[Build 42, QoL, Misc, Multiplayer, WIP]`（全在白名单）、
`contentFolder exists=true`、`validatePreviewImage=OK`、`id=null`（首次上传前不带 id）。
物品根现在是：`workshop.txt` + `preview.png`(256×256) + `changelog.txt` + `Contents/`（只有 `Contents/` 会被打包）。

> 已发布：工坊 id **3813096783**、`visibility=public`（2026-10-05 复核 `workshop.txt` 实测）。
> ⚠️ 依赖（Steam 的「必需物品」）只能在工坊页面手填，`workshop.txt` 声明不了；
> 本物品需要 `3803984183`（A-Life）与 `3806944055`（Jeem Extension），详见 `../workshop_create.sop.md` §3.6。

## 5.7 第二个模组：`bin2_npc_extension`（橙子社区经济 × NPC 招募，**在隔壁目录**）

> 2026-10-05 新增。它**不是**本目录的模组，但它是本项目研究成果的直接产物，故在此登记：
> 路径 `../bin2_npc_extension/`，mod id `Bin2NPCExtension`。

- **做什么**：为「橙子社区经济」（工坊 3777900792）加一个「NPC 招募」面板 ——
  用社区货币**收编**身边已有的 A-Life NPC，或**中介派遣**（`ActorRegistry.create` + `SpawnService.request`）
  现造一名友好 NPC；岗位有跟随（A-Life 原生 follow）/ 守卫（hold + 锚点）/ 居民（Jeem `Residents.recruit`）；
  另有名册、日薪、欠薪解约、阵亡清理、名额上限。
- **复用了本项目什么**：造人链路与 `operationId` 幂等写法（`ALifeStartWithNPC/Grant.lua`）、
  友好阵营挑选（`Pick.lua`）、`tools/lua_syntax_check.mjs`、以及 `docs/` 里的稳定性评级与坑位清单。
- **本项目被它纠正的一处**：我们一度把自己的条目写进 `ProjectALife.ModCompat.known`。
  `Compat.report()`（`42.20/.../ALifeModCompat.lua:314-330`）会遍历它并按 `entry.verdict` 打印成
  `[A-Life] compat: … -> adapted: …`，等于第三方借 A-Life 的口替自己背书 —— 与本项目
  `docs/integration-brainstorm.md` §1 的结论一致（"不是注册 API"）。已改为**只读**自检：
  跑 `Compat.foreignCopies(active)` 点名"自带 A-Life Lua 副本"的模组。
- **它的文档**：`../bin2_npc_extension/docs/design.md`（设计）、`docs/research/`（两端扩展点逆向）、
  `docs/test-plan.md`（T1~T18 进游戏清单）。

## 6. 下一步（待用户决策）

按 `docs/roadmap.md` 的决策点执行；当前建议的首发候选：

1. **A-Life 手柄支持扩展**（本仓库独有专长，工坊无竞品）
2. **A-Life 装备 provider 包**（Hot Brass / Heavy Ordnance / 军装，纯数据、低风险）

第一个模组骨架已经落地（见 5.5 节）。接下来的候选：
1. **进游戏跑完 `start-with-npc-design.md` 的 T1~T14**（这是当前最高优先级的动作）
2. **A-Life 手柄支持扩展**（本仓库独有专长，工坊无竞品）
3. **A-Life 装备 provider 包**（Hot Brass / Heavy Ordnance / 军装，纯数据、低风险）
