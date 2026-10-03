# PZ 在 macOS / Linux 上传创意工坊失败：定位与修复

> 症状：游戏内 Workshop 上传向导只输出
> `error requesting Steam to update the item`，创意工坊物品被创建但永远是 0.000 B；
> 同一套模组在 Windows 上一切正常。
> 环境：Project Zomboid **42.21.0**（Steam 108600，报告帖为 B42.20.4）、macOS 27 / Apple Silicon、系统语言 `zh-Hans-CN`。
> 相关反馈帖：<https://steamcommunity.com/app/108600/discussions/1/582806854239939623/>

## 1. 结论（一句话）

`zombie.core.znet.SteamWorkshopItem.submitUpdate()` 把"LWJGL tinyfd 原生确认框返回 1"当作上传的前置条件；
而 tinyfd 在 macOS 上用 AppleScript 实现，它把对话框按钮名和**写死的英文字面量** `"Yes"/"OK"/"No"` 比较——
非英文系统上那个唯一的默认按钮是**本地化**的（中文是"好"），于是返回 `0`，`submitUpdate()` 直接 `return false`，
`SubmitItemUpdate` 从未被调用。Windows 走 Win32 `MessageBox`（IDOK/IDCANCEL 是数字）所以不受语言影响。

## 2. 证据链

### 2.1 Lua 侧：错误信息来自 `submitUpdate()` 返回 false

`Contents/Java/media/lua/client/OptionScreens/WorkshopSubmitScreen.lua`（Page7）：

```lua
elseif self.state == "update" then
    if TEST or self.item:submitUpdate() then
        self:LOG("success requesting Steam to update the item")
        ...
    else
        self:LOG("error requesting Steam to update the item")   -- 用户看到的这一行
        self.state = "updateFail"
    end
```

同一份文件里 Page6 的提示也印证了这个"原生弹窗"的存在：
`"WARNING: Uploading a mod will require clicking a popup box which may not be visible in Fullscreen/Borderless mode."`

### 2.2 Java 侧：`submitUpdate()` 依赖一个原生确认框

`javap -p -c zombie/core/znet/SteamWorkshopItem.class`（游戏自带 `projectzomboid.jar`，class 主版本 69 / Java 25）：

```
public boolean submitUpdate();
   0: aload_0
   1: invokedynamic  #177  // accept:(SteamWorkshopItem) -> Params0$Boolean$ICallback
   6: invokestatic   #181  // RenderThread.invokeQueryOnRenderContext(...)Z
   9: istore_1
  10: iload_1
  11: ifeq  28              // ← 只有确认框返回 1 才继续
  14: getstatic  #168       // SteamWorkshop.instance
  18: invokevirtual #187    // SteamWorkshop.SubmitWorkshopItem(SteamWorkshopItem)Z
  21: ifeq  28
  24: iconst_1
  25: goto  29
  28: iconst_0
  29: ireturn
```

被 `invokedynamic` 引用的 `lambda$submitUpdate$0()` 就是那个确认框，它调用的是
`org.lwjgl.util.tinyfd.TinyFileDialogs.tinyfd_messageBox(...)`（LWJGL 自带的 tinyfd 原生库，
本例 dylib 里可见 tinyfiledialogs 版本串 `3.19.3`），随后：

```java
// 等价源码
if (new java.io.File(...) ... )
int r = TinyFileDialogs.tinyfd_messageBox(
        "WARNING: Steam Workshop upload requested!",
        "Please confirm you want to upload this mod to the Steam Workshop:\n\n" + title + id + "\n\n" +
        "If you did not request this, click Cancel.",
        "okcancel", "warning", 2);
return r == 1;      // 字节码：iconst_1; if_icmpne -> false
```

注意标题里的 `"` `'` 被替换成 `”` `’`——说明作者知道 AppleScript/命令行转义问题，
但漏掉了**按钮名的本地化**。

### 2.3 复现：同一台 mac 上 tinyfd 就返回 0

用游戏自带的 jar + JRE 直接调用同一个 API：

```console
$ java -Djava.awt.headless=true -cp classes:projectzomboid.jar T
calling tinyfd_messageBox ...
tinyfd_messageBox returned = 0
```

即：**返回 0，而不是 1**，所以 `submitUpdate()` 必然 false。这与 Steam 客户端日志完全吻合：
`~/Library/Application Support/Steam/logs/workshop_log.txt` 里只有创建、没有更新：

