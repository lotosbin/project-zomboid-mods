# bin2_viewpoint / ViewpointMac

面向 **macOS / Apple Silicon** 的 3D 视角模组工程（Project Zomboid Build 42）。

它不是为了替代 [Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528)，
而是回答一个具体问题：**在 macOS 上，我们到底能不能把自研渲染塞进游戏的帧里。**
答案是能 —— 本工程把它做成了可运行、可验证的第一步，并把平台能力探测固化下来。

背景分析见：

* [`docs/viewpoint-macos-apple-silicon.md`](../../docs/viewpoint-macos-apple-silicon.md) —— 为什么现成 Viewpoint 在 macOS 上跑不起来
* [`docs/pz-3d-mod-macos-feasibility.md`](../../docs/pz-3d-mod-macos-feasibility.md) —— 重做的可行性与三条技术路线

---

## 目录结构

```
bin2_viewpoint/                                  ← Steam 工坊物品目录（已软链到 ~/Zomboid/Workshop）
├── workshop.txt                                 ← 工坊发布信息
├── preview.png
├── build.sh                                     ← 编译打包脚本
├── README.md
└── Contents/mods/ViewpointMac/                  ← 模组本体
    ├── 42.21/                                   ← B42 版本目录（必须有，否则模组管理里看不到）
    │   ├── mod.info                             ← 含 require=\ZombieBuddy / javaJarFile / javaPkgName
    │   ├── poster.png
    │   ├── src/viewpointmac/                    ← Java 源码（随模组分发，便于社区维护）
    │   │   ├── Main.java              入口：读配置、兼容性自检
    │   │   ├── Vp.java                常量、日志、路径
    │   │   ├── VpConfig.java          ~/Zomboid/viewpointmac.properties
    │   │   ├── Compat.java            反射式兼容性自检（缺成员就整体禁用）
    │   │   ├── GlProbe.java           渲染线程上的 GL 能力探针（含就地着色器编译）
    │   │   ├── FrameStats.java        帧时间统计
    │   │   ├── Overlay.java           GL 2.1 覆盖层（GLSL 1.20 + VBO，失败回落立即模式）
    │   │   ├── Mat4.java              P1：4x4 矩阵（透视 / lookAt / 乘法，列主序）
    │   │   ├── GameWorld.java         P1：反射读取玩家世界坐标与朝向
    │   │   ├── Camera.java            P1：第一/第三人称相机与 MVP
    │   │   ├── Scene3D.java           P1：3D 管线（MVP uniform + 深度 + 流式 VBO）
    │   │   ├── RenderHook.java        帧边界逻辑与熔断
    │   │   ├── Report.java            ~/Zomboid/viewpointmac-report.txt
    │   │   ├── Patch_PostRender.java  ZombieBuddy 挂载点
    │   │   └── LuaApi.java            暴露给 Lua 的 API
    │   └── media/
    │       ├── java/client/ViewpointMac.jar     ← 构建产物
    │       └── lua/client/ViewpointMac/ViewpointMac.lua
    └── common/                                  ← 跨版本共享层（当前仅占位）
```

> ⚠️ **重要**：B42 需要 `<mod>/<版本>/`（如 `42.21/`）或 `<mod>/common/` 这样的版本子目录；
> 把 `mod.info`/`media` 直接放在模组根目录（B41 的扁平写法）在本机实测**不会出现在模组管理里**。
> 这也是本项目从 pz3d（`42.20.4/`）与 Viewpoint（`42/` + `common/`）学到的第一条经验。

---

## 已实现的功能

### P0：把渲染管线打通

| 功能 | 说明 | 验证方式 |
|---|---|---|
| **渲染钩子** | `@Patch(zombie.core.SpriteRenderer#postRender)` 的 `OnEnter`/`OnExit`。该方法尾部才真正提交本帧绘制（`RingBuffer.render()`），返回时画面尚未交换，是叠加自绘内容的正确位置 | 日志 `render hook armed on ...` |
| **兼容性自检** | 反射校验 3 个必需类 + 3 个必需方法 + 1 个可选字段，缺失即禁用注入，绝不把游戏搞崩 | 日志 `compat: all 6 patch targets and members found` |
| **GL 能力探针** | 在**渲染线程**首帧读取 `GL_VERSION/RENDERER/VENDOR/GLSL`、41 项关键扩展、5 项硬件上限，并**就地编译** `#version 120` 与 `#version 330` 测试着色器 | `~/Zomboid/viewpointmac-report.txt` |
| **GL 覆盖层** | 自绘面板：帧时间柱状图 + 能力指示块 + 状态色边框。走 GLSL 1.20 着色器 + 流式 VBO；编译失败自动回落固定管线立即模式 | 游戏内左上角可见（用调试面板开关） |
| **状态 HUD** | 用游戏自身字体通道画一行运行状态（Java 只管 GL，文字交给游戏） | 游戏内文字行 |
| **Lua API** | `ViewpointMac.status/backend/shaderProbe/toggleOverlay/writeReport/fps/...` | `console.txt` 里的 `[ViewpointMac]` 行 |
| **熔断** | 渲染钩子连续异常 3 次即永久关闭并写报告，避免拖垮游戏 | 日志 `render hook disabled after 3 errors` |

### P1：相机 + 真正的 3D 管线

| 功能 | 说明 | 验证方式 |
|---|---|---|
| **矩阵与透视** | `Mat4` 自实现透视/lookAt/乘法（列主序，可直接喂 `glUniformMatrix4fv(..., false, ...)`） | `~/Zomboid/viewpointmac-report.txt` 的 `camera:` 行 |
| **世界数据桥** | `GameWorld` 用反射读 `IsoPlayer.getInstance()/getX/getY/getZ/getForwardDirectionX/Y/getLookAngleRadians`。用**朝向向量**而不是角度，避免猜 PZ 的角度基准 | 日志 `world bridge ready: zombie.characters.IsoPlayer (reflection)` |
| **第一/第三人称相机** | 眼高、FOV、俯仰、跟随距离可配；可在调试面板运行时切换 | 报告 `camera: eye=(...) yaw=... pitch=... mode=...` |
| **3D 绘制通路** | `Scene3D`：GLSL 1.20 + `uniform mat4 uMvp` + 深度缓冲 + 流式 VBO，一次上传分两次绘制（先线后三角） | 报告 `pipeline: lines=N tris=M ...` |
| **可见几何** | 跟随玩家的地面网格（1 单位 = 1 地块格，每 8 格加亮）、X/Y/Z 坐标轴、玩家线框盒、**世界原点 (0,0) 标记 + 玩家到原点的连线** | 用调试面板开关；走动时原点标记会相对移动 |
| **深度策略** | 不清理游戏的深度缓冲，改用 `glDepthFunc(GL_ALWAYS)` + 写深度：几何永远压过已画画面，但彼此仍有正确遮挡 | 状态成对保存/恢复（含 program / VBO / depthFunc / depthMask / blend / vertex attrib / **viewport**） |
| **整屏尺寸解析** | `GameScreen` 显式把 viewport 设成整屏再绘制，不沿用渲染线程残留的偏移视口 | 报告 `screen=1920x1022 source=lwjglx.Display (game viewport was ...)` |

> 原点标记是 P1 最关键的验证物：**如果你走动时它相对后退，说明读到的确实是真实世界坐标**，
> 而不是角色局部坐标 —— P2 的地块体素化完全建立在这个前提上。

### P3.1：接入 PZ Voxel Studio 模型包（真 3D 几何）

原版没有物件的 3D 几何，所以这里接**第三方模型包**（Workshop `3810302175` / `3810051489`，本地 408 MB）：

| 项 | 实测 |
|---|---|
| 包结构 | `common/media/voxel-studio/package*.properties` + `<uuid>/r1-*/model.obj` + `model-rp.mtl` + `*.png` |
| 规模 | **16 个包、9,187 个模型、10,110 条 bind**、13,743 张 PNG |
| 清单格式 | `model.<key>=<相对路径>` / `bind.<精灵名>=<key>,<rot>,<ox>,<oy>,<oz>,<scale>` |
| OBJ 约定 | 文件头自带 `# PZ Voxel Studio — Z up, tile units` —— 与我们的世界坐标完全一致，无需换算 |
| 贴图 | MTL 的 `map_Kd <png>`，小尺寸体素贴图 |
| 解析校验 | 10,110 / 10,110 条 bind 全部能定位到真实 `.obj` 文件 |

