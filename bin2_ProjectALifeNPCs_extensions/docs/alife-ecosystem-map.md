# Project A-Life 生态地图（工坊实测，2026-10-04）

> 数据来源：Steam Web API `ISteamRemoteStorage/GetPublishedFileDetails`（无需 API Key），
> 候选项来自工坊搜索 `searchtext=Project+A-Life`（appid 108600）返回的 31 条结果，逐条拉取真实元数据。
> **补录（2026-10-04）**：另有 `3808789424`（标题不含 "Project"，因此不在该搜索的返回里，见 §三 检索盲区）。
> 复核命令见文末。

## 一、生态总览（按订阅排序）

| 订阅 | 工坊 ID | 标题 | 最后更新 | 类型 |
| --- | --- | --- | --- | --- |
| 121,425 | 3803984183 | Project A-Life [ALIFE NPCS] | 10-01 | **核心** |
| 10,743 | 3806944055 | Project A-Life - Jeem Extension | 10-01 | **扩展**（基地/居民/任务/声望） |
| 9,515 | 3806181882 | Project A-Life [RU] — Русская локализация | 10-01 | 翻译 |
| 5,921 | 3806063445 | Project A-Life: Aftermath [Addon] | 09-30 | **扩展**（装备/阵营 provider，3 变体） |
| 5,015 | 3805910220 | Traducción al Español | 10-01 | 翻译 |
| 3,733 | 3807738026 | **Project A-Life & Companion Dogs Compatibility Patch** | 09-25 | **兼容补丁**（动物同伴 × A-Life） |
| 2,887 | 3805566620 | 生态NPC简中汉化 | 09-30 | 翻译（CN） |
| 2,448 | 3807156999 | Project A-Life RU | 09-24 | 翻译（RU，另一份） |
| 1,808 | 3807333066 | 中文汉化（完整版） | 09-25 | 翻译（CN） |
| 1,457 | 3806218339 | Tradução PT-BR | 09-27 | 翻译 |
| 1,176 | 3806786035 | [unofficial] **Hostility Indicator Dots** | 09-23 | **UI 扩展**（敌对指示点） |
| 1,120 | 3811640626 | **Project Viewpoint - 3D Tracer Fix for Project A-Life** | 10-02 | **渲染兼容**（Viewpoint 3D 曳光） |
| 814 | 3806340371 | THAILAND translation | 09-27 | 翻译 |
| 543 | 3808304775 | Jeem Extension-CN 生态NPC拓展包简中汉化 | 09-26 | 翻译（CN） |
| 348 | 3807277264 | ProjectALife中文汉化整合版 | 09-24 | 翻译（CN） |
| 338 | 3808256808 | Jeem Extension 简繁中文汉化 | 09-30 | 翻译（CN） |
| 318 | 3804728952 | Korean Translation | 09-20 | 翻译 |
| 312 | 3807510618 | Türkçe Yama | 10-02 | 翻译 |
| 248 | 3805959381 | Traduzione Italiana | 10-01 | 翻译 |
| **226** | **3808789424** | **A-Life x zombie mods - stack compatibility** | 10-03 | **兼容层（第三方）** ← 补录 |
| 151 | 3808333397 | Jeem Extension - แปลไทย | 09-26 | 翻译 |
| 86 | 3806895410 | Português Brasileiro | 10-01 | 翻译 |
| 85 | 3806931923 | Japanese Translation | 10-01 | 翻译 |
| 74 | 3810118894 | **Roaming Survivors + Project A-Life Compat** | 09-29 | **兼容补丁**（另一个 NPC mod） |
| 38 | 3807243560 | PROJECT A LIFE CN | 09-30 | 翻译 |
| 36 | 3808937339 | IT - Traduzione Italiana | 09-28 | 翻译 |
| 23 | 3808613530 | 1.3.16 PT-BR Tradução | 10-03 | 翻译 |
| 21 | 3807853553 | **Clean Context Menu Fix** | 09-25 | **UI 修补** |
| 20 | 3806666221 | ภาษาไทย | 09-23 | 翻译 |
| 12 | 3806186038 | ProjectALifeNPCs中文汉化 | 09-22 | 翻译 |
| 4 | 3811885613 | Korean Translation | 10-02 | 翻译 |
| — | 2872282653 | Modding Policy（工坊政策，非模组） | 11-09 | 参考 |

## 二、结构性结论（对"该做什么"至关重要）