```
[2026-10-02 23:55:39] [AppID 108600] Create new workshop item of type Community for AppID 108600 : 3811968819 (OK)
```

### 2.4 tinyfd 到底执行了什么（抓到真实 argv）

放一个假的 `osascript` 到 PATH 前面记录参数，再跑上面那个测试，抓到 tinyfd 实际拼出的脚本：

```
-e 'tell application "System Events"' -e 'Activate' -e 'try'
-e 'set {vButton} to {button returned} of ( display dialog "Please confirm ... " with title "WARNING: Steam Workshop upload requested!" with icon caution )'
-e 'if vButton is "Yes" then' -e 'return 1'
-e 'else if vButton is "OK" then' -e 'return 1'
-e 'else if vButton is "No" then' -e 'return 2'
-e 'else' -e 'return 0' -e 'end if'
-e 'on error number -128' -e '0' -e 'end try'
-e 'end tell'
```

用**真的** `/usr/bin/osascript` 跑同一段（限时 15s）：

```console
exit = 0
stdout = '0\n'          # 注意：不是 1
stderr = ''
```

再单独探针"默认按钮叫什么"（`giving up after 4`）：

```console
$ osascript -e 'tell application "System Events"' -e 'set r to (display dialog "probe" with title "probe" with icon caution giving up after 4)' -e 'return r' -e 'end tell'
button returned:好, gave up:false
```

```console
$ defaults read -g AppleLanguages
( "zh-Hans-CN" )
```

**结论坐实**：对话框只有一个按钮，且标题被系统本地化成"好"；
AppleScript 里比较的却是 `"OK"`，三个分支都不中，落到 `else` → `return 0` → tinyfd 返回 0。

（英文系统上这个按钮恰好就是字面量 `OK`，所以同样的代码能上传成功——这就是"看人下菜碟"式的随机性来源。
`display dialog` 未显式指定 `buttons` 时按钮名由系统语言决定（本机实测中文=`好`；英文系统恰好就是 `OK`，所以英文机器上一切正常））

## 3. 为什么 Windows 正常、Linux 也坏

| 平台 | tinyfd 实现 | 失败点 |
| --- | --- | --- |
| Windows | `MessageBoxA(..., MB_OKCANCEL)` | 返回 `IDOK=1`/`IDCANCEL=2`，与语言无关 → 正常 |
| macOS | `osascript` + AppleScript | 按钮名本地化后与英文字面量不匹配 → 返回 0 |
| Linux | 依次尝试 `zenity`/`kdialog`/`yad`/`gxmessage`/`Xdialog`，最后退到 `/dev/tty` 提示 | Steam 启动的游戏没有可用对话框工具/终端时返回 -1（并把消息打到 stderr）→ 同样 `!= 1` |

两者都会让 `submitUpdate()` 返回 false，从而出现**完全一样**的报错，
所以这个帖子里 Linux 和 macOS 用户看到的是同一个 bug 的两种触发方式。

## 4. 修复

那份原生确认框在 macOS / Linux 上本来就只有一个"确定"按钮（没有取消），
它的返回值不该成为上传的前置条件。因此把 `submitUpdate()` 里这个判断去掉即可：

```diff
  9: istore_1
- 10: iload_1
- 11: ifeq 28
+ 10: nop
+ 11: nop
+ 12: nop
+ 13: nop
 14: getstatic SteamWorkshop.instance
 18: invokevirtual SubmitWorkshopItem
```

仓库内脚本：`bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py`（纯标准库，macOS/Linux 通用）

```bash
python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py            # 自动找游戏、备份并修复
python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --dry-run  # 只看不改
python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --verify   # 查状态
python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --restore  # 还原
python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --game-dir "/path/to/Project Zomboid.app/Contents/Java"
```

实现要点（都是为了保证"只动这一个方法、且不弄坏这个 jar"）：

* 用正则 `3c 1b 99 .. .. b2 .. .. 2a b6 .. .. 99 00 07 04 a7 00 04 03 ac` 精确定位，
  **必须且只能命中一次**，否则拒绝修改（游戏更新后字节码变了也不会改坏东西）。
* **整包重写** jar 来替换这一个成员：除目标成员外，26140 个条目的名称/时间/压缩方式/属性/顺序全部原样保留
  （实测：与备份逐条目比对，只有目标成员的 CRC 与内容不同）。重写后的 CRC、压缩后长度、
  data descriptor 全部自洽 ⇒ `ZipFile`、`ZipInputStream`、`unzip` 都能正常读。
