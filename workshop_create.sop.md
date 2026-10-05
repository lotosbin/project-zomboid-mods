# 工坊物品创建标准作业流程 (Workshop Create SOP)

从零建一个可上传、可被游戏正确识别的 Project Zomboid 工坊物品。
本文所有字段规则都**反汇编自游戏自己的代码**（`zombie.core.znet.SteamWorkshopItem` /
`zombie.Lua.LuaManager$GlobalObject.getModFileReader`），不靠印象；文末给出复查命令。

> 与既有文档的关系：`modify.sop.md` 管**已有物品的版本更新**，`tranlate.sop.md` 管**翻译补丁**，
> 本文管**从零新建物品**。`guides/workshop-txt-guide.md` 是**面向字段速查**的同一份规格（含富文本 / BBCode
> 一节），2026-10-05 已按字节码改正（此前在 tags 分隔符、visibility 取值、preview 尺寸、
> `changelog=`/`preview_image=` 字段这几处是错的）；深入结论、探针命令、踩坑表都在本文。

---

## 参数（开工前先填）

```
物品名(英文, 无空格):        <item>            # 决定 ~/Zomboid/Workshop/<item> 与上传向导里的显示名
模组 ID(ModId):              <ModId>           # mod.info 的 id=，也是 getModFileReader 的查表键
游戏版本目录:                42.21 / 42.19.0 / common
工坊标题:                    中英双语，带上 Build 42
依赖的模组 id:               \ZombieBuddy 之类
可见性:                      private（开发期）→ public（发布）
```

---

## 1. 目录骨架（上传时**选这一层**）

```
<item>/                            ← 工坊物品根；上传向导里选的就是这一层（含 workshop.txt 的那层）
├── workshop.txt                   # 工坊元数据（必须在根）
├── changelog.txt                  # 给人看的更新说明（仓库惯例，见 §5）
├── preview.png                    # 工坊预览图：正方形 256x256 或 512x512，见 §7
└── Contents/
    └── mods/<ModId>/
        ├── <版本目录>/             # 例：42.21、42.19.0、42
        │   ├── mod.info
        │   ├── Changelog.txt      # 游戏内更新弹窗读这个，见 §4
        │   ├── poster.png         # 模组列表海报（惯例 512x512）
        │   └── media/             # lua / ui / java / scripts …
        └── common/                # 跨版本共享文件（可有可无）
```

**只有 `Contents/` 会被上传。** `getContentFolder()` 就是 `<item>/Contents`；证据：订阅后本机落盘的是
`.../steamapps/workshop/content/108600/<id>/mods/<ModName>/...` —— 上传根里的 `mods/` 正好对应
`Contents/mods/`。所以**放在物品根的 `changelog.txt`、README、源码都不进工坊包**（这没问题，它们本来
就是给人看的），而任何想让玩家拿到的文件**必须放进 `Contents/`**。

B41 老结构允许 mod 目录下直接是 `media/`（没有版本目录），本仓库 `bin2/Contents/mods/Respawn2/` 即此例；
B42 请用版本目录。

---

## 2. `mod.info`（放在版本目录里）

```ini
name=<ModId> (Build 42)
id=<ModId>
modversion=1.0.0
description=<模组列表里显示的一段话>
poster=poster.png
require=\ZombieBuddy          # 依赖的 mod id，用 \ 前缀；多个用逗号分隔
versionMin=42.21.0            # 最低游戏版本
javaJarFile=media/java/client/<ModId>.jar   # 路径相对**版本目录**
javaPkgName=<包名>
```

* `javaJarFile` 语义：含 `media/java/client/` = 仅客户端，`media/java/server/` = 仅服务端，
  放 `media/java/` = 两端都加载（专用服务器也加载）。
* 依赖写 `require=\<ModId>`；只有在依赖存在时才生效的功能，代码里要能**安静早退**（本仓库
  `bin2_companion_alpaca` 是范例）。
* 互斥模组在同一纹理上冲突时，用 `incompatible=` 声明（本仓库 `bin2_title_cover/*` 两套 16:9 / 21:9 即此例）。

---

## 3. `workshop.txt`（放在物品根）

游戏**只认这 6 个键**，其余一律被忽略（反汇编确认的完整键列表）：

| 键 | 取值 | 说明 |
| --- | --- | --- |
| `version` | `1` | 固定值，无实际用途 |
| `id` | 工坊 id | **首次上传前不要写**；有 `id=` 时向导走"更新已有物品"分支。上传成功后由向导写回并提交进仓库 |
| `title` | 字符串 | 工坊物品标题 |
| `description` | 字符串，**可重复** | 多行描述只能靠多行 `description=`，见下 |
| `tags` | `;` 分隔 | **必须**取自游戏 `media/WorkshopTags.txt` 白名单，见 §3.2 |
| `visibility` | `public` / `friendsOnly` / `private` / `unlisted` | 见 §3.3 |

