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

## ⚠ 合并语义：mod 的翻译会**盖掉**原版（2026-10-13 实测记录）

**结论：同一个键，后加载的赢；加载顺序是"原版文件 → 各 mod"，所以模组里的任何一条翻译都会覆盖上游同名键。**
`bin2_extension` 因此删掉了自带的 `ItemName.json`（详见仓库该模组 README 与 1.7.2 更新日志）。

证据（`zombie.core.Translator`，本机 jar `javap -p -c` 反汇编，**字节码层面确认，未在游戏内实测**）：

- `loadFiles()` → `forLanguageStack(...)` → `lambda$loadFiles$4`：先对**原版**目录调
  `tryFillMapFromFile(base, 文件名, map, 语言, identity)`，再调 `tryFillMapFromMods(文件名, map, 语言)`；
  `tryFillMapFromMods` 遍历 `ZomboidFileSystem.getModIDs()`，对每个 mod 的 `common` 与版本目录各调一次
  `tryFillMapFromFile` —— **mod 在后面填同一个 map**。
- 真正的写入在 `lambda$tryFillMapFromFile$0`：`map.containsKey(key)` 之后**仍然**走
  `map.put(key, transform.apply(value))`（只有当新值为 null/空串时才跳过），即**无条件覆盖**，不是 `putIfAbsent`。

复现这条链的最小探针（无头、不启 Steam；`java` 用游戏自带 JRE，cwd 必须是游戏的 `Contents/Java`）：

```java
ZomboidFileSystem.instance.init();      // 不初始化它，loadFiles() 会 NPE
Languages.instance.init();              // 之后 getLanguages() 才有 29 种语言
Translator.setLanguage(Languages.instance.getIndexByName("CN"));
Translator.loadFiles();                 // 注意：它会按"游戏设置里的语言"重设 language
System.out.println(Translator.getItemNameFromFullType("Base.Pot"));
```

⚠ **`loadFiles()` 会把 `Translator.language` 重置成游戏设置里的语言**（无头环境 = 默认 EN），
所以上面的探针在本机只能读到英文名（`Cooking Pot`）—— 想读某个语言的值，得先让游戏设置里的语言是它，
或者绕过 `loadFiles()` 直接反射调用那两个私有方法。

**实践规则**：给原版物品写 `ItemName.json` 是"抢方向"的动作 —— 上游改了译名，你这份旧文案会继续盖住它
（`bin2_extension` 就这样把 `Base.Pot` 盖成了「陶锅」、`Base.CrudeWoodenTongs` 盖成「简易木钳」）。
**只翻译上游没有的东西**（别的 mod 的物品、自己的配方名），原版已有译名的键不要重复提供。
