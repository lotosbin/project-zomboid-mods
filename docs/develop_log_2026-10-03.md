# 开发日志 - 2026-10-03

## PZ 在 macOS / Linux 上传创意工坊失败：定位与修复

### 任务背景

用户给出 Steam 讨论帖
<https://steamcommunity.com/app/108600/discussions/1/582806854239939623/>：
**"僵尸毁灭工程上传到创意工坊，mac/linux 报错，windows 正常，定位问题并修复"**。
帖子标题即报错原文 `Unable to upload mod to Steam workshop "error requesting Steam to update the item" [B42.20.4][LINUX]`，
回帖里另有一位 macOS 用户症状完全相同：物品能创建（拿到 ID），但内容永远是 0.000 B。

本机环境：PZ **42.21.0**（`~/Zomboid/version.txt`）、macOS 27 / Apple Silicon、系统语言 `zh-Hans-CN`，
并且本机 `~/Zomboid/Workshop/` 里就躺着一个已创建但空着的工坊物品（`id=3811968819`），
Steam 客户端 `workshop_log.txt` 里只有 `Create new workshop item ... (OK)`、没有任何 Update 记录 —— **本地可复现**。

### 一、根因链条

```
Page7:updateWhenVisible()                     media/lua/client/OptionScreens/WorkshopSubmitScreen.lua
  └─ self.item:submitUpdate()                 zombie.core.znet.SteamWorkshopItem
       ├─ RenderThread.invokeQueryOnRenderContext(this::确认框)   ← 必须返回 true
       │    └─ org.lwjgl.util.tinyfd.TinyFileDialogs.tinyfd_messageBox(t,m,"okcancel","warning",2)
       │         macOS: osascript + AppleScript，把 button returned 和 "Yes"/"OK"/"No" 比字面量
       │         中文系统默认按钮是"好" ⇒ 落到 else ⇒ return 0 ⇒ tinyfd 返回 0
       └─ SteamWorkshop.instance.SubmitWorkshopItem(item)         ← 因此**从未执行**
```

于是 Lua 走进 `else` 分支打印 `error requesting Steam to update the item`，
`ISteamUGC::SubmitItemUpdate` 一次都没被调用 —— 这正好解释了"Steam 客户端日志里什么都没有、物品 0 B"。

### 二、证据（全部可在本机复现）

| # | 证据 | 命令/来源 |
|---|------|-----------|
| 1 | 错误文本出自 Lua 的 `submitUpdate()` 失败分支 | `grep -n "update the item" …/WorkshopSubmitScreen.lua` → 1082/1090 行 |
| 2 | `submitUpdate()` = 确认框 && `SubmitWorkshopItem` | `javap -p -c zombie/core/znet/SteamWorkshopItem.class`（`ifeq` 在 `iload_1` 之后） |
| 3 | 确认框就是 tinyfd，且要求 `== 1` | `lambda$submitUpdate$0()` 字节码 + `javap -v` 的 `makeConcatWithConstants` 常量 |
| 4 | 直接调该 API 得到 **0**（不是 1） | 用游戏自带 jar + JRE 跑 20 行测试程序：`tinyfd_messageBox returned = 0` |
| 5 | tinyfd 实际执行的 AppleScript（抓到真实 argv） | PATH 前置假 `osascript` 记录 `"$@"` |
| 6 | 真 `osascript` 重放该脚本 → `stdout='0\n'` | 限时 15s，无 stderr，exit 0 |
| 7 | 按钮名被本地化：`button returned:好` | `display dialog … giving up after 4` 探针 + `defaults read -g AppleLanguages` = `zh-Hans-CN` |
| 8 | Steam 客户端只记录了 Create、没有 Update | `~/Library/Application Support/Steam/logs/workshop_log.txt` 第 8646 行附近 |

**为什么 Windows 正常**：tinyfd 走 Win32 `MessageBoxA`，`IDOK=1/IDCANCEL=2` 是数字，与语言无关。
**为什么 Linux 也坏**：tinyfd 依次找 `zenity`/`kdialog`/`yad`/`gxmessage`/`Xdialog`，Steam 启动的游戏没有终端，
都找不到时返回 -1，同样 `!= 1`。

### 三、修复

那份原生确认框在 macOS/Linux 上本来就只有一个"确定"按钮，返回值不该是上传前置条件，所以只改 `submitUpdate()` 一处：

```diff
  9: istore_1
- 10: iload_1
- 11: ifeq 28
+ 10..13: nop nop nop nop
 14: getstatic SteamWorkshop.instance
 18: invokevirtual SubmitWorkshopItem
```

交付物：`bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py`（纯标准库；`--dry-run/--verify/--restore/--game-dir`）。
工程要点：

