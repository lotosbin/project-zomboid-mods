# 开发日志 - 2026-10-06

承接 2026-10-05（`docs/develop_log_2026-10-05.md`）：昨天把两个口味共用的 12 个中性文件抽成了公共层
`Bin2NPCExtensionBase`（v0.3.0）。今天加**第四个模组** `Bin2NPCExtensionVanilla` —— 纯原版口味：
不装任何经济模组，用**原版钞票**雇人，入口是**屏幕左侧原版图标栏**里的一个 NPC 图标。

一句话概括这轮的技术核心：**把"钱从哪来"和"入口挂哪"从经济模组上解耦**，并为此把两个前提都用
引擎证据钉死。

---

## 课题一：原版钞票怎么算钱（`docs/research/vanilla-money-integration.md`）

先把问题拆开：原版有没有"钱"这个概念？有，但它只是物品。

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| `Base.Money` 一件值多少 | **1 个单位**；`Base.MoneyBundle` = **100** | 配方 `craftRecipe UnbundleMoney` 的 `outputs { item 100 Base.Money }`（`media/scripts/generated/recipes/recipes_packing.txt`），物品脚本里没有任何 Count/Stackable/面值属性 |
| 有没有 `getMoney()` | **没有** | `InventoryItem` javap 无此方法；`IsoPlayer`/`IsoGameCharacter` 也没有 money/coin/cash 字段 |
| 能不能"收 30 找 70" | **不能**（没有原语） | `InventoryItem.CanStack()` / `CanStackNoTemp()` 字节码 = `iconst_0; ireturn`；count 恒 1、不进 `save()`、不进 `SyncItemFieldsPacket`；全游戏 Lua `grep -rn ":setCount("` = **0 处** |
| 背包里的钱数得到吗 | 子容器**可以**，**穿戴中的容器不行** | `getItemsFromType(type, true)` / `getCountTypeRecurse` 会递归子容器；而 `IsoGameCharacter.setWornItem(...,boolean)` 会 `getInventory():Remove(item)` 把穿戴容器摘出主背包 |
| 改完背包客户端怎么知道 | 必须显式发包 | `AddItem`/`Remove`/`RemoveAll` 都不发包；真同步是 `sendRemoveItemsFromContainer` / `sendAddItemsToContainer`（javap：`zombie.Lua.LuaManager$GlobalObject`）。`setDrawDirty(true)` 只是本地 UI 脏标记 |

最后一条正好解释了"为什么 `Cash.lua` 看起来比 `Economy.lua` 啰嗦得多"：上游经济模组的
`Pay/AddCoins` 自己会 `Transmit`，而原版钞票没有任何这样的中间层，**每一步删除/新增都要自己发包**。

⇒ `Cash.pay` 的算法因此定型：① 先确认余额够（不够就一个物品都不动地失败）；② 先花散钞；
③ 不够就破一捆（=100），多出来的**当场新发找零**；④ 删完还不够只可能是并发改包，如实失败并记日志。
**绝不静默多收或少收**。

## 课题二：左侧侧边栏入口怎么挂（`docs/research/vanilla-sidebar-entry.md`）

原版那条竖排栏（心/背包/建造/家具/地图…）的容器是 `media/lua/client/ISUI/ISEquippedItem.lua`。
调研的结论直接决定实现：

* **没有**任何"侧边栏注册表"可以 append（`sidebarButtons/sidebarIcons/...` grep 零命中）；
* 唯一零副作用的插入点是**后置 hook `ISEquippedItem:initialise`，把按钮追加在最后**：
  插在中间就得平移原版按钮的 y，而原版把 `movableTooltip/movablePopup` 的坐标写死在
  `:initialise` 里（`:807-812`），一平移就错位；
* 追加之后**再调一次 `self:shrinkWrap()`** —— 它只统计 `Type == "ISButton"` 的子元素，
  会自动把我们的按钮算进面板高度；
* 原版整段按钮包在 `if self.chr:getPlayerNum() == 0 then` 里 ⇒ **只有 player 0 有这一列**，
  分屏的 player 1 没有（那是原版设计，我们不造）；
