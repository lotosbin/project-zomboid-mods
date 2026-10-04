# 落地路线与决策记录

> 前置阅读：`integration-brainstorm.md`（做什么）、`alife-extension-api.md`（挂哪里、哪里会崩）、
> `extension-aftermath-analysis.md`（纯数据扩展的完整模板）、`extension-jeem-analysis.md`（重型逻辑扩展的代价）

---

## 阶段 0：决策门（**当前所在位置**）

必须先在三条路线里选一条开工。判断依据（全部来自已完成的研究）：

| 路线 | 竞品 | 本仓库优势 | 成本 | 风险 | 建议 |
| --- | --- | --- | --- | --- | --- |
| **① A-Life 手柄支持**（H3） | **无** | **极强**：本仓库是 `bin2_neat_controller_support` 作者，有 `guides/controller-support-development.md`、`docs/joypad.md` | 中 | 低（只动 UI 层） | ⭐ 首选 |
| **② 装备/武器 provider 包**（H1） | 部分（Aftermath 覆盖 Marz/MFS/guns93） | 中（需读 `.alife` 格式） | **低** | 极低 | ⭐ 先拿来练手 |
| **③ Viewpoint × A-Life 官方适配**（H3） | 有 1 个（3811640626，1,120 订阅） | **极强**：本仓库是 ViewpointMac 作者 | 中 | 中（要双向跟版本） | 备选 |

**推荐组合**：先做 **②**（最快跑通"数据扩展 → 工坊"的完整链路），再做 **①**（吃独有优势）。

---

## 阶段 1-A：如果选 H1（provider 包）

**目标**：为 A-Life 补齐 Aftermath 未覆盖的枪械/装备生态。

| 步骤 | 具体动作 | 完成判据 |
| --- | --- | --- |
| 1 | 选定首个 provider（建议 **Hot Brass 弹药链**：`HBAC`/`HBAmmoCraft`(3610677934)、`HBTacReload`、`HotBrass`(3637364024)） | 明确目标 mod id 与要附加的 item 全名 |
| 2 | 建目录骨架（照 `extension-aftermath-analysis.md` §8） | `42/mod.info` + `common/<base>/providers/*.alife` 就位 |
| 3 | 写 `.alife`（kind=`npc_merge` / `npc_upsert`），字段规格见 `alife-extension-api.md` §2.2 | `tools/alife_lint.py` 校验通过（0 error） |
| 4 | 写 `Loader`（门控 `getActivatedMods():contains()` + 猴补 `Catalog.load`），**照抄 Aftermath 的 `Require.must` 双路径兼容** | 进游戏后日志出现 `provider scan loaded=1 inactive=0 errors=0` |
| 5 | 在游戏内验证：NPC 手上出现目标武器/弹药；卸下目标 mod 后**不报错**且自动跳过 | 有/无目标 mod 两种情形都测一遍 |
| 6 | 打包发布（照 `pz-workshop-item-publishing` skill / `workshop_create.sop.md`） | `preview.png` 通过游戏自带校验、staging 软链可见 |

**必须登记的已知风险**（来自 Aftermath 的教训）：
- A-Life 的 **780 条出厂 NPC id** 是我们 merge 的目标 → A-Life 重命名 id 会**静默失效**，
  所以必须复刻 `skipped missing NPC=` 日志并在启动时自检。
- `Catalog.load` / `Catalog.shipped` 属于【半稳定】~【内部实现】，A-Life 升级需回归。

---

## 阶段 1-B：如果选 H3（手柄支持）

**目标**：让 A-Life 的全部交互界面可手柄操作。

