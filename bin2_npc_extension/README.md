# bin2_npc_extension

> **经济模组 × A-Life 的 NPC 招募扩展**（一个工坊物品，两个口味）
> Mod ID：`Bin2NPCExtension`（橙子社区经济版）/ `Bin2NPCExtensionYese`（YeseMarket 版）
> 工坊 id：**3813914438**（已发布，public）｜ 归属：`bin2` 系列
> 状态：已进游戏跑通基础流程，完整清单（`docs/test-plan.md` T1~T20 / M1~M4 / Y1~Y12）未跑完
> 建档：2026-10-05

---

## 1. 这是什么

一个**独立扩展模组**，把「招募 NPC」做成橙子社区经济里的一门生意：

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
| 橙子社区经济 | `3777900792` | UI 容器 + 玩家钱包（唯一付款渠道） | 硬依赖：整个模组静默禁用 |
| Project A-Life | `3803984183` | NPC 本体、生成、跟随指令 | 页面可用但招募按钮禁用，并给出提示 |
| Jeem Extension | `3806944055` | 「居民」岗位（营地/岗位/作息/声望） | 只保留跟随/守卫两种岗位 |

依赖与兼容对象的逆向取证见：

* `docs/research/economy-integration-hooks.md` —— 橙子经济对外开放的扩展点
* `docs/research/jeem-recruit-api.md` —— Jeem 招募链路 + A-Life 生成/跟随 API
* `docs/design.md` —— 本模组的功能与实现设计（含降级矩阵、存档格式、风险清单）

---

## 1.5 一个物品里的两个模组

| mod id | 配哪个经济模组 | 入口 | 备注 |
| --- | --- | --- | --- |
| `Bin2NPCExtension` | 橙子社区经济（`OrangeCommunityEconomy`，3777900792） | 首页「NPC 招募」按钮 + Ctrl+Alt+N | 已进游戏跑过基础流程 |
| `Bin2NPCExtensionYese` | YeseMarket（3735641567） | **导航栏插一行**「NPC Recruit」+ Ctrl+Alt+N | **尚未进游戏验证** |

两者共用同一套 A-Life / Jeem 招募内核（契约、维护循环、命令路由），差别只在"钱包 + UI 容器"：
YeseMarket 版的 `Config`/`Economy` 由替换表生成，只有 `ui/Entry.lua` 是**独立实现**
（它的 `Open(playerNum)` 不接受 pageId、首页也没有橙子版那两个锚点）。
两份可以同时启用；各自的名册会互查，同一个 NPC 不会被两边同时雇走。

> **变体目录是生成物**：`Contents/mods/Bin2NPCExtensionYese/` 与 `tools/test-yese/` 都由
> `tools/fork_variant.py` 产出，`--check` 会在有人手改变体时报差异（防两份核心代码悄悄分叉）。
> 要改变体，改生成器的替换表/补丁，而不是直接改变体文件。

## 2. 目录导览

```
bin2_npc_extension/
├── workshop.txt / preview.png / changelog.txt      ← 工坊物品根（只有 Contents/ 会被打包）
├── docs/
│   ├── design.md                                   设计文档（架构/数据模型/降级矩阵/稳定性评级/风险）
│   ├── test-plan.md                                进游戏测试清单 T1~T20 + 多人 M1~M4 + YeseMarket Y1~Y12
│   └── research/                                   两端扩展点逆向报告
│       ├── economy-integration-hooks.md            橙子经济的 UI / 协议 / 货币 / 翻译扩展点
│       └── jeem-recruit-api.md                     Jeem 招募链路 + A-Life 生成/跟随 API
├── tools/
│   ├── make_images.py                              生成 preview.png(256) / poster.png(512)
│   ├── lua_syntax_check.mjs                        Lua 语法检查（fengari）
│   └── test/                                       离线逻辑测试（mock 三个依赖）
└── Contents/mods/Bin2NPCExtension/42.21/
    ├── mod.info / poster.png
    └── media/
        ├── sandbox-options.txt
        └── lua/
            ├── shared/Bin2NPCExtension/{Config,Contracts,Text}.lua + Translate/{CN,EN}/
            ├── server/Bin2NPCExtension/{Store,Alife,Jimmy,Economy,Service,Maintain,Bootstrap}.lua
            └── client/Bin2NPCExtension/{Net,Bootstrap}.lua + ui/{Page,Entry}.lua
```

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

1. **网络 module 名必须是我们自己的 mod id**（`Bin2NPCExtension`）——
   `ProjectALife` 是 A-Life Debug 服务的白名单领地，第三方不得复用。
2. **只依赖对方的公开/半公开入口**，其余一律「存在性探测 + `pcall` + 缺失即禁用」；
   绝不复制别人私有存档的内部形状（Jeem 的直接写声望表就是反例）。
3. **钱只能走橙子经济的服务端 API**（`OrangeTradingModServer.Pay`）；
   客户端传来的价格一律不采信，服务端自己重算。

---

## 5. 构建与校验（无需编译，Lua 运行时加载）

| 手段 | 结果（2026-10-05） |
| --- | --- |
| Lua 语法检查（14 个文件） | `files=14 failed=0` |
| 离线逻辑测试（mock A-Life / Jeem / 橙子经济，33 条断言） | `33/33 passed` → `ALL PASS` |
| 工坊探针（游戏自己的解析器） | `readWorkshopTxt=true`、tags 全在白名单、`validatePreviewImage=OK` |
| 仓库级 `check_all.sh` | `ALL CHECKS PASSED (18 item(s))` |

离线测试抓出并修掉了 4 个真缺陷（关闭闸门缺失、周期重下丢 `quiet`、退款不写流水、
派遣后不校验 actor 是否还在），详见 `docs/design.md` §8.1。

```bash
# Lua 语法检查（本机无 lua 解释器，用仓库自带 fengari）
NODE=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin
PATH="$NODE:$PATH" node tools/lua_syntax_check.mjs Contents/mods/Bin2NPCExtension

# 离线逻辑测试（mock A-Life / Jeem / 橙子经济，不启动游戏）
tools/test/run_lua_test.sh

# 重新生成两张图（纯 Pillow，无网络）
python3 tools/make_images.py

# 本地加载目录（游戏 Mods 列表里会出现）
ln -sfn "$PWD/Contents/mods/Bin2NPCExtension" ~/Zomboid/mods/Bin2NPCExtension
# 工坊待上传目录
ln -sfn "$PWD" ~/Zomboid/Workshop/bin2_npc_extension

# 上传前用游戏自己的解析器校验（不会真的上传）
bash bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/bin2_npc_extension
```

过程记录见仓库 `docs/rolling_log.md`；进游戏验证按 `docs/test-plan.md` 的 T1~T20 逐条跑。