* `TEXTURE_WIDTH/HEIGHT` 与 `setTextureWidth()` 都是**对方文件的 local** ⇒ 尺寸只能从
  `self.invBtn:getWidth()` 量（别自己复刻 `getOptionSidebarSize()→尺寸` 的映射，那里面还有一个
  `size==6 → getFontSizeReal()-1` 的分支）；
* 玩家在选项里改"侧边栏尺寸"时，原版 `checkSidebarSizeOption()` 会**整体重建**面板
  （`removeFromUIManager` + `launchEquippedItem`）⇒ 按钮引用只能挂在面板自己身上，不能放模块全局。

**这里踩到一个沉默的坑（本轮的第二个真 bug）**：`ISButton:onMouseUp` 调的是
`self.onclick(self.target, self, ...)` —— 第一个参数是**注册时给的目标**（这里就是面板），
第二个才是按钮。原版 `ISEquippedItem.onOptionMouseDown(button, x, y)` 之所以能把第一个参数叫
`button`，是因为它以面板为 self 被调用。我一开始写成 `onIconClicked(button)`（单参），
于是 `button` 收到的是面板、`button.internal` 恒 nil ⇒ **图标点了永远没反应，而语法检查与
离线测试都看不出来**（除非 mock 忠实复现这个调用约定）。修完的签名是
`onIconClicked(target, button)`。

## 课题三：把"钱"变成可换的实现（`Core.API` 1 → 2）

公共层原来只有一份 `Economy.lua`，写死在上游经济模组的 `Pay/AddCoins/PlayerData` 上。
现在多了一层"钱从哪来"的选择：

```lua
-- Namespace.lua（手写文件）
Core.MONEY_PROVIDERS = { upstream = "Economy", cash = "Cash" }
NS.MONEY_KIND = spec.money or "upstream"
NS.Economy = require("Bin2NPCExtensionCore/" .. Core.MONEY_PROVIDERS[NS.MONEY_KIND])(NS)
```

两个实现给出同一组方法（`available / balance / pay / refund / flow / wage`），
`Service`/`Maintain` 完全看不见区别；`cash` 没有账单系统，`flow()` 如实返回 false。
`available()` 的语义也随之澄清：不再是"经济模组的全局在不在"，而是"**这个收钱实现现在能不能用**"。

**为什么 `Core.API` 要升到 2**：这一版是**加字段**，老口味不写 `money` 也能跑（默认 upstream）。
但"只更新了一半的工坊物品"必须被拦下来 —— 新口味要的 `Cash.lua` 在旧公共层里根本不存在，
静默降级的后果是"变成了没有经济模组"，正是最坏的降级方式。加字段也升版，就是为了让
`coreApi` 守卫（口味打一行 `public layer mismatch: ... Update the whole workshop item` 并停用自己）
在这种组合下生效。

顺带两个小接口：

* `spec.uiHint`：入口装不上时打给人看的那句话由口味自己给。旧代码把它写死成
  `"is " .. Config.ECONOMY_MOD_ID .. " enabled?"`，对原版口味毫无意义（`ECONOMY_MOD_ID` 是 nil）。
* `spec.sibling` 支持**字符串或字符串表**（三个口味要两两互查），归一化成 `NS.SIBLING_MODULES`；
  指向自己的项会被丢掉并记一条日志。`Service.takenBySibling` 改成遍历数组。

## 课题四：贴图放在版本目录里，引擎找得到吗

原版侧边栏的贴图路径是拼出来的：`media/ui/Sidebar/<尺寸>/<名字>_<On|Off>_<尺寸>.png`
（`ISEquippedItem.lua:620-660` 那一串 `getTexture`）。而我们的模组是 B42 的**带版本目录**布局，
贴图在 `42.21/media/ui/...`。这一条离线检查（语法/测试/生成器一致性）**完全看不出来**，
一旦错了游戏里就是一个空白按钮。

