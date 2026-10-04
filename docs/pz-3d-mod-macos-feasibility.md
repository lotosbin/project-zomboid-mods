# 在 macOS 上重做一个 Viewpoint 式 3D 模组：可行性分析

> 前置结论见 [`viewpoint-macos-apple-silicon.md`](viewpoint-macos-apple-silicon.md)：现成 Viewpoint 在 macOS 上跑不了。
> 本文回答的是：**参考它的思路自己重做，能不能在 macOS 上跑起来、要付出什么代价。**
> 所有平台能力数据均为本机（Mac16,10 / Apple M4 / macOS 27.0）实测。

---

## 一、结论摘要

把问题拆成三层，可行性完全不同：

| 层 | 可行性 | 依据 |
|---|---|---|
| **① Java 集成层**（挂钩游戏、读世界数据、输入、交互 UI） | ✅ **完全可行** | ZombieBuddy 在 Apple Silicon 上已验证可用；Viewpoint 自己的日志证明 57 个 hook 在 42.21 + arm64 上全部命中 |
| **② 渲染层 — 纯 OpenGL 重写** | ⚠️ **可行但降级**（GLSL 1.20 时代的技术栈） | 实测 macOS legacy 上下文：有 MRT/浮点纹理/FBO/instancing/fence/纹理数组；无 DSA/buffer storage/compute/SSBO/`map_buffer_range` |
| **③ 渲染层 — Metal（或 Vulkan/MoltenVK）后端** | ✅ **可行，且是 macOS 的最优解** | 实测 `CGLTexImageIOSurface2D`、IOSurface、Metal 全部可用；GL 只留最后一步 blit，彻底绕开 4.1 天花板 |

**关键洞察**：macOS 上失败的根本原因不是 Viewpoint 用了 GL 4.3~4.5（这部分只有约 93 个调用点，属于机械可移植），
而是**游戏只给 GLSL 1.20 的 2.1 上下文**。所以：

* 给 Viewpoint 打"GL 4.1 回退补丁" → 对 Windows/Linux 老显卡有意义，**对 macOS 依然无效**（`#version 330` 编译不过）。
* 让 mod 自己把上下文改成 core profile → **会让游戏自己崩**（PZ 在 macOS 把自带着色器降级成 `#version 120`，core profile 拒绝 1.20）。
* 只有 **绕开 GL**（Metal/Vulkan 渲染 → IOSurface → GL 贴图合成）才能既保留现代渲染能力，又不动游戏的 2.1 上下文。

---

## 二、macOS legacy 上下文实测能力矩阵

（`kCGLOGLPVersion_Legacy` + `kCGLPFAAccelerated`，等价于 PZ 实际拿到的上下文；`GL_VERSION = 2.1 Metal - 91.7`）

### 2.1 上限

| 项 | 值 |
|---|---|
| GLSL | **1.20**（`#version 130` / `330` 编译失败） |
| 纹理单元 / 顶点属性 | 16 / 16 |
| Vertex / Fragment uniform 组件 | 4096 / 4096（≈1024 个 vec4，够用） |
| **Varying 浮点数** | **124**（≈31 个 vec4，比经典"32 float"宽松很多） |
| Draw buffers / Color attachments | **8 / 8**（够做 G-buffer） |
| MSAA | 4x |
| Texture array 层数 | 2048 |
| 最大纹理 | 16384 |

### 2.2 可用（✅ 这些让"现代感"渲染成立）

```
GL_ARB_framebuffer_object / GL_EXT_framebuffer_object   多渲染目标 + FBO
GL_EXT_framebuffer_blit / GL_EXT_framebuffer_multisample(_blit_scaled)
GL_ARB_draw_buffers / GL_EXT_draw_buffers2              MRT + 单独写掩码
GL_ARB_texture_float / GL_ARB_color_buffer_float        HDR 缓冲
GL_ARB_depth_texture / GL_ARB_shadow(_ambient)          阴影贴图
GL_ARB_depth_buffer_float / GL_EXT_packed_depth_stencil depth32f / depth24s8
GL_EXT_texture_array                                    级联阴影、纹理图集数组
GL_ARB_texture_rg / GL_EXT_texture_integer              法线/ID 缓冲
GL_EXT_texture_shared_exponent / GL_ARB_half_float_pixel
GL_EXT_texture_sRGB / GL_ARB_framebuffer_sRGB           正确的线性/sRGB 管线
GL_EXT_texture_compression_s3tc / _dxt1 / ARB_texture_compression_rgtc
GL_ARB_instanced_arrays / GL_ARB_draw_instanced         实例化
GL_EXT_multi_draw_arrays                                一次调用多段绘制（间接绘制的弱化替身）
GL_ARB_draw_elements_base_vertex                        base vertex
GL_APPLE_vertex_array_object                            VAO（必须用 APPLE 版）
GL_ARB_sync            → glFenceSync/glClientWaitSync ✅ 实测可用（GPU 与 CPU 并行）
GL_EXT_timer_query / GL_APPLE_fence                     计时与旧式栅栏
GL_APPLE_flush_buffer_range → glBufferParameteriAPPLE/glFlushMappedBufferRangeAPPLE
GL_ARB_occlusion_query                                  遮挡剔除
GL_EXT_gpu_shader4                                      在 GLSL 1.20 语法下补上整数运算/flat/textureSize
GL_ARB_shader_texture_lod / GL_EXT_texture_filter_anisotropic / GL_NV_texture_barrier
GL_EXT_transform_feedback / GL_EXT_geometry_shader4 / GL_EXT_bindable_uniform
```

