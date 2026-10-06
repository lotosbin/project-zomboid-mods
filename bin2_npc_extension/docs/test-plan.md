# Bin2NPCExtension 进游戏测试清单（T1~T20 / M1~M4 / Y1~Y14 / V1~V12）

> 前提：本物品有 **1 个公共层 + 3 个口味**（橙子社区经济 / YeseMarket / 原版钞票）。
> 下面 T / M 两组以**橙子口味**为准；Y 组是 YeseMarket 口味；V 组是原版钞票口味。
> 每个口味都要求公共层 `Bin2NPCExtensionBase` 一起启用（`mod.info` 的 `require=` 会自动带上它）。
> 本仓库 `bin2_npc_extension` 的各模组已软链到 `~/Zomboid/mods/` 并在游戏 Mods 里启用。
> 建议先把沙盒 `Bin2NPCExtension.DebugLog` 设为 **true**，测完再关。
> 判定日志统一前缀：`[Bin2NPCExtension]`。日志文件：`~/Zomboid/console.txt`。

## 准备

```bash
# 公共层 + 你要测的那个口味（四个都要时才全都链）
ln -sfn "$PWD/bin2_npc_extension/Contents/mods/Bin2NPCExtensionBase"    ~/Zomboid/mods/Bin2NPCExtensionBase
ln -sfn "$PWD/bin2_npc_extension/Contents/mods/Bin2NPCExtension"        ~/Zomboid/mods/Bin2NPCExtension
ln -sfn "$PWD/bin2_npc_extension/Contents/mods/Bin2NPCExtensionYese"    ~/Zomboid/mods/Bin2NPCExtensionYese
ln -sfn "$PWD/bin2_npc_extension/Contents/mods/Bin2NPCExtensionVanilla" ~/Zomboid/mods/Bin2NPCExtensionVanilla
```

| 组 | 用例 | 期望 | 失败时先看 |
| --- | --- | --- | --- |
| A 加载 | T1 单人新档启动 | `loaded v0.1.1 \| economy=true(server=true) alife=true jeem=…`；`client ready … page=true`；无 ERROR | 橙子经济是否启用；`loadModAfter` 是否生效 |
| A 加载 | T2 主菜单 Mods 列表 | mod 名/描述/海报正常，`require` 不报缺依赖 | `mod.info` 的 `require`/`id` |
| B 入口 | T3 打开橙子经济主界面 | 首页出现「NPC 招募」按钮（在「社区中心」左边），中文标题不溢出 | `Entry.install` 是否有 `recruit page registered` 日志 |
| B 入口 | T4 按 Ctrl+Alt+N | 直接打开招募页；与其它模组/原版按键不冲突 | T3 是否通过 |
| B 入口 | T5 沙盒关掉 `Enabled` 重进 | 首页无按钮；服务端命令返回 `disabled`；契约保留 | `Config.enabled()` |
| C 收编 | T6 身边有 A-Life NPC 时开「收编」页 | 列出 NPC（名字/阵营/距离），距离 ≤ RecruitRadius | A-Life 是否真的在跑；`Watchdog.bindings` |
| C 收编 | T7 点「收编」 | 余额减少 = SignPrice；名册出现该 NPC；日志 `hired … for 500` | `Pay` 是否返回 false |
| C 收编 | T8 收编一个远处的 NPC（先在面板外走远再刷新） | 返回「离得太远」，**不扣钱** | `RecruitRadius` |
| C 收编 | T9 余额 <2 价位时收编 | 返回「社区货币不足」，名册为空，余额不变 | `ReasonNoFunds` |
| C 收编 | T10 把 MaxContracts 设为 1 后再收编第二个 | 「雇员名额已满」 | `activeCount` |
| D 派遣 | T11「中介派遣」 | 身边生成一名友好 NPC；余额减少 = SpawnPrice；日志 `spawned …` + `summoned …` | A-Life 人口上限（`ALife.Population_HostileCeiling`） |
| D 派遣 | T12 把人口上限调到最小后再派遣 | 失败并**全额退款**（`refunded …`），名册无残留 | `spawn_failed` 分支 |
| E 岗位 | T13 跟随 | 雇员跟过来；走远再回来它仍在跟（8 秒内重下指令） | `orderFollow` 的 `order_*` 失败串 |
| E 岗位 | T14 守卫 | 雇员停在签约位置附近；你走远它不跟 | `orderHold` 的锚点 |
| E 岗位 | T15 居民（需 Jeem） | 雇员进营地（可能在你自己基地或自动建的小营地）；面板岗位显示「居民」 | `R.recruit` 的失败串会写在 `最近事件` |
| E 岗位 | T16 没装 Jeem 时点居民 | 退化为跟随，面板显示原因；日志 `resident conversion unavailable` | — |
| F 运维 | T17 读档 | 指令恢复（≤8 秒），名册仍在，无重复 NPC | `restored orders for active contracts` |
| F 运维 | T18 工资 / 阵亡 / 欠薪 | 跨 24 小时扣一次日薪（`wage … paid`）；余额清零后 `unpaid=true`，超宽限期自动解约；杀死雇员后名册显示「阵亡」且名额释放 | `Maintain.settleWages` / `Maintain.tick` |
| E 岗位 | T19 对一名**已经是居民**的雇员反复点「居民 → 应用岗位」 | 岗位稳定显示「居民」，`最近事件` 为空；不再出现「居民化被拒（resident（上游返回））」；控制台无 `resident conversion refused` | 服务端幂等预读（`Service.applyMode` / `Jimmy.residentEntry`）；若仍报，说明直接调了 `R.recruit` |
| E 岗位 | T20 让 NPC 在**面板之外**变成居民（Jeem 右键「邀请入住」，或让同小队的另一名契约带他一起入住） | 30 秒内名册那一行自动变成「岗位：居民」；控制台出现 `reconcile: <uid> is a Jeem resident (base …) but this contract said follow; corrected to resident` | `Maintain.reconcile`；`Maintain.restore` 进世界会把对账时间戳清零 |

