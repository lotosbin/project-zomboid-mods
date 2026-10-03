# bin2_workshop_upload_fix / ZBWorkshopUploadFix

修复 Project Zomboid 在 **macOS / Linux** 上上传创意工坊报
`error requesting Steam to update the item` 的问题。三种东西放在一起：**模组本体**（ZombieBuddy 运行时补丁，
推荐）、**等价的"改 jar"脚本**、**验证工具**。

背景与分析见 [`docs/pz-steam-workshop-upload-macos-linux-fix.md`](docs/pz-steam-workshop-upload-macos-linux-fix.md)。

---

## 问题一句话

`zombie.core.znet.SteamWorkshopItem.submitUpdate()` 要求 LWJGL tinyfd 的原生确认框返回 `1` 才提交：

```java
boolean ok = RenderThread.invokeQueryOnRenderContext(this::confirmBox);
return ok && SteamWorkshop.instance.SubmitWorkshopItem(this);
```

tinyfd 在 macOS 上用 AppleScript 实现，脚本把 `button returned` 和写死的英文 `"Yes"/"OK"/"No"` 比较；
非英文系统的默认按钮是**本地化**的（中文系统是"好"），匹配失败 → 返回 `0` → `submitUpdate()` 直接 false，
`SubmitItemUpdate` 从未被调用（Steam 的 `workshop_log.txt` 里只剩创建记录、物品永远 0 B）。
Linux 上 tinyfd 找不到 zenity/kdialog 时返回 `-1`，同样 `!= 1`。
Windows 走 Win32 `MessageBoxA`（`IDOK=1`，与语言无关）所以不受影响。

---

## 目录结构

```
bin2_workshop_upload_fix/                              ← 本工程；已软链为 ~/Zomboid/Workshop/bin2_workshop_upload_fix（上传向导可见）
├── Contents/mods/ZBWorkshopUploadFix/                 ← 模组本体；已软链到 ~/Zomboid/mods/ZBWorkshopUploadFix（本地加载）
│   ├── common/.gitkeep
│   └── 42.21/
│       ├── mod.info                                   ← poster=poster.png + require=\ZombieBuddy
│       ├── poster.png                                 ← 模组列表海报 512x512
│       ├── src/com/lotosbin/zbworkshopfix/            ← @Patch.OnExit + forceSubmit()
│       └── media/java/client/ZBWorkshopUploadFix.jar  ← 构建产物（Java 17 字节码）
├── build.sh                                           ← 编译打包（自动挑 JDK >= 25）
├── test/                                              ← 离线自测：不启动游戏、不上传
│   ├── zbworkshopfix/test/{TestAgent,DummyTarget,ForceTrueAdvice,RunAdviceTest}.java
│   └── run_offline_test.sh
├── tools/
│   ├── pz_fix_workshop_upload.py                      ← 等价的"直接改 projectzomboid.jar"方案
│   ├── pz_workshop_probe/                             ← 上传前链路自检（初始化 Steam、不提交）
│   └── make_images.py                                 ← 用 Pillow 重新生成下面两张预览图
├── preview.png                                        ← 工坊物品预览图 256x256（游戏只收 256/512 的正方形）
├── docs/
│   ├── pz-steam-workshop-upload-macos-linux-fix.md    ← 完整证据链 / 根因 / 三种修法
│   └── pz-workshop-bug-report-en.md                   ← 可直接贴给 TIS 的英文 bug 报告
├── workshop.txt                                       ← 工坊发布信息（visibility=public）
├── changelog.txt
└── README.md
```

---

## 用法

### 1. ZombieBuddy 补丁模组（推荐）

```bash
./build.sh                 # 编译 → Contents/mods/ZBWorkshopUploadFix/42.21/media/java/client/*.jar
./test/run_offline_test.sh # 离线自测（不启动游戏）
```

本机已把它链接进本地 mod 目录：

```bash
ln -sfn "$(pwd)" ~/Zomboid/mods/ZBWorkshopUploadFix
```