`changelog=`、`preview_image=`、`author=`、`preview=` **都不存在**，写了也不会被解析。

### 3.1 `description` 的真实语义（本项目实测过）

* **分隔符是单个 `\n`**，不是空行：`description=A` + `description=B` ⇒ `A\nB`。
* 想要空一行，就**自己多写一行空的 `description=`**（空值行贡献一个空段落）。
* 值里写 `\n` 不会换行，会原样显示。
* 提交时 `getSubmitDescription()` 还会追加 `Workshop ID:` / `Mod ID:` 两行，不必自己写。
* 行首 `#` / `//` 是注释会被整行跳过；每行先 `trim()`；正文里出现字面量 `description=` 会被删掉
  —— 完整规则与两侧富文本方言（Steam BBCode / 游戏内 `<LINE>`）见 **§3.5**。

实测依据：本仓库某物品按 `\n` 拼接 = 1912 字符，游戏探针打印 `description = 1912 chars`；
按 `\n\n` 拼接会得到 1939，与探针不符。

### 3.2 `tags` 白名单（游戏 `media/WorkshopTags.txt`，共 31 个，原样照抄）

```
Build 40   Build 41   Build 42   Animals   Audio   Balance   Building   Clothing/Armor
Farming    Food       Framework  Hardmode  Interface  Items   Language/Translation
Literature Map        Military   Misc      Models    Multiplayer  Pop Culture
Realistic  Silly/Fun  Skills     Textures  Traits    Vehicles     QoL
WIP        Weapons
```

* 分隔符是 **`;`**（不是逗号），且游戏**不做 trim** —— `a; b` 会得到带前导空格的 ` b`，
  匹配不上白名单，Steam 侧静默忽略。
* 选 3~5 个：必带 `Build 42`（或 `Build 41`），再加类型标签（`Language/Translation`、`QoL`、
  `Interface`、`Map`、`Animals` …）。
* `tags=` 留空会 split 出一个**空标签**，等于没写，别留空。

### 3.3 `visibility` 取值（`getVisibilityInteger()`）

| 字面量 | 值 | 含义 |
| --- | --- | --- |
| `public` | 0 | 公开 |
| `friendsOnly` | 1 | 仅好友 |
| `private` | 2 | 私有（开发期用） |
| `unlisted` | 3 | 不列出 |
| 其它任何值（含拼错的 `privatee`、`friends`、留空） | **0** | ⚠️ **静默变成公开** |

注意是 `friendsOnly` 而不是 `friends`。发布前记得从 `private` 改成 `public`。

### 3.4 可直接抄的骨架（本仓库统一排版）

本仓库所有 `workshop.txt` 都用这套结构 —— 在 Steam 页面上呈现为「大标题 + 小标题 + 项目符号列表」：

```ini
version=1
title=<中英双语标题，含 Build 42>
description=[h1]<一句话标题>[/h1]
description=<它解决什么问题 / 是什么；结尾可带版本与版本要求>
description=
description=[h2]<小节名：症状 / 功能 / 包含模组 / 依赖 / 安装 / 已知限制 …>[/h2]
description=[list]
description=[*]<要点一>
description=[*]<要点二，续行也必须写 description= 前缀，行内用两个空格做视觉缩进>
description=[/list]
description=
description=[b]<不适合做小节的强调段>[/b]
description=…
description=
description=[ ALERT_CONFIG ]
description=link1 = GitHub = https://github.com/lotosbin/project-zomboid-mods,
description=link2 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/lotosbin,
description=link3 = 爱发电 = https://steamcommunity.com/linkfilter/?u=https://afdian.com/a/bin_2,
description=[ ------ ]
tags=Build 42;QoL;Misc
visibility=private
```

排版约定：

* 标题用 `[h1]`，小节用 `[h2]`，行内强调用 `[b]`；**不要用 Markdown** —— `#` 开头的行会被当注释整行丢掉，`- 列表` 在 Steam 上只是普通文本。
* 列表只能用「`[list]` + 每项一行 `[*]` + `[/list]`」，每项占一个 `description=` 行。
* 空行只能用**空的 `description=`**；续行/缩进的空格写在 `description=` **之后**。
* `[b]` / `[h2]` / `[list]` 必须成对闭合 —— 漏闭合会把游戏追加的 `Workshop ID:` / `Mod ID:` 行一起吞进列表。
* 结尾的 `[ ALERT_CONFIG ]` 块是社区约定（Mod Update and Alert System），**原样保留**，不要包进 BBCode。
* 全文 ≤ 8000 **字节**（见 §3.5.3）；改完用 §10 的 `check_all.sh` 一次校验全部物品。

