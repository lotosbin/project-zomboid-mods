# 开发日志

## 2026-03-19

### bin2_extension 模组创建

创建了 bin2_extension 模组，用于扩展游戏功能。

**添加的配方：**
- 简易木钳拆解配方：将 1 个简易木钳拆解为 2 个木棒和 1 个碎布条

**文件结构：**
```
bin2_extension/42.15.0/
├── mod.info
├── poster.png
├── media/
│   ├── scripts/
│   │   └── Recipes.txt       # 配方定义
│   └── lua/shared/Translate/CN/
│       └── ItemName.json     # 中文翻译
```

### 研究：Project Zomboid 物品 Display Name 翻译方法

#### 翻译文件位置
- 路径：`media/lua/shared/Translate/<语言代码>/`
- B42.13 及之前：`.txt` 格式
- B42.15+：`.json` 格式

#### 翻译现有游戏物品（Patch 方式）

**JSON 格式 (B42.15+)：**
```json
{
  "ItemName_Base.CrudeWoodenTongs": "简易木钳",
  "ItemName_Base.WoodenStick": "木棒"
}
```

**TXT 格式 (B42.13)：**
```lua
ItemName_CN = {
    ItemName_Base.CrudeWoodenTongs = "简易木钳",
    ItemName_Base.WoodenStick = "木棒",
}
```

#### 翻译模组新增物品
使用模组前缀：
```lua
ItemName_CN = {
    ItemName_Xantji.RubberProjectile223 = "橡胶弹丸",
}
```

#### 配方名称翻译
```json
{
  "Recipe_拆解简易木钳": "拆解简易木钳"
}
```

**参考来源：**
- https://pzwiki.net/wiki/Translation
- https://theindiestone.com/forums/index.php?/topic/9535-how-to-translate-every-mod-a-z/

### ExtensiveHealthReworkB42 物品翻译

翻译了 EHR_Items.txt 中的所有医疗物品 DisplayName。

**翻译文件位置：**
```
learn/ExtensiveHealthReworkB42/42/media/lua/shared/Translate/CN/ItemName_EN.txt
```

**翻译内容：**
- 血液袋 (8种血型)
- 空血液袋
- 静脉输液设备 (生理盐水袋、IV套件、注射器、肾上腺素)
- TIER 1 非处方药 (感冒药、止咳药、消炎药等)
- TIER 2 处方药 (抗生素、抗病毒药等)
- TIER 3 临床级药物 (静脉注射药物、急救包等)
- KNOX 感染治疗物品 (基因治疗、阻断剂等)

### ExtensiveHealthRework 物品翻译更新

将物品翻译添加到 bin2_extensive_health_rework 模组（B42.15+ JSON 格式）。

**翻译文件位置：**
```
bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/ItemName.json
```

**翻译内容：**
- 血液袋 (8种血型) + 空血液袋
- 静脉输液设备
- TIER 1 非处方药
- TIER 2 处方药
- TIER 3 临床级药物
- KNOX 感染治疗物品