* 21 字节特征串精确定位并且**要求恰好命中一次**，否则拒绝修改（游戏更新后安全退出，不会改坏 jar）；
* **整包重写** jar 来替换这一个成员：其余 26140 个条目的名称/时间/压缩方式/属性/顺序原样保留，
  重写后 CRC、压缩后长度、data descriptor 全部自洽 ⇒ `ZipFile`/`ZipInputStream`/`unzip` 都能读；
* 先写临时文件并自检（`testzip()` 全量 CRC + 目标成员内容），再覆写原路径（inode 不变 ⇒ 权限/xattr 保留）；
* 备份只在"原版"状态下创建，并记录 `original_member_sha256`；`--restore` 先核对哈希，不一致拒绝还原；
* 幂等；`--dry-run` 对 `--restore` 也生效。

（第一版是"就地改 4 字节 + 补 `\x00` 对齐原压缩长度"，翻车点见下面第 8 条。）

### 四、验证（本机实测）

1. `python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py` → `[ok] patched + verified`，`entries=26140, member csize=10030 usize=20721`；
2. `javap -p -c` 反汇编：`10..13` 已是 4 个 `nop`，`SubmitWorkshopItem` 直接可达（确认框调用仍保留）；
3. 用**游戏自带 JRE 25** 从真实 jar 里 `Class.forName` 加载该类：`class loaded + verified`，无 VerifyError；
4. `unzip -t projectzomboid.jar` → `No errors detected`；`JarFile` 读取 CRC 正确（`crc=1735906023`）；
5. `/tmp` 副本上跑 patch → restore 往返，`cmp` 与原始文件**逐字节一致**；`--restore --dry-run` 确实不写盘；
6. 脚本 `--verify` 重跑报 `already patched`（幂等）；
7. **上传前链路逐调用自检**（关键补强）：用游戏自带 jar + JRE 25 起 Steam（`SteamAPI_Init` 成功加载
   `steamclient.dylib`，AppID 108600），把 `SubmitWorkshopItem()` 里的 native 调用一个个执行、
   **唯独不调 `n_SubmitItemUpdate`**（不上传）：`StartItemUpdate/SetItemTitle/SetItemDescription/
   SetItemVisibility/SetItemTags/SetItemContent/SetItemPreview` **全部返回 true**，
   `readWorkshopTxt()` 也正确读到了 `id=3811968819 / title / visibility`。
   ⇒ 排除了"即使过了确认框，后面的 native 调用在 macOS 上也会失败"这一替代解释，
   **唯一返回 false 的就是那个本地化确认框**。工具已收录为 `bin2_workshop_upload_fix/tools/pz_workshop_probe/`。
8. **子代理独立复核抓到的两个真缺陷**（都出在第一版"就地补零"实现上，已重写并复验）：
   * 成员带 data descriptor（flag bit 3）时，descriptor 里的 CRC 没有同步改写 ⇒ 结构不自洽；
   * 尾部补零能让 `ZipFile`/`unzip` 通过，却会让 `java.util.zip.ZipInputStream`
     报 `invalid entry size (expected ... but got 20721 bytes)`（它按流位置找 descriptor）。
     改成整包重写后，`ZipInputStream` 全量读 26140 条目 / 142 MB 无异常；
     "其他条目逐条目内容一致、只有目标成员不同"也验证过了。
   子代理另外指出 `--dry-run --restore` 会真的还原、`--restore` 不校验备份哈希，已一并修掉。

**未做**：没有真的调用 `n_SubmitItemUpdate`、也没有在游戏内点一次真实上传
（前者会把用户模组直接发布到工坊、后者需要走完 UI 向导，都留给用户侧）。
补丁后走的就是 Windows 成功时的同一条 Java 路径。

### 五、同一问题的第二种修法：ZombieBuddy 运行时补丁（推荐）

用户问"可以用 ZombieBuddy 修复么"。查了本机已装的 ZombieBuddy 2.3.2（workshop 3619862853，作者 Zed）：
它是一个基于 ByteBuddy 的注解式运行时补丁框架（`@Patch(className, methodName)` + `@Patch.OnEnter/OnExit/
This/Return`），并且自带完整文档与示例；**官方示例里就有一个 `ZBetterWorkshopUpload`**，
patch 的正是 `zombie.core.znet.SteamWorkshopItem`（`getContentFolder`/`getSubmitDescription`），
说明这条路径在该类上是现成可用的。

于是新增补丁模组 `bin2_workshop_upload_fix/`（照 `bin2_viewpoint` 的仓库约定：模组在
`Contents/mods/ZBWorkshopUploadFix/`，`mod.info`/`src/`/`media/java/client/*.jar` 都在 `42.21/` 版本目录里，
`require=\ZombieBuddy`，`javaPkgName`；同目录还放了 tools/ 三个工具与 docs/）：