## 多人补充（专用服，用非管理员账号）

| 用例 | 期望 |
| --- | --- |
| M1 两名玩家同时收编同一个 NPC | 一人成功，另一人 `taken_by_other`；只扣一次钱 |
| M2 非管理员转居民 | 若 `MakeAllied=true` 且 `addGroup` 生效则成功；否则降级为跟随（面板写明原因），不报错 |
| M3 客户端看不到服务端 ModData 的情况下 | 面板数据仍完整（走 `sendServerCommand` 推送，不读 ModData） |
| M4 玩家掉线再上线 | 名册恢复；跟随指令在 ≤8 秒内重下 |

## 记录模板

```
T7：结果=通过/失败；console 关键行=<粘贴 5~10 行>；截图=<文件名>；备注=<…>
```

## 明确未验证的部分（写工坊声明时不要美化）

* ~~`StandingService.addGroup(key, groupId, factionId, 400)` 是否真能把 `R.isAlly` 变成真~~
  —— **已进游戏验证**（v0.2.2 那轮：签约后 Jeem 自己记账 `residents: bin2 invited 1 (…) to base base:1`，
  即 `R.recruit` 的 `not_allied` 门槛已通过）
* 转居民时「整支小队一起进营地」的实际观感
* 首页按钮与「社区中心」按钮的排布是否永远不重叠（对方改布局就会变）
* 与其它 NPC 模组（Bandits2、The Mutants 等）的共存

## YeseMarket 版（`Bin2NPCExtensionYese`）补充用例