### 3.5 富文本 / 排版：两侧方言别混用

先分清"哪份文件、在哪里显示、谁渲染"，这几种显示的富文本能力**完全不同**：

| 显示位置 | 读的文件 | 富文本方言 | 渲染者 |
| --- | --- | --- | --- |
| **Steam 工坊物品页**的简介 | 物品根 `workshop.txt` 的 `description=` | **Steam BBCode** | Steam 网页 / 客户端 |
| **游戏内 Mods 列表**右侧的描述 | `<版本目录>/mod.info` 的 `description=` | **PZ 自己的 `<LINE>` / `<RGB:…>`** | 游戏 `ISRichTextPanel`（`ModInfoPanelDesc.lua:33`） |
| 游戏内上传向导的简介输入框 | 上面那份 `workshop.txt` | 纯文本 `ISTextEntryBox`，**不预览 BBCode** | —— |

**游戏侧只做四件事，对 BBCode 一个字都不改**（`readWorkshopTxt()` 字节码 + 本仓库探针实测）：
每行 `trim()` → 用**单个 `\n`** 拼接 → 追加 `Workshop ID:` / `Mod ID:` 两行 → 原样交给
`n_SetItemDescription`。所以 `[b]` / `[h1]` / `[list]` 会**原封不动**送到 Steam 页面上被渲染。

#### 3.5.1 实测证据（可复现，**不需要 Steam**）

```bash
JAVA_DIR="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"
JAVAC="$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac"
JAVA="$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java"

"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d /tmp/bbprobe \
  bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java
cd "$JAVA_DIR" && "$JAVA" -Djava.awt.headless=true -cp /tmp/bbprobe:projectzomboid.jar \
  WorkshopTxtProbe "$HOME/Zomboid/Workshop/<item>"
```

喂进去的 `workshop.txt`（`#` 与 `//` 开头的行是注释）：

```ini
# 这行是注释（# 开头）——应被忽略
version=1
title=BBCode 探针
description=[h1]中文标题[/h1]
description=[b]加粗[/b] 与 [i]斜体[/i] 与 [url=https://example.com]链接[/url]
description=
description=[list]
description=[*]条目一
description=[*]条目二
description=[/list]
description=  ← 两个空格打头的缩进（写在 description= 之后）
// 行首两个斜杠也是注释——应被忽略
description=结尾
tags=Build 42;Misc
visibility=public
```

（带缩进那行**故意**在正文里写了字面量 `description=`，用来观察下文规则 3 的删除行为。）

实测输出（原样节选，`|…|` 是探针加的边界标记）：

```
readWorkshopTxt = true
title           = BBCode 探针
tags            = [Build 42, Misc]              ← 分号分隔、已 trim
visibility      = 0   (0=public 1=friendsOnly 2=private 3=unlisted)
description     = 126 chars / 198 bytes (UTF-8)
submitDesc      = 145 chars / 217 bytes   (Steam 上限 8000 字节，这里已含游戏自动追加的 Workshop ID / Mod ID 行)
--- getDescription() ---
|[h1]中文标题[/h1]|
|[b]加粗[/b] 与 [i]斜体[/i] 与 [url=https://example.com]链接[/url]|
||                                              ← 空 description= 贡献的空行
|[list]|
|[*]条目一|
|[*]条目二|
|[/list]|
|  ← 两个空格打头的缩进（写在  之后）|           ← 正文里的 "description=" 被删掉了（见规则 3）
|结尾|
--- getSubmitDescription() ---
|…同上…|
||
|Workshop ID: null|                             ← 游戏自动追加，不用自己写
```

#### 3.5.2 由此得到的 6 条硬规则

1. **空行不能靠空行**：真正的空行会被 `line.isEmpty()` 跳过 ⇒ 要空一行就写一行**空的 `description=`**。
2. **行首缩进会被吃掉**：整行先 `trim()`。要保留缩进（代码块、控制台日志），把空格写在 `description=`
   **之后**：`description=  start update of existing item`（本仓库已发布物品就是这么排的）。
3. **正文里不能出现字面量 `description=`**：解析用的是 `replace("description=", "")`，会删掉**所有**出现。
4. **行首 `#` / `//` 会被当注释整行丢掉**，别用它们开头写正文（Steam BBCode 不用这两个符号，通常无害）。
5. **值里写 `\n` 不会换行**，会原样显示；换行只能再写一行 `description=`。
6. **未闭合的 BBCode 会吞掉追加的 ID 行**：`getSubmitDescription()` 把那两行直接接在描述末尾，
   少一个 `[/list]` / `[/quote]`，`Workshop ID:` / `Mod ID:` 就会被折进列表或引用块里。

