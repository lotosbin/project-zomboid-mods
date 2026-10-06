# bin2_npc_extension

> **A-Life 的 NPC 招募扩展**（一个工坊物品，**四个模组 = 1 个公共层 + 3 个口味**）
> Mod ID：`Bin2NPCExtensionBase`（公共层）/ `Bin2NPCExtension`（橙子社区经济版）/
> `Bin2NPCExtensionYese`（YeseMarket 版）/ `Bin2NPCExtensionVanilla`（**原版钞票版**，不需要任何经济模组）
> 工坊 id：**3813914438**（已发布，public）｜ 归属：`bin2` 系列
> 状态：橙子口味已进游戏跑通基础流程；**YeseMarket 与 原版钞票 口味尚未进游戏验证**；
> 完整清单（`docs/test-plan.md` T1~T20 / M1~M4 / Y1~Y14 / V1~V12）未跑完
> 建档：2026-10-05（2026-10-06 增补第三个口味与公共层的钱接口）

---

## 1. 这是什么

一个**独立扩展模组**，把「招募 NPC」做成经济模组里的一门生意 —— 也可以**完全不用经济模组**，
直接花原版钞票。三个口味共用同一份招募内核（见 §1.5），钱从哪来由每个口味自己决定
（`docs/design.md` §13.2）：

* **收编**（便宜）：把你身边已有的 A-Life NPC 用社区货币签下来，成为你的雇员；
* **中介派遣**（贵）：直接在招募面板下单，由 A-Life 在你身边**生成**一名新的友好 NPC 交给你；
* **雇员岗位**：跟随（A-Life 原生 follow）／守卫／居民（交给 Jeem Extension 的居民系统）。
  名册页的岗位按钮是"选中 → 点「应用岗位」"两步；契约上的岗位只是**缓存**，
  每次改状态前都会先读一遍 Jeem 的 `memory.jimmyResident`，并每 30 秒对账一次（见 `docs/design.md` §11.8）；
* **运维**：雇员名册、解雇、岗位切换、日薪（欠薪会走人）、名额上限、死亡自动清理。

三个依赖各自**软挂接**，缺任何一个都只降级、不报错：

依赖的 id 与本机反查方式见 `../workshop_create.sop.md` §3.6；
**Steam 页面上的「必需物品 / Required Items」只能在网页手填（`workshop.txt` 声明不了，游戏的上传
native 也没有这个能力），每个物品一次** —— 详见该节的反汇编与实测证据。

| 依赖 | 工坊 id | 作用 | 缺失时 |
| --- | --- | --- | --- |
| 公共层 `Bin2NPCExtensionBase` | （本物品内） | 三个口味的共用逻辑 | 该口味**不生效**并打一行明确日志（`require=` 会自动启用公共层） |
| 橙子社区经济 | `3777900792` | **橙子口味**的 UI 容器 + 钱包 | 橙子口味静默禁用；另两个口味不受影响 |
| YeseMarket | `3735641567` | **YeseMarket 口味**的 UI 容器 + 钱包 | 该口味静默禁用 |
| Project A-Life | `3803984183` | NPC 本体、生成、跟随指令 | 页面可用但招募按钮禁用，并给出提示 |
| Jeem Extension | `3806944055` | 「居民」岗位（营地/岗位/作息/声望） | 只保留跟随/守卫两种岗位 |

**原版钞票口味不需要任何经济模组**：钱用原版物品 `Base.Money` / `Base.MoneyBundle`，
入口是原版左侧竖排图标栏（见 §1.5 与 `docs/design.md` §13）。

依赖与兼容对象的逆向取证见：

* `docs/research/economy-integration-hooks.md` —— 橙子经济对外开放的扩展点
* `docs/research/jeem-recruit-api.md` —— Jeem 招募链路 + A-Life 生成/跟随 API
* `docs/design.md` —— 本模组的功能与实现设计（含降级矩阵、存档格式、风险清单）

---

## 1.5 一个物品里的四个模组（1 个公共层 + 3 个口味）

| mod id | 角色 | 钱从哪来 | 入口 | 备注 |
| --- | --- | --- | --- | --- |
| `Bin2NPCExtensionBase` | **公共层** | —— | —— | 由口味 `require=` 自动启用，不用手勾 |
| `Bin2NPCExtension` | 口味 | 橙子社区经济（`OrangeCommunityEconomy`，3777900792） | 首页「NPC 招募」按钮 + Ctrl+Alt+N | 已进游戏跑过基础流程 |
| `Bin2NPCExtensionYese` | 口味 | YeseMarket（3735641567） | **导航栏插一行**「NPC Recruit」+ Ctrl+Alt+N | **尚未进游戏验证** |
| `Bin2NPCExtensionVanilla` | 口味 | **原版物品 `Base.Money`**（不需要任何经济模组） | **原版左侧图标栏最下方**的 NPC 图标 + Ctrl+Alt+N | **尚未进游戏验证** |

