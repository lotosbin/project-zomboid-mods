# 开发日志 - 2026-10-12

承接 `docs/develop_log_2026-10-06.md`（v0.4.0：第四个模组 `Bin2NPCExtensionVanilla`，纯原版钞票 +
屏幕左侧原版图标栏入口）。今天这一轮是 **v0.5.0**：

> `Bin2NPCExtensionYese` 也要在**游戏原版左侧竖排侧边栏**（心/背包/建造那一列，`ISEquippedItem`）里
> 有一个入口 —— 点一下开关 YeseMarket 的**幸存者交易站**窗口。

一句话概括技术核心：**同一段"往原版 HUD 追加图标"的挂接，第二个口味要用时不是复制一份，而是抬
`Core.API` 把它变成公共层模块**；顺带把"工坊简介有硬字节上限"这件事从一次踩坑变成一条流程。

---

## 课题一：先证明"这个入口真的不存在"

需求听起来像"再做一个已有入口的快捷方式"，所以在动手前先把 YeseMarket 全库过了一遍：

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| YeseMarket 有没有交易站的按键绑定 | **没有**，一处都没有 | 全库 `getKeyBindings` / `addKeyBinding` / `Bind` 零命中 |
| 有没有别的快捷入口 | **没有**，只有右击菜单里的「打开幸存者交易站」 | `client/` 下的上下文菜单注册；交易站窗口只能从那里出 |
| 我们自己的 `Ctrl+Alt+N` 算不算 | **不算**，它直达**招募页**（我们插的那一页），不是交易站 | `Entry.open` → `setPage(pageId)` |
| 句柄长什么样 | `YeseMarket.Window` 是唯一窗口句柄；`YeseMarket.Open(playerNum)` 只吃一个参数、**不返回窗口** | `client/event_handlers.lua:299`；`client/ui/shell.lua:991-1029` 的 `close()` 会 `setVisible(false)` + `removeFromUIManager` + 把句柄置 nil |

结论：这是一个**真缺口**，不是重复入口。同时也决定了实现里最重要的一条：
`isOpen` 必须**现算**（读 `YeseMarket.Window ~= nil`），不能缓存 —— 玩家用窗口右上角的 × 关掉时，
只有 `close()` 知道。

## 课题二：抽到公共层，并抬 `Core.API` 2 → 3

Vanilla 口味在 v0.4.0 已经做过同一件事（后置 hook `ISEquippedItem:initialise` 追加按钮、
`shrinkWrap()`、按钮引用挂在面板自己身上……）。第二个口味再抄一份立刻会撞两条红线：

* 公共层**零身份**（`tools/check_base.py`）：挂接逻辑天然要读各口味的东西（贴图名、tooltip、
  点一下干什么），写进口味文件又变成"两份要同步的代码"；
* 更实际的理由是**加载期**。新版口味在**文件加载期**就会调 `Config.Sidebar.install(spec)`；
  如果玩家只更新了口味没更新公共层，那一刻就是 `attempt to index a nil value (field 'Sidebar')` ——
  而这个错误会被 `ClientBootstrap` 的 `pcall` 吞掉。**玩家看到的是入口静默消失，日志里一行 ERROR 都没有。**

所以：新模块 `Bin2NPCExtensionCore/Sidebar.lua`（手写、中性），`Core.API` 从 2 抬到 3，
让"只更新了一半"变成启动时一句明确的 `public layer mismatch: … coreApi …`。

### `Sidebar.install(spec)` 的契约（`docs/design.md` §13.4）

| 项 | 约定 | 为什么 |
| --- | --- | --- |
| 返回值 | `true` = 装好或不需要；`false` = **原版侧边栏还没就绪**，调用方自己重试 | 原版 `ISEquippedItem` 的创建时机不受我们控制（分屏/重生/改尺寸都会重建） |
| `spec.id` | 必填、internal 风格、**同一面板内唯一** | 面板上按 id 存引用，重建后才能认出"这是我的按钮" |
| `spec.texture` | 必填，`media/ui/Sidebar/<W>/<name>_{On,Off}_<W>.png` | 尺寸档由原版按钮宽度决定 |
| `spec.toggle` | 必填 `function(playerNumber)` | 点了干什么，各口味自己定 |
| `spec.isOpen` | 可选，现算 | 决定图标 On/Off 两态 |
| `spec.tooltip` | 可选，**已经翻译好的文案**（不是翻译键） | 见下 |
| 引用位置 | `panel.bin2NpcSidebar[spec.id].button` | 原版改"侧边栏尺寸"会**整体重建**面板，挂模块全局会变出第二个图标 |
| 幂等判据 | `Sidebar.hooked == 面板类表` | 引擎 "Reset Lua" 重跑文件不会重复 hook |
| 范围 | 每个命名空间只认**第一张** spec；只给 **player 0** 装 | 原版按钮列本身就包在 `if getPlayerNum() == 0` 里 |