然后在游戏里 **Mods → 启用 `ZB Workshop Upload Fix (macOS / Linux)`**；
首次启动 ZombieBuddy 会弹一次 "Allow Java mod to load?"（选 Yes；重编译后 JAR 哈希变化会再问一次）。

补丁做了什么：`@Patch.OnExit` 挂在 `submitUpdate()` 上，返回 `true`（英文系统 / Windows 正常确认）
时什么都不做；返回 `false` 且非 Windows 时补一次
`SteamWorkshop.instance.SubmitWorkshopItem(item)`。**不跳过原方法**（确认框照旧弹），
也**没有**去改 `TinyFileDialogs.tinyfd_messageBox` —— 那是 ZombieBuddy 自己审批 Java mod 用的同一个方法，
全局改成返回 1 会让所有 Java mod 静默过审。

生效标志（`~/Zomboid/console.txt`）：

```
[ZB] patching zombie.core.znet.SteamWorkshopItem.submitUpdate with 1 advice(s)
[ZBWorkshopUploadFix] confirm box did not report OK (localized button / no tinyfd backend) -> SubmitWorkshopItem(item id=...) = true
```

### 2. 等价的"改 jar"脚本（不装 ZombieBuddy 时用）

```bash
python3 tools/pz_fix_workshop_upload.py            # 自动找游戏、备份并修复
python3 tools/pz_fix_workshop_upload.py --dry-run  # 只看不改
python3 tools/pz_fix_workshop_upload.py --verify   # 0=已修 1=未修 2=未知
python3 tools/pz_fix_workshop_upload.py --restore  # 还原备份
```

做法是把 `SteamWorkshopItem.class` 里 `submitUpdate()` 的 `iload_1; ifeq` 抹成 4 个 `nop`，
**整包重写** jar（其余 26140 个条目原样保留，CRC/长度/data descriptor 自洽，inode/权限/xattr 保留）。

两个方案可以共存（不会重复提交：jar 补丁让 `submitUpdate()` 返回 true，ZB 补丁就什么都不做）。
想只保留 ZB 方案、把游戏文件还原：`python3 tools/pz_fix_workshop_upload.py --restore`。

### 3. 验证工具

```bash
tools/pz_workshop_probe/run.sh          # 自动挑 ~/Zomboid/Workshop 下最新的待上传目录
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/MyMod
```

两个用途：

* **校验 `workshop.txt`**：它用游戏自己的 `SteamWorkshopItem.readWorkshopTxt()` 解析，打印
  id / title / visibility / tags / description 长度，以及 `Contents`、`preview.png` 是否存在
  （改完工坊文案后跑一下，比上传失败再回查快得多）；
* **区分失败原因**：起 Steam 后逐个调用 `StartItemUpdate/SetItemTitle/SetItemDescription/
  SetItemVisibility/SetItemTags/SetItemContent/SetItemPreview`，唯独不调 `SubmitItemUpdate`
  （所以不会真的上传）。本机实测这些全部 `true` —— 说明失败的不是 Steam 侧，而是那个确认框。

---

## 离线自测覆盖了什么

`test/run_offline_test.sh` 用一个假的 `submitUpdate()` 目标 + ZombieBuddy 自带的 `PatchTransformer`，
在真实 JVM 里验证：

* `@Patch.*` 别名注解能被翻译成 ByteBuddy 的 `@Advice.*` 并被接受（说明补丁类写对了）；
* **没有跳过原方法**（确认框仍会弹）；
* `@Return(readOnly = false) boolean` 确实能改写返回值（补丁生效的机制）；
* 补丁代码真的会执行（日志出现），异常被兜住不会抛给游戏。

```
[ok]   PatchTransformer 返回补丁类
[ok]   补丁方法上出现了 ByteBuddy 的 @OnMethodExit
[ok]   原方法没有被跳过（确认框仍会弹）
[ok]   补丁代码确实执行了（打出了 ZBWorkshopUploadFix 日志）
[ok]   对照组：返回值被 @Return(readOnly=false) 改写为 true
== ALL CHECKS PASSED ==
```

