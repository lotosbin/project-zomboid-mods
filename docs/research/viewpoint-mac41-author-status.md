# PZ Build 42.21 / macOS / 3D 渲染模组「平台桥」生态现状调研

- 调研时间：**2026-10-03 06:47–07:00 UTC**（北京时间 2026-10-03 14:47–15:00）
- 方法：`web_fetch` 在本机不可用（所有域名解析到 fake-IP `198.18.x.x`，工具拒绝访问）；全部改用 `curl` 抓取原始 HTML 后本地解析。原始抓取件保存在 `/tmp/mac41/d/raw/` 与 `/tmp/mac41/d/gl/`。
- 标注约定：**【页面原文】**＝我抓到的一手页面/仓库原文；**【二手/推断】**＝他人转述、社区猜测或我的推理。
- 明确失败的抓取：Steam 工坊「搜索页」的条目标题是客户端渲染，未能取到（只有 id）；Project Viewpoint 的 **1156 条评论只取到第 1 页（最新约 10 条）**，无法全文检索；官方论坛仅取到 topic 75195。

---

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| 有比 `0.1.0-alpha1-currentpack-private1` 更新的版本吗？ | **没有**。工坊 changelog 只有 2 条，均为 10-02 当天，且第 2 条原文写明 "No runtime changes"。 |
| 作者回应过 GL 4.3 缺口吗？ | **没有**。补丁页描述、2 条 changelog、8 条评论里均无 `glVertexAttribFormat` / `GL 4.3` / `JVM abort` 字样；作者在补丁评论区 **0 条回复**。 |
| 作者是谁 / 联系方式 | Steam 用户 **xiveboy**（`/id/xiveboy`，个人页仅显示 Portugal，**无 GitHub / Discord / 主页外链**）。他在 Viewpoint 的 macOS 讨论帖里活跃。 |
| macOS 能直接给 GL 4.3+ 吗？ | **不能**。Apple 官方 API 上限是 **4.1 core**（已弃用）；MoltenGL 只做 ES 2.0；ANGLE 只做 GL ES；zink on macOS 官方文档自称 "experimental with very limited capabilities"。 |
| 有公开的同类工作吗？ | 有：**xD3I / PZ_Optimization**（`pzopt.CoreGl`，用 FunctionProvider + Java upcall 在 4.1 core 上补齐缺失入口）。这正是本补丁致谢的 "OpenGL bridge origins"。 |
| 评论里有同类崩溃报告吗？ | 有大量「按 O 就崩」报告（M1/M1 Pro/M4 Max/M5），最接近的一条是 `jni_FatalError` + `liblwjgl.dylib`；但 **没有任何一条提到 `glVertexAttribFormat` / "JVM will abort" / "No context is current"**。 |

---

## 1. 工坊 3812168749（Mac 补丁）当前状态

### 1.1 基本事实【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/?id=3812168749>

| 字段 | 值 |
|---|---|
| 标题 | `Project Viewpoint - Patch for Mac [Apple Silicon \| B42.21 \| Unofficial Alpha]` |
| 作者 | **xiveboy**（<https://steamcommunity.com/id/xiveboy>，steamid `76561198974156602`） |
| 标签 | `Build 42`, `Misc`, `WIP` |
| 文件大小 | 21.194 MB |
| Posted | **2 Oct @ 2:25pm**（2026-10-02） |
| Updated | **2 Oct @ 2:33pm**（2026-10-02） |
| Unique Visitors | 154 |
| Current Subscribers | 44 |
| Current Favorites | 7 |
| Discussions | **0** |
| Comments | **8** |
| Change Notes | **2** |
| Required items | Project Viewpoint、ZombieBuddy |

> ⚠️ **易误判点**：该页 HTML 里含有 "This item has been removed from the community because it violates Steam Community & Content Guidelines." —— 但这行位于 `<div class="bannedNotification" id="bannedNotification" style="display: none">`，是 Steam **每个工坊页都带的隐藏模板**（Project Viewpoint 页面同样含 1 处）。**该物品并未被下架**，最新评论是 1 小时前。