#### 3.5.3 Steam BBCode 常用标签（平台侧能力，不是 PZ 功能）

| 标签 | 效果 |
| --- | --- |
| `[b]…[/b]` `[i]…[/i]` `[u]…[/u]` `[strike]…[/strike]` | 粗体 / 斜体 / 下划线 / 删除线 |
| `[h1]…[/h1]` `[h2]` `[h3]` | 标题（自动换行、字号递减） |
| `[list]` + 每行 `[*]条目` + `[/list]`；`[olist]` | 无序 / 有序列表（**每项各占一行 `description=`**） |
| `[url=链接]文字[/url]`、`[url]链接[/url]` | 链接（站外链接 Steam 会加跳转提示；本仓库 ALERT_CONFIG 用的 `linkfilter/?u=` 只是那个社区约定的写法） |
| `[img]图片URL[/img]` | 图片（必须是公网可达的 URL） |
| `[quote]…[/quote]`、`[code]…[/code]` | 引用块、代码块 |
| `[spoiler]…[/spoiler]` | 折叠的剧透块 |
| `[hr][/hr]` | 分隔线 |
| `[noparse]…[/noparse]` | 原样显示标记本身 |
| `[previewyoutube=视频ID][/previewyoutube]` | 内嵌 YouTube |

**长度上限**：Steamworks 定义 `k_cchPublishedDocumentDescriptionMax = 8000`，单位是**字节**（UTF-8），
不是字符 —— 一个汉字占 3 字节，所以纯中文简介约 2600 字封顶，而且这个额度要和 BBCode 标记、
游戏追加的 ID 行一起算。本仓库现有 17 份 `workshop.txt` 实测最大 **3015 字节**
（`bin2_companion_alpaca`），余量充足；用 §10 的探针可以看到自己的 `submitDesc = … bytes`。

> 这一节里"Steam 侧渲染"的结论来自 Steam 平台文档（见文末"参考资料"），**本次未做真实上传验证**；
> 而"游戏侧不转义、原样透传"是上面探针的实测结果。上传后打开工坊页面看一眼渲染结果是最稳的收尾。

#### 3.5.4 游戏内那份（`mod.info`）的富文本方言

`ModInfoPanelDesc.lua:33` 用 `ISRichTextPanel` 渲染 `modInfo:getDescription()`，标签解析器就在
`media/lua/client/ISUI/ISRichTextPanel.lua` 的 `processCommand()` 里；标签用 `<…>` 包裹：

| 标签 | 效果 |
| --- | --- |
| `<LINE>` | 换行（游戏翻译文件里到处在用，如 `IG_UI.json` 的新手教程文本） |
| `<BR>` | 空一行 |
| `<H1>` / `<H2>` / `<TEXT>` | 大标题（居中白色）/ 小标题（左对齐浅灰）/ 恢复正文样式 |
| `<CENTRE>` `<LEFT>` `<RIGHT>` | 对齐方式 |
| `<RGB:r,g,b>` | 设颜色，分量是 0~1 小数（`<RGB:0.7,0.7,0.7>`） |
| `<PUSHRGB:r,g,b>` + `<POPRGB>` | 颜色入栈 / 出栈（可嵌套） |
| `<RED>` `<ORANGE>` `<GREEN>` `<GHC>` `<BHC>` | 预设色；`GHC`/`BHC` 取游戏当前"好/坏"高亮色 |
| `<SIZE:small\|medium\|large\|intro\|credits1\|credits2>` | 字号 |
| `<IMAGE:路径[,宽,高]>`、`<IMAGECENTRE:…>`、`<VIDEOCENTRE:…>` | 插图 / 居中插图 / 内嵌视频 |
| `<KEY:绑定名>` | 直接渲染当前玩家的按键名（手柄/键鼠自适应） |
| `&lt;` `&gt;` | 转义出真正的尖括号 |

注意：这些标签**只在游戏内有效**；写进 `workshop.txt` 只会原样显示在工坊页面上（BBCode 写进 `mod.info`
同理，游戏不认）。`mod.info` 的 `description=` 是**单个值**，要换行只能写 `<LINE>`，不能多行重复键。

---

## 4. `Changelog.txt`：游戏内更新弹窗（**在版本目录或 `common/`**）

`getModFileReader(modID, file)` 的解析顺序（反汇编确认）：

