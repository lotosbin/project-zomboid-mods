# Workshop.txt 配置指南

`workshop.txt` 是 Project Zomboid 工坊物品的元数据文件，**放在物品根目录**（含 `Contents/` 的那一层）。
本文所有字段规则**反汇编自游戏自己的代码**（`zombie.core.znet.SteamWorkshopItem` /
`zombie.core.znet.SteamWorkshop`）并用本仓库探针实测过；需要从零新建物品的完整流程看
[`workshop_create.sop.md`](../workshop_create.sop.md)，发布前自检清单见 skill
`pz-workshop-item-publishing`。

> 本文曾长期存在 5 处字段描述错误（`tags` 分隔符、`visibility` 取值、`preview` 尺寸、
> `changelog=`/`preview_image=` 字段、文件位置），2026-10-05 已按字节码逐条改正。

## 目录

- [文件位置与格式](#文件位置与格式)
- [字段说明](#字段说明)
- [多行描述的真实语义](#多行描述的真实语义)
- [富文本与排版](#富文本与排版)
- [图片规格](#图片规格)
- [上传流程](#上传流程)
- [常见问题](#常见问题)
- [参考资料](#参考资料)

---

## 文件位置与格式

```
<item>/                          ← 上传时选这一层
├── workshop.txt                 ← 就是这里（游戏只认物品根这一份）
├── preview.png                  ← 工坊预览图（硬性规则见下文）
├── changelog.txt                ← 给人看的更新说明（游戏不读，随物品一起打包）
└── Contents/mods/<ModId>/<版本目录>/
    ├── mod.info
    └── media/…
```

- 格式是每行一条 `key=value` 的纯文本（UTF-8）。
- **游戏只认 6 个键**：`version`、`id`、`title`、`description`、`tags`、`visibility`；
  其余行一律静默忽略。
- 行首 `#` 或 `//` 的行被当作注释整行跳过；空行跳过；每行先 `trim()`。
- 放在 `Contents/mods/<ModId>/` 里的 `workshop.txt` **完全没有作用**（它只会作为模组内容被打包上传）。

## 字段说明

| 键 | 取值 | 说明 |
| --- | --- | --- |
| `version` | `1` | 固定值，无实际用途 |
| `id` | 工坊 id | **首次上传前不要写这一行**；有 `id=` 时向导走"更新已有物品"分支。上传成功后向导写回，记得提交进仓库 |
| `title` | 字符串 | 工坊物品标题 |
| `description` | 字符串，**可重复出现** | 多行描述只能靠多行 `description=`，见下节 |
| `tags` | `;` 分隔 | **必须**取自游戏 `media/WorkshopTags.txt` 白名单 |
| `visibility` | `public` / `friendsOnly` / `private` / `unlisted` | 见下 |

**`tags` 白名单**（游戏 `media/WorkshopTags.txt`，原样照抄，共 31 个）：
`Build 40` `Build 41` `Build 42` `Animals` `Audio` `Balance` `Building` `Clothing/Armor` `Farming`
`Food` `Framework` `Hardmode` `Interface` `Items` `Language/Translation` `Literature` `Map` `Military`
`Misc` `Models` `Multiplayer` `Pop Culture` `Realistic` `Silly/Fun` `Skills` `Textures` `Traits`
`Vehicles` `QoL` `WIP` `Weapons`

- 分隔符是 **`;`**（不是逗号），且游戏**不做 trim**：写 `a; b` 会得到带前导空格的 ` b`，匹配不上白名单，
  Steam 侧静默忽略。→ 写 `Build 42;QoL;Misc`。
- 选 3~5 个：必带 `Build 42`（或 `Build 41`），再加类型标签。

**`visibility` 取值**（`getVisibilityInteger()`）：

| 字面量 | 值 | 含义 |
| --- | --- | --- |
| `public` | 0 | 公开 |
| `friendsOnly` | 1 | 仅好友 |
| `private` | 2 | 私有（开发期用） |
| `unlisted` | 3 | 不列出 |
| 其它任何值（含拼错的 `friends`、`privatee`、留空） | **0** | ⚠️ **静默变成公开** |

**不存在的字段**：`changelog=`、`preview_image=`、`author=`、`preview=` 都不存在，写了不会被解析。
更新说明请写**物品根的 `changelog.txt`** 和**版本目录的 `Changelog.txt`**（后者才是游戏内更新弹窗读的那个）。

## 多行描述的真实语义

来自 `readWorkshopTxt()` 字节码 + 本仓库 `WorkshopTxtProbe` 实测：

1. **分隔符是单个 `\n`**：`description=A` + `description=B` ⇒ `A\nB`（不会自动空行）。
2. **想要空一行**，就写一行**空的 `description=`**；真正的空行会被 `isEmpty()` 跳过。
3. **每行先 `trim()`**：行首缩进会被吃掉。要保留缩进（代码块、控制台日志），把空格写在 `description=`
   **之后**：`description=  start update of existing item`。
4. **值里写 `\n` 不会换行**，会原样显示。
5. **正文里不能出现字面量 `description=`**：解析用 `replace("description=", "")`，会删掉所有出现。
6. 提交时 `getSubmitDescription()` 会自动追加 `Workshop ID:` / `Mod ID:` 两行，不必自己写。

可直接抄的骨架（本仓库 17 份 `workshop.txt` 统一采用这套排版，细节见下一节）：

```ini
version=1
title=<中英双语标题，含 Build 42>
description=[h1]<一句话标题>[/h1]
description=<它解决什么问题 / 是什么>
description=
description=[h2]<小节名>[/h2]
description=[list]
description=[*]<要点一>
description=[*]<要点二，续行也要写 description= 前缀>
description=[/list]
description=
description=源码与完整分析：<仓库链接>
tags=Build 42;QoL;Misc
visibility=public
```

改完一次校验全部物品（用游戏自己的解析器，不需要 Steam）：

```bash
bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh
# 输出每份的 read / tags / vis / 字节数；全通过时打印 ALL CHECKS PASSED (N item(s))
```

## 富文本与排版

**关键前提：`workshop.txt` 里能写的富文本，是 Steam 工坊页面的方言（BBCode），不是游戏内的方言。**
游戏对描述文本只做"trim + 用单个 `\n` 拼接 + 追加 ID 行"，然后**原样**交给
`n_SetItemDescription` —— 不转义、不剥离，`[b]` / `[h1]` 会一个字都不改地传到 Steam 页面上被渲染。

| 显示位置 | 读的文件 | 富文本方言 | 渲染者 |
| --- | --- | --- | --- |
| **Steam 工坊物品页**的简介 | `workshop.txt` 的 `description=` | **Steam BBCode** | Steam 网页 / 客户端 |
| **游戏内 Mods 列表**的描述 | `<版本目录>/mod.info` 的 `description=` | `mod.info` 的 **`<LINE>` / `<RGB:…>`** | 游戏 `ISRichTextPanel` |
| 游戏内上传向导的简介输入框 | 上面那份 `workshop.txt` | 纯文本编辑框，**不预览 BBCode** | —— |

### Steam BBCode 常用标签（工坊页面侧）

| 标签 | 效果 |
| --- | --- |
| `[b]…[/b]` `[i]…[/i]` `[u]…[/u]` `[strike]…[/strike]` | 粗体 / 斜体 / 下划线 / 删除线 |
| `[h1]…[/h1]` `[h2]` `[h3]` | 标题（自动换行、字号递减） |
| `[list]` + 每行 `[*]条目` + `[/list]`；`[olist]` | 无序 / 有序列表（**每项各占一行 `description=`**） |
| `[url=链接]文字[/url]`、`[url]链接[/url]` | 链接 |
| `[img]图片URL[/img]` | 图片（必须是公网可达的 URL） |
| `[quote]…[/quote]`、`[code]…[/code]` | 引用块、代码块 |
| `[spoiler]…[/spoiler]` | 折叠的剧透块 |
| `[hr][/hr]` | 分隔线 |
| `[noparse]…[/noparse]` | 原样显示标记本身 |
| `[previewyoutube=视频ID][/previewyoutube]` | 内嵌 YouTube |

一条带排版的真实写法（注意空行只能靠空的 `description=`、缩进写在 `=` 之后）：

```ini
description=[h1]这个模组解决什么问题[/h1]
description=[b]症状[/b]：工坊物品一直是 0.000 B
description=
description=[list]
description=[*]Windows 不受影响
description=[*]macOS / Linux 会中招
description=[/list]
description=
description=[url=https://github.com/lotosbin/project-zomboid-mods]源码（GitHub）[/url]
```

### 排版陷阱

- **未闭合的标签会吞掉追加的 ID 行**：游戏把 `Workshop ID:` / `Mod ID:` 直接接在描述末尾，
  少一个 `[/list]` / `[/quote]`，那两行就被折进列表或引用块里。
- **长度上限 8000 字节**（Steamworks `k_cchPublishedDocumentDescriptionMax`，UTF-8 **字节**不是字符）：
  一个汉字 3 字节 ⇒ 纯中文简介约 2600 字封顶，额度还要和 BBCode 标记、追加的 ID 行一起算。
  本仓库现有 17 份 `workshop.txt` 实测最大 3015 字节，余量充足。
- **游戏内看不到渲染结果**：上传向导的输入框是纯文本编辑框，渲染只发生在 Steam 页面上。
- 本仓库既有物品用 `[ ALERT_CONFIG ]` … `[ ------ ]` 作为区块标记，那是社区模组
  （Mod Update and Alert System）的约定，不是 BBCode；它与 BBCode 混用没有已知冲突，
  但它本身**不会被渲染成特殊样式**，只是普通文本行。

### 游戏内那份（`mod.info`）的标签

`ModInfoPanelDesc.lua` 用 `ISRichTextPanel` 渲染 `modInfo:getDescription()`，标签解析器在
`media/lua/client/ISUI/ISRichTextPanel.lua` 的 `processCommand()`，标签用 `<…>` 包裹：

| 标签 | 效果 |
| --- | --- |
| `<LINE>` / `<BR>` | 换行 / 空一行 |
| `<H1>` `<H2>` `<TEXT>` | 大标题（居中白色）/ 小标题（浅灰）/ 恢复正文 |
| `<CENTRE>` `<LEFT>` `<RIGHT>` | 对齐 |
| `<RGB:r,g,b>` | 颜色，分量 0~1 小数 |
| `<PUSHRGB:r,g,b>` + `<POPRGB>` | 颜色入栈 / 出栈 |
| `<RED>` `<ORANGE>` `<GREEN>` `<GHC>` `<BHC>` | 预设色 |
| `<SIZE:small\|medium\|large\|intro\|credits1\|credits2>` | 字号 |
| `<IMAGE:路径[,宽,高]>` `<IMAGECENTRE:…>` `<VIDEOCENTRE:…>` | 插图 / 居中插图 / 内嵌视频 |
| `<KEY:绑定名>` | 渲染当前玩家的按键名（手柄/键鼠自适应） |
| `<INDENT:n>` `<SETX:n>` `<SPACE>` `<JOYPAD:…>` | 进阶排版：缩进 / 指定 x / 空格 / 手柄按键图标 |
| `&lt;` `&gt;` | 转义出真正的尖括号 |

这些标签**只在游戏内有效**；写进 `workshop.txt` 只会原样显示在工坊页面上（反之亦然）。
`mod.info` 的 `description=` 是单个值，换行只能写 `<LINE>`，不能多行重复键。

## 图片规格

| 文件 | 位置 | 规则 |
| --- | --- | --- |
| `preview.png` | **物品根** | **硬性**：正方形，边长只能是 **256 或 512**，≤ **1024000** 字节，必须是真 PNG。校验器 `validatePreviewImage()` 返回 `PreviewNotFound` / `PreviewFileSize` / `PreviewDimensions` / `PreviewFormat` |
| `poster.png` | **版本目录** | 由 `mod.info` 的 `poster=poster.png` 指定，游戏**不做尺寸校验**，惯例 512x512 |

⚠️ 常见错误：`preview.png` 用 1024×1024（"越大越好"）会被判 `PreviewDimensions`；改了后缀的 jpg 会被判
`PreviewFormat`。生成图片建议用可复现脚本（本仓库 `bin2_workshop_upload_fix/tools/make_images.py`
是纯 Pillow 绘制 + 断言尺寸 + 逐行检查文字溢出，256 与 512 是两套排版）。

## 上传流程

1. 建好 `<item>/Contents/mods/<ModId>/<版本目录>/` 与 `mod.info`（见 `workshop_create.sop.md` §2）。
2. 写 `workshop.txt`（本文）。**首次上传前不写 `id=`**，`visibility=private`。
3. 挂 staging 软链（软链是安全的，两条证据见 SOP §8）：

   ```bash
   ln -sfn "$PWD/<item>" ~/Zomboid/Workshop/<item>                         # 上传向导可见
   ln -sfn "$PWD/<item>/Contents/mods/<ModId>" ~/Zomboid/mods/<ModId>      # 本地加载
   ```

4. 本地自检（用游戏自己的解析器，见 SOP §10）：

   ```bash
   bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/<item>
   ```

5. 游戏内 **Mods** 启用模组 → 打开 **Workshop 上传向导** → 选 `~/Zomboid/Workshop/<item>` 这一层 →
   走完向导。⚠️ 向导里有原生确认弹窗，**全屏/无边框时可能看不见**，建议窗口化。
   macOS / Linux 若报 `error requesting Steam to update the item`，装本仓库 `bin2_workshop_upload_fix`。
6. 成功判据：向导日志 success；Steam 客户端 `logs/workshop_log.txt` 出现该物品的 update 记录；
   工坊页面体积不再是 `0.000 B`。
7. 向导会把 `id=` 写回 `workshop.txt` ⇒ 提交进仓库，下次即走"更新"分支。
8. 内容稳定后把 `visibility` 改成 `public`。

## 常见问题

**Q：`workshop.txt` 是必需的吗？**
A：不是必需的，但强烈建议。没有它时上传向导里标题/描述为空，工坊页面也没有标签。

**Q：可以用 Markdown 写描述吗？**
A：不行。游戏不认识 Markdown，Steam 也不渲染 Markdown；工坊页面渲染的是 **BBCode**（见上文）。
唯一"看起来像 Markdown"的 `- 列表` 只是普通文本。

**Q：更新模组时要改 `workshop.txt` 吗？**
A：要。改了内容就把 `description` 一起更新（否则玩家看到的是旧描述），并按 `modify.sop.md`
更新 `changelog.txt` 与版本目录的 `Changelog.txt`。

**Q：工坊页面上标签没生效？**
A：三个常见原因：用了逗号分隔、标签不在 `media/WorkshopTags.txt` 白名单里、`tags=` 留空
（会 split 出一个空标签）。

**Q：工坊页面简介被截断？**
A：超过 8000 **字节**（不是字符）。用 SOP §10 的探针看 `submitDesc = … bytes`。

**Q：怎么删除已上传的物品？**
A：Steam 客户端 → 工坊 → 我的物品 → 删除。删除后 ID 不可恢复。

## 参考资料

- 本文结论的字节码复查命令：`workshop_create.sop.md` §10
- 相关文档：[`workshop_create.sop.md`](../workshop_create.sop.md)（从零新建）·
  [`modify.sop.md`](../modify.sop.md)（版本更新）·
  [`bin2_ProjectALifeNPCs_extensions/docs/pz-alife-mod-dev-report.md`](../bin2_ProjectALifeNPCs_extensions/docs/pz-alife-mod-dev-report.md)
- 游戏代码：`projectzomboid.jar` → `zombie.core.znet.SteamWorkshopItem` / `SteamWorkshop`；
  `media/lua/client/ISUI/ISRichTextPanel.lua`；`media/lua/client/OptionScreens/WorkshopSubmitScreen.lua`；
  `media/WorkshopTags.txt`
- Steam 官方：Steamworks `ISteamRemoteStorage`（描述上限 8000 字节）
  <https://partner.steamgames.com/doc/api/ISteamRemoteStorage> ·
  Steam 社区文本格式说明 <https://steamcommunity.com/comment/Guide/formattinghelp>
- PZ 官方与社区：<https://projectzomboid.com/> ·
  PZ Wiki Modding <https://pzwiki.net/wiki/Modding> ·
  工坊入口 <https://steamcommunity.com/app/108600/workshop/>