### 1.2 Change Notes 全文（只有 2 条）【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/changelog/3812168749>

```
Showing 1-2 of 2 entries
Update: 2 Oct @ 2:33pm  by xiveboy
  Larger original cover; clarified untested PZOpt compatibility and installer limitation. No runtime changes.
Update: 2 Oct @ 2:25pm  by xiveboy
  Private alpha: Mac M1 tested; isolated OpenGL 4.1 installer.
```

**→ 结论：不存在比 `0.1.0-alpha1-currentpack-private1` 更新的版本。**
- 自首发以来**零运行时改动**（第 2 条明确写 "No runtime changes"，只改了封面和文案）。
- 页面上**没有出现任何版本号字符串**；`0.1.0-alpha1-currentpack-private1` 只存在于本地 `mod.info`/文件名。所以无法从网页确认该字符串，但可以确认**内容未被更新过**。
- 页面描述的 "Pinned versions" 里写的是 Viewpoint `0.1.5a-hotfix`、ZombieBuddy `2.3.2`、PZ `42.21.0 / revision 4a0e9546ec` —— 与本地看到的一致。

### 1.3 页面描述中的关键原文（节选）【页面原文】

> "**WARNING — VERY LIMITED TESTING** This patch has had very limited testing and has only been tested on one Mac mini M1 (16 GB)."

> "It prepares **OpenGL 4.1** and an adapted Viewpoint renderer in a separate game installation and profile."

> "Designed for Apple Silicon chips. ... **The current installer requires macOS and an ARM64 runtime; it does not support installation on Intel.**"

> "**Pinned versions:** PZ 42.21.0 / revision `4a0e9546ec`, Viewpoint `0.1.5a-hotfix`, ZombieBuddy `2.3.2`, and the validated model pack 1.0 variant."

> "**PZOpt compatibility has not been validated.** The current installer requires an unmodified PZ 42.21.0 source and does not merge existing Java patches or agents."

> "**Credits:** Project Viewpoint — ellu and norkus; models — sour_kisel; ZombieBuddy — Andrey "Zed" Zaikin; **OpenGL bridge origins — PZ Optimization, xD3I and contributors.** Unofficial community patch; no official endorsement is claimed."

🔎 **全文 grep 结果（整页 HTML）**：`glVertexAttribFormat` = **0 次**、`mac41` = 0 次、`JVM will abort` = 0 次、`No context is current` = 0 次。`ViewpointMac41` = 4 次（都指安装路径 `mods/ViewpointMac41Patch/...`、`~/Library/Application Support/ViewpointMac41/versions/`，以及一条评论里提到的 "custom alpha launcher (ViewpointMac41)"）。

### 1.4 全部 8 条评论（作者 0 回复）【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/?id=3812168749>（Comments 区）与 <https://steamcommunity.com/sharedfiles/filedetails/comments/3812168749>

| 用户 | 时间（相对抓取时刻） | 原文要点 |
|---|---|---|
| unaturalx | 7 小时前 | "Working on M4 Mac" |
| vladek6996 | 7 小时前 | "not work((( m4 max 36ram" |
| tubs chubs | 5 小时前 | "Having trouble with Zombie Buddy, should I use a temp fix??" |
| Kingwenz | 3 小时前 | 长文：M5 MacBook Pro 16GB；手动把补丁文件塞进隐藏的 app 包内容、清 Zomboid 缓存、试不同版本；"**Half the time, the game crashed instantly the second I pressed O to toggle perspectives.**"；另外被 "the Portuguese launcher script (**Jogar.command**) refusing to boot the game due to version mismatch errors" 拦住。（他自述 "yes, i did use A.I for this message"） |
| tubs chubs | 2 小时前 | "Had very similar roadblocks as Kingernz" |
| Kingwenz | 2 小时前 | "should also mention my macbook pro m5 is on 16GB of ram" |
| NNG | 1 小时前 | "please add intel support / macBook pro 2018 intel i7" |
| breydonhoang9 | 1 小时前 | "It only works with zombiebuddy the project viewpoint mod and this one **if I add any more mods it crashes when I press O**" |