**tooltip 为什么收"已翻译文案"而不是翻译键**（这条看着别扭，但有两个真实理由）：

1. 公共层不认识任何翻译前缀，认识就等于认识口味身份 —— 直接违反零身份守卫；
2. 各套件的 `run.js` 翻译键扫描器只认源文件里的 `T("IconTooltip")` **字面量**。如果公共层自己去查键，
   Vanilla 套件那条"83 条字面量键"的断言会掉到 82。

第 2 条意味着：**是测试在替我们守这条设计约束**。一个"看起来只是风格"的决定，被断言钉住了。

## 课题三：三个口味各交什么

* **Yese**：`id="BIN2NPCTRADE"`、`texture="Trade"`、`tooltip=T("IconTooltip")`、
  `isOpen=Entry.isMarketOpen`、`toggle=Entry.toggleMarket`。
  `Entry.install()` 改成返回 `marketReady and sidebarReady`：侧边栏没就绪就返回 false 让公共层重试，
  只 WARN 一次（`Entry.sidebarWarned`）；**热键路径 `Entry.open` 完全独立**，上游界面坏了也照常可用。
* **Vanilla**：行为不变，`Icon.lua` 从"自己 hook"瘦成"一份 spec + 委托 + `Icon.open()`"。
* **橙子口味**：本来就没有原版侧边栏入口（它的入口是经济主界面首页按钮），但**公共层的新模块它也要
  跟着装**，所以它的套件新增了 5 条**与 spec 无关**的公共层用例。

新翻译键 `IGUI_Bin2NPCExtensionYese_IconTooltip`（Yese 的 CN/EN `IG_UI.json` 各 93 条键）。

## 课题四：图标资产两套化

`tools/make_icons.py` 参数化成两套口味参数（`NPC` / `Trade`），新增 `--only`，并加了 `render_market`
（On 态金币外圈 `(236,170,48)`）。生成 10 张 `Trade_{On,Off}_<W>.png` 到 Yese 的
`42.21/media/ui/Sidebar/{48,64,80,96,128}/`；**原先那 10 张 `NPC_*` 重新生成后逐字节相同**
（`git status` 干净 —— 这条就是"没顺手改坏旧资产"的证据）。

尺寸仍是硬约束不是审美：原版实测 48x36 / 64x48 / 80x60 / 96x72 / 128x96（W x 0.75W）；
交一张正方形会被 `ISButton:render` 的 `drawTextureScaledAspect` 等比缩掉。
`docs/assets/yese-sidebar-icons.png` 是与既有 `sidebar-icons.png` 同风格的对照图
（列 = NPC Off/On + Trade Off/On，行 = 48/96/128，×3 最近邻）。

## 课题五：测试升级 —— 以及一个**假绿**

公共层模块要有自己的用例，但用例**不能认识任何口味**。新增的 5 条（41–45）做法是：

* `activeSpec()` / `iconOf(panel, id)` / `countIcons(panel)` / `expectedTexture()` 四个探针；
* **就地把 `spec.toggle` / `spec.isOpen` 换成自己的函数**，然后观察公共层有没有老实调用它们 ——
  断言的是"公共层的行为"，不是"某个口味今天怎么写的"。

同时把源套件（`tools/test/mock_env.lua`）的 mock 升级成 Vanilla 那份忠实版：真的 `ISEquippedItem`
类表、`ISButton`、`panel:addToUIManager()`、`getPlayerData`、以及**改尺寸整体重建面板**。

**踩到的坑（本轮最值得记的一条）**：那份 mock 的 UI 底座原本把方法挂在**实例**上。
于是 hook 到**类表**上的包装方法永远被实例方法遮蔽 —— "面板重建后会重新 attach"这条断言
**永远是绿的**，被测量代码怎么坏都测不出来。改成方法挂**类表**
（`ISPanel.initialise(self)` 这种调用形状才是原版真实的形状）之后，它才真的能红。

> 这是"mock 忠实度 = 测试价值"的第二次咬人（第一次是 v0.4.0 的 `ISButton.onclick(target, self)`
> 参数顺序）。**弱化 mock 的每一处，都会让某条断言退化成「永远为真」。**