实现：
* `VoxelPack` —— 扫描 `Zomboid/mods`、`Zomboid/Workshop`、Steam 工坊目录（也可用 `voxelPackDir` 指定），建 `精灵名 → 模型` 表；
* `ObjMesh` —— 极简 OBJ 解析（`v/f/vt`，扇形三角化），把 bind 的旋转/缩放/位移**烘焙进顶点**，输出与 `Scene3D` 相同的 9 float 格式；
* `ModelCache` —— LRU（192 个模型 + 贴图）、**每帧最多加载 4 个**避免集中读盘卡顿，超限自动释放 VBO/贴图；
* 渲染 —— 命中 bind 的物件**不再画盒子**，改画真模型（每个实例一次 `glDrawArrays`，MVP = 相机 × 平移）。

### 地面与天空

* **地面**：新增 `FLOOR` 分类（只有地板、不算实心的地块），铺 0.03 高的平板并贴原版地板精灵；`floors_rugs_*`、`street_*` 这类命中模型包的还会换成模型。
* **天空**：渐变天空盒（以相机为中心的大立方体，天顶蓝 → 地平线亮 → 地面灰），最先绘制作为背景。
  用**原版天空/云层贴图**是下一步（需要反射 `zombie.iso.sprite.SkyBox`）。

### 关于"原版材质是不是 3D 的"

**不是。** 实测游戏本体的资源构成：

| 资源 | 实际形态 |
|---|---|
| 世界物件（墙 / 地板 / 家具 / 树 / 栅栏） | **2D 等距精灵图集**（`media/textures/`），**没有 3D 几何** |
| 角色、载具 | **真 3D 模型**：`media/models/` 46 个模型定义 + `media/anims_X/` 2209 个 `.x` 动画（全库 109 个 `.x` + 23 个 `.fbx`） |

这就是 **Viewpoint 必须额外依赖第三方 `PZVoxelStudio` 模型包**（Workshop `3810302175`）的原因 ——
原版根本没有物件的 3D 几何可用。

所以"用原版材质"能做的正确事情是：**把原版精灵贴图当作我们体素的纹理**（本版已实现）。
想要物件真正的 3D 外形，只有两条路：
1. 挂第三方体素/模型包（Viewpoint 生态的 `PZVoxelStudio`，已经装了）；
2. 自己把 2D 精灵"挤出"成体素 —— 这正是我们正在做的方向。

### 改了 Java 一定要重启游戏（血泪教训）

Project Zomboid 会**热重载 Lua 文件**（回到主菜单、切存档时会重跑），但**已加载的 Java class 不会更新**。
于是会出现"Lua 是新的、jar 是旧的"这种混合状态：新 Lua 去调老 jar 里不存在的方法，只能拿到 `nil`，
而且看起来像是模组写错了 —— 实测就是这么被坑了一轮（`voxel: nil`，`world tiles` 一行日志都没有）。

现在的防呆措施：
* Lua 侧 `LUA_VERSION` 与 Java 侧 `Vp.VERSION` 在启动时握手，不一致直接打印 `VERSION MISMATCH: jar=... lua=...`；
* `call()` 不再静默返回 nil，而是打印 `java method 'xxx' is not exposed - the JAR is older than this Lua file...`；
* 启动时列出 Java 实际暴露给 Lua 的方法清单：`java API (N): status:string toggleVoxel:function ...`。

### 快捷键为什么不用功能键

macOS 默认把 **F9~F12 当媒体/系统键**（F10 静音、F11 显示桌面、F12 音量+），会被系统抢先吃掉，
游戏收不到。

**现在只保留一个快捷键**（1.9 起）：


| 快捷键 | 作用 |
|---|---|
| `Ctrl+Alt+D` | **打开/关闭调试控制面板**（唯一的快捷键，所有开关都在面板里）|

实现在 `media/lua/client/ViewpointMac/ViewpointMac.lua` 的 `PANEL_KEY`（想换键改那一处）。
如果运行环境取不到 `isCtrlKeyDown`/`isAltKeyDown`（游戏改动），代码会自动退回 `F9/F10/F12` 兜底表。

### 三条必须记住的"自绘内容"经验

1. **顶点属性是全局状态**：macOS 只有 GL 2.1 兼容上下文（没有 core VAO），`glVertexAttribPointer`
   改的是全局属性。若用 `glGetAttribLocation` 拿到的 0/1 号槽位，就会把游戏的顶点指针指向我们的 VBO，
   而游戏画面变黑、我们的覆盖层照常显示。现在两套管线都在 link 前用 `glBindAttribLocation`
   把属性钉到 **14/15**（`Scene3D` 用 12/13），并用 `GlAttribState` 成对保存/恢复启用状态。
2. **永远不要在 Lua 事件里抛异常**：`Events.OnPostUIDraw` / `OnPostRender` 这类在
   `UIManager.render` 内部触发的事件，一旦抛出 Java 异常，整条 UI 渲染链会被中断
   （表现就是菜单全黑、背景动画卡住）。所有会碰游戏 API 的 Lua 代码都要 `pcall` 包住，
   **并且第一次失败就要彻底停用**。
3. **不要沿用渲染线程残留的 viewport**：`postRender()` 结束时 viewport 往往还停在
   等距相机的偏移视口上（实测原点被平移、尺寸比窗口小）。沿用它会让自绘内容整体缩到角落
   （第一版实测：3D 网格挤在左下角、2D 面板不在左上角）。自绘前必须 `glViewport(0,0,W,H)`
   显式设成整屏、画完再还原；`W/H` 由 `GameScreen` 依次从
   `org.lwjglx.opengl.Display` → `zombie.core.Core` → 当前 viewport 解析。

### P2：世界体素化

| 功能 | 说明 | 验证方式 |
|---|---|---|
| **世界数据桥** | `WorldTiles`：反射走 `IsoWorld.instance → getCell() → IsoCell.getGridSquare(x,y,z) → IsoGridSquare.getWall()/isSolid()`，句柄全缓存，错误计数到上限自动停用 | 日志 `world tiles bridge ready: IsoWorld/IsoCell/IsoGridSquare (reflection)` |
| **预算式采样** | `VoxelWorld`：每帧只采 `voxelBudget` 格，几帧补齐 (2R+1)² 窗口；记录的是**世界坐标**，补采期间旧数据仍在正确位置 | 报告 `voxel world : sampled=N/1089 boxes=M` |
| **网格缓存** | 只有数据版本变化时才重算顶点，顶点数组常驻，`Scene3D` 每帧直接 `System.arraycopy` 追加进自己的批次 | `overlay=0.0xx ms` 依旧极低 |
| **原版材质** | `TileTextures` 反射取 `IsoSprite.texture` → `Texture.getTextureId().getID()`（GL 贴图）+ `getXStart/getYStart/getXEnd/getYEnd`（图集 UV 矩形），按材质**分桶**绘制（每桶一次 `glDrawArrays`）。无贴图时退回 1x1 白贴图 + 纯色 | 报告 `tile textures : slots=.. resolved=.. missed=..` |
| **瓦片分类** | 读游戏自己的 `IsoPropertyType` 枚举（反射 `PropertyContainer.has(...)`）区分 **墙 2.7 / 门 2.1 / 高栅栏 1.9 / 窗 1.5 / 矮栅栏 1.0 / 家具 0.9**，颜色也分开 | 报告 `voxel world : ... (wall=N solid=N feature=N)` |
| **背面剔除** | 体素面的绕序按"外侧看逆时针"生成，绘制时开启 `GL_CULL_FACE/BACK`：站在方块内部时内侧被剔掉，不会把屏幕糊成一块颜色 | 走进墙里画面不会变成纯蓝 |
| **距离衰减** | 体素透明度按到玩家的距离平方衰减（0.10~1.0），远处淡出；相机所在那一格直接跳过 | 视野边缘自然淡出 |
| **线框模式** | `voxelWireframe=true` 改成 12 条棱的线框盒，完全不遮挡游戏画面，适合核对采样是否正确 | 配置项切换 |

### 已知限制（P0~P2 阶段，故意保留）

* **帧计数可能偏大**：`postRender` 是渲染线程的"状态提交"入口，一帧内可能被调用多次
  （方法里有 `states.getRendering()` / `waitingForRenderState` 机制）。后续会改挂到真正的
  帧交换点（`org.lwjglx.opengl.Display#update`）来修正 FPS 统计。