**→ 结论：**
- 8 条评论里**没有一条**提到 `glVertexAttribFormat`、`JVM will abort`、`No context is current`。
- 作者 xiveboy 在这 8 条下**没有任何回复**，也没有在描述或 changelog 里承认 GL 4.3 缺口、没有发布新桥。
- 崩溃报告集中在「按 O 切换视角瞬间崩」，机型覆盖 M1 Pro / M4 Max / M5，与本地观察方向一致（首次 3D 绘制即崩），但**公开评论没有给出 GL 调用级的证据**。

---

## 2. 作者 xiveboy 的可查身份与公开表态

### 2.1 Steam 个人页【页面原文】

来源：<https://steamcommunity.com/id/xiveboy>
- persona name: `xiveboy`；个人页 "real name" 字段显示 **Portugal**。
- private summary 为空；**抓取到的外链只有 Valve 自家的 CSS/法务链接**（`avatars.fastly.steamstatic.com`、`www.valvesoftware.com/*`）。
- **→ 没有公开的 GitHub / Discord / 个人主页 / 邮箱。唯一可行联系方式是 Steam 评论或讨论帖。**

### 2.2 他的工坊作品【页面原文】

来源：<https://steamcommunity.com/id/xiveboy/myworkshopfiles/?appid=108600>
共 9 项：本补丁 + `WalkingTuga Stutter Fix [B42.20.4]`、`NoAutoWake [B42.20.4]`、`WalkingTuga Zombie Vanilla Body Patch`、`WalkingTuga Intro Cleaner`、`WalkingTuga - Automatic Firearm Handling`、`WalkingTuga HopOverIt No Injuries`、`DO NOT USE`、`teste desempenho`。**没有其他 macOS / OpenGL 相关作品。**

### 2.3 作者在 Project Viewpoint 的 macOS 讨论帖里的全部表态【页面原文】

帖子：**"macOS Crash on perspective change (M-series chips) + Cannot open settings menu"**
<https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187334843720692/>
OP = `vladek6996`，29 Sep @ 2:14pm，共 26 帖，最后回复 2 Oct @ 7:18pm。

作者 xiveboy 的原话（按时间）：

| 时间 | 原文 |
|---|---|
| 30 Sep @ 1:18am | "**Im doing a fix to works in mac!**" |
| 30 Sep @ 8:11am | "At this point, I've made total playable without any very noticeable visual bugs, however, the performance is poor. I have a Mac Mini M1 with 16GB of RAM. I don't know if it's my PC or the port to make it work on Mac. I'll publish the patch to make it work on Mac tomorrow or in the next few days if I manage to, so people can test it. I've started optimizing it, but I won't dedicate time to that right now! I'll give updates here!" |
| ≈2 Oct（"21 hours ago"） | "Hey everyone, the patch is progressing better now. I should be able to release the Mac version on the Workshop either today or by the end of the week. Cheers!" |
| ≈2 Oct（"9 hours ago"） | "**Here it is: https://steamcommunity.com/sharedfiles/filedetails/?id=3812168749** Please read the description, I hope it works for all, best regards!" |

**→ 作者从未公开说明他用了什么桥、也从未提及 GL 4.3 / `glVertexAttribFormat`。** 他唯一的技术描述是"做成了 OpenGL 4.1"。

### 2.4 同帖里最接近本机症状的公开证据【页面原文，二手用户报告】

- `vladek6996`（OP，M4 Max，29 Sep @ 2:14pm）："As soon as I press the 'O' key to switch the perspective into 3D, the game instantly crashes to the desktop. This is a known issue for Apple Silicon GPUs when custom OpenGL/PBR shaders try to inject into the Mac's graphic translation layer."（后半句是用户的**推测**）
- `CrokoZo`（29 Sep @ 11:43pm）："I just checked and its an opengl version issues, **macos runs on opengl 2.1 and viewpoint uses opengl 3.0**, so there is no fix possible until the mod creator make a macos version."【二手/说法不准确】
- `DixieNormus`（30 Sep @ 9:52am）——**公开记录里最接近 JVM abort 的一条**：
  > "macOS 26.6.2, Apple Silicon ARM64 MacBookPro18,4, PZ Build 42.21. Viewpoint loads successfully and reports all patch targets found. Pressing Delete does not open the settings window. **Pressing O immediately crashes JavaAppLauncher. macOS crash report shows EXC_BAD_ACCESS / SIGABRT with `jni_FatalError` on the main thread and ARM64 `liblwjgl.dylib` loaded. PZ reports OpenGL 2.1 Metal - 90.5.**"