---

## 两个真实的坑（都已被复核/自测抓到）

- **ByteBuddy 的 Advice 是内联的**：访问权限按**被补丁的类**判定，所以 `WorkshopUploadFix`
  的类和方法必须 `public`，包私有会在游戏里 `IllegalAccessError`。
- **别用"就地补零"的方式改 jar**：尾部补 `\x00` 能让 `ZipFile`/`unzip` 通过，却会让
  `java.util.zip.ZipInputStream` 报 `invalid entry size`（它按流位置找 data descriptor）；
  改成整包重写后 `ZipInputStream` 全量读 142 MB 无异常。

## 依赖

* ZombieBuddy ≥ 2.0.0（本机 2.3.2，workshop `3619862853`），已作为 javaagent 生效
* JDK ≥ 25（B42.21 的 `projectzomboid.jar` 是 Java 25 字节码；构建产物本身是 Java 17 字节码）
* PZ Build 42.21（版本目录 `42.21/`）

## 发布到工坊

[`workshop.txt`](workshop.txt) 已经写好（`version=1`、标题、多行 `description=`、`tags=Build 42;QoL;Misc`、
`visibility=public`）。上传时的布局与 `bin2_viewpoint/` 一致：

```
bin2_workshop_upload_fix/                     ← 工坊物品目录（Steam 上传时选这一层）
├── workshop.txt                              ✅ visibility=public
├── preview.png                               ✅ 256x256 工坊物品预览
├── changelog.txt                             ✅
└── Contents/mods/ZBWorkshopUploadFix/
    └── 42.21/
        ├── poster.png                        ✅ 512x512 模组列表海报
        ├── mod.info                          ✅ poster=poster.png
        └── media/java/client/*.jar           ✅
```

预览图是可复现的：`python3 tools/make_images.py`（Pillow 绘制，深色 + 网格 + 终端日志，
风格对齐 `bin2_viewpoint`）；`--check` 只打印现有尺寸。

**`preview.png` 的尺寸是有硬性要求的**（来自游戏 `SteamWorkshopItem.validatePreviewImage(Path)` 的字节码）：

| 规则 | 不满足时的错误码 |
|---|---|
| 存在 / 可读 / 不是目录 | `PreviewNotFound` |
| 文件 ≤ 1024000 字节 | `PreviewFileSize` |
| **正方形，且边长只能是 256 或 512** | `PreviewDimensions` |
| 能被 `PNGDecoder` 解析（即必须是 PNG） | `PreviewFormat` |

所以预览图用 256x256（试过 1024x1024，游戏直接报 `PreviewDimensions`）。
探针会顺带调用这个校验器打印 `validatePreviewImage = OK`。
（模组海报 `poster.png` 不受这条约束，沿用 512x512。）

发布步骤：

```bash
# 本机已创建（与其它模组一致）：
ln -sfn "$(pwd)" ~/Zomboid/Workshop/bin2_workshop_upload_fix   # 让上传向导能看到这个待上传目录
python3 tools/pz_fix_workshop_upload.py --verify               # 确认补丁在位（或启用 ZB 模组）
```

软链对上传链路是安全的，已用游戏代码验证过两点：`SteamWorkshopItem` 构造函数的
`ZomboidFileSystem.validatePrefix()` 接受这个符号链接路径；`getStageFolders()` 的过滤器是
`Files.isDirectory(path)`（没有 `NOFOLLOW_LINKS`），所以软链目录会出现在上传向导的列表里。

游戏内 Workshop 上传向导选 `bin2_workshop_upload_fix/` 这一层 → 上传成功后把向导写回的 `id=` 提交进仓库。
（注：第一次上传正是这个 bug 会拦住的操作；装好本补丁后就能在 macOS 上完成。）