1. `ChooseGameInfo.getModDetails(modID).getVersionDir() + "/" + file`
2. 上一步的文件不存在 ⇒ `getCommonDir() + "/" + file`
3. 以 **UTF-8** 读；查不到 modID 直接返回 `null`

所以 `Changelog.txt` 要放在 **`Contents/mods/<ModId>/<版本目录>/`** 或 **`common/`**。
**放物品根（`<item>/Changelog.txt`）游戏读不到**（那个位置既不上传也查不到表）。

格式（供 Mod Update and Alert System 使用）：

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://github.com/lotosbin/project-zomboid-mods,
link2 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/lotosbin,
link3 = 爱发电 = https://steamcommunity.com/linkfilter/?u=https://afdian.com/a/bin_2,
[ ------ ]

[ 10/04/2026 ]
版本 1.0.0 (2026-10-04)
- 初始发布：<做了什么>
- 已知限制：<例如"未在 Linux 上实测">
[ ------ ]
```

要点：每个块以 `[ ------ ]` 结束；日期用 `MM/DD/YYYY`，游戏按时间倒序显示；
外部链接**必须**套 Steam 链接过滤器 `https://steamcommunity.com/linkfilter/?u=<原始链接>`。

> **文件名大小写要注意**：本仓库统一用 `Changelog.txt`（小写 `l`），Wiki 也写作 `Changelog.txt`；
> 但消费它的 `[B42] Mod Manager` 兼容层实际请求的是 **`ChangeLog.txt` / `ChangeLog.md`（大写 `L`）**。
> Windows / macOS 的文件名不区分大小写，两种写法都能命中；**只有 Linux 客户端（区分大小写）会暴露差异**。
> 如果你要照顾 Linux 客户端，最稳的做法是同时提供两个文件名（或与目标模组版本保持一致）。

> **这套 ALERT_CONFIG 是社区模组（Mod Update and Alert System / Chuckleberry Finn 系列）提供的，不是游戏本体功能。**
> 详见 `docs/pz_mod_update_alert_system.md`。把同样的块写进 `workshop.txt` 的 `description=` 只会显示在
> **工坊页面**上，游戏内不解析它 —— 两处都写是有意义的（功能 + 页面展示）。

---

## 5. 物品根的 `changelog.txt`：给人看的那份（仓库惯例）

* 全小写 `changelog.txt`、放物品根；**不进工坊包、游戏不读**，纯粹是仓库文档。
* 首行固定 `版本 X.Y.Z (YYYY-MM-DD)`，每条一行 `- `。
* 如实写"未做/未验证"的部分（本仓库多条 changelog 都带"已知限制"）。

---

## 6. `poster.png`（模组列表海报）

* 由 `mod.info` 的 `poster=poster.png` 指定，放版本目录。
* 游戏**不做尺寸校验**（仓库里 512x512、512x768 都在用），惯例 512x512。

---

## 7. `preview.png`（工坊预览图，**硬性规则**）

来自 `SteamWorkshopItem.validatePreviewImage(Path)`：

| 规则 | 不满足时的返回值 |
| --- | --- |
| 存在 / 可读 / 不是目录 | `PreviewNotFound` |
| 文件 ≤ **1024000** 字节 | `PreviewFileSize` |
| 正方形（`width == height`）且边长**只能是 256 或 512** | `PreviewDimensions` |
| 能被 `zombie.core.textures.PNGDecoder` 解析（即必须是 PNG） | `PreviewFormat` |

⇒ 用 **256x256**（或 512x512），不要用 1024 —— 已实测 1024 会被判 `PreviewDimensions`。

生成方式要可复现，别手绘丢进来：本仓库 `bin2_workshop_upload_fix/tools/make_images.py` 是纯 Pillow
绘制 + 断言尺寸 + 逐行检查文字溢出，`--check` 可打印现有尺寸与上面的规则表。256 与 512 需要**两套排版**
（把 512 的设计直接缩小会让 10px 字变 7px）。

---

## 8. 执行步骤