* 补丁本体：`@Patch.OnExit` 挂在 `submitUpdate()` 上，返回 `false` 且非 Windows 时补一次
  `SteamWorkshop.instance.SubmitWorkshopItem(item)`；**不跳过原方法**（确认框照旧弹），
  Windows / 英文系统行为完全不变；
* 没有去补 `TinyFileDialogs.tinyfd_messageBox`：那是 ZombieBuddy **自己审批 Java mod** 用的同一个方法
  （`TinyfdModApprovalFrontend`），全局改成返回 1 会让所有 Java mod 静默过审（安全问题）；
* 本机已链接到 `~/Zomboid/mods/ZBWorkshopUploadFix`（与用户其它本地 mod 一样用 symlink 指向仓库），
  只需在游戏里启用这个 mod、并在 ZB 弹窗里允许加载。

**工坊物品就绪**：`workshop.txt`（`tags=Build 42;QoL;Misc`，`visibility=public`，暂不写 `id=`）、
`changelog.txt`、`preview.png`(256) 与 `42.21/poster.png`(512) 都由 `tools/make_images.py`
（Pillow 绘制：深色 + 网格 + 终端日志，风格对齐 `bin2_viewpoint`）可复现地生成。
踩坑：`preview.png` 有硬性规则 —— 游戏 `SteamWorkshopItem.validatePreviewImage()` 要求**正方形且边长只能是
256 或 512**、≤1024000 字节、且必须是 PNG；一开始按仓库里 `bin2_viewpoint` 的 1024x1024 出图，被游戏判为
`PreviewDimensions`（已用探针做正反两组验证：256 → `OK`，1024 → `PreviewDimensions`）。
`workshop.txt` 的格式用**游戏自己的** `SteamWorkshopItem.readWorkshopTxt()` 验证过
（title/visibility=2/tags/description=1680 chars 解析正确），并确认软链的待上传目录能被
`ZomboidFileSystem.validatePrefix()` 接受、也会出现在 `getStageFolders()` 列表里
（它的过滤器是 `Files.isDirectory(path, LinkOption[0])`，跟随符号链接）。

**离线自测**（`bin2_workshop_upload_fix/test/run_offline_test.sh`，需要一点 `-javaagent` 技巧拿到 `Instrumentation`）：
用 ZombieBuddy 自带的 `PatchTransformer` 把我们的 `@Patch.*` 别名注解翻译成 ByteBuddy 的 `@Advice.*`，
挂到假的 `submitUpdate()` 上调用，结果全部通过：

```
[ok]   PatchTransformer 返回补丁类
[ok]   补丁方法上出现了 ByteBuddy 的 @OnMethodExit
[ZBWorkshopUploadFix] SubmitWorkshopItem threw: java.lang.ClassCastException: ...DummyTarget cannot be cast to ...SteamWorkshopItem
[ok]   原方法没有被跳过（确认框仍会弹）
[ok]   补丁代码确实执行了（打出了 ZBWorkshopUploadFix 日志）
[ok]   对照组：返回值被 @Return(readOnly=false) 改写为 true
== ALL CHECKS PASSED ==
```

（第一条"CCE 被兜住"正是预期：假目标不是 `SteamWorkshopItem`，说明 advice 真的被内联执行了。）

**踩坑**：ByteBuddy Advice 是**内联**进目标方法的，访问权限按目标类判定 ⇒ `WorkshopUploadFix`
的类与方法必须 `public`，包私有会在游戏里 `IllegalAccessError`。另外测试 agent 的清单必须声明
`Can-Redefine-Classes`/`Can-Retransform-Classes`，否则 ZB 的 `PatchTransformer` 无法重定义补丁类。

两种修法可以共存（不会重复提交：jar 补丁让 `submitUpdate()` 返回 true，ZB 补丁就什么都不做）。
想只留 ZB 方案、把游戏文件还原：`python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --restore`。

### 六、把经验固化成 DSH Skill

新增项目级 skill `.dsh/skills/pz-engine-deepdive/SKILL.md`（frontmatter：`name` / `description` / `whenToUse`）。
DSH 的 skill 文件系统提供者默认扫描 `<项目>/.dsh/skills`、`<项目>/.agents/skills`、`~/.dsh/skills`、
`~/.agents/skills` 与内置目录，并带文件监听：写完当前会话的 skill 目录即时生效，`skill` 工具可直接加载。
内容是一条可复用的链路：环境事实（Java 25 字节码/JDK 25/自带 JRE/日志路径）→ 六步取证法
（错误串找出处 → javap 读调用链 → 直接调 API 拿返回值 → 假可执行文件抓真实 argv → 对照实验 → 子代理证伪）
→ tinyfd 三平台差异与"别全局改"的安全理由 → ZombieBuddy `@Patch` 语义表与离线自测 → 整包重写改 jar 的纪律
→ 工坊交付与 `validatePreviewImage` 硬性规则 → 交付前自检清单。

