---
name: pz-workshop-item-publishing
description: Package, validate, and publish a Project Zomboid mod as a Steam Workshop item. Covers the item folder layout, mod.info fields, workshop.txt format (multi-line description, tag whitelist, visibility, when to write id=), changelog.txt convention, poster.png and preview.png hard rules (square, 256 or 512, <=1024000 bytes, PNG), staging under ~/Zomboid/Workshop, the in-game upload wizard and id write-back, and validating all of it with the game's own parsers before uploading.
whenToUse: The task is about workshop.txt, changelog.txt, preview.png / poster.png, mod.info, staging or symlinking an item into ~/Zomboid/Workshop, the in-game Workshop upload wizard, a workshop item stuck at 0.000 B, publishing/updating this repo's mods to the Steam Workshop, or validating a Workshop item before upload.
---

# PZ 工坊物品：打包 → 校验 → 发布

所有规则都来自**游戏自己的代码**（`zombie.core.znet.SteamWorkshopItem` / `SteamWorkshop`）与
本仓库已发布的物品；不要凭印象写字段，写完用第 7 节的探针验一遍。

## 1. 物品目录布局（Steam 上传时选**这一层**）

```
<item>/                       ← 磁盘上是 ~/Zomboid/Workshop/<name>；仓库里就是 bin2_xxx/
├── workshop.txt              # 工坊信息（本文件必须在这一层）
├── preview.png               # 工坊物品预览图，256x256（硬性规则见 §4）
├── changelog.txt             # 更新说明（人在看，随物品一起打包）
└── Contents/mods/<ModId>/<ver>/
    ├── mod.info
    ├── poster.png            # 模组列表海报，512x512（惯例）
    └── media/…               # lua/ java/ scripts/ 等真正的内容
```

游戏侧的路径是怎么来的（`SteamWorkshopItem` 字节码）：

| 方法 | 返回 | 含义 |
| --- | --- | --- |
| `getContentFolder()` | `<item>/Contents` | 上传的内容根；**只打包这个目录**（所以 `Contents` 之外的文件不会进工坊） |
| `getPreviewImage()` | `<item>/preview.png` | 预览图，`validatePreviewImage()` 校验的就是它 |
| `getFolderName()` | `<item>` 的目录名 | 上传向导列表里显示的名字 |

- 版本目录名用游戏版本（`42.21`、`42` 都见过）。`mod.info` 放版本目录或 `common/` 都能被识别，
  本仓库统一放**版本目录**。
- `Contents` 与 `Contents/mods/<ModId>` 之外的东西（`workshop.txt`、`preview.png`、`changelog.txt`、
  工程源码、`java/`）不会被打包进模组内容，放在物品根目录是安全的。

## 2. `workshop.txt` 规格

格式：每行一条 `key=value`；`description=` **可以重复出现，按行累加**（多行描述就写多行
`description=`，**不要**在值里塞 `\n`）。

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `version` | `1` | 固定 |
| `id` | 已发布后的工坊 id | **首次上传前不要写**；写了游戏会走"更新已有物品"分支。上传成功后由向导写回 |
| `title` | 显示标题 | 会作为工坊物品标题提交（`n_SetItemTitle`） |
| `description` | 多行 | 提交时游戏还会自动追加 `Workshop ID:` / `Mod ID:` 行（`getSubmitDescription()`） |
| `tags` | `;` 分隔 | **必须**取自游戏 `media/WorkshopTags.txt`（如 `Build 42`、`QoL`、`Misc`、`Interface`、`Framework`、`Language/Translation`） |
| `visibility` | `public` \| `private` | 解析成 `getVisibilityInteger()`：**`0` = public，`2` = private** |

可直接抄的骨架：

```ini
version=1
title=<标题（中英双语，含 Build 42）>
description=<一句话：这个模组解决什么问题>
description=
description=依赖 / 安装 / 生效标志 / 已知限制……
description=
description=源码与完整分析：<仓库链接>
tags=Build 42;QoL;Misc
visibility=public
```