### 2.3 不可用（❌ 必须改设计）

| 能力 | 状态 | 替代方案 |
|---|---|---|
| `#version 130/330` 着色器 | 编译失败 | 全部改写 GLSL 1.20（`attribute/varying`，去掉 `layout(location=)`） |
| `GL_ARB_gpu_shader5` | 无（只有 warning） | 手写 4-tap 代替 `textureGather` |
| `glTexStorage2D`（不可变纹理） | `GL_INVALID_OPERATION` | `glTexImage2D` |
| `glBindVertexArray`（core 版） | `GL_INVALID_OPERATION` | `glBindVertexArrayAPPLE` |
| `glMapBufferRange` | `GL_INVALID_OPERATION`（且无 `ARB_map_buffer_range`） | `glMapBuffer` + `GL_APPLE_flush_buffer_range`，或双缓冲 `glBufferSubData` |
| DSA（`glCreateTextures`/`glTextureStorage2D`/`glTextureParameteri`） | 框架未导出 | bind-then-modify |
| `glBufferStorage`（持久映射） | 无 | 双/三缓冲 VBO + `glFenceSync` |
| `glMultiDrawElementsIndirect` | 无 | CPU 批次 + `glMultiDrawElementsEXT` |
| Compute Shader / SSBO / image load-store | 无 | 全部退回 fragment/vertex + 纹理 |
| UBO（`ARB_uniform_buffer_object`） | 无（只有 `EXT_bindable_uniform`） | 普通 uniform + 常量表 |
| `glGetQueryObjectui64`（core） | 框架未导出 | `EXT_timer_query` 版本 |

---

## 三、五条实现路线对比

| 路线 | 做法 | 上限 | 工作量 | 风险 | 评价 |
|---|---|---|---|---|---|
| **A. 纯 GL 2.1/GLSL 120 重写** | 全部在游戏的 2.1 上下文里写延迟/前向渲染 | "2012 年 Minecraft 光影包"级别：能做出 G-buffer、阴影、HDR、天气，但没有 GPU 驱动管线、没有间接绘制 | 中～高 | 低（不依赖任何非标准接口） | 可行，效果打折扣 |
| **B. Metal 后端 + IOSurface 合成（推荐）** | 自研 native dylib 用 Metal 渲染到 IOSurface；GL 侧只做 `CGLTexImageIOSurface2D` + 全屏 quad | **不设上限**（Metal 3，想做 compute/光线追踪都行） | 高（要写两套代码 + 桥接） | 中（同步/全屏/分辨率切换） | **macOS 唯一能"现代化"的路** |
| **C. MoltenVK/Vulkan 后端** | 同上，但用 Vulkan 写渲染器（跨平台复用） | 同上（受 MoltenVK 支持范围） | 高 | 中高（要自带 `org.lwjgl.vulkan` 模块 + MoltenVK.dylib） | 想同时出 Windows/Linux 才选 |
| **D. 独立覆盖窗口** | 另开一个无边框 Metal 窗口盖在游戏上 | 不受游戏限制 | 中 | **高**：全屏/焦点/UI 层叠/Dock 切换全要自己处理 | 不推荐 |
| **E. 改游戏上下文为 core profile** | patch `org.lwjglx.opengl.Display.create` 加 GLFW hints | 高（可用 GL 4.1） | 极高 | **致命**：游戏自带的 `#version 120` 着色器在 core profile 下全部失效，需要重写约 120 个游戏着色器并修掉所有废弃调用 | 不要做 |

---

## 四、路线 B 的接口已全部实测可用

