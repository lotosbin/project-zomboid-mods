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

## 翻译类型完整列表

| 类型 | 文件名 | Key 前缀 | 用途 |
|------|--------|----------|------|
| UI | UI.json | UI_ | 主菜单、选项界面 |
| Sandbox | Sandbox.json | Sandbox_ | 沙盒设置选项 |
| ContextMenu | ContextMenu.json | ContextMenu_ | 右键菜单 |
| IGUI | IG_UI.json | IGUI_ | 游戏内界面 |
| Tooltip | Tooltip.json | Tooltip_ | 物品提示 |
| ItemName | ItemName.json | **(无前缀)** | 物品名称 |
| Recipe | Recipe.json | **(无前缀)** | 制作配方 |
| EvolvedRecipeName | EvolvedRecipeName.json | **(无前缀)** | 烹饪食谱 |
| Farming | Farming.json | Farming_ | 农业相关 |
| Moodles | Moodles.json | Moodles_ | 角色状态 |
| GameSound | GameSound.json | GameSound_ | 游戏音效描述 |
| Moveables | Moveables.json | Moveables_ | 可移动物体 |
| Challenge | Challenge.json | Challenge_ | 挑战模式 |
| MultiStageBuild | MultiStageBuild.json | MultiStageBuild_ | 多阶段建筑 |
| News | News.json | News_ | 新闻/电台内容 |
| Recorded_Media | Recorded_Media.json | Recorded_Media_ | 录制媒体 |
| DynamicRadio | DynamicRadio.json | DynamicRadio_ | 动态电台 |
| MakeUp | MakeUp.json | MakeUp_ | 化妆/面容 |
| Stash | Stash.json | Stash_ | 藏匿点 |
| SurvivalGuide | SurvivalGuide.json | SurvivalGuide_ | 生存指南 |

> **注意**: ItemName、Recipe、EvolvedRecipeName 类型的 key prefix 是空的！翻译键就是完整的键名。

## 官方翻译资源

- **翻译仓库**: https://github.com/TheIndieStone/ProjectZomboidTranslations
- **贡献方式**: Fork 后提交 PR 或联系管理员获取贡献权限
- **TV/电台翻译**: `_TVRADIO_TRANSLATIONS` 文件夹 (需要 WordZed 解析)

## 翻译键命名规则

### 原版游戏物品
```json
{
  "ItemName_Base.Glue": "胶水",
  "ItemName_Base.Apple": "苹果"
}
```

### 模组新增物品
```json
{
  "ItemName_ExtensiveHealth.BloodBagONeg": "血液袋 (O-)",
  "ItemName_ModName.CustomItem": "自定义物品"
}
```

### UI 元素 (带提示)
```json
{
  "UI_KeyName": "显示文本",
  "UI_KeyName_Tooltip": "提示文本"
}
```

### 沙盒设置
```json
{
  "Sandbox_OptionName": "选项名称",
  "Sandbox_OptionName_tooltip": "选项描述"
}
```

## 特殊格式

- **换行符**: 使用 `<LINE>` (不是 \n)
- **变量占位符**: `%d`, `%.1f`, `%s` 等保持原样
- **颜色代码**: 使用 `[RGB(r,g,b)]` 格式

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