* **覆盖层可能被重复叠加**：同一原因，多次调用会让半透明底板颜色偏深；不影响可读性，
  也是判断调用次数的直观信号。
* **相机朝向来自角色**：目前没有接管鼠标锁定，方向跟随角色朝向（第三人称是"角色背后"）。
  自由视角（鼠标 yaw/pitch）排在 P2 之后。
* **还没有世界几何**：地面网格与原点标记只是坐标参照，P2 才会从 `IsoCell` 提取真实地块。
* **主菜单也会显示 3D 调试场景**：`IsoPlayer.getInstance()` 在菜单期也返回对象，所以网格照样会画。
  对 P1 来说这是"随时可验证"的优点；P2 接入真实地块后会改成只在存档内绘制。

### 为什么 GL 代码必须放在渲染线程

模组加载（`Main.main`）跑在主线程，那时 GL 上下文不在当前线程，任何 `glGetString` 都会失败。
所以探针与绘制都做成"渲染线程首帧惰性执行"，这也是整个方案能成立的关键前提。

### 为什么只用 GLSL 1.20

macOS 上 PZ 建的是 **OpenGL 2.1 legacy 上下文**（实测 `GL_VERSION = 2.1 Metal - 91.7`，
`#version 330` 编译直接失败，4.3~4.5 的函数在系统框架里根本不存在）。
本模组因此把 GL 代码压到 2.1 可用的最小集合；要恢复"现代渲染能力"，
按可行性文档走 **Metal/Vulkan + IOSurface + `CGLTexImageIOSurface2D`** 合成路线，
GL 只保留最后一步 blit。

---

## 构建

```bash
cd bin2_viewpoint
./build.sh          # 编译 src/ → media/java/client/ViewpointMac.jar
./build.sh clean    # 清理
```

前置条件：

* JDK 17+（`javac`）。游戏自身的类文件是 Java 25 格式，**不**参与编译——
  本模组对游戏类的访问全部走反射，编译期只依赖 `org.lwjgl.*`（Java 8 字节码）与 ZombieBuddy 的注解。
* ZombieBuddy 已安装：`<游戏>/Project Zomboid.app/Contents/Java/ZombieBuddy.jar`

可覆盖的环境变量：`PZ_JAVA_DIR`、`ZB_JAR`、`JAVAC`、`JAR`。

---

## 安装与测试

1. **确认 ZombieBuddy 就位**（一次性）：
   * `Project Zomboid.app/Contents/Java/ZombieBuddy.jar` 存在；
   * Steam → Project Zomboid → 属性 → 启动选项：
     `-javaagent:ZombieBuddy.jar -Xmx6g -Xms2g --`（末尾 `--` 不能省）。
2. **本地工坊物品已链接**：
   ```bash
   ls -l ~/Zomboid/Workshop/bin2_viewpoint
   # -> /Volumes/.../project-zomboid-mods/bin2_viewpoint
   ```
   游戏会把它当作本地工坊物品扫描（`SteamWorkshop.getStageFolders()`）。
3. 启动游戏 → **模组管理** → 勾选 **ViewpointMac**（ZombieBuddy 必须同时启用）。
4. 首次加载 Java 模组时 ZombieBuddy 会弹窗要求授权，点 **Yes**（确认 JAR 的 SHA-256）。
5. 进入游戏后：
   * 左上角出现带边框的面板（帧时间柱状图 + 能力指示块）；
   * `Ctrl+Alt+D` 打开调试面板，所有开关都在面板上；
   * 查看 `~/Zomboid/viewpointmac-report.txt` 与 `~/Zomboid/console.txt`（检索 `[ViewpointMac]`）。

### 期望看到的报告要点（Apple Silicon）

```
backend          : GL_LEGACY_21
shader #version 120 : OK
shader #version 330 : FAIL | ERROR: 0:1: '' :  version '330' is not supported
extensions absent (..):
  - GL_ARB_direct_state_access
  - GL_ARB_buffer_storage
  - GL_ARB_compute_shader
  ...
```

如果 `#version 330` 是 OK，说明运行环境已经不是 2.1 legacy —— 那才轮到讨论"进程内现代 GL 渲染"。

---

## 2.2：按日志实测修 bug（自动读日志的第一次收获）

**日志文件自己会说话** —— 这一轮我没让你复制粘贴，直接读 `~/Zomboid/ViewpointMac.log`，
一次拿到 6 个确定问题：

| 日志证据 | 结论 | 修复 |
|---|---|---|
| `raw=(0.000,0.258)-(0.123,0.320)` 全在 0~1 | UV **本来就是归一化**的 | 归一化逻辑保留（防御），但确认没走错 |
| `sprite=126x64` | **地板确实是 2:1 等距菱形** | 菱形重映射方向正确；**V 默认改成 `isoflip`**（用户反馈上下反） |
| `charModels unavailable (draw: InvocationTargetException)` | **角色绘制抛异常，而我把根因吞了** | 现在会**层层 unwrap 打出真正的 cause**；面板重新打开该功能会**清掉失败状态重试** |
| `models=192/192 loaded=4089 evicted=3897 deferred=18487` | LRU 太小 → **疯狂换入换出**（掉帧 + 模型闪烁） | 缓存 192 → **1024**，每帧加载 4 → **16** |
| `boxes=8192`（=上限，世界被截断）/ `slots=160/160` 满 | 容量不够 | 盒子 8192 → **20000**，贴图槽位 160 → **512** |
| `tree=8 furniture=4315` | **树木分类基本没命中**：靠类名判断对树/灌木没区分度 | 改成**先按精灵名判断**（`jumbo/tree/pine/birch` → 树，`bush/hedge/shrub/plant/fern` → 灌木） |

**外加你报的三个"反了"**：
* **视角方向反了** → `invertMouseY` 默认 **true**（面板可切）；
* **贴图方向反了** → 模型贴图 PNG 上传的上下翻转改成**可配置**，默认关（`flipModelTextureV`）；
* **树木上下反了** → 同上是贴图 V 的问题（树是带树贴图的广告牌模型），一并解决。

## 2.2 的快捷键（就两个）

| 键 | 作用 |
|---|---|
| `Ctrl+Alt+V` | **切原版视图 / 3D 视图**（等价 `coverVanilla`；切到 3D 时自动确保天空盒开着，否则盖不住） |
| `Ctrl+Alt+D` | 打开/关闭调试控制面板 |

面板里也加了 `Toggle view: vanilla / 3D` 按钮，以及 `Flip model texture V` / `Invert mouse Y` 开关。

## 2.1：P6/P7/P8 一起推进

### P8 操作：角色朝向跟随 3D 视线（新）

自由视角打开后，如果不管朝向，就会"你看东边、角色朝北开枪"。
游戏提供了可写接口，我们每帧把相机 yaw 喂进去：

```java
IsoGameCharacter.setForwardDirection(float dx, float dy)   // 反射，每帧一次
```

* 只在"自由视角开 + 存档内 + `controlFacing` 开"时生效；
* 失败自动禁用并打一次日志，绝不影响游戏；
* 面板开关：`Character follows 3D view (aim)`。

### P7 人物与动作：完整 3D 视图下自动接管

一键 PRESET 会把 `characterModels` 打开，此时：
* 世界绘制阶段**原版的角色 GL 调用被接管**（`Patch_SkipVanillaDraw`，四条条件全满足才生效）；
* 我们用**自己的相机**（`Camera.projection()/view()` → `ModelCamera` 子类 → 矩阵栈）把它们画出来；
* 模型、动画、手持物全部来自原世界，我们只负责相机。

### P6 世界几何：容量放开

* PRESET 把采样半径从 16 提到 **24**（"完整的世界"需要更远），采样预算提到 512；
* 模型实例上限 1024 → **4096**，盒子 4096 → **8192**，网格缓冲 1.5M → **3M float**。

### 仍然没做到的（P6 的真难点）

| 缺口 | 说明 |
|---|---|
| **多层 z** | 现在只采样玩家所在的一层：**楼上的地板、屋顶、地下室**都没有 3D 几何。要做需要按 z 分层采样（内存/预算都要重算） |
| **屋顶/天花板** | 同上 |
| **水域** | 游戏的水面是专门渲染器，没接 |
| **地面 UV** | 仍是等距菱形精灵贴到平板上，四档模式里挑一个（`iso` / `isoflip` / `inset` / `plain`） |
| **光影/天气** | 完全没有，所以纯 3D 视图会显得平 |

## 2.0.1：用"遮住"代替"跳过"（零风险的 Viewpoint 视图）

