# 开发日志 - 2026-10-05

## 课题一：`workshop.txt` 的"富文本格式"到底是哪一套

用户提问只有五个字："**workshop.txt 富文本格式**"。先把问题拆成两个可能被混淆的东西，再用游戏自己的
代码定案 —— 结论是**两套方言，分别在两个地方渲染**：

| 显示位置 | 读的文件 | 富文本方言 | 渲染者 |
| --- | --- | --- | --- |
| Steam 工坊物品页的简介 | 物品根 `workshop.txt` 的 `description=` | **Steam BBCode** | Steam 网页 / 客户端 |
| 游戏内 Mods 列表的描述 | `<版本目录>/mod.info` 的 `description=` | `<LINE>` / `<RGB:r,g,b>` / `<SIZE:…>` | 游戏 `ISRichTextPanel` |
| 游戏内上传向导的简介输入框 | 上面那份 `workshop.txt` | 纯文本，**不预览 BBCode** | —— |

### 证据（每条都可复现，不靠印象）

1. **字节码**：`javap -p -c zombie/core/znet/SteamWorkshopItem.class`
   * `readWorkshopTxt()`：每行先 `String.trim()`（offset 59）、`#` 与 `//` 开头整行 `goto` 跳过、
     空行 `isEmpty()` 跳过；`description=` 用**单个 `\n`** 累加（BootstrapMethods 里的
     `\u0001\n` + `\u0001\u0001`）；值里 `replace("description=", "")` 会删掉**所有**出现。
   * `getSubmitDescription()`：描述非空时先补 `\n\n`，再拼 `Workshop ID: <id>` / `Mod ID: <modid>`。
   * `SteamWorkshop.SubmitWorkshopItem()` 把该字符串原样喂给 `n_SetItemDescription`
     —— **不转义、不剥离**，所以 BBCode 能活着到 Steam 页面。
   * `getVisibilityInteger()` 订正：合法值是 `public` / `friendsOnly` / `private` / `unlisted`，
     **其它任何值静默返回 0 = public**（旧文档写的 `friends` 是错的）。
2. **实机探针**（本次新写，`--check` 批量模式）：喂一份含 `[h1]/[b]/[i]/[url]`、空 `description=`、
   `description=  ← 缩进`、`#`/`//` 注释的 `workshop.txt`，探针逐行 `|…|` 打印，标记与空行原样保留、
   注释行消失，并且**实测到正文里的字面量 `description=` 被删掉**（`写在 description= 之后` → `写在  之后`）。
3. **游戏内方言的完整标签表**：`media/lua/client/ISUI/ISRichTextPanel.lua` 的 `processCommand()`
   —— LINE / BR / H1 / H2 / TEXT / CENTRE / LEFT / RIGHT / RGB / PUSHRGB / POPRGB / GHC / BHC /
   RED / ORANGE / GREEN / SIZE / IMAGE / IMAGECENTRE / VIDEOCENTRE / INDENT / JOYPAD / SETX / SPACE，
   转义用 `&lt;` `&gt;`；消费方 `ModInfoPanelDesc.lua:33` 用 `ISRichTextPanel:setText(modInfo:getDescription())`。
4. **长度上限**：Steamworks `k_cchPublishedDocumentDescriptionMax = 8000`，单位是 **UTF-8 字节**
   （汉字 3 字节/字），额度含 BBCode 标记与游戏追加的 ID 行。

### 顺带得到的 6 条硬规则

空行只能靠**空的 `description=`**；行首缩进被 `trim()` 吃掉（缩进要写在 `=` 之后）；正文不能出现
字面量 `description=`；行首 `#` / `//` 会被当注释丢掉；值里写 `\n` 不换行；**未闭合的 BBCode 会把
游戏追加的 `Workshop ID:` / `Mod ID:` 行一起吞进列表**。

---

## 课题二：统一优化仓库全部 `workshop.txt`（17 份）

### 做法

先写工具再动文件：给 `WorkshopTxtProbe` 加 `--check` 批量模式，再写 `check_all.sh`
（扫描仓库 → 每份复制进 `~/Zomboid/Workshop/__wtchk_*` 白名单 staging → 跑完清理），
得到一份"改前基线"。基线立刻抓到第一个问题：`bin2/Contents/mods/Respawn2/workshop.txt`
这份**历史遗留**（游戏只在物品根读 `workshop.txt`，这份在 `Contents/` 里的只会被当模组内容上传，
而且 `tags=` 是空的）—— 按 SOP §9 的说法直接 `git rm` 删除。

