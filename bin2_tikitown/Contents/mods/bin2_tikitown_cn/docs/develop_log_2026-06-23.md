# 开发日志 - 2026-06-23

## bin2_tikitown_cn / bin2_tikitown_powerplant_cn 中文翻译模组

### 版本演进: v1.0.0 → v1.1.0 → v1.2.0 (拆分) → v1.3.0 (迁移目录)

#### 当前路径 (2026-06-23 后)

两个翻译模组从 `bin2_b42/Contents/mods/` 迁移到 **`bin2_tikitown/Contents/mods/`** 统一管理：

```
bin2_tikitown/                                     # bin2 的 B42 模组集合目录
├── Contents/mods/
│   ├── bin2_tikitown_cn/                          # 蒂基镇中文翻译 (214 条)
│   └── bin2_tikitown_powerplant_cn/               # 蒂基镇发电厂中文翻译 (84 条)
└── workshop.txt / Changelog.txt                   # 合集描述与历史
```

#### 任务概览

参考三个原始 Steam Workshop 模组（`Tikitown` 3037854728、`Tikitown_CN` 3448869708、`TikitownPowerPlant`），编写 B42.15+ JSON 格式的中文翻译包。

- **v1.0.0** (2026-06-23)：首个版本，覆盖 Tikitown + TikitownPowerPlant 共 298 条翻译。
- **v1.1.0** (2026-06-23)：与原版 Tikitown_CN 对齐，修正 5 处排版差异，新增 1 条键名兼容。
- **v1.2.0** (2026-06-23)：拆分 PowerPlant 部分到独立模组 `bin2_tikitown_powerplant_cn` v1.0.0。
- **v1.3.0** (2026-06-23)：从 `bin2_b42/` 迁移到 `bin2_tikitown/` 统一管理，与 `bin2_extension`、`Project_Cook_Controller_Support` 并列。

#### v1.2.0 拆分设计

##### 拆分原因

1. **可选依赖分离**：TikitownPowerPlant 是 Tikitown 的可选子模组，用户可能只想用 Tikitown。
2. **减小主模组体积**：主模组从 298 条 → 214 条。
3. **独立更新维护**：PowerPlant 更新更频繁，分开后两个模组可独立迭代。

##### 拆分方法

Python 脚本按 key 前缀/黑名单分类：
- `ItemName.json`: 以 `TikitownPower.` 开头的 key → PowerPlant 模组
- `Sandbox.json`: 以 `Sandbox_TikitownPower` 开头的 key → PowerPlant 模组
- `Recipes.json`: 33 个 PowerPlant 配方 key 黑名单 → PowerPlant 模组
- `IG_UI.json`: 2 个 PowerPlant 物品分类 key → PowerPlant 模组

##### 拆分结果

**主模组 `bin2_tikitown_cn` (214 条)**：
```
ItemName.json    148 条  棒球卡 35 / BSSO 警服 18 / 历史军装 24 / Plush 12 / 罐头 12 / 医疗 3 / 其他 44
Recipes.json      17 条  收藏品 13 + Plush 2 + 其他 2
Sandbox.json      25 条  Tikitown 沙盒选项
Tooltip.json      11 条  棒球卡叙事 + 药剂说明 + 邮局包裹
IG_UI.json         3 条  GoKart / 钥匙 ×2
ContextMenu.json   2 条  注射药剂 / 开启罐头
UI.json            2 条  收藏品 / 发电厂分类标签
MapLabel.json      6 条  地图标签
```

**独立模组 `bin2_tikitown_powerplant_cn` (84 条)**：
```
ItemName.json    42 条  PowerPlant 零件 + 中间品
Recipes.json     33 条  锻造 + 组装 + 修复 + 调配
Sandbox.json      7 条  部件损耗 / 销毁 / 基础损耗率
IG_UI.json        2 条  发电厂零件分类（兼容原版两种键名）
```

#### 文件结构

```
bin2_b42/Contents/mods/
├── bin2_tikitown_cn/
│   ├── README.md
│   ├── 42.19.0/
│   │   ├── mod.info                    # id=bin2_tikitown_cn, modversion=1.2.0
│   │   ├── Changelog.txt
│   │   ├── poster.png
│   │   └── media/lua/shared/Translate/CN/
│   │       ├── ItemName.json (148)
│   │       ├── Tooltip.json (11)
│   │       ├── Sandbox.json (25)
│   │       ├── Recipes.json (17)
│   │       ├── IG_UI.json (3)
│   │       ├── ContextMenu.json (2)
│   │       ├── UI.json (2)
│   │       └── MapLabel.json (6)
│   └── common/
│       └── media/lua/shared/Translate/CN/Tikitown/
│           ├── title.txt
│           └── description.txt
└── bin2_tikitown_powerplant_cn/
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

#### 依赖关系

| 模组 | require | loadModAfter |
|------|---------|--------------|
| `bin2_tikitown_cn` | `\TikiTown, \Tikitown_CN` | `\TikiTown, \Tikitown_CN` |
| `bin2_tikitown_powerplant_cn` | `\TikitownPower` | `\TikitownPower` |

#### 用户启用组合

- **只用 Tikitown**：`Tikitown` + `Tikitown_CN` + `bin2_tikitown_cn`
- **Tikitown + 发电厂**：上述 + `TikitownPower` + `bin2_tikitown_powerplant_cn`

#### 经验总结（可复用）

1. **跨模组翻译键空间不冲突**：Tikitown 主模组用 `Tikitown.*`，TikitownPowerPlant 用 `TikitownPower.*`，命名空间隔离清晰。

2. **优先参考原版汉化模组的语义和排版**：原版 `Tikitown_CN` 已提供高质量中文翻译，继承其翻译风格和排版细节（半角括号、紧凑空格）确保社区一致性。

3. **键名兼容性的价值**：保留原版键名（如 `IGUI_ItemCat_*` vs `ItemCat_*`）可以让多个翻译模组并存而不互相覆盖。

4. **翻译模组拆分原则**：当原模组本身有可选子模组时，应将翻译模组也拆分为对应子模组，避免用户被迫下载不需要的翻译。

5. **覆盖度自检 Python 脚本模板**：解析 TXT 的 `Key = "Value"` 格式 → 归一化前缀 → 与 JSON keys 集合做差集。

6. **拆分时优先按 key 前缀**：ItemName 用 `Module.` 前缀、Sandbox 用 `Sandbox_Module` 前缀、Recipe 用白名单匹配，IGUI 用黑名单匹配。

#### 参考资源

- Steam Workshop:
  - Tikitown: https://steamcommunity.com/sharedfiles/filedetails/?id=3037854728
  - Tikitown_CN: https://steamcommunity.com/sharedfiles/filedetails/?id=3448869708
- 翻译 Wiki: https://pzwiki.net/wiki/Translation
- 官方翻译仓库: https://github.com/TheIndieStone/ProjectZomboidTranslations