## 课题六：工坊简介有硬上限，这次真的撞上了

加完 v0.5.0 的说明后，`workshop.txt` 的 `submitDescription` 变成 **8608 字节 > 8000**（Steam 上限）。
仓库级探针 `bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh` 直接报了出来 ——
它是用游戏自己的 `SteamWorkshopItem` 解析出来的数字（**简介 7893 / 提交 7918**，上限 8000），
不是我们自己数的，所以我们的估计没有意义。

做法：删掉**名词解释性的重复**与**可推断的细节**，不删事实 —— 版本历史细节本来就在 `changelog.txt` 里，
所以更新记录压到每条 1~2 行；"背着的背包里的都算"这类可从别处推出的修饰语直接去掉。
每个口味各自的钱、入口、依赖、沙盒差异全部留着。

> 沉淀：工坊简介是**有硬上限的对外文案**。以后每次给它加段落，都要让探针先过一遍，
> 而不是等上传时才发现。

## 验证（本轮实测，可复现）

```
tools/lua_syntax_check.mjs <四模组 + 三套测试>     → files=36 failed=0
tools/test/run_lua_test.sh --quick               → 45/45 passed, ALL PASS（原 40 条 + 新 5 条）
tools/test-yese/run_lua_test.sh --quick          → 45/45 passed, ALL PASS（生成物）
tools/test-vanilla/run_lua_test.sh --quick       → 50/50 passed, 0 failed, ALL PASS
python3 tools/check_base.py                      → 公共层零身份 + 3 个口味互不撞车：OK（Core.API = 3）
python3 tools/fork_variant.py --check            → 变体与生成器一致（mod 11 文件 / test 5 文件）
python3 tools/extract_base.py --from-git 33f24e3 → 公共层 12 个文件与机械搬移结果一致（379 行）
python3 tools/make_icons.py --check              → 图标齐全且尺寸正确（2 套 x 5 档 x 2 态 = 20 张）
tools/modinfo_probe/run.sh                       → ALL MOD.INFO PARSED（4 模组）
                                                   + 两段 ALL PATHS RESOLVED（NPC_* 10/10、Trade_* 10/10）
bash bin2_workshop_upload_fix/.../check_all.sh    → ALL CHECKS PASSED (18 item(s))
```

> `extract_base.py --from-git` 复核的是"公共层 12 个搬迁文件仍与抽取前逐字一致"；本轮**手写**的
> `Namespace.lua` / `Cash.lua` / `Sidebar.lua` 不在那 12 个里，所以它们的变化不会让它变红 ——
> 这也是它能继续用的原因（不带 `--from-git` 的旧用法已经读不到源口味文件了，属预期，不修）。

## 未做 / 交给下一轮

* **游戏内一条都没跑**：交易站图标的实际观感、两态切换、窗口被 × 关掉后再点开、
  `Ctrl+Alt+N` 是否仍直达招募页 —— 逐条清单在 `docs/test-plan.md` 的 **Y15 / Y16**。
* **实机 `getTexture` 未证**：探针只证明"20 张贴图路径能被 `media.version`（`<mod>/42.21/media`）解析"，
  不等于运行时纹理对象拿到图。
* **128 档图标是否超出屏幕底部**只有手算（`8W+135`），未实测。
* **手柄**：原版图标栏本身没有手柄导航，所以这个新入口只能用鼠标点（键盘只能走 `Ctrl+Alt+N` 开招募页）。
  要补的话，挂 `ISDPadWheels.onDisplayRight` 往手柄圆盘菜单里加一格是最贴近原版的做法。
* **工坊未重新上传**：线上仍是上一版；v0.5.0 的说明只在本地 `workshop.txt` 里。

> 沉淀（四条，已同步进 `docs/rolling_log.md`）：
> ① **第二个使用者出现时，才是抽象的真正时刻** —— 而且理由往往不是"少写代码"，是**加载期错误的可见性**
> （`pcall` 吞掉的 nil 索引 = 静默消失的入口）；
> ② **mock 挂方法的位置就是断言的生死线** —— 实例方法遮蔽类表方法，会让一条断言永远为真；
> ③ **对外文案有硬上限，探针口径才算数** —— 简介超限这类错误，自己数字节永远算不准；
> ④ **"看着只是风格"的决定也要被断言钉住** —— tooltip 收已翻译文案这件事，靠翻译键扫描器的计数守住了。