三个口味**共用同一份招募内核**（A-Life / Jeem 适配、契约、维护循环、命令路由都在公共层，
只有一份代码），差别只剩三样：一张 `Profile.lua` 里的身份 spec、口味自己的 UI 容器
（怎么挂进对方界面 + 怎么画列表），以及各自的翻译/沙盒选项。公共层**零身份**
（不含任何 mod id / 表名 / 前缀），所以三个口味可以同时启用而不会写进对方的存档表；
各自的名册会互查，同一个 NPC 不会被两边同时雇走（`spec.sibling` 必须**列全**其它口味，
见 `docs/design.md` §13.6）。

**钱的接口是可换实现**：公共层 `Core.MONEY_PROVIDERS = { upstream = "Economy", cash = "Cash" }`，
口味在 spec 里写 `money = "cash"` 就换成原版钞票（省略 = `upstream`，走经济模组）。接口方法
（`available/balance/pay/refund/flow/wage`）、三条引擎事实（面值 100:1、B42 无堆叠所以没有找零原语、
穿戴容器不在主背包）与入口挂接方式都在 `docs/design.md` §13。

> 公共层抽取的边界、机制与引擎依据见 `docs/design.md` §12；原版钞票口味见 §13；
> 不变量由 `tools/check_base.py` 守着。

> **变体目录是生成物**：`Contents/mods/Bin2NPCExtensionYese/` 与 `tools/test-yese/` 都由
> `tools/fork_variant.py` 产出，`--check` 会在有人手改变体时报差异（防两份核心代码悄悄分叉）。
> 要改变体，改生成器的替换表/补丁，而不是直接改变体文件。

## 2. 目录导览

```
bin2_npc_extension/
├── workshop.txt / preview.png / changelog.txt      ← 工坊物品根（只有 Contents/ 会被打包）
├── docs/
│   ├── design.md                                   设计文档（架构/数据模型/降级矩阵/稳定性评级/风险）
│   ├── test-plan.md                                进游戏测试清单 T1~T20 + 多人 M1~M4 + Y1~Y14 + V1~V12
│   └── research/                                   各扩展点的逆向报告（证据优先）
│       ├── economy-integration-hooks.md            橙子经济的 UI / 协议 / 货币 / 翻译扩展点
│       ├── yese-integration-hooks.md               YeseMarket 的对应扩展点
│       ├── jeem-recruit-api.md                     Jeem 招募链路 + A-Life 生成/跟随 API
│       ├── vanilla-money-integration.md            原版钞票（Base.Money）经济接入：面值/计数/扣款/退款/联机
│       └── vanilla-sidebar-entry.md                原版左侧竖排图标栏（ISEquippedItem）挂接 + 贴图规格
├── tools/
│   ├── make_images.py                              生成 preview.png(256) / poster.png(512)
│   ├── make_icons.py                               生成原版侧边栏图标（5 档 x 2 态，--check 自检）
│   ├── lua_syntax_check.mjs                        Lua 语法检查（fengari）
│   ├── extract_base.py                             公共层抽取的机械搬移 + 差异报告（--from-git 可永久复核）
│   ├── check_base.py                               公共层隔离守卫（零身份 / coreApi / 口味不撞车 / sibling 列全且不自指 / money 合法）
│   ├── fork_variant.py                             YeseMarket 口味 + 它的测试套件（防两份分叉）
│   ├── modinfo_probe/                              用游戏自己的解析器验 mod.info 与贴图路径（Java，无需 Steam）
│   ├── test/                                       橙子口味的离线逻辑测试（mock 三个依赖）
│   ├── test-yese/                                  YeseMarket 口味的同名套件（生成物）
│   └── test-vanilla/                               原版钞票口味的同名套件（50 条断言，50/50 通过）
└── Contents/mods/
    ├── Bin2NPCExtensionBase/42.21/                 ← 公共层（共享逻辑，只有这一份）
    │   ├── mod.info / poster.png
    │   └── media/lua/shared/Bin2NPCExtensionCore/  Namespace + 12 个工厂模块（Config/Text/Contracts/
    │                                               Store/Economy/Alife/Jimmy/Service/Maintain/Net/
    │                                               ServerBootstrap/ClientBootstrap）
    ├── Bin2NPCExtension/42.21/                     ← 橙子口味（12 个文件，Lua 只有 5 个）
    │   ├── mod.info（require=\Bin2NPCExtensionBase,…）/ poster.png
    │   └── media/
    │       ├── sandbox-options.txt
    │       └── lua/
    │           ├── shared/Bin2NPCExtension/Profile.lua   身份 spec + 实例化公共层
    │           ├── shared/Translate/{CN,EN}/IG_UI.json   本口味自己的翻译键空间
    │           ├── server/Bin2NPCExtension/Bootstrap.lua 只有一行：装服务端接线
    │           └── client/Bin2NPCExtension/Bootstrap.lua + ui/{Page,Entry}.lua
    ├── Bin2NPCExtensionYese/42.21/                 ← YeseMarket 口味（生成物，同上结构）
    └── Bin2NPCExtensionVanilla/42.21/              ← 原版钞票口味（不需要经济模组）
        ├── mod.info（require=\Bin2NPCExtensionBase,\ProjectALifeJimmy）/ poster.png
        └── media/
            ├── sandbox-options.txt                   默认价比另两个口味低（50 / 200 / 5，见 design.md §13.7）
            ├── ui/Sidebar/{48,64,80,96,128}/NPC_{On,Off}_<尺寸>.png   原版侧边栏图标（make_icons.py 生成）
            └── lua/
                ├── shared/Bin2NPCExtensionVanilla/Profile.lua       身份 spec（money = "cash"）
                ├── server/Bin2NPCExtensionVanilla/Bootstrap.lua     装服务端接线
                └── client/Bin2NPCExtensionVanilla/Bootstrap.lua + ui/{Icon,Panel}.lua
```
> 公共层 `media/lua/shared/Bin2NPCExtensionCore/` 除 12 个工厂模块外还有一个**手写**的
> `Cash.lua`（原版钞票收钱实现）；`poster.png` 是**独立产物**（`tools/make_images.py`），
> 不由 `fork_variant.py` 复制。