用户的关键简化：**不需要 patch 原版的渲染，用我们自己的 3D 把它盖住就行。**

于是：
* **删掉 `Patch_SkipWorldDraw`** —— 现在只剩 3 个补丁，且都不涉及跳过世界绘制；
* 天空盒是包围相机的**不透明**立方体，先画它 → **整屏盖住原版画面**，
  之后的地面/物件/角色再叠在上面 —— 这就是"遮住"，**完全不动游戏渲染管线**；
* 覆盖模式下相机必须用**我们自己的**（没有原版画面可对齐）；
* 顺手修一个会让"遮住"漏光的细节：天空盒半边长原来是 180，
  对角线 180·√3 ≈ 312 **超过远裁剪面 240** → 部分面被裁掉会出现空洞。
  改成 100（对角线 173 < 240），**保证全屏无缝**。

| 模式 | `coverVanilla` | `alignVanillaView` | 相机 | 效果 |
|---|---|---|---|---|
| **叠加对照**（默认） | false | true | 游戏世界 3D 相机 | 模型包 3D 原位替换精灵，可与原版对比 |
| **3D 世界视图** | true | false | 我们自己的相机 | 不透明 3D 盖住原版 = Viewpoint 那样的纯 3D 视图 |

面板一键：**`PRESET: FULL 3D (Viewpoint-like)`**（现在走的是"覆盖"而非"跳过"）。

## 2.0：完整 3D 路线（Viewpoint 等价）—— 目标与路线图

**目标**：在 macOS 上用 3D 渲染**原来的完整世界**（地图、模型、人物、动画、操作），
也就是把上游 Viewpoint 的能力在这台机器上重建出来。

### 核心约束（必须讲清楚）

> **"完整世界用 3D 渲染" ⟺ 不再绘制原版的等距世界。**

同一个画面里放两套投影（等距精灵 + 我们的 3D）永远对不齐 —— 之前所有 UV/摩尔纹/
位置错位问题都是这个矛盾的产物。所以完整 3D **必须**跳过原版世界绘制。

1.3.1 那次黑屏事故的根因是**把主菜单误判为游戏内**，不是这个方向本身有问题；
现在用官方 `GameWindow.isIngameState()` 判定，主菜单阶段该补丁**不生效**。

### 两种模式（面板一键切换）

| 模式 | `hideVanillaWorld` | 相机 | 用途 |
|---|---|---|---|
| **叠加对照**（默认） | false | 对齐游戏世界 3D 相机 | 模型包 3D **原位替换**精灵，可与原版逐像素对比 |
| **完整 3D** | true | 我们自己的相机 | Viewpoint 等价：整个世界由我们渲染 |

面板新增 **`PRESET: FULL 3D (Viewpoint-like)`** 一键切换：跳过原版世界 + 用自己的相机
+ 打开地面/模型/贴图/角色/天空（原版不画了，这些必须我们补上）。

### 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1 渲染挂载与 GL 探针 | 注入渲染线程、能力自检 | ✅ |
| P2 世界数据 → 几何 | 地块采样、物件分类、精灵贴图 | ✅ |
| P3 模型包 | 9,187 模型 / 10,110 bind 的映射与加载 | ✅ |
| P4 骨骼模型与相机注入 | `ModelCamera` 子类（ByteBuddy）+ 矩阵栈 | ✅ 机制可用 |
| **P5 完整 3D 模式** | 跳过原版世界、我们渲染世界 | ⏳ **本轮打通开关** |
| P6 世界几何补全 | 墙/地板/屋顶/水域/植被全部用 3D（模型包 + 挤出） | ⏳ |
| P7 人物与动作 | 玩家/僵尸用我们相机渲染，动画/手持物跟随 | ⏳ 机制就绪 |
| P8 操作 | 鼠标视角、瞄准、第一人称交互 | 🟡 鼠标视角已有 |
| P9 画面档次 | 光照/阴影/天气/雾；GLSL 1.20 上限或 Metal 后端 | ⏳ |

## 1.10：与游戏视图对齐 —— 2.5D 物件原地变成 3D

**架构转向**（这是把之前那堆 UV/相机麻烦一次性消掉的关键）：

之前我们的 3D 用**自己的透视相机**画在游戏画面上 → 同一个画面两套投影 →
于是要重映射菱形 UV、地面摩尔纹、角色画两遍、模型位置对不上……全是叠加层自找的。

现在改成：**我们的 3D 直接用游戏给世界 3D 模型用的那套相机矩阵**：

```java
ModelCamera.instance.Begin();                          // 让游戏把世界 3D 相机设好
glGetFloatv(GL_PROJECTION_MATRIX) / (GL_MODELVIEW)     // 机制无关地抓下来
ModelCamera.instance.End();                            // 还原
mvp = projection * view;                               // 我们的几何用它
```

* 用 `glGetFloatv` 而不是读 `Core` 的矩阵栈，是因为**不管游戏用什么机制设置矩阵都能抓到**；
* 结果：模型包的真 3D 物件**精确落在它在 2.5D 里对应的精灵位置上** = 原位替换，
  **不再需要任何地面/精灵 UV 重映射**；
* 抓不到矩阵 → 自动退回我们自己的相机，功能不会因此失效。

配套默认值（迁移 v6 会强制）：`alignVanillaView=true`、`voxelFloor=false`、
`characterModels=false`、`entities=false` —— 因为**在对齐视图里，游戏自己画的地面/角色
本来就是正确且对齐的**，我们再去画只会盖住它们。面板上可随时改回来对比。

面板新增开关 **`alignVanillaView`**；报告里 `camera:` 行会显示
`[aligned to game world camera]` 或 `[own camera]`。

## 1.9.2：日志落文件 + 周期快照（不用再复制粘贴）

**问题**：排查时要用户从 console.txt 里捞日志再贴过来，很费事。

**做法**：日志**双写**到 `~/Zomboid/ViewpointMac.log`，并且**每 ~5 秒自动写一次状态快照**
（快照**只进文件**，不刷控制台）：

```
00:22:31.104 SNAP STATUS ViewpointMac 1.9.2 | hook=active | compat=ok | overlay=on | scene3d=on | ...
00:22:31.105 SNAP CONFIG scene3d=true overlay=on ... voxelRadius=16 floorUv=iso sensitivity=0.0025
00:22:31.105 SNAP SCENE  sky=0 lines=252 flat=6 voxel=... buckets=13 | sampled=1089/1089 boxes=... models=...
00:22:31.106 SNAP TEX    slots=37/160 resolved=... missed=... uv=normalized
00:22:31.107 SNAP TEXUV0 slot0 gl=123 sprite=64x64 atlas=1024x1024 raw=(256.000,512.000)-(320.000,576.000) -> uv=(0.25000,...)
00:22:31.107 SNAP CHAR   ready=5 drawn=5 skipped=0 failed=0 world=false camera=ViewpointCamera(...) | installs=..
```

* 启动时也会记录一条会话分隔 + 完整配置 dump + 日志路径；
* 文件超过 2 MB 自动轮转为 `ViewpointMac.log.1`；
* 写日志失败**绝不影响游戏**（全部 try/catch）。

**顺带修掉一个误报**：`TileTextures/Entities/CharacterModels/WorldTiles.describe()` 原来没先调
`init()`，导致开局打印成 `unavailable ()`（括号里空的）—— 看起来像功能挂了，其实只是还没初始化。

**已从现有 console.txt 确认**（1.9.1 那次运行）：
* 我们的模组**没有任何 WARN/ERROR**；
* ZombieBuddy 认到了**全部 3 个补丁类**：`Patch_PostRender` / `Patch_SkipVanillaDraw` / `Patch_WorldPassFlag`；
* 面板工作正常（日志里有完整的 option 开关记录）。

## 1.9.1：地面改实心 + 增加 V 翻转模式

用户截图里的"大片菱形"有两个叠加原因：

1. **地面是半透明的**（原来远处衰减到 0.35）。薄板在**掠射角**下互相叠加，
   会形成大块菱形摩尔纹，而且根本盖不住游戏地面。
   → 现在**半径内一律 alpha=1.0**，只有最外圈降到 0.75 做软边。
2. **V 轴方向可能反了**。等距菱形→正方形的映射里，"上顶点"取的是 `v1`，
   如果原版纹理的 V 原点在图像顶部，就会采到菱形外的透明区 → 四角漏底。
   → 新增 `isoflip` 模式（V 翻转），面板上循环对比：`iso → isoflip → inset → plain`。

