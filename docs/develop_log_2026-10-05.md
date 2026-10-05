# 开发日志 - 2026-10-05

## 课题一：`workshop.txt` 的"富文本格式"到底是哪一套

用户提问只有五个字："**workshop.txt 富文本格式**"。先把问题拆成两个可能被混淆的东西，再用游戏自己的
代码定案 —— 结论是**两套方言，分别在两个地方渲染**：

| 显示位置 | 读的文件 | 富文本方言 | 渲染者 |
| --- | --- | --- | --- |
| Steam 工坊物品页的简介 | 物品根 `workshop.txt` 的 `description=` | **Steam BBCode** | Steam 网页 / 客户端 |
| 游戏内 Mods 列表的描述 | `<版本目录>/mod.info` 的 `description=` | `<LINE>` / `<RGB:r,g,b>` / `<SIZE:…>` | 游戏 `ISRichTextPanel` |
| 游戏内上传向导的简介输入框 | 上面那份 `workshop.txt` | 纯文本，**不预览 BBCode** | —— |

### 证据（每条都可复现，不靠印象）

1. **字节码**：`javap -p -c zombie/core/znet/SteamWorkshopItem.class`
   * `readWorkshopTxt()`：每行先 `String.trim()`（offset 59）、`#` 与 `//` 开头整行 `goto` 跳过、
     空行 `isEmpty()` 跳过；`description=` 用**单个 `\n`** 累加（BootstrapMethods 里的
     `\u0001\n` + `\u0001\u0001`）；值里 `replace("description=", "")` 会删掉**所有**出现。
   * `getSubmitDescription()`：描述非空时先补 `\n\n`，再拼 `Workshop ID: <id>` / `Mod ID: <modid>`。
   * `SteamWorkshop.SubmitWorkshopItem()` 把该字符串原样喂给 `n_SetItemDescription`
     —— **不转义、不剥离**，所以 BBCode 能活着到 Steam 页面。
   * `getVisibilityInteger()` 订正：合法值是 `public` / `friendsOnly` / `private` / `unlisted`，
     **其它任何值静默返回 0 = public**（旧文档写的 `friends` 是错的）。
2. **实机探针**（本次新写，`--check` 批量模式）：喂一份含 `[h1]/[b]/[i]/[url]`、空 `description=`、
   `description=  ← 缩进`、`#`/`//` 注释的 `workshop.txt`，探针逐行 `|…|` 打印，标记与空行原样保留、
   注释行消失，并且**实测到正文里的字面量 `description=` 被删掉**（`写在 description= 之后` → `写在  之后`）。
3. **游戏内方言的完整标签表**：`media/lua/client/ISUI/ISRichTextPanel.lua` 的 `processCommand()`
   —— LINE / BR / H1 / H2 / TEXT / CENTRE / LEFT / RIGHT / RGB / PUSHRGB / POPRGB / GHC / BHC /
   RED / ORANGE / GREEN / SIZE / IMAGE / IMAGECENTRE / VIDEOCENTRE / INDENT / JOYPAD / SETX / SPACE，
   转义用 `&lt;` `&gt;`；消费方 `ModInfoPanelDesc.lua:33` 用 `ISRichTextPanel:setText(modInfo:getDescription())`。
4. **长度上限**：Steamworks `k_cchPublishedDocumentDescriptionMax = 8000`，单位是 **UTF-8 字节**
   （汉字 3 字节/字），额度含 BBCode 标记与游戏追加的 ID 行。

### 顺带得到的 6 条硬规则

空行只能靠**空的 `description=`**；行首缩进被 `trim()` 吃掉（缩进要写在 `=` 之后）；正文不能出现
字面量 `description=`；行首 `#` / `//` 会被当注释丢掉；值里写 `\n` 不换行；**未闭合的 BBCode 会把
游戏追加的 `Workshop ID:` / `Mod ID:` 行一起吞进列表**。

---

## 课题二：统一优化仓库全部 `workshop.txt`（17 份）

### 做法

先写工具再动文件：给 `WorkshopTxtProbe` 加 `--check` 批量模式，再写 `check_all.sh`
（扫描仓库 → 每份复制进 `~/Zomboid/Workshop/__wtchk_*` 白名单 staging → 跑完清理），
得到一份"改前基线"。基线立刻抓到第一个问题：`bin2/Contents/mods/Respawn2/workshop.txt`
这份**历史遗留**（游戏只在物品根读 `workshop.txt`，这份在 `Contents/` 里的只会被当模组内容上传，
而且 `tags=` 是空的）—— 按 SOP §9 的说法直接 `git rm` 删除。