* 先写临时文件并自检（`testzip()` 全量 CRC + 目标成员内容），再**覆写原路径**（inode 不变，权限与
  `com.apple.provenance` 之类的 xattr 都保留）。
* 备份只在"原版"状态下创建，并把 `original_member_sha256` 记到 `projectzomboid.jar.pzfix.json`；
  `--restore` 会先核对这个哈希，不一致就拒绝还原（可 `--force`）。
* 幂等：已打补丁时直接报 `already patched`；`--dry-run` 对 `--restore` 同样生效。

> **为什么不"就地改 4 个字节"：** 第一版实现是把新 deflate 流写回原位置、不足处补 `\x00`
> （保持压缩后长度不变，从而全 jar 偏移量都不用动；`ZipFile`/`unzip -t` 确实都能过）。
> 但 `java.util.zip.ZipInputStream` 是**按流位置**找 data descriptor 的，尾部补零会让它算出
> `invalid entry size (expected ... but got 20721 bytes)`；而且当成员带 data descriptor（flag bit 3）时，
> 那张 descriptor 里的 CRC 也需要同步改写。游戏本身走的是 `URLClassLoader → ZipFile` 随机访问，
> 不受影响，但这种"能用但结构不自洽"的 jar 是个定时炸弹，所以改成整包重写。
> 代价只有几秒（本机 65 MB / 26140 条目约 5 s）。

### 本次验证记录

```console
$ python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py
[info] original sha256 : 9d1d15bedf811f0593e75d3b3e5263d4
[info] patched  sha256 : 7b542913273fa35d4ca04109bd64fb9a
[info] rebuilt jar     : entries=26140, member csize=10030 usize=20721
[ok]   patched + verified
```

补丁后 `javap -p -c` 的 `submitUpdate()`（确认框仍然会弹，但不再拦截）：

```
  9: istore_1
 10: nop
 11: nop
 12: nop
 13: nop
 14: getstatic     #168  // SteamWorkshop.instance
 18: invokevirtual #187  // SteamWorkshop.SubmitWorkshopItem
 21: ifeq  28
 24: iconst_1
 25: goto  29
 28: iconst_0
 29: ireturn
```

用游戏自带 JRE 25 从**真实 jar** 里加载该类，验证器无报错，且各种读法都正常：

```console
# JarFile（随机访问，游戏/URLClassLoader 走的就是这条）
jar read OK, len=20721 crc=1735906023
class loaded + verified: zombie.core.znet.SteamWorkshopItem

# ZipInputStream（流式顺序读，最挑剔：会检查 data descriptor 与长度是否自洽）
member via ZipInputStream: size=20721 crc=6777d2e7 read=20721
ZipInputStream OK: entries=26140 bytes=142152148 memberFound=true

# 本地头 / 中央目录 / CRC 一致 + 其他条目原样
flags=0x0000 local_crc=0x6777d2e7 cd_crc=0x6777d2e7 csize=10030/10030 usize=20721/20721
entries: 26140 / 26140   same order/names: True
content-differing members: ['zombie/core/znet/SteamWorkshopItem.class']

$ unzip -t projectzomboid.jar | tail -1
No errors detected in compressed data of projectzomboid.jar
$ xattr -l projectzomboid.jar
com.apple.provenance:            # 覆写原路径，xattr/权限保留
```

`ZipInputStream` 那一步会顺带发现"就地补零"这类结构不自洽问题，值得单独跑一次：

```java
try (ZipInputStream zis = new ZipInputStream(new BufferedInputStream(new FileInputStream(jar)))) {
    ZipEntry e; byte[] buf = new byte[1 << 16];
    while ((e = zis.getNextEntry()) != null) { while (zis.read(buf) > 0) {} }   // 会校验长度/CRC/descriptor
}
```

> 游戏更新或 Steam"验证文件完整性"会覆盖 `projectzomboid.jar`，**重跑一次脚本**即可。

### 4.1 排除其它嫌疑：上传前的每一步在 macOS 上都是成功的

"确认框返回 0"只是推理，还要排除"即使过了这一步，`StartItemUpdate` / `SetItemContent` 在 macOS 上照样失败"。
于是写了一个**停在提交之前**的自检程序：用游戏自带 jar + JRE 25 初始化 Steam（`SteamAPI_Init` 加载
`steamclient.dylib`，AppID 108600），然后把 `SubmitWorkshopItem()` 里的调用**逐个**执行，唯独不调 `n_SubmitItemUpdate`
（所以不会真的上传任何东西）。已收录为 `bin2_workshop_upload_fix/tools/pz_workshop_probe/`：

