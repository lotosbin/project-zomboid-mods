# PZ 模组开发：对应的开发工具清单（模型 / 动画 / 贴图 / 音频 / 调试）

本文回答"这条链路上到底该用什么工具"，而不是把脚本再写一遍。分三层：

* **A. 游戏自带的开发工具**（零安装，最权威 —— 它看到的就是引擎看到的）
* **B. 通用外部工具链**（3D/贴图/音频的行业标准工具与授权）
* **C. 与本仓库现有手搓脚本的映射**（哪些该换、哪些该留）

一键探针：`scripts/pz_dev_tool_probe.sh [<模组版本目录>]` —— 打印本机哪些工具已有、
游戏自带工具的入口是否还在（用 `文件:行号` 自证），并对模组目录做一次资产体检。

---

## A. 游戏自带的开发工具（最容易被忽略，也最有用）

**入口（两步）**

1. Steam → Project Zomboid → 属性 → 启动选项加 **`-debug`**（Lua 侧判据 `getCore():getDebug()`；
   证据：`projectzomboid.jar` 里 `zombie/gameStates/MainScreenState`、`ConnectToServerState`、
   `CoopMaster`、`GameServer`、`CellLoader` 等 6 个类含 `-debug` 字面量）。
2. 游戏内 **右键"装备栏物品" → 调试菜单（Debug Menu）→ 切到 `Dev` 标签页**。
   入口代码：`media/lua/client/ISUI/ISEquippedItem.lua:452`（`button.internal == "DEBUG" and getCore():getDebug()`），
   `media/lua/client/DebugUIs/DebugMenu/ISDebugMenu.lua:85` 的 `ISDebugMenu.OnOpenPanel()`。

| 工具（Dev 标签页） | 代码位置 | 它是什么 / 能用它做什么 | 能替代我们哪些手搓脚本 |
| --- | --- | --- | --- |
| **Animation Viewer** | `ISDebugMenu.lua:38` → `showAnimationViewer`（`LuaManager$GlobalObject` 暴露）→ `client/DebugUIs/AnimationClipViewer.lua` | **带 "Animal Model" 下拉的动物动画查看器**：下拉数据来自 `getAllAnimalsDefinitions()`（`:446`），按动物定义里的 `bodyModel` 载入模型（`:575`），用 `getAnimationViewerState():fromLua1("getClipNames", ...)`（`:577`）列出**该模型里真实存在的剪辑**并播放。支持空格播放/暂停、左右箭头逐帧、Shift 旋转、时间轴/关键帧、声音面板、选项面板；默认动画集是 `media/AnimSets/animal-editor`（`:452` 的 `setCharacterAnimSet("animal1", "animal-editor")`，默认剪辑 `Cow_Idle01`） | **`tools/alpaca/render_glb.py`（离线预览器）的权威替代/补充**：模型与剪辑能不能被引擎认出来、是否有冻结/穿模，在这里看才算数 |
| **Attachment Editor** | `ISDebugMenu.lua:39` → `showAttachmentEditor` → `client/DebugUIs/AttachmentEditorUI.lua` | 附件（帽子/驮袋/挂点）的 offset / rotate / translate / scale 实时编辑 | **正是 `media/scripts/models_alpaca.txt` 里 `attachment head` / `saddlebags_*` 数值该用的工具**（此前只能靠推算 + 我提醒"要进游戏目视微调"） |
| **Anim Debug Monitor** | `ISDebugMenu.lua:36` → `ISAnimDebugMonitor` | 实时看动画层 / 变量 / 激活节点 / 轨道 / tick 戳，还能改动画变量 | 调试"动画状态机为什么没切过去"（例如 `AnimSets/raccoon/idle/*.xml` 写错时的症状） |
| **Extended Anims List** | `DebugContextMenu.lua:94`（`IGUI_DebugContext_ExtendedAnimsList`）→ `ISExtAnimListDebugUI.lua` | 对角色右键播放/检查"外部动画" | 想快速确认某个剪辑名字是否被引擎识别时用 |
| **Animation Text** | `DebugContextMenu.lua:105` → `ISDebugAnimationTextUI.lua` | 屏幕上打印当前动画状态文本 | 抓"到底在播哪条剪辑" |
| **Texture Viewer / Object Viewer / Sprite Model Editor** | `client/DebugUIs/{TextureViewer,ObjectViewer,SpriteModelEditor}.lua` | 贴图、对象、精灵模型查看器 | 查贴图有没有被正确加载（比"看不出来"强） |
| **Lua Debugger / Lua File Browser / Watch Window** | `client/DebugUIs/LuaDebugger.lua` 等 | Lua 断点调试、文件浏览、变量监视 | 替代"加 print 再重启"的土办法 |
| **其它创作向** | `AttachmentEditorUI`、`ISFilmingToolsUI`、`TileGeometryEditor`、`SeamEditor`、`ISDebugAvatarUI`（头像预览）、`setAnimationRecorderActive(true)`（`ISEquippedItem.lua:460` 的动画录制器） | 头像/动画/地块/接缝等各自的编辑器 | 头像构图对应 `AnimalAvatarDefinition`；动画录制器可用于做参考素材 |