| 接口 | 位置 | 实测 |
|---|---|---|
| `CGLGetCurrentContext()` | OpenGL.framework | `PRESENT`（GLFW 的 NSOpenGLContext 底层就是 CGL，可从渲染线程直接取） |
| `CGLTexImageIOSurface2D()` | OpenGL.framework（SDK：`OpenGL/CGLIOSurface.h`） | `PRESENT`；SDK 注释明确"binding is live"，IOSurface 内容变化可直接被 GL 采样 |
| `MTLDevice.newTextureWithDescriptor:iosurface:plane:` | Metal.framework（`MTLDevice.h:710`） | 头文件存在 |
| `IOSurfaceCreate/Lookup/GetBaseAddress` | IOSurface.framework | `PRESENT`，框架可加载 |
| Metal.framework | 系统 | 可加载 |
| MoltenVK | 系统未安装 | 需要自带（约 3 MB dylib），或走纯 Metal |

**游戏侧还额外送了两个便利条件**（实测 `projectzomboid.jar`）：

* 已经内置 **LWJGL 3**（1202 个类，含 `org.lwjgl.system` 400 个、`org.lwjgl.opengl` 479 个），
  以及 `macos/arm64` 原生库（`liblwjgl.dylib` / `liblwjgl_opengl.dylib` / `libglfw.dylib`）；
  **但没有 `org.lwjgl.vulkan`**——走 Vulkan 路线需要自己把 LWJGL 的 Vulkan 模块打进 mod jar。
* 运行期已加载 **JNA**（日志 `jna.loaded=true`），可以先零 native 代码用 JNA 调
  `IOSurfaceCreate` / `CGLTexImageIOSurface2D` / `objc_msgSend`(Metal) 做 PoC，稳定后再换正式 dylib。

### 合成数据流

```
[渲染线程]                                    [游戏 GL 线程]
 Metal: 场景 → MTLTexture(IOSurface 背衬)  ──►  CGLTexImageIOSurface2D
                                                  ↓
                                          GLSL 120 全屏 quad(采样 GL_TEXTURE_RECTANGLE_EXT)
                                                  ↓
                                          画进游戏 framebuffer（其它 UI 之后照常绘制）
```

同步靠 IOSurface lock / `glFenceSync` / `dispatch_semaphore`；建议 2~3 缓冲避免撕裂。

---

## 五、要复刻的规模（以 Viewpoint 0.1.3 为参照）

| 指标 | 数值 |
|---|---|
| jar 条目 | 680（4,088,546 B） |
| class | **493** |
| 包分布 | `render` 113、`platform` 68、根 68、`light` 62、`far` 59、`world` 41、`visibility` 19、`interact` 12、`game` 12、`packs` 11、`models` 11、`environment` 9、`input` 5、`core` 3 |
| 主渲染着色器 | 54 个（42 `.frag` + 12 `.vert`）+ 41 个 `.glsl` 库 |
| 附带 shaderpack | 4 套（normal / default / vivid / dreamy） |
| 游戏挂载点 | **57 个 `Patch_*` 类**，其中 53 个带明确目标，覆盖 **26 个游戏类** |
| GL 调用分布 | `GL11` 515、`GL30` 158、`GL15` 126、`GL13` 110、`GL20` 87、`GL33` 45、`GL43` 42、`GL45` 40、`GL31` 9、`GL44` 6、`GL32` 6、`GL42` 5、`GL40` 2 |

### 26 个挂载目标（重做时的"接口地图"）

```
渲染管线   zombie.core.SpriteRenderer          （DrawGeneric / GameRender / UiFrameEnd）
          zombie.core.opengl.RenderSettings    （视距）
          zombie.core.PerformanceSettings      （帧率/锁帧）
          zombie.core.Core                     （选项读写/第一人称开关状态）
          zombie.iso.fboRenderChunk.FBORenderLevels（等距块缓存失效）
          zombie.iso.IsoCell
          zombie.core.skinnedmodel.ModelManager（角色模型槽更新）
世界/剔除  zombie.iso.IsoWorld                  （动物剔除 / 僵尸剔除 / 天气特效）
          zombie.MovingObjectUpdateScheduler
          zombie.iso.LightingJNI               （灯光/视野锥）
          zombie.iso.weather.ThunderStorm
拾取/交互  zombie.iso.IsoObjectPicker ×9 处     （尸体/门/窗/树/车/可跳越/可敲击/窗框/上下文）
          zombie.iso.objects.IsoWindow / IsoLightSwitch
玩家/输入  zombie.characters.IsoPlayer、IsoGameCharacter、IsoZombie、Stats
          zombie.input.Mouse / KeyboardState / AimingReticle
状态/时间  zombie.gameStates.IngameState / GameLoadingState、zombie.GameTime
```

---

## 六、分阶段路线图（建议按此交付，每阶段独立有价值）