```bash
bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh            # 自动找游戏、自动挑 ~/Zomboid/Workshop 下最新的待上传目录
bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/MyMod
```

（它同时可以用来校验 `workshop.txt`：走的就是游戏自己的 `readWorkshopTxt()`，会打印
id / title / visibility / tags / description 长度 以及 `Contents`、`preview.png` 是否存在。）

```java
System.load(javaDir + "/libZNetJNI.dylib");
zombie.ZomboidFileSystem.instance.init();
zombie.core.znet.SteamUtils.init();        // SteamAPI_Init
zombie.core.znet.SteamWorkshop.init();     // ZNetWorkshop 实例
var item = new zombie.core.znet.SteamWorkshopItem(workshopFolder);
item.readWorkshopTxt();                    // 读 id/title/description/visibility/tags
long id = zombie.core.znet.SteamUtils.convertStringToSteamID(item.getID());
// 下面每个 n_* 都是 SteamWorkshop 的 private native，用反射调用
n_StartItemUpdate(id); n_SetItemTitle(item.getTitle()); n_SetItemDescription(item.getSubmitDescription());
n_SetItemVisibility(item.getVisibilityInteger()); n_SetItemTags(item.getSubmitTags());
n_SetItemContent(item.getContentFolder()); n_SetItemPreview(item.getPreviewImage());
// 到此为止，不调 n_SubmitItemUpdate
```

实测输出（原版代码的那段调用链，全部 `true`）：

```
[S_API] SteamAPI_Init(): Loaded '.../Steam.AppBundle/Steam/Contents/MacOS/steamclient.dylib' OK.
Setting breakpad minidump AppID = 108600
steamMode after SteamUtils.init=true
readWorkshopTxt=true
id=3811968819 title=嵌套容器物品拿取 (Nested Containers - Take Items) vis=0
contentFolder=/Users/liubinbin/Zomboid/Workshop/bin2_nested_containers_take/Contents
previewImage=.../preview.png exists=true
StartItemUpdate       = true
SetItemTitle          = true
SetItemDescription    = true
SetItemVisibility     = true
SetItemTags           = true
SetItemContent        = true
SetItemPreview        = true
STOP before SubmitItemUpdate (no upload performed)
```

结论：`StartItemUpdate` 拿到的句柄有效、`SetItemContent`/`SetItemPreview` 都接受这些绝对路径，
**唯一返回 false 的就是那个原生确认框**。去掉它之后 `SubmitWorkshopItem()` 会返回 true，上传随即开始。
（剩下仅有 `n_SubmitItemUpdate` 本身未实测，它与 Windows 走的是同一个 SDK 调用。）

### 4.2 用 ZombieBuddy 修复（装了 ZB 的话推荐这条）

ZombieBuddy（[steam 3619862853](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)，作者 Zed）
是 PZ 社区在用的运行时字节码补丁框架（ByteBuddy，注解即补丁），本仓库新增了对应的补丁模组：

```
bin2_workshop_upload_fix/
├── Contents/mods/ZBWorkshopUploadFix/                  # 模组本体（已软链到 ~/Zomboid/mods）
│   ├── common/.gitkeep
│   └── 42.21/
│       ├── mod.info                                    # poster=poster.png + require=\ZombieBuddy
│       ├── poster.png                                  # 模组列表海报 512x512
│       ├── src/com/lotosbin/zbworkshopfix/             # 源码：@Patch.OnExit + forceSubmit()
│       └── media/java/client/ZBWorkshopUploadFix.jar   # 产物（Java 17 字节码）
├── build.sh                                            # 编译（自动挑 JDK >= 25，--release 17）
├── test/                                               # 离线自测（不启动游戏、不上传）
│   ├── zbworkshopfix/test/…                            # TestAgent / DummyTarget / RunAdviceTest
│   └── run_offline_test.sh
├── tools/
│   ├── pz_fix_workshop_upload.py                       # 等价的"直接改 projectzomboid.jar"方案
│   ├── pz_workshop_probe/                              # 上传前链路自检（起 Steam、不提交）
│   └── make_images.py                                  # 重新生成 preview.png / poster.png
├── preview.png                                         # 工坊物品预览图 256x256（游戏只收 256/512 的正方形）
├── workshop.txt                                        # 工坊发布信息（visibility=public）
├── changelog.txt
├── docs/
│   ├── pz-steam-workshop-upload-macos-linux-fix.md     # 本文
│   └── pz-workshop-bug-report-en.md                    # 英文 bug 报告草稿
└── README.md
```

