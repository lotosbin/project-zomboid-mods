# bin2_tikitown_powerplant_cn

蒂基镇发电厂 (TikitownPowerPlant) 简体中文汉化包。

> 本模组从 `bin2_tikitown_cn` v1.1.0 拆分而来，作为独立模组发布。

## 引用来源

- 参考 Steam 创意工坊：
  - [TikitownPowerPlant](https://steamcommunity.com/sharedfiles/filedetails/?id=3037854728)（Tikitown 包的子模组）

## 依赖

- TikitownPower（原作模组）

## 兼容性

- Project Zomboid Build 42.15.0 及以上版本（采用 JSON 翻译格式）。
- 目录：42.19.0。

## 翻译覆盖

| 类型 | 文件 | 条数 |
|------|------|------|
| ItemName | ItemName.json | 42 |
| Recipe | Recipes.json | 33 |
| Sandbox | Sandbox.json | 7 |
| IG_UI | IG_UI.json | 2 |

**总计 84 条翻译条目。**

## 翻译明细

- **42 个零件名**：IndustrialFilter / PumpBlades / PumpCheckValve / PumpDisch / PumpSuction / PumpImpeller / PumpSeals / TurbineRotor / TurbineControlSystem / FurnControl / TurbineBlades / TurbineStator / IndustrialGrease / IndustrialOil / IndustrialAntifreeze / EmptyIndustrialCan 等
- **33 个配方**：锻造 (Forge_Powerplant_*)、组装 (Assemble_Powerplant_*)、修复 (Repair*)、调配 (Mix_Coolant_Base / Mix_Corrosion_Inhibitor) 等
- **7 个沙盒选项**：DailyDegradeChance / PartsCanBeDestroyed / RunningWearMultiplier（含 label + tooltip）
- **2 个 IGUI 键**：`IGUI_ItemCat_PowerPlantParts` (兼容原版 Tikitown_CN 键名) + `ItemCat_PowerPlantParts` (兼容 PowerPlant 自身 EN 键名)

## 历史

- v1.0.0 (2026-06-23)：从 bin2_tikitown_cn v1.1.0 拆分出 PowerPlant 部分独立发布。
- (2026-06-23)：从 `bin2_b42/` 迁移到 `bin2_tikitown/` 统一管理。
