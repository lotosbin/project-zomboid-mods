# Project Viewpoint（3D 第一人称模组）在 macOS Apple Silicon 上的可行性调研

> 调研时间：2026-10-01　调研对象：Workshop `3809306528` / Mod ID `Viewpoint` v0.1.3（B42.21）
> 结论一句话：**在 macOS（含 Apple Silicon）上目前无法运行，属于显卡 API 的硬限制，不是安装或配置问题。**
>
> 若关心"自己重做一个同类模组"的可行性，见 [`pz-3d-mod-macos-feasibility.md`](pz-3d-mod-macos-feasibility.md)。

---

## 2026-10-03 实测更新（覆盖下面 2026-10-01 的部分结论）

社区包 **`ViewpointMac41Patch`**（Workshop `3812168749`，本文调研时还不存在）+ `pz-mac41-bridge.jar`
已经把游戏上下文从 **GL 2.1 兼容上下文换成了 OpenGL 4.1 core**，本机实测日志：

```
[PZMac41Bridge] macGlCore: OpenGL 4.1 Metal - 91.7, GLSL 4.10; core bridge on
                (63 implemented callbacks, forwardCompatible=true, native extension flags, OpenGL33 true…)
```

所以下面"游戏上下文是 GLSL 1.20 ⇒ 着色器编译必然失败"这条**不再成立**：这次 Viewpoint 真的跑过了
着色器编译、贴图、模型加载，并打印了 `[Viewpoint] game build: Build 42.21.0, as pinned`、
`compat: all 61 patch targets and 61 private members found`、`setup finished: first person turns on`。

**当前真正的硬阻塞换了位置**：桥用「libffi 回调 + 包装 `FunctionProvider`」模拟了一部分 GL 4.2+ 入口，
但**没有实现 GL 4.3 的顶点属性绑定族**（`glVertexAttribFormat` / `glVertexAttribBinding` /
`glVertexBindingDivisor` / `glBindVertexBuffer`），而 `viewpoint.render.MeshArena` 在首次世界绘制时
**无能力位门控**地调用它 ⇒ macOS 上该函数指针为 0 ⇒ LWJGL 直接
`FATAL ERROR in native method … The JVM will abort execution`。

覆盖度实测：Viewpoint 一共引用 **32 个 GL 4.2+ 函数，桥只覆盖 3 个**
（`glTexStorage2D`/`glTexStorage3D`/`glClearTexImage`）；其余大多有 `GLCapabilities` 门控
（`viewpoint/platform/IrisPacks` 读 `OpenGL40…46`、`GlDebug` 读 `OpenGL43`）所以能降级跑过，
`MeshArena` 没有门控，于是成为第一个把 JVM 打死的调用。

完整证据链、可复现命令与可直接提交给作者的报告：
[`viewpoint-mac41-bridge-gap-report.md`](viewpoint-mac41-bridge-gap-report.md)。
实测环境：Apple M4 / 32 GB / macOS 27.0、PZ 42.21.0 `4a0e9546ec`、Viewpoint 0.1.5a-hotfix、
ZombieBuddy 2.3.2、桥 `85c45fd3…`。

---

## 一、结论

| 项目 | Viewpoint 的要求 | macOS Apple Silicon 能给的 | 结果 |
|---|---|---|---|
| 着色器 | 54 个 `.frag/.vert` 全部是 `#version 330`，另有 3 处 `#extension GL_ARB_gpu_shader5` | 游戏实际上下文是 **GLSL 1.20**（OpenGL 2.1） | ❌ 编译必然失败 |
| 纹理 API | 无条件调用 `GL45.glCreateTextures` / `glTextureStorage2D` | OpenGL 4.1 上限，**4.5 函数在系统框架里根本不存在** | ❌ |
| 缓冲/顶点 API | `GL44.glBufferStorage`、`GL43.glVertexAttribBinding/glBindVertexBuffer` | 同上，**4.3/4.4 函数不存在** | ❌ |
| 拷贝/间接绘制 | `GL43.glCopyImageSubData`、`glMultiDrawElementsIndirect` | 同上，**不存在** | ❌ |
| 游戏上下文 | 需要 core profile ≥ 3.3 | PZ 在 macOS 建的是 **2.1 兼容上下文** | ❌ |