**也可以绕过菜单**：`showAnimationViewer()` / `showAttachmentEditor()` 都是 **Java 暴露的全局函数**
（`zombie/Lua/LuaManager$GlobalObject.class` 里有这两个字符串），在调试控制台直接调用即可；
同族还有 `getAllAnimalsDefinitions()`、`getAnimationViewerState()`、`setAnimationRecorderActive(bool)`。

**引擎能载入哪些模型格式（决定你导出什么）**：jar 里
`zombie/core/skinnedmodel/model/FileTask_AbstractLoadModel`、`MeshAssetManager`、
`ModelManager$AnimDirReloader`、`zombie/core/physics/PhysicsShapeAssetManager` 这几个类里
同时出现字面量 `.glb` / `.fbx` / `.x`，且 jar 内含 **47 个 `jassimp.*` 类**（Assimp 绑定）
⇒ **三种格式引擎都吃**（走 Assimp）。B42 的动物模型生态（Companion Dogs 及其全部 addon）用的是 **`.glb`**，
所以做动物 addon 就按 `.glb` 走；`.x` 是旧资产格式（需要时见 B 节的 Blender DirectX X 插件）。

> 注意（诚实标注）：`AnimationClipViewer.lua` / `AttachmentEditorUI.lua` 这两个 Lua 文件在**零售版 jar 里
> 没有被任何 Java 类引用**（我扫了 23829 个 class，命中 0），所以它们的 Java 侧接线很可能在 TIS 内部构建里。
> 但 `showAnimationViewer` / `showAttachmentEditor` 这两个入口**确实存在于零售版**的
> `LuaManager$GlobalObject`，且调试菜单里也确实挂了它们 —— 因此正常路径可用；
> 万一菜单里点了没反应，就是内部构建差异，直接在控制台调同名函数试。

---

## B. 通用外部工具链（按任务）

本机现状：**除 ffmpeg/lame/node 外，一个都没有**（所以之前的管线只能手搓）。
下表每条都在本机核实过"包是否存在"，并在括号里给出授权（GitHub API / PyPI 元数据实测）。