- `Did_you_eat_my_burrito`（2 Oct，"4 hours ago"）："tried to figure it out for 30 min but it didnt work for me"

另一帖 **"Crash by pressing O"** <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187435308750170/>（7 帖，2026-09-29 起）主体是 **Windows + Intel Arc B580/B570**（"on Intel ARC b580 draw skybox and crashes"），但最后一条 `大吃货喵`（抓取时 3 分钟前）写："The same problem also occurred with my MacBook pro m1pro"。

**→ 三个线程 + 两个工坊主页全部 HTML 中，`glVertexAttribFormat` / `JVM will abort` / `No context is current` 命中数均为 0。**

---

## 3. 依赖 1：Project Viewpoint（工坊 3809306528）

### 3.1 基本事实【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528>

| 字段 | 值 |
|---|---|
| 标题 | Project Viewpoint |
| 作者 | **ellu** + **norkus**（页面 "Created by" 两人） |
| 标签 | Build 42, Misc, Models, Multiplayer, WIP |
| 文件大小 | 2.485 MB |
| Posted | **27 Sep @ 12:10pm**（2026） |
| Updated | **1 Oct @ 1:41am**（2026） |
| Unique Visitors | 189,747 |
| Current Subscribers | **114,209** |
| Current Favorites | 9,487 |
| 评分 | 3,245 ratings |
| Discussions | 111 |
| Comments | 1,156 |
| Change Notes | 8 |
| Requires | **ZombieBuddy** |
| 依赖它的物品 | 23 |

### 3.2 Change Notes 全文（8 条）【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/changelog/3809306528>

```
1 Oct @ 1:41am   ellu  - Crashing to iso view Hotfix
1 Oct @ 12:04am  ellu  - Signature Hotfix
30 Sep @ 11:56pm ellu  - Setup: Brand new configuration wizard / 3D Corpses / MC Shaders (Iris) /
                         Movement / Gunplay / FPV Camera / Keybinds / TAA / 3D Text / Sound / Misc
29 Sep @ 2:40am   ellu  - Hotfix: interaction UI no longer breaks on multiplayer
29 Sep @ 1:15am   ellu  - Hotfix: deal with ZB signing issues
29 Sep @ 12:21am  ellu  - Hotfix: dropped bloody weapons no longer cause a crash
28 Sep @ 9:06pm   ellu  - Signature Hotfix
27 Sep @ 12:10pm  ellu  - Release
```

### 3.3 描述中的技术定位与联系方式【页面原文】

> "ANY EXTERNAL JAVA ADDONS TO OUR MOD ARE USE AT YOUR OWN RISK."
> "Custom Rendering Engine — **Built from the ground up using modern OpenGL features, and a full PBR-based rendering pipeline**, Viewpoint turns Project Zomboid into a fully-fledged 3D game."
> "Join our community: **discord.gg / 6hXWv7Usgk**"
> "Bugs and Feedback — Viewpoint writes lines starting with `[Viewpoint]` to `Zomboid\console.txt`."
> 控制：`O` 第一人称、`Shift+O` 切换、`Insert+O` Free Cam、**`Delete` 打开设置**（评论 #2 指出 Mac 笔记本没有 forward delete 键，这是 Mac 用户的第二类阻塞）。

**源码仓库：没有。** 描述、页面、Skymods 镜像页（<https://catalogue.smods.ru/archives/487860>）均无 GitHub/源码链接。唯一官方社区入口是 Discord。

