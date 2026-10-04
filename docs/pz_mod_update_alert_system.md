# Project Zomboid Mod Update and Alert System 完全指南

## 什么是 Mod Update and Alert System？

Mod Update and Alert System 是 Project Zomboid 提供的一个 API，允许模组作者直接在游戏主菜单中向玩家展示更新日志（Patch Notes）。玩家可以在启动游戏时看到模组的最新更新内容，还可以添加自定义链接（如 GitHub、Steam Workshop、Ko-Fi 等）。

> **注意**: 此功能从 Build 42.7.0 开始可用

> ⚠️ **它不是游戏本体的功能，而是一个社区模组（Mod Update and Alert System / Chuckleberry Finn 系列）提供的能力。**
> 已实测：把 `projectzomboid.jar` 全量解包后 `grep -r ALERT_CONFIG` 零命中，
> `Contents/Java/media/` 下也没有任何解析代码。本机上唯一消费该块的是 `[B42] Mod Manager` 的兼容层
> `media/lua/client/ModManager/Compatibility/ModdingAlertSystem.lua` + `ModManager/Utils/WorkshopSubmit.lua`：
> 后者用 `getModFileReader(modID, "ChangeLog.md")` / `"ChangeLog.txt"` 读取，**只读模组目录内的
> `Changelog.txt`，从不读 `workshop.txt`**，并在 `parseTxtVersionHeader` 里用 `v ~= "ALERT_CONFIG"`
> 跳过配置块、把 `[ ------ ]` 当块终止符。
>
> ⇒ 把 ALERT_CONFIG 写进 `workshop.txt` 的 `description=` **不会**在游戏内生效，它只会作为工坊页面的
> 描述文本显示出来（本项目确实两处都写了：`Changelog.txt` 负责功能，`workshop.txt` 负责页面展示）。

### `workshop.txt` 的 `description=` 到底怎么解析（反汇编自 `zombie.core.znet.SteamWorkshopItem`）

| 行为 | 结论 |
|------|------|
| 注释 | 以 `#` 或 `//` 开头的行整行跳过 |
| 重复 `description=` | `description += "\n" + 本行去掉前缀后的内容` —— **分隔符是单个 `\n`** |
| 想要空行 | 必须自己多写一行空的 `description=`（各行之间不会自动空行） |
| 提交时 | `getSubmitDescription()` 再追加 `Workshop ID:` / `Mod ID:` 行 |
| `tags=` | 按 `;` split，**不 trim**，且必须在 `media/WorkshopTags.txt` 白名单内 |

实测（`bin2_blocky_alpaca`）：按 `\n` 拼接 = 1912 字符，游戏探针打印 `description = 1912 chars`；
按 `\n\n` 拼接会得到 1939，与探针不符 ⇒ 单 `\n` 得到字节码与运行时两侧互证。

---

## 一、快速开始

### 1. 创建 Changelog.txt 文件

- **Build 42**: 放在 `common/Changelog.txt`
- **Build 41**: 放在 `media/Changelog.txt`

### 2. 基本格式

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://steamcommunity.com/linkfilter/?u=https://github.com/yourname/your-mod,
[ ------ ]

[ MM/DD/YYYY ]
- 更新内容描述
[ ------ ]
```

---

## 二、链接配置

### 1. 为什么需要 Steam 链接过滤器？

Project Zomboid 要求所有外部链接必须通过 Steam 链接过滤器，以防止恶意链接。这是 Steam 的安全机制。

### 2. 链接格式

```
https://steamcommunity.com/linkfilter/?u=<原始链接>
```

### 3. 支持的链接类型

| 类型 | 示例 |
|------|------|
| GitHub | `https://steamcommunity.com/linkfilter/?u=https://github.com/yourname/your-mod` |
| Steam Workshop | `https://steamcommunity.com/sharedfiles/filedetails/?id=123456789` |
| Ko-Fi | `https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/yourname` |

### 4. 多个链接配置

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://steamcommunity.com/linkfilter/?u=https://github.com/yourname/your-mod,
link2 = Workshop = https://steamcommunity.com/sharedfiles/filedetails/?id=123456789,
link3 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/yourname,
[ ------ ]
```

---

## 三、更新日志格式

### 1. 单条更新

```txt
[ 03/15/2026 ]
- 修复了若干 bug
- 优化了性能
[ ------ ]
```

### 2. 多条更新

```txt
[ 03/15/2026 ]
- 修复了若干 bug
- 优化了性能
[ ------ ]

[ 03/01/2026 ]
- 初始版本发布
[ ------ ]
```

### 3. 时间格式

推荐使用美国日期格式 `MM/DD/YYYY`，游戏会自动按时间倒序显示。

---

## 四、完整示例

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://steamcommunity.com/linkfilter/?u=https://github.com/lotosbin/project-zomboid-mods,
link2 = Workshop = https://steamcommunity.com/sharedfiles/filedetails/?id=123456789,
link3 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/bin2,
[ ------ ]

[ 03/15/2026 ]
- 翻译文件迁移到 JSON 格式
- 支持 B42.15+
- 修复循环依赖问题
[ ------ ]

[ 03/01/2026 ]
- 初始版本发布
- 包含 5 个中文翻译模组
[ ------ ]
```

---

## 五、注意事项

1. **文件名必须是 `Changelog.txt`**，不能是 `ChangeLog.txt` 或其他变体
2. **链接必须使用 Steam 链接过滤器**
3. **版本号写在方括号内**，如 `[ 03/15/2026 ]`
4. **每个版本块以 `[ ------ ]` 结束**
5. **可选功能** - 玩家可以在游戏设置中禁用此功能

---

## 六、验证你的 Changelog

在游戏中验证：
1. 启用模组
2. 进入游戏主菜单
3. 查看模组列表中的更新提示

---

## 参考链接

- 官方文档: [pzwiki.net/wiki/Mod_Update_and_Alert_System](https://pzwiki.net/wiki/Mod_Update_and_Alert_System)