第一版探针用 `ZomboidFileSystem.instance.getAbsolutePath("media/ui/...")` → **10 张全部 null**，
连模组的 `Profile.lua` 也 null。差点得出"贴图路径错了"的结论。停下来想了想：那个 API 是
`LuaManager.require` 用的（`getAbsolutePath(path + name)`），它只搜**游戏本体**目录 ——
能解析游戏自己的 `media/ui/Sidebar/48/Inventory_Off_48.png`，但对任何模组资源都返回 null。

换成引擎自己的模组信息才拿到真答案：`ChooseGameInfo$Mod` 上带着
`dir` / `versionDir` / `mediaFile{PZModFolder{common,version}}`，而带版本目录的模组解析 media 用的是
**`<mod>/42.21/media`**（`media.version`；`common/media` 是另一套）：

```
mod        : Bin2NPCExtensionVanilla
versionDir : ~/Zomboid/mods/Bin2NPCExtensionVanilla/42.21
media.version : .../Bin2NPCExtensionVanilla/42.21/media
OK   ui/Sidebar/48/NPC_Off_48.png   1862 bytes  <- .../42.21/media/ui/Sidebar/48/NPC_Off_48.png (media.version)
...
ALL PATHS RESOLVED
```

⇒ 贴图位置是对的；探针 `tools/modinfo_probe/TextureProbe.java` 随 `run.sh` 一起跑（4 个模组
`ALL MOD.INFO PARSED` + 10/10 贴图）。**教训：探针要探对 API** —— 一个只会对本体资源返回非 null
的函数，问你模组资源时给出的 null 毫无信息量。

## 课题五：生成器与守卫（第二次被同一类 bug 咬）

三个口味意味着 `sibling` 从 `sibling = "Bin2NPCExtensionYese"` 变成一张表。而
`tools/fork_variant.py` 里那条外科手术替换的匹配串是**含 `sibling = ` 前缀的整行** ——
源文件一改，它命中 0 次，脚本只是 `.replace()`，于是**什么也没发生**；紧接着的全局替换
（`Bin2NPCExtension` → `Bin2NPCExtensionYese`）又把表里的 `"Bin2NPCExtensionYese"` 切了一次，
YeseMarket 版的 sibling 变成 `Bin2NPCExtensionYeseYese`。**这正是 v0.3.0 刚修过的那个 bug**
（"重招被解雇/阵亡过的自己人"被误报"已被别人雇走"）换个方式复活 —— 它甚至是被我生成完
`--write` 之后**读输出**才发现的。

修法不是改那一行，而是给生成器加纪律：

```python
def sub_once(text, old, new, label):
    count = text.count(old)
    if count != 1: raise SystemExit("字面量替换未唯一命中（%s，命中 %d 次）：%r" % ...)
    return text.replace(old, new)
```

`sibling` 那条替换随之改成整表匹配，`PROTECT_BEFORE/AFTER` 加 `\x00VANILLA\x00` 哨兵
（否则 `Bin2NPCExtensionVanilla` 会被切成 `Bin2NPCExtensionYeseVanilla`，以及 `poster.png`
这样"不由本生成器产出"的文件在 `--write` 重建目录时被删掉 —— 第一次跑就删了一次，已改成保留）。

同一类"文档/脚本里的字面量与代码脱节"还咬了 `tools/extract_base.py`：本轮手改了
`Service/ServerBootstrap/ClientBootstrap` 三个公共层文件，按纪律要把这些改动补进抽取配方
（`--from-git 33f24e3` 要能重新复现当前公共层）。我第一版**手抄**了"包装后（整体缩进 4 格）"的
文本去当 `old`，5 条里 2 条失配 —— 因为 `apply_edits` 看到的是**未包装帧**。改成从生成器的
`build()` 里直接拿未包装帧、用 `difflib` 自动切出 replace 块、并**模拟应用一遍**确认逐字复现
当前文件，才不再靠手抄缩进。（这个过程本身也说明：能用机器算出来的东西，不要手抄。）

守卫方面：