**判断方法**（10 秒）：面板上点 `Ground UV mode` 循环四档。
哪一档地面变成**连续、不透明、没有菱形缝**的草地/沥青，就是对的。

## 1.9：单快捷键 + 调试控制面板 + 我们 3D 视角里的角色

### 1. 只保留一个快捷键

`Ctrl+Alt+D` 打开/关闭**调试控制面板**。原来那堆 `Ctrl+Alt+V/C/E/K/L/O/U/X/R` 全部移除 ——
功能没少，只是搬进面板里点。

面板（`ViewpointMacPanel`，用游戏自己的 ISUI 搭的）包含：

| 控件 | 作用 |
|---|---|
| 12 个开关 | 3D 场景 / 2D 覆盖层 / 鼠标视角 / 体素世界 / 地面平板 / 模型包 / 原版精灵贴图 / 让位原版 3D / **我们 3D 里的角色** / 实体方块 / 线框 / 天空盒 |
| `-` `+` | 体素采样半径（4~31） |
| `Ground UV mode` | 现场循环 `iso` / `isoflip` / `inset` / `plain` |
| `Camera mode` | 第一/第三人称 |
| `Write report` | 写报告文件 + 打印全部状态 |
| `Close` | 关面板 |

细节：**面板打开时会临时关掉"鼠标视角"**（否则光标被隐藏，按钮点不到），关闭时自动恢复原值。
所有改动都会即时落盘到 `viewpointmac.properties`。

### 2. 角色/僵尸画进**我们自己的 3D 视角**

1.5 的做法是"用游戏当前的相机再画一遍" → 只是复制原版那一份，还容易画歪（1.7.1 已关掉）。
这次换成**真正把我们的相机注入游戏模型渲染器**：

```
ByteBuddy 运行期生成 ModelCamera 子类
  Begin() → 我们把自己的 投影/视图矩阵压进游戏矩阵栈
            PZGLUtil.pushAndLoadMatrix(GL_PROJECTION, Matrix4f) + (GL_MODELVIEW, ...)
  End()   → popMatrix 还原
绘制角色时：
  ModelCamera.instance ← 我们的相机 → TextureDraw.drawModel + DrawQueued → 还原
```

* 为什么必须 ByteBuddy：`ModelCamera` 是 Java 25 字节码，我们编译期（JDK 17）引用不了，
  只能运行期生成子类；`org.joml.Matrix4f` 同样是 25，所以也走反射构造 + `set(float[])`。
* **不再出现两份角色**：世界绘制阶段原版的角色 GL 调用被接管掉。
  接管点是 `TextureDraw.DrawQueued(TextureDraw, ModelSlot)` —— **真正发 GL 的地方**，
  而准备与状态记账在调用方 `GenericSpriteRenderState.drawQueued` 里，
  所以跳过它**不会**破坏 `renderRefCount` / `numSprites` / `postRender` 的记账。
* 什么时候才接管（**四条同时成立**，任何一条不成立原版照常画，绝不会"角色消失"）：
  `功能开着` && `我们相机可用` && `当前处于世界绘制阶段` && `不是我们自己在画`。
  "世界绘制阶段"由 `Patch_WorldPassFlag` 打标记（只设标志位，不跳过任何东西），
  这样背包纸娃娃、主菜单的 3D 角色完全不受影响。

## 1.8：UV 自动归一化 + 地面模式现场切换

地面那些**菱形大得跨越十几格**，指向的不是"菱形映射"本身，而是 **UV 越界**：
如果 `Texture.getXStart()` 返回的是**像素坐标**（几十/几百），被当成归一化 UV 用，
采样就会越界 → GL_REPEAT 平铺 → 屏幕上出现跨十几格的重复菱形。

**这一版做了三层防护**：

1. **自动识别坐标系**：归一化 UV 必然落在 `[0,1]`，一旦出现 `> 1.5` 就判定为像素坐标；
2. **按图集硬件尺寸归一化**：除以 `getWidthHW()/getHeightHW()`（**图集页尺寸**），
   而不是 `getWidth()`（精灵尺寸）—— 用错除数会把 UV 再放大几十倍；
3. **报告里同时打印原始值与归一化结果**，一眼就能确认走的是哪条路：
   ```
   texture uv[0] : slot0 gl=123 sprite=64x64 atlas=1024x1024 raw=(256.000,512.000)-(320.000,576.000) -> uv=(0.25000,0.50000)-(0.31250,0.56250)
   ```

另外加了 **`Ctrl+Alt+U`**：现场循环 `iso → inset → plain` 三种地面 UV 模式，
立刻重建网格（不用改配置、不用重启），改完自动落盘。三种模式对比一下就知道哪种对。

## 1.7.1：角色不再重复绘制（原版已经画好了）

**症状**：玩家模型渲染不正确。

**根因**：我们没有跳过原版渲染 —— 游戏在这一帧里**已经用完整的状态机、正确的相机**
把角色画好了。而 1.5 又在 `postRender` 末尾用 `TextureDraw.drawModel/DrawQueued` **再画一遍**，
这是**脱离渲染状态机的外部调用**：

* 它依赖 `ModelCamera.instance` 在 `postRender` 末尾仍然是世界相机；
  如果此时它是别的相机（物品/预览用），模型就会画到错误的位置或尺寸；
* 骨骼模型的着色器、骨骼贴图、矩阵栈都会被它改写，游戏下一帧若没全部重置，
  就会出现"角色被画歪"这类**跨帧污染**。

**处理**：`characterModels` 与 `entities`（角色方块）默认**关闭**，角色交给原版渲染；
两者都保留为对照开关（`Ctrl+Alt+K` / `Ctrl+Alt+E`），配置迁移到 v4 会强制关闭。

> 要在**我们自己的 3D 视角**里画角色（而不是复制原版那一份），必须把我们的相机
> 注入游戏模型渲染器 —— 也就是之前调研过的 `ModelCamera` 子类 + 矩阵栈替换那条路。
> 在那之前，重复绘制只有风险没有收益。

## 1.7：地面 UV 重映射（等距菱形 → 正方形）

**问题**（用户截图确认）：地面出现"菱形拼贴 + 四角漏出游戏地面"。

**原因**：原版地板精灵是**等距菱形**（菱形只占贴图的一部分，四角透明）。
把它的包围盒直接铺到正方形上，就等于把菱形画进正方形 —— 四角必然透明。
1.6 用的"UV 向内缩 25%"只是取中心不透明区，菱形图案本身还在，所以看起来仍是菱形拼贴。

**正确做法**：把菱形**重映射**到正方形，让菱形四顶点正好落到方块四角。
等距投影下 世界 `(x,y)` → 屏幕 `(x−y, (x+y)/2)`，所以对应关系是固定的：

| 方块角 | 屏幕方向 | 菱形顶点 | UV |
|---|---|---|---|
| 西北 `(x0,y0)` | 正上 | 上顶点 | `(mid, top)` |
| 东北 `(x1,y0)` | 正右 | 右顶点 | `(right, mid)` |
| 东南 `(x1,y1)` | 正下 | 下顶点 | `(mid, bottom)` |
| 西南 `(x0,y1)` | 正左 | 左顶点 | `(left, mid)` |

> 实现时我先写错了 90°（把西北配到了左顶点），推导等距投影公式后修正。

配置 `floorUvMode` 三档，可现场对比：
* `iso`（默认）—— 菱形重映射，不浪费贴图也不漏角；
* `inset` —— 只取中心 50%（1.6 的行为，纹理被放大）；
* `plain` —— 整块铺满（会出现菱形透明角，用来复现问题）。

报告里新增 UV 诊断，用来确认 `getXStart()` 这类接口返回的到底是**归一化 UV** 还是**像素坐标**
（如果是像素，映射还要再改）：
```
texture uv[0] : slot0 gl=123 size=64x64 rect=(0.2500,0.5000)-(0.3750,0.7500)
```

## 1.6.1：盒子是**拖底**，模型是**增强**

设计定稿：**任何没有"自己 3D 模型"的物件，都一定有盒子兜着。**

* 有模型包几何的物件：**盒子照画**（透明度 ×0.6，不糊）**＋ 模型叠在上面**。
  这样模型因为 LRU 淘汰、每帧加载配额（4 个/帧）还没加载好、或者加载失败时，
  这一格**依然有东西**，不会出现空洞 —— 盒子就是"拖底"。