补丁本体只有一件事：`@Patch.OnExit` 挂在 `submitUpdate()` 上，返回 false 且不是 Windows 时补一次
`SteamWorkshop.instance.SubmitWorkshopItem(item)`；**不跳过原方法**（确认框照旧弹），Windows/英文系统行为不变。

**为什么不去补 `TinyFileDialogs.tinyfd_messageBox`（更"对症"的那一层）**：那是 ZombieBuddy 自己审批
Java mod 用的同一个方法（`TinyfdModApprovalFrontend`），全局改成返回 1 会让所有 Java mod 静默通过审批，
是安全问题。ZB 自己的审批框用的是 `"yesno"` 类型，tinyfd 在 macOS 上会显式生成
`buttons {"No", "Yes"}`，按钮名不再被本地化 —— 这也正是"如果 TIS 想保留确认框、应该怎么改"的答案。

离线自测（`bin2_workshop_upload_fix/test/run_offline_test.sh`，不启动游戏）用 ZombieBuddy 自带的 `PatchTransformer` + 一个
假 `submitUpdate()` 目标，在真实 JVM 里证明了：`@Patch.*` 别名能被翻译成 `Advice.*` 并被
ByteBuddy 接受、原方法未被跳过、补丁代码确实执行、`@Return(readOnly=false) boolean` 能改写返回值。

> 踩坑记录：ByteBuddy 的 Advice 是**内联**进被补丁方法的，访问权限按被补丁的类判定 ——
> 所以 `WorkshopUploadFix` 的类和方法必须是 `public`，包私有会在运行时 `IllegalAccessError`。

### 不想改游戏文件时的替代方案（Linux）

Linux 上让 tinyfd 找到可用对话框工具，也能绕开（因为 zenity/kdialog 分支看退出码，与语言无关）：

```bash
sudo dnf install zenity      # Bazzite / Fedora 系
sudo apt install zenity      # Debian / Ubuntu 系
```

macOS 上没有等价的一行方案：tinyfd 固定走 `osascript`，而"好/OK"由系统语言决定，
改语言或改 jar 二选一（本文选择改 jar）。

## 5. 给开发商（TIS）的修复建议

这个 bug 的价值在于它复现条件很窄但影响面很广：**非英文系统的 macOS / 缺对话框工具的 Linux**。
三处建议：

1. `SteamWorkshopItem.submitUpdate()` 不要用原生确认框的返回值做前置条件；
   要么直接 `SubmitWorkshopItem()`，要么在确认框不可用时（返回 0/-1）也继续。
2. 若保留确认框，请显式指定按钮，例如给 tinyfd 传 `buttons`（macOS 侧即 `display dialog ... buttons {"OK"}`），
   不要让按钮名依赖系统语言。
3. 顺带把 Page7 的日志写进 `Zomboid/WorkshopLog.txt`（源码里那条 `-- TODO: write to WorkshopLog.txt as well`
   至今还在），本次定位最大的障碍就是"失败原因只出现在 UI 文本框里、没有落盘"。

报 bug 时可直接附上本文 2.3 / 2.4 两段可复现证据。

## 6. 参考资料

* 问题反馈帖（Linux + macOS 同一症状，含 `workshop_log.txt` 只有 Create 没有 Update 的关键线索）：
  <https://steamcommunity.com/app/108600/discussions/1/582806854239939623/>
* 官方论坛"B42.16.3 Updating your workshop mod as a creator"（上传向导的使用/FAQ）：
  <https://theindiestone.com/forums/topic/94163-b42163-updating-your-workshop-mod-as-a-creator/>
* LWJGL 3 的 tinyfd 模块（PZ 使用的绑定）：<https://github.com/LWJGL/lwjgl3/tree/master/modules/lwjgl/tinyfd>
* tinyfiledialogs 上游项目（macOS 分支即 `osascript` + `button returned` 比较那一段）：
  <https://sourceforge.net/projects/tinyfiledialogs/>
* Steamworks `ISteamUGC::SubmitItemUpdate` 语义（`SubmitItemUpdateResult_t`，即被跳过的那一步）：
  <https://partner.steamgames.com/doc/api/ISteamUGC>