**能力门控（GL 4.2/4.3 检测）：描述里没有任何关于 GL 版本检测或 macOS 分支的说明。** 从公开页面看**没有**"检测不到就降级/拒绝加载"的文字声明。【推断】从 xiveboy 的补丁必须"adapt the Viewpoint renderer"来看，Viewpoint 本身没有 macOS/低版本 GL 的降级路径。

**macOS 相关讨论（页面原文标题）**，来自 <https://steamcommunity.com/sharedfiles/filedetails/discussions/3809306528>：

| 主题 | 链接 | 回复 |
|---|---|---|
| **macOS Crash on perspective change (M-series chips) + Cannot open settings menu** | <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187334843720692/> | 26 |
| Crash by pressing O | <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187435308750170/> | 7 |
| Intel arc compatiblility fix | <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187435308969677/> | 9 |
| Works great on Linux!!!! This is amazing!!!! | <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187704184609561/> | 0 |

**→ Viewpoint 侧没有 `glVertexAttribFormat` 相关的 issue/讨论。**

---

## 4. 依赖 2：ZombieBuddy（工坊 3619862853 / GitHub）

### 4.1 工坊页【页面原文】

来源：<https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853>

| 字段 | 值 |
|---|---|
| 标题 | ZombieBuddy |
| 作者 | **Zed**（= Andrey "Zed" Zaikin） |
| 标签 | Build 41, Build 42, Framework |
| 文件大小 | 14.460 MB |
| Posted | **7 Dec, 2025** @ 2:11pm |
| Updated | **7 May @ 12:13am**（年份未显示；因发布于 2025-12-07，**推断为 2026-05-07**） |
| Unique Visitors | 321,194 |
| Current Subscribers | **308,963** |
| Current Favorites | 7,135 |
| 评分 | 1,843 ratings |
| Discussions | 13 / Comments 878 / Change Notes 21 |
| 依赖它的物品 | 186 |

最新 5 条 changelog【页面原文，<https://steamcommunity.com/sharedfiles/filedetails/changelog/3619862853>】：

```
7 May @ 12:13am   mouse cursor fix
6 May @ 2:16pm    autofix known mods order to prevent borken game
6 May @ 11:08am   API updates
4 May @ 7:22am    watermark opacity in ModOptions / internal API changes
2 May @ 11:08am   v2.1.0: in-game mod approval dialog, mod signing, mod preload,
                  check if mods are banned on steam before loading them
```

安全机制原文："Java mods enabled through ZombieBuddy have unrestricted access to your system... Whenever a Java mod ships a new or updated JAR, ZombieBuddy shows a native dialog with the mod id, file path, last-modified date, and **SHA-256 fingerprint**. Nothing is loaded until you click Yes." 批准记录：macOS/Linux `~/.zombie_buddy/mod_approvals.json`。

macOS 安装方式原文："Copy ZombieBuddy.jar from the mod's `libs/` directory to macOS: `~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/` ... Add this JVM argument: `-javaagent:ZombieBuddy.jar --`"

### 4.2 GitHub / 最新版本【页面原文】

来源：<https://github.com/zed-0xff/ZombieBuddy>、<https://api.github.com/repos/zed-0xff/ZombieBuddy>、<https://api.github.com/repos/zed-0xff/ZombieBuddy/releases>

- 描述："Java agent framework for Project Zomboid that enables runtime bytecode patching using ByteBuddy."
- **License: MIT**；Stars 122；最后 push `2026-08-16T16:41:02Z`
- Releases（GitHub API）：
  - **`v2.3.3`** — published `2026-07-30T09:46:25Z` — assets: `zbNative.dll`, `ZombieBuddy.jar`, `ZombieBuddy.jar.zbs`
  - `windows_installer_4.2` — `2026-07-30T10:08:52Z` — `ZombieBuddyInstaller_v4.2.exe`
  - `windows_installer` v4.1 — `2026-01-23T08:40:04Z`

**→ 官方最新 release 是 v2.3.3（2026-07-30）；xiveboy 的补丁 pin 的是 2.3.2（落后一个小版本）。** 工坊条目最近更新在 2026-05-07，早于 v2.3.3 发布，**工坊内 jar 的实际版本无法从页面确认**（页面不显示版本号）。