实测（探针打印，说明格式被游戏接受）：

```
readWorkshopTxt = true
title           = ZB Workshop Upload Fix - 修复 macOS/Linux 上传创意工坊失败 (Build 42)
visibility      = 0                       # public
tags            = [Build 42, QoL, Misc]   # 在白名单内才会这样解析出来
description     = 1680 chars              # 多行 description= 累加正确
```

## 3. `changelog.txt` 规格

没有解析逻辑（游戏不会读它，但会被打包进物品），所以按**仓库惯例**写给人看：

```
版本 1.0.0 (2026-10-03)
- 初始发布：<做了什么>
- 根因：<一句话，方便别人搜到>
- 已知限制：<例如"未在 Linux 上实测""未做真实上传验证">
```

要点：**首行 `版本 X.Y.Z (YYYY-MM-DD)`**；每条一行 `- `；把"未做/未验证"的部分**如实写出来**。

## 4. 图片规格：`preview.png` 是硬性的，`poster.png` 不是

### `preview.png`（物品根目录，工坊预览）

来自 `SteamWorkshopItem.validatePreviewImage(Path)` 的字节码：

| 规则 | 不满足时 |
| --- | --- |
| 存在 / 可读 / 不是目录 | `PreviewNotFound` |
| 文件 ≤ **1024000** 字节 | `PreviewFileSize` |
| **正方形，边长只能是 256 或 512** | `PreviewDimensions` |
| 能被 `zombie.core.textures.PNGDecoder` 解析（即必须是 PNG） | `PreviewFormat` |

⇒ 用 **256x256**（或 512x512），不要用 1024 —— 本仓库里两种尺寸都有，照抄 1024 会被游戏判
`PreviewDimensions`（已实测：1024 → `PreviewDimensions`，256 → `OK`）。

### `poster.png`（`<ver>/poster.png`，模组列表海报）

- 由 `mod.info` 的 `poster=poster.png` 指定；游戏**不做尺寸校验**（仓库里 512x512、512x768 都在用）。
- 惯例 512x512。

### 生成方式（可复现，不要手绘后丢进来）

`bin2_workshop_upload_fix/tools/make_images.py`：纯 Pillow 绘制（无网络）、
**断言输出尺寸**、逐行检查文字是否溢出画布、`--check` 打印现有尺寸与上面的规则表。
256 与 512 是**两套排版**（小尺寸直接缩小 512 的设计会让 10px 字变 7px 看不清）。
配色/观感对齐仓库既有模组（深色 + 细网格 + 等宽"终端日志"卡片）。

## 5. `mod.info` 里与发布相关的字段

```ini
name=ZB Workshop Upload Fix (macOS / Linux)
id=ZBWorkshopUploadFix
modversion=1.0.0
description=<模组列表里显示的一段话（英文/双语）>
poster=poster.png
require=\ZombieBuddy          # 依赖的 mod id，用 \ 前缀
ZBVersionMin=2.0.0            # 依赖框架的最低版本
javaJarFile=media/java/client/<ModId>.jar   # 相对**版本目录**
javaPkgName=<包名>
```

- `javaJarFile` 路径语义：含 `media/java/client/` = 仅客户端（专用服务器跳过），
  `media/java/server/` = 仅服务端，两边都要就放 `media/java/`。
- 依赖写 `require=\<ModId>`，多个用逗号分隔。

## 6. staging 与上传

**软链当待上传目录是安全的**，两条都从游戏代码确认过：

1. `SteamWorkshopItem` 构造函数的 `ZomboidFileSystem.validatePrefix()` 接受符号链接路径；
2. `SteamWorkshop.getStageFolders()` 的过滤器是 `Files.isDirectory(path, new LinkOption[0])`
   （没有 `NOFOLLOW_LINKS`）⇒ 软链目录会出现在上传向导的列表里。

```bash
ln -sfn "$PWD/bin2_xxx" ~/Zomboid/Workshop/bin2_xxx    # 待上传目录（上传向导可见）
ln -sfn "$PWD/bin2_xxx/Contents/mods/<ModId>" ~/Zomboid/mods/<ModId>   # 本地加载
```

