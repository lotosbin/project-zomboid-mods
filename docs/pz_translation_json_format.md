# Project Zomboid 42.15 翻译文件格式

## 关键变更

从 Build 42.15.0 开始，Project Zomboid 的翻译文件格式从旧的 `.txt` (Lua 表格式) 迁移到新的 **JSON 格式**。

### 旧格式 (.txt)

**目录**: `media/lua/shared/Translate/<语言代码>/`
**文件名**: `UI_CN.txt`, `Sandbox_CN.txt` 等（包含语言代码）

```lua
UI_CN = {
    UI_KeyName = "翻译文本",
    UI_KeyName_Tooltip = "提示文本",
}
```

### 新格式 (.json)

**目录**: `media/lua/shared/Translate/<语言代码>/`
**文件名**: `UI.json`, `Sandbox.json` 等（**去掉语言代码后缀**）

```json
{
    "UI_KeyName": "翻译文本",
    "UI_KeyName_Tooltip": "提示文本"
}
```

## 翻译类型

| 类型 | 文件名 | Key 前缀 | 函数 |
|------|--------|----------|------|
| UI | UI.json | UI_ | getText |
| Sandbox | Sandbox.json | Sandbox_ | getText |
| ContextMenu | ContextMenu.json | ContextMenu_ | getText |
| IGUI | IG_UI.json | IGUI_ | getText |
| Tooltip | Tooltip.json | Tooltip_ | getText |

更多类型参考: [pzwiki.net/wiki/Translation](https://pzwiki.net/wiki/Translation)

## 模组更新记录

### 2026-03-15

将以下模组的中文翻译从 .txt 转换为 .json 格式：

| 模组 | 翻译文件 |
|------|----------|
| Respawn2 | UI.json |
| Lingering Voices CN | Sandbox.json |
| Extensive Power Rework CN | UI.json, ContextMenu.json, Sandbox.json |
| Extensive Health Rework | Sandbox.json, Tooltip.json, UI.json |
| EnergyRoutingSystem_CN | IG_UI.json, Sandbox.json |

## 转换脚本

位于 `scripts/convert_translation.py`

使用方法:
```bash
python3 scripts/convert_translation.py
```

## Changelog 格式

使用 `Changelog.txt` 文件配合 Mod Update and Alert System：

```txt
[ ALERT_CONFIG ]
link1 = GitHub = https://github.com/your/link,
[ ------ ]

[ MM/DD/YYYY ]
- 更新内容
[ ------ ]
```

参考: [pzwiki.net/wiki/Mod_Update_and_Alert_System](https://pzwiki.net/wiki/Mod_Update_and_Alert_System)