---

## 5. Q3：macOS 上「给 PZ 加现代 OpenGL 模拟层 / GL 4.x 桥」的公开工作

### 5.1 已存在的公开工作（最相关）：xD3I / PZ_Optimization

- 工坊：**PZ_Optimization, item 3805285544** → <https://steamcommunity.com/sharedfiles/filedetails/?id=3805285544>
- 镜像页（含作者名与日期）：<https://catalogue.smods.ru/archives/478160> —— "Author: **xD3I**; Published September 21, 2026; Last revision: 22 Sep at 09:35 UTC; Steam version on Windows, Linux and macOS."
- 源码仓库：**<https://github.com/xD3I/PZ_Optimization>** —— 描述 "Project Zomboid Build 42 performance work: class overrides, harness, findings"；**仓库没有 LICENSE 文件**（只有 README 里说明 FSR1 部分为 MIT）；最后 push `2026-10-03T03:19:50Z`（今天）；默认分支 `master`。

**关键文档：`docs/findings-mac-gl41-2026-10-01.md`**
（<https://github.com/xD3I/PZ_Optimization/blob/master/docs/findings-mac-gl41-2026-10-01.md>）
标题：`# macOS on OpenGL 4.1 core (macGlCore, 2026-10-01)`，测试机 MacBook Pro M1 Pro / macOS 27.0.1 / "4.1 Metal - 91.7"。**原文摘录**：

> "The game asks GLFW for a window with no version hints, so **macOS hands it Apple's legacy context: OpenGL 2.1, GLSL 1.20, no GL 3 entry point. Apple offers more only as a *core* profile (3.2 to 4.1, forward compatible)**, where the fixed-function API is gone."

> "Probe ... a **4.1 core forward-compatible context works**, GLSL 4.10 ... **43 extensions** ... **no compute, image load / store, bindless, buffer storage, DSA, `ARB_clear_texture`, KHR_debug.**"

> "LWJGL 3.4.1 forces `forwardCompatible` on a core context, so its table has no deprecated entry point (**a call aborts the JVM**)."

> "**Aliases**: `...EXT` / `...ARB` names to the core function (180 of them) ... **A shared no-op for any entry point the driver lacks** ... **Emulated GL 4.4 `glClearTexImage` / `glClearTexSubImage`** through a scratch framebuffer (`GL_ARB_clear_texture` reported)."

> "The shim itself is ~6 % of a core on the render thread: ~1,500 `glEnable`, ~500 `glDisable` and ~1,000 `glUseProgram` upcalls a frame (~70-150 ns each)."

- 实现：`src/pzopt/pzopt/CoreGl.java`、`CoreGlsl.java`（在仓库 `src/pzopt/pzopt/` 目录下，共 200+ 个类）。
- **`tools/mac/glbridge.m` 不是 GL 4.3 桥**，而是**呈现路径**原型：legacy 2.1 GL 渲染 → `IOSurface` → `CAMetalLayer`，用 `presentDrawable:afterMinimumDuration:` 拿 ProMotion 时序。**别把它和本任务的「桥」混淆。**
- `docs/plan-vulkan-renderer.md`（2026-09-19）：把渲染器从 OpenGL 迁到 Vulkan 的长期计划；原文提到 "**LWJGL 3.4.1** is shaded into `projectzomboid.jar` ... **The `vulkan` module is not bundled.**"、"119 Java files call `org.lwjgl.opengl.*`; about **1,800 call sites**"。

**→ 这就是本补丁致谢里的 "OpenGL bridge origins — PZ Optimization, xD3I and contributors"。它证明：macOS 上可行的路线不是"拿到 4.3 上下文"，而是"在 Apple 4.1 core 上做入口点模拟 + GLSL 降级"。**

### 5.2 通用 GL 层：macOS 能否「直接」给出 GL 4.3+？

