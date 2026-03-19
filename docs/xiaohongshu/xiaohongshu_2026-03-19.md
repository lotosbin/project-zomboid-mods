# 🎮 Project Zomboid 模组中文翻译全攻略

## 从 0 到 1 学会模组翻译

---

## 📋 今日翻译成果

### 1️⃣ XantjiRecycleEverything 物品翻译

一个回收利用为主题的模组，添加了各种拆解、制作配方。

**翻译内容（29个物品）：**

| 类别 | 物品示例 | 翻译 |
|------|---------|------|
| 弹药 | Rubber Projectiles | 橡胶弹丸 |
| 武器 | MSR700 Air Rifle | MSR700 气步枪 |
| 材料 | Rubber Flakes | 橡胶碎片 |
| 容器 | Empty Glue Bottle | 空胶水瓶 |
| 废料箱 | Box of Iron Junk | 可熔废铁箱 |

### 2️⃣ Extensive Health Rework 疾病手册

**新增9个疾病信息手册翻译：**

- DiseaseFlyer_CommonCold → 疾病信息：普通感冒
- DiseaseFlyer_Flu → 疾病信息：流感
- DiseaseFlyer_Pneumonia → 疾病信息：肺炎
- DiseaseFlyer_FoodPoisoning → 疾病信息：食物中毒
- DiseaseFlyer_Hypothermia → 疾病信息：体温过低
- DiseaseFlyer_HeatExhaustion → 疾病信息：热衰竭
- DiseaseFlyer_Sepsis → 疾病信息：脓毒症
- DiseaseFlyer_CorpseSickness → 疾病信息：尸体感染病
- DiseaseFlyer_Tuberculosis → 疾病信息：肺结核

### 3️⃣ bin2_modpack 模组包更新

- 版本：1.0.5 → 1.0.6
- 新增：SideBarCS, MREfood4213, ERS_SmallProducersPack_CN

---

## 🔧 翻译格式详解（重点！）

这是最关键的部分，很多人不清楚格式导致翻译不生效。

### B42.15+ 使用 JSON 格式

**文件路径：**
```
模组目录/media/lua/shared/Translate/CN/ItemName.json
```

### 格式对比

#### ❌ 错误格式
```json
{
    "RubberProjectile223": "橡胶弹丸"
}
```

#### ✅ 正确格式
```json
{
    "Xantji.RubberProjectile223": "橡胶弹丸"
}
```

### 三种翻译类型

#### 1. 模组新增物品
```json
{
    "模组名.物品ID": "中文名称"
}
```

#### 2. 翻译原版物品（Patch）
```json
{
    "Base.Glue": "胶水",
    "Base.WoodGlue": "木胶"
}
```

#### 3. 配方名称翻译
```json
{
    "Recipe_制作弹丸": "制作弹丸",
    "Recipe_拆解椅子": "拆解椅子"
}
```

### Tooltip 提示翻译
```json
{
    "Tooltip_物品ID": "提示文本内容"
}
```

---

## 📁 标准模组结构

```
<模组名>/
├── Contents/
│   └── mods/
│       └── <模组ID>/
│           ├── mod.info              # 模组信息
│           ├── poster.png            # 预览图
│           ├── icon.png              # 图标
│           ├── Changelog.txt         # 更新日志
│           └── media/
│               ├── scripts/          # 脚本文件
│               └── lua/
│                   └── shared/
│                       └── Translate/
│                           └── CN/   # 中文翻译
│                               ├── ItemName.json
│                               ├── Recipe.json
│                               ├── Tooltip.json
│                               ├── UI.json
│                               └── Sandbox.json
```

---

## ⚠️ 常见问题

### Q1: 翻译不生效？

**检查三点：**
1. JSON 格式是否正确（可以用 JSON 验证器）
2. key 是否有正确的前缀
3. 文件是否放在正确位置

### Q2: B42.13 和 B42.15 区别？

| 版本 | 文件格式 | 文件名示例 |
|------|---------|-----------|
| B42.13 | TXT | ItemName_CN.txt |
| B42.15+ | JSON | ItemName.json |

### Q3: 如何找到物品 ID？

查看模组的 `media/scripts/` 目录下的 TXT 文件：
```
item BloodBagONeg
{
    DisplayName = Blood Bag (O-),
    ...
}
```
这里的 `BloodBagONeg` 就是物品 ID。

---

## 🛠️ 翻译工具推荐

1. **VS Code** - 编辑 JSON 文件
2. **JSON Formatter** - 验证 JSON 格式
3. **Notepad++** - 批量查找替换

---

## 📖 学习资源

- 官方 Wiki：pzwiki.net/wiki/Translation
- 官方翻译仓库：github.com/TheIndieStone/ProjectZomboidTranslations
- Schema 验证：github.com/SirDoggyJvla/pz-translation-data

---

## 💬 交流

有问题欢迎评论区问我！

#ProjectZomboid #僵尸生存 #游戏模组 #翻译教程 #Steam创作者 #生存游戏