### 七、第二个 skill：工坊物品打包与发布

按"一件事一个 skill"把工坊交付规格独立成 `.dsh/skills/pz-workshop-item-publishing/`：
物品目录布局与路径规则（`Contents` 才会被打包）、`workshop.txt` 字段表（多行 `description=`、
`tags` 白名单、`visibility` 0/2、未发布不写 `id=`）、`changelog.txt` 惯例、`preview.png` 四条硬性规则
（256/512 正方形、≤1024000 字节、PNG）与 `poster.png` 惯例、`mod.info` 发布相关字段、
软链 staging 的安全性依据、上传流程与成功判据、上传前探针校验、踩坑清单与发布前 checklist。
`pz-engine-deepdive` 第 6 节收缩为指针 + 取证入口，避免两份规格漂移。

### 八、后续 / 建议

* 游戏更新或 Steam"验证文件完整性"会覆盖 jar ⇒ **重跑脚本**；
* 向 TIS 报 bug 时附上本机两条可复现证据（tinyfd 返回 0；AppleScript 里 `button returned:好`）；
  建议：确认框返回值不要作为前置条件、显式指定按钮、把 Page7 日志落盘到 `WorkshopLog.txt`（源码里 TODO 仍在）；
* Linux 用户若不改游戏文件，可尝试装 `zenity` 让 tinyfd 找到对话框工具（分支按退出码判断，与语言无关）。

完整技术文档：`docs/pz-steam-workshop-upload-macos-linux-fix.md`。

---

## 扩展 Companion Dogs（Workshop 3740052292）：新物种「羊驼」addon

### 任务背景

