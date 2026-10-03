---
name: pz-engine-deepdive
description: Locate, prove, and fix Project Zomboid engine-level (Java) defects in this repo, and deliver the result as a mod or a Workshop item. Use it when a symptom is platform-specific (macOS/Linux works differently from Windows), when Lua alone cannot explain a failure, when you must read or patch projectzomboid.jar bytecode, when writing a ZombieBuddy @Patch mod, or when packaging/validating a Workshop item (mod.info, workshop.txt, poster.png, preview.png, staged folder, upload wizard).
whenToUse: The symptom points below the Lua layer (something "just returns false", a native dialog, a Steam/Workshop operation), or the task is "make a ZombieBuddy Java patch", or the task is "publish/validate this Workshop item".
---

# Project Zomboid：引擎层定位 → 修补 → 工坊交付

这份 skill 记录的是**在本机真实跑通过**的一套流程，不是通用建议。每一条结论都附带"怎么自己证实"。

## 0. 三条铁律

1. **先证后改**：结论必须来自游戏自己的代码/返回值（`javap` 字节码、直接调用 API 的返回值、抓到真实 argv），
   不接受"看起来像是"。
2. **"只在一个平台坏" 先找那一个跨平台分支**：同一段代码里凡是调原生、外部程序、路径分隔符、
   系统语言的地方，都是第一嫌疑；不要先去怀疑更底层的 SDK。
3. **能不动游戏文件就不动**：优先 ZombieBuddy 运行时补丁；必须改 jar 时，整包重写 + 备份 + 可还原 +
   "特征串唯一命中否则拒绝"。

## 1. 本机环境事实（先核对，别猜）

| 事实 | 值 / 命令 |
| --- | --- |
| 游戏 Java 目录（macOS） | `~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java` |
| Linux 布局 | `<steam>/steamapps/common/ProjectZomboid/projectzomboid.jar`（jar 直接在这一层） |
| `projectzomboid.jar` 字节码版本 | **Java 25（class 主版本 69）** ⇒ `javac`/`javap` 必须 ≥ 25；JDK 17 会报 `class file has wrong version 69.0` |
| 可用的 JDK 25 | `~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/{javac,javap,java}` |
| 游戏自带 JRE（跑游戏 class 最稳） | `.../Contents/PlugIns/jre-aarch64/Contents/Home/bin/java` |
| 游戏日志 | `~/Zomboid/console.txt`（`[ZB]` 前缀是 ZombieBuddy） |
| Steam 客户端工坊日志（定位上传问题的关键） | macOS `~/Library/Application Support/Steam/logs/workshop_log.txt`；Linux `~/.steam/steam/logs/workshop_log.txt` |
| ZombieBuddy | agent: `Contents/Java/ZombieBuddy.jar`（2.3.2）；mod: workshop `3619862853`；文档 `<mod>/doc/ModdingGuide.md`；审批状态 `~/.zombie_buddy/mod_approvals.json` |
| 本地 mod 目录 | `~/Zomboid/mods/<ModId>` → 惯例是**软链到本仓库** |
| 工坊待上传目录 | `~/Zomboid/Workshop/<name>`（同样惯例是软链到本仓库） |

反编译单个类（不整包解压）：

```bash
cd "$JAVA_DIR" && unzip -o -q projectzomboid.jar 'zombie/core/znet/*' -d /tmp/pz && \
  javap -p -c          /tmp/pz/zombie/core/znet/SteamWorkshopItem.class   # 看调用链
  javap -p -c -v -constants /tmp/pz/zombie/core/znet/SteamWorkshopItem.class  # 看常量池/注解/字符串
```

## 2. 从症状到证据：固定六步

1. **错误字符串先找出处**：`grep -rn "<报错原文>" media/` 与 class 常量池。
   落点是 Java 还是 Lua 决定了后面所有动作。若在 Lua，看它 `if` 的条件来自哪个 Java 调用。
2. **`javap -p -c` 读调用链**，把"某方法返回 false"变成"哪一个分支返回 false"。
   `&&` 短路是最常见的坑：`return a && b` 里 `a==false` 时 `b` 根本不会被调用。
3. **直接调那个 API 拿返回值**：写 20 行 Java，用**游戏自带 jar + JRE**：
   ```bash
   perl -e 'alarm 25; exec @ARGV' "$JRE/bin/java" -Djava.awt.headless=true \
        -cp classes:"$JAVA_DIR/projectzomboid.jar" Probe
   ```
   一次调用胜过一小时推理。
4. **抓真实 argv（原生程序问题的杀手锏）**：在 `PATH` 前面放一个假的 `osascript`/`zenity`，
   把 `"$@"` 落盘，就能看到第三方库真正拼出来的命令；再用真程序重放同一串，观察 stdout/exit。
5. **对照实验**：只改一个变量（本地化标签 / 有没有 `buttons` / 平台），证明因果而不是相关。
6. **子代理独立复核**：把"证据 + 结论 + 待复核点"交给一个 subagent，明确要求它**证伪**。
   本次它抓到两个真缺陷（jar 补零破坏 `ZipInputStream`、data descriptor 的 CRC 未同步），值得这一步。