| 阶段 | 覆盖范围 | 完成判据 |
| --- | --- | --- |
| B1 | 对话选项（`Talk` 的 `talkChoose` 流程）+ NPC 上下文菜单（`OnPreFillWorldObjectContextMenu`） | 用纯手柄完成一次"警告 → 投降 → 抢劫"全流程 |
| B2 | 无线电菜单（`outpostRadioList/Use/Disable`）+ 状态窗（`requestStatus`） | 纯手柄切频道、切断据点通讯 |
| B3 | Creator 编辑器（`Interface/Creator/*`，328 KB 主体） | 纯手柄新增一个阵营并保存至少 1 个字段组 |
| B4 | 与 `bin2_neat_controller_support` 合并/共存策略 | 两模组同时启用无输入抢占 |

**技术约束（来自 `alife-extension-api.md`）**：
- A-Life 的上下文菜单**无注册器、无优先级** → 我们必须自己挂 `OnFillWorldObjectContextMenu`，
  顺序 = 注册顺序，需处理与其它模组的叠层。
- **不得**在 A-Life 目录树内放 Lua 文件，**不得** rebind `ProjectALife.CreatorScreen`；
  手柄层应通过我们自己的 mod 名 + 自己的事件挂接实现。
- A-Life 已把 `NeatUI_Framework` / `Neat_Crafting` / `Neat_Building` / `Neat_Rocco` / `NeatLockpicking`
  声明为 `compatible` → 我们与 Neat 系列共存是安全的。
- 沙盒选项必须用**自己的表名**（如 `ALifePad`），**不要**写 `option ALife.*`。

---

## 阶段 1-C：开局自带 NPC（**已开工**，`ALifeStartWithNPC` v0.1.0）

起因：用户直接提出的功能需求——"扩展 Jeem Extension，玩家出生时带一名友好 NPC"。

| 步骤 | 状态 |
| --- | --- |
| 摸清 Jeem 有无现成入口 | ✅ 结论：**没有**，居民只能由 `R.recruit` 收编"已存在"的 actor |
| 摸清 A-Life 造人链路 | ✅ `ActorRegistry.create` → `SpawnService.request`（4 步，含回滚） |
| 摸清"跟随"该怎么做 | ✅ **A-Life 有原生 follow**（`DecisionLoop.setOrder`），自建模块会被 `orders`(priority 10) 抢跑 |
| 写代码（5 文件 + 沙盒 + 双语翻译 + 海报） | ✅ 完成，Lua 语法校验通过 |
| **进游戏验证 T1~T14** | ⬜ **待做**（见 `start-with-npc-design.md` 第 8 节） |
| 发布准备（workshop.txt / preview.png / changelog.txt / staging 软链） | ✅ 完成，探针 `validatePreviewImage=OK` |
| 首次上传工坊 | ⬜ 待做（建议先 `visibility=private` 私测，再改 public） |

## 阶段 2：兼容/冲突守护（**模板已存在，可直接接手**）

> 补录（2026-10-04）：[ALifeStackCompat](extension-stackcompat-analysis.md)（3808789424，294 行）
> 已经把这一类做出来了 —— `common/mod.info` + 单文件、`isOurs` 三路回退、
> `OnZombieCreate` 入队 + 延迟复查 + 低频 sweep 打标、每目标一个 `wrapXxx()` 返回 `wrapped/absent`。
>
> **它的空白 = 我们的切入点**：①`Bandit` 标记的认领型反噬（Bandits2 系 / CompanionDogs）；
> ②单人下 Zombie Dismemberment 未覆盖。
>
> 首个可做任务：**先做对照实验**（开/关 Bandits2 两组，观察 A-Life NPC 是否被 Bandits2 接管），
> 用日志与行为记录成证据，再决定「带条件借用标记」还是「反向守卫」。


**动机**：A-Life 官方把 `Bandits2` 标为 `unsupported`、`BanditsWeekOne` 标为 `incompatible`，
而本机同时装着 Bandits2 + 4 个附属。与其"融合"，不如做一个**检测 + 明确提示**的小补丁：

- 启动时用 `getActivatedMods()` 检测冲突组合；
- 给出可操作提示（禁用哪一个），而不是让玩家自己去猜；
- 绝不去 patch A-Life 或 Bandits2 的 NPC 逻辑（那会踩 `ALifeModCompat.lua:217-234` 的红线）。