上传流程：

1. 游戏内 **Mods** 启用模组（ZB Java 模组还要在 ZB 弹窗里允许加载）；
2. 打开 Workshop 上传向导 → 选 `~/Zomboid/Workshop/<name>` 这一层的物品；
3. 填/确认标题描述 → 走完向导（**注意窗口化**：向导里有原生确认弹窗，
   全屏/无边框时可能看不见）；
4. 成功判据：向导日志出现 success；Steam 客户端 `workshop_log.txt` 出现该物品的
   **update/上传记录**；工坊页面的物品体积不再是 `0.000 B`；
5. 向导会把 `id=` 写回 `workshop.txt`（把它提交进仓库），下次上传即走"更新"分支。

更新：改内容 → 更新 `changelog.txt` 与 `workshop.txt` 的 `description` → 重新跑一遍向导。

## 7. 上传前的校验（用游戏自己的解析器，别等上传失败）

`bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh`（不提交任何东西）：

```bash
tools/pz_workshop_probe/run.sh                       # 自动挑 ~/Zomboid/Workshop 下最新的物品
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/<name>
```

它打印：`readWorkshopTxt` 的结果、id/title/visibility/tags/description 长度、`Contents` 与
`preview.png` 是否存在、**`validatePreviewImage` 的结论**；若物品已有 `id=`，还会逐个调用
`n_StartItemUpdate / n_SetItemTitle / n_SetItemDescription / n_SetItemVisibility / n_SetItemTags /
n_SetItemContent / n_SetItemPreview`（**唯独不调 `n_SubmitItemUpdate`**），证明上传前的 native 链路是好的。

## 8. 踩坑清单（每条都真实踩过）

- **绝不能把仓库路径直接喂给 `SteamWorkshopItem`**：`validatePrefix()` 只认白名单前缀
  （`~/Zomboid/Workshop/…`、mods 目录等），传仓库路径会抛
  `IllegalArgumentException: Invalid prefix found for: …`。校验/上传都必须走 staging 目录（软链或拷贝）。
- `preview.png` 用 1024 → 游戏判 `PreviewDimensions`；必须 256 或 512 的正方形。
- `workshop.txt` 里**没有 `id=`** 时，自己写工具要判空（本仓库探针一开始就在
  `isValidSteamID(null)` 上 NPE 过）。
- 多行描述只能靠多行 `description=`；写 `\n` 会原样显示。
- `tags` 乱写不在白名单里不会报错，但会被 Steam 忽略 → 从 `media/WorkshopTags.txt` 里挑。
- 物品内**只打包 `Contents/`**：想让某个文件进工坊就必须放在 `Contents` 下；
  物品根的 `preview.png`/`changelog.txt` 是工坊元数据，不是模组内容。
- 发布前记得把 `visibility` 从 `private` 改成 `public`（`getVisibilityInteger()` 2→0）。

## 9. 发布前自检清单

- [ ] `Contents/mods/<ModId>/<ver>/mod.info`：`id` / `name` / `modversion` / `poster` / `require` 齐全
- [ ] `workshop.txt`：`version=1`、多行 `description=`、`tags` 在白名单内、`visibility` 是本次想要的
- [ ] `preview.png` 256x256（或 512x512）正方形 PNG ≤1024000 字节
- [ ] `poster.png` 在版本目录里且 `mod.info` 的 `poster=` 指对了
- [ ] `changelog.txt` 首行是 `版本 X.Y.Z (日期)`，并写明已知限制
- [ ] 探针：`readWorkshopTxt=true`、`validatePreviewImage=OK`、`contentFolder exists=true`
- [ ] staging 软链就位（`~/Zomboid/Workshop/<name>`）且游戏 Mods 里已启用
- [ ] 上传后：`id=` 写回并提交进仓库；必要时重跑本仓库的补丁脚本（游戏更新会覆盖游戏文件）
