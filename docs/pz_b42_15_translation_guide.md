# Project Zomboid B42.15 翻译文件格式完全指南

## 前言

Project Zomboid 在 Build 42.15.0 版本中对翻译系统进行了重大更新，将传统的 `.txt` (Lua 表格式) 迁移到了现代的 **JSON 格式**。本文将详细介绍这一变化，并提供完整的迁移指南。

> **重要提示**: 如果你使用模组包（如 bin2 的 B42 合集），确保同时更新依赖的翻译模组版本。

---

## 一、发生了什么变化？

### 1. 文件格式

**旧格式** (.txt):
```lua
UI_CN = {
    UI_KeyName = "翻译文本",
    UI_KeyName_Tooltip = "提示文本",
}
```

**新格式** (.json):
```json
{
    "UI_KeyName": "翻译文本",
    "UI_KeyName_Tooltip": "提示文本"
}
```

### 2. 文件命名

**旧格式**: `UI_CN.txt`, `Sandbox_CN.txt`, `IG_UI_CN.txt`

**新格式**: `UI.json`, `Sandbox.json`, `IG_UI.json`

> **关键变化**: 文件名不再包含语言代码后缀 (`_CN`)

### 3. 目录结构

```
media/lua/shared/Translate/<语言代码>/
```

目录结构保持不变，但文件命名规则改变了。

---

## 二、翻译类型对照表

| 类型 | 旧文件名 | 新文件名 | Key 前缀 |
|------|----------|----------|----------|
| 用户界面 | UI_CN.txt | UI.json | UI_ |
| 沙盒设置 | Sandbox_CN.txt | Sandbox.json | Sandbox_ |
| 上下文菜单 | ContextMenu_CN.txt | ContextMenu.json | ContextMenu_ |
| 游戏内界面 | IG_UI_CN.txt | IG_UI.json | IGUI_ |
| 工具提示 | Tooltip_CN.txt | Tooltip.json | Tooltip_ |

完整的翻译类型列表请参考: [pzwiki.net/wiki/Translation](https://pzwiki.net/wiki/Translation)

---

## 三、转换工具

### 1. Python 转换脚本

如果你有大量翻译文件需要转换，可以使用以下 Python 脚本：

```python
import re
import json

def parse_lua_table(content):
    """解析 Lua 表内容为 Python 字典"""
    result = {}
    lines = content.split('\n')
    cleaned_lines = []
    for line in lines:
        if '--' in line:
            before_comment = line[:line.find('--')]
            if before_comment.count('"') % 2 == 0:
                line = before_comment.rstrip()
        if line.strip():
            cleaned_lines.append(line)

    content = '\n'.join(cleaned_lines)
    content = re.sub(r'^\s*\w+\s*=\s*\{', '', content)
    content = re.sub(r'^\s*\}\s*$', '', content)

    pattern = r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)'
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('--'):
            continue
        match = re.match(pattern, line)
        if match:
            key = match.group(1)
            value = match.group(2).rstrip(',').rstrip(',')
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            result[key] = value.replace('\\n', '\n').replace('\\"', '"')
    return result

# 使用示例
with open('UI_CN.txt', 'r', encoding='utf-8') as f:
    data = parse_lua_table(f.read())

with open('UI.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=4)
```

### 2. 手动转换

对于少量文件，手动转换也很简单：

1. 打开旧翻译文件
2. 复制 key 名称（去掉 `_CN` 后缀，如果是表头）
3. 转换为 JSON 格式

---

## 四、Changelog 配置 (Mod Update and Alert System)

从 B42.15 开始，你可以使用 `Changelog.txt` 在游戏主菜单中显示更新日志。

### 1. 文件位置

- **Build 42**: `common/Changelog.txt`
- **Build 41**: `media/Changelog.txt`

### 2. 格式规范

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://steamcommunity.com/linkfilter/?u=https://github.com/yourname/your-mod,
[ ------ ]

[ 03/15/2026 ]
- 更新翻译文件为 JSON 格式
- 修复已知问题
[ ------ ]
```

### 3. 链接配置

PZ 要求所有外部链接使用 Steam 链接过滤器：

```
https://steamcommunity.com/linkfilter/?u=<原始链接>
```

支持的链接类型：
- Workshop 页面
- GitHub 仓库
- Ko-Fi 页面

### 4. 完整示例

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://steamcommunity.com/linkfilter/?u=https://github.com/yourname/your-mod,
link2 = Workshop = https://steamcommunity.com/sharedfiles/filedetails/?id=123456789,
[ ------ ]

[ 03/15/2026 ]
- 翻译文件迁移到 JSON 格式
- 支持 B42.15+
[ ------ ]

[ 03/01/2026 ]
- 初始版本发布
[ ------ ]
```

更多详情请参考: [pzwiki.net/wiki/Mod_Update_and_Alert_System](https://pzwiki.net/wiki/Mod_Update_and_Alert_System)

---

## 五、常见问题

### Q1: 旧翻译文件还能用吗？

**答**: 在 B42.15+ 中，游戏优先加载 JSON 格式。如果同时存在 JSON 和 TXT 文件，JSON 会被使用。建议迁移到新格式以确保兼容性。

### Q2: 需要更新 mod.info 吗？

**答**: 如果你的模组依赖特定游戏版本，可以更新 `versionMin`。翻译格式变化不影响模组功能，但建议更新版本号以便用户知道需要更新。

### Q3: 如何验证 JSON 文件格式正确？

**答**: 使用任何 JSON 验证工具，或在命令行运行：

```bash
python -m json.tool your_translation.json
```

如果格式正确，会输出格式化后的 JSON；否则会显示错误。

---

## 六、总结

B42.15 的翻译格式变化虽然看似简单，但有几个关键点需要注意：

1. **文件命名**: 去掉 `_CN` 后缀
2. **格式转换**: Lua 表 → JSON 对象
3. **Changelog**: 使用 Steam 链接过滤器
4. **测试验证**: 确保 JSON 格式正确

希望这篇指南能帮助你顺利完成翻译文件的迁移！

---

## 参考链接

- [官方翻译文档](https://pzwiki.net/wiki/Translation)
- [Mod Update and Alert System](https://pzwiki.net/wiki/Mod_Update_and_Alert_System)
- [JSON Schema 验证](https://github.com/SirDoggyJvla/pz-translation-data)