然后逐份重写，规则统一为：`[h1]` 大标题 → 一句话 → `[h2]` 小节（功能 / 包含模组 / 依赖 / 安装 /
已知限制）→ `[list]` + `[*]` 列表 → 结尾保留 `[ ALERT_CONFIG ]` 块。

### 逐份改动的要点

| 物品 | 关键改动 |
| --- | --- |
| `bin2` | 从"标题重复一遍"补成两个模组的说明（Keep XP When Respawn 2 的技能折减保留 / Death Is Not The End 2 的尸体取回 XP），依赖 `modoptions` |
| `bin2_b42` | 补上此前完全没提的 **bin2_base（42.19.0）**；tags 从 10 个收敛到 5 个 |
| ERS / EHR / EPR / Xantji / Lingering Voices | 空壳描述 → 按各自 `mod.info` 写清**翻译范围**（ItemName / Tooltip / Sandbox / Recipe / UI / ContextMenu）、依赖 mod id、安装步骤；EHR 补 `loadModAfter` 加载顺序 |
| Neat 手柄支持 | 把 `mod.info` 里的完整按键映射搬到工坊页面，并写明 B42 建造模式必须用鼠标的原因（`ISBuildIsoEntity` 是 Java 类） |
| `nested_containers_take` | 补机制一段、双端安装要求、覆盖范围，并把"**从未在真实联机会话里实测**"如实写上 |
| A-Life 扩展 | 结构化为沙盒选项列表；**日志版本 `v0.1.0` → `v0.1.5`**（`Config.VERSION` 实测） |
| `bin2_tikitown` | 条目数按 JSON 实点订正：214 → **223**、84 → **172**（并给出分类明细） |
| viewpoint | 内容严重过时：**快捷键早已从 F9/F10 改成 Ctrl+Alt+D 控制面板**、版本 1.x → **2.2.0**，补上 P1 相机/3D 管线、P3.1 体素模型包（16 包 / 9,187 模型 / 10,110 bind）、安装与配置段 |
| title cover ×2 | `【】` 小节 → `[h2]`；补 `Title.png + Title2/3/4.png` 与 `renderOriginalBackground` 的事实 |
| alpaca ×2 | 保持英文原文风，改为 `[h2]` + 列表结构 |

### 校验结果

```
ALL CHECKS PASSED (17 item(s))
```

`submitDescription` 最大 **3534 字节**（`bin2_viewpoint`），距 8000 上限仍有一半余量；
`id=` / `visibility=` / `version=` 与原值逐份比对**全部未变**（只有 Xantji 的标题补了一个缺失的空格）。

**工具抓到了我自己写错的一行**：Xantji 那份有一行续行忘了写 `description=` 前缀，`--check` 直接报
`非法的键: L6 没有 '='` —— 没有这一步，那一行会静默消失在工坊页面上。

另外做了一次"事实标记"回归：把新旧描述的 URL / 点号标识符 / 多位数版本号抽出来做差集，只剩
`0.1.0`、`214`、`1.2` 三处"消失"，全是**故意订正的过时值**。

### 产出

* `bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java`（新增 `--check` 批量自检）
* `bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh`（仓库级一键校验）
* `workshop_create.sop.md`：§3.4 换成统一排版骨架与约定、§3.5 新增富文本整节、§9 补 3 条症状、§10 补批量校验
* `guides/workshop-txt-guide.md`：订正 5 处字段错误 + 新增"富文本与排版"整节
* skill `pz-workshop-item-publishing`：§2.1 description 解析细节与富文本、§7 新探针、§8 踩坑
* 17 份 `workshop.txt` 重写；删除 1 份历史遗留

### 未做 / 待确认

* **没有真实上传一次**去核对 Steam 页面的渲染结果（本机 `web_fetch` 对所有域名都返回
  "resolves to a non-public IP"，Steamworks 文档与社区排版页都只能引 URL）。
* `bin2_blocky_alpaca` / `bin2_companion_alpaca` / `bin2_title_cover/*` / `bin2_viewpoint`
  仍是 `visibility=private` —— 发布与否是作者的决定，本次不擅自改。
* 顺带发现但**未改**：`bin2_title_cover` 两个模组的 `mod.info` 里
  `incompatible=\ZomboidTitleCover,\ZomboidTitleCoverWide` 把**自己**也列进了互斥名单，
  疑似复制粘贴笔误（16:9 版声明 16:9 版互斥），已单独提出待确认。

