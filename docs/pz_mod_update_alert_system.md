# Project Zomboid Mod Update and Alert System 完全指南

## 什么是 Mod Update and Alert System？

Mod Update and Alert System 是 Project Zomboid 提供的一个 API，允许模组作者直接在游戏主菜单中向玩家展示更新日志（Patch Notes）。玩家可以在启动游戏时看到模组的最新更新内容，还可以添加自定义链接（如 GitHub、Steam Workshop、Ko-Fi 等）。

> **注意**: 此功能从 Build 42.7.0 开始可用

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