* `tools/check_base.py` 新增三条断言：sibling 必须**列全**其它所有口味、`money` 必须是公共层
  支持的收钱方式、每个口味的沙盒选项翻译键在 CN/EN `Sandbox.json` 里都有（22 键/口味；
  我删掉一个键验证过它确实会红）。`currencyName` 不再算身份字面量（"钞票/金币"是钱叫什么，
  不是身份；公共层的 `Cash.lua` 必须能说清楚这件事）。
* `tools/make_icons.py`（新）：5 档 x 2 态侧边栏图标。尺寸是硬约束不是审美：原版实测
  48x36 / 64x48 / 80x60 / 96x72 / 128x96（W x 0.75W），`ISButton:render` 对"比按钮大"的贴图走
  `drawTextureScaledAspect` —— 交一张正方形 48x48 会被等比缩到 36x36。
* `tools/make_images.py`：海报改成**每个口味一张**（各自的强调色/依赖/入口文案），
  顺带修掉"公共层的海报是橙子口味那张的复制品"这个遗留问题。

## 课题六：测试与发布面

* **新增第三个测试套件** `tools/test-vanilla/`（**50 条断言，50/50 ALL PASS**）：
  钱的部分用「原版物品栏」mock 断言（余额含子容器与穿戴容器、破捆找零、不够时一个物品都不动、
  每次删/加都显式发包、退款回到原值、端到端走 `Service.dispatch` 扣的正好是 `SignPrice`），
  入口的部分断言 hook 幂等 / 只有 player 0 有图标 / 尺寸从原版按钮量 / 面板重建后新图标 /
  点图标开关窗口 / 没有侧边栏时热键照样能开；窗口的部分断言三个页签各自发什么命令 /
  名册页岗位没变时什么都不发 / revision 变了才重建 / `close()` 摘掉 UIManager 并清单例。
  静态部分还会校验 10 张侧边栏贴图的像素与 RGBA，并从 `sandbox-options.txt` 读出真正生效的默认值。
  * mock 的忠实度是这套测试的价值所在：**穿戴容器对 `getInventory()` 不可见**、**没有堆叠**（每件物品恒 1 个）、
    `RemoveAll` 只删本容器、`ISButton.onclick(target, self)` 的调用约定 —— 都照引擎语义复现；弱化任何一条，
    上面那些断言就会退化成「永远为真」。
  * 首次跑出 6 条失败，其中一条是**被测代码的真问题**：切页签时列表会被重建两遍（`rebuild()` 之后没有记下
    `seenRevision`，下一帧 `syncState()` 又重建一次）。已修：`Panel.rebuild()` 末尾记下当前 revision。
  * 套件交付时还报了三个**被测代码的真问题**（都已修，并把对应断言从「钉住现状」改成「钉住正确行为」）：
    ① `Panel.lua` 的两个 UI 类名忘了写 `local`，漏进 `_G` —— 现在改成 local，并挂到
    `Panel.RecruitList` / `Panel.Window` 供测试与排障使用；
    ② `Bootstrap.install()` **自身不幂等** —— 幂等判据只在工厂里，引擎 "Reset Lua" 重跑文件后会再
    install 一次：`OnTick` 注册两遍（维护循环每帧跑两次）、Ctrl+Alt+N 会「开了又关」；现在两个
    Bootstrap 的 `install()` 开头都比较 Events 表身份；
    ③ 原版口味的沙盒默认值（50/200/5）与公共层兜底值（500/1500/20）不一致 —— 沙盒表整个读不到时
    会显示/收取 10 倍价格；现在口味可以用 `spec.defaults` 覆盖兜底值，两边一致。
    这三条都属于「静态语法检查看不见、忠实 mock 或实机才看得见」的类别。
    其余几条是 mock 与断言本身要跟着引擎语义对齐（例如 `onmousedown(target, item)` 的参数顺序、
    列表数据存在 `entry.item` 而不是 `entry.data`）。
* 橙子套件与 Yese 套件各 **40/40**（本轮给两套都加了：`Core.API == 2`、`Core.MONEY_PROVIDERS`、
  `namespace()` 对认不出的 `money` 必须返回 nil、sibling 归一化（字符串/表/自指项丢弃）、
  以及 `Cash.lua` 工厂的接口合同；测试装载清单也从 13 个公共层文件变成 14 个 —— 补上了
  `Cash.lua`，它此前**根本没进测试的装载清单**，等于新实现无人看守）。