---

## 课题三：新模组 `bin2_npc_extension` —— 把 NPC 招募做进橙子社区经济

用户给的需求是一句话：*npc 扩展模组 bin2_npc_extension，兼容 Project A-Life Jeem Extension（3806944055），
在 橙子社区经济模组（3777900792）中增加 npc 招募功能*。它同时牵动三个第三方模组，所以**先取证、再动手**。

### 一、两端各请一个子代理做只读逆向，产出可引用的规格

两份报告都落在 `bin2_npc_extension/docs/research/`，每条结论带 `文件:行号`：

| 报告 | 规模 | 对我们最有用的三件事 |
| --- | --- | --- |
| `economy-integration-hooks.md` | 1087 行 / 41 个被引文件 | ① 页面注册表是**公开 API**；② 侧栏 `MENU`、社区中心 `TABS` 是 `local`，加不进 —— 唯一先例是它自己包首页工厂；③ 服务端路由对非自己 module 直接 return，所以**用自己的 module 名发包即可，零 patch** |
| `jeem-recruit-api.md` | 638 行 / 两份 mod.info + 关键函数逐行核对 | ① A-Life **没有**任何雇佣/同伴机制，跟随只能靠 `DecisionLoop.setOrder`；② `R.recruit` 收编**整支 crew**、服务端**不校验距离**、且**不收费**；③ `memory.persistent` 与 `memory.admin.persistent` 管的是两个不同的回收函数 |

### 二、设计上被这两份报告改动的地方

1. **不用对方的网络通道**：橙子经济的 `command_router` 只认 `module == "OrangeTradingMod"`，
   硬塞进去要么改对方文件、要么抢它的包解析；我们直接用 `Bin2NPCExtension` 自己的 module，
   A-Life 也明文禁止第三方复用 `"ProjectALife"`。两边红线一次满足。
2. **客户端不读 ModData**：A-Life 的 `Executor.PROTECTED` 白名单不含第三方 memory 键，
   多人下"运行该 NPC 的客户端"看不到我们的标记；统一由服务端 `sendServerCommand` 推快照，
   就不会出现"主机能看到、别人看不到"。
3. **钱自己收**：Jeem 招募免费、只有阵营声望代价，所以扣款、退款、欠薪全是我们的责任 ——
   也因此必须自带限速与 `requestId` 去重（对方的 `action_request_guard` 是白名单制，第三方塞不进去）。
4. **岗位失败只降级、不撤销契约**：钱已收、人已造，最差也要给玩家一个"跟随"的雇员，
   并把降级原因写进契约备注、显示在面板上（`Reason*` 系列翻译）。

### 三、交付物与自检

* 模组：`Contents/mods/Bin2NPCExtension/42.21/`（14 个 Lua、4 份翻译 JSON、14 个沙盒选项、poster）
* 文档：`docs/design.md`（架构/数据模型/降级矩阵/稳定性评级/风险）、`docs/test-plan.md`（T1~T18 + M1~M4）
* 工具：`tools/make_images.py`（新写）、`tools/lua_syntax_check.mjs`（复用）、`tools/test/`（离线逻辑测试）
* 校验结果：
  * Lua 语法：14/14 OK；
  * 工坊探针：`readWorkshopTxt=true`、tags 全在白名单、`validatePreviewImage=OK`、`submitDescription=4274` 字节；
  * 仓库级 `check_all.sh`：`ALL CHECKS PASSED (18 item(s))`（新增我们这一份）；
  * 翻译一致性：代码里 45 个字面量键 + `Text.lua` 映射表值 → CN/EN 零缺失、键集合完全相同。

### 四、未做 / 未验证（都写进了工坊简介的"已知限制"）

没有进游戏实跑；`StandingService.addGroup` 能否真把组点数顶过同盟阈值、转居民时"整支小队一起进营地"的
实际观感、首页按钮与「社区中心」按钮的排布是否会随对方布局变化重叠、与 Bandits2 等 NPC 模组的共存、
专用服非管理员玩家转居民的成功率 —— 全部列在 `docs/test-plan.md` 的待确认清单里。

### 五、离线逻辑测试：33/33，并抓出 4 个真缺陷

补记一节，因为这是本课题里回报率最高的一步。测试（`bin2_npc_extension/tools/test/run_lua_test.sh`，
fengari + 忠实 mock 三个依赖）一开始就红了 4 条，全是真缺陷而不是 mock 不准：