即使忽略游戏上下文、只谈系统能力：**Apple 的 OpenGL 从 10.14 起就被冻结在 4.1 core，4.2/4.3/4.4/4.5 从未实现**（见 [Apple: OpenGL Profiles](https://developer.apple.com/documentation/appkit/opengl-profiles)）。而 Viewpoint 的渲染主路径假定 GL 4.5。

---

## 二、证据链（全部为本机实测，可复现）

### 1. 游戏的 OpenGL 上下文确实是 2.1

来源：本机游戏日志（`~/Zomboid/Logs/` 下每次启动都会生成）

```
~/Zomboid/Logs/logs_2026-09-30_15-17/2026-09-30_15-17_DebugLog.txt:78
[30-09-26 15:17:31.228] LOG  : General      f:0> OpenGL version: 2.1 Metal - 91.7.
```

这句由游戏自己打印，对应 `projectzomboid.jar → zombie/core/Core.class#getOpenGLVersions()`：

```
sipush        7938                          // GL_VERSION
invokestatic  org/lwjgl/opengl/GL11.glGetString:(I)Ljava/lang/String;
putstatic     zombie/core/Core.glVersion
```

### 2. 游戏自己在 macOS 上把着色器降级到 GLSL 1.20

游戏自带说明文件：

```
<Steam>/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/media/shaders/README-Shaders.txt
"MacOS is limited to OpenGL 2.1 unless deprecated API calls are removed,
 in which case version 3.2 and greater are supported on MacOS.
 ...
 1) "#version 330" is replaced by "#version 120""
```

代码侧对应 `projectzomboid.jar → zombie/core/opengl/ShaderUnit.class`：该 class 的常量池里同时存在 `#version 330` 与 `#version 120` 两个字符串（即运行时替换）。

### 3. 游戏创建窗口时没有请求任何 GL 版本 / core profile

`projectzomboid.jar → org/lwjglx/opengl/Display.class`（GLFW 调用的常量已解码）：

| 设置的 hint | 值 | 说明 |
|---|---|---|
| `GLFW_CLIENT_API` | `GLFW_OPENGL_API` | 用 OpenGL |
| `GLFW_RED/ALPHA/DEPTH/STENCIL/ACCUM/AUX/SAMPLES` | 像素格式 | 与版本无关 |
| `GLFW_COCOA_RETINA_FRAMEBUFFER` | `0`（仅 macOS） | 关 Retina 缓冲 |
| `GLFW_OPENGL_DEBUG_CONTEXT` | `1`（仅 `Core.debug`） | 调试 |
| **`GLFW_CONTEXT_VERSION_MAJOR/MINOR`** | **未设置** | → GLFW 用平台默认值 |
| **`GLFW_OPENGL_PROFILE`** | **未设置** | → macOS 默认给 2.1 legacy |

所以 macOS 上永远拿到 2.1 上下文。

### 4. macOS 系统能力上限实测（CGL 探针）

```c
// /tmp/cgllegacy.c（legacy 上下文）
attrs: kCGLPFAOpenGLProfile = kCGLOGLPVersion_Legacy
输出: GL_VERSION = 2.1 Metal - 91.7    GLSL_VERSION = 1.20

// /tmp/cglprobe.c（3.2 core 上下文）
attrs: kCGLPFAOpenGLProfile = kCGLOGLPVersion_3_2_Core
输出: GL_VERSION = 4.1 Metal - 91.7    GLSL_VERSION = 4.10
```

符号表探测（`dlsym` 查 `/System/Library/Frameworks/OpenGL.framework/OpenGL`）：

```
glCreateTextures             MISSING   (GL 4.5)
glTextureStorage2D           MISSING   (GL 4.5)
glTextureParameteri          MISSING   (GL 4.5)
glBufferStorage              MISSING   (GL 4.4)
glVertexAttribBinding        MISSING   (GL 4.3)
glBindVertexBuffer           MISSING   (GL 4.3)
glCopyImageSubData           MISSING   (GL 4.3)
glMultiDrawElementsIndirect  MISSING   (GL 4.3)
glGetQueryObjectui64         MISSING   (GL 3.3)
glBindVertexArray            PRESENT
glBindSampler                PRESENT
glTexBuffer                  PRESENT
glTexStorage2D               PRESENT
glGetString                  PRESENT
```

### 5. Viewpoint 的实际 GL 需求（反汇编 `Viewpoint.jar`）

* 着色器：`viewpoint/shaders/*` 共 42 个 `.frag` + 12 个 `.vert`，**全部 `#version 330`**（另有 41 个 `.glsl` 库文件）。
* 字节码引用：`org/lwjgl/opengl/GL45`、`GL44`、`GL43`、`GL42`、`GL40`、`GL33`、`GL32`、`GL31` …（LWJGL3 API）。
* **主路径不做能力检测**：

```
$ javap -p -c viewpoint/render/MeshArena.class
private static int lightTexture(int);
   0: sipush        3553
   3: invokestatic  org/lwjgl/opengl/GL45.glCreateTextures:(I)I      // 无条件调用
```

全 jar 只有 5 个 class 读 `GL.getCapabilities()`，且都只用于可选功能：

| class | 检查的字段 | 用途 |
|---|---|---|
| `viewpoint/platform/FrameTimes` | `OpenGL33` | GPU 计时查询 |
| `viewpoint/platform/GlDebug` | `OpenGL43` | 调试输出 |
| `viewpoint/platform/VideoMemory` | NVX 显存查询 | 显存统计 |
| `viewpoint/render/TextureFilter` | — | 纹理过滤 |
| `viewpoint/render/FloorSlices` | — | 地板切片 |

而 `glCreateTextures` / `glBufferStorage` / `glVertexAttribBinding` / `glBindVertexBuffer` / `glCopyImageSubData` / `glMultiDrawElementsIndirect` 分布在 `render/` 下的 20+ 个 class（`MeshArena`、`PackArena`、`ShellArena`、`FrameStream`、`ModelBatches`、`PackDraws`、`FloorBaker`、`LampShadows`、`CascadeLayer` …），**均无能力回退分支**。

---

## 三、本机现状核查（与 GL 无关的部分其实都已就绪）

| 项目 | 状态 | 证据 |
|---|---|---|
| 游戏版本 | B42.21.0（模组要求 42.21，`versionMin=42.21 / versionMax=42.21`） | `~/Zomboid/version.txt`；日志 `version=42.21.0 4a0e9546ec` |
| 运行架构 | 原生 arm64（Zulu JRE 25.0.1 aarch64） | 日志 `os.arch=aarch64`、`java.vendor.version=Zulu25.30+17-CA` |
| ZombieBuddy 安装 | ✅ 已放好 | `Project Zomboid.app/Contents/Java/ZombieBuddy.jar`（12,428,709 B） |
| 42.21 Java 模组加载器修复 | ✅ 已打 | 该 jar 的 `META-INF/MANIFEST.MF`：`Implementation-Version: 2.3.2`、`X-Local-Compatibility-Fix: b42.20.4-b42.21-list-loader-1` |
| Steam 启动项 | ✅ 正确 | `-javaagent:ZombieBuddy.jar -Xmx6g -Xms2g --`（`--` 必须保留） |
| 模组授权 | ✅ 已批准 | `~/.zombie_buddy/mod_approvals.json` 中 `Viewpoint` = true |
| 实际加载结果 | ✅ 加载成功，57 个 patch 目标全部命中 | 日志 `[Viewpoint] game build: Build 42.21.0, as pinned`、`[Viewpoint] compat: all 57 patch targets and 61 private members found` |
| 3D 渲染 | ❌ | 日志中从未出现渲染器运行期才有的行（`GL debug output on`、`settings window: ImGui ready`、`video memory:`、`fps`） |

也就是说：**Java 侧（ZombieBuddy + PZVoxelStudioViewpoint 模型包 + Viewpoint）在 Apple Silicon 上完全正常，卡死的是 GPU 侧。**

---

## 四、可选路径（按现实程度排序）

### A. 换到有现代 GPU 驱动的 Windows 环境（唯一现实可行）
Viewpoint 需要 GL 4.3+，Windows/Linux 的独显驱动普遍提供 4.6。可选项：本机 Windows、家里另一台 Windows、或云端 Windows 主机（GeForce NOW 之类不支持装 Workshop 模组，需自备云主机/串流方案）。

### B. macOS 上"套壳"不可行（不要浪费时间）
* **CrossOver / Whisky / Wine**：OpenGL 最终仍转发到 Apple 的 OpenGL.framework，上限 4.1；`glCreateTextures` 等符号在宿主侧就是 NULL，转不出来。
* **Parallels Desktop（Windows 11 ARM 虚拟机）**：Parallels 自己的虚拟 GPU 驱动 OpenGL 支持更低（3.3 级别），4.5 同样无望。
* **D3DMetal / MoltenVK**：只能翻译 DirectX/Vulkan，PZ 走的是 OpenGL，不适用。

### C. 推动上游 / 作者（长期解）
两个前置条件缺一不可：
1. PZ 的 macOS 版必须给出 **core profile** 上下文（游戏自己的 `README-Shaders.txt` 承认"移除废弃 API 后可支持 3.2+"，说明这是可做的，但目前没做）；
2. Viewpoint 的作者要补一条 **GL 4.1 及以下** 的渲染回退路径（去掉 DSA 纹理、buffer storage、间接绘制等）。

建议把本页的探测结果直接发到作者的 Discord（`discord.gg/6hXwV7Usgk`），附上 `console.txt` + 显卡信息（模组说明里明确要求这样反馈）。

### D. 想要 Mac 上的 3D 视角，可以再试 `pz3d`
本机已安装 `3807334881 pz3d 0.4.1`。反汇编其 `PZ3D-0.4.1.jar` 可见：

* GL 引用最高到 `GL41`（正好等于 macOS 上限），`GL43` 只出现 1 处；
* 对 `GL_ARB_buffer_storage`、`GL_ARB_copy_image`、`GL_ARB_texture_gather` 做了扩展能力检测；
* 着色器是 `#version 330 core`。

**比 Viewpoint 更接近 macOS 可行**，但仍受制于"PZ 在 macOS 只给 2.1 上下文"这一条，所以不能保证可用——需要实测，并优先向该模组作者确认 macOS 支持情况。

---

## 五、附带排查项（与 GL 无关，但作者公告里提到）

* **关闭「锁定鼠标到窗口」**：模组说明第一条即为此——"Anyone stuck on setup, try disabling the lock cursor to window option on the ui options in main menu."（UI 选项里的 lock cursor to window）。
* 模组 `mod.info` 把版本钉死在 42.21：一旦游戏更新（`versionMin/versionMax=42.21`），会打印
  `[Viewpoint] first person stays off: this is not the game build the mod supports (see the line at load)` 并关闭第一人称。
* 遇到问题时作者建议：**先取消订阅再重新订阅**，以拉取热修版本。
* 模组运行期日志都写在 `~/Zomboid/console.txt`（以 `[Viewpoint]` 开头），截图用 `F9`。

---

## 六、参考链接

* Project Viewpoint（Workshop 3809306528）— https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528
* PZVoxelStudioViewpoint 3D 模型包（Workshop 3810302175）— https://steamcommunity.com/sharedfiles/filedetails/?id=3810302175
* ZombieBuddy 框架（Workshop 3619862853）— https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853
* ZombieBuddy GitHub（含 macOS 手动安装说明）— https://github.com/zed-0xff/ZombieBuddy
* B42.21 ZombieBuddy 临时修复（Workshop 3807686870）— https://steamcommunity.com/sharedfiles/filedetails/?id=3807686870
* pz3d（Workshop 3807334881）— https://steamcommunity.com/sharedfiles/filedetails/?id=3807334881
* Apple 官方：OpenGL Profiles（仅 legacy 2.1 与 core 3.2/4.1）— https://developer.apple.com/documentation/appkit/opengl-profiles
* GLFW 头文件说明：macOS 仅支持 core profile 上下文 — https://raw.githubusercontent.com/glfw/glfw/master/include/GLFW/glfw3.h