## 3. 平台差异第一嫌疑：LWJGL tinyfd 原生弹窗

`org.lwjgl.util.tinyfd.TinyFileDialogs` 是 LWJGL 打包的第三方弹窗库（内含 tinyfiledialogs），
三个平台三套实现，返回值语义完全不同：

| 平台 | tinyfd 实际做什么 | "确定"对应 | 结论 |
| --- | --- | --- | --- |
| Windows | `MessageBoxA(..., MB_OKCANCEL)` | `IDOK = 1`（数字常量） | 与语言无关，永远对 |
| macOS | `osascript` + AppleScript：`set {vButton} to {button returned} of ( display dialog … )`，再拿 `vButton` 和写死的 `"Yes"/"OK"/"No"` **比字符串** | 按钮标题被**系统语言本地化**（中文=`好`）⇒ 匹配失败 `return 0` | 非英文系统必挂 |
| Linux | 依次找 `zenity` / `kdialog` / `yad` / `gxmessage` / `Xdialog`，最后退到 `/dev/tty` | 找不到任何工具 ⇒ `-1` | 精简发行版/无终端必挂 |

- **信号**："英文机器上好好的" / "以前能传现在不能" ⇒ 高度怀疑这一类。
- 复现（本次实测）：直接调 `tinyfd_messageBox(title,msg,"okcancel","warning",2)` 返回的不是 1；
  `osascript … display dialog "probe" giving up after 4` 打印 `button returned:好`。
- **不要全局把 `tinyfd_messageBox` 改成返回 1**：ZombieBuddy 自己审批 Java mod 用的就是它
  （`TinyfdModApprovalFrontend`），全局改等于让所有 Java mod 静默过审。
  ZB 自己的弹窗用 `"yesno"` 类型 —— tinyfd 在 macOS 上会显式生成 `buttons {"No","Yes"}`，
  按钮名不再被本地化。这就是给 TIS 的正确改法示范。

## 4. 落地方式 A：ZombieBuddy 运行时补丁（首选）

仓库约定布局（照 `bin2_viewpoint/`）：

```
bin2_<name>/
├── Contents/mods/<ModId>/<ver>/{mod.info, poster.png, src/…, media/java/client/<ModId>.jar}
├── build.sh              # 自动挑 JDK ≥ 25，--release 17 出产物
├── test/run_offline_test.sh
├── tools/                # 本项目自己的工具 + 生成脚本
├── docs/                 # 证据链/报告
├── workshop.txt  changelog.txt  preview.png
└── README.md
```

`mod.info` 关键字段：`id` / `require=\ZombieBuddy` / `ZBVersionMin` / `poster=poster.png` /
`javaJarFile=media/java/client/<X>.jar`（相对**版本目录**）/ `javaPkgName=<包名>`。

注解语义（`me.zed_0xff.zombie_buddy.Patch`，是 ByteBuddy `Advice.*` 的别名，由 `PatchTransformer` 转换）：

| 注解 | 用途 | 注意 |
| --- | --- | --- |
| `@Patch(className, methodName)` | 声明目标 | `strictMatch` 控制"无参 advice 是否只匹配无参方法"；`warmUp=true` 用于内部类 |
| `@Patch.OnEnter` | 方法进入 | `skipOn=true` 时可跳过原方法，但**跳过时返回值是默认值**；`boolean` 无返回值不要乱返回 |
| `@Patch.OnExit` | 方法退出 | 配合 `@Patch.Return(readOnly=false)` 才能改写返回值 |
| `@Patch.This` / `@Patch.Argument(n)` | 取 this / 参数 | 类型用 `Object` + 自己强转更宽容 |
| `isAdvice=false` | MethodDelegation（整体替换） | 同一方法**全局只能有一个**；已加载的类上不靠谱 |

**必须记住**：ByteBuddy 的 Advice 是**内联**进被补丁方法的，访问权限按**被补丁的类**判定 ⇒
辅助类与辅助方法统统要 `public`，包私有会在游戏里 `IllegalAccessError`。

写补丁的稳妥姿势（本次验证有效）：不要 `skipOn` 跳原逻辑，而是 `@Patch.OnExit` 里
"结果不合意就自己补做一次"，这样英文系统/Windows 的行为一个字都不变：

```java
@Patch.OnExit
public static void exit(@Patch.This Object self, @Patch.Return(readOnly = false) boolean result) {
    if (result || isWindows()) return;                 // 正常路径零影响
    result = Helper.forceDoIt(self);                   // Helper 必须是 public
}
```

**离线自测**（不启动游戏、不上传）：用一个 5 行的 `Premain` 小 agent 拿到 `Instrumentation`
（清单必须写 `Can-Redefine-Classes` / `Can-Retransform-Classes`），再用框架自带的
`PatchTransformer.transformPatchClass(...)`（包私有，用反射调）把 `@Patch.*` 翻译成 `Advice.*`，
挂到一个**假目标**上调用，断言：翻译成功 / 原方法未被跳过 / advice 真的执行 / `@Return` 能改写返回值。
参考实现：`bin2_workshop_upload_fix/test/`。

