# 开发日志

## 2026-03-19

### SOP 流程更新

更新了翻译和模组变更的 SOP 文档。

**修改的文件：**
- `tranlate.sop.md` - 添加模组版本升级翻译流程
- `modify.sop.md` - 完善为标准作业流程文档

### XantjiRecycleEverything 翻译修复

**发现问题：** ItemName.json 翻译 key 格式不正确

**问题分析：**
- 英文原版: `ItemName_Xantji.RubberProjectile223`
- 原翻译: `Xantji.RubberProjectile223` (缺少 `ItemName_` 前缀)

**修正结论：** 根据验证，JSON 格式不需要 `ItemName_` 前缀，保持原格式。

**翻译内容（29个物品）：**
- 弹药类：橡胶弹丸、金属弹丸
- 服装类：简易外科手套
- 烹饪类：胶水基锅具、碱液基锅具、肥皂基长柄锅
- 材料类：胶水瓶、木灰、弹簧、橡胶碎片、碱液
- 废料箱：可熔废铁箱
- 武器类：MSR700 气步枪

**文件位置：**
```
bin2_XantjiRecycleEverything/Contents/mods/XantjiRecycleEverything/42.15/media/lua/shared/Translate/CN/
├── ItemName.json
├── Recipes.json
├── Tooltip.json
└── Fluids.json
```

### Extensive Health Rework 翻译更新

**新增翻译内容：**
- 疾病手册 (DiseaseFlyer) 9个：
  - 普通感冒、流感、肺炎、食物中毒
  - 体温过低、热衰竭、脓毒症、尸体感染病、肺结核

**文件位置：**
```
bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42.15/media/lua/shared/Translate/CN/
├── ItemName.json      # 58个物品翻译
├── Tooltip.json      # 45个提示翻译
├── UI.json
└── Sandbox.json
```

### bin2_modpack 同步更新

根据 penglai.ini 服务器配置同步模组列表。

**mod.info 更新：**
- 添加：SideBarCS, MREfood4213, ERS_SmallProducersPack_CN
- 移除：simpleStatusFixed
- modversion: 1.0.5 → 1.0.6

**文件位置：**
```
bin2_b42/Contents/mods/bin2_modpack/42.15.0/
├── mod.info
└── Changelog.txt
```

### ERS_SmallProducersPack_CN 版本升级

创建了 42.15 版本的 Changelog.txt。

**文件位置：**
```
bin2_energy_routing_system/Contents/mods/ERS_SmallProducersPack_CN/42.15/
├── Changelog.txt
├── mod.info
├── icon.png
└── poster.png
```

---

## 参考资料

- 翻译格式：https://pzwiki.net/wiki/Translation
- 官方翻译仓库：https://github.com/TheIndieStone/ProjectZomboidTranslations
- 翻译数据 Schema：https://github.com/SirDoggyJvla/pz-translation-data