* 原版自带 `SpriteModel` 的物件（载具等）：仍让给游戏自己画（不铺盒子盖住它）。
  若发现这类物件反而变少，把 `voxelSkipOwn3d=false` 写进配置即可强制铺盒子。

顺手堵掉两个会让物件"凭空消失"的漏洞：

| 漏洞 | 后果 | 修复 |
|---|---|---|
| 每格物件上限 = 4 | 地板+双向墙+家具+树 很容易超 4，**超出的物件被整格丢掉** | 上限提到 **6** |
| `type == EMPTY` 整格跳过 | 没地板、不实心、无墙但有物件（树/道具）的格子**完全不采集** | 照样收集物件；只有"无类型且无物件"才跳过 |

## 1.6：逐物件映射（树木/桌椅）+ 地面盖住游戏地面

三个问题一起解决：

### 1. 地面打开，并且盖住游戏地面
* `voxelFloor` 默认 **true**（配置迁移 v3 会把旧配置里的 `false` 改回 `true`）；
* 地面用**原版地板精灵**贴图，UV **向内缩 25%** —— 等距菱形精灵的内接正方形临界点正好是 25%，
  这样采样到的全是不透明区域，方块四角不会漏出游戏地面；
* 近处不透明度 1.0，远处衰减到 0.35（平滑过渡）。

### 2. 树木 / 桌椅不再漏画
原因是原来**一格只画一个盒子**，类型由 `getWall()/isSolid()` 决定：
树和家具既非实心也不是墙，地被判成 `FLOOR` → 只画了一块 3cm 的地板，物件本体消失。

现在改成**逐物件**：遍历 `getObjects()` + `getWall()`（按身份去重，因为墙不一定在 `getObjects` 里），
每个物件单独决定画什么，并按**类名**分类高度：

| 分类 | 判定（类名包含） | 高度 |
|---|---|---|
| 树 | `Tree` | 3.2 |
| 墙/楼梯/电线杆/招牌/玩家建筑 | `Stairs/Thumpable/Wall/Fence/Pole/Pylon/Tower/Sign/Light/Pillar/Column` | 2.7 |
| 门 | `Door/Curtain/Gate` | 2.1 |
| 窗 | `Window` | 1.5 |
| 灌木/草丛 | `Bush/Plant/Fern/Grass/Vine` | 1.0 |
| 家具（桌椅柜台） | 其余 | 0.9 |

### 3. 接上原版的 `IsoObjectModelDrawer` 判定
`IsoObject.getSpriteModel()` 是**游戏自己**"这个物件有没有 3D 模型"的判定（public）。
载具这类物件在原世界里本来就是真 3D 渲染的，所以我们**为它们不画盒子** ——
再画一个盒子只会盖住原版更好的模型。报告里的 `own3d=` 就是这类物件的计数。

> 映射优先级（每个物件独立判断）：
> **原版自带 SpriteModel → 交给游戏自己画** ＞ **模型包有 bind → 用模型包几何** ＞ **兜底盒子（按类型给高度和贴图）**

实现细节坑：贴图槽位上限提到 160 后，`byte` 存槽位会溢出成负数（159 → -97），
所以 `TILE_FLOOR_SLOT/OBJ_SLOT/BOX_SLOT` 全部改成 `short`。

## 1.5：角色用**原世界的骨骼模型 + 动画**（不再用方块）

设计原则：**能用原世界的就用原世界的，模型包只做"原世界没有"的补位。**

角色模型不是静态网格，而是骨架 + 蒙皮权重 + 每帧姿态 —— 这些**游戏已经算好了**，
就在 `ModelManager.getSlot(character).model` 里。所以我们一行蒙皮代码都不用写：

```
ModelManager.instance.getSlot(IsoGameCharacter)     // 模型槽（含动画姿态、朝向、手持物）
ModelCamera.instance.Begin() / End()                // 游戏自己的相机 → 与背景投影严格对齐
TextureDraw.drawModel(TextureDraw, ModelSlot)       // public static：准备
TextureDraw.DrawQueued(TextureDraw, ModelSlot)      // public static：立刻发 GL
```

关键决策（都有字节码依据）：

| 决策 | 原因 |
|---|---|
| **自己 `new TextureDraw()` 当 scratch** | 它有 public 无参构造；若去改游戏渲染状态的 `sprite[]/numSprites`，游戏会在同一个 state 里再画一遍 → 重影 |
| **直接用 `ModelCamera.instance`（不换相机）** | 它就是游戏自己的等距相机，角色因此和游戏背景**投影完全一致** —— 这就是"用原世界做拖底"，也是不引入自定义相机风险的做法 |
| **角色模型最后画** | 它用的是游戏自己的着色器/矩阵，放在我们自己几何之后、并在 `render()` 的 `finally` 状态恢复范围内，把影响限制到最小 |
| **失败自动退回方块** | 任何一步抛异常 → 打一次日志、禁用该功能，方块接手（方块跳过硬编码到 `Ctrl+Alt+E`） |

配套修复：实体扫描原来只在"方块开关"打开时进行 → 关掉方块会连带关掉角色模型。
现在扫描条件是"两者之一开着"，方块绘制单独由 `entities` 控制。

`Ctrl+Alt+K` 可在**原版骨骼模型 ↔ 方块**之间实时对比。

## 1.4：只做叠加，永不跳过原版渲染

按需求**彻底移除**了"跳过原版世界绘制"这条路：

* 删掉 `Patch_SkipWorldDraw`（现在只剩 `Patch_PostRender` 一个补丁）；
* 删掉 `hideVanillaWorld` 配置与 `RenderHook.shouldHideVanillaWorld()`；
* 3D 场景**永远**画在 `postRender` 的 OnExit，也就是游戏画面之上；
* 游戏画面始终完整，任何情况下都不会因为我们的补丁变黑；
* 启动日志改为 `patch: SpriteRenderer#postRender only - the vanilla rendering is never skipped.`

**两个默认值跟着改**（它们是为"不要游戏画面"设计的，叠加模式下会整屏盖住游戏）：

| 配置 | 旧默认 | 新默认 | 原因 |
|---|---|---|---|
| `voxelSky` | true | **false** | 天空盒是以相机为中心的大立方体，会整屏盖住游戏画面 |
| `voxelFloor` | true | false（**1.6 起又改回 true**） | 1.4 时认为它盖住游戏地面不好；1.6 需求明确要"用原版地板盖住游戏地面" |

**配置迁移**：加了 `configVersion`（**1.6 起为 3**）。加载后按版本强制修正并落盘，
所以不需要手动删配置：
* v1 → 关闭天空盒（会整屏盖住画面）、关闭地面；
* v3（1.6）→ 天空盒保持关闭，**地面改为开启**（用原版地板盖住游戏地面）。

注意顺序 —— 迁移判定必须在所有字段 `load()` **之后**执行，
放在前面会被后面的 load 用旧值覆盖（这个坑我在实现时踩到并当场修掉了）。

## 1.3.1：事故复盘（已随 1.4 彻底移除该功能） —— 主菜单被当成"在游戏里"

**症状**：启动时停在 ZombieBuddy 的 Java Mod 审批对话框，**鼠标光标消失、点不到按钮**；
背景全黑；左上角却在画我们的 overlay。

**根因**：`GameWorld.inGame()` 用"玩家对象存在"当判定，但**主菜单也会创建 `IsoPlayer`**
（这也是早期"主菜单就会画 3D"的原因）。于是主菜单上：

| 后果 | 原因 |
|---|---|
| 光标被隐藏，审批对话框点不动 | `MouseLook.update()` 认为 `inGame()==true` → `Mouse.setCursorVisible(false)` |
| 主菜单背景全黑 | `hideVanillaWorld` 生效 → 主菜单的世界绘制被跳过（主菜单背景正是走世界绘制的） |
| 左上角出现 overlay | `Overlay.draw()` 没有做"在存档内"判定 |

**修复**：改用官方判定 **`zombie.GameWindow.isIngameState()`**（`public static boolean`，
反射调用，取不到时保守返回 false），统一收紧四处：

1. `GameWorld.inGame()` = 玩家存在 **且** `isIngameState()`；
2. `MouseLook` 只认 `inGameState()`；
3. `shouldHideVanillaWorld()` 增加 `inGameState()` —— 主菜单不再跳世界绘制；
4. `Overlay.draw()` 只在存档内画。