1. 按 §1 建目录骨架（`<item>/Contents/mods/<ModId>/<版本目录>/`）。
2. 写 `mod.info`（§2）与 `media/` 内容；Lua 语法自检（`luac -p` 或仓库既有 `tools/check.sh` 套路）。
3. 写 **版本目录** 的 `Changelog.txt`（§4，含 `[ ALERT_CONFIG ]`）。
4. 写物品根的 `changelog.txt`（§5）。
5. 写 `workshop.txt`（§3）。**首次上传前不要写 `id=`**，`visibility=private`。
6. 生成 `preview.png`（256²）与版本目录的 `poster.png`（512²）。
7. **本地上传链路自检**（§10），必须 `readWorkshopTxt=true` 且 `validatePreviewImage=OK`。
8. 挂 staging 软链并本地加载：

   ```bash
   ln -sfn "$PWD/<item>" ~/Zomboid/Workshop/<item>                  # 上传向导可见
   ln -sfn "$PWD/<item>/Contents/mods/<ModId>" ~/Zomboid/mods/<ModId>   # 本地加载
   ```

   软链是安全的，两条独立证据：`SteamWorkshop.getStageFolders()` 里的
   `Files.isDirectory(path, new LinkOption[0])` **不带** `NOFOLLOW_LINKS` ⇒ 软链目录会出现在上传向导列表里；
   `ZomboidFileSystem.validatePrefix()` 只是 `normalizeToPath()` 后做 `Path.startsWith(白名单)`，
   不解析软链 ⇒ **实测**把物品软链到本仓库路径后，探针依旧 `readWorkshopTxt=true`
   （若它解析了软链，就会抛 `IllegalArgumentException: Invalid prefix found for: /Volumes/…`）。
9. 游戏内 **Mods** 启用模组（Java 模组还要在 ZombieBuddy 弹窗里允许加载），进主菜单确认无红字报错。
10. 打开 **Workshop 上传向导** → 选 `~/Zomboid/Workshop/<item>` 这一层 → 走完向导。
    ⚠️ 向导里有原生确认弹窗，**全屏/无边框时可能看不见**，建议窗口化。
    macOS/Linux 若报 `error requesting Steam to update the item`，装本仓库 `bin2_workshop_upload_fix`。
11. 成功判据：向导日志出现 success；Steam 客户端 `logs/workshop_log.txt` 出现该物品的 update 记录；
    工坊页面体积不再是 `0.000 B`。
12. 向导会把 `id=` 写回 `workshop.txt` ⇒ **提交进仓库**，下次即走"更新"分支。
13. 内容稳定后把 `visibility` 改成 `public`，按 `modify.sop.md` 走后续版本更新。

---

## 9. 常见错误（每条都真实踩过 / 反汇编确认）

| 症状 | 根因 | 正解 |
| --- | --- | --- |
| 描述在工坊页面上挤成一坨 | 以为多行 `description=` 之间会自动空行 | 分隔符是单个 `\n`；想要空行就多写一行空的 `description=` |
| 页面上显示成一堆方括号原文 / 排版没生效 | 标签没成对闭合、或在**游戏内向导输入框**里看（那里是纯文本编辑框，从不预览 BBCode） | 成对闭合；渲染结果只看 Steam 工坊页面（§3.5.3） |
| 代码块 / 控制台日志的缩进在页面上没了 | 整行先被 `trim()` | 把空格写在 `description=` **之后**（§3.5.2 规则 2） |
| 描述里某一段莫名少了一截 | 正文出现字面量 `description=`，被 `replace` 删掉了 | 正文别写 `description=`（§3.5.2 规则 3） |
| 某一整行在工坊页面上完全不见了 | **续行忘了写 `description=` 前缀**（没带 `=` 的行被直接忽略） | 每个正文行都必须以 `description=` 开头；`check_all.sh` 会报 `没有 '='` |
| 页面上的快捷键 / 版本号 / 条目数已经过时 | 改了 `mod.info` 与代码，没同步 `workshop.txt` | 一起改；本次巡检发现 viewpoint 写着 F9/F10、A-Life 写着 v0.1.0、tikitown 写着 214 / 84 条，实际都已变（§10 的 check 只查格式，内容要靠人核） |
| `Workshop ID:` / `Mod ID:` 两行被折进列表或引用块 | BBCode 未闭合，游戏追加的 ID 行被裹进去了 | 补上 `[/list]` / `[/quote]` 等（§3.5.2 规则 6） |
| 工坊页面简介被截断 | 超过 8000 **字节**（汉字 3 字节/字） | 控到 8000 字节内，用探针看 `submitDesc = … bytes` |
| 标签在工坊页面上没生效 | 用了逗号分隔，或标签不在白名单 | 用 `;` 分隔，且照抄 `media/WorkshopTags.txt` |
| 明明写了 `visibility=private` 却是公开 | 值写错（如 `friends`、拼错）⇒ 静默返回 0 = public | 只能是 `public` / `friendsOnly` / `private` / `unlisted` |
| 上传成功但订阅者拿不到某个文件 | 文件放在 `Contents/` 之外 | 只有 `Contents/` 会打包 |
| 游戏内更新弹窗一直不出现 | `Changelog.txt` 放物品根了 | 放 `Contents/mods/<ModId>/<版本目录>/` 或 `common/`；文件名精确为 `Changelog.txt` |
| `PreviewDimensions` | preview 用了 1024 或非正方形 | 256x256 或 512x512 正方形 PNG |
| `PreviewFormat` | preview 不是 PNG（改了后缀的 jpg 也会中招） | 真 PNG，且 `PNGDecoder` 能解析 |
| `PreviewFileSize` | PNG 超过 1024000 字节 | 压到 1 MB 以内 |
| 向导里看不到物品 | 上传目录不是 `<item>` 这一层（选进了 `Contents`） | 选含 `workshop.txt` 的那一层 |
| 在 `Contents/mods/<ModId>/` 里另放了一份 `workshop.txt` 却毫无作用 | 游戏只在**物品根**读 `workshop.txt`（本仓库 `bin2/Contents/mods/Respawn2/workshop.txt` 就是这种历史遗留，它只会作为模组内容被打包上传） | 只保留物品根那一份 |
| `IllegalArgumentException: Invalid prefix found for: …` | 把**仓库路径**直接喂给 `SteamWorkshopItem` | 校验/上传都必须走 `~/Zomboid/Workshop/` 下的 staging 软链 |
| NPE 在 `isValidSteamID(null)` | 工具代码没判 `workshop.txt` 里没有 `id=` 的情况 | 自己写工具时先判空 |
| 更新了模组但玩家看到的是旧描述 | 只改了 `Contents/` 里的内容没更新 `workshop.txt` 的 `description` | 两者一起改 |

