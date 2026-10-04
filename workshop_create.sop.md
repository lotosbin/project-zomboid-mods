# 工坊物品创建标准作业流程 (Workshop Create SOP)

从零建一个可上传、可被游戏正确识别的 Project Zomboid 工坊物品。
本文所有字段规则都**反汇编自游戏自己的代码**（`zombie.core.znet.SteamWorkshopItem` /
`zombie.Lua.LuaManager$GlobalObject.getModFileReader`），不靠印象；文末给出复查命令。

> 与既有文档的关系：`modify.sop.md` 管**已有物品的版本更新**，`tranlate.sop.md` 管**翻译补丁**，
> 本文管**从零新建物品**。仓库既有的 `guides/workshop-txt-guide.md` 在 tags 分隔符、visibility 取值、
> preview 尺寸、`changelog=`/`preview_image=` 字段这几处说法**是错的**（见 §9），以本文为准。

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

### 3.4 可直接抄的骨架

```ini
version=1
title=<中英双语标题，含 Build 42>
description=<一句话：这个模组解决什么问题>
description=
description=依赖 / 安装 / 生效标志 / 已知限制……
description=
description=[ ALERT_CONFIG ]
description=link1 = GitHub = https://github.com/lotosbin/project-zomboid-mods,
description=link2 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/lotosbin,
description=link3 = 爱发电 = https://steamcommunity.com/linkfilter/?u=https://afdian.com/a/bin_2,
description=[ ------ ]
tags=Build 42;QoL;Misc
visibility=private
```

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

自检清单：

- [ ] `mod.info`：`id` / `name` / `modversion` / `poster` / `require` / `versionMin` 齐全
- [ ] `workshop.txt`：`version=1`、多行 `description=`、`tags` 在白名单内、`visibility` 是本次想要的
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
* 反汇编来源：`projectzomboid.jar` → `zombie/core/znet/SteamWorkshopItem.class`、
  `zombie/Lua/LuaManager$GlobalObject.class`（命令见 §10）
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