## 5. 落地方式 B：直接改 `projectzomboid.jar`（没有 ZB 时）

- **整包重写**替换成员，不要"就地改几个字节再补零对齐压缩长度"：
  尾部补 `\x00` 能让 `ZipFile`/`unzip -t` 通过，却会让 `java.util.zip.ZipInputStream`
  报 `invalid entry size`（它按流位置找 data descriptor）；带 data descriptor（flag bit 3）的成员
  其 descriptor 里的 CRC 也要同步改。整包重写后 CRC/长度/descriptor 全自洽，
  26000 条目约 5 秒，且逐条目内容除目标外完全一致。
- 写盘时**覆写原路径**（inode 不变 ⇒ 权限与 xattr 保留），先写临时文件并 `testzip()` 自检。
- 定位用**唯一特征串**并要求恰好命中一次，否则拒绝执行（游戏更新后安全退出）。
- 备份 + `original_member_sha256` 记录 + `--restore` 前核对哈希 + `--dry-run` 对破坏性开关同样生效。
- 参考实现：`bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py`（`--verify/--dry-run/--restore`）。

## 6. 工坊物品交付与校验

目录与字段：

- 物品根：`workshop.txt`、`preview.png`、`changelog.txt`、`Contents/mods/<ModId>/<ver>/…`
- `workshop.txt`：`version=1` + 若干行 `description=`（**一行一个 description=**）+ `tags=`（分号分隔，
  取值必须来自游戏 `media/WorkshopTags.txt`）+ `visibility=public|private`；未发布时**不写 `id=`**
  （首次上传后由向导写回）。
- `mod.info` 的 `poster=` 指向版本目录里的海报。

**`preview.png` 是硬性规则**（来自 `SteamWorkshopItem.validatePreviewImage(Path)` 字节码）：

| 规则 | 错误码 |
| --- | --- |
| 存在 / 可读 / 不是目录 | `PreviewNotFound` |
| ≤ 1024000 字节 | `PreviewFileSize` |
| **正方形，边长只能是 256 或 512** | `PreviewDimensions` |
| 能被 `zombie.core.textures.PNGDecoder` 解析（即 PNG） | `PreviewFormat` |

不要照抄别的模组的预览图尺寸（本仓库里既有 256 也有 1024，1024 会被游戏判 `PreviewDimensions`）。

软链当待上传目录是安全的，已用游戏代码证实两点：
`SteamWorkshopItem` 构造函数的 `ZomboidFileSystem.validatePrefix()` 接受符号链接路径；
`SteamWorkshop.getStageFolders()` 的过滤器是 `Files.isDirectory(path, LinkOption[0])`（跟随符号链接）。

**用游戏自己的代码校验，而不是上传失败后回查**：

- `SteamWorkshopItem.readWorkshopTxt()` → id/title/visibility(`0`=public,`2`=private)/tags/description 长度
- `SteamWorkshopItem.validatePreviewImage(Path)` → `null` 表示通过，否则是上面的错误码
- 起 Steam 后逐个调用 `n_StartItemUpdate / n_SetItemTitle / … / n_SetItemContent / n_SetItemPreview`，
  **唯独不调 `n_SubmitItemUpdate`** ⇒ 不会真的上传，却能证明"上传前的 native 链路是好的"。
  实现：`bin2_workshop_upload_fix/tools/pz_workshop_probe/`

## 7. 定位"上传/下载类"问题的额外提示

- 游戏内日志常常**不落盘**（`WorkshopSubmitScreen.lua` 里那句 `-- TODO: write to WorkshopLog.txt` 至今还在），
  所以 Lua 侧那句 `error ...` 往往无法区分是"确认框返回 false"还是"提交真的失败"。
- 反过来看 **Steam 客户端**的 `workshop_log.txt`：只有 `Create new workshop item … (OK)`、没有 update 记录，
  就说明 `ISteamUGC::SubmitItemUpdate` 从未被调用 ⇒ 失败发生在游戏侧提交之前。
- 上传统计别的"体积为 0.000 B"就是这个特征。

## 8. 交付前自检清单

- [ ] 结论有"可复现的命令 + 原始输出"，不是描述
- [ ] 平台差异结论有对照实验（改一个变量，结果反转）
- [ ] ZB 补丁：辅助类/方法 `public`；离线自测 `ALL CHECKS PASSED`
- [ ] 改 jar：整包重写；`--verify` 通过；`--restore` 与原文件逐字节一致；`ZipInputStream` 全量读无异常
- [ ] 工坊：`readWorkshopTxt` 解析正确、`validatePreviewImage = OK`、软链 staging 可见
- [ ] 更新 `docs/rolling_log.md`，并生成当天的 `docs/develop_log_<date>.md`
- [ ] 明确写出"**未做**什么"（例如没有真实点一次上传），不要含糊