| 方案 | 提供什么 | 能否给桌面 GL 4.3 core | 成熟度 / 授权 | 来源 |
|---|---|---|---|---|
| **Apple 原生 OpenGL** | 默认 2.1 legacy；可选 **3.2 / 4.1 core**（NSOpenGLProfile 只有 `VersionLegacy` / `Version3_2Core` / `Version4_1Core`） | **不能** | 官方**已弃用**（macOS 10.14 起） | 【页面原文】<https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html>（"OpenGL was deprecated in macOS 10.14"）；NSOpenGLProfile 枚举镜像：<https://learn.microsoft.com/en-us/dotnet/api/appkit.nsopenglprofile> |
| **MoltenGL**（Brenwill，MoltenVK 同门） | **OpenGL ES 2.0** over Metal | **不能**（连桌面 GL 都不是） | 商业闭源授权；当前版本 0.30.1 | 【页面原文】<https://moltengl.com/>（"MoltenGL is an implementation of the **OpenGL ES 2.0** API that runs on Apple's Metal graphics framework"）、<https://moltengl.com/downloads/>、<https://moltengl.com/docs/license-agreement/moltengl-license-agreement.html> |
| **ANGLE**（google/angle） | 把 **GL ES** 2.0/3.0/3.1 翻译到后端；macOS 上 Metal 后端 complete（10.14+） | **不能**（输出的是 GL ES，不是桌面 GL core；桌面 GL 那一列是它「消费」的后端，且在 macOS 标 deprecated） | 成熟、BSD 系；但目标是 WebGL/ES | 【页面原文】<https://chromium.googlesource.com/angle/angle/>（表格：OpenGL ES 2.0/3.0/3.1 → Metal complete；Mac OS X 的 Desktop GL 列 = deprecated） |
| **Mesa zink**（Vulkan→桌面 GL） | 理论可给 GL 4.3/4.5/4.6（文档逐版本列要求） | 理论可以，**实际不能用于本项目** | Mesa 官方原文：**"Zink on macOS is experimental with very limited capabilities."** 需 MoltenVK / Vulkan SDK ≥ 1.3.250 | 【页面原文】<https://docs.mesa3d.org/drivers/zink.html>（节 "Apple macOS and MoltenVK"） |
| **Mesa llvmpipe**（软件光栅化） | 高版本 GL，但纯 CPU | 形式上有，实际不可行：要自建 Mesa 并替换 macOS 上 GLFW/Cocoa 走的 CGL 路径；性能对 3D 游戏不可用 | 页面未直接标注 GL 版本号 | 【页面原文】<https://docs.mesa3d.org/drivers/llvmpipe.html> |
| **LWJGL 侧的「缺失入口回退」** | 无 | — | LWJGL 无内建回退：`GL43.glVertexAttribFormat(int,int,int,boolean,int)` 存在但缺函数地址就 abort（见上 xD3I 原文）。只能自己做 `GLCapabilities` + `FunctionProvider` | 【页面原文】<https://javadoc.lwjgl.org/org/lwjgl/opengl/GL43.html> |

**公开检索结果**：
- GitHub API 搜索 `mac41+zomboid` → **0 个仓库**（<https://api.github.com/search/repositories?q=mac41+zomboid>）
- GitHub API 搜索 `zomboid+opengl` → 仅 1 个无关仓库 `graemsheppard/project-zigboid`
- → **除 xiveboy 的私有补丁 + xD3I 的公开工作外，没有其他公开的「PZ macOS GL 4.x 桥」项目。**

### 5.3 可行替代方案（按可落地性排序）【推断，基于以上一手材料】