* `workshop.txt`：简介要在一个物品里说清"四个模组 + 三个口味 + 两种钱 + 三种入口"，
  还要压在 Steam 的 8000 字节以内（探针口径 **7848 / 7873**）。做法是压更新记录与已知限制，
  不删事实：每个口味各自的钱、入口、依赖、沙盒默认值差异（原版口味签约 50 张 / 派遣 200 张 /
  日薪 5 张）都留着。
* `docs/design.md` 新增 §13（原版口味：可换的钱接口、三条引擎事实、侧边栏挂接、贴图与版本目录、
  sibling 变表、沙盒默认值差异、未证实清单），`docs/test-plan.md` 追加离线检查与 **V1~V12**
  游戏内清单，`README.md` 的模块概览/依赖/工具表/校验结果全部按四个模组更新。
* 上传前用游戏自己的解析器验了一遍（这个会加载 Steam native，都不提交任何东西）：
  `readWorkshopTxt=true`、`id=3813914438 valid=true`、`validatePreviewImage=OK`、
  `StartItemUpdate/SetItemTitle/Description/Visibility/Tags/Content/Preview` 全 true、
  到 `SubmitItemUpdate` 之前停下。

## 验证（本轮实测，可复现）

```
python3 tools/check_base.py                      → 公共层零身份 + 3 个口味互不撞车：OK
tools/lua_syntax_check.mjs <四模组 + 三套测试>    → files=35 failed=0
tools/test/run_lua_test.sh --quick               → 40/40 ALL PASS
tools/test-yese/run_lua_test.sh --quick          → 40/40 ALL PASS
tools/test-vanilla/run_lua_test.sh --quick       → 50/50 ALL PASS
python3 tools/fork_variant.py --check            → 变体与生成器一致（mod 11 文件 / test 5 文件）
python3 tools/extract_base.py --from-git 33f24e3 → 公共层 12 个文件与机械搬移结果一致（347 行）
python3 tools/make_icons.py --check              → 图标齐全且尺寸正确（5 档 x 2 态）
tools/modinfo_probe/run.sh                       → ALL MOD.INFO PARSED（4 模组）+ ALL PATHS RESOLVED（10/10）
bash bin2_workshop_upload_fix/.../check_all.sh   → ALL CHECKS PASSED (18 item(s))
```

## 未做 / 交给下一轮

* **游戏内未跑**：左侧图标的位置与观感、破捆找零、退款、日薪、三口味互查、专用服
  `money=true(cash)`、分屏 player 1 无图标 —— 逐条清单在 `docs/test-plan.md` 的 V1~V12。
* **手柄**：原版侧边栏本身没有手柄导航（`onJoypad` 零命中），目前手柄玩家只能靠
  Ctrl+Alt+N（键盘）或鼠标点图标。要补的话挂 `ISDPadWheels.onDisplayRight` 往圆盘菜单里加一格
  是最贴近原版的做法。
* **工坊未重新上传**：线上仍是 v0.2.3 / 两个模组；物品现在含四个模组，Base 由 `require=` 自动启用。
* **沙盒价格未做经济平衡**（钞票掉落率未知），默认值是按"稀缺"取的保守值。
* 128 档图标是否超出屏幕底部只有源码手算（未实测）。

> 沉淀（四条，已同步进 `docs/rolling_log.md`）：
> ① **"钱怎么算"是策略不是接口** —— B42 没有堆叠就没有"找零"原语，先证清楚这一点，
> `pay()` 才不会写成一个跑不通的"部分扣除"；
> ② **探针要探对 API** —— `getAbsolutePath` 对模组资源一律 null，差点被读成"贴图路径写错了"；
> ③ **回调签名是沉默的坑** —— `onclick(target, self)` 顺序写反既不报错也不生效；
> ④ **生成器里每条替换都要"恰好命中一次"** —— 同一类 bug 第二次咬人时，修法应该是加断言。