| 任务 | 工具 | 授权 | 本机安装命令 | 能替代我们什么 |
| --- | --- | --- | --- | --- |
| 3D 全流程（网格/骨骼/蒙皮/UV/烘焙/渲染/导出） | [Blender](https://www.blender.org/download/) + [glTF-Blender-IO](https://github.com/KhronosGroup/glTF-Blender-IO) | GPL-2.0+ / Apache-2.0 | `brew install --cask blender` | 一个工具替代 `build_alpaca_from_cc0.py`（骨骼对应/权重/UV）+ `render_glb.py`（渲染）+ `make_images.py` 的渲染部分；**但无头脚本化要自己写**，且 Apple Silicon 上体积约 1GB |
| glTF 检查/优化/变换/合并 | [gltf-transform](https://gltf-transform.dev/)（`@gltf-transform/cli` 4.5.1） | MIT | `npm i -g @gltf-transform/cli` | 替代 `glb_util.py` 的读写与 `validate_glb.py` 的部分断言（`gltf-transform inspect`） |
| glTF 官方校验 | [glTF-Validator](https://github.com/KhronosGroup/glTF-Validator)（npm 2.0.0-dev） | Apache-2.0 | `npm i -g gltf-validator` | 比自写校验器更权威的规范级检查（我们会话里那些"accessor 越界/索引不连续"断言可以交给它） |
| glTF 压缩 | [gltfpack](https://github.com/zeux/meshoptimizer) | MIT | 上游 releases（无 brew formula） | 模型体积优化（我们的 6180 顶点模型目前 3.2MB，其中大量是 JSON） |
| 网格格式转换/检查 | [assimp](https://github.com/assimp/assimp) | BSD-3 类（仓库 LICENSE） | `brew install assimp` | 换几何来源时的格式转换（FBX/OBJ/glTF 互转） |
| FBX→glTF | [FBX2glTF](https://github.com/facebookincubator/FBX2glTF) | BSD 类（仓库 LICENSE） | `npm i -g fbx2gltf` | 如果来源资产是 FBX（本项目 CC0 来源已经是 glb，用不上） |
| Python glTF 库 | [pygltflib](https://pypi.org/project/pygltflib/) 1.16.5 | MIT | `pip install pygltflib` | 替代 `glb_util.py`（读写/校验） |
| Python 网格处理 | [trimesh](https://trimesh.org/) 5.1.1 | MIT | `pip install trimesh` | 法线/面积/拓扑检查、凸包、体素化，替代 `validate_glb.py` 里手写的几何断言 |
| UV 展开 | [xatlas](https://github.com/jpcy/xatlas) 0.0.11（PyPI 有 wheel） | MIT | `pip install xatlas` | **替代"每三角形一格"的土办法 UV**：直接展开成正经图集（但身体图集要按材质分块上色，仍得自己写） |
| 网格处理（GUI） | [MeshLab](https://www.meshlab.net/) | GPL-3.0 | `brew install --cask meshlab` | 目视检查/减面/重网格 |
| 位图批处理 | [ImageMagick](https://imagemagick.org/) | Apache-2.0 类 | `brew install imagemagick` | 贴图批量缩放/格式转换/合成 |
| 音频处理 | [SoX](https://sox.sourceforge.net/) | GPL-2 / LGPL-2.1 | `brew install sox` | 替代 `make_sounds.py` 的后期（重采样/归一化/拼接），但**合成部分仍需代码** |
| 音频中间件 | [FMOD Studio](https://www.fmod.com/download) | 官方免费档（营收阈值内，详见其许可页） | 官网注册下载 | **本项目用不上**：Companion Dogs 用的是"散装 `.ogg` + `media/scripts/sounds_*.txt`"，不需要音库；只有在要做音库/复杂混音时才需要它 |
| 纹理打包 | [TexturePacker](https://www.codeandweb.com/texturepacker) | 商业（有免费版） | 官网 | 只有在要做图集精灵表时才需要；身体图集是 UV 决定的，不是打包问题 |
| 旧版 `.x` 模型（PZ 老资产格式） | [Blender: DirectX X Format (.x)](https://extensions.blender.org/add-ons/io-directx-x/)（另有历史 addon `io_scene_x`） | 见扩展页 | Blender 扩展面板里安装（或 `blender --command extension install …`） | 需要读写 `media/models_X/*.x` 时用；我们的动物是 `.glb`，用不上 |
| 浏览器拖拽预览 glTF | [gltf-viewer](https://gltf-viewer.donmccurdy.com/)（three.js 0.186.1，MIT） | MIT | 打开网页 | 快速目视（但**不带**我们的骨架/剪辑语义，验证动画仍要看 A 节的游戏内查看器） |

### B2. PZ 专用 Blender 扩展 / rig（社区自制，逐条实测）

| 工具 | URL | 授权（GitHub API 实测） | 活动 | 用途与限制 |
| --- | --- | --- | --- | --- |
| **DirectX X Format (.x)** | <https://extensions.blender.org/add-ons/io-directx-x/> · 源码 <https://github.com/SaintBaron/io_directx_x> | **GPL-3.0-or-later** | 6★，pushed 2026-07 | 在 Blender 里**导入/导出 PZ 的 `.x` 模型**（纯 Python，可 `blender -b --python`）。这是"在 macOS 上改 base 的 `.x` 骨架/动画"唯一可行的桥（这类活以前基本要 Windows + 3ds Max） |
| **Project Zomboid Community Rig** | <https://github.com/Paddlefruit/ProjectZomboid_CommunityRig> | **GPL-3.0** | **32★，pushed 2026-10-02（活跃）** | PZ 的社区骨骼 rig（Blender 5.1+）。注意 GPL-3.0：**当工具用，别把它的资产并入要发布的模组** |
| **ExpressionRig** | <https://github.com/nonameservices83/ExpressionRig> | **CC0-1.0** | 2★，pushed 2026-01 | 面向 PZ 的表情/动画 rig，授权最宽松 |
| **pz-character-blender** | <https://github.com/DevelopmentStatus/pz-character-blender> | **GPL-3.0** | 0★，pushed 2026-09 | 把 B42 本体的角色网格/衣物/肤色/动画剪辑装进 Blender（纯 stdlib） |

安装（Blender 本体在本机的 cask 实测版本是 **5.2.2**）：

```bash
brew install --cask blender          # macOS arm64 官方 dmg，约 1GB
# 然后在 Blender 内：Get Extensions 搜 "DirectX X Format"（或拖 zip 安装）
# 无头用法：blender -b --python your_script.py
```

> 本机没有 Python 的 scipy/trimesh/pygltflib：如果要把上面这些接进现有脚本，
> 建议固定用仓库当前那个独立运行时（`PY=.../dsh-primary-runtime/dependencies/python/bin/python3`）
> 并在一个 `requirements.txt` 里声明，避免"脚本换台机器就跑不起来"。

---

## C. 与本仓库现有手搓脚本的映射

| 现有脚本 | 现在该用什么 | 建议 |
| --- | --- | --- |
| `tools/alpaca/build_alpaca_from_cc0.py`（骨骼对应 + 仿射传递 + 逆蒙皮烘焙 + UV/图集） | **Blender 无头**（`blender -b --python`）可以做同样的传递与烘焙，但四足 46→55 骨骼的对应、Umeyama 拟合、逆蒙皮烘焙这套逻辑**仍然要自己写**；xatlas 可替换土办法 UV | **保留**（它是这套契约的可复现证据），把 UV 部分视情况换 xatlas |
| `tools/alpaca/render_glb.py`（离线 CPU 渲染） | 游戏内 **Animation Viewer**（权威）；Blender EEVEE/Cycles（好看）；gltf-viewer（快） | **保留**作"进游戏前的回归检查"（它能在 CI/无游戏时跑，游戏查看器不能） |
| `tools/alpaca/validate_glb.py` | glTF-Validator（规范）+ trimesh（几何）+ 游戏内查看器（语义） | **保留**：它检查的是"这个模组能不能被 Companion Dogs 用"（必需剪辑、平移爆值、UV/索引约定），glTF-Validator 不查这些 |
| `tools/alpaca/make_images.py` 的渲染部分 | Blender 渲染 / 游戏内截图 | 可换 Blender；图标/海报的排版部分 Pillow 更省事，**保留** |
| `tools/alpaca/make_sounds.py`（numpy 合成） | SoX/ffmpeg 处理 + 任意 DAW/Audacity | **保留**（合成逻辑无现成替代），后期可交给 sox |
| `tools/test/`（fengari 上跑 Lua + mock base） | 游戏内 Lua 调试器（真实环境） | **保留**：mock 能在无游戏时回归"注册契约"；真实环境用游戏调试器 |
| `tools/check.sh`（一键自检） | 组合上面所有工具 | **保留**并把新工具挂进去 |

---

## D. 建议的安装顺序（按投入产出比）

1. **零成本、立刻可用**：`-debug` + 游戏内 **Animation Viewer**（选 Animal Model → 我们的羊驼）、
   **Attachment Editor**（调 `models_alpaca.txt` 的挂点）。这两件是本次交付遗留的"必须在游戏里确认"的部分。
2. **轻量、马上提升可信度**（几 MB）：
   ```bash
   npm i -g @gltf-transform/cli gltf-validator
   PY=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3
   $PY -m pip install pygltflib trimesh xatlas
   ```
3. **中等份量、值得装**：`brew install assimp imagemagick sox`
4. **大件（按需；但有一个值得提前装的理由）**：`brew install --cask blender`（本机 cask 实测 **5.2.2**，≈1GB）。
   装它的理由不只是 UV/烘焙：再装 **DirectX X Format (.x)** 扩展（GPL-3.0-or-later，见 B2 节）之后，
   **在 macOS 上就能读写 PZ 的 `.x` 模型** —— 想改 base 的骨架/动画（而不是只做 glb addon）时这是唯一可行的桥；
   再配 **PZ Community Rig**（GPL-3.0，32★，2026-10 仍活跃）可做目视验证与手工刷权重。
   同档还有 `brew install --cask meshlab`（网格目视/减面）。
5. **只在特定场景**：FMOD Studio（要做音库）、TexturePacker（要做精灵表）、FBX2glTF（来源是 FBX）、gltfpack（体积优化）

---

## E. 探针

```bash
scripts/pz_dev_tool_probe.sh                                   # 只探测
scripts/pz_dev_tool_probe.sh bin2_companion_alpaca/Contents/mods/CompanionDogsAlpaca/42
```

它会打印：游戏自带工具的入口是否仍在（逐条 `文件:行号` 自证）、外部工具缺哪些及安装命令、
以及目标模组的资产体检（models_X / AnimSets / textures / sound / scripts 与贴图体积尺寸）。

---

## F. 文档与社区资源（先看这些，再决定要不要自己造）

| 资源 | 链接 | 说明 |
| --- | --- | --- |
| Companion Dogs 官方 addon 手册 | <https://companiondogs.pet/docs/en/modding.html> | 新物种/新品种的**唯一权威契约**（本仓库 `docs/pz-companion-dogs-addon.md` 是它的实证速查） |
| PZ Wiki: Animation | <https://pzwiki.net/wiki/Animation> | 社区整理的动作/动画说明（注：该站对脚本抓取返回 403，我未能逐字核对内容，仅作为入口给出） |
| Steam 工坊讨论：3D 模型格式 | <https://steamcommunity.com/workshop/discussions/18446744073709551615/4699034922677165346/> | 玩家/作者关于"PZ 支持哪些 3D 格式"的讨论串 |
| Blender glTF I/O | <https://github.com/KhronosGroup/glTF-Blender-IO> | Blender 官方 glTF 导入导出（Apache-2.0） |
| glTF 规范 | <https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html> | 判断"引擎为什么忽略网格节点变换""IBM/绑定姿态"这类问题时的依据 |

本机已装的、与本链路相关的调试/工具类模组（来自 `~/Zomboid/Lua/ModManager/ModListData.ini`，仅作参考）：
`PZ_Debug`、`PZ_Debug_PlayerCheats`、`QNWDebugMenuB42`、`twisttool`、`B42DisableDebugText`、
`FixAnimalTrailers`、`HorseUtilityAddon`、`vac_carry_more_animal`。

---

## G. PZ 社区专用工具（GitHub API 实测：星数/授权/最后提交都核过）

| 工具 | 实测情况 | 与本项目的关系 |
| --- | --- | --- |
| [LazySpongie/Project-Zomboid-GLTF-Export-Preset](https://github.com/LazySpongie/Project-Zomboid-GLTF-Export-Preset) | Blender 的 **PZ 专用 glTF 导出预设**（Python，`pushed 2025-12-30`）。见下方授权提醒。README 明确提醒"导出动画默认是关的，要自己开" | **做模型时该先抄它的导出设置**：PZ 对轴向/缩放/动画开关很敏感，我们这轮是自己用脚本硬写 glTF，下次若走 Blender 就用它对齐参数 |
| [ssjshields/pz-fbx-to-glb](https://github.com/ssjshields/pz-fbx-to-glb) | 便携 CLI：**FBX → GLB，correct scale / UV safety / ASSIMP compatibility**（Python，依赖 Blender 4.2 LTS，以 Windows 批处理为主）。两项硬限制：**不支持带关键帧的 FBX**、**仓库无 LICENSE（慎用）** | 换几何来源时若拿到的是 FBX，用它转换比手写转换器稳（不过我们这次来源本身就是 glb） |
| [AlexVDefi/rcpz-tools](https://github.com/AlexVDefi/rcpz-tools) | **MIT**，4★，TypeScript，pushed 2026-08；**PZ Icon Maker**（把物品 3D 模型渲成游戏等距视角的 `Item_*.png`，带透明背景 + 无头 CLI）与 **PZ Survivor Studio**（播放游戏动画，导出静帧/精灵表/GIF）。**只有 Windows x64 预编译包**（不需要游戏/Blender/Python） | 我们这轮的背包图标（偶蹄）是 Pillow 画的；如果要"物品模型→图标"，它是现成的；但**它只涉及物品图标与角色，不涉及动物 3D**。我们是 macOS，只能自己编译（TypeScript）或换方案 |
| [PZ-Wiki-Modding/pz-animsets-parser](https://github.com/PZ-Wiki-Modding/pz-animsets-parser) | Python，**只读**解析 PZ 的 `AnimSets`（需 `PZ_GAME_PATH`）；`pushed 2026-09-24`；**仓库无 LICENSE（慎用）** | 将来若要自己写 `AnimSets/raccoon/idle/*.xml`（例如给羊驼加"卧姿"节点），用它先摸清 base 的节点结构 |
| [Konijima/project-zomboid-studio](https://github.com/Konijima/project-zomboid-studio) | **Apache-2.0**，41★，TypeScript，Lua 模组工程管理 | **最后提交 2023-05（B41 时代）**，对 B42 的版本目录/翻译 JSON 结构基本过时；参考其工程组织即可，别当工具依赖 |
| [PeterHammerman/PZ-modding-tools](https://github.com/PeterHammerman/PZ-modding-tools) | MIT，C#，**服装脚本生成器**，README 自述"已停止开发" | 与动物无关，列出来是为了说明"社区工具里没有现成的动物 rig/AnimSet 编辑器" |
| [pzstorm/zomboid-plugin-loader](https://github.com/pzstorm/zomboid-plugin-loader) | GPL-3.0，Java 插件加载器（运行时改游戏代码） | 与本仓库已用的 **ZombieBuddy** 同类；引擎级问题的两条路之一（见 `.dsh/skills/pz-engine-deepdive`） |
| [SimKDT/Doggy-s-Library](https://github.com/SimKDT/Doggy-s-Library) | **CC0-1.0**，Lua 模组 API 工具库 | 写 Lua 模组时的通用工具箱（我们这只 addon 没依赖它） |

> ⚠️ **授权提醒（实测）**：上面 `Project-Zomboid-GLTF-Export-Preset`、`pz-fbx-to-glb`、
> `pz-animsets-parser` 三个仓库**都没有 LICENSE 文件** ⇒ 默认保留所有权利，只把它们当「设置/结构参考」看，**不要整包并入自己的模组发布**；
> 需要宽松授权的就用 `io_directx_x`(GPL-3.0)、`Community Rig`(GPL-3.0，仅作工具)、`ExpressionRig`(CC0-1.0)、`rcpz-tools`(MIT)。

> 结论：**动物 rig / 骨头对应 / 蒙皮传递这一层，社区没有现成工具**（搜过 `zomboid blender`、
> `zomboid animset`、`zomboid model exporter`、`project zomboid glb` 等查询，命中的都是上面这些
> 导出预设、格式转换、图标渲染、解析器）。这也是为什么 `build_alpaca_from_cc0.py` 里那套
> "骨骼对应表 + Umeyama 拟合 + 逐骨骼仿射传递 + 逆蒙皮烘焙"必须自己写；
> 但**验证**它们（游戏内 Animation Viewer / Attachment Editor）与**资产格式**（导出预设 / FBX→GLB）
> 都有现成工具可用。

---

## H. 两个「找不到工具」的结论（附证据，省得以后再查一遍）

### H1. 四足 rig → 四足 rig 的跨拓扑蒙皮迁移：没有现成工具

我们要做的是「46 骨骼 CC0 羊驼 rig → base 的 55 骨骼 Raccoon 骨架，拓扑不同，且结果必须落在
**别人已有的绑定空间**里」。逐个查证：

| 方案 | 为什么不行 |
| --- | --- |
| Blender **Data Transfer 修改器**（[官方文档](https://docs.blender.org/manual/en/latest/modeling/modifiers/modify/data_transfer.html)） | 它只有**空间邻近**映射（Nearest Edge / Nearest Face Interpolated / Projected Face Interpolated），**无法表达"用户给的 46↔55 语义骨骼对应表"**。我们这边躯干是「CC0 单链 vs 腰/胸/颈三段」，语义对不上，纯几何邻近会传错 |
| [Simple-Retarget-Tool-Blender](https://github.com/cgvirus/Simple-Retarget-Tool-Blender)（GPL-3.0 ★144）、[Rokoko Studio Live](https://github.com/Rokoko/rokoko-studio-live-blender)（LGPL-3.0 ★504）、[Auto-Rig Pro](https://blendermarket.com/products/auto-rig-pro)（付费） | 都是**人形**姿势迁移（仍要你填骨骼对应），不做网格换绑，也不解决「目标绑定空间」这件事 |
| [@three-ws/retarget](https://www.npmjs.com/package/@three-ws/retarget)（Apache-2.0） | README 自述只接受 humanoid，非人形会被 refuse |
| Unity Humanoid / Mecanim | Humanoid 只收两足；四足只能 Generic，而 **Generic 完全不重定向**（要求层级与命名一致） |

⇒ 正确做法就是本项目现在的样子：**骨骼对应表 + Umeyama 全局拟合 + 逐骨骼仿射传递 + 逆蒙皮烘焙**
（`bin2_companion_alpaca/tools/alpaca/build_alpaca_from_cc0.py`，数学与两个坑见 `docs/pz-cc0-mesh-retarget.md`）。
Blender 在这里的定位是**目视验证与手工刷权重**（配合 Community Rig 载入目标骨架），而不是重定向器。

### H2. PZ 创意工坊：绕不过游戏内向导

| 方案 | 结论 |
| --- | --- |
| [steamcmd](https://developer.valvesoftware.com/wiki/SteamCMD) | 只能 `workshop_download_item`（下载/更新），**没有提交 UGC 的子命令** |
| [Steamworks SDK / ISteamUGC](https://partner.steamgames.com/doc/api/ISteamUGC) | 官方唯一上传 API，但**只有 app 所有者（The Indie Stone）能为 appid 108600 创建/提交工坊物品**，第三方拿不到这个权限 |
| [SteamworksPy](https://github.com/philippj/SteamworksPy)（MIT ★269） | 技术上能调 UGC，但预编译只发 Windows/Linux，且同样受 appid 权限限制 |
| [ZBetterWorkshopUpload](https://github.com/zed-0xff/ZBetterWorkshopUpload)（MIT） | 真实存在的增强，但**仍在游戏内向导之内**（加 `.workshopignore` 过滤 + 上传前预览） |
| `ecneho/zbun`、`wink-/pz_mod_builder`（均 MIT，低星/停更） | 只做打包与生成 `workshop.txt`，**不上传** |

⇒ 本仓库 `bin2_workshop_upload_fix` 的定位（用游戏自己的 `readWorkshopTxt` / `validatePreviewImage` /
`n_StartItemUpdate…` 一路调到最后一步**之前**）就是这个事实下的最优解：
**能自动校验到提交前一步，最后一下必须走向导。**

### H3. 顺带确认：base 手册里的 `_dogrig/forge/_paw_band.py` 社区拿不到

它在官方手册里只被提到一次（<https://companiondogs.pet/docs/en/modding.html>，用于生成「爪伤绷带贴图的
四个变体」）。三条证据说明它是**作者内部脚本**：已装的工坊包内 `find -name "*.py"` 为空；
GitHub 搜 `_dogrig` / `paw_band` / `companion+dogs+zomboid` 无对应仓库；base 只发布成品贴图。
它只涉及贴图，与骨架/网格无关 —— 所以本模组没做 `bandSkin` 是「社区没有这套工具」，
而不是「漏做」。