1. **`Service.dismiss` 漏了 `Config.enabled()` 闸门** —— 另外三个改状态命令都有，只有它没有，
   沙盒关掉模组后玩家仍能解雇（行为不一致）。
2. **周期重下指令把 `quiet=true` 丢了** —— `Maintain` → `Service.applyMode` → `Alife.orderFollow`
   这一串没透传，于是每 8 秒重下一次 follow 都会重放 follow 动画与 `ORDER_ACK` 语音；
   而 `Maintain.lua` 顶部的注释写的正是"用 quiet 模式"。**注释与实现不一致**是这类缺陷的典型信号。
3. **退款不写流水** —— `Economy.refund` 只调 `AddCoins`，账单里只有扣钱没有退钱。
4. **`hireSpawned` 不校验刚造出来的 uid 是否还在** —— 记录被当场回收时仍收钱、写契约，
   要靠下一次 `Maintain.tick` 才把契约标 dead，钱不退。

顺手修掉两个"可疑点"：`Contracts.sanitize` 改为**先剔除非法项再重建 order**（原来要跑两遍才干净）；
requestId 去重队列改为**按时间裁剪**（原来按条数留 64 条，60 秒内连发 65 个不同 requestId
就能把最早那条挤出窗口，重放它不再判 duplicate）。

修完把测试里"如实记录现状"的四处期望翻成正确行为，并给两处可疑点补了回归断言，
现在 `[test] 33/33 passed, 0 failed` → `ALL PASS`（exit 0）。
**方法论收获**：mock 的价值不在"跑通"，而在**把上游的校验顺序与拒绝码抄准** ——
抄准了它就能替游戏先发现我们自己骗自己的地方。

### 六、对照 `bin2_ProjectALifeNPCs_extensions`：纠正"往 Compat.known 里写自己"

用户追加"同时参考 bin2_ProjectALifeNPCs_extensions"。把那个项目还没读的 `roadmap.md` 与
`integration-brainstorm.md` 过完，抓到本模组的一个**真实错误**：

我们（以及给建议的子代理）把"往 `ProjectALife.ModCompat.known` 注册自己的 verdict"当成了加分项。
读 A-Life 源码定案：`Compat.report()`（`ALifeModCompat.lua:314-330`）会遍历 `known`，把启用中的条目
按 `entry.verdict` 打印成 `[A-Life] compat: <name> (<id>) -> adapted: <note>` ——
**第三方写进去 = 借 A-Life 的口替自己背书**，而那个 verdict 不是它给的。
那个项目的 `integration-brainstorm.md` §1 已写明"不是注册 API"，本轮把它落成了代码约束。

改法：`registerCompat`（写）→ `reportCompat`（只读），跑 A-Life 自己的 `Compat.foreignCopies(active)`，
点名"自带 A-Life Lua 副本"的模组 —— 这恰好是本模组最需要的排障信息，因为那类模组会让每次 NPC 水合失败，
而生成 NPC 正是我们的主路径。另外采纳了它的 `Grant.makeAllied` 里的"复核并打日志"习惯：
`addGroup` 之后读 `groupPoints`，为进游戏验证"非管理员转居民"（T15/M2）留下判据。

测试同步 3 处（mock 补 ModCompat、用例 1 加两条只读断言、用例 24 删掉"写 known"的断言），
改完仍 `33/33 passed`。文档互挂：新项目 README §3、旧项目 README §5.7 + roadmap 阶段 1-D。

**方法论**：跨项目对照的价值不在复用代码，而在**拿别人的既有结论审计自己新写的代码** ——
这处错误在"推荐做法"的外衣下活到了测试通过之后，只有回到上游源码读 `Compat.report()` 才翻出来。

### 七、再采纳两条工程约定（防 Reset Lua 重入 + 可观测）

对照它的 `roadmap.md` 阶段 4「通用工程约定」后补的两处：

1. **§4 防 `Reset Lua` 重入**：把三个注册 `Events` 的文件的守卫从布尔量改成 **`Events` 表的身份**判据 ——
   同一张表说明是同一次会话（跳过，防重复注册），换了一张表说明引擎重置过 Lua（必须重新注册）。
   布尔守卫的毛病在后者：重置后它会永久拦住重新注册，功能静默失效。