---

## 3. 与同域项目 `bin2_ProjectALifeNPCs_extensions` 的关系

本项目是那个项目（A-Life 扩展研究与开发目录）的**延续**，不是平行重复：

| 从它那里直接复用的东西 | 位置 |
| --- | --- |
| A-Life / Jeem 的扩展点与稳定性评级 | 它的 `docs/alife-extension-api.md`、`docs/extension-jeem-analysis.md` |
| 造人链路与"每角色令牌"幂等写法 | 它的 `Contents/mods/ALifeStartWithNPC/.../Grant.lua`（本模组 `Alife.spawn` 沿用同一套 `operationId` + 回滚） |
| 友好阵营挑选策略 | 它的 `Pick.lua`（本模组 `Alife.pickFactionProfile`） |
| 坑位清单（人口回收、orders 不持久化、读档重下） | 它的 `docs/start-with-npc-design.md`、`docs/pz-alife-mod-dev-report.md` |
| 工坊打包/校验流程与工具 | 它的 `workshop.txt` 排版、`tools/lua_syntax_check.mjs`（本模组直接复用） |

**这轮对照纠正了本模组的一个错误**：我们一度把自己的条目写进 `ProjectALife.ModCompat.known`。
但 `Compat.report()`（`ALifeModCompat.lua:314-330`）会遍历它、把启用中的条目按 `entry.verdict`
打印成 `[A-Life] compat: <name> (<id>) -> adapted: <note>` —— 也就是说第三方往里写，
等于借 A-Life 的口替自己背书。它的 `docs/integration-brainstorm.md` §1 早已写明"这不是注册 API"，
现已改成**只读**自检：跑 A-Life 自己的 `Compat.foreignCopies(active)`，把"自带 A-Life Lua 副本"的
模组点名报出来（这正是 NPC 生成/水合失败最常见的环境原因）。

## 4. 三条设计红线（来自 A-Life 生态的历史教训）

1. **网络 module 名必须是我们自己的 mod id**（每个口味各一个：`Bin2NPCExtension` /
   `Bin2NPCExtensionYese` / `Bin2NPCExtensionVanilla`）——
   `ProjectALife` 是 A-Life Debug 服务的白名单领地，第三方不得复用。
2. **只依赖对方的公开/半公开入口**，其余一律「存在性探测 + `pcall` + 缺失即禁用」；
   绝不复制别人私有存档的内部形状（Jeem 的直接写声望表就是反例）。
3. **钱只能走"服务端权威"的那条路**：经济模组口味走它的服务端 API
   （`OrangeTradingModServer.Pay` / `YeseMarketServer.Pay`），原版钞票口味由**服务端**
   删/发物品并显式发包（`sendRemoveItemsFromContainer` / `sendAddItemsToContainer`）；
   客户端传来的价格一律不采信，服务端自己重算（见 `docs/design.md` §13.2/§13.3）。

---

## 5. 构建与校验（无需编译，Lua 运行时加载）

