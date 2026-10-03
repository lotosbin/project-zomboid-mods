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

### 七、后续 / 建议

* 游戏更新或 Steam"验证文件完整性"会覆盖 jar ⇒ **重跑脚本**；
* 向 TIS 报 bug 时附上本机两条可复现证据（tinyfd 返回 0；AppleScript 里 `button returned:好`）；
  建议：确认框返回值不要作为前置条件、显式指定按钮、把 Page7 日志落盘到 `WorkshopLog.txt`（源码里 TODO 仍在）；
* Linux 用户若不改游戏文件，可尝试装 `zenity` 让 tinyfd 找到对话框工具（分支按退出码判断，与语言无关）。

完整技术文档：`docs/pz-steam-workshop-upload-macos-linux-fix.md`。