**加固**：
* `MouseLook.update()` 移到 `Scene3D.draw()` **最前面**，后面任何提前 return 都不会让光标卡在"已隐藏"；
* 注册 JVM shutdown hook，退出时强制把光标还回来；
* 报告新增 `in game state : true/false`，一眼判断判定是否正常；
* 逃生口：`~/Zomboid/viewpointmac.properties` 里 `mouseLook=false` → 完全不碰光标。

**教训**：凡是"改全局状态"（光标、跳过渲染）的功能，判定条件必须用官方状态机，
不能用"某个对象非空"这种间接信号。

## 1.3：原版角色模型（骨骼蒙皮）的接入调研

**结论：原版角色确实是 3D 的，骨骼/姿态游戏也已经算好，我们不需要重做蒙皮 —— 但"直接用"卡在三个地方。**

字节码核对出的完整调用链（`zombie/core/SpriteRenderer`、`GenericSpriteRenderState`、`TextureDraw`）：

```
SpriteRenderer.drawModel(slot)
  → SpriteRendererStates.getPopulatingActiveState().drawModel(slot)
      → TextureDraw.drawModel(sprite[numSprites], slot)     // public static：准备绘制数据
      → postRender.add(...); numSprites++; slot.renderRefCount = 1
GenericSpriteRenderState.drawQueued(slot)
  → TextureDraw.DrawQueued(sprite[numSprites], slot)        // public static：立刻发 GL 调用
ModelManager.instance.getSlot(IsoGameCharacter)             // 拿到角色的模型槽
```

| 卡点 | 说明 |
|---|---|
| **1. 绘制被"排队"** | `drawModel()` 只是把槽位塞进当前 render state；真正的 GL 调用发生在 ring buffer 执行阶段 —— **那正是纯 3D 模式跳过的世界绘制**。角色和世界是同一批被跳掉的。 |
| **2. 相机是抽象插槽** | 模型相机是 `zombie.core.skinnedmodel.ModelCamera`（`public static ModelCamera instance`），接口 `IModelCamera` **只有 `Begin()` / `End()`**。要套我们的第一人称相机就必须提供**子类**；游戏类是 Java 25 字节码，我们 JDK 17 编译期引用不了 → 只能运行期用 ByteBuddy 生成（ZombieBuddy.jar 内置 3163 个 `net/bytebuddy` 条目，已验证可用）。<br>证据：游戏自己就这么换相机 —— `zombie/worldMap/WorldMapRenderer$CharacterModelCamera`。 |
| **3. 矩阵栈在游戏手里** | `Core` 持有 `projectionMatrixStack` / `modelViewMatrixStack`，`PZGLUtil` 提供 `pushAndLoadMatrix(int, Matrix4f)` / `popMatrix(int)`。矩阵要在绘制前替换，绘制后还原。 |

**可用的注入口（已定位）**：
* `TextureDraw.drawModel(TextureDraw, ModelSlot)` / `TextureDraw.DrawQueued(TextureDraw, ModelSlot)` —— 都是 **public static**，可以自己调用实现"立即绘制"；
* `GenericSpriteRenderState.sprite[]` / `numSprites` —— **public 字段**，可作临时绘制槽；
* `ModelManager.instance.getSlot(IsoGameCharacter)` —— 拿模型槽；
* `ModelCamera.instance` + ByteBuddy 子类 —— 换相机；
* `PZGLUtil.pushAndLoadMatrix/popMatrix` —— 换矩阵。

**1.3 先做了探针**（`CharacterModels`）：因为 `ModelSlot.renderRefCount` 与 `ModelManager.resetAfterRender`
说明槽位是**渲染后回收**的 —— 我们跳过了渲染，槽位生命周期可能已经断了。
必须先确认"跳过世界绘制后 `getSlot()` 还有没有、`active`/`framesSinceStart` 还在不在动"，
才敢接第 2 步。探针每 ~3 秒采一次，结果同时进日志与报告文件。

## 1.2：实体渲染（玩家 / 僵尸）

`Entities` 从 `IsoWorld.instance.getCell().getObjectList()`（所有 `IsoMovingObject`）
读出实体位置，`Scene3D` 用带色方块画出来：

| 类型 | 颜色 | 判定 |
|---|---|---|
| 玩家 | 青 | `IsoPlayer` 实例 |
| 僵尸 | 红 | `IsoZombie` 实例 |
| 其它移动对象 | 黄 | 其余 |

* 每帧刷新，带**距离剔除 + 视锥剔除**（相机背后 `dot < -0.35` 丢弃），按距离由近到远排序，
  上限 256 个（远处先被丢掉，保证近处僵尸一定可见）；
* 单帧最多画 200 个方块，避免尸潮把帧率拉垮；
* `Ctrl+Alt+E` 可开关，方便对比。

下一步会把方块换成游戏自带的骨骼模型（`ModelManager` / `ModelSlotRenderData`）。

## 1.1：纯 3D 模式（**已在 1.4 移除**，此处仅存档技术分析）

> ⚠️ 该功能已删除。原因：它会跳过游戏自己的世界绘制，副作用超出收益
> （主菜单背景变黑、需要额外的状态判定、以及 1.3.1 那次的隐藏光标事故）。
> 下面是当时的字节码安全论证，留作技术参考 —— 结论仍然成立，只是我们选择不用它了。

这是把"叠加层"变成"真正的 3D 视图"的那一步。做法是给
`zombie.core.SpriteRenderer#buildStateDrawBuffer` 挂一个 `skipOn` 补丁，
开启时**直接跳过游戏自己的世界绘制**，只保留 UI 绘制。

**为什么这个是安全的**（字节码核对，不是猜）：

```
postRender():
  state = states.getRendering()
  if (无 sprites) { state.onRendered(); return; }
  buildStateUIDrawBuffer(state)    ← 保留（UI）
  buildStateDrawBuffer(state)      ← 本补丁在这里跳过（等距世界）
  ...
  state.onRendered()               ← offset 153，在方法末尾，与两个 buffer 无关
  notifyRenderStateQueue()
```

状态的回收 `onRendered()` **不在被跳过的方法里**，所以主线程不会因为等不到空闲渲染槽而卡死。
（这正是 1.0 里我不敢做、现在做了充分验证才做的事。）

层次因此变成：**3D 场景（OnEnter 绘制）→ 游戏 UI → 我们的 2D 数据面板（OnExit 绘制）**。
关闭纯 3D 时自动回到旧行为（3D 画在世界之上）。

配套改进：**逐物件取模型**。原来一格只查一次 `getWall()`（只有一面墙），
现在遍历 `getObjects()`，北墙 / 西墙 / 家具 / 装饰**各自**查模型包的 bind 表；
只有当这一格所有物件都有模型时才不画兜底盒子，避免出现空洞。
模型包对结构墙的覆盖也已确认（`walls_exterior_wooden_01_3/16/17/18...`）。

配置文件里的逃生口：`hideVanillaWorld=false` 后重启即可回到叠加模式。

## 1.0 完成度说明（诚实版）

**已经做到**：
* 在 macOS 的 OpenGL 2.1 上下文里跑通了完整自绘管线（MVP、深度、贴图、天空、模型）；
* 世界数据、原版精灵贴图、第三方 3D 模型包三条素材链全部打通；
* 第一人称自由视角（鼠标 yaw/pitch + 隐藏光标）、第一/第三人称切换；
* 模型视锥剔除与绘制上限、体素距离衰减、LRU 模型缓存与每帧加载预算；
* 全套自检/熔断：任何一环失败都只关闭对应功能，绝不影响游戏本体。

**还没做到（下一步）**：
1. ~~游戏自己的等距世界仍在下面渲染~~ → **1.1 已解决**（纯 3D 模式）。
2. ~~玩家角色模型不显示~~ → **1.5 已接入原版骨骼模型 + 动画**。
3. **模型逐个 draw call**：还没做同模型实例合批；密集区靠 `MAX_MODEL_DRAWS=320` 兜底。
4. **按 chunk 缓存 / 网格级视锥剔除**：目前是整窗重建 + 绘制期剔除。
5. **天空贴图**：现在是程序化渐变 + 游戏天空颜色；`SkyBox.getTextureCurrent().getID()` 已经探明可用，下一步换成真云层。
6. **P3 的 Metal/IOSurface 后端**：换掉 GLSL 1.20 才能真正把画面档次拉起来。

## 配置

`~/Zomboid/viewpointmac.properties`（首次运行自动生成）：