| 手段 | 结果（2026-10-06） |
| --- | --- |
| Lua 语法检查（**四个**模组，29 个文件） | `files=29 failed=0` |
| 离线逻辑测试 —— 橙子口味（mock A-Life / Jeem / 橙子经济，40 条断言） | `40/40 passed` → `ALL PASS` |
| 离线逻辑测试 —— YeseMarket 口味（同 40 条，生成物） | `40/40 passed` → `ALL PASS` |
| 离线逻辑测试 —— 原版钞票口味（`tools/test-vanilla/`） | `50/50 passed, 0 failed` / `ALL PASS`（钱的原版物品栏 mock + 侧边栏挂接 + 窗口命令） |
| 公共层隔离守卫 | `公共层零身份 + 3 个口味互不撞车：OK`（含 `Core.API = 2`、`money=cash, upstream`） |
| 变体与生成器一致性 | `变体与生成器一致（mod 11 文件 / test 5 文件）` |
| 抽取等价性复核 | `公共层 12 个文件与机械搬移结果一致`（合计改动 347 行，全部逐条列出） |
| 侧边栏图标资产 | `图标齐全且尺寸正确（5 档 x 2 态）`（48x36 … 128x96 RGBA） |
| mod.info（游戏自己的解析器） | **四个模组** `ALL MOD.INFO PARSED`，三条 `require=Bin2NPCExtensionBase[ok]` |
| 贴图路径（游戏自己的解析器） | `ALL PATHS RESOLVED`：10 张侧边栏图全部由 `media.version`（`<mod>/42.21/media`）解析 |
| 工坊探针（游戏自己的解析器） | `readWorkshopTxt=true`、tags 全在白名单、`validatePreviewImage=OK`、简介 7848 字节 / 提交 7873 字节（上限 8000） |
| 仓库级 `check_all.sh` | `ALL CHECKS PASSED (18 item(s))` |

> **本表只写实测过的数字。** 原版钞票口味的游戏内行为（`docs/test-plan.md` V1~V12）
> **一条都没跑过**（离线套件 50/50 只覆盖逻辑，覆盖不了观感与实机 API）——
> 有疑问的地方写"未证实 + 验证方法"，不要用推断填空。

离线测试抓出并修掉了 4 个真缺陷（关闭闸门缺失、周期重下丢 `quiet`、退款不写流水、
派遣后不校验 actor 是否还在），详见 `docs/design.md` §8.1。

```bash
# Lua 语法检查（本机无 lua 解释器，用仓库自带 fengari）
NODE=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin
PATH="$NODE:$PATH" node tools/lua_syntax_check.mjs Contents/mods/Bin2NPCExtensionBase \
    Contents/mods/Bin2NPCExtension Contents/mods/Bin2NPCExtensionYese \
    Contents/mods/Bin2NPCExtensionVanilla

# 离线逻辑测试（mock A-Life / Jeem / 经济模组，不启动游戏；已就绪的两个口味各 40 条）
tools/test/run_lua_test.sh
tools/test-yese/run_lua_test.sh
tools/test-vanilla/run_lua_test.sh     # 原版钞票口味的套件（50 条断言）

# 公共层不变量（零身份 / coreApi / 口味不撞车 / sibling 列全且不自指 / money 合法）
python3 tools/check_base.py
# 变体仍是生成物（防有人手改）
python3 tools/fork_variant.py --check
# 抽取等价性复核（把公共层与抽取前那份代码逐字比对）
python3 tools/extract_base.py --from-git 33f24e3
# 用游戏自己的解析器读 mod.info（确认 require=Bin2NPCExtensionBase 被认出来）
# 以及确认 42.21/media/ui/... 的贴图能被引擎解析到
tools/modinfo_probe/run.sh

# 重新生成图（纯 Pillow，无网络）
python3 tools/make_images.py      # preview.png + 三个口味各自的 poster.png
python3 tools/make_icons.py       # 原版侧边栏图标 5 档 x 2 态（--check 只校验）

# 本地加载目录（游戏 Mods 列表里会出现；**四个都要软链**，公共层缺了 require 找不到它）
ln -sfn "$PWD/Contents/mods/Bin2NPCExtensionBase"    ~/Zomboid/mods/Bin2NPCExtensionBase
ln -sfn "$PWD/Contents/mods/Bin2NPCExtension"        ~/Zomboid/mods/Bin2NPCExtension
ln -sfn "$PWD/Contents/mods/Bin2NPCExtensionYese"    ~/Zomboid/mods/Bin2NPCExtensionYese
ln -sfn "$PWD/Contents/mods/Bin2NPCExtensionVanilla" ~/Zomboid/mods/Bin2NPCExtensionVanilla
# 工坊待上传目录
ln -sfn "$PWD" ~/Zomboid/Workshop/bin2_npc_extension

# 上传前用游戏自己的解析器校验（不会真的上传）
bash bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/bin2_npc_extension
```

过程记录见仓库 `docs/rolling_log.md`；进游戏验证按 `docs/test-plan.md` 逐条跑（T1~T20 橙子口味 / M1~M4 多人 / Y1~Y14 YeseMarket / V1~V12 原版钞票）。