### 2.1 翻译赛道已经彻底饱和 ⚠️

**中文就有至少 6 个**（3805566620 / 3807333066 / 3807277264 / 3806186038 / 3807243560 / 338+543 的 Jeem 汉化），
此外 RU ×2、ES、PT-BR ×2、TH ×2、KO ×2、IT ×2、JP、TR 各至少一份。

> **修正**：本仓库此前的主报告（`pz-alife-mod-dev-report.md` 第 9.2 节）建议"第一步做中文翻译补丁"——
> **该建议已被本表推翻**，入局做翻译属于重复劳动。请以本文档为准。

### 2.2 真正的扩展只有 **4 个**（其余全是翻译）

| 扩展 | 覆盖的领域 | 是否已饱和 |
| --- | --- | --- |
| Jeem Extension | 基地 / 居民 / 任务 / 声望 | 独占，但本体是 WIP（0.4.6） |
| Aftermath（3 变体） | 装备 / 阵营 **provider**（依赖感知） | 覆盖 Marz / MFS / guns93 |
| Companion Dogs Compat | 动物同伴 × A-Life | 已有（3,733 订阅），但只做基础兼容 |
| Hostility Indicator Dots | UI（敌对点） | 单一功能 |
| （Viewpoint 3D Tracer Fix） | 渲染（第三方为 Viewpoint 做的） | 已存在 |
| **ALifeStackCompat**（3808789424） | **兼容层**：让 6 个僵尸行为模组跳过 A-Life NPC（294 行 / 13 KB） | **已有**（226 订阅） |

**空白区**（据上表 + 本机 1,150 个已装模组推导，详见 `integration-brainstorm.md`）：
> 注：`ALifeStackCompat` 覆盖 6 个模组，但**未覆盖 Bandits2 系与 CompanionDogs 的 `Bandit` 标记反噬**，
> 这正是仍空白的部分 —— 详见 `extension-stackcompat-analysis.md` §3.2 与 §5.2。
地图适配、载具联动、枪械生态补全（Hot Brass / Heavy Ordnance）、电力与据点通讯联动、
手柄支持、Viewpoint 官方级适配、Jeem 内容包 —— **这些方向目前没有任何工坊物品在做**。

### 2.3 一个直接与"本仓库既有资产"相关的信号

`3811640626 Project Viewpoint - 3D Tracer Fix for Project A-Life`（1,120 订阅，10-02 更新）
说明 **Viewpoint（3D 渲染）× A-Life 的交集已经有人在做**，而本仓库正是 `bin2_viewpoint`
（ViewpointMac，macOS/Apple Silicon 版）的维护者 —— 这是本仓库**独有的先发优势**。

## 三、复核命令

```bash
# 1) 抓候选项（工坊搜索页，需浏览器 UA）
curl -s -A "Mozilla/5.0" \
  "https://steamcommunity.com/workshop/browse/?appid=108600&searchtext=Project+A-Life&browsesort=textsearch&section=readytouseitems&actualsort=textsearch&p=1" \
  -o /tmp/alife_search.html
grep -oE 'filedetails/\?id=[0-9]+' /tmp/alife_search.html | sort -u

# 2) 批量拉真实元数据（一次最多 100 个 id）
args="itemcount=N"; i=0
for id in <ID...>; do args="$args&publishedfileids[$i]=$id"; i=$((i+1)); done
curl -s -X POST "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" -d "$args"
```

> 注：工坊搜索页的标题是 JS 渲染的，HTML 里只能稳定拿到 **id**；
> 标题/订阅数必须走上面第 2 步的 API，**不要从搜索页 HTML 里猜**。

### 检索盲区（本次踩到的）

`searchtext=Project+A-Life` 只匹配含 "Project" 的结果，因此**漏掉了 `3808789424`
「A-Life x zombie mods - stack compatibility」**（标题里没有 "Project"）。

→ **补全做法**：至少跑三种检索并做 id 并集：
`Project+A-Life`、`A-Life`、`ALife`；再用「已装模组的 `loadModAfter` / `require` 里提到 A-Life 的」做交叉验证
（例如本机 `ALifeStackCompat` 的 `loadModAfter` 就写着 `ProjectALifeNPCs`）。
更可靠的一条：**扫本机已装模组的 `mod.info`，凡是 `require`/`loadModAfter` 含 `ProjectALifeNPCs` 的都是扩展**。