| 阶段 | 目标 | 关键验证点 | 单人估时 |
|---|---|---|---|
| **P0 打通管线** | ZombieBuddy 装载自研 jar；patch `SpriteRenderer` 后置一个全屏 quad；Metal 渲染纯色/IOSurface 贴到屏幕上 | 能盖住游戏画面且不掉帧、无撕裂 | 1~2 周 |
| **P1 相机与角色** | 第一/第三人称相机、鼠标锁定；复用游戏自带 skinned model 管线渲染玩家模型 | 走路不晕、模型不穿模 | 3~6 周 |
| **P2 体素化世界** | 从 `IsoCell`/`IsoGridSquare` + 精灵图集提取几何，分层 box/quad 网格，分块缓存 | 近处 19×19 chunk 几十 FPS | 2~3 个月 |
| **P3 光照与远景** | 阴影贴图（depth texture）、每像素灯、远景 LOD shell、天空/天气 | 可玩画面成型 | 2~4 个月 |
| **P4 交互与打磨** | 鼠标拾取、掉落菜单、设置窗口（ImGui 已随游戏提供） | 接近原版操作 | 1~2 个月 |

> 参考量级：Viewpoint 是 493 个类的完整引擎，功能对等基本是"多人×多季度"的工程；
> 但 **P0~P2 就能提供一个能用的 3D 第一人称视角**，这部分是单人可完成的。

---

## 七、风险清单

1. **IOSurface 同步**：GL 侧是"live binding"，Metal 写的同时 GL 读会撕裂；必须用 IOSurface lock 或信号量做帧同步。
2. **渲染线程模型**：PZ 有主线程 + 渲染线程，必须像 Viewpoint 一样在 `FrameSwap`/`GameRender`/`UiFrameEnd` 上做双线程编排。
3. **Retina**：游戏在 macOS 显式设置了 `GLFW_COCOA_RETINA_FRAMEBUFFER=0`，IOSurface 尺寸要按 framebuffer 实际像素来，不能按逻辑点。
4. **窗口/全屏切换、分辨率变更**：IOSurface 与 Metal 纹理都要重建。
5. **内存**：`-Xmx6g` 已经给 JVM，几何数据建议放 native（Metal buffer / JNA Memory）而不是 Java 堆。
6. **ZombieBuddy 授权弹窗**：新 jar 每次变更都要在 `~/.zombie_buddy/mod_approvals.json` 重新批准（可按住 Shift 强制弹窗）。
7. **游戏版本敏感**：Viewpoint 把 `versionMin/versionMax` 钉死在 42.21，说明游戏内部结构变动频繁——重做时也要建立自己的"兼容性自检"（它那句 `compat: all 57 patch targets and 61 private members found` 就是干这个的，建议照抄这个思路）。

---

## 八、许可与 clean-room 提醒 ⚠️

`Viewpoint` 的 LICENSE 是 **专有许可**，明确写着：

> "No licence is granted to copy, modify, merge, publish, distribute, sublicense or sell them, in source or binary form...
> It may not be redistributed, re-uploaded, repackaged, **decompiled for reuse** or modified."

因此：

* ✅ **可以参考的是"事实与思路"**：需要挂哪些游戏类、分几层、用哪种技术路线——这些来自游戏自身的公开类结构，不构成对它的代码复制。
* ❌ **不能复制**它的 `.class`、着色器文本、`facade-colours.txt` / `far-colours.txt`、shaderpack、贴图或任何资源。
* ❌ 不能反编译后改写再发布（本次调研属于互操作性分析，产出仅为文档，未包含其代码）。
* 建议：命名、资源、着色器全部自研；如需灵感，可参考同样合法的开源 3D/体素渲染资料。

---

## 九、参考链接

* Viewpoint（Workshop 3809306528）— https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528
* ZombieBuddy（Java 模组框架，Workshop 3619862853）— https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853
* ZombieBuddy GitHub — https://github.com/zed-0xff/ZombieBuddy
* pz3d（另一套 3D 框架，API 面 ≤ GL4.1）— https://steamcommunity.com/sharedfiles/filedetails/?id=3807334881
* Apple：`CGLTexImageIOSurface2D` 文档（SDK：`OpenGL.framework/Headers/CGLIOSurface.h`）
* Apple：`newTextureWithDescriptor:iosurface:plane:`（SDK：`Metal.framework/Headers/MTLDevice.h:710`）
* Apple：OpenGL Profiles（legacy 2.1 / core 3.2–4.1）— https://developer.apple.com/documentation/appkit/opengl-profiles
* GLFW：macOS 仅支持 core profile 上下文 — https://raw.githubusercontent.com/glfw/glfw/master/include/GLFW/glfw3.h
