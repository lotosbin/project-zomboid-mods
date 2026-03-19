# 模组翻译标准作业流程(Mod translate SOP)

## 参数
原始模组的路径:
翻译模组的路径:

## 翻译文件格式

### B42.15+ (JSON 格式)
- 路径: `media/lua/shared/Translate/<语言代码>/`
- 文件名: 不含语言代码，如 `UI.json`, `ItemName.json`, `Tooltip.json`

### B42.13 及之前 (TXT 格式)
- 路径: `media/lua/shared/Translate/<语言代码>/`
- 文件名: 含语言代码，如 `UI_CN.txt`, `ItemName_CN.txt`

## 模组版本升级翻译 (42 -> 42.15)

当原版模组从 42 升级到 42.15 时：

1. 创建新版本目录 `42.15/`
2. 复制必要文件:
   - `mod.info` (更新 `versionMin` 和 `supports`)
   - `poster.png`, `icon.png`
   - 翻译文件目录 `media/lua/shared/Translate/CN/`
3. 如果翻译文件格式从 TXT 转换为 JSON:
   - 创建 JSON 格式翻译文件
   - 文件名去除语言代码后缀
4. 创建/更新 `Changelog.txt`

## 翻译生效要点

### 翻译模组新增物品
直接使用 `<模组名>.<物品ID>` 格式：
```json
{
    "Xantji.RubberProjectile223": "橡胶弹丸",
    "ExtensiveHealth.BloodBagONeg": "血液袋 (O-)"
}
```

### 翻译现有游戏物品 (Patch)
使用 `Base.<物品ID>` 格式：
```json
{
    "Base.Glue": "胶水",
    "Base.WoodGlue": "木胶"
}
```

### ⚠️ 关键：ItemName 翻译格式

**英文原版格式是什么样的，翻译就必须保持完全相同的格式！**

英文原版 (ItemName_EN.txt):
```lua
ItemName_EN = {
    ItemName_Xantji.RubberProjectile223 = "Rubber Projectiles",
    ItemName_Xantji.MetalProjectile223 = "Metal Projectiles",
}
```

JSON 翻译格式 (去掉 `ItemName_` 前缀):
```json
{
    "Xantji.RubberProjectile223": "橡胶弹丸",
    "Xantji.MetalProjectile223": "金属弹丸"
}
```

### 配方名称翻译
```json
{
    "Recipe_拆解简易木钳": "拆解简易木钳"
}
```

### Tooltip 翻译
```json
{
    "Tooltip_BloodBagONeg": "O型阴性血液袋"
}
```

## 执行步骤

1. 确定原版模组的游戏版本（B42.13 或 B42.15+）
2. 选择对应的翻译文件格式
3. 找到需要翻译的内容：
   - 物品 DisplayName → ItemName 文件
   - UI 文本 → UI 文件
   - 提示文本 → Tooltip 文件
4. 创建翻译条目（使用正确的 key 前缀）
5. 执行 modify.sop.md

## 参考资料
- https://pzwiki.net/wiki/Translation
- https://theindiestone.com/forums/index.php?/topic/9535-how-to-translate-every-mod-a-z/