---

## 10. 上传前的本地自检（用游戏自己的解析器，别等上传失败）

`bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh`（不提交任何东西、不会真的上传）：

```bash
tools/pz_workshop_probe/run.sh                                   # 自动挑 ~/Zomboid/Workshop 下最新的物品
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/<item>      # 指定物品
```

它打印：`readWorkshopTxt` 结果、`id` / `title` / `visibility` / `tags` / `description` 长度、
`Contents` 与 `preview.png` 是否存在、`validatePreviewImage` 的结论；物品已有 `id=` 时还会逐个调用
`n_StartItemUpdate / n_SetItemTitle / n_SetItemDescription / n_SetItemVisibility / n_SetItemTags /
n_SetItemContent / n_SetItemPreview`（**唯独不调 `n_SubmitItemUpdate`**），证明上传前 native 链路是通的。

**只看 `workshop.txt` 的解析结果**（排版/富文本/换行）用同目录的第二个探针 —— 它**不需要 Steam 客户端、
也不加载 native 库**，只初始化 `ZomboidFileSystem`，把 `description` 与 `getSubmitDescription()` 逐行
用 `|` 括起来打印，空行与缩进都看得见，并给出 UTF-8 字节数：

```bash
JAVA_DIR="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"
JAVAC="$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac"
JAVA="$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java"

"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d /tmp/bbprobe \
  bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java
cd "$JAVA_DIR" && "$JAVA" -Djava.awt.headless=true -cp /tmp/bbprobe:projectzomboid.jar \
  WorkshopTxtProbe "$HOME/Zomboid/Workshop/<item>"
```

⚠️ 参数只能传 `~/Zomboid/Workshop/<item>` 这类白名单路径（软链即可）；传仓库路径会抛
`IllegalArgumentException: Invalid prefix found for: …`（§9）。

**一次校验仓库里所有 `workshop.txt`**（编译一次 → 每份复制进白名单 staging → 跑完自动清理）：

```bash
bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh              # 扫仓库根
bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh <仓库根>     # 指定仓库根
```

输出每个物品一行 `read / tags / vis / desc÷submit 字节数`，并把问题打在下面：

| 检查项 | 为什么要查 |
| --- | --- |
| `tags` 全部命中 `media/WorkshopTags.txt` | 不在白名单里的标签 Steam 静默忽略 |
| 只有那 6 个合法键 | 其余键（含写错的、或**忘了写 `description=` 前缀**的续行）会被整行忽略 |
| `description` 值里没有字面量 `description=` | `replace("description=","")` 会把正文删掉 |
| BBCode 成对闭合 | 未闭合会吞掉游戏追加的 `Workshop ID:` / `Mod ID:` 行 |
| `submitDescription` ≤ 8000 字节 | Steam 上限，汉字 3 字节/字 |

全通过时最后一行是 `ALL CHECKS PASSED (N item(s))`；有问题时退出码为 1，可直接接进 CI。

自检清单：