然后逐份重写，规则统一为：`[h1]` 大标题 → 一句话 → `[h2]` 小节（功能 / 包含模组 / 依赖 / 安装 /
已知限制）→ `[list]` + `[*]` 列表 → 结尾保留 `[ ALERT_CONFIG ]` 块。

### 逐份改动的要点

| 物品 | 关键改动 |
| --- | --- |
| `bin2` | 从"标题重复一遍"补成两个模组的说明（Keep XP When Respawn 2 的技能折减保留 / Death Is Not The End 2 的尸体取回 XP），依赖 `modoptions` |
| `bin2_b42` | 补上此前完全没提的 **bin2_base（42.19.0）**；tags 从 10 个收敛到 5 个 |
| ERS / EHR / EPR / Xantji / Lingering Voices | 空壳描述 → 按各自 `mod.info` 写清**翻译范围**（ItemName / Tooltip / Sandbox / Recipe / UI / ContextMenu）、依赖 mod id、安装步骤；EHR 补 `loadModAfter` 加载顺序 |
| Neat 手柄支持 | 把 `mod.info` 里的完整按键映射搬到工坊页面，并写明 B42 建造模式必须用鼠标的原因（`ISBuildIsoEntity` 是 Java 类） |
| `nested_containers_take` | 补机制一段、双端安装要求、覆盖范围，并把"**从未在真实联机会话里实测**"如实写上 |
| A-Life 扩展 | 结构化为沙盒选项列表；**日志版本 `v0.1.0` → `v0.1.5`**（`Config.VERSION` 实测） |
| `bin2_tikitown` | 条目数按 JSON 实点订正：214 → **223**、84 → **172**（并给出分类明细） |
| viewpoint | 内容严重过时：**快捷键早已从 F9/F10 改成 Ctrl+Alt+D 控制面板**、版本 1.x → **2.2.0**，补上 P1 相机/3D 管线、P3.1 体素模型包（16 包 / 9,187 模型 / 10,110 bind）、安装与配置段 |
| title cover ×2 | `【】` 小节 → `[h2]`；补 `Title.png + Title2/3/4.png` 与 `renderOriginalBackground` 的事实 |
| alpaca ×2 | 保持英文原文风，改为 `[h2]` + 列表结构 |

### 校验结果

```
ALL CHECKS PASSED (17 item(s))
```

`submitDescription` 最大 **3534 字节**（`bin2_viewpoint`），距 8000 上限仍有一半余量；
`id=` / `visibility=` / `version=` 与原值逐份比对**全部未变**（只有 Xantji 的标题补了一个缺失的空格）。

**工具抓到了我自己写错的一行**：Xantji 那份有一行续行忘了写 `description=` 前缀，`--check` 直接报
`非法的键: L6 没有 '='` —— 没有这一步，那一行会静默消失在工坊页面上。

另外做了一次"事实标记"回归：把新旧描述的 URL / 点号标识符 / 多位数版本号抽出来做差集，只剩
`0.1.0`、`214`、`1.2` 三处"消失"，全是**故意订正的过时值**。

### 产出

* `bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java`（新增 `--check` 批量自检）
* `bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh`（仓库级一键校验）
* `workshop_create.sop.md`：§3.4 换成统一排版骨架与约定、§3.5 新增富文本整节、§9 补 3 条症状、§10 补批量校验
* `guides/workshop-txt-guide.md`：订正 5 处字段错误 + 新增"富文本与排版"整节
* skill `pz-workshop-item-publishing`：§2.1 description 解析细节与富文本、§7 新探针、§8 踩坑
* 17 份 `workshop.txt` 重写；删除 1 份历史遗留

### 未做 / 待确认

* **没有真实上传一次**去核对 Steam 页面的渲染结果（本机 `web_fetch` 对所有域名都返回
  "resolves to a non-public IP"，Steamworks 文档与社区排版页都只能引 URL）。
* `bin2_blocky_alpaca` / `bin2_companion_alpaca` / `bin2_title_cover/*` / `bin2_viewpoint`
  仍是 `visibility=private` —— 发布与否是作者的决定，本次不擅自改。
* 顺带发现但**未改**：`bin2_title_cover` 两个模组的 `mod.info` 里
  `incompatible=\ZomboidTitleCover,\ZomboidTitleCoverWide` 把**自己**也列进了互斥名单，
  疑似复制粘贴笔误（16:9 版声明 16:9 版互斥），已单独提出待确认。