同类可守护的组合（来自 `alife-extension-api.md` §1.1 的 34 条清单）：
`ProjectALifeReconstructed`（两个 A-Life 同时启用）、`KnoxEventExpandedNpc`（替换引擎类）、
`AmmoLootDropGunsOfMarzB42`（未测）。

---

## 阶段 3：其他候补（按需）

- **RoadGraph 烘焙包**（地图适配）：为 Chinatown / Cathaya Valley / Tikitown / Echo Creek 等
  预烘焙路网，降低 A-Life 首次进入的构图开销。技术路径见主报告 §4.12 与
  `ALifeRoadGraph.lua:723-755`。
- **据点电力/通讯联动**：把 A-Life 的 `commsDisabled` 接到本仓库的电力模组
  （`bin2_extensive_power_rework` / `bin2_energy_routing_system` / WPControl）。
- **Companion Dogs 深度联动**：已有第三方基础兼容（3807738026）。
- **电台/语音内容包**：A-Life 的 6 个 `Voice*Register` hook 是**最开放的扩展点**（有 `type()` 守卫）。

---

## 阶段 4：通用工程约定（无论选哪条路线都要遵守）

1. **命名空间**：mod id / Lua 全局表 / ModData TAG / 网络命令 module 名 / 沙盒表名 / 文本前缀，
   六者统一用同一个前缀（如 `ALifePad*`）。
2. **软挂接**：所有对 A-Life 的调用都走"存在性探测 + `pcall` + 缺失即禁用"，
   绝不复制 A-Life 的私有存档形状（反面教材见 `extension-jeem-analysis.md` §7 第 1、2 项）。
3. **可观测**：启动时打印 `loaded/inactive/errors` 三态汇总与 `skipped missing` 计数，
   便于 A-Life 升级后第一时间发现静默失效。
4. **幂等**：所有猴补打 `_XxxBridge = true` 标记，防 `Reset Lua` 重入（Aftermath 的做法）。
5. **只发自己的文件**：翻译只发 `media/lua/shared/Translate/<LANG>/*.json`；
   绝不在 A-Life 目录树下放文件。
6. **文档同步**：每轮实测追加到仓库 `docs/rolling_log.md`，并按需生成 `docs/develop_log_<date>.md`。

---

## 决策记录

| 日期 | 决策 | 依据 |
| --- | --- | --- |
| 2026-10-04 | 建立本目录，把 A-Life 研究资料集中归档 | 用户指示"整理到 bin2_ProjectALifeNPCs_extensions 目录" |
| 2026-10-04 | **放弃"做中文翻译补丁"的初始建议** | 生态地图实测：中文汉化已有 ≥6 份（3805566620 / 3807333066 / 3807277264 / 3806186038 / 3807243560 / 3808256808 / 3808304775…） |
| 2026-10-04 | **不追求与 Bandits2 共存** | A-Life 官方 `Compat.known` 判为 `unsupported`（"另一套建立在僵尸身体上的 NPC 系统，未一起测试"） |
| 2026-10-04 | 记录：`ALifeStackCompat` 证明「兼容层」是可行产品；但它的 `Bandit` 标记策略对 Bandits2 系有反噬风险，**不可无条件照抄** | `extension-stackcompat-analysis.md` §3.2 |
| 2026-10-04 | 首发候选收敛为"手柄支持"与"装备 provider 包" | 见阶段 0 的三方对比 |
| 2026-10-04 | 用户选定第三条线：**开局自带 NPC**（`ALifeStartWithNPC`） | 直接需求；且该功能在工坊**无竞品** |
| 2026-10-04 | 该功能**不依赖 Jeem 也能工作**：造人走 A-Life，居民化只是可选增强 | `R.recruit` 不能凭空造人，且有多重门槛（base/床位/声望） |
| 待定 | 手柄支持 / provider 包是否继续 | 等开局 NPC 验证完再定 |