同一物品里的 YeseMarket 口味配 [YeseMarket](https://steamcommunity.com/sharedfiles/filedetails/?id=3735641567)。
它的入口不是首页按钮，而是**导航栏新插的一行**，所以下面这几条必须单独跑一遍：

| 组 | 用例 | 期望 | 失败时先看 |
| --- | --- | --- | --- |
| Y 入口 | Y1 装 YeseMarket + 本模组（**不要**装橙子版依赖） | 控制台 `recruit page registered; YeseMarket navigation row installed` | `Config.economy()` 是否拿到 `YeseMarket` |
| Y 入口 | Y2 开 YeseMarket 界面 | 左侧导航栏**多出一行**「NPC Recruit」，在最后一行下方 | 上游是否改了 `navButtons` / `navigationButtonHeight` 等字段名 |
| Y 入口 | Y3 点那一行 | 右侧切到招募页（**不是**首页） | `setPage` 是否放行我们的 pageId |
| Y 入口 | Y4 按 Ctrl+Alt+N | 从任意时刻都能打开招募面板；与 YeseMarket 自带按键不冲突（它全库零绑定） | 热键是这条路径的兜底 |
| Y 入口 | Y5 先关窗口再按热键 | 会先开窗再切到招募页（`Open(playerNum)` → `Window:setPage`），不会停在首页 | `Open` 只吃一个参数 |
| Y 功能 | Y6 收编 / 派遣 / 岗位 / 工资 / 解雇 | 与 T6~T18 相同；货币显示为「金币」 | 记账看 `RecordPlayerFlow` 的 out/in 两行 |
| Y 队友 | Y10 用面板雇一名 NPC（跟随）→ 让他当居民/队友 | 能成功：`labelFor == allied`（或小队点数 ≥50），Jeem 右键「邀请入住」也能过 | 控制台应有 `standing <faction> -> allied (was hostile), group … = 400 (needs >= 50)`；若报 `not_allied`，说明签约时没垫声望 |
| Y 队友 | Y11 把沙盒 `MakeAllied` 关掉再雇 | 雇得成，但转居民会被拒（`not_allied`）—— 这是选项的预期行为 | 这时需要玩家自己刷 Jeem 声望 |
| Y 岗位 | Y12 「应用岗位」的两步流程 | 点「跟随/守卫/居民」只高亮选中、**不发命令**；再点「应用岗位」才生效；岗位没变时按钮是灰的（不重发 = 不再触发 `resident` 拒绝） | 这轮线上 bug 的根因就在"按钮点一下立刻发 + 应用又发当前岗位" |
| Y 岗位 | Y13 拒绝原因的文案 | 所有岗位失败都显示中文原因（如「床位不够」「他们对你信任不足（需要同盟关系）」），**不出现**「（上游返回）」 | `Text.lua` 的 REASONS 是否穷举了 Jeem 的拒绝码；未知码才走兜底 |
| Y 共存 | Y7 三个口味同时启用 | 三个界面各自可开；**同一个 NPC 只能被一边雇走**（另两边报「已被其他玩家雇佣」） | `Service.takenBySibling` 互查 |
| Y 界面 | Y8 看导航那一行的按钮文字 | 显示「NPC 招募」，**不是** `IGUI_YeseMarket_EntryButton` 这种原始键 | 标题必须取自本模组自己的翻译表（对方 `Text()` 会强制加它自己的前缀） |
| Y 公共 | Y14 公共层缺失 / 版本不符 | 勾了口味但没勾公共层（或只更新了一半）时：控制台一行 `[Bin2NPCExtension][ERROR] Bin2NPCExtensionBase is missing or not enabled…` 或 `public layer mismatch: … coreApi …`，功能不生效但**不报错、不崩** | 公共层与该口味都要启用；`mod.info` 的 `require=\Bin2NPCExtensionBase` 正常会自动勾上公共层 |
| Y 界面 | Y9 招募页里的雇员/候选列表 | 每行是四行信息的卡片样式，点击能选中（高亮），滚动正常 | 列表用 `CreateList` + `doDrawItem`；若报 `call nil`，说明又用了橙子独有的 `CreateCardGrid` |

## 原版钞票口味（`Bin2NPCExtensionVanilla`）补充用例

第三个口味（`docs/design.md` §13）**不依赖任何经济模组**：钱用原版物品 `Base.Money` / `Base.MoneyBundle`，
入口是原版左侧竖排图标栏（`ISEquippedItem`）最下面的一个 NPC 图标，招募窗口是自己画的 `ISUI`。
所以它的失败面与前两个口味完全不同（钱算术、原版 HUD 挂接），必须单独跑。

### 离线（不启动游戏）

```bash
# 新口味的离线套件（tools/test-vanilla/，与其它两个同构）
tools/test-vanilla/run_lua_test.sh --quick

# 侧边栏图标资产：5 档 x 2 态的尺寸/模式/大小
python3 tools/make_icons.py --check

# mod.info + 贴图路径（用游戏自己的解析器；四个模组都要在 ~/Zomboid/mods/ 下有软链）
tools/modinfo_probe/run.sh

# 公共层不变量（零身份 / coreApi / 口味字段不撞车 / sibling 不自指且列全 / money 合法）
python3 tools/check_base.py

# 变体目录仍与生成器一致（防有人手改生成物）
python3 tools/fork_variant.py --check

# 抽取等价性复核（把公共层与抽取前那份代码逐字比对）
python3 tools/extract_base.py --from-git 33f24e3

# Lua 语法（四个模组）
NODE=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin
PATH="$NODE:$PATH" node tools/lua_syntax_check.mjs Contents/mods/Bin2NPCExtensionBase \
    Contents/mods/Bin2NPCExtension Contents/mods/Bin2NPCExtensionYese \
    Contents/mods/Bin2NPCExtensionVanilla
```

| 检查 | 覆盖什么 | 期望 |
| --- | --- | --- |
| `tools/test-vanilla/run_lua_test.sh --quick` | **钱的算术**（`Cash.balance` 含子容器与穿戴容器、散钞优先、破捆找零、余额不足不动物品、退款新发钞票、`flow()` 返回 false、端到端 `Service.dispatch` 扣的正好是 `SignPrice`）与**侧边栏挂接**（`Icon.attach` 幂等、只服务 player 0、尺寸从原版按钮量、面板重建后重新 attach、热键兜底）与**窗口命令**（三页签各发什么、岗位没变什么都不发、revision 变了才重建、`close()` 清单例） | `50/50 passed, 0 failed` / `ALL PASS` |
| `tools/make_icons.py --check` | 10 张图在不在、尺寸对不对 | `图标齐全且尺寸正确（5 档 x 2 态）` |
| `tools/modinfo_probe/run.sh` | 四个 mod.info 能否被游戏解析；`require=` 依赖的名字对不对；10 张贴图能否从 `media.version`（`<mod>/42.21/media`）解析到 | `ALL MOD.INFO PARSED` + `ALL PATHS RESOLVED`（10/10） |
| `python3 tools/check_base.py` | 见 `docs/design.md` §12.5 / §13.6 | `公共层零身份 + 3 个口味互不撞车：OK` |
| `python3 tools/fork_variant.py --check` | YeseMarket 变体仍是生成物 | `变体与生成器一致（mod N 文件 / test 5 文件）` |
| `python3 tools/extract_base.py --from-git 33f24e3` | 公共层仍等价于抽取前那份代码 + 逐条列出的替换 | `公共层 12 个文件与机械搬移结果一致。` |

> 离线检查**证明不了**的事（不要去 `console.txt` 之外找证据）：实机 `getTexture` 是否真拿到图、
> 128 档侧边栏下图标会不会超出屏幕底部、钞票在世界里的实际掉落率。

### 游戏内（V1~V12）

准备：`~/Zomboid/mods/` 下软链 `Bin2NPCExtensionBase` + `Bin2NPCExtensionVanilla`（见 README §5），
游戏里启用这两个；**不要**启用任何经济模组（这一组就是要证明它不需要）。
建议先把沙盒 `Bin2NPCExtensionVanilla.DebugLog` 设为 true，测完再关。
日志前缀 `[Bin2NPCExtensionVanilla]`，文件 `~/Zomboid/console.txt`。

| 组 | 用例 | 怎么验 | 期望看到什么 | 失败时先看 |
| --- | --- | --- | --- | --- |
| V 入口 | V1 左侧竖排栏最下方出现 NPC 图标 | 进游戏后看屏幕左侧那一列（心/背包/建造/家具/地图） | 最下方多出一个 NPC 图标，与原版按钮同宽、间距一致；鼠标悬停显示「NPC 招募：用原版钞票雇人。快捷键 Ctrl+Alt+N。」 | 控制台 `sidebar icon hooked into ISEquippedItem (left column, below the vanilla buttons)`；`client ready … ui=true` |
| V 入口 | V2 点这个图标开关面板 | 点一次 → 再点一次 | 面板打开；再点关闭。图标在面板开着时是 `On` 态、关着时是 `Off` 态 | `Config.RecruitPanel.toggle` 是否被调到；两态贴图路径 |
| V 入口 | V3 Ctrl+Alt+N（**没装任何经济模组**） | 关掉面板后按热键 | 面板打开/关闭；控制台无「经济模组没装」之类的告警 | 热键这条路不经过侧边栏图标，是入口的兜底 |
| V 钱 | V4 余额算上钱包 / 背包 / **背着的背包** | 分别把钞票放进：身上（主背包）、背包里的钱包、**穿在身上的背包**，看面板上的余额 | 三种位置都计入余额；把背包穿上/脱下余额不变 | 穿戴容器不在 `getInventory()` 里（`docs/design.md` §13.3c）——数漏了就是这里 |
| V 钱 | V5 破捆找零 | 身上只放 **1 捆**钞票（=100 张），收编一个 `SignPrice=30` 的 NPC | 捆少 1 个、钞票多 70 张（净值 -30）；余额显示 70 | `Cash.pay` 的"先散钞、不够破捆、多余新发"三步；控制台不应有 `cash payment short by` |
| V 钱 | V6 余额不足时明确失败且**不掉钱** | 清空身上的钞票（保留别的物品），再点收编 | 提示「钞票不足」；背包物品一个不少；名册没有新契约 | `ReasonNoFunds`；`Cash.pay` 在余额不足时**先 return**，不动物品 |
| V 钱 | V7 退款到账 | 把 A-Life 人口上限调到最小后点「中介派遣」（造人必然失败） | 提示造人失败；控制台 `refunded <n> Base.Money to <player>`；钞票张数与付款前一致 | `Cash.refund` → `addNotes` → `sendAddItemsToContainer`；联机下另一台客户端也要看到钱回来了 |
| V 钱 | V8 日薪按沙盒扣 | 沙盒 `DailyWage=5`，雇一名雇员，等跨过一个 24 世界小时 | 每满 24 小时少 5 张钞票；`WageEnabled=false` 时不扣；欠薪超 `UnpaidGraceDays` 后雇员走人 | `Maintain.settleWages`；日志里 `wage` 的数字 |
| V 共存 | V9 三个口味同时启用，同一个 NPC 只能被一边雇走 | 同时启用三个口味，在橙子口味界面雇一名 NPC，再到钞票口味界面点同一名 NPC 的「收编」 | 第二个界面报「已被其他玩家雇佣」；**钱一分不掉**、不写契约 | `Service.takenBySibling` 遍历 `Config.SIBLING_MODULES`（三个口味时必须列全，见 `docs/design.md` §13.6） |
| V 界面 | V10 改「侧边栏尺寸」后图标跟着换、不重复 | 游戏选项里把侧边栏尺寸从 1 改到 5（48→128），每档看一眼 | 图标跟着换尺寸档；面板高度把图标算在内；**不出现第二个图标**、也不残留旧图标 | 原版改尺寸会**整体重建**面板（`ISEquippedItem.lua:1059-1068`）⇒ 引用必须挂在面板自己身上；另见 V1 的 hook 日志只有一条 |
| V 界面 | V11 分屏时 player 1 没有图标 | 2 人分屏，看 2P 那半屏的左侧 | 2P 只有两只手（mainHand/offHand），没有按钮列、也没有我们的图标 —— **这是原版设计**，不是 bug | 原版按钮列整段包在 `if self.chr:getPlayerNum() == 0 then`；我们的 `attach` 对非 0 号玩家直接返回 true |
| V 联机 | V12 专用服务器上日志正确 | 起专用服（或主机），看服务端日志那一行 | `loaded v0.4.0 \| money=true(cash) alife=… jeem=… \| hooks active=… inactive=…`；**没有**「<经济模组> is missing」这类误报 | 上游口味的缺失告警只在 `MONEY_KIND == "upstream"` 时发；`cash` 的 `available()` 恒 true |

> V4/V5/V7 是这一组里**最值得先跑**的三条：它们覆盖的正是原版钞票最难的三件事
> （穿戴容器、破捆找零、发包同步），而这三件事在单机下"错了也看不出来"。
