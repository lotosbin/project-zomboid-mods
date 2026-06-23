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
| Recipe | Recipes.json | 34 |
| Sandbox | Sandbox.json | 7 |
| IG_UI | IG_UI.json | 30 |
| UI | UI.json | 20 |
| Tooltip | Tooltip.json | 28 |
| ContextMenu | ContextMenu.json | 12 |

**总计 173 条翻译条目。**

### 字面量翻译覆盖

为 PowerPlant 客户端 Lua 中硬编码的英文（如右键菜单 `Power Grid Control`、面板标题 `Power Plant Systems`、按钮 `Shut Down Grid`、部件标签 `Rotor/Stator/Condenser Chamber`、修复提示 `Repairs locked` 等）提供**默认翻译键**。这些 key 同时以两种形式提供：
- **带前缀规范名**（如 `ContextMenu_PowerGridControl`）— 用于 PZ 引擎查找
- **裸字符串**（如 `Power Grid Control`）— 与 Lua 字面量直接匹配，作为冗余备份

## 历史

- v1.2.0 (2026-06-23)：为 PowerPlant 字面量提供默认翻译键（ContextMenu 12 / UI 20 / IG_UI 30 / Tooltip 28，共 +78 条）。
- v1.1.0 (2026-06-23)：补充 PZ 原版 CN 通用 UI 键冗余备份。
- v1.0.0 (2026-06-23)：从 bin2_tikitown_cn v1.1.0 拆分出 PowerPlant 部分独立发布。
- (2026-06-23)：从 `bin2_b42/` 迁移到 `bin2_tikitown/` 统一管理。