2. **§3 可观测**：新增 `Bootstrap.capabilities()`，把 10 个半公开入口逐个探一遍，
   启动打印 `hooks active=N inactive=M` 并在缺项时 WARN 列出名字。
   为验证它真管用，做了一次失败实验：mock 里把 `DecisionLoop.setOrder` 置 nil（模拟上游改名），
   日志立刻变成 `hooks active=9 inactive=1` + `inactive hooks (1): alife.orders -- an upstream rename looks like this`；
   恢复后回到 `33/33 passed`。

用例 24 因此扩了 6 条断言，把"可观测链路"也纳入回归。

### 八、v0.1.1：玩家实测反馈的两处版面错位

用户把游戏截图发过来：功能是通的（首页入口在、招募面板开得起来、经济流水里有
两笔 `FlowHire NPC -1500.00`，说明中介派遣成功跑过两次），但有两处重叠：

1. **右侧说明文字压住模式按钮行**。根因是我们自己写的固定坐标：模式按钮钉在 `listTop + 118`，
   而文本从上往下不限行数地画。窗口一矮，两者必然相遇。
   改成**自下而上**排版（先从底部预留模式行 + 主按钮 + 次按钮三块固定高度，文本区夹在中间），
   并加 `drawLines()` 只画得下的行；次按钮位永远预留，切页签时按钮不再跳。
2. **首页入口按钮压住对方的「卡片」按钮**，两个标题叠成了「NPC 招募: 卡片」。
   根因是锚点只有一个：`communityCenterButton` 在社区中心功能关闭时不存在，于是回退到"贴右边缘"，
   正好落在右侧那排视图切换按钮上。改成收集三个锚点取最左，贴在它左侧；都没有就贴左边缘。

**最有价值的不是这两处修复，而是补上的回归**：把版面几何当契约测 —— 三种窗口尺寸下断言
文本区止于模式行上方、按钮两两不重叠、全部在页面内、小窗口 `render()` 不抛错；
并做了失败实验（把文本裁剪改回旧行为 → 三条断言立刻红）。

**教训**：布局是**状态函数的输出**（尺寸 × 页签 × 选中项 × 依赖可用性四个变量），
不能靠"看起来排好了"交付。把它写成可断言的几何契约只要十几行，却能挡住这类
"必然在某个窗口尺寸下出现"的问题 —— 这一条已回填到 `docs/design.md` §8.2。

### 九、追问「workshop.txt 能不能声明必需物品」：不能，并把它变成可查的表

用户的实际痛点是每发布一个物品都要在 Steam 网页手动加 Required Items。查清后答案是**不能**，
三条证据：① `readWorkshopTxt()` 的键字符串只有 6 个（`javap -c`）；② 把 `required=`/`required0=`
追加进真实文件，用游戏自己的解析器跑，`description` 字节数与原来**逐字节相同**、无任何报错；
③ 上传 native 只有 `n_SetItemTitle/Description/Visibility/Tags/Content/Preview/SubmitItemUpdate`，
提交界面也只有那 6 项输入 —— 链路里根本没有"设置依赖"这一步。
反向发现：游戏**会读**（`SteamUGCDetails.getChildren` / `SteamWorkshop.GetQueryUGCChildren`），
只是自己的 Lua 零调用点，所以手填 Required Items 的价值在于 Steam 客户端的"一键订阅"。

于是把"手动"里能自动化的部分做掉：

1. 新工具 `bin2_workshop_upload_fix/tools/workshop_requires.py`：从本机已订阅工坊内容的
   `mod.info` 反查 mod id → 工坊 id（索引 1169 个），输出每个物品的 必需/可选 清单与可点击 URL，
   `--write` 可直接往 `workshop.txt` 生成依赖小节（`#` 行做标记，解析器会跳过）；
2. 两份简介的依赖段升级成 `[url=…]` 可点击链接，`check_all.sh` 仍 18/18 通过；
3. SOP 新增 §3.6（含本仓库依赖 id 对照表）与执行步骤第 13 步，skill 新增 §2.2 与清单两条；
4. 顺手订正两处过期文档（两个项目的发布状态还写着 private/未上传）。

**踩坑**：拿错 staging 路径时探针**不报错**，只打印空字段 —— 见到全空先确认路径存在
（`bin2_ProjectALifeNPCs_extensions` 的 staging 实际叫 `ALifeStartWithNPC`）。

**留给作者定夺**：`mod.info` 里 `require=\ProjectALifeJimmy`（作者自己改的）与代码的软挂接设计不一致 ——
前者会让游戏在缺 Jeem 时拒绝启用，而代码 `no_jeem` 分支本可降级。工坊简介已按现状改写，是否降回可选出作者决定。