```properties
# --- P0：2D 覆盖层与诊断 ---
overlay=true          # 是否绘制 GL 覆盖层
verbose=false         # 详细日志
reportOnStart=true    # 探针完成后自动写报告
overlayX=16
overlayY=16
graphBars=80

# --- P1：3D 场景与相机 ---
scene3d=true          # 是否绘制 3D 调试场景（调试面板可切换）
sceneGridRadius=24    # 地面网格半径（地块格）
cameraFovDeg=72       # 垂直视场角
cameraPitchDeg=-8     # 视线俯仰角（负值向下看）
cameraEyeHeight=1.55  # 第一人称眼高
cameraThirdPerson=false
cameraDistance=4.5    # 第三人称跟随距离

# --- P2：体素世界 ---
voxel=true            # 是否把游戏世界采样成体素（调试面板可切换）
voxelRadius=16        # 采样半径（地块格，上限 31）
voxelBudget=256       # 每帧最多采样多少格（预算式，避免掉帧）
voxelWireframe=false  # true = 只画线框，不遮挡游戏画面
voxelTextured=true    # 用原版精灵贴图给体素上材质（false = 纯色）
voxelModels=true      # 用 PZ Voxel Studio 模型包渲染物件（真 3D）
hideVanillaWorld=true # 纯 3D：跳过原版等距世界绘制（Ctrl+Alt+H 切换；出问题改回 false 重启）
characterModels=false # 是否额外再画一遍原版角色模型（默认关：原版已画好，重复画会歪）
entities=false        # 是否给我们 3D 层画角色方块（默认关，会盖住原版角色）
voxelSky=true         # 天空（用游戏自身的天空颜色，含昼夜/天气）
mouseLook=true        # 鼠标自由视角（第一人称）
mouseSensitivity=0.0025  # 鼠标灵敏度（弧度/像素，0.0004~0.02）
voxelPackDir=         # 模型包目录（留空 = 自动扫描）
```

---

## 排障

| 现象 | 原因 / 处理 |
|---|---|
| **新 Lua 调 Java 方法得到 `nil` / `java method 'xxx' is not exposed`** | **Java class 不能热重载**：游戏会重载 Lua 文件，但已加载的 JAR 不会变。改了 Java 必须**完全重启游戏**。模组现在会在启动时做版本握手，不一致会打印 `VERSION MISMATCH: jar=... lua=...`，并列出实际暴露的 API 清单 |
| 日志里没有 `[ViewpointMac]` | JAR 没被加载：检查 ZombieBuddy 是否启用、启动项是否有 `-javaagent`、模组是否勾选 |
| ZombieBuddy 弹窗被拒绝 | 删除 `~/.zombie_buddy/mod_approvals.json` 里对应条目后重启，或按住 Shift 强制弹窗 |
| `compat: ... missing: ...` | 游戏版本变了。渲染注入自动关闭，游戏不受影响；按日志补齐 `Compat.java` 的检查项 |
| 面板不出现但日志正常 | 面板默认在左上角 `16,16`；确认没被其它 HUD 覆盖，或调 `overlayX/overlayY` |
| 画面出现异常色块 | `Ctrl+Alt+D` 打开面板，关掉 3D 场景与覆盖层；并把 `console.txt` + 报告贴出来（GL 状态保存/恢复可能需要针对该版本补全） |
| **主菜单黑屏、只剩左上角面板** | 已修复（v0.1.1）：文字 HUD 曾用 `DrawString(font, text, x, y, ...)`，而 B42 的签名是 `DrawString(font, x, y, text, ...)`（字符串在第 4 个参数）。Java 异常从 `OnPostUIDraw` 事件链里逃逸，导致 `UIManager.render` 每帧中断 → 菜单和背景动画都不画。现在改成正确签名**且只在存档内绘制**（`OnGameStart` 之后、`OnMainMenuEnter` 之前） |
| 3D 场景不出现 | 报告里看 `world bridge`：`no player yet`＝还在主菜单（进存档才有效）；`unavailable(...)`＝游戏版本改了 `IsoPlayer` 签名，按日志补 `GameWorld` |
| 网格/原点标记位置不对 | 报告里看 `player=` 与 `camera=` 两行，把截图+报告发出来；PZ 世界坐标 X 向东、Y 向南、Z 向上 |
| 想彻底停用 | 启动项去掉 `-javaagent`，或把 `overlay` 设为 `false` |

---

## 后续路线

按 [`docs/pz-3d-mod-macos-feasibility.md`](../../docs/pz-3d-mod-macos-feasibility.md) 的分阶段计划：

* **P0（已完成）** ✅ 渲染管线打通 + 能力自检 + 覆盖层
* **P1（已完成）** ✅ 矩阵/透视、反射世界桥、第一/第三人称相机、GLSL 1.20 的 3D 通路（深度 + MVP）、
  跟随玩家的地面网格与**世界原点标记**（用于证实读到的是真实世界坐标）
* **P1.5（下一步）** 鼠标锁定与自由视角（yaw/pitch）、把帧统计改挂到 `Display#update`
* **2.2（当前版本）** ✅ 按日志实测修 6 个 bug（容量/缓存/树分类/异常根因/两个"反了"）+ 两个快捷键
* **2.1** ✅ P8 角色朝向跟随视线 + P7 完整视图下接管角色 + P6 容量放开
* **2.0.1** ✅ 用不透明 3D「遮住」原版画面（删除世界跳过补丁，零风险）
* **2.0** ✅ 完整 3D 路线与路线图
* **1.10** ✅ 与游戏世界 3D 相机对齐（2.5D 物件原位变 3D，告别 UV 重映射）
* **1.9.2** ✅ 日志落文件 + 每 5 秒状态快照（可直接读文件排查）
* **1.9.1** ✅ 地面改实心（消除掠射角菱形摩尔纹）+ `isoflip` V 翻转模式
* **1.9** ✅ 单快捷键 + 调试控制面板 + 用我们自己的相机画角色/僵尸
* **1.8** ✅ UV 自动归一化（像素/归一化双兼容）+ `Ctrl+Alt+U` 现场切换地面 UV
* **1.7.1** ✅ 角色不再重复绘制（避免画歪/跨帧污染），交出对照开关
* **1.7** ✅ 地面 UV 重映射（等距菱形→正方形）+ UV 诊断
* **1.6.1** ✅ 盒子作为拖底（模型加载中/失败也不会空洞）+ 堵掉两个物件丢失漏洞
* **1.6** ✅ 逐物件映射（树木/桌椅）+ 地面盖住游戏地面 + 原版 SpriteModel 让位
* **1.5** ✅ 角色改用原版骨骼模型 + 动画（模型包只做补位）
* **1.4** ✅ 移除"跳过原版渲染"，只做叠加层 + 配置迁移到 v2
* **1.3.1** ✅ 修复"主菜单被当成在游戏里"导致的隐藏光标 / 黑屏事故
* **1.3** ✅ 原版角色模型接入调研 + `CharacterModels` 探针
* **1.2** ✅ 实体渲染（玩家/僵尸方块，带距离与视锥剔除）
* **1.1** ✅ 纯 3D 模式（跳过原版世界绘制）+ 逐物件模型（双向墙/家具）
* **1.0** ✅ 鼠标自由视角 + 游戏天空颜色 + 模型视锥剔除/绘制上限 + 全套 1.0 文档
* **P3.1（已完成）** ✅ PZ Voxel Studio 模型包加载 + 物件真 3D 模型 + 地面平板 + 天空
* **P2（进行中）** ✅ 世界数据桥 + 预算式体素采样 + 网格缓存 + 体素渲染 + 瓦片分类 + 背面剔除/距离衰减/线框模式；
  下一步：按 chunk 分块缓存（避免整窗重算）、视锥剔除、用地板贴图做真正的贴图体素
* **P3** 阴影贴图、每像素灯、远景 LOD、天空/天气
* **P4** 鼠标拾取、掉落菜单、设置窗口

> **P3 起建议切到 Metal/IOSurface 后端**：GLSL 1.20 做不出 Viewpoint 那种画面，
> 而 Metal 渲染 + `CGLTexImageIOSurface2D` 合成本工程已验证过所需接口全部可用。

---

## 许可

本工程为独立实现（clean-room）：不包含、不复制 Project Viewpoint 的任何代码、着色器或资源。
Viewpoint 采用专有许可（禁止反编译复用/再分发），本项目只参考了"需要挂钩哪些游戏类"这类
来自游戏自身公开结构的**事实信息**。
