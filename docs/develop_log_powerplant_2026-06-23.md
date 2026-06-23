# 开发日志 - 2026-06-23

## bin2_tikitown_powerplant_cn 中文翻译模组

### 当前路径 (2026-06-23 后)

模组从 `bin2_b42/Contents/mods/bin2_tikitown_powerplant_cn/` 迁移到 **`bin2_tikitown/Contents/mods/bin2_tikitown_powerplant_cn/`** 统一管理。

### 任务概览

从 `bin2_tikitown_cn` v1.1.0 拆分出 TikitownPowerPlant 部分的简体中文翻译，作为独立模组发布。

### 关键决策

**1. 拆分而非合并**
- TikitownPowerPlant 是 Tikitown 的可选子模组
- 拆分开后，用户可以选择只翻译 Tikitown 部分，不必强制下载 PowerPlant 翻译
- 减小主模组体积（298 条 → 214 条）

**2. 拆分方法（Python 脚本）**
按 key 前缀/黑名单分类：
- `ItemName.json`: 以 `TikitownPower.` 开头的 key → PowerPlant 模组
- `Sandbox.json`: 以 `Sandbox_TikitownPower` 开头的 key → PowerPlant 模组
- `Recipes.json`: 33 个 PowerPlant 配方 key 黑名单 → PowerPlant 模组
- `IG_UI.json`: 2 个 PowerPlant 物品分类 key → PowerPlant 模组

### 翻译覆盖

```
ItemName.json    42 条  PowerPlant 零件 + 中间品
Recipes.json     33 条  锻造 + 组装 + 修复 + 调配
Sandbox.json      7 条  部件损耗 / 销毁 / 基础损耗率
IG_UI.json        2 条  发电厂零件分类（兼容原版两种键名）
```

### 文件结构

```
bin2_tikitown_powerplant_cn/
├── README.md
└── 42.19.0/
    ├── mod.info                    # id=bin2_tikitown_powerplant_cn, modversion=1.0.0
    ├── Changelog.txt
    ├── poster.png
    └── media/lua/shared/Translate/CN/
        ├── ItemName.json (42)
        ├── Recipes.json (33)
        ├── Sandbox.json (7)
        └── IG_UI.json (2)
```

### mod.info 配置

```ini
name=bin2扩展 - TikitownPowerPlant 中文翻译
id=bin2_tikitown_powerplant_cn
poster=poster.png
versionMin=42.15.0
description=蒂基镇发电厂 (TikitownPowerPlant) 简体中文汉化包...
tags=Chinese;Translation;TikitownPowerPlant;PowerPlant
author=bin^2
modversion=1.0.0
category=content
require=\TikitownPower
loadModAfter=\TikitownPower
```

### 经验总结

1. **翻译模组拆分原则**：当原模组本身有可选子模组时，应将翻译模组也拆分为对应子模组，避免用户被迫下载不需要的翻译。

2. **拆分时优先按 key 前缀**：ItemName 用 `Module.` 前缀、Sandbox 用 `Sandbox_Module` 前缀、Recipe 用白名单匹配，IGUI 用黑名单匹配。

3. **键名兼容性的保留**：从主模组继承的 `IGUI_ItemCat_PowerPlantParts` + `ItemCat_PowerPlantParts` 两个键名都保留，确保兼容不同原版 EN JSON。

4. **依赖指向原模组而非翻译模组**：`require=\TikitownPower` 而非 `require=\Tikitown_CN`（Tikitown_CN 是 Tikitown 的翻译，不翻译 PowerPlant）。

### 历史

- v1.0.0 (2026-06-23)：从 bin2_tikitown_cn v1.1.0 拆分出 PowerPlant 部分独立发布。