用户要求"扩展 3740052292 模组，创建一个羊驼的宠物模组"。该 ID 在仓库里没有对应目录，先在
`~/Zomboid/Lua/ModManager/ModListData.ini:364-371` 定位到 `["CompanionDogs"] = { workshopID = 3740052292 }`
⇒ 目标是 [Companion Dogs [ALPHA]](https://steamcommunity.com/sharedfiles/filedetails/?id=3740052292)
（base 0.7.4 / `CD.API_VERSION = 11`）。

它自带官方 addon 契约手册：<https://companiondogs.pet/docs/en/modding.html>，明确允许第三方为它做
addon 与新物种，并要求注明出处。生态里已有新物种范例 `CompanionCat`（3791294616）与新品种范例若干
（Pug / Labrador / Doberman / Rottweiler / Malinois），因此实现路线是"照契约写，不碰 base 内部"。

交付物：`bin2_companion_alpaca/`（工坊物品目录），模组 id `CompanionDogsAlpaca`，
`require=CompanionDogs`，版本 0.1.0，7 种毛色，EN/CN/CH 三语。

### 一、契约要点（以 base 代码为准，手册冲突处已标注）

| 事项 | 结论 | 证据 |
| --- | --- | --- |
| 新物种注册 | `CD.registerSpecies{key, nounKey, youngKey, labelKey}`，`labelKey` 手册漏写 | `media/lua/shared/CompanionDogs/skills/Species.lua:14` |
| 品种注册 | `engineBreed` 事实必填（缺省是 `CD.BREED = "brown"`，不是 key） | `skills/Skills.lua:240-243` |
| 钩子保护 | base 全目录**没有 pcall** ⇒ handler 必须自保 | `skills/BreedAPI.lua:12-24`、`server/systems/CompanionDogs_Hunting.lua:1033-1038` |
| 循环音 | `registerVoices` 不写 `CD.SOUND_LOOPED`，必须自己补 | `config/Needs.lua:26,76-92` |
| 剥皮表 | 键 = `<typePrefix><sex><engineBreed>`，每毛色一次；不注册会崩 | `Definitions/animal/CompanionDogs_Parts.lua:9-27`、`ButcheringUtil.lua:15` |
| 尺寸语义 | `minSize/maxSize` 就是模型缩放（米），`puppySize` 是绝对值且每轮强制写入 | `CowDefinitions.lua:191-193`、`server/CompanionDogs/life/Mounted.lua:134-141` |
| moodle | `breed` 字段是"品种专属"开关而非过滤器，过滤要写在 `condition`；icon/fg 需 6 个尺寸 | `client/CompanionDogs_Moodles.lua:538-558,561-598,697-710` |
| 版本戳 | 只有 mod id 以 `Companion` 开头才会被日志打印 | `VersionStamp.lua:12-17` |

### 二、模型：程序化派生（仓库与游戏都没有羊驼模型）

契约要求新物种自带绑定到同一骨架、且含全套 `Rac_*` 剪辑的 glb。本机 800 个已装模组里没有任何羊驼/llama，
B42 原版动物也没有 ⇒ 经用户确认走"从 base 授权的金毛模型派生"路线，工具为
`bin2_companion_alpaca/tools/alpaca/derive_alpaca.py`：

1. 骨骼段重比例（`t_new = t_rest + (k-1)·t_rest`，rest 与 24 个剪辑一起改）；
2. 姿态增量（父骨骼空间左乘常量四元数：长颈、口鼻水平、立耳、短尾）；
3. 网格形变（按蒙皮权重区域缩放 + 法线方向噪声 = 绒面）；
4. **重新落地**：拉长腿后静止姿态 ≠ 绑定姿态，脚会沉到地面下 0.062，按真实蒙皮 min-y 抬回；
5. 姿态角用网格扫描求解（`tune_pose.py`，目标：脖子 74°、口鼻 -5°），而不是肉眼调。

**关键 bug 与修法**：第一版 idle 剪辑被拉爆（头到 z=1.33）。根因是同一个剪辑内多条 channel
**共用同一个 accessor**，就地写共享数据让增量叠加了 11 次。改为给每条受影响通道克隆独占
accessor + sampler（`glb_util.detach_channel_output`）。该问题已变成 glb 校验器里的一条断言
（带蒙皮权重的关节，平移通道 |t| ≤ 1.0）。

### 三、验证结果（`bin2_companion_alpaca/tools/check.sh` 全绿）

```
Lua 5.1 语法（luaparse）      5/5 OK
翻译（自写校验器）            EN/CN/CH 各 53+3+1 键，键集合一致，无重复键/BOM/裸 %
声音范围一致性（自写校验器）  9 条 distanceMax 与 registerVoices 逐条相同；两条循环音都在 SOUND_LOOPED
glb 结构（自写校验器）        55 骨骼（≤60）、24 剪辑、accessor 无越界、min/max 一致、平移最大 0.175
图片                          30/30（工坊预览 256×256 PNG）
声音                          9/9（44.1 kHz / 2ch）
Lua 集成测试（fengari+mock）  11/11 断言通过（注册契约/顺序/生成/剥皮/moodle/气候钩子）
离线渲染目视                  静止 + idle/walk/run/eat/attack/lie 均无变形、无冻结
工坊物品（游戏自带解析器）     readWorkshopTxt=true、tags=[Build 42, Animals, Misc]、
                              contentFolder exists=true、validatePreviewImage=OK
```

**集成测试自己也做了证伪实验**（改测试文件 → 跑 → 恢复并 `diff -q` 验证字节一致；模组本体全程未改）：
让 mock 拒绝一个毛色 → 断言 5 与 11 变红；把一次 `registerBreed` 记录挪到 `registerVoices` 之前 → 3 变红；
去掉 `CD.SOUND_LOOPED` → 4 变红；把期望 `nameKey` 写错 → 5 变红；往"禁止全局"集合里塞一个必然存在的
全局名 → 1 变红。五条都真的红过，证明断言不是空转。

### 四、已知限制（未做/未验证，如实记录）

* **没有在游戏内实测**：静态验证与离线渲染全绿，但不等于进游戏 100% 正确；模型观感、鞍袋/帽子挂点数值、
  沙盒页显示都还需要进游戏目视确认。
* `bandSkin`（绷带/断裂四变体贴图）未提供：受伤仍会流血、可治疗、可缠绷带，只是不显示绷带纹理。
* 声音为 numpy 合成音，未做听感验证。
* 只有 EN / CN / CH 三语，其它语言回落英文。
* `workshop.txt` 当前 `visibility=private`；正式公开前改为 `public`（首次上传不要写 `id=`）。
* 已建立 staging 软链：`~/Zomboid/Workshop/bin2_companion_alpaca`、`~/Zomboid/mods/CompanionDogsAlpaca`。

完整过程记录见 `docs/rolling_log.md`（2026-10-03 条目）；契约与踩坑速查见
`docs/pz-companion-dogs-addon.md`；模组自述见 `bin2_companion_alpaca/README.md`。

---

## 追加：模型返工 —— 用 CC0 羊驼网格替换"拉长脖子的狗"

### 起因与决策

第一版羊驼模型是**程序化重塑 base 的金毛模型**（`tools/alpaca/derive_alpaca.py`：骨段重比例 +
姿态增量 + 网格区域缩放/绒面噪声）。用户看过渲染后判定"与羊驼差别太大"。复盘确认：
该路线只能改比例，改不了解剖结构——**钝吻、额顶绒毛、桶状躯干**做不出来，头骨与躯干断面仍是犬科底子。

决策：换**几何来源**，并优先找 CC0 / Public Domain 资产。找到
[Quaternius 的 "Alpaca"](https://poly.pizza/m/bCVFD48i2l)（模型页标注 **Public Domain (CC0)**，
页内 JSON `"Licence":"CC0 1.0"`；直链 `https://static.poly.pizza/444228bb-745d-49b2-89ef-cc12805deaa8.glb`），
原件入库为 `tools/alpaca/vendor/alpaca_cc0.glb`（+ 出处/授权/sha256）。

资产实况：2060 三角形 / 4156 顶点，按材质拆 7 个 primitive，**无 UV、无贴图**（纯色材质），
46 骨骼四足骨架，26 个自带动画；绑定是四足 T-pose，站立姿态在 Idle 里。

### 实现：保留 base 骨架与剪辑，只把网格"翻译"进绑定空间

`tools/alpaca/build_alpaca_from_cc0.py`：

1. 合并 7 个 primitive 并记录每三角形材质号；
2. 46 → 55 骨骼**显式对应表**（两套骨架名字/拓扑完全不同；带权重的 IK/pole 骨也必须映射）；
3. **Umeyama 全局相似变换**（FBX 的动画世界坐标是绑定的 ~100 倍，不做这步尺度差 13 倍）；
4. 逐骨骼仿射传递目标形状 `p_target = Σ w·(G·S_β)·v`；
5. **逆蒙皮烘焙** `v_bind = (Σ w·D_b)⁻¹·p_target`（本文最关键的修正，见下）；
6. 法线由目标形状重算 + `(Σw·D_b)⁻ᵀ` 预补偿；
7. 每三角形独立 UV 岛 + 按材质分类画 7 张毛色图集。

### 两个真实踩过的坑

| 症状 | 根因 | 修法 |
| --- | --- | --- |
| 静止网格正常，但表面像"一地碎瓷片"，缝隙透出背景 | 用 `Σ w·(D_b⁻¹·G·S_β)` 算位置、却让引擎用 `Σ w·D_b` 变换它；**混合与求逆不可交换**，每顶点残差方向不同 | 改为**逆蒙皮烘焙**：先定目标形状，再解 `v_bind = (Σ w·D_b)⁻¹·p_target`（4156/4156 精确解出，病态时兜底最大权重骨）。同理：**落地偏移要加在目标形状上再重解** |
| 静止正常，动画里**腿与尾巴被撕开** | 我做了 3 轮网格邻接权重平滑（alpha 0.55），把腿的权重糊到躯干、尾巴的权重糊到臀腿 | 默认**不平滑**（保留作者权重）；需要时 1 轮、alpha ≤ 0.25 |

### 结果与新数值

* 网格：2060 三角形 / 6180 顶点（每三角形独立 UV），**静止高 0.4523 单位**（≈ 肩高 0.9 m @ size 2.6）；
  55 骨骼、24 个 `Rac_*` 剪辑一个不少、animset 仍为 `raccoon`；CC0 自带的骨架与动画**未使用**。
* 离线渲染逐剪辑确认：rest / idle / walk / run / eat（低头吃草）/ attack 均不冻不裂、脚踩地。
* 动物定义按新网格重标定：成年 `size` 2.60~3.35；幼驼 `puppySize` 1.60 → **1.85**（≈0.84 m）；
  阴影 0.34/0.52（幼）/0.45/0.70（成）；头像相机体型比 **2.16 → 2.24**。
* `models_alpaca.txt`：帽子挂点 (y 0.39→0.40, z 0.156→0.21)、驮袋 offset/scale 按新躯干重算
  （**未进游戏验证**，仍需目视微调）。
* 头像/海报/预览/图标全部重生成；`validate_glb.py` 新增三条断言（必须有 `TEXCOORD_0`、
  顶点数是 3 的倍数、索引必须是 `0..N-1` 连续）。
* `tools/check.sh` 全绿：Lua 语法 5/5、翻译 EN·CN·CH、声音范围一致、glb OK、
  图片 30/30、声音 9/9、**Lua 集成测试 11/11**、游戏探针 `readWorkshopTxt=true` / `validatePreviewImage=OK`。
* 删除已被取代的 `tools/alpaca/make_textures.py`（犬体毛皮重绘）；`derive_alpaca.py` 保留，
  但现在只用于**骨架比例调参**（`BONE_LEN`/`BONE_ROT`，被新脚本 import）。

技术总结：`docs/pz-cc0-mesh-retarget.md`（逐骨骼仿射传递 + 逆蒙皮烘焙的可复用做法）。

---

## 追加：ViewpointMac41Patch（工坊 3812168749）—— 从"桥缺 GL 4.3"更正为"垫片门控反相"并给出修复方案

### 任务背景

用户问："`/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600/3812168749`
这个模组修复的思路方案是什么"。此前（同一天）本仓库已定位到"进世界首次绘制 JVM abort，落点
`GL43C.glVertexAttribFormat`"，并写了一份给作者的报告。本次目标是给出**可执行**的修复方案，
因此先把全部结论拉回"可复现证据"这一层重新核了一遍。

### 一、最重要的更正：证据取自了错误的 jar

| jar | sha256（前 16） | 大小 | `MeshArena` 里调谁 |
| --- | --- | --- | --- |
| 上游 Viewpoint（工坊 3809306528） | `94fedda302ab6c17` | 2 068 978 B | 直接 `org/lwjgl/opengl/GL43.glVertexAttribFormat` |
| 补丁 payload = 游戏实际加载 | `9d8d4890a2657cc1` | 2 149 583 B | `viewpoint/mac41/Draws41.glVertexAttribFormat`（有门控） |

payload 多出的 30 个 `viewpoint.mac41.*` 类是作者自写的 macOS 兼容层，**已覆盖全部 32 个 GL4.2+ 入口**；
`Mac41$BridgeAccess` 还专门反射 `pzmac41.Bridge.nativeCapabilities()/active()/onDestroy`，说明它就是为这个桥写的。

### 二、真正的根因

```
Draws41.glVertexAttribFormat: nativeVertexPath() ? GL43.glVertexAttribFormat : <垫片>
Mac41.nativeVertexPath():     if (!active()) return true;        // 没有兼容层 ⇒ 假定原生 4.3
Mac41.active():               MAC && nativeCapabilities().OpenGL41 && (PROFILE_MASK & 1)
```

桥合成的 caps 只标到 3.3（日志 `… OpenGL33 true …`）⇒ `active()==false` ⇒ 垫片被短路绕过 ⇒
调原生 GL4.3；Apple 从不导出这一族（`dlsym` 探针：5 个顶点格式函数全 NULL）⇒ 地址表槽位 0 ⇒
LWJGL 空地址桩 abort。

### 三、方案（三层，已做离线原型）

1. **主修**：自研 javaagent，类加载期**常量池 Methodref 重定向**（只改 `class_index`，方法体不动）：
   `Mac41.active()Z` → `MAC && core ≥3.2` 的实现；`Mac41.nativeVertexPath()Z` → 恒 `false`。
   对**所有类**生效，让作者自带的 32 函数垫片真正跑起来。
2. **安全网**：`org/lwjgl/opengl/GL43` 的 5 个 4.3 顶点格式入口 → 自研 GL4.1 降级实现
   （`attrib→(size,type,norm,relOff,binding,divisor)`、`binding→(buffer,offset,stride)`，
   `glBindVertexBuffer` 时重放 `glVertexAttribPointer`+`glVertexAttribDivisor` 并恢复 `GL_ARRAY_BUFFER`）。
3. **诊断**：首次碰到垫片类时打印 `gate:` 一行（有效 caps 的 OpenGL33/40/41、`Bridge.nativeCapabilities().OpenGL41`、
   `Bridge.active()`、`Bridge.isLegacyMac()`、我们的 active），一次跑清"为什么 active 为假"。

**集成**：安装器 `Installer.verifyInstalled()` 第 279 行硬性要求"恰好 2 个 `-javaagent`"，且校验
`plist.sha256`/payload 哈希 ⇒ 不改 plist、不改 jar，改用 `JAVA_TOOL_OPTIONS="-javaagent:…"` +
`Jogar.shim.command` 包装（实测游戏自带 JRE 25 认这个环境变量并执行 premain；marker 文件用于确认）。

### 四、验证结果

| 项 | 结果 |
| --- | --- |
| 门控重定向（真实 `Mac41`/`Draws41`/`Textures41` 字节） | ✅ 全部指向 `pzglshim/Emul`，常量池 +2 条目，`javap` 正常 |
| 4.3→3.3 状态机（记录型 Sink） | ✅ formats-first、换 buffer 重放、先 bind 后 format、整数格式、ARRAY_BUFFER 恢复 |
| 端到端（真实 `GL43` + 替身 `GL43C`） | ✅ `INTEGRATION PASSED (GL43 -> pzglshim.Emul)`，未走 native |
| agent 注入 | ✅ `-javaagent` 与 `JAVA_TOOL_OPTIONS`（游戏自带 JRE）premain 均执行 |
| 合计 | ✅ 23/23 checks，0 failure |

### 五、已知限制（如实记录）

* **未在游戏里跑过**：需要用户在隔离实例上跑一次；本次全部结论为字节码/探针 + 离线原型。
* **门控真值未现场观测**：`active()` 为假的两个可能来源（桥只标 3.3 / `Bridge.nativeCapabilities()` 给的不是原生 caps）
  由第 3 层日志在下次运行时确证；两种来源本方案都覆盖。
* Iris 的 compute 路径（`glDispatchCompute`/`glMemoryBarrier`）在 `graphics.mode=Vanilla` 下是否被调用未验证。
* 未在 Intel Mac 上验证（作者也只测过一台 M1）。
* 许可：补丁包是 private alpha、上游 Viewpoint 禁止再分发/反编译复用；本 shim 只做互操作性修正，不含被复制代码。

方案：[`viewpoint-mac41-gl43-fix-plan.md`](viewpoint-mac41-gl43-fix-plan.md)；证据：[`research/`](research/)。

---

## 追加：第二个造型 —— 脚本生成的方块羊驼（独立工坊物品）

### 起因

用户提问"能借鉴 MC 的羊驼模型么"。查证后结论是：**风格可借鉴、资产不可搬**。
Minecraft 的 [Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines) 把 models/textures 列入
"Our assets" 并明确禁止再分发；[EULA](https://www.minecraft.net/en-us/eula) 要求 Mod 不得包含其版权内容。
存在自由许可的替代品（[VoxeLibre](https://github.com/VoxeLibre/VoxeLibre)，GPL-3.0，其
`mobs_mc_llama.b3d` 模型由 22i 以 GPLv3 授权），但会传染许可。最终选择**自己用脚本拼盒子**（用户选定）。

### 实现

新物品 `bin2_blocky_alpaca/`（mod id `CompanionDogsBlockyAlpaca`，`require=CompanionDogs,CompanionDogsAlpaca`）：

* `tools/blocky/make_blocky_alpaca.py`：按骨段生成 23 个长方体（828 顶点 / 276 三角形），
  每顶点 100% 绑一根骨头，逆蒙皮烘焙进 base 骨架的绑定空间；腿链与脖子"竖直化"（只改位移）；
  每盒面一个图集格子，输出 4 张毛色图集（spot 每只随机加深）。
* `tools/blocky/make_images.py`：4 张品种头像 + 图标 + 海报 + 工坊预览（复用写实羊驼的字体/网格工具）。
* Lua 三个文件：**不新开物种**，复用写实羊驼注册的 "alpaca" 物种、叫声与肉物品；
  把 4 个品种键并进它的 `BREED_KEYS`/`ENGINE_BREEDS` ⇒ 方块羊驼自动继承"羊毛暖意" moodle 与怕热/耐寒应激。
* 尺寸按"世界高度一致"反推（静止高 0.5589 单位 × 0.809 ≈ 写实 0.4523 × 1.0）。

### 两个关键技术坑（已写入物品内的 models_blocky.txt 与 README）

| 症状 | 根因 | 修法 |
| --- | --- | --- |
| 静止渲染完美，一播 walk/eat 方块散架 | **每条剪辑对每根骨头都有位移轨道**（55 骨骼 × 23~24 条），运行时覆盖静止位移 | 增量**同步写入全部剪辑的位移通道**（改写 414 条）；做法照 base 的 `apply_bone_lengths` |
| gallop 时蹄子飞出 | 独立蹄盒绑在位移最大的脚骨上 | 取消独立蹄盒，腿的最下一段直接用蹄色 |

普适结论：**在该骨架上改任何静止位移都必须同步改剪辑通道**，否则只有播动画才暴露问题。

### 校验状态（全绿）

* Lua 5.1 语法 3/3；翻译 EN/CN/CH 各 12 键、键集合一致且与 `Breed.lua` 交叉一致
* glb：55 骨骼 / 24 剪辑 / 828 顶点 / 276 三角形 / 静止高 0.5589 / UV+索引连续
* 图片 7/7（工坊预览 256²、海报 512²、图标 64²、头像 4×512²）
* 新增 fengari 契约测试 **9/9 ALL PASS**（依赖缺失早退、7+4=11 次 registerBreed、12 个剥皮键、
  并进写实羊驼集合、CD.log 无禁忌词）
* 游戏自带解析器探针：`readWorkshopTxt=true`、`validatePreviewImage=OK`、`tags=[Build 42, Animals, Misc]`、`visibility=2`
* 未做：游戏内实测；公开前需把 `visibility` 改 `public`