- [ ] `mod.info`：`id` / `name` / `modversion` / `poster` / `require` / `versionMin` 齐全
- [ ] `workshop.txt`：`version=1`、多行 `description=`、`tags` 在白名单内、`visibility` 是本次想要的
- [ ] 简介排版：空行用空 `description=`、缩进写在 `=` 之后、BBCode 成对闭合、`submitDesc` ≤ 8000 字节（§3.5）
- [ ] `Changelog.txt` 在**版本目录或 `common/`**，含 `[ ALERT_CONFIG ]` 块
- [ ] `preview.png` 256x256（或 512x512）正方形 PNG ≤1024000 字节
- [ ] `poster.png` 在版本目录里且 `mod.info` 的 `poster=` 指对了
- [ ] 物品根 `changelog.txt` 首行是 `版本 X.Y.Z (日期)`
- [ ] 探针输出：`readWorkshopTxt=true`、`validatePreviewImage=OK`、`contentFolder exists=true`
- [ ] staging 软链就位，游戏 Mods 里已启用且主菜单无报错
- [ ] 上传后：`id=` 写回并提交进仓库

### 想自己复查本文的结论（复用同一套反汇编）

```bash
JAR=~/Library/Application\ Support/Steam/steamapps/common/ProjectZomboid/Project\ Zomboid.app/Contents/Java/projectzomboid.jar
mkdir -p /tmp/pzjar && unzip -q -o "$JAR" -d /tmp/pzjar && cd /tmp/pzjar

# workshop.txt 认哪些键 / 怎么拼接 description
javap -p -c zombie/core/znet/SteamWorkshopItem.class | sed -n '/public boolean readWorkshopTxt/,/^  public /p'
# visibility 字面量 → 整数
javap -p -c zombie/core/znet/SteamWorkshopItem.class | sed -n '/public int getVisibilityInteger/,/^  public /p'
# preview.png 的全部硬规则
javap -p -c zombie/core/znet/SteamWorkshopItem.class | sed -n '/public java.lang.String validatePreviewImage/,/^  public /p'
# Changelog.txt 到底从哪个目录读
javap -p -c 'zombie/Lua/LuaManager$GlobalObject.class' | sed -n '/public static java.io.BufferedReader getModFileReader/,/^  public /p'

# 上传只打包 Contents：订阅后落盘结构可佐证
ls ~/Library/Application\ Support/Steam/steamapps/common/ProjectZomboid/Project\ Zomboid.app/Contents/Java/steamapps/workshop/content/108600/<id>/mods/
```

---

## 参考资料

* 仓库内：`modify.sop.md`（版本变更）· `tranlate.sop.md`（翻译补丁）·
  `docs/pz_mod_update_alert_system.md`（ALERT_CONFIG 的真实机制与反汇编结论）·
  `docs/pz_b42_15_translation_guide.md`（B42.15+ JSON 翻译）
* 反汇编来源：`projectzomboid.jar` → `zombie/core/znet/SteamWorkshopItem.class`（`readWorkshopTxt` /
  `getSubmitDescription` / `getVisibilityInteger` / `validatePreviewImage`）、
  `zombie/core/znet/SteamWorkshop.class`（`SubmitWorkshopItem` → `n_SetItemDescription`）、
  `zombie/Lua/LuaManager$GlobalObject.class`（`getModFileReader`）（命令见 §10）
* 富文本来源：
  - 游戏内方言：`media/lua/client/ISUI/ISRichTextPanel.lua` 的 `processCommand()`（标签全集），
    消费方 `media/lua/client/OptionScreens/ModSelector/ModInfoPanelDesc.lua`（`ISRichTextPanel:new` + `modInfo:getDescription()`）
  - 实测探针：`bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java`
  - Steam 侧 BBCode 与长度上限：Steamworks `ISteamRemoteStorage`
    （`k_cchPublishedDocumentDescriptionMax = 8000` 字节）https://partner.steamgames.com/doc/api/ISteamRemoteStorage
    · Steam 社区"文本格式"说明页（标签表）https://steamcommunity.com/comment/Guide/formattinghelp
* 标签白名单来源：游戏目录 `media/WorkshopTags.txt`
* 可运行的完整范例（本仓库已发布物品）：
  - `bin2_workshop_upload_fix/` —— 单模组 + Java/ZombieBuddy 补丁 + 自带探针工具，最完整的模板
  - `bin2_nested_containers_take/` —— `<版本目录>` + `common/` 双目录结构
  - `bin2_b42/` —— 一个物品里塞多个 mod、多版本目录的集合型物品
  - `bin2_companion_alpaca/` / `bin2_blocky_alpaca/` —— 依赖第三方模组的 add-on
* 官方 / 社区：
  - PZ Wiki · Mod Update and Alert System：https://pzwiki.net/wiki/Mod_Update_and_Alert_System
  - PZ Wiki · Modding：https://pzwiki.net/wiki/Modding
  - Steam Workshop 上传：https://steamcommunity.com/app/108600/workshop/