1. **（最可行）在 Apple 4.1 core 上模拟 `glVertexAttribFormat` 族**：`glVertexAttribFormat` / `glVertexAttribIFormat` / `glVertexAttribLFormat` / `glBindVertexBuffer` / `glVertexAttribBinding` / `glVertexBindingDivisor` 属 `ARB_vertex_attrib_binding`，Apple 的 4.1 core 没有（xD3I 原文："no ... DSA"）。可在 shim 里跟踪 «attrib → format / buffer / offset / stride / divisor» 状态，在 draw 前翻译成 `glBindBuffer(GL_ARRAY_BUFFER)` + `glVertexAttribPointer` + `glVertexAttribDivisor`（语义等价，因为 `glVertexAttribFormat` 只是把「格式」与「缓冲绑定」拆开）。这正是 xiveboy 的桥缺的那一块。代价：需要一份能拦下所有 draw 的钩子。
2. **让 Viewpoint 走 3.3/4.1 路径**：xD3I 已证明「游戏本体 + 大量增强特性」能在 4.1 core 上跑（GLSL 1.x→330 core 翻译、4.2+→410、丢 `layout(binding)` 后置绑定）。Viewpoint 若加能力门控即可，但 **Viewpoint 是闭源 jar，需要字节码 patch**（ZombieBuddy `@Patch` 可用）。
3. **不要指望的路线**：MoltenGL（只有 ES2）、ANGLE（只有 ES）、zink-on-macOS（官方自称实验性）、llvmpipe（纯 CPU）、Vulkan 后端（xD3I 自己的 plan 也承认是大工程，且 LWJGL 未打包 `vulkan` 模块）。

---

## 6. 页面未能取到 / 限定说明

- 本机 `web_fetch` 工具对**所有**域名失败（DNS 解析到 `198.18.x.x`，工具判定为 non-public IP）；本报告全部内容均由 `curl` 直接抓取 HTML 得到，未见"页面被墙"的情况。
- **Steam 工坊搜索页**（"viewpoint mac" / "mac41"）的条目标题由客户端渲染，未能取到标题列表；只能确认 "viewpoint mac" 的搜索结果里出现过 `3812168749`，"mac41" 的搜索结果里没有。
- **Project Viewpoint 的 1156 条评论只取到第 1 页**（最新约 10 条），未能全文检索；因此「评论里没有 glVertexAttribFormat」这一结论的覆盖范围仅限于补丁页 8 条 + 两个讨论帖 33 帖 + 两个工坊主页 HTML。
- 官方论坛仅取到 <https://theindiestone.com/forums/topic/75195-mac-version-b4201-siliconintel/>（内容为 Apple Silicon 原生 JVM / Rosetta 的讨论，**与 OpenGL 版本无关**）；其他论坛帖未逐一取。
- 工坊页面均**不显示模组版本号**，所以 `0.1.0-alpha1-currentpack-private1` 无法从网页交叉验证，只能通过 changelog「无运行时改动」推断本地版本仍是最新。
- 相关但与 macOS 无关：社区崩溃调查报告 <https://willmayrink.github.io/pz-bug-tracking/>（2026-07-02，**Windows/AMD GPU** 的 `GameWindow.InitDisplay()` OpenGL API 误用，提到 LWJGL `-Dorg.lwjgl.system.allocator=system`），不适用于本项目。

---

## 7. 给下一步的行动建议

1. **不要等更新**：页面零运行时更新、作者未回应、评论区无同类技术报告。若要走作者路线，只能主动联系：在 <https://steamcommunity.com/workshop/filedetails/discussion/3809306528/586187334843720692/> 里 @xiveboy（他 10-02 还在那儿回帖），或在他的补丁页评论。他**没有** GitHub/Discord。
2. **自修桥的最小改动面**：补 `ARB_vertex_attrib_binding` 六个入口的**状态跟踪 + 翻译**（不是 no-op，否则顶点布局错乱），并确保 shim 在 `GL.createCapabilities()` 之后替换 `GLCapabilities`/`FunctionProvider`（照抄 xD3I `CoreGl` 的反射构造思路）。
3. **验证基线**：先确认本机上下文是不是 4.1 core（`glGetString(GL_VERSION)` 应为 `4.1 Metal - xx`）；如果是 `2.1 Metal`，说明补丁的窗口提示没生效——xD3I 文档说明游戏向 GLFW 要窗口时**不带 version hint**，所以必须由补丁显式请求 core profile。
4. 若要与 xD3I 的既有成果对齐，直接读 <https://github.com/xD3I/PZ_Optimization/blob/master/docs/findings-mac-gl41-2026-10-01.md> 与 `src/pzopt/pzopt/CoreGl.java`（注意该仓库**无 LICENSE**，只有 README 里 FSR1 部分标明 MIT，复用前需确认授权）。
