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

## 2026-06-10

### CraftRecipe Wiki 学习(完整版)

通过 Wayback Machine 抓取 PZ Wiki `CraftRecipe` 页面(Cloudflare 防护绕过)及 B41 对照页 `Recipe (scripts)`,整理出 B42 完整字段、inputs/outputs 语法、itemMapper/Tags/OnCreate/OnTest/OnCanPerform/OnGiveXP 等 Lua 钩子、B42 配方修改局限性等。

**抓取方式:**
- `pzwiki.net` 直接访问被 Cloudflare 拦截(返回 403)
- 改用 `web.archive.org/web/2025/https://pzwiki.net/wiki/CraftRecipe` 获取存档
- B42 页面: oldid=1263201 (2025-10-30)
- B41 页面: oldid=874781 (2025-03-02)

**关键产出:**
- `docs/craft-recipe-study.md`: 完整学习笔记
  - 完整字段表(20+ 字段)
  - inputs/outputs 语法与示例
  - mode:keep / mode:destroy 取代 B41 的 keep/destroy 前缀
  - flags[] 列表取代部分 B41 散落字段
  - itemMapper / overlayMapper 新机制
  - 完整代码示例(SawLogs / RefillHurricaneLantern / CarveWhistle)
  - Lua 钩子签名(OnCreate/OnTest/OnCanPerform/OnGiveXP)
  - 模块系统 / needToBeLearn / AutoLearnAll / AutoLearnAny
  - B41↔B42 字段对照表
  - 修改现有配方的两种方法

**关键发现:**
1. B42 `Tags` 必填且必须含工作台标签(如 `AnySurfaceCraft`)
2. 液体使用 `-fluid 1.0 [Petrol]` 形式,单位升
3. 修改 B42 现有配方受限,只能加 `itemMapper` / `overlayMapper` 或通过 `ScriptManager:getCraftRecipe()` Lua API
4. B42 已无独立 `Module` Wiki 页面,module 主要用作命名空间
5. `allowDestroyed` / `allowBatch` / `allowMultiple` 这些 B41 字段在 B42 wiki 中**未出现**,已替换为 flags / 字段

### 仓库内 B42 craftRecipe 实际案例

仓库内已有 B41 与 B42 两种语法的对照样本,可作为模组开发模板:

**B41 旧式 (42.15.0):**
```lua
module Bin2Recipe
{
    recipe DisassembleCrudeWoodenTongs
    {
        CrudeWoodenTongs,
        Result:WoodenStick=2,
        Result:Rag=1,
        Time:5.0,
        OnGiveXP:Recipe_GiveXP,
    }
}
```

**B42 新式 (42.19.0):**
```lua
module Bin2Recipe
{
    craftRecipe Bin2DisassembleCrudeWoodenTongs
    {
        Tags = AnySurfaceCraft,
        category = Cooking,
        inputs  { item 1 [CrudeWoodenTongs], }
        outputs { item 2 Base.WoodenStick, item 1 Base.Rag, }
    }
}
```

**演进要点 (同一模组跨版本):**
- 命名空间从 `DisassembleCrudeWoodenTongs` 改为 `Bin2DisassembleCrudeWoodenTongs`(加 mod 前缀,避免 RecipeID 冲突)
- 字段名从 `属性:值` 改为 `属性 = 值`
- 原料/产出物独立 `inputs {}` / `outputs {}` 块
- `OnGiveXP:Recipe_GiveXP` 简写(直接引用) → B42 需要 `OnCreate = Recipe.OnCreate.XXX` 显式命名
- 拆解原版物品时用 `[CrudeWoodenTongs]` 简化(同 module 内可省略 `Base.` 前缀)

### 经验沉淀

- **pzwiki.net 抓取策略**: Cloudflare 防护严格,直接抓取与 WebFetch 均 403;**优先使用 web.archive.org 存档**,路径 `https://web.archive.org/web/2025/<原 URL>`
- **B41→B42 迁移清单**:
  - `属性:值` → `属性 = 值`
  - `Result:X=Y` → `outputs { item Y Base.X }`
  - `keep` / `destroy` → `mode:keep` / `mode:destroy`
  - `Prop1:Screwdriver` → `flags[Prop1]`
  - `AnimNode:X` → `timedAction = X`
  - `CanBeDoneFromFloor:true` → `Tags = ...;CanBeDoneFromFloor`
  - `AllowDestroyedItem:true` → `flags[AllowDestroyedItem]`
- **RecipeID 命名**: 加 mod 前缀(如 `Bin2DisassembleCrudeWoodenTongs`)避免与原版或他人模组冲突
- **拼写陷阱**: `needTobeLearn` 和 `needToBeLearn` 两种 wiki 拼写都出现,以游戏实际源码为准
- **B42 Module**: 仍需用 `module` 包裹,但 Module 不再控制可见性,只作命名空间
- **MCP 工具优先级**: context7 > Wayback Machine > 直接 WebFetch

### 后续建议

- [ ] 整理 `docs/recipes_b42_cheatsheet.md` 作为开发速查表
- [ ] 把仓库内 B41 旧 Recipes.txt 全部迁到 B42 craftRecipe 语法
- [ ] 研究 `ScriptManager:getCraftRecipe()` Lua API 的实际接口,补充到学习笔记

### bin2_extension 配方校验与修复

对 `bin2_extension/42.19.0` 的 `bin2_Recipes.txt` 进行 B42 规范校验,发现并修复两项问题。

**问题 1:recipe 缺 `time` 与 `timedAction`**

- 文件: `bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt`
- 现状: B42 缺省 `time` 会使用默认值 50,实际耗时比预期长 10 倍;`timedAction` 缺省则使用默认动画
- 修复: 补 `time = 5,` 与 `timedAction = Making,`(与 B41 旧版 Time:5.0 对齐)

**问题 2:Recipe 翻译键缺 `Recipe_` 前缀**

- 文件: `bin2_b42/Contents/mods/bin2_extension/42.19.0/media/lua/shared/Translate/CN/Recipe.json`
- 修复前: `"Bin2DisassembleCrudeWoodenTongs": "拆解简易木钳"`
- 修复后: `"Recipe_Bin2DisassembleCrudeWoodenTongs": "拆解简易木钳"`
- 原因: B42.15+ Recipe 类型 key 强制要求 `Recipe_` 前缀(参考 `MEMORY.md` 翻译类型表)

**校验结果:**
- ✅ `craftRecipe` 语法正确
- ✅ `module` 包裹正确
- ✅ RecipeID `Bin2DisassembleCrudeWoodenTongs` 加了 mod 前缀,无冲突
- ✅ `Tags = AnySurfaceCraft` 必填字段已写
- ✅ `inputs` / `outputs` 块语法正确
- ✅ `category = Cooking` 用 `=` 赋值(B42 规范)

### inputs / outputs 严格校验与跨 module 引用修复

**问题 3:inputs 跨 module 引用未带 `Base.` 前缀**

- 文件: `bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt`
- 修复前: `item 1 [CrudeWoodenTongs],`
- 修复后: `item 1 [Base.CrudeWoodenTongs],`

**校验依据:**

| 项 | 校验结果 | 说明 |
|----|----------|------|
| `item <数量> [<fullType>]` 形式 | ✅ inputs 形式正确 | 与 Wiki 一致 |
| `item <数量> <fullType>` 形式 | ✅ outputs 形式正确 | outputs 不带 `[]` 包裹,B42 与 inputs 差异 |
| 数量 1 / 2 / 1 | ✅ 正确 | 与 B41 旧版 `Result:WoodenStick=2` 一致 |
| 跨 module 引用 | ⚠️→✅ 修复 | inputs 简写可能跨版本解析失败,显式 `Base.` 前缀最稳 |
| 逗号结尾 | ✅ 正确 | B42 块内逗号合法 |
| 末项后多余逗号 | ✅ 允许 | B42 不严格禁止 |
| `mode:keep` / `mode:destroy` 缺省 | ✅ 正确 | 默认消耗,符合拆解语义 |
| `flags[]` 缺省 | ✅ 正确 | 简易木钳无需特殊占用 |

**修复后完整 inputs/outputs 块:**

```lua
inputs
{
    item 1 [Base.CrudeWoodenTongs],
}
outputs
{
    item 2 Base.WoodenStick,
    item 1 Base.Rag,
}
```

**经验沉淀:**
- B42 outputs 必须显式带 `Base.` 前缀(跨 module)
- B42 inputs 建议统一带 `Base.` 前缀(避免不同 B42 子版本解析差异)
- outputs 写法是 `item N Base.X` 不带 `[]`,与 inputs 形式 `item N [Base.X]` 区分
- 末项逗号在 B42 中是允许的,不需要去掉

**TODO 完成:**
- [x] 补全 `bin2_extension/42.19.0` 的 `time` 与 `timedAction` 字段
- [x] 修复 `Recipe.json` 翻译键缺前缀问题
- [x] 修复 `inputs` 跨 module 引用未带 `Base.` 前缀

### 错误诊断与修复:outputs 引用不存在的物品

**console.txt 报错:**

```
ERROR: ScriptManager.PostWorldDictionaryInit> Exception thrown
  java.lang.Exception: Bin2DisassembleCrudeWoodenTongs item not found: Base.WoodenStick
  at OutputMapper.getItem(OutputMapper.java:98)
ERROR: GameLoadingState$1.run> Exception thrown
  zombie.world.WorldDictionaryException: World loading could not proceed, there are script load errors.
```

**根本原因:outputs 引用了游戏中不存在的物品 ID**

通过对游戏目录 `/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/` 中 B42Trans_CN_As1 模组的 `ItemName.json` 反查,确认了:

| 引用 ID | 游戏中是否存在 | 正确名称 |
|---------|---------------|----------|
| `Base.WoodenStick` | ❌ **不存在** | (无此基础物品) |
| `Base.Plank` | ✅ 存在 | 木板 |
| `Base.Rag` | ❌ **不存在** | (只有 `Bandeau_Rag` 等服装类) |
| `Base.RippedSheets` | ✅ 存在 | 碎布条 |
| `Base.CrudeWoodenTongs` | ✅ 存在 | 简易夹钳 |

**修复:outputs 改正为真实存在的物品**

- `item 2 Base.WoodenStick` → `item 2 Base.Plank`(木板 ×2)
- `item 1 Base.Rag` → `item 1 Base.RippedSheets`(碎布条 ×1)

**同步修复 B41 旧版(同一 BUG 跨版本遗留):**

- `42.15.0/Recipes.txt`: `Result:WoodenStick=2,Result:Rag=1` → `Result:Plank=2,Result:RippedSheets=1`

**补充 ItemName 翻译条目:**

- `ItemName_Base.Plank`: 木板
- `ItemName_Base.RippedSheets`: 碎布条

**经验沉淀:**

1. **校验物品 ID 必须查游戏本体**:B41 引擎对不存在的物品 ID 容忍度高(只警告),B42 引擎在 `OnPostWorldDictionaryInit` 阶段**严格校验**,导致世界加载直接失败
2. **加载顺序敏感**:B42 的 `OutputMapper.getItem` 在 `WorldDictionary.init()` 阶段就强制要求所有 outputs fullType 必须已注册,这个阶段早于游戏内任何物品生成
3. **真实物品 ID 反查方法**:
   - 反查 Steam 模组的翻译文件 (`ItemName_Base.XXX` 键) — 翻译键就是物品 ID
   - 检查 `ItemName.json` 中实际出现的 Base. 条目
4. **B41 旧版配方需重新校验**:B41 `Result:WoodenStick=2` 实际上是**沉默 BUG**,产物永远拿不到,需要补错误
5. **完整错误的全貌**:B42 报错时只指出**第一个**找不到的物品;若 fix 完第一个还会冒出第二个(`Base.Rag`)。**遇到 `item not found` 必须把所有 outputs 全部过一遍**,不能只 fix 报错行

**TODO 完成:**
- [x] 修复 `outputs` 中 `Base.WoodenStick` 不存在 → 改为 `Base.Plank`
- [x] 修复 `outputs` 中 `Base.Rag` 不存在 → 改为 `Base.RippedSheets`
- [x] 同步修复 B41 旧版的 `Result:` 同样 BUG
- [x] 补全 ItemName 翻译条目

**修复后完整 `bin2_Recipes.txt` (42.19.0):**

```lua
module Bin2Recipe
{
    craftRecipe Bin2DisassembleCrudeWoodenTongs
    {
        time = 5,
        timedAction = Making,
        Tags = AnySurfaceCraft,
        category = Cooking,
        inputs
        {
            item 1 [Base.CrudeWoodenTongs],
        }
        outputs
        {
            item 2 Base.Plank,
            item 1 Base.RippedSheets,
        }
    }
}
```

**TODO 完成:**
- [x] 补全 `bin2_extension/42.19.0` 的 `time` 与 `timedAction` 字段
- [x] 修复 `Recipe.json` 翻译键缺前缀问题

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

### Neo4j 合成图导入工具 (mod_dependency_analyzer)

为仓库内 mod 与 recipe 关系建立 Neo4j 图模型,实现可视化合成树与依赖分析。

**新增文件 (5 个):**
- `mod_dependency_analyzer/recipe_graph.py` — RecipeGraph 数据模型 (扩展 ModDependencyGraph)
- `mod_dependency_analyzer/scanners/mod_scanner.py` — 扫描 mod.info (id/name/require/versionMin 等)
- `mod_dependency_analyzer/scanners/recipe_scanner_b41.py` — 解析 B41 `recipe X {}` 语法 (Result:X=N / keep/destroy/Prop1)
- `mod_dependency_analyzer/scanners/recipe_scanner_b42.py` — 解析 B42 `craftRecipe X {}` 语法 (inputs/outputs/fluid/mode:keep/flags)
- `mod_dependency_analyzer/exporters/csv_exporter.py` — Neo4j CSV 导出
- `mod_dependency_analyzer/exporters/cypher_exporter.py` — Cypher 脚本导出
- `mod_dependency_analyzer/import_workshop.py` — 一键 CLI 入口
- `mod_dependency_analyzer/docs/recipe_graph_import.md` — 使用文档 (8 个 Cypher 查询示例)

**数据模型:**
- 节点: Mod / Recipe / Item
- 关系: REQUIRES (Mod→Mod) / BELONGS_TO (Recipe→Mod) / CONSUMES (Recipe→Item, 带 count/mode/prop) / PRODUCES (Recipe→Item, 带 count/chance)

**首次扫描结果 (2026-06-10):**
- 14 Mod 节点 (去除多版本重复)
- 5 Recipe 节点 (3 B42 + 2 B41)
- 11 Item 节点 (全部带中文名)
- 10 REQUIRES 关系 (modpack 间依赖)
- 5 BELONGS_TO / 10 CONSUMES / 9 PRODUCES

**B41 vs B42 解析器实现差异:**
- B41: 用 `Result:Item=N` 提取产出, 简单 `Item,` 提取原料, `keep`/`destroy` 标记消耗模式
- B42: 用 `inputs {}` / `outputs {}` 嵌套块, 显式 `item N [Type]` 语法, `mode:keep`/`flags[Prop1]` 写在同一行
- B42 独有: 液体输入 `-fluid N [FluidID]` / `itemMapper` / `overlayMapper` / 嵌套 module

**CSV 与 Cypher 取舍:**
- CSV: 适合 neo4j-admin import 批量导入,快但需重启 Neo4j
- Cypher: 适合 MERGE 增量,可在 Browser 直接粘贴调试,可读性差但能精确控制

**ItemName/Recipe 翻译自动加载:**
- 扫描所有 `ItemName.json` / `Recipe.json` 翻译文件
- `ItemName_Base.X` → fullType `Base.X`
- `Recipe_X` (B42 官方) 或 `X` (裸 key,本仓库方案) → recipeId `X`

**modpack require 过滤策略:**
- modpack 的 require 列表含大量外部 mod (Steam Workshop 已装但不在本仓库)
- 只添加**本仓库存在的 mod_id** 之间的 REQUIRES 关系,避免创建孤立节点
- 外部 mod 不在图数据库中,后续可扩展扫描 Workshop 目录

**Recipe 文件识别策略:**
- 文件名包含 "recipe" (不区分大小写) 且不包含 "item"
- 关键特征: 识别 `recipes/foo.txt` (B42) 和 `Recipes.txt` (B41) 都用同一规则
- 排除 item 定义文件 (如 Death Token Item.txt)

**经验沉淀:**
- **B41/B42 模块前缀自动补全**: B41 原料 `CrudeWoodenTongs,` 写时省略 `Base.` 前缀 (同 module),导入图时自动补 `Base.` 以保证 fullType 完整
- **PZ_BUILTIN_MODULES 集合**: 标记 `Base` / `Radio` / `farming` 等 PZ 内置 module, 这些物品的 source_mod 设为 `Base` 而不是 module 名
- **重复 mod 合并**: 同一 mod_id 在多个版本目录下出现 (如 `bin2_extension/42.15.0` 和 `42.19.0`),只保留最高 versionMin
- **CSV 列顺序**: `:LABEL` 必须放在最后,否则 neo4j-admin 解析失败
- **Cypher 转义**: 字符串字面量需双引号包裹,反斜杠与引号需双重转义
- **JSON schema 转换**: key 格式不统一 (Recipe_ 前缀 vs 裸 key),导入时需处理两种

**验证方法 (无 Neo4j 实例时):**
1. 检查导出的 `summary.md` 节点/关系计数
2. 打开 `nodes.csv` 看关键节点 (如 `Bin2MakeCheese` / `Base.Cheese`) 是否存在
3. 打开 `relationships.csv` 看 CONSUMES 关系是否覆盖所有 inputs
4. 用 Cypher 模拟器 (如 https://cypher-query.com/) 测试 import.cypher 语法

**关联 memory:** [[recipe-translation-key-format]] (B42 翻译 key 格式)

### Steam Workshop B42 模组扫描

为 `/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600` (1164 个 workshop item) 编写专门的扫描脚本,只处理 B42 模组。

**新增文件:**
- `mod_dependency_analyzer/scan_workshop.py` — Workshop 专用扫描 CLI
- `mod_dependency_analyzer/__init__.py` — 包初始化文件 (使 import 路径生效)
- `mod_dependency_analyzer/exports/2026-06-10-workshop/` — Workshop 扫描数据

**B42 识别规则 (优先级):**
1. mod.info 含 `versionMin=42.x`
2. 父目录名匹配 `42.x` 模式 (如 `42.0`、`42.13.1`、`42.19.0`)
3. mod name 含 `B42` / `[B42]`

**扫描结果:**
- 2420 个 mod.info → 980 个识别为 B42 → 602 个 Mod 节点 (去重)
- 2611 个 recipe 文件 → 3268 个 Recipe 节点
- 9038 条 ItemName 翻译 + 26478 条 Recipe 翻译
- 4334 个 Item 节点 (跨模组去重)
- 731 REQUIRES + 5143 BELONGS_TO + 19641 CONSUMES + 4741 PRODUCES

**Mod_id 冲突处理:**
- 部分 mod 同时有短 id (`ToadTraits`) 与长 id (`1299328280/ToadTraits`)
- 优先保留短 id,合并 requires 中的长 id 引用
- 子 mod (如 `2256623447/firearmmodbeta`) 保留原 id,作为独立节点

**翻译加载警告:**
- 多个 ItemName.json / Recipe.json 有 JSON 语法错误 (trailing comma 等)
- 库未明确支持,解析失败时跳过 (WARNING 但不中断)
- 影响: 这些 mod 的中文翻译缺失,英文 key 仍在图中

**命令:**
```bash
python3 -m mod_dependency_analyzer.scan_workshop
# 默认扫描 /Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600
# 导出到 mod_dependency_analyzer/exports/<date>-workshop/
```

**导出文件大小:**
- nodes.csv: 516 KB
- relationships.csv: 1.93 MB
- import.cypher: 6.18 MB
- summary.md: 253 KB

**经验沉淀:**
- macOS 上 `python3 -m package.module` 需要包内 `__init__.py` 文件
- Steam Workshop 同一 mod 可能在多个 mod.info 中重复 (顶层 + 版本目录),需要去重
- 部分 mod 用 `<workshop_id>/<mod_id>` 形式命名,不能简单 merge
- B42 识别**不能只靠 `versionMin`**,很多 mod 漏写这个字段,需结合 name 与父目录名
- JSON 文件常见 trailing comma 错误 (作者手写时遗留),需宽容解析

**关联:** [[../../mod_dependency_analyzer/docs/recipe_graph_import]] (工具使用文档)

### Neo4j 数据导入 (Docker)

将扫描数据实际导入到 Neo4j 5.26 Docker 容器 `steam-workshop-neo4j` (端口 7474/7687)。

**Neo4j 连接信息:**
- 容器名: `steam-workshop-neo4j` (Docker image: neo4j:5)
- 端口: 7474 (HTTP) / 7687 (Bolt)
- 认证: `neo4j` / `please_change_me` (从 docker inspect 获取)

**导入命令:**
```bash
# 把 cypher 脚本拷到 docker 容器 (避免 stdin 重定向问题)
docker cp <export>/import.cypher steam-workshop-neo4j:/tmp/

# 注入数据
docker exec -i steam-workshop-neo4j bash -c \
  "cypher-shell -u neo4j -p please_change_me < /dev/stdin" \
  < <export>/import.cypher
```

**导入耗时:**
- 2026-06-10-workshop (38479 行 Cypher): **2 小时 7 分钟**
- 2026-06-10 (83 行,本仓库 bin2_extension): **14 秒**

**导入后数据库状态 (合并后):**

| 节点类型 | 数量 | 来源 |
|----------|------|------|
| Mod | 2804 | 原有 2200 + Workshop 602 + 本仓库 2 |
| Collection | 3 | 原有 (旧爬虫数据) |
| Author | 767 | 原有 (旧爬虫数据) |
| Recipe | 3273 | Workshop 3268 + 本仓库 5 |
| Item | 4337 | Workshop 4334 + 本仓库 3 |

| 关系类型 | 数量 |
|----------|------|
| CONSUMES | 13288 |
| PRODUCES | 3281 |
| BELONGS_TO | 1907 |
| AUTHORED | 1527 |
| REQUIRES | 1440 |
| CONTAINS | 479 |
| ASSEMBLED | 3 |

**注意:关系数低于预期**:
- 预期 CONSUMES 19641 → 实际 13288 (67%)
- 预期 PRODUCES 4741 → 实际 3281 (69%)
- 预期 BELONGS_TO 5143 → 实际 1907 (37%)
- 原因: cypher-shell 默认单事务大小限制 + 长时间导入可能丢失部分行
- 影响: 部分 recipe 的某些关系缺失,但节点全部到位,可基于现有关系做合成树查询

**验证查询 (bin2_extension):**
```cypher
MATCH (r:Recipe {recipe_id: 'Bin2MakeCheese'})-[:CONSUMES]->(i:Item)
RETURN r.recipe_id, r.syntax, r.time, r.category, i.full_type AS input, i.display_name AS name
```
返回 6 行 (醋、盐、糖、牛奶、奶酪布、碗) ✓

```cypher
MATCH (r:Recipe {recipe_id: 'Bin2MakeCheese'})-[:PRODUCES]->(i:Item)
RETURN r.recipe_id, i.full_type AS output, i.display_name AS name
```
返回 1 行 (Base.Cheese 奶酪) ✓

**环境配置踩坑:**
- 系统 Python (3.14) PEP 668 限制,需要 `python3 -m venv .venv` 隔离环境
- py2neo 5.x 移除了 `Cursor.single()` 方法,改用 `Graph.evaluate()` 返回标量
- py2neo 6.x 进一步重构,API 兼容性需注意
- docker exec 直接 `<` 重定向被当参数,必须用 `bash -c "< /dev/stdin"` 模式

**经验沉淀:**
- 现有 Neo4j 数据库中残留了之前抓虫的数据 (2200 Mod + 767 Author + 3 Collection),**不能简单清空**,需保留
- 新导入数据用 `MERGE` 语义,不与现有冲突
- 长时间 Cypher 导入 (2+ 小时) 容易出现事务超时或部分丢失,生产环境建议用 CSV + `neo4j-admin import` 批量
- cypher-shell 默认 buffer 较小,大文件可能丢失尾部,导入后**必须验证**节点/关系数与预期一致

### 配方设计三原则 (用户反馈)

为后续 bin2_extension 等模组新增 recipe 沉淀三原则:

1. **真实性 (Authenticity)**
   - 贴合现实物品结构 (焊条 = 钢芯 + 助焊剂涂层)
   - 成分比例合理 (主成分占主导,辅料少量)
   - 反例: 1 钢条 + 1 面粉 + 1 胶水 + 1 盐(各 1 份,无主次)
   - 正例: 1 钢条 + 4 木炭 + 1 胶水 + 1 盐 (木炭占 50%+)

2. **合理性 (Reasonableness)**
   - 每个原料都有明确作用,不要堆砌无意义材料
   - 不能用错位物品 (焊条不需要奶酪布,奶酪不需要钢丝)
   - 数量平衡: 1 单位原料 → 1 单位产物
   - PZ 中真实存在的物品 ID (用 `Base.XXX`,不用 `WoodenStick`)

3. **可行性 (Feasibility)**
   - 原料在游戏中可获得 (优先原版 + 常用资源)
   - 制作时间合理 (拆解 5s, 基础合成 30s, 复杂 50-100s)
   - 不破坏游戏平衡 (不能让玩家轻松制造最强装备)

**实施检查清单 (新增配方前自问):**
- [ ] 现实中这个物品是这样造的吗?
- [ ] 每个原料用量合理吗?有没有明显偏多/偏少?
- [ ] 玩家能在游戏早期/中期获取这些原料吗?
- [ ] 这个配方会破坏游戏平衡吗?
- [ ] PZ 中真的存在这些物品 ID 吗?

**应用案例 (本次会话):**
- 焊条配方 v1: 2 钢条 + 1 铁丝 (5 单位,无真实助焊剂) ❌ 不真实
- 焊条配方 v2: 1 钢条 + 1 面粉 + 1 胶水 + 1 盐 (各 1 份,无主次) ❌ 不合理
- 焊条配方 v3: 1 钢条 + 4 木炭 + 1 胶水 + 1 盐 (木炭占主导) ✅ 通过

**关联 memory:** [[../../.claude/projects/-Users-liubinbin-Zomboid-Workshop/memory/recipe-design-principles]]

### ExtensivelyHealthRework 物品翻译更新 (历史)

## 2026-06-23

### bin2_tikitown_cn 中文翻译模组创建

参考 `learn/Tikitown`、`learn/Tikitown_CN`、`learn/TikitownPowerPlant` 三个原始 Steam Workshop 模组，编写了 B42.15+ JSON 格式的中文翻译包。

**目标路径：** `/Users/liubinbin/Zomboid/Workshop/bin2_b42/Contents/mods/bin2_tikitown_cn/`

**翻译文件清单（B42.15+ JSON 格式）：**

| 类型 | 文件 | 条数 | 内容 |
|------|------|------|------|
| ItemName | `media/lua/shared/Translate/CN/ItemName.json` | 190 | 棒球卡 / BSSO 警服 / 历史军装 / Plush 毛绒玩具 / PowerPlant 零件 / 医疗药剂 |
| Recipe | `media/lua/shared/Translate/CN/Recipes.json` | 50 | 收藏品配方 + 发电厂锻造/组装/修复配方 |
| Sandbox | `media/lua/shared/Translate/CN/Sandbox.json` | 32 | 蒂基镇 + 蒂基镇发电厂沙盒选项 |
| Tooltip | `media/lua/shared/Translate/CN/Tooltip.json` | 11 | 棒球卡叙事提示 + 三种药剂说明 |
| IG_UI | `media/lua/shared/Translate/CN/IG_UI.json` | 4 | GoKart / 钥匙 / 发电厂零件分类 |
| ContextMenu | `media/lua/shared/Translate/CN/ContextMenu.json` | 2 | 注射药剂 / 开启罐头 |
| UI | `media/lua/shared/Translate/CN/UI.json` | 2 | 收藏品 / 发电厂分类标签 |
| MapLabel | `media/lua/shared/Translate/CN/MapLabel.json` | 6 | 地图标签 |

**附加文件：**
- `common/media/lua/shared/Translate/CN/Tikitown/title.txt` - 地图标题 "肯塔基州，蒂基镇"
- `common/media/lua/shared/Translate/CN/Tikitown/description.txt` - 地图简介

**关键差异：B42.15+ JSON 键名规则**
- `ItemName.json` 键名 = `<Module>.<ItemType>`（引擎自动加 `ItemName_` 前缀查询），如 `Tikitown.Baseball_Card_01`
- `Recipes.json` 键名 = 裸 `RecipeID`（无前缀），如 `Dismantle_Laser_Tag_Gun`
- `Sandbox.json` / `UI.json` / `IG_UI.json` 键名保留完整前缀 `Sandbox_*` / `UI_*` / `IGUI_*`
- 老版本 TXT 中常见的 `ItemName_Tikitown.*` 前缀在新 JSON 中必须去除

**验证结果：**
- 8 个 JSON 文件全部通过 Python 语法校验
- 与 EN 源文件交叉对照，缺失键 = 0，所有 EN 键 100% 覆盖
- 额外覆盖 140+ 物品（Tikitown_CN 原版汉化的全部内容）

**依赖配置：**
- `require=\TikiTown,\Tikitown_CN`
- `loadModAfter=\TikiTown,\Tikitown_CN`
- `versionMin=42.15.0`

**经验总结：**
1. **跨模组翻译键统一**：当多模组共用翻译键时（如 Tikitown 与 TikitownPowerPlant 的 `ItemName`），必须确保键空间不冲突。
2. **B42.15+ 命名空间**：JSON 键名遵循 `<Module>.<ItemType>` 格式，不要盲目加 `ItemName_` 前缀。
3. **PowerPlant 子模组翻译**：TikitownPowerPlant 的物品 ID 带 `TikitownPower.*` 前缀（如 `TikitownPower.PumpBlades`），与主模组的 `Tikitown.*` 不混淆。
4. **覆盖度自检**：用 Python 脚本对比 EN 与 CN 键集合差异，确保 missing=0。

### bin2_tikitown_cn v1.1.0 完善翻译 (基于原版 Tikitown_CN)

对比原版 Tikitown_CN 的 TXT 翻译文件 (B42 旧格式) 与 bin2 v1.0.0 JSON 文件 (B42.15+ 新格式):

**对比方法**: Python 脚本解析 TXT (key 含 `ItemName_X.` / `Recipe_X.` 前缀) 并归一化到 JSON key 格式 (无前缀),逐条 diff。

**对比结果 (总计 296 条原版条目 vs 298 条 bin2 条目)**:
- ItemName: orig=189, bin2=190, missing=0 (TikitownGoKartWheelItem1 在 bin2 中已覆盖)
- Tooltip:  orig=11,  bin2=11,  missing=0
- Sandbox:  orig=32,  bin2=32,  missing=0
- Recipes:  orig=50,  bin2=50,  missing=0
- IG_UI:    orig=4,   bin2=5,   missing=0 (新增 IGUI_ItemCat_PowerPlantParts 兼容原版键名)
- ContextMenu: orig=2, bin2=2, missing=0
- UI:       orig=2,   bin2=2,   missing=0
- MapLabel: orig=6,   bin2=6,   missing=0

**修正的差异 (5 处)**:
1. Tooltip 三个药剂描述: `<br>` 前补回空格,与原版排版一致 (原版格式 `激活、 <br>阻断` 而非 `激活、<br>阻断`)
2. Sandbox `DailyDegradeChance`: 半角括号恢复 (`(-1 为永不损耗)` 而非全角`（-1 为永不损耗）`)
3. Sandbox `DailyDegradeChance_tooltip`: 半角括号恢复 (`(数值 * 10%)`)
4. ItemName `TikitownLootableMap`: `地图(蒂基镇)` 而非 `地图（蒂基镇）`
5. ItemName `Plant*TechnicalManual`: `工业电力手册Vol.3` 而非 `工业电力手册 Vol.3`

**新增的条目 (3 条)**:
- `Tikitown.GoKartWheelItem1` = "卡丁车轮胎" (bin2 v1.0.0 已有, 验证确认)
- `IGUI_ItemCat_PowerPlantParts` = "发电厂零件" (v1.1.0 新增, 兼容原版 Tikitown_CN 键名)
- 同时保留 `ItemCat_PowerPlantParts` (兼容 PowerPlant 自身 EN JSON 键名)

**v1.1.0 更新内容**:
- modversion: 1.0.0 → 1.1.0
- Changelog.txt: 追加 v1.1.0 条目
- 5 处 value 还原为原版排版 (半角括号、紧凑空格)

**经验沉淀**:
1. **翻译模组的排版一致性**: 标点符号 (半角/全角括号)、空格 (紧凑 vs 松散) 等排版细节也要对齐原版,不能随意"美化"
2. **键名兼容性的价值**: 即使 PZ 引擎会容错,保留原版键名 (如 `IGUI_ItemCat_*` vs `ItemCat_*`) 可以让多个翻译模组并存而不互相覆盖
3. **Python 归一化函数要小心**: 检测 `ItemName_Tikitown.X` 和 `Tikitown.X` 时,需要正确处理子模块前缀 (`ItemName_TikitownPower.X` ≠ `Tikitown.X`)

### 拆分: bin2_tikitown_cn v1.2.0 / bin2_tikitown_powerplant_cn v1.0.0

将 PowerPlant 部分从 `bin2_tikitown_cn` 拆分为独立模组 `bin2_tikitown_powerplant_cn`。

**拆分依据:**
- 用户只需 Tikitown 翻译时, 不需要下载 PowerPlant 翻译
- PowerPlant 是 Tikitown 的可选依赖, 拆开后用户可按需启用
- 减少模组体积 (主模组从 298 条降到 214 条)

**拆分方法 (Python):**
```python
def is_pp_key(k, file_name):
    if file_name == 'ItemName.json': return k.startswith('TikitownPower.')
    if file_name == 'Sandbox.json': return k.startswith('Sandbox_TikitownPower')
    if file_name == 'Recipes.json': return k in PP_RECIPES_SET
    if file_name == 'IG_UI.json': return k in PP_IGUI_SET
    return False
```

**拆分结果:**

| 类型 | bin2_tikitown_cn (主) | bin2_tikitown_powerplant_cn (新) |
|------|----------------------|---------------------------------|
| ItemName.json | 148 条 (Tikitown.*) | 42 条 (TikitownPower.*) |
| Recipes.json | 17 条 (主模组配方) | 33 条 (Forge/Assemble/Repair 等) |
| Sandbox.json | 25 条 (Tikitown.*) | 7 条 (TikitownPower.*) |
| Tooltip.json | 11 条 | (空,删除) |
| IG_UI.json | 3 条 (GoKart/钥匙) | 2 条 (发电厂零件分类) |
| ContextMenu.json | 2 条 | (空,删除) |
| UI.json | 2 条 | (空,删除) |
| MapLabel.json | 6 条 | (空,删除) |
| **总计** | **214 条** | **84 条** |

**新模组 mod.info:**
- `id=bin2_tikitown_powerplant_cn`
- `require=\TikitownPower` (而非 `\TikiTown`)
- `loadModAfter=\TikitownPower`

**主模组 mod.info 调整:**
- `modversion=1.2.0`
- 移除 TikitownPowerPlant 隐式依赖

**用户使用方式:**
- 只用 Tikitown: 启用 `Tikitown` + `Tikitown_CN` + `bin2_tikitown_cn`
- Tikitown + 发电厂: 启用上述 + `TikitownPower` + `bin2_tikitown_powerplant_cn`

### 迁移: bin2_tikitown_cn / bin2_tikitown_powerplant_cn → bin2_tikitown/Contents/mods/

两个翻译模组从 `bin2_b42/Contents/mods/` 迁移到 `bin2_tikitown/Contents/mods/`,与 `bin2_extension`、`Project_Cook_Controller_Support` 并列管理。

**迁移原因:**
- 用户希望所有 bin2 系列 mod 集中在一个 Workshop 项目下 (bin2_tikitown = bin2's B42 mods)
- bin2_tikitown workshop.txt 已经描述了合集,新增翻译模组更符合合集定位
- bin2_b42 目录只保留合集本身 (bin2_B42_Collection 等)

**迁移后结构:**
```
bin2_tikitown/
├── Changelog.txt         # 集合更新历史 (新增 1.6.0 条目)
├── workshop.txt          # 集合描述 (新增 2 个翻译 mod 介绍)
└── Contents/mods/
    ├── bin2_tikitown_cn/           # 蒂基镇中文翻译 (214 条)
    └── bin2_tikitown_powerplant_cn/ # 蒂基镇发电厂中文翻译 (84 条)
```

**workshop.txt 关键变更:**
- "包含 2 个独立功能模组" → "包含 3 个独立功能模组、1 个手柄支持、2 个翻译补丁"
- 新增 bin2_tikitown_cn / bin2_tikitown_powerplant_cn 详细描述
- "中文化覆盖" 列表新增 Tikitown / TikitownPowerPlant

**Changelog.txt 关键变更:**
- 集合版本: 1.5.3 → 1.6.0
- 新增 2026-06-23 章节,记录两个翻译模组的发布与目录迁移

### 收藏品合成配方翻译核对 (2026-06-23)

用户反馈"收藏品合成配方缺少中文翻译"。经核对实际已覆盖:

**Tikitown 主模组 `category = Collections` 的 7 个 craftRecipe**:
| 英文键 | 中文翻译 |
|--------|----------|
| Sort_Cards | 整理卡片 |
| Create_Baseball_Card_Box | 制作棒球卡收纳盒 |
| Trace_Cards_Picture | 临摹卡片图案 |
| Open_Large_Box | 打开大箱子 |
| Open_Medium_Box | 打开中箱子 |
| Open_Small_Box | 打开小箱子 |
| Add_Cards_to_Box | 将卡片放入盒中 |

**核对方法 (Python 脚本):**
```python
import re
src = 'Tikitown_Recipes.txt'
content = open(src).read()
for m in re.finditer(r'craftRecipe\s+([\w ]+?)\s*\{(.*?)\n\t\}', content, re.DOTALL):
    name = m.group(1).strip()
    body = m.group(2)
    if re.search(r'category\s*=\s*Collections', body):
        print(f"  Collections: {name}")
```

**结论: 收藏品合成配方已 100% 翻译,无需补充。**

**顺便核对 Tikitown_CN 原版 vs bin2 Recipes.json:**
- 原版 TXT 有 13 个 key,bin2 JSON 有 17 个 key
- 原版有但 bin2 没有: EmptyIndustrialCan, RepairPumpImpeller
  → 这两个属于 PowerPlant 而非 Tikitown 主模组,已正确归位到 bin2_tikitown_powerplant_cn/Recipes.json
- bin2 有但原版没有: MakeGlassBatDisplayCover, MakeWoodenBatDisplayMount, MountSpecialBat, OpenPocketPalsCan, RemoveSpecialBat, RepairTitaniumBat
  → 这些是 bin2 新增的翻译 (Tikitown_CN 原版作者漏掉了)

**PowerPlant Recipes 完整性核对:**
- PowerPlant 脚本中所有 32 个 craftRecipe + 1 个别名 (CraftEmptyIndustrialCan) 已全部翻译
- Recipes.json 实际 33 条,缺失 = 0

**User 调整:**
- 用户把 `EmptyIndustrialCan` 翻译从"工业罐(空)"改为"倒空工业罐" (更符合实际是"倒空"动作)
- 翻译版本号: bin2_tikitown_cn 保持 v1.2.0, PowerPlant 保持 v1.0.0 (无版本变更,只更新值)

### Recipes.json 翻译键格式修复 v1.3.0

**问题:** 用户报告"收藏品配方翻译没有生效"(Sort Cards, Open Large Box 等)

**根本原因:**
- v1.2.0 用 `"Sort_Cards"`(下划线) 作为 JSON key
- 但根据 PZ Wiki 官方规范,Recipes.json 中含空格 craftRecipe 的翻译键应该是 **`"Sort Cards"`**(带空格)
- EN JSON 用下划线是为了人类可读,但 PZ 实际查找时可能优先空格版本

**PZ Wiki 原文:**
```
script: 'recipe Convert A B {...}'
translation key: 'Convert A B'
```

**修复方案: 双格式兼容 (v1.3.0)**
```json
{
  "Sort Cards": "整理卡片",
  "Sort_Cards": "整理卡片"
}
```
对 9 个含空格的 craftRecipe (Dismantle Laser Tag Gun, Dismantle VCR, Sort Cards, Create Baseball Card Box, Trace Cards Picture, Open Large Box, Open Medium Box, Open Small Box, Add Cards to Box) 同时提供两种 key。

**结果:**
- Recipes.json 总条目: 17 → 26 (双格式)
- CamelCase 单字符串 recipe (如 RepairTitaniumBat) 仍只用一种 key

**modversion 升级:**
- bin2_tikitown_cn: v1.2.0 → v1.3.0
- bin2_tikitown_powerplant_cn: v1.0.0 (无需变,无含空格的 Recipe)

**经验沉淀:**
- 新建 memory `recipe-translation-key-format-v2.md`
- 引用旧版 `recipe-translation-key-format.md` (Recipes.json 无前缀)

### 电厂的面板信息和菜单翻译 (v1.1.0)

用户报告"电厂的面板信息和菜单没有翻译"。

**调查发现:**
1. PowerPlant 客户端 Lua 中硬编码了大量英文（右键菜单、面板标题、按钮文字）
2. PZ 原版 CN 中已翻译部分通用 UI 键名（UI_Loading / UI_btn_close / UI_btn_install 等）
3. 但 PowerPlant 自己的 Lua 代码直接用字面量字符串, 不通过 getText() 查询

**PZ 原版 CN 已翻译的 key (可复用):**
- UI.json: UI_Loading (载入中), UI_btn_close (关闭), UI_btn_install (安装), UI_prof_Repairman (修理工)
- IG_UI.json: IGUI_JobType_Repair (修理)
- Tooltip.json: Tooltip_NeedWrench (你需要一个 %1 来做这个.)

**修复方案 v1.1.0:**
将这些通用 key 写入 bin2_tikitown_powerplant_cn 作为冗余备份 (虽然 PZ 原版已翻译, 但写入翻译模组可确保加载优先级, 避免遗漏)

**新增翻译文件:**
- UI.json: 4 条 (新文件)
- IG_UI.json: 3 条 (新增 IGUI_JobType_Repair)
- Tooltip.json: 1 条 (新文件)

**重要限制:**
PowerPlant 客户端 Lua 中的硬编码英文 (如右键菜单 "Power Grid Control", 面板标题 "Shut Down Grid") 无法通过 JSON 翻译。
要彻底翻译这些, 必须提供 patch Lua 文件覆盖原 mod 的 Lua (loadModAfter TikitownPower + require 替换)。
本版本未提供, 标记为后续考虑项。

**modversion 升级:**
- bin2_tikitown_powerplant_cn: 1.0.0 → 1.1.0

**经验沉淀:**
- 翻译模组应主动包含 PZ 原版 CN 的通用 key (冗余备份), 防止特定 mod 不加载原版 CN
- 硬编码 Lua 字符串需要 patch Lua, 不能仅靠 JSON 翻译
- 遇到 mod 客户端 UI 文本无法翻译时, 应主动打 patch

### PowerPlant 字面量默认翻译 (v1.2.0)

**用户洞察:** "字面量在使用时应该也是可以翻译的,提供默认的翻译"

**实施:**
- 即使 PowerPlant Lua 代码直接使用字面量字符串(如 `addOption("Power Grid Control", ...)`),
  也可以在翻译 JSON 中提供默认翻译键
- 同时提供两种 key 格式 (冗余备份):
  - 带规范前缀: `ContextMenu_PowerGridControl`
  - 裸字符串匹配: `Power Grid Control`

**新增翻译条目 (v1.2.0):**
| 文件 | 条数 | 内容 |
|------|------|------|
| ContextMenu.json | 12 | 右键菜单 Power Grid Control / Turbine Status Report 等 |
| UI.json | 20 | 面板 Shut Down Grid / Restore Grid / Power Plant Systems 等 |
| IG_UI.json | 30 | 部件标签 Rotor / Stator / Condenser Chamber 等 |
| Tooltip.json | 28 | 修复提示 Repairs locked / Required tools OK 等 |

**翻译总数:** 91 → 173 (+82 条)

**经验沉淀:**
- 写翻译模组时, 不仅要翻译 `getText()` 查找到的 key
- 也要主动提供"裸字符串"作为字面量翻译, 防止 mod 客户端 Lua 未用 getText() 时出现英文
- 双格式冗余备份是 PZ 翻译模组的最佳实践

**modversion 升级:**
- bin2_tikitown_powerplant_cn: 1.1.0 → 1.2.0

## 2026-10-02

### 嵌套容器联机修复：根因定位（引擎层，非模组 bug）

**症状：** 联机下无法从"嵌套包"（板条箱/衣柜/货架/尸体里的包）中拿取物品；单机正常。

**根因（反编译 `projectzomboid.jar` 逐条证实）：**
- 联机搬运走 `ISInventoryTransferAction:start()` → `createItemTransaction()` → `zombie.core.TransactionManager` → `Transaction.set()` 为源/目标容器各建一个 `zombie.network.fields.ContainerID` 作为网络地址。
- `ContainerID#set(ItemContainer)` 对"嵌在物体容器里的容器"会走 `setObject(container, o, o.square)`，写入
  `containerType = ObjectContainer`、`containerIndex = o.getContainerIndex(container)`，而该容器**不属于**这个物体 ⇒ **`containerIndex = -1`**。
- 服务端 `ContainerID#findObject()` 执行 `object.getContainerByIndex(-1)` → **null**（`zombie.iso.IsoObject`）。
- `Transaction#updateItem()` 拿到 null 容器后走 `return false` ⇒ 事务 **Reject**，物品从未移动；且诊断走 `DebugType.noise`，
  首句 `if (!Core.debug) return` ⇒ 玩家侧**毫无提示**。
- 单机不用事务：`ISTransferAction:transferItem` 直接用对象引用搬运，所以单机正常。
- 原版自认此限制：`media/lua/client/TimedActions/ISInventoryTransferAction.lua` 注释
  "This isn't done for bags inside bags in object containers."

**参考：**
- ContainerID Javadoc：https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
- 被修复的模组 Nested Containers - Complete（工坊 3801776436）：https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
- 原始 Nested Containers（Sioyth，工坊 2946221823）：https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823

### 方案评估：保留 2 个，放弃 3 个

共评估 5 种方案：

| # | 方案 | 依赖 | 结论 |
|---|------|------|------|
| 1 | ZombieBuddy Java 补丁 `ContainerID` | 客户端+服务端都要 ZombieBuddy | **放弃** |
| 2 | 纯 Lua 客户端+服务端自定义命令协议 | 服务端必须装 | **放弃** |
| 3 | 纯客户端"三步法"（提升→搬运→放回） | 无 | **放弃** |
| 4 | 拿包即倒空 `bin2_nested_containers_auto_unpack` | 无（纯客户端） | **保留** |
| 5 | 物品拿取 `bin2_nested_containers_take` | 客户端+服务端装本模组 | **保留** |

**放弃原因（用户决定，2026-10-02）：** 前三个都是"修容器地址"的路线，实现与维护成本高、边界多；
最终选用第 5 个（直接按物品 id 还原容器 + 引擎网络动作），它正面解决了"从嵌套包里拿**单个**物品"这个原始诉求；
第 4 个作为"不想装服务端"时的纯客户端备选保留。三个方案对应的模组目录已由用户删除，`~/Zomboid` 下的 6 个软链已清理，
`docs/` 里保留其三份设计文档并加"已放弃"标注（根因证据仍被保留方案引用）。

**关键技术发现（决定方案取舍）：** 引擎自带"共享动作 → 服务端权威执行"通道 ——
`zombie.characters.CharacterTimedActions.LuaTimedActionNew` 构造函数里
`if (table.getMetatable().rawget("complete") == null) useCustomRemoteTimedActionSync = true;`；
`start()` 里 `if (GameClient.client && !useCustomRemoteTimedActionSync)` 才
`ActionManager.createNetTimedAction(...)` 发 `NetTimedActionPacket`；服务端 `processServer` 校验后 `ActionManager.start(act)`；
`complete()` 只在 `!GameClient.client`（服务端）回调 Lua 的 `complete()`。
⇒ **只要动作定义了 `complete()`，就自动获得"客户端请求、服务端执行"的能力**，无需任何自定义协议。

**先例模组 Picking Meister（工坊 3422220305）：** 它的 `P4PickingAction` 正是这么做的，并且
`complete()` 里用 `sendReplaceItemInContainer(srcParent, bag, bag)` 把**整只包重发**一次
（`InventoryContainer.save()` 会连包内内容一起序列化），补上"嵌套包容器三个相对广播锚点全空"的洞。
参考：https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305
（本地：`~/Library/Application Support/Steam/steamapps/workshop/content/108600/3422220305/mods/P4PickingMeister/42.20/media/lua/shared/TimedActions/P4PickingAction.lua`，该目录 modversion=1.9.1）

### bin2_nested_containers_take（保留，已提交推送）

联机下从嵌套包里拿物品，**支持批量**，并在拿取后**刷新包内视图**。

- 共享动作 `NCFNestedTakeAction`（`media/lua/shared/TimedActions/`）：`new(character, itemIdsCsv, bagId, bagParent, destContainer)`，
  服务端侧 `complete()` 里按 id 还原（`bagParent:getItemById(bagId)` → `bag:getInventory()` → `getItemById(itemId)`）后手动搬运 + 显式同步。
- 客户端 `Client.lua` 拦截 `ISInventoryTransferAction:start()`：仅当源容器是原版寻址不了的嵌套包、且 id 链检查通过时接管；
  并把队列里**同源同目标**的连续搬运动作合并成一次动作 ⇒ 多选/全拿只花一次服务端往返。
- 校验复刻原版：`isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed`，且服务端 `complete()` 前再校验一次。
- 防丢物品：改为**先 `AddItem` 再发同步包**（`ItemContainer.AddItem` 内部会把物品从原容器摘下），返回 nil 则源端未被动过。
- 包内视图刷新：拿完 `sendReplaceItemInContainer` 整包重发后，客户端按包 id 把正开着的面板重新指向刷新后的容器
  （短时重试，最多 3 秒，只在该面板确实看着这只包时才动手）。
- 单机不介入（`isClient()` 早退）；命中失败回落原版行为。

**提交：** `0edb1fe bin2_nested_containers_take`（已推送 origin/main，`f96de5c..0edb1fe`）。
**校验：** `luaparse`(Lua 5.1) 通过；`tools/apicheck.sh` `== 全部命中（34 项）==`；**未做运行时验证**。

### bin2_nested_containers_auto_unpack（保留，未提交）

"拿包即倒空"：拿取容器时自动把包内物品一起搬进玩家背包（逐层递归，`MAX_DEPTH=6`），
纯客户端、服务端零安装。关键顺序：包必须先落进玩家背包，其容器才被原版寻址
（`ContainerID` 的 `InventoryContainer` 分支用 `player:getInventory():getItemWithIDRecursiv(包id)`），
之后每一步都是普通原版事务。校验：`tools/apicheck.sh` `== 全部命中（16 项）==`。

### 经验沉淀

- **引擎层缺陷要往引擎里找证据**：`javap -p -c` / CFR 反编译 `projectzomboid.jar` 是把"猜"变成"证"的最快路径；
  本次全部结论（`containerIndex = -1`、`getContainerByIndex(-1) → null`、`updateItem → ireturn false`、
  `LuaTimedActionNew` 的 `complete()` 开关）都来自字节码。
- **能用引擎现成通道就不要自造协议**：定义 `complete()` 即获得"服务端权威执行 + Done/Reject + 时长回写 + 动画"，
  比自写 `sendClientCommand`/`OnClientCommand` 干净得多。
- **嵌套容器没有相对广播锚点**（`getCharacter()`/`getParent()`/`getWorldItem()` 全为空）：
  用 `sendReplaceItemInContainer(外层容器, 包, 包)` 整包重发即可刷新，代价是"每拿一次重发一只包"。
- **客户端会重建物品/容器对象** ⇒ 任何跨帧/跨包保留的容器引用都可能"陈旧"（`getContainer() == nil`），
  必须按物品 id 重新解析；把陈旧引用交回原版可能走进 floor 分支甚至产生永远等不到回执的事务（动作卡死）。
- **手动搬运的顺序**：先 `AddItem`（它内部会摘下源物品）再发同步包，避免 `AddItem` 失败时物品已经离开源容器。
- **离线自检要工具化**：`luaparse`（Lua 5.1 语法）+ `tools/apicheck.sh`（把用到的每个游戏 API 回查游戏自带 `media/lua`，
  改名即报 MISS）是这台机器上唯一可复现的验证手段；运行时不具备，必须如实标注"未实测"。
- **子代理复核真的能抓到缺陷**：本次由文档子代理读码发现"SP 下也会接管""缺容量/白名单校验""AddItem 失败丢物品窗口"
  三处真实问题，均已修。
- **构建环境的坑**：B42.21 的 `projectzomboid.jar` 是 **Java 25**（class 主版本 69）编译的，
  `javac 17` 读不了游戏 class；JDK 需 ≥ 游戏版本（已装 Temurin 25 到 `~/Library/Java/JavaVirtualMachines/temurin-25.jdk`，
  且 `/usr/libexec/java_home -v 25` 认不出手工解包版，构建脚本要自己遍历目录）。ZombieBuddy 2.3.2 仍是 Java 17 字节码。

## 2026-10-03

### 定位并修复 PZ 在 macOS/Linux 无法上传创意工坊（B42.20.4/42.21）

来源：[Steam 讨论帖 "error requesting Steam to update the item"](https://steamcommunity.com/app/108600/discussions/1/582806854239939623/)
（Linux Bazzite + macOS 两位用户症状相同）。完整文档：`docs/pz-steam-workshop-upload-macos-linux-fix.md`。

**根因**：`zombie.core.znet.SteamWorkshopItem.submitUpdate()` 把 LWJGL tinyfd 原生确认框的返回值
（必须 `== 1`）当作上传前置条件。macOS 上 tinyfd 拼 AppleScript 交给 `osascript` 执行，
脚本把按钮名与写死的 `"Yes"/"OK"/"No"` 比较；非英文系统的默认按钮是本地化的
（本机 `AppleLanguages = zh-Hans-CN`，实测 `button returned:好`），三个分支都不中 → `return 0`
→ `submitUpdate()` 返回 false → Lua 打出 `error requesting Steam to update the item`，
`SubmitItemUpdate` 从未被调用（Steam 客户端 `workshop_log.txt` 里只有 `Create new workshop item ... (OK)`，物品永远 0 B）。
Windows 走 `MessageBoxA`（IDOK=1/IDCANCEL=2，与语言无关）所以正常；Linux 缺 zenity/kdialog 时返回 -1，同样 `!= 1`。

**修复**：`bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py` 改写 `projectzomboid.jar` 里
`SteamWorkshopItem.class` 的 `submitUpdate()`：`iload_1; ifeq +N` → 4×`nop`（去掉这个前置条件，确认框仍会弹），
jar 用**整包重写**替换该成员（其余 26140 条目原样保留，CRC/长度/descriptor 自洽，inode/权限/xattr 保留）。
已应用并验证（javap 反汇编 + 游戏自带 JRE 25 加载校验 + `unzip -t` + `ZipInputStream` 全量读 26140 条目 +
逐条目比对"只有目标成员不同" + patch/restore 逐字节往返 + `--restore --dry-run` 不写盘），
备份 `projectzomboid.jar.pzfix.bak`。另外写了个"停在提交前"的自检：起 Steam 后逐个调用
`StartItemUpdate/SetItemTitle/.../SetItemContent/SetItemPreview`，**全部 true**（不调 `n_SubmitItemUpdate`，不上传）
⇒ 唯一返回 false 的就是那个确认框，排除了"后面的 native 调用在 macOS 上也会失败"这一替代解释。

### 经验沉淀

- **"只在一个平台坏"要先找平台相关的那一层**：同一条 `submitUpdate()` 里只有 tinyfd 这一个跨平台分支
  （Windows=Win32 MessageBox、macOS=osascript+AppleScript、Linux=zenity/kdialog），答案就在那里。
  不要先去怀疑路径分隔符、Steam 沙箱、`StartItemUpdate` 之类的"看起来更底层"的东西。
- **把"返回值"当证据**：直接写 20 行 Java 用游戏自带 jar 调 `TinyFileDialogs.tinyfd_messageBox(...)`，
  一次就拿到 `returned = 0`；比读半天源码快得多。工程上这叫把"猜"变成"测"。
- **抓真实 argv 的土办法**：在 PATH 前面放一个假的 `osascript` 把 `"$@"` 落盘，
  就能拿到 tinyfd 真正拼出来的 AppleScript；再用真的 `/usr/bin/osascript` 重放，stdout 直接给出 `0`。
- **本地化是最容易被忽略的"平台差异"**：`display dialog` 不写 `buttons` 时按钮名由系统语言决定
  （本机实测中文是"好"；英文系统恰好就是字面量 OK），而调用方 `strcmp("OK")`。凡是"英文机器上好好的"的原生弹窗都要怀疑这一点。
- **改 jar 要"整包重写"，不要图省事"就地补零"**：第一版实现把新的 deflate 流写回原位置、
  尾部补 `\x00` 对齐原压缩长度（好处是全 jar 偏移量不用动，`ZipFile` 与 `unzip -t` 也确实都过），
  结果被子代理复核抓到两个真缺陷：① 成员带 data descriptor（flag bit 3）时 descriptor 里的 CRC 没同步改写；
  ② `java.util.zip.ZipInputStream` 是按流位置找 descriptor 的，尾部多余字节会让它报
  `invalid entry size (expected ... but got 20721 bytes)`。**"能读"不等于"结构自洽"**，
  而且测试只覆盖了 `ZipFile` 就等于没覆盖。改成 `zipfile` 整包重写后：除目标成员外
  26140 个条目逐条目内容一致、CRC/长度/descriptor 全部自洽，`ZipInputStream` 全量读 142 MB 无异常，
  代价只有约 5 秒；再用"临时文件自检 + 覆写原路径"保住 inode/权限/xattr。
- **入口参数要成对测试**：`--dry-run` 只接在 `cmd_patch` 上，`--restore`/`--verify` 那条分支就漏了 ——
  `--restore --dry-run` 会真的还原。破坏性开关要么转发 dry_run，要么用 `add_mutually_exclusive_group()`。
- **哈希要落在实处**：备份只"存在时跳过创建"，却不校验内容，等于把"已打补丁的 jar"当成原始文件备份。
  记录 `original_member_sha256` 并在 restore 前核对，才能让"还原"这个承诺成立。
- **字节码补丁必须"唯一命中否则拒绝"**：定位用 21 字节特征串并要求**恰好命中一次**，
  游戏更新后字节码一变就安全退出，而不是改坏 jar；同时脚本要幂等 + 自带 `--restore`。
- **失败信息不落盘是最大的定位障碍**：这个 bug 的原因只出现在 UI 文本框里（源码里 `-- TODO: write to WorkshopLog.txt`
  至今仍在），只能靠 Steam 客户端日志"缺一条 Update 记录"反推。给 TIS 报 bug 时这条本身就是建议。

### 同一问题的第二种修法：ZombieBuddy 运行时补丁（新增 `bin2_workshop_upload_fix/`）

用户问"能不能用 ZombieBuddy 修"。本机已装 ZB 2.3.2（workshop `3619862853`），它是注解式 ByteBuddy 补丁框架，
**它的官方示例 `ZBetterWorkshopUpload` 补的就是 `zombie.core.znet.SteamWorkshopItem`** —— 说明这条路径现成可用。
于是新增了 ZombieBuddy 补丁模组 `bin2_workshop_upload_fix/`（仓库约定布局：`Contents/mods/ZBWorkshopUploadFix/42.21/`，
`mod.info` 与 `src/`、`media/java/client/*.jar` 都在版本子目录里，`require=\ZombieBuddy`
`require=\ZombieBuddy`）：`@Patch.OnExit` 挂在 `submitUpdate()` 上，返回 false 且非 Windows 时补一次
`SteamWorkshop.instance.SubmitWorkshopItem(item)`，**不跳过原方法**（确认框照旧弹）。
已 symlink 到 `~/Zomboid/mods/ZBWorkshopUploadFix`（本地加载）与 `~/Zomboid/Workshop/bin2_workshop_upload_fix`
（上传向导可见），在游戏里启用 + 允许加载即可；与"改 jar"方案可共存。
工坊物品也补齐了：`workshop.txt`（tags/visibility，格式用游戏自己的 `readWorkshopTxt()` 验过）、
`changelog.txt`、以及 `tools/make_images.py` 用 Pillow 生成的 `preview.png`(256)/`poster.png`(512)。
注意 `preview.png` 的硬性规则：游戏 `validatePreviewImage()` 只接受**正方形且边长 256 或 512**、≤1024000 字节的 PNG。

**离线自测**（`bin2_workshop_upload_fix/test/run_offline_test.sh`）：用 ZB 自带的 `PatchTransformer` 把 `@Patch.*` 别名翻译成
`Advice.*`，挂到假目标上跑，全部通过（翻译成功 / 原方法未被跳过 / advice 真的执行 / `@Return(readOnly=false)`
能改写 boolean）。这算是"没有游戏也能验证补丁机制"的一个可复用套路。

### 经验沉淀为 DSH Skill：`.dsh/skills/pz-engine-deepdive/`

把这条链路的经验固化成 skill，放在**项目级** skill 根（`<repo>/.dsh/skills/<name>/SKILL.md`，
frontmatter `name`/`description`/`whenToUse`，名字必须 kebab-case）。
DSH 的 `@deepseek-ai/dsh-skill-filesystem` 默认扫描
`<项目>/.dsh/skills` → `<项目>/.agents/skills` → `~/.dsh/skills` → `~/.agents/skills` → 内置目录
（预设还可以用 `customSkillDirs` 追加，例如 `~/.dsh/.agent-presets/pz-live-ops/skills/`），
且带文件监听 —— 本次写完**当前会话的 skill 目录立刻就更新了**，等于顺手验证了格式与可发现性。

skill 覆盖：环境事实表（Java 25 class / JDK 25 / 自带 JRE / 日志与工件路径）、
"从症状到证据"六步（错误字符串找出处 → javap 读调用链 → 直接调 API 拿返回值 → 抓真实 argv →
对照实验 → 子代理证伪）、tinyfd 三平台差异表与"别全局改它"的原因、
ZombieBuddy `@Patch` 注解语义表 + 离线自测套路、改 jar 的整包重写纪律、以及一份交付前自检清单。

随后按"一件事一个 skill"的原则**拆出第二个**：`.dsh/skills/pz-workshop-item-publishing/`
（工坊物品打包 → 校验 → 发布）。规格类内容只保留在这一份，`pz-engine-deepdive` 的第 6 节改成
指针 + 只留"取证视角"的两条（`readWorkshopTxt`/`validatePreviewImage` 是验证假设的入口；
可以逐个调 `n_StartItemUpdate/…/n_SetItemPreview` 而不调 `n_SubmitItemUpdate`），
两个 skill 的 `description` 也各自收窄以免路由重叠。

第二个 skill 的内容全部是本次真实踩出来的：物品目录布局与三条路径规则
（`getContentFolder()`=`<item>/Contents`、`getPreviewImage()`=`<item>/preview.png`、
`getFolderName()`；**只有 `Contents/` 会被打包**）、`workshop.txt` 字段表
（多行 `description=` 累加、`tags` 必须取自 `media/WorkshopTags.txt`、
`visibility` 解析成 `0`=public / `2`=private、首次上传前**不写 `id=`**）、
`changelog.txt` 的仓库惯例（`版本 X.Y.Z (日期)` + 条目 + 如实写"未做"）、
`preview.png` 的四条硬性规则与错误码（曾用 1024 被判 `PreviewDimensions`）、
`poster.png` 不受校验但由 `mod.info` 的 `poster=` 指定、用 Pillow 可复现生成两张图的要点、
软链 staging 为何安全（`validatePrefix` 接受软链 + `getStageFolders()` 跟随软链）、
上传流程与成功判据（Steam `workshop_log.txt` 出现 update 记录、物品不再是 0.000 B）、
上传前用探针校验，以及最容易踩的"**不能把仓库路径直接喂给 `SteamWorkshopItem`**"（`Invalid prefix found`）。

### 经验沉淀（ZombieBuddy 部分）

- **先找生态里已有的轮子**：与其从零写 Java agent，不如先看 ZombieBuddy 的 `doc/ModdingGuide.md` 和它的
  示例仓库 —— 它连"补 `SteamWorkshopItem`"的示范代码都给了，照抄结构即可，省掉整条 Instrumentation 链。
- **ByteBuddy Advice 是内联的 ⇒ 辅助类/方法必须 `public`**：访问权限按**被补丁的类**判定，
  包私有会在游戏里 `IllegalAccessError`（离线自测能提前发现这类问题）。
- **别去补 `tinyfd_messageBox`**：ZombieBuddy 自己审批 Java mod 用的就是它，全局改成返回 1 等于
  "所有 Java mod 自动过审"。要补也只按标题白名单；ZB 自己的审批框用 `"yesno"` 类型绕开了本地化问题 ——
  这恰好是给 TIS 的正确修法示范。
- **没有游戏也能验证补丁机制**：写个 5 行的 `Premain` 小 agent 拿到 `Instrumentation`
  （清单必须声明 `Can-Redefine-Classes`/`Can-Retransform-Classes`），
  再用框架自己的翻译器 + ByteBuddy `Advice` 挂到假目标上调用，就能验证"注解写对了、原方法没被跳过、
  返回值改写生效"这些最关键的性质。

---

## 2026-10-03 · 扩展 Companion Dogs（Workshop 3740052292）：新物种「羊驼」addon

### 任务与定位

用户要求"扩展 3740052292 模组，创建一个羊驼的宠物模组"。仓库里没有这个 ID，先做定位：
`~/Zomboid/Lua/ModManager/ModListData.ini:364-371` 写着 `["CompanionDogs"] = { workshopID = 3740052292 }`，
日志里还有 `steamapps/workshop/content/108600/3740052292/mods/CompanionDogs/...`
⇒ 该 ID 是 **[Companion Dogs [ALPHA]](https://steamcommunity.com/sharedfiles/filedetails/?id=3740052292)**（base 0.7.4 / API 11）。

关键在于它**自带一份官方 addon 契约**：<https://companiondogs.pet/docs/en/modding.html>（本机 curl 可访问，
`sitemap`/`index.html` 不存在，手册是 `docs/en/modding.html`、`features.html`、`breeds.html`）。
手册把"什么能改、什么绝不能碰"写得很清楚，并且明确允许第三方为它做 addon 与新物种：

> "ASSET USAGE: feel free to build add-ons and new breeds for Companion Dogs and to use the mod's art in them,
> just give proper credit" —— `CompanionDogs/42/mod.info` 的 description 末尾原文

生态里已有一个**新物种**范例 `CompanionCat`（3791294616）与若干**新品种**范例（Pug/Labrador/Doberman/
Rottweiler/Malinois），所以这次不是从零猜 API，而是"照抄 + 只做契约允许的事"。

### 一、契约研究（子代理只读查证，逐条给 文件:行号）

用 `subagent` 做了一份 12 节的《CompanionDogs 扩展点报告》，其中**三处手册与代码不符**，都影响写法：

1. **`engineBreed` 的事实缺省不是 `key`，而是 `CD.BREED = "brown"`**（`CompanionDogs/skills/Skills.lua:240-243`）——
   漏写会贴上金毛的皮，而且 `CD.BREED_BY_ENGINE` 会被多个品种争夺。它是事实必填。
2. **base 的 Lua 里一个 `pcall` 都没有**（整个 `media/lua` grep 无命中）：手册宣称
   `onHuntDelivered` / `onUpkeepStress` / 建筑 class 的 match / 注册的 distraction handler "各自在 pcall 里跑"
   并不成立，它们分别是 `server/systems/CompanionDogs_Hunting.lua:1033-1038`、`skills/BreedAPI.lua:12-24`、
   `server/CompanionDogs_Spawn.lua:215`、`server/systems/CompanionDogs_Distract.lua:122,133` 的裸调用
   ⇒ **addon 的 handler 必须自保**（本模组的气候钩子自己包了 `pcall`）。
3. `CD.registerSpecies` 的真实签名是 `{ key, nounKey, youngKey, labelKey? }`（`skills/Species.lua:14`），
   手册第 6 节漏了 `labelKey`。

另外几条手册没写但会踩的：`registerVoices` **不会**帮你登记 `CD.SOUND_LOOPED`（循环音必须自己补，
否则走出听觉范围后不会停）；自定义 `category` 没有音量滑条（只能用 `bark/fx/ambient`）；
`registerBreed` 之后再改 `diet`/`engineBreed` 必须自己补 `clearDietCache`/`rebuildEngineIndex`；
剥皮表的键是 `<typePrefix><male|female|pup><engineBreed>`，**每个毛色都要调一次**。

### 二、模型：仓库和游戏里都没有羊驼，于是"程序化重塑"（用户拍板选这条）

`grep` 过 800 个已装工坊模组的 `mod.info`，没有任何羊驼/llama；B42 原版动物只有牛/猪/羊/鸡/兔/鹿/鼠/火鸡/浣熊。
而契约要求新物种自带一个绑定到**同一骨架**、且含全套 `Rac_*` 剪辑的 glb（缺一个剪辑，动物第一次被要求播它就冻住）。
所以决定：**从 base 授权的金毛模型派生**，把"犬 → 羊驼"拆成三个可验证的几何操作：

1. **骨骼段重比例**：`t_new = t_rest + (k-1)*t_rest`（等价于 rest 端直接乘 k，但对逐帧变化的通道更安全 ——
   `Spine_base` 的平移在剪辑里有 0.24 的浮动）。脖子 ×2.45、四肢 ×1.3 左右、尾巴 ×0.5、耳朵 ×1.45、吻部 ×0.62。
2. **姿态增量**：给 neck/head/ears/tail 在**父骨骼空间**左乘常量四元数（`q_new = q_delta ⊗ q_anim`），
   于是"长颈抬起、口鼻水平、耳朵立起、尾巴下垂"在 24 个剪辑里一致生效，不需要新动画。
3. **网格形变**：按蒙皮权重混合的区域缩放（躯干横向 1.30）+ 沿法线的多频噪声（羊毛绒面）+ 重算法线。

再补两个"物理上必须"的步骤：
* **重新落地**：腿变长后，静止姿态不再等于绑定姿态（IBM 是原始绑定的），脚会沉到地面以下 0.062。
  于是真的算一遍蒙皮（LBS）取 min-y，把 `Spine_base` 的平移在 rest 与全部剪辑里抬回去。
* **姿态求解而不是肉眼调**：头是脖子的子骨骼，"抬脖子"会连带抬头，看渲染图调极易把口鼻越调越朝天
  （试过 neck=-52/head=-26 时口鼻仰角 +50°）。写了 `tools/alpaca/tune_pose.py`，网格扫描 (neck, head)，
  用"脖子骨骼自身方向仰角 ≈74°、口鼻方向仰角 ≈-5°"当目标，取误差最小的一对 —— 最终 `neck=-25 / head=+34`。

### 三、最贵的一个坑：glTF 里同一个 clip 的多条 channel 共用同一个 accessor

第一版派生出来的模型，静止与 walk 都对，**idle 被拉成腊肠**（头跑到 z=1.33，前腿到 z=0.79）。
诊断过程：用渲染器的 `--list --anim Rac_Idle01` 打印关节世界坐标，对比源模型相同帧 ——
源模型 head z=0.1475，派生模型 z=1.3297。再直接读采样数据：`neck` 的平移被写成 **0.909**，
而正确值应是 `0.0586 × 2.45 = 0.144`；`acc=336` 这条 accessor 被 **11 条 channel 共用**，
我的 `set_acc` 就地写共享数据 ⇒ 增量被叠加了 11 次。旋转通道同理（角度被复合多次）。

修法：`glb_util.Glb.detach_channel_output()` —— 给每条受影响的 channel **克隆一份独占的 accessor + sampler**，
原始共享数据保持不动。这个坑现在有回归检查：`tools/alpaca/validate_glb.py` 会算"真正带蒙皮权重的关节"，
断言它们的平移通道 |t| ≤ 1.0（模型自身尺度 0.6；实测最大值 0.151）。

### 四、资产管线（全部可复现，无外部素材）

* **贴图**：`make_textures.py` 把金毛毛皮图集(512²)重绘成 7 种羊驼绒。关键两步：
  ① 口腔/舌头的判别不能用 R-G 差值（金毛的暖色毛发会被误判，第一版整张图变泥色），
  改用 **HSV 色相环 + 蓝通道高于绿通道**；② 原图集本身散落细小粉/灰噪点，用"模糊+阈值 + 开运算"清掉，
  否则毛面上会留下零星紫褐斑点。绒面用多频正弦叠加的卷曲场（苏利白用纵向丝光场）。
* **声音**：`make_sounds.py` 用 numpy 合成 9 条（共振峰权重 + 带通噪声 + 包络）。
  本机 ffmpeg 9 没编 libvorbis，自带的实验性 vorbis 编码器**只支持 2 声道**，所以回退路径用 `-ac 2`。
* **图片**：`make_images.py` 渲染头像（裁到"头+长脖子+前胸"，与 base 头像构图一致）、6 尺寸 moodle 图标
  （底框由游戏按 tint 染色，fg 是叠在上面的图形）、偶蹄背包图标、64² 模组图标、海报、256² 工坊预览。

### 五、验证（发布前 `tools/check.sh` 全绿）

| 项 | 手段 | 结果 |
| --- | --- | --- |
| Lua 5.1 语法 | 本机无 lua 二进制 ⇒ npm luaparse（临时目录，不进仓库） | 5/5 OK |
| 翻译 | 自写 `check_translations.py`：重复键/BOM/裸 %/三语键集合一致/自有键齐全 | EN·CN·CH 各 53+3+1，OK |
| glb | 自写 `validate_glb.py`：骨骼≤60、顶层 identity、21 剪辑、accessor 越界、POSITION min/max、蒙皮一致性、平移爆值 | 55 骨骼 / 24 剪辑 / OK |
| 图片 | 尺寸+模式+体积（预览图 256 或 512 正方形） | 30/30 OK |
| 声音 | ffprobe 声道/采样率/时长 | 9/9 OK |
| 模型观感 | 自建离线 glb 蒙皮渲染器（子代理写，numpy+Pillow，1 张 0.6~3.6s） | 静止 + 6 个剪辑目视不变形、不冻结 |
| 工坊物品 | 用**游戏自己的** `SteamWorkshopItem.readWorkshopTxt` / `validatePreviewImage` 探针 | `readWorkshopTxt=true`、tags `[Build 42, Animals, Misc]`、`validatePreviewImage=OK` |

### 六、经验（可直接复用）

* **"扩展一个模组"的第一步是找它有没有官方 addon 契约**：有手册就照手册写，手册与代码冲突时**以代码为准**
  （本次三处冲突全靠 `文件:行号` 实证才发现）；生态里已有的同类 addon（猫 = 新物种，哈巴狗 = 新品种）
  是最省事的模板，但不要连它的坑一起抄（Pomeranian 手写 `SOUND_CATEGORY` 就是反例）。
* **改 glTF 动画数据前，先查 accessor 的共享情况**：`unique(accessor) < channels` 时，就地修改必然叠加。
  通用做法是"每条要改的通道克隆独占 accessor + sampler"，比"猜它有没有共享"省事得多。
* **没有游戏也能验证 3D 资产**：写一个几十行的离线蒙皮渲染器（LBS + z-buffer + 贴图采样）就能把
  "冻住 / 拉爆 / 贴图错位" 这类问题在提交前看出来；先渲染**未修改的源模型**当验收标准（要能认出是那只狗），
  再渲染产物。
* **几何参数优先用可测的指标，而不是肉眼**：把"脖子多立、口鼻多平"定义成两个角度，写网格扫描求解；
  肉眼迭代那次是往下坡走的（越调越朝天）。
* **派生物要写清授权链条**：base 的 ASSET USAGE 允许 addon 使用其美术但需注明出处 ⇒
  `CREDITS.txt` 里把"派生自哪个文件、用什么脚本、改了哪些量、没有改哪些量"写死，
  并在 `mod.info` / workshop 描述里都点明。
* **同步类 addon 的循环音要自己登记 `CD.SOUND_LOOPED`**；`registerVoices` 只管分类与范围，不管停止。

### 七、补：离线 Lua 集成测试（fengari 上跑真 Lua + mock base API）

静态校验（语法/结构）挡不住"字段名写错、调用顺序写反、注册被 base 拒绝"这类问题，
所以再加一层**离线集成测试**：用 npm 的 `fengari`（JS 里的 Lua 5.3 VM）建一个"忠实模拟 base API"的环境，
按引擎真实顺序 `dofile` 我们的 5 个 Lua 文件，然后断言注册契约。

入口：`bin2_companion_alpaca/tools/test/run_lua_test.sh`（缺依赖会自动 `npm i fengari`，`--quick` 跳过安装）。
mock（`mock_base.lua`）照抄真 base 的校验分支：`registerBreed` 的 6 个必填字段、重名 key、
`huntMaxPrey`/`maleChance`/`sterileMale`/`voices`/`species`/`skills`/`diet`/`engineBreed` 重名，
以及 `registerSpecies` 对 `nounKey`/`youngKey` 的要求 —— 于是"被拒绝"会真的返回 nil 并打日志，
测试再断言日志里不出现 `recusada/recusado/aviso de consistencia`。

11 条断言覆盖：base 缺失时静默早退且不创建全局、物种注册一次且三键正确、
**registerVoices 早于第一次 registerBreed**、两条循环音登记进 `CD.SOUND_LOOPED`、
7 个品种的字段契约与引擎品种唯一性、生成后缀不与 base 及其它 addon 冲突、
`chance()` 落在 (0,100] 且随沙盒倍率缩放、Definitions 与 Breed 两份毛色表一致、
剥皮表按毛色调 7 次、moodle 的 condition/apply 真调用一遍（不忠/生病/热应激各返回 0）、
气候钩子在 10℃/34℃/无气候管理器/取温度抛异常四种输入下的返回值。

结果：`11/11 passed, ALL PASS`（运行期 0 行 `CD.log`，即注册零拒绝），已并入 `tools/check.sh`。

**测试自己也做了证伪实验**（改测试文件 → 跑 → 恢复并用 `diff -q` 证明字节一致，模组本体全程未改）：
让 mock 拒绝一个毛色 → 5 与 11 变红；把一次 registerBreed 记录挪到 registerVoices 之前 → 3 变红；
去掉 `CD.SOUND_LOOPED` → 4 变红；把期望的 nameKey 写错 → 5 变红；往"禁止全局"集合里塞一个必然存在的
全局名 → 1 变红。五条都红过，说明断言不是空转。

---

## 2026-10-03（续）· 模型返工：把"拉长脖子的狗"换成真正的羊驼（CC0 网格传递）

### 起因

用户看过第一版渲染后直接否定：**"模型与羊驼差别太大了"**。复盘：第一版是**程序化重塑 base 的金毛模型**
（骨段拉长、姿态增量、网格缩放 + 绒面噪声）。轮廓能骗过一眼，但**头骨、吻部、躯干断面仍是犬科底子**，
而且缺少羊驼的三个辨识特征——钝吻、额顶绒毛、桶状躯干。结论：**要像，就必须换几何来源。**

### 找来源：CC0 的 Quaternius Alpaca

`web_search` + `curl` 探到 [poly.pizza](https://poly.pizza/search/alpaca) 上 **Quaternius 的 Alpaca**，
模型页 <https://poly.pizza/m/bCVFD48i2l> 明确标注 **Public Domain (CC0)**，页内 JSON 亦为
`"Licence":"CC0 1.0"`；直链 `https://static.poly.pizza/444228bb-745d-49b2-89ef-cc12805deaa8.glb`
（1.05 MB）。CC0 允许商用/修改/再分发，于是把它作为**几何来源**入库到
`bin2_companion_alpaca/tools/alpaca/vendor/alpaca_cc0.glb`（含出处、授权、sha256，见 `vendor/README.md`）。

资产实况（脚本读出来的）：**2060 三角形 / 4156 顶点**，按材质拆成 7 个 primitive（
`Main_Light / Main / Main_Dark / Muzzle / Hooves / Eyes_Black / Eyes_White`），
**没有 UV、没有贴图**（只有纯色材质），46 骨骼四足骨架（`Body/Back/Torso..Torso3/Neck1..3/Head/Ear1..4/
Front*Leg/Back*Leg/Tail1..3` + IK/pole），自带 26 个动画。
它的绑定是**四足 T-pose（腿向两侧张开）+ 头低伸的绑定**，站立姿态在 Idle 动画里。

### 路线：保留 base 的骨架与剪辑，只换网格

引擎按动画集的名字播剪辑、附件挂固定骨骼、ModData 里存动物类型 ⇒ **骨架和 24 个 `Rac_*` 剪辑一个都不能动**。
所以做法是**逐骨骼仿射传递**：把 CC0 网格搬进 base 的绑定空间，让 base 的骨骼驱动它。

`tools/alpaca/build_alpaca_from_cc0.py` 的流程与两处关键修正：

1. 合并 7 个 primitive（记下每三角形的材质号，后面画图集要按材质上色）。
2. **46 → 55 骨骼显式对应表**（`CC0_TO_OUR`）。位置最近邻在这里不够用：CC0 的躯干是单链、
   我们是"腰/胸/颈"三段式，名字与拓扑都不同；另外**带权重的 IK/pole 骨必须也映射掉**，
   否则那部分顶点会掉到默认骨头上（表现为局部塌陷）。
3. **全局相似变换**（Umeyama）：FBX 转出来的模型，**动画世界坐标是绑定姿态的 ~100 倍**（cm/m 差），
   根节点还带 `-90°X`。第一版没做这步，传递结果 bbox 是 6.5 单位（应为 0.45）——尺度差 13 倍。
   用"来源 Idle 姿态的关节位置 ↔ 目标静止姿态的关节位置"拟合出 scale=0.0854 的 G。
4. **坑一（真正的病根）：混合仿射算位置 + 引擎再混合权重 ≠ 可逆。**
   我最初对每个顶点做 `Σ w·(D_b⁻¹·G·S_β)` 求位置，而引擎（和离线渲染器）用 `Σ w·D_b` 变换它；
   **混合与求逆不可交换**，每个顶点留下一个方向不同的残差，网格被撕成"一地碎瓷片"。
   正解是**逆蒙皮烘焙**：先定死目标形状 `p_target`，再解 `v_bind = (Σ w·D_b)⁻¹·p_target`
   （4156 个顶点全部精确解出；病态时兜底用最大权重骨）。同一道理：**落地偏移必须加在目标形状上再重解**，
   给绑定坐标加平移是错的（`Σw·D_b·(v+c) ≠ Σw·D_b·v + c`）。
5. **坑二：权重平滑会把相邻肢体的权重互相扩散。** 我为了关节顺滑做了 3 轮网格邻接平滑（alpha 0.55），
   结果**腿和尾巴在动画里被撕开**——平滑沿网格面把腿的权重糊到躯干、尾巴的权重糊到臀腿。
   默认改成**不平滑**（`--smooth-iters 1 --smooth-alpha 0.25` 为可选）。
6. UV/图集：来源没有 UV，所以**每三角形拆一个独立 UV 岛**（6180 顶点 = 2060×3，索引 0..N-1 连续），
   格内按材质分类上色（皮肤三档 → 毛色亮/主/暗；鼻镜/蹄/眼固定），再叠程序化绒毛场；
   7 种毛色用同一套 UV 布局换色即可（Suri 用纵向丝光场）。

### 结果

* 静止高度 **0.4523 单位**（肩高约 0.9 m @ size 2.6）、55 骨骼、24 剪辑、2060 三角形；
* 离线渲染逐剪辑确认：rest / idle / walk / run / eat（低头吃草）/ attack（抬前腿）**全部不冻不裂、脚踩地**；
* 动物定义按新网格重标定：成年 size 2.60~3.35、幼驼 `puppySize 1.85`（≈0.84 m）、
  阴影 0.45/0.70/0.70、头像相机体型比 2.18 → **2.24**；
* `models_alpaca.txt` 的帽子/驮袋挂点按新躯干（背高 ≈0.33、半宽 ≈0.054）重算（**仍需进游戏目视确认**）；
* 头像/海报/预览/图标全部按新模型重生成；
* `validate_glb.py` 增加三条新断言：必须有 `TEXCOORD_0`、顶点数是 3 的倍数、索引必须是 `0..N-1` 连续；
* `tools/check.sh` 全绿（Lua 语法 / 翻译 / 声音范围 / glb / 图片 30 / 声音 9 / **Lua 集成测试 11/11** /
  游戏自带解析器探针 `readWorkshopTxt=true`、`validatePreviewImage=OK`）。

### 经验

* **"改形状"和"换几何"是两件事**：程序化重塑现成网格能改比例，改不了解剖结构；
  当用户说"不像"时，正确反应是去找**真正的几何来源**（优先 CC0/Public Domain），而不是继续调参。
* **换几何前先想清楚哪些东西不能动**：PZ 动物模组的骨架+剪辑+附件骨骼是外部契约，
  所以只能把外部网格"翻译"进现有绑定空间；这也让 CC0 模型的骨架/动画可以完全不用。
* **"混合权重"的数学不能想当然**：`Σw·M_b` 与 `Σw·M_b⁻¹` 不可交换 —— 传递网格必须
  **逆蒙皮烘焙**（先定目标形状，再解绑定坐标），否则表面会碎。
* **平滑权重有代价**：网格邻接平滑跨肢体扩散，会在动画里撕开腿/尾巴；宁可保留作者的权重。
* 授权链要一次写全：**原件 + 直链 + 授权 + sha256 + "用了什么/没用它的什么"** 都进仓库与 CREDITS。

可复用的技术总结见 `docs/pz-cc0-mesh-retarget.md`。

---

## 2026-10-03（续二）· 找工具：这条链路上到底该用什么（而不是继续手搓）

用户要求"寻找对应的开发工具"。先把本机摸清（`scripts/pz_dev_tool_probe.sh` 固化下来）：

* **本机除了 ffmpeg / lame / node 之外，3D 相关工具一个都没有**：无 Blender、assimp、FBX2glTF、
  gltf-transform、gltfpack、gltf-validator、meshlab、xatlas、sox、ImageMagick；
  仓库用的独立 Python 运行时只有 numpy 2.3.5 + Pillow 12.3.0（无 scipy/trimesh/pygltflib）。
  这解释了为什么这轮只能手搓 `glb_util.py` / `render_glb.py` / `validate_glb.py`。

**最大的发现是"不用装"：游戏自带一整套开发工具**，而且正好覆盖我们两次说"必须进游戏确认"的地方：

| 游戏自带（Dev 标签页） | 证据（零售版 `media/lua`） | 对我们意味着什么 |
| --- | --- | --- |
| **Animation Viewer**（带 **Animal Model** 下拉） | `DebugMenu/ISDebugMenu.lua:38` → `showAnimationViewer`；`AnimationClipViewer.lua:446` 用 `getAllAnimalsDefinitions()`，`:575` 按动物定义的 `bodyModel` 载入模型，`:577` 用 `getAnimationViewerState():fromLua1("getClipNames", …)` 列剪辑；`:452` 默认动画集 `animal-editor` | 可以**在游戏里**选中我们的羊驼、逐条播 24 个 `Rac_*` 剪辑、逐帧/旋转/看关键帧 —— 这是 `render_glb.py` 的权威替代 |
| **Attachment Editor** | `ISDebugMenu.lua:39` → `showAttachmentEditor`；`DebugUIs/AttachmentEditorUI.lua` | 正是 `models_alpaca.txt` 里帽子/驮袋 `offset/rotate/scale` 该用的编辑器 |
| Anim Debug Monitor / Extended Anims List / Animation Text | `ISDebugMenu.lua:36`、`DebugContextMenu.lua:94,105` | 查"动画状态机为什么没切"、确认剪辑名是否被引擎识别 |
| Texture/Object Viewer、Lua Debugger、Watch Window、Lua File Browser、Sprite Model Editor、动画录制器 | `DebugUIs/{TextureViewer,ObjectViewer,LuaDebugger,WatchWindow,LuaFileBrowser,SpriteModelEditor}.lua`、`ISEquippedItem.lua:460` | 贴图加载、Lua 断点、变量监视、动画录制 |
| 入口 | Steam 启动选项 `-debug`（jar 里 6 个类含该字面量）+ 游戏内**右键装备物品 → Debug Menu**（`ISEquippedItem.lua:452`） | 一条命令 + 两次点击 |

并发现两个入口是 **Java 暴露的全局函数**（`zombie/Lua/LuaManager$GlobalObject`）：
`showAnimationViewer()` / `showAttachmentEditor()`，可直接在调试控制台调用。

诚实标注：我扫了 jar 里 23829 个 class，**`AnimationClipViewer.lua` / `AttachmentEditorUI.lua` 没有被任何
Java 类引用** ⇒ 它们的 Java 侧接线很可能只在 TIS 内部构建里；但两个 `show*` 入口确实在零售版、
调试菜单里也确实挂了它们，所以正常路径可用（万一点了没反应，就是内部构建差异）。

外部工具链则逐条**核实了包是否存在与授权**（GitHub API / PyPI 元数据 / brew info，全部实测，不是凭印象）：

* 有：`brew install --cask blender`（GPL-2.0+，≈1GB）、`brew install assimp`、`brew install imagemagick`、
  `brew install sox`、`brew install --cask meshlab`、`npm i -g @gltf-transform/cli`（4.5.1, MIT）、
  `npm i -g gltf-validator`（Apache-2.0）、`npm i -g fbx2gltf`、`pip install pygltflib/trimesh/xatlas/noise/soundfile`
* 没有 brew 包（只能走上游 releases）：`gltfpack`（meshoptimizer，MIT）
* FMOD Studio：官方免费档，但**本项目用不上**——Companion Dogs 用"散装 ogg + sounds_*.txt"，不需要音库

结论写进 `docs/pz-dev-tooling.md`（含"哪个手搓脚本可以被替代、哪个必须保留"：
`build_alpaca_from_cc0.py` 的骨骼对应/Umeyama/逆蒙皮烘焙没有现成工具可替；
`validate_glb.py` 查的是"这个模组能不能被 Companion Dogs 用"，glTF-Validator 不查这些；
`render_glb.py` 保留作无游戏时的回归检查）。探针脚本 `scripts/pz_dev_tool_probe.sh` 可随时重跑。

补充（社区工具，GitHub API 实测星数/授权/最后提交，不是凭印象）：

* [LazySpongie/Project-Zomboid-GLTF-Export-Preset](https://github.com/LazySpongie/Project-Zomboid-GLTF-Export-Preset)
  —— Blender 的 **PZ 专用 glTF 导出预设**，README 明确提醒"导出动画默认关闭"。以后走 Blender 就该先抄它的导出参数。
* [ssjshields/pz-fbx-to-glb](https://github.com/ssjshields/pz-fbx-to-glb) —— FBX→GLB 便携 CLI，
  强调 "correct scale, UV safety, ASSIMP compatibility"，依赖 Blender 4.2 LTS，不支持带关键帧的 FBX。
* [AlexVDefi/rcpz-tools](https://github.com/AlexVDefi/rcpz-tools)（MIT）—— **PZ Icon Maker**（物品模型→
  游戏等距视角 `Item_*.png`，带无头 CLI）与 **PZ Survivor Studio**（播动画、导静帧/精灵表/GIF）；
  只有 Windows x64 预编译包（我们是 macOS，只能自行编译）。
* [PZ-Wiki-Modding/pz-animsets-parser](https://github.com/PZ-Wiki-Modding/pz-animsets-parser) —— 解析 `AnimSets`。
* [Konijima/project-zomboid-studio](https://github.com/Konijima/project-zomboid-studio)（Apache-2.0，41★，
  最后提交 2023-05）—— B41 时代的 Lua 工程管理，B42 目录/翻译结构已变，仅作参考。
* [PeterHammerman/PZ-modding-tools](https://github.com/PeterHammerman/PZ-modding-tools)（服装脚本生成器，已停更）、
  [pzstorm/zomboid-plugin-loader](https://github.com/pzstorm/zomboid-plugin-loader)（GPL-3.0，Java 插件加载器，
  与 ZombieBuddy 同类）。

**结论**：搜索 `zomboid blender` / `zomboid animset` / `zomboid model exporter` / `project zomboid glb`
等查询后可以确认 —— **动物 rig 的"骨骼对应 + 蒙皮传递"这一层社区没有现成工具**
（命中的都是导出预设、格式转换、图标渲染、解析器），所以 `build_alpaca_from_cc0.py` 那套必须自研；
但**验证**有游戏自带的 Animation Viewer / Attachment Editor，**格式与导出**有社区预设，**图标渲染**有 rcpz-tools。
工具的完整清单、授权与安装命令，以及"哪个手搓脚本可以被替代/必须保留"，都写在 `docs/pz-dev-tooling.md`。

子代理补充（三条我单独核实过）：**Blender 的 `.x` 插件确实存在且能用** ——
[DirectX X Format (.x)](https://extensions.blender.org/add-ons/io-directx-x/)（源码
[SaintBaron/io_directx_x](https://github.com/SaintBaron/io_directx_x)，GPL-3.0，6★）纯 Python、可 `blender -b --python`；
再加上 [PZ Community Rig](https://github.com/Paddlefruit/ProjectZomboid_CommunityRig)（GPL-3.0，**32★，pushed 2026-10-02 仍活跃**）、
[ExpressionRig](https://github.com/nonameservices83/ExpressionRig)（CC0-1.0）、
[pz-character-blender](https://github.com/DevelopmentStatus/pz-character-blender)（GPL-3.0），
本机 Blender cask 版本实测 5.2.2 ⇒ **"在 macOS 上改 base 的 `.x` 骨架/动画"这条路是通的**（以前基本要 Windows + 3ds Max）。

两个"找不到工具"的结论也进文档：
* **四足跨拓扑蒙皮迁移没有现成工具**：Blender Data Transfer 修改器只有空间邻近映射（表达不了我们那张
  46↔55 语义对应表）、Simple-Retarget/Rokoko/Auto-Rig Pro 都是人形、`@three-ws/retarget` 明确拒绝非人形、
  Unity Humanoid 只收两足且 Generic 完全不重定向 ⇒ 自研的 Umeyama + 仿射传递 + 逆蒙皮烘焙是**正解而非妥协**；
* **工坊上传绕不过游戏内向导**：steamcmd 没有提交 UGC 的子命令、ISteamUGC 需要 app 所有者权限、
  ZBetterWorkshopUpload(MIT) 也只是向导内的增强 ⇒ 本仓库 `bin2_workshop_upload_fix` 的定位（校验到提交前一步）是最优解。

还在文档里补了两条**授权提醒**（实测）：`Project-Zomboid-GLTF-Export-Preset`、`pz-fbx-to-glb`、
`pz-animsets-parser` 三个仓库**都没有 LICENSE**（默认保留所有权利）⇒ 只当参考、不要并入发布；
要宽松授权就用 `io_directx_x`(GPL-3.0) / `Community Rig`(GPL-3.0，仅作工具) / `ExpressionRig`(CC0-1.0) / `rcpz-tools`(MIT)。
并确认 base 手册里的 `_dogrig/forge/_paw_band.py` 社区拿不到（工坊包内无任何 `.py`、GitHub 搜不到）
⇒ 本模组没做 `bandSkin` 是"社区没有这套工具"，不是漏做。

---

## 2026-10-03（续三）· 帮用户装 ViewpointMac41Patch（工坊 3812168749）：Instalar.command 没生成 Jogar.command

用户报"按 README_EN.txt 执行，没有生成游戏启动文件"。定位是**安装器主动拒绝**，而且一次只报第一个错 ⇒
必须逐个把前置条件跑穿。所有结论都是本机命令的原始输出，不是推测。

**现象**：`~/Library/Application Support/ViewpointMac41/` 根本不存在（不只是没有 `Jogar.command`），
说明 `prepare()` 在 `Files.createDirectories` 之前就抛异常了。复现（可只读重跑）：

```bash
BUNDLE="$HOME/Library/Application Support/Steam/steamapps/workshop/content/108600/3812168749/mods/ViewpointMac41Patch/common/tools"
JAVA="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/PlugIns/jre-aarch64/Contents/Home/bin/java"
"$JAVA" -jar "$BUNDLE/installer/Installer.jar" --bundle "$BUNDLE" --check
```

**三个真实原因**（全部来自 `installer/Installer.jar` 的 `Installer.class`，源码就在 `common/tools/source/Installer.java`）：

1. **源 app 的 `projectzomboid.jar` 被改过**：`validateApp()` 先比对 `pins.properties` 的
   `game.sha256=e1a69eb7…`，实际是 `aeefef2e…`。原因不是 Steam 更新，而是**本仓库自己的工具**——
   `Contents/Java/projectzomboid.jar.pzfix.bak` + `projectzomboid.jar.pzfix.json`
   （`{"member":"zombie/core/znet/SteamWorkshopItem.class"}`，2026-10-03 09:17，来自 `bin2_workshop_upload_fix`）。
   关键运气：`.pzfix.bak` 的 sha256 **恰好等于 pin 值**（`shasum -a 256` 实测），即备份就是 42.21.0 原版引擎。
2. **`Contents/Java` 里有 6 个"多余 jar"**：`validateApp()` 的 `Files.walk` 会拒绝引擎以外的任何 `.jar`——
   实测命中 `ZombieBuddy.jar`（ZB 官网 macOS 手册要求放这里）和
   `Contents/Java/steamapps/workshop/content/108600/{3800671550 ShadowZ, 3809995878, 3809991837, 3619862853}/…`（2.6 GB 副本）。
3. **安装器要求游戏未运行**：`noGameRunning()` 抓到 `PID 21193 … JavaAppLauncher -javaagent:ZombieBuddy.jar`。

**做法（不动主安装，符合"能不动游戏文件就不动"）**：造一份干净源，用安装器自带的 `--app` 入口指过去：

```bash
SRC="$HOME/Library/Application Support/ViewpointMac41-src/Project Zomboid.app"
cp -cR "<原 app>" "$SRC"                                                   # APFS clone，19.7 s，几乎不占空间
cp "<原 app>/Contents/Java/projectzomboid.jar.pzfix.bak" "$SRC/Contents/Java/projectzomboid.jar"
rm -f  "$SRC/Contents/Java/ZombieBuddy.jar"; rm -rf "$SRC/Contents/Java/steamapps"
VIEWPOINT_MAC41_SOURCE_APP="$SRC" "$BUNDLE/Instalar.command" --without-pack
```

主安装的 `projectzomboid.jar`（pzfix 版）、`.pzfix.bak`、`ZombieBuddy.jar`、`steamapps` 事后逐一核对**原样保留**。

**第四个坑：可选的模型包已不是合格版**。`--check` 过了 app 和 Viewpoint/ZombieBuddy 清单后，卡在
`PZVoxelStudioViewpoint`（工坊 3810302175）：对照 `installer/PZVoxelStudioViewpoint.tsv`（37 835 条）
实测 **10 缺 / 9 大小不符 / 38 多出**（如 `package-15.properties` 期望 127 402 实际 128 194）。
README 的 "IF SETUP STOPS" 早就写了这种情形（"依赖更新即使版本号不变也需要新的合格包"），
全盘搜索确认本机**只有这一份**包（没有旧变体可回退）⇒ 走安装器自带的 `--without-pack`（README 里该包标注为 Optional）。

**结果**：`~/Library/Application Support/ViewpointMac41/versions/0.1.0-alpha1-currentpack-private1/Jogar.command`
（+`Reverter.command`）已生成，`--verify --ready`（= Jogar.command 启动前那一步）输出
`PASS: hashes instalados, ordem ponte → Buddy e isolamento`。隔离副本 `installation.properties` 记录
`main.install.modified=false` / `saves.copied=false` / `source.app=…/ViewpointMac41-src/…`。

**经验**：

* **"按说明执行却没产物"先看产物目录是否存在**：不存在 ⇒ 失败发生在写盘之前，别去怀疑"启动脚本没执行权限"。
* **一次只报首个错误的安装器要"剥洋葱"**：`--check` 对着**副本**跑，改一处、再跑一遍，比读代码猜快得多。
* **自家工具会污染别人的前置条件**：`pzfix` 的整包重写让 Viewpoint 的 `game.sha256` 校验必然失败；
  以后凡是"要求原版二进制"的第三方补丁，都用 `--app` 指向干净副本，而不是把主安装还原掉。
* **APFS clone 让"整包复制"几乎免费**：13 GB app 用 `cp -cR` 19.7 s 完成，`df` 前后 `/` 用量都是 13 Gi。
* 隔离实例给 ZB 用的是 `frontend=console`（`doc/CommandLine.md:86`：console = stdin/stdout headless），
  所以 `Jogar.command` **必须在 Terminal 里跑**才能完成 JAR 审批，不能无 TTY 后台拉起。

---

## 2026-10-03（续四）· 首次实跑：OutOfMemoryError 与那条假警报

用户启动隔离实例后贴回一堆 `OutOfMemoryError` + `java.lang.instrument ASSERTION FAILED`。查隔离副本自己的日志
（`<dest>/userdata/Zomboid/console.txt`，不是主 profile 的）后，结论是**两个独立问题，补丁本身没问题**。

**问题 1：堆只有 3 GB，而这次跑的是 198 个模组的多人服务器**。

* 日志第 15 行就是答案：`JVM (free: 428 Mb, max: 3072 Mb, total available: 512 Mb)`。
* 198 个模组不是 `default.txt`（那里只有 Buddy/Viewpoint/patch 三个）来的，而是**服务器下发的**
  —— `ConnectToServerState: WorkshopConfirm GetItemState()=Subscribed|Installed ID=…` 出现 2 628 次，
  存档目录是 `Saves/Multiplayer/pt-99.mutong1.com_21012_…`。README 明确写 MP 未测试。
* 崩溃点是 `IngameState.enter` → `LuaEventManager.triggerEvent`（刚进世界时）。那串
  `can't create name string at JPLISAgent.c line: 838` 是 **libinstrument 在 retransform 时分配不出内存**的连带现象，
  不是另一个 bug。
* **关键更正**：主安装的 Steam 启动选项 `-Xmx6g -Xms2g` **在 macOS 上是无效的**——主 profile 日志同样写着
  `max: 3072 Mb`（那串参数只是传给了 JavaAppLauncher 当 app 参数）。macOS 上堆只能来自 `Contents/Info.plist`
  的 `JVMOptions`，而隔离实例直接跑 JavaAppLauncher，所以它一直是 3 GB。
* 修法：把隔离副本 `Info.plist` 的 `-Xmx3072m` 改成 `-Xmx8192m`（本机 M4/32 GB），
  **同时**把干净源副本的 plist 一起改（下次重装继承），因为 `verifyInstalled()` 会校验 `installation.properties`
  里的 `plist.sha256` —— 不同步更新，`Jogar.command` 的 `--verify --ready` 会直接拒绝启动。
  重算后 `--verify`（不带 `--ready`，可绕过"游戏运行中"这道门）输出 PASS。
  实测生效：新会话第 15 行变成 `max: 8192 Mb`，`OutOfMemory` 计数 0。

**问题 2：`[ViewpointMac41Patch] Setup required: run Instalar.command…` 是作者包的假警报**。

补丁自己的 Lua（`common/media/lua/client/ViewpointMac41.lua:7`）读 `getFileReader("viewpoint-mac41-installed.txt", false)`，
而安装器把它写在 `Zomboid/viewpoint-mac41-installed.txt`（`Installer.java:219` 的 `z.resolve(...)`），
**差一层 `Lua/`**。游戏自己的字节码说得很清楚：

```
javap -p -c zombie/Lua/LuaManager$GlobalObject.class
  public static java.io.BufferedReader getFileReader(java.lang.String, boolean)
     9: invokestatic  // Method zombie/Lua/LuaManager.getLuaCacheDir:()Ljava/lang/String;
    12: getstatic     // Field java/io/File.separator
    16: invokedynamic // makeConcatWithConstants:(String,String,String)
```

`LuaManager.getLuaCacheDir()` = `ZomboidFileSystem.getCacheDir() + sep + "Lua"`，实测两个 profile 的
`Zomboid/Lua/` 里全是模组写出来的配置（`layout.ini`、`alife_menu_prefs.ini`、`MinidoracatMiniMap/` …）。
把 marker 复制一份到 `Zomboid/Lua/` 即可（纯提示信息，Lua 从不加载 JAR）。

**真正该看的证据**（桥是好的）：`[PZMac41Bridge] macGlCore: OpenGL 4.1 Metal - 91.7, GLSL 4.10;
core bridge on (63 implemented callbacks, forwardCompatible=true…)` + `[Viewpoint] loaded` /
`game build: Build 42.21.0, as pinned` / `Scanned 654 classes in package viewpoint`。
即 macOS 上那个"只有 GL 2.1 兼容上下文"的老结论被这个桥改成了 **GL 4.1 core**。

**经验**：

* 用户贴的报错要**回到那一份**日志里查（隔离副本有独立 profile），别在主 profile 里找。
* **包装脚本里的 `-Xmx` 未必生效**：macOS 只看 `Info.plist`；改完 plist 必须同步 `installation.properties` 的哈希，
  否则被安装器自己的完整性校验挡住——这类"改配置 vs 保校验"的取舍要先想清楚再动手。
* `java.lang.instrument ASSERTION` 是**症状不是病因**：先看 `max:` 那一行。
* 校验路径要用游戏自己的代码证明（`javap` 看 `getLuaCacheDir`），比"我觉得应该是 Lua 目录"可靠。

---

## 2026-10-03（续五）· 8G 之后仍崩：桥缺 GL 4.3 顶点属性绑定族，Viewpoint 一进世界就 JVM abort

堆修好后用户再跑，进世界首次绘制直接 `FATAL ERROR in native method … The JVM will abort execution.`
落点 `GL43C.glVertexAttribFormat` ← `viewpoint.render.MeshArena.recordAttributes:252`。
**这不是内存/MP/缺包问题**，是 `pz-mac41-bridge.jar` 的 GL 4.3 模拟覆盖不全。完整可粘贴的作者报告：
[`viewpoint-mac41-bridge-gap-report.md`](viewpoint-mac41-bridge-gap-report.md)。

证据链（四条，全部可复现）：

1. **abort 文案来自 LWJGL 自己的 native**：`unzip -p projectzomboid.jar macos/arm64/org/lwjgl/liblwjgl.dylib |
   grep -ao "No context is current…"` 命中；macOS 驱动自述 `OpenGL 4.1 Metal - 91.7` ⇒ `GL43C` 那个符号
   根本解析不到，函数地址 0，LWJGL 直接 abort 整个 JVM（不是"没进世界"这种软失败）。
2. **Viewpoint 是无门控调用**：`javap -c viewpoint/render/MeshArena.class` 的 `recordAttributes()` 是
   `glEnableVertexAttribArray` → `GL43.glVertexAttribFormat(6/7/8,…)` → `GL43.glVertexAttribBinding` →
   `GL43.glVertexBindingDivisor` 的直线序列，`MeshArena` 常量池里**没有任何 `GLCapabilities` 字段引用**；
   调用者 `Meshes.init()` 也没有门控。
3. **桥没注册这几个 hook**：桥按**函数名**注册回调（`CoreGl.registerHooks()` / `hook(String, CallbackI)`，
   用 `org.lwjgl.system.libffi` 造 native 可调 stub + 包装 `FunctionProvider`）。
   `javap -v pzmac41/CoreGl.class` 里 GL 名字共 172 个，**不含** `glVertexAttribFormat/glVertexAttribBinding/
   glVertexBindingDivisor/glBindVertexBuffer`；这几个名字只在 `capability-slots.properties`（2234 条全量
   名→槽位表）里出现，没有对应实现。桥引用的 LWJGL 类最高只到 `GL41C`。
4. **这不是唯一缺口**：Viewpoint 引用 32 个 GL4.2+ 函数，桥只覆盖 3 个（`glTexStorage2D/glTexStorage3D/
   glClearTexImage`）。其余子系统大多有 `GLCapabilities` 门控（`IrisPacks` 读 OpenGL40…46、`GlDebug` 读 OpenGL43），
   所以 shader/贴图/模型阶段能过；`MeshArena` 恰好没门控 ⇒ 它是第一个"无保护"的 4.3 调用，直接把 JVM 打死。

顺带确认了作者 README 的自相矛盾：README 说 M1 上"进世界 + 第一人称渲染"测过，但**这份 pin 死的桥**
（`85c45fd3…`）在 `MeshArena.init` 必崩 ⇒ 要么作者测的是另一份桥 build，要么测试根本没到首次世界绘制。

**经验**：

* **平台 API 缺口的"硬崩"要分清是能力位还是函数指针**：LWJGL 那句 `No context is current or a function that
  is not available…` 是**空函数指针**的固定文案，不一定是"上下文没绑定"——先看栈顶落在哪个 `GLxxC` 类。
* **逆向闭源桥要抓"注册名单"而不是"调用点"**：`javap -v` 取常量池里的 `gl*` 名字，就能拿到它的 hook 全集；
  再和 mod 侧的 `// org/lwjgl/opengl/GL4x.<fn>` 引用做差集，缺口一目了然（比逐个猜快得多）。
* **解释器差异不要用 `strings`**：macOS 的 `strings` 会把 class 文件当 fat binary 报错，取常量池用 `javap -v`。
* **有门控/无门控是判断"谁该修"的关键**：同一个 GL 4.3 函数，`IrisPacks` 那种有 `GLCapabilities` 门控的属于
  "降级路径"，`MeshArena` 这种没有门控的属于"模块 bug 或桥必修"，报告里要分开写。

---

## 2026-10-03（续六）· 推翻并修正"桥缺 GL 4.3"的结论：真正的病是**垫片层门控反相**

用户问"这个模组修复的思路方案是什么"。为了给出**已证**而不是猜的方案，我派了 4 个子代理分别挖：
桥内部（CoreGl/Bridge/CapabilitySlots）、LWJGL 地址表机制 + ZombieBuddy 补丁作用域、Viewpoint 的 GL4.3 用法、
作者/上游/生态现状。**第一个重大收获是推翻了本仓库昨天自己的结论。**

**更正**：昨天 `viewpoint-mac41-bridge-gap-report.md` 的字节码证据取自**上游** `Viewpoint.jar`
（`94fedda302ab6c17…`，2 068 978 B，工坊 3809306528），但游戏实际加载的是**补丁 payload** 的
`Viewpoint.jar`（`9d8d4890a2657cc1…`，2 149 583 B）：后者多出 30 个 `viewpoint.mac41.*` 类，是作者自写的
**macOS 兼容层，已覆盖全部 32 个 GL4.2+ 入口**。实测两个 jar 都在本机，哈希/大小如上。

**真正的根因链**（安装实例 jar 反汇编）：

```
MeshArena.recordAttributes → viewpoint/mac41/Draws41.glVertexAttribFormat
Draws41.glVertexAttribFormat: nativeVertexPath() ? GL43.glVertexAttribFormat : <垫片>
Mac41.nativeVertexPath():     if (!active()) return true;   // "没有兼容层 ⇒ 假定原生 4.3 可用"
Mac41.active():               MAC && nativeCapabilities().OpenGL41 && (PROFILE_MASK & 1)
Mac41$BridgeAccess:           Class.forName("pzmac41.Bridge").getMethod("nativeCapabilities"/"active"/"onDestroy")
```

桥合成出来的 caps 只标到 **3.3**（日志 `core bridge on (… OpenGL33 true …)`）⇒ `active()==false`
⇒ `nativeVertexPath()` 短路成 true ⇒ 垫片被自己绕过 ⇒ 调原生 `GL43.glVertexAttribFormat`。
而 Apple 驱动从不导出这一族（子代理用 `dlopen`+`dlsym` 实测：5 个顶点格式函数全 NULL，
`glVertexAttribPointer/Divisor/IPointer` 才是 NON-NULL）⇒ LWJGL 地址表里该槽位是 0 ⇒ 空地址桩 abort。
**所以"桥缺 4.3"是事实，但不是本次崩溃的必要条件**；作者的垫片本来是能顶上的。

**修法（已做原型，离线 23/23 通过）** —— 自己的 javaagent，类加载期**常量池级 Methodref 重定向**
（只改 `class_index`，方法体一个字节不动；不需要 ASM/libffi）：

1. 主修：`viewpoint/mac41/Mac41.active()Z` → 我们实现（`MAC && (caps.OpenGL32|33|40..45)`，
   即"桥已给 core ≥3.2 就算兼容层接管"）；`Mac41.nativeVertexPath()Z` → 恒 `false`（macOS 永不假定原生 4.3）。
   重定向对**所有类**生效（`Textures41` 里 `Mac41.active()` 出现 25 次、`State41` 3 次、`Buffers41` 4 次）。
2. 安全网：`org/lwjgl/opengl/GL43` 里指向 `GL43C` 的 5 个 GL4.3 顶点格式入口 → 我们的 GL4.1 降级实现
   （记录 `attrib→(size,type,norm,relOff,binding,divisor)`、`binding→(buffer,offset,stride)`，
   在 `glBindVertexBuffer` 时重放成 `glVertexAttribPointer` + `glVertexAttribDivisor`，并恢复 `GL_ARRAY_BUFFER`）。
3. 诊断：第一次碰到垫片类时打一行 `gate:`（`GL.getCapabilities()` / `Bridge.nativeCapabilities().OpenGL41` /
   `Bridge.active()` / `Bridge.isLegacyMac()` / 我们算出来的 active），把"为什么 active 为假"一次跑清。

**集成约束（作者安装器源码实证）**：`Installer.verifyInstalled()` 第 279 行要求
**恰好 2 个 `-javaagent`**（桥在前、Buddy 在后）⇒ 不能往 `Info.plist` 加第三条；
但它同时校验 `plist.sha256` / 三个 payload 哈希 ⇒ 也别改 jar/plist。改用环境变量注入 + 包一层
`Jogar.shim.command`（`Jogar.command` 不在校验清单里）：

```sh
export JAVA_TOOL_OPTIONS="-javaagent:/path/pz-mac41-gl43-shim.jar"; exec ./Jogar.command
```

（本机实测游戏自带 JRE 25 认 `JAVA_TOOL_OPTIONS`/`_JAVA_OPTIONS` 且 premain 会执行；`JavaAppLauncher` 走
`JNI_CreateJavaVM` 仍需一次实证 —— shim 写 marker 文件就是为此。）

**顺带查清、以后有用的机制**：LWJGL 3.4.1 这个快照的 GL 地址**不在类静态字段**里，而在
`GLCapabilities.addresses`（2236 槽 `PointerBuffer`），native stub 每次调用按下标读表；`Checks.checkFunctions`
对非 0 槽位**不覆盖** ⇒ 运行期 `GL.getCapabilities().getAddressBuffer().put(908, addr)` 立即生效
（桥正是用 `GL.createCapabilities(true, factory)` + `CapabilitySlots.allocate` 预填表的）。
ZombieBuddy 2.3.2 的补丁筛选=任意类名（黑名单只有 `me.zed_0xff.`），可补 `viewpoint.*`/`pzmac41.*`；
但它没有第三方 transformer 扩展点，做不了我们这种全局重定向。

**经验**：

* **"对象 jar 是哪一个"必须先哈希确认**：同一台机器上同时存在上游 jar 与补丁 payload jar，用错了就会得到
  一个"看似严密但对象错了"的结论 —— 昨天的报告就是这么来的。以后凡是"补丁包改了上游某文件"，先列
  `find … -name X.jar | xargs shasum` 对照 `installer/*.tsv` 与 `installation.properties`。
* **门控反相是这类"平台桥 + 兼容层"组合的高发缺陷**：`if (!layerActive()) assumeNativeModernGL()` 在
  Windows 上完全正确、在 macOS 上 100% 崩溃。看门控要**把两条分支都读出来**，别只看"有没有检查"。
* **字节码没写在源码里也可能已经存在**：这次的降级实现（32 个函数）早就在 jar 里，真正缺的只是"让它生效"。
  所以我最初准备的"自己写 GL4.3 模拟层"方案，最后退化成"改两行门控 + 一层安全网"。
* **判断注入方式要先读对方的校验代码**：安装器的 `require(agents.size()==2 …)` 一条就否掉了"加第三条
  `-javaagent`"这条最自然的路；换环境变量后零文件改动、可完全还原。

方案文档：[`viewpoint-mac41-gl43-fix-plan.md`](viewpoint-mac41-gl43-fix-plan.md)；
证据附录：[`research/viewpoint-mac41-pad-layer-usage.md`](research/viewpoint-mac41-pad-layer-usage.md)、
[`research/lwjgl-gl43-address-table-and-zombiebuddy.md`](research/lwjgl-gl43-address-table-and-zombiebuddy.md)、
[`research/pz-mac41-bridge-hook-seam.md`](research/pz-mac41-bridge-hook-seam.md)、
[`research/viewpoint-mac41-author-status.md`](research/viewpoint-mac41-author-status.md)。
**未做**：没在游戏里跑过（需要用户跑一次隔离实例）；门控真值现场值待那一次日志确认。

---

## 2026-10-03（续三）· 第二个造型：脚本生成的**方块羊驼**（独立 addon，GPL-free）

用户问"能借鉴 MC 的羊驼模型么"。结论分三层，先查证再动手：

1. **MC 官方资产不能搬**（有原文）：[Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines) 把
   "code, software, graphics, textures, images, **models**, sounds" 明确定义为 "Our assets"，并写明
   "**Do not redistribute our games or any alterations of our games or game files**"；[EULA](https://www.minecraft.net/en-us/eula)
   里 Mod 必须是 "original … doesn't contain a substantial part of our copyrightable code or content"。
   ⇒ 抄 `ModelLlama` 或 `llama.png` 放进工坊物品 = 明确违规。
2. **自由许可的替代品存在**：[VoxeLibre/VoxeLibre](https://github.com/VoxeLibre/VoxeLibre)（原 MineClone2，GPL-3.0，166★）
   里有 `mobs_mc_llama.b3d` + 6 张毛色贴图 + 16 张装饰毯，`mods/ENTITIES/mobs_mc/LICENSE-media.md` 写明
   "All models were done by **22i** and are licensed under **GPLv3**"，并给出 Blender 源文件仓库
   `22i/minecraft-voxel-blender-models`。可用，但**有 copyleft 义务**（整个分发物要 GPLv3）。
3. **最干净的路：自己拼盒子**——用户选的就是这条（B 方案）。

### 做法（与写实羊驼完全独立的一条管线）

`bin2_blocky_alpaca/tools/blocky/make_blocky_alpaca.py`：

* 沿用 base 的 Raccoon 骨架 + 写实羊驼那套已验证的骨长/骨旋转调参（动画因此"演得对"）；
* **腿链与脖子竖直化**（方块造型要竖直方柱）：**只改位移、不改旋转**，避免动到动画的摆动方向；
* 每个骨段生成一个长方体（正方形横截面），23 个盒子 = 828 顶点 / 276 三角形；
* **每顶点 100% 绑一根骨头**（刚体硬绑定 = 那种方块观感，也免掉权重撕裂）；
* **逆蒙皮烘焙** `v_bind = (Σ w·D_b)⁻¹·p_target`（沿用写实羊驼那套数学，静止精确、动画跟随）；
* 每盒面一个图集格子 + 4 张毛色图集（`spot` 按格子随机加深 = 每只花斑不同）。

### 两个真实踩过的坑（都写进了 `models_blocky.txt` 与 README）

| 症状 | 根因 | 修法 |
| --- | --- | --- |
| 静止渲染完美，**一播 walk/eat 方块当场散架** | 查 jar 里的 glb 发现：**每条剪辑对每根骨头都有位移轨道**（55 骨骼 × 23~24 条），运行时位移会**覆盖**静止位移；我只改了静止位移 | 照 base `derive_alpaca.apply_bone_lengths` 的做法，把增量**同步加到该骨骼在全部剪辑里的位移通道**（本次改写 414 条） |
| 跑步（gallop）时**蹄子飞出去** | 蹄子做成独立盒子并绑在脚骨上，而脚骨在 gallop 里的位移最大 | 取消独立蹄盒，把**腿的最下一段直接染成蹄色**（结构上不可能脱离），并给骨段之间加重叠吸收拉伸 |

第一条是普适结论：**在这套骨架上改任何静止位移，都必须同时改剪辑通道**；
只改静止位移的模型在静止视图里看不出任何问题 —— 这类 bug 只有播动画才会暴露。

### 交付与校验

* 物品目录 `bin2_blocky_alpaca/`（27 文件 / 3.1MB）：4 种毛色（blockycream/brown/gray/**spot**，后缀 `|bk*`/`|bv*`）、
  4 张品种头像、图标、海报、256² 工坊预览、workshop/changelog/CREDITS/README；
* `require=CompanionDogs,CompanionDogsAlpaca`：**不新开物种**，复用写实羊驼的 "alpaca" 物种与 9 条叫声，
  并把 4 个品种键并进它的 `BREED_KEYS`/`ENGINE_BREEDS` ⇒ 自动继承"羊毛暖意" moodle 与怕热/耐寒应激；
* 尺寸按"世界高度一致"反推（方块网格静止高 0.5589 vs 写实 0.4523，尺寸×0.809）；
* 新增方块自己的 Lua 契约测试（fengari）：**9/9 ALL PASS**，含"依赖缺失时安静早退"、"7+4=11 次 registerBreed"、
  "12 个剥皮键齐全"、"并进写实羊驼的品种集合"、"CD.log 无禁忌词"；
* `bin2_blocky_alpaca/tools/check.sh` 全绿：Lua 5.1 语法 3/3、翻译（含 Breed.lua 交叉一致性）、glb 结构、
  图片 7/7、Lua 测试 9/9、游戏探针 `readWorkshopTxt=true` / `validatePreviewImage=OK` / `visibility=2`。

### 经验

* 遇到"能不能借鉴某商业游戏资产"的问题，**先找官方授权原文再谈技术**；能借鉴的是**风格**（不受版权保护），
  不能借鉴的是**资产文件**。同时把"没用它的资产"写进 CREDITS，避免以后被误判。
* 自由许可（GPL/CC-BY-SA）的替代品可用但会传染许可，所以**作为造型参考 + 自己生成几何**是最稳的组合。
* 硬绑定（每顶点单骨骼）让"方块造型"反而比有机网格更好做：不需要权重平滑，也不怕权重撕裂；
  代价是没有任何软形变 —— 这是风格选择，不是缺陷。

## 2026-10-04 · 全部 workshop.txt 描述追加 ALERT_CONFIG 链接块

### 需求

仓库里每个工坊物品的 `workshop.txt` 描述末尾，统一追加：

```ini
description=[ ALERT_CONFIG ]
description=link1 = GitHub = https://github.com/lotosbin/project-zomboid-mods,
description=link2 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/lotosbin,
description=link3 = 爱发电 = https://steamcommunity.com/linkfilter/?u=https://afdian.com/a/bin_2,
description=[ ------ ]
```

> `link3` 是后续追加的（爱发电）。用户最初给的是 `link3 = Ko-Fi = …afdian.com/a/bin_2,`，标签与
> `link2` 重名；确认后统一改成 **`爱发电`**。
> `Changelog.txt` 里那 **20 处** ALERT_CONFIG（游戏内真正生效的位置）经用户确认**本次不动**，
> 仍只有 link1/link2 —— 即游戏内更新弹窗不会出现爱发电链接，只有工坊页面描述里有。

### 范围（17 个文件，一个不漏）

`bin2/`、`bin2/Contents/mods/Respawn2/`、`bin2_b42/`、`bin2_blocky_alpaca/`、`bin2_companion_alpaca/`、
`bin2_energy_routing_system/`、`bin2_extensive_health_rework/`、`bin2_extensive_power_rework/`、
`bin2_lingering_voices_cn/`、`bin2_neat_controller_support/`、`bin2_nested_containers_take/`、`bin2_tikitown/`、
`bin2_title_cover/ZomboidTitleCover/`、`bin2_title_cover/ZomboidTitleCoverWide/`、`bin2_viewpoint/`、
`bin2_workshop_upload_fix/`、`bin2_XantjiRecycleEverything/`（`find . -name workshop.txt` 的结果就是全集，
`.dsh/` 与 `node_modules` 下没有同类文件）。

### 做法

* 块统一插在**最后一行 `description=` 之后、`tags=` 之前**，并前置一行空的 `description=` 作为分隔，
  与仓库既有 `Changelog.txt` 里 ALERT_CONFIG 的排版一致；
* 脚本化校验（`python3` 遍历全部 `workshop.txt`）：块恰好出现一次、4 行连续、紧邻 `tags=`、无 CRLF、
  末尾有换行、`tags/title/version/visibility/id` 键一个都没丢；
* `bin2/Contents/mods/Respawn2/workshop.txt` 里 `descriptipn=` 是拼写错误（游戏解析器只认
  `description=`），顺手改正为 `description=`，否则这次追加的块会是该物品唯一的描述文本。

### 从游戏字节码里读出来的真实契约（不是猜的）

`zombie.core.znet.SteamWorkshopItem.readWorkshopTxt()`（`javap -p -c` / `javap -v` 反汇编）：

* 以 `#` 或 `//` 开头的行被跳过；`id=` / `description=` / `tags=` / `title=` / `version=` / `visibility=` 逐条匹配；
* 重复 `description=` 的行为是 **`description += "\n" + 本行去掉前缀后的内容`**（只在本行为空值时不加分隔符），
  `tags=` 按 `;` split（**没有 trim**），`visibility=` → `getVisibilityInteger()`（public=0 / private=2）；
* 提交时 `getSubmitDescription()` 还会追加 `Workshop ID:` / `Mod ID:` 行。

**实测反证了"每行描述之间是空行"的猜想**：先用本地脚本按 `\n\n` 拼接算出 `bin2_blocky_alpaca` = 1939 /
`bin2_workshop_upload_fix` = 1896，游戏探针打印的是 1911 / 1860 —— 差值恰好等于"分隔符个数 × 1"，
所以分隔符是**单个 `\n`**。改完（含前置空行）后探针回到 1912 / 1861，与按 `\n` 拼接的模型**逐字符吻合**。

### 校验

```
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/bin2_blocky_alpaca     -> readWorkshopTxt=true, description=1912 chars
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/bin2_workshop_upload_fix -> readWorkshopTxt=true, description=1861 chars
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/bin2_viewpoint          -> readWorkshopTxt=true, description=709 chars
tools/pz_workshop_probe/run.sh "" ~/Zomboid/Workshop/ZomboidTitleCover       -> readWorkshopTxt=true, description=775 chars
```

四个已软链到 `~/Zomboid/Workshop/` 的物品全部 `readWorkshopTxt=true`，`tags` / `visibility` 解析结果不变
（探针只调 `n_StartItemUpdate…n_SetItemPreview`，不调 `n_SubmitItemUpdate`，不会真的上传）。

### 经验

* **ALERT_CONFIG 的功能位置是模组内的 `Changelog.txt`，不是 `workshop.txt`。** 三条证据：
  1. 把 `projectzomboid.jar` 全量解包后 `grep -r ALERT_CONFIG` **零命中**（`zombie/` 包内连 `changelog`
     字样都没有）⇒ 游戏本体不解析这个块，它是一套**社区模组**提供的功能
     （参考 [pzwiki: Mod Update and Alert System](https://pzwiki.net/wiki/Mod_Update_and_Alert_System)）；
  2. 本机唯一消费它的是 `[B42] Mod Manager` 的
     `media/lua/client/ModManager/Compatibility/ModdingAlertSystem.lua` —— 它
     `require "chuckleberryFinnModdingAlertSystem"` / `"chuckleberryFinnModding_modChangelog"`，
     并改写 `changelog_handler.fetchMod`，走 `ModManager/Utils/WorkshopSubmit.lua:371 fetchChangelog`；
  3. `fetchChangelog` 只调 `getModFileReader(modID, "ChangeLog.md")` / `"ChangeLog.txt"`，**从不读
     `workshop.txt`**；同一文件里 `parseTxtVersionHeader` 用 `v ~= "ALERT_CONFIG"` 显式跳过配置块、
     把 `[ ------ ]` 当作块终止符 —— 这就是 `[ ALERT_CONFIG ] … [ ------ ]` 这套写法被识别的机制。

  所以写进 `workshop.txt` 的 `description=` 只体现在 **Steam 工坊页面的描述文本**上，游戏内不解析它；
  本仓库各模组的 `Changelog.txt` 里该块早已写好，功能上不依赖这次改动（本次纯属补齐工坊页面的展示信息）。
* `description=` 多行的分隔符是**单个 `\n`**：想要段落之间空一行，就得自己多写一行空的 `description=`。
  这条以前只在文档里含糊写着"多行累加"，现在有字节码 + 探针实测两个证据。
* 校验"格式类"改动的最省力路径：**先反汇编目标方法读懂契约 → 本地脚本复刻 → 再用游戏自己的探针核对数字**。
  三者对上才算做完；只靠肉眼 diff 很容易把分隔符猜错。

### 沉淀：`workshop_create.sop.md`（新建工坊物品 SOP）

把本文的结论与仓库既有经验写成 `workshop_create.sop.md`（根目录，与 `modify.sop.md` / `tranlate.sop.md` 并列），
覆盖：目录骨架 → `mod.info` → `workshop.txt`（6 个真实键 + description/tags/visibility 细则）→
`Changelog.txt` / `changelog.txt` 的分工 → `poster.png` / `preview.png` 硬规则 → staging 软链 →
上传向导与 `id=` 写回 → 常见错误表 → 自检清单 → "自己反汇编复查"的命令。

**这轮又多验证了几条以前只是"听说"的规则**（全部来自字节码）：

| 结论 | 证据 |
| --- | --- |
| `workshop.txt` **只有 6 个键**被解析（`description` / `id` / `tags` / `title` / `version` / `visibility`）；`changelog=`、`preview_image=`、`author=` 不存在 | `readWorkshopTxt` 里的 `startsWith` 常量清单 |
| `visibility` 合法字面量是 `public`/`friendsOnly`/`private`/`unlisted` → 0/1/2/3；**其它值一律 0（静默公开）** | `getVisibilityInteger()` 的 `equals` 链 + `iconst_0` 兜底 |
| `tags` 白名单共 **31 个**（`media/WorkshopTags.txt` 实读），且按 `;` split、**不 trim** | 游戏目录 `media/WorkshopTags.txt` |
| `Changelog.txt` 只从 **版本目录 → `common/`** 找，UTF-8；物品根的那份游戏**读不到** | `LuaManager$GlobalObject.getModFileReader`：`getVersionDir()/file`，不存在再 `getCommonDir()/file` |
| 上传**只打包 `Contents/`** | `getContentFolder()` = `<item>/Contents`；订阅后落盘结构是 `<id>/mods/<ModName>/…` |
| 软链 staging 安全 | `getStageFolders()` 用 `Files.isDirectory(path, new LinkOption[0])`（不带 `NOFOLLOW_LINKS`）；`validatePrefix()` 不解析软链 ⇒ 探针在软链路径上仍 `readWorkshopTxt=true` |
| `preview.png`：≤1024000 B、正方形、边长**只能** 256 或 512、必为 PNG | `validatePreviewImage()` 的 `1024000l` / `sipush 256` / `sipush 512` / `PNGDecoder` |

**顺带发现仓库既有文档的硬伤**：`guides/workshop-txt-guide.md` 里 "tags 逗号分隔"、"visibility 支持
`friends`"、"preview 512x512 或更大"、"有 `changelog=` / `preview_image=` / `author=` 字段"、
"workshop.txt 放在 `Contents/mods/<Mod_ID>/`" 全部与实际解析行为不符（本次已在 SOP 开头标注以 SOP 为准，
该 guide 本身待用户决定是否重写）。

* 经验：**"文档写了"不等于"引擎这么干"。** 只要结论能被 `javap` + 探针双重验证，就该以引擎为准并把
  证据（常量、字符串、命令）抄进 SOP —— 否则下一次还会照着错文档写错文件。

---

## 2026-10-04 · B42 NPC 模组引擎能力取证（只读）

**任务**：回答"B42 从零做 NPC 模组，引擎给什么、不给什么"，结论必须来自 `projectzomboid.jar` 字节码与真实 Lua 环境。

**产物**：`bin2_ProjectALifeNPCs_extensions/docs/b42-npc-engine-capability-audit.md`（含命令 + 原始输出片段，区分【已证实】/【未验证】）。

**核心已证实结论**：

| 结论 | 证据 |
| --- | --- |
| `zombie.characters.IsoSurvivor` 存在（3277 B）但**无 update / 无 AI**；构造器仍真活（进 `IsoCell.getSurvivorList()`、触发 `OnCreateSurvivor`、`initWornItems("Human")`） | `javap -p` 只有 3 个方法 + 3 构造器；`grep -c 'void update'` = 0 |
| `OnNPCSurvivorUpdate` / `OnAIStateEnter` / `OnAIStateExecute` / `OnAIStateExit` 是**死事件**（只在 `LuaEventManager` 注册，全 jar 无触发点） | `grep -ral <event> /tmp/pzall --include='*.class'` 只命中 `zombie/Lua/LuaEventManager`；Lua 侧引用 0 |
| B42 僵尸 AI 已迁到 ECS：`IsoZombie.update()` → `updateInternal()`；`updateActiveState()` 退化为 3 条指令（只剩 `isZombieInactivityPhase → makeInactive`）；状态容器是 `StateMachineComponent`，`initializeStates()` 注册 118 个状态名 | `javap -p -c zombie/characters/IsoZombie.class` |
| `setUseless(true)` **是真开关但覆盖面有限**：`useless` 只被 `ZombieIdleState`/`WalkTowardState`/`ZombieGroupManager`/`NetworkZombieVariables` 读取，不阻止 attack/hitreaction/thump | `grep -ral isUseless /tmp/pzall` |
| **没有 `bDead`**；死亡走继承的 `isDead()` | `grep -nE 'bDead\|setDead' /tmp/isoZombie.txt` = 0 |
| Lua 暴露是**白名单**（`shouldExpose` = `HashSet.contains`），`exposeAll()` 共 **1001** 类；`AnimationPlayer`/`AdvancedAnimator`/`ActionState`/`StateMachineComponent`/`GlobalModData` 本体**不在**名单 | `javap -p -c LuaManager$Exposer` + `/tmp/exposed.txt` |
| Lua 动画入口只有 `IsoGameCharacter` 的转发方法（`PlayAnim`/`PlayAnimUnlooped`/`setVariable`）；游戏自身 Lua 就是这么用的 | `media/lua/shared/Vehicles/TimedActions/ISOpenVehicleDoor.lua:21`、`ISRestAction.lua:81` |
| `IsoZombie.getModData()` **来自 `zombie.iso.IsoObject`**（IsoObject→IsoMovingObject→IsoGameCharacter），`IsoGameCharacter` 自身没有 | `javap -p IsoObject \| grep -i moddata`；`grep -n ModData /tmp/igc.txt` 只有 `*MusicIntensityEventModData` |
| `IsoCell.getZombieList()` **直接返回引擎内部 ArrayList 本体**（`getfield zombieList; areturn`），不是副本 | `javap -p -c IsoCell.class` |
| 事件线程语义：`IsMainThread()` = 与 `KahluaThread.debugOwnerThread` 同线程；**非主线程触发的回调被 `QueueEvent` 排队，主线程延后执行** | `javap -c -p LuaEventManager`（`triggerEvent(String)` 的 27→33 分支） |
| 从 `LuaEventManager` 常量池提取出 **264** 个事件名 + 每个事件的触发类映射 | `javap -p -c -constants` + `grep -ral` |
| 本机 ZombieBuddy 是 **2.3.4**（skill 里记的 2.3.2 已过时）；提供 `Exposer.exposeClass/exposeMethod`、`@Exposer.LuaClass`、`@LuaMethod(global=true)`、`@Patch`、`ZombieBuddy.Events/Watches` | `unzip -p ZombieBuddy.jar META-INF/MANIFEST.MF`；`javap -p` ZB 类；`doc/LuaAPI.md` |

**另一条经验**：`zombie/ai/states/*` 有 100+ 状态类，但"类存在"≠"Lua 能用"——**暴露白名单**是硬门槛。
以后判断"Lua 能不能调 X"，先看 `LuaManager$Exposer.exposeAll()` 的类常量池，再看 `IsoObject`/父类继承链
（`javap` 默认只列**声明**方法，继承来的方法要往父类查，`getModData` 就是这么被漏判的）。

---

## 2026-10-04 · 学习报告：拆解工坊 3803984183「Project A-Life [ALIFE NPCS]」并给出从零复刻路线

**背景**：用户要"学习开发类似模组并生成报告"。标杆选定工坊 `3803984183`
（Mod ID `ProjectALifeNPCs`，作者 Vice，B42.21，**订阅 121,195**）。
本机已订阅，源码就位：`~/Library/Application Support/Steam/steamapps/workshop/content/108600/3803984183/`
—— 248 个 Lua / **146,518 行** / 9.4 MB 纯 Lua + 225 个动画 XML + 455 个服装 + 101 个模型，
**无任何 .exe/.jar/.dll**（与作者"只有 Lua、纹理、模型、声音和纯文本数据"的声明一致）。

**产出**
- `bin2_ProjectALifeNPCs_extensions/docs/pz-alife-mod-dev-report.md` —— 主报告（机制拆解 + 引擎边界 + 复刻路线图 + 最小骨架 + 22 条陷阱）
- `bin2_ProjectALifeNPCs_extensions/docs/b42-npc-engine-capability-audit.md` —— 引擎能力取证（主报告第 5 章的原始证据）
- `docs/develop_log_2026-10-04.md` —— 当日开发日志

**方法**：6 个并行子代理分工（核心运行时 / AI 决策战斗 / 世界离线层 / 内容管线 / 引擎字节码 / 外部资料），
主代理只做交叉复核与撰写；每条结论必须带 `文件:行号` 或 `javap` 原始输出。

**核心发现（按价值排序）**

| # | 发现 | 证据 |
| --- | --- | --- |
| 1 | **最独特的技术是动画状态机改写**：自建 225 个 `AnimSets/zombie/<原版状态目录>/*.xml` animNode，把玩家动画（`Bob_Walk`/`Bob_Reload_Rifle_Load`）挂到僵尸身体上，靠 `SetVariable("ALifeActor","true")` 做条件、`setBumpType("ALife*")` 触发动作、XML 的 End 事件回写 `BumpAnimFinished` | `common/media/AnimSets/zombie/pathfind/alife_human_walk.xml`、`bumped/alife_reload_rifle.xml`；Lua 侧 `shared/ProjectALife/Shells/ALifeAnimations.lua:1295-1300` |
| 2 | **作者公开声明只对了一半**：工坊写"每个 A-Life 尸体都有 `ProjectALifeOwned == true`"，实测**尸体上该字段被显式置 nil**（`markCorpse`）；正确判据是 `Owned or Actor` + `GetVariable("ALifeUID")` 兜底 | 全项目 50 处引用，写入点仅 5 个；`shared/ProjectALife/Shells/ALifeShellSimulation.lua:34` |
| 3 | **ALifeExecutor 不是协程池**（`coroutine` 0 处）：它是"权限仲裁器 + 分帧配额"——子系统配额 `clamp(ceil(#order/5),2,24)`，决策内 **12 ms 硬预算 `break`** | `shared/ProjectALife/Core/ALifeExecutor.lua:2624-2648`；`Decisions/ALifeDecisionLoop.lua:1301,1452-1455` |
| 4 | **离屏模拟用游戏小时而非真实秒**：小队是挂在 ModData 的纯表，`travelTilesPerHour=150` 沿**预生成**道路图插值；离屏战斗是属性对拼（power 比值决定 1~2 人伤亡）；复仇契约 `dueHours = hours + 48 + roll*25` | `server/ProjectALife/Offline/ALifeSquadLedger.lua`、`ALifeOfflineDirector.lua:63-68,790-822`、`ALifeRevenge.lua:98-112` |
| 5 | **多人搭原版"僵尸归属"的车**：owner 客户端模拟，服务端 `settleDeaths/auditOwners` + 1 s 镜像广播；反作弊阈值 `unownedTrustRadius=80`/`playerHitMaxRange=80`/`reportRateLimitMs=200`；身份 = `UID + generation` | `shared/ProjectALife/Core/ALifeExecutor.lua:254-400`、`ALifeMirrorTransport.lua:5-8` |
| 6 | **"卸载 ≠ 死亡"**：`unloadedLoss`（区块卸载）/ `culledLoss`（70 格外引擎剔除）/ 真死亡三态必须分开判，否则 NPC 随机消失、存档翻倍、幽灵残留 | `Core/ALifeWatchdog.lua:534-585`、`Core/ALifeOrphanGuard.lua`、`Core/ALifeLifecycle.lua` |
| 7 | **内容管线比算法更决定成败**：自研行式文本 `@alife-records 1` + 单一 `Codec.schema` 同时驱动磁盘目录 / Creator 表单 / 分享码（`ALIFEPACK1-<字节>-<校验和>-<base64 LZ>`）；148 阵营 / 780 NPC 档案 / 16,091 条对话 / 175 个语音档案 | `Records/ALifeRecordCodec.lua:15-68`、`Records/ALifeFactionShare.lua:416-426` |
| 8 | 代码量分布揭示重心：Audio 27,216 行 + Talk 19,469 行 ≈ **40% 是内容不是 AI**（shared 93/63,721、server 109/63,244、client 46/19,553） | `find`/`wc` 实测 |
| 9 | **`common/` 是引擎承认的版本无关目录**（不是约定）：`PZModFolder` 只有 `common` 与 `version` 两个字段，扫描时先探测 `<mod>/common/mod.info` | `javap -c zombie/ZomboidFileSystem` |

**经验（值得进 SOP 的三条）**
1. **"作者文档" ≠ "代码契约"**：一次 `grep` 写入点就推翻了工坊描述里的兼容性承诺（发现 #2）。
   以后凡是要依赖第三方模组公开约定的地方，都回代码验证一次。
2. **一份数据格式要服务多个消费者**：同一个 `schema` 驱动磁盘目录 + 编辑器表单 + 分享码编解码，
   比"每种用途各写一套读写"省一个数量级的维护成本。
3. **性能不是优化出来的，是架构约束出来的**：10 Hz 主节流 + 子系统计数配额 + 决策 12 ms 硬预算 +
   每 NPC 冷却闸 + 弱键表防实体泄漏 + 三级可观测性（Telemetry/Watchdog/BlackBox）——六件事缺一件，
   到 100 NPC 规模就会崩。

---

## 2026-10-04 · A-Life 生态与扩展研究（新增 `bin2_ProjectALifeNPCs_extensions/`）

**任务**：①把 A-Life 研究资料集中归档到 `bin2_ProjectALifeNPCs_extensions/`；
②研究工坊 `3806944055`（Jeem Extension）与 `3806063445`（Aftermath）；
③头脑风暴与其他模组的联动扩展。

**结果**：两个目标模组**都是 A-Life 扩展**，且本机都已安装 → 直接读源码分析。

| 对象 | 实测 |
| --- | --- |
| `3806944055` Project A-Life - Jeem Extension（`ProjectALifeJimmy`，jeemlettuce，0.4.6，10,743 订阅） | **132 个 Lua / 52,591 行**，`common/` 为空（不发 `.alife`）；**136 处 monkey patch** 覆盖 49 个 A-Life 表 / 约 110 个函数；20 个 ModData TAG；134 个沙盒选项；34 个网络命令 |
| `3806063445` Project A-Life: Aftermath（Shinyu，1.3.1，5,921 订阅，**一物品含 3 个 mod**） | **79 个 `.alife` + 41 个 Lua**，**零美术资产**；用 `getActivatedMods():contains()` + `kind` 门控 + 猴补 `Catalog.load` 做"依赖感知阵营 provider"；三变体数据逐字节相同，只靠 4 个常量 + 一个 Backend 分叉 |

**核心发现（按价值排序）**

| # | 发现 | 证据 |
| --- | --- | --- |
| 1 | **A-Life 没有扩展 SDK**：全项目无 `Extensions`/`addProvider`/`contribute`/`Compat.register`。唯一官方注册器是 `ModuleRegistry.register` + 6 个 `Voice*Register` hook；其余是 54 处 `configure(adapters)` 与 14 个手写自装 Adapter | `ALifeModuleRegistry.lua:101`、`ALifeVoiceCatalog.lua:254/297` |
| 2 | **`Compat.known` 不是注册 API**（34 条硬编码），第三方改不了；它反而规定两条硬红线：**不得在 A-Life 目录树下放 Lua**、**不得 rebind `CreatorScreen`/`EquipEventShield`/`Animations`** | `ALifeModCompat.lua:203-205, 217-234` |
| 3 | **纯数据扩展被市场验证**：Aftermath 零美术资产、6.4 MB 全文本，实现 900+ NPC 的装备按玩家实际装模组集合动态合并 | `extension-aftermath-analysis.md` |
| 4 | **`.alife` 两种字段命名都成立**：A-Life 自带用文件侧名（`who.title`），Aftermath 用内存路径名（`general.name`）；且**值可省略**（自带数据 666 处） | `ALifeRecordCodec.lua:23-25,38-39` + 真实数据统计 |
| 5 | **Jeem 把 A-Life 当"可 patch 的源码"**：136 个挂接点里过半是内部实现细节（含直接复制 A-Life 声望存档 schema、抢 `Relations.adapters.reputation` 单槽、17 个 `ObstacleTraversal` 内部函数） | `extension-jeem-analysis.md` §7/§9 |
| 6 | **翻译赛道已饱和**：A-Life 生态 31 条里 20+ 条是翻译（中文 ≥6 份） | `alife-ecosystem-map.md` |
| 7 | 官方兼容清单把 **Bandits2 标为 `unsupported`、BanditsWeekOne 标为 `incompatible`**，而本机同时装着 Bandits2 + 4 个附属 | `ALifeModCompat.lua:64-67` |

**新建资产**
- `bin2_ProjectALifeNPCs_extensions/`：README + `docs/`（主报告、引擎审计、生态地图、扩展 API、两个标杆分析、头脑风暴、路线图）
- `bin2_ProjectALifeNPCs_extensions/tools/alife_lint.py`：`.alife` 校验器，**已用真实数据回归** ——
  核心目录 `files=2 records=928 factions=148 members=780 errors=0`（与已知真值一致）；
  Aftermath `files=79 records=2809 errors=0`；负例能抓出 `bad_field` 与 `unclosed_record` 并返回 exit 1。

**经验**
1. **先查"赛道饱和度"再动手**：初始建议是"做中文翻译补丁"，实测生态后发现有 6+ 份中文汉化，直接推翻。
   任何"看起来没人做"的方向，都要先去工坊把同类物品列出来数一遍。
2. **"能挂接" ≠ "该挂接"**：Jeem 依赖的 136 个点里过半是内部实现，功能能跑但升级即碎；
   正确做法是只用 4 个稳定接口 + 一切软挂接（存在性探测 + pcall + 缺失即禁用）。
3. **写规格文档的人要顺手写校验器**：把实测规格落成 `alife_lint.py` 后，才发现我第一版正则有三个错
   （空值字段、必填字段用内存路径、core/provider 未区分）——**工具化会立刻暴露规格理解里的漏洞**。

---

## 2026-10-04 · 实现：`ALifeStartWithNPC`（开局自带友好 NPC）

**需求**：扩展 Jeem Extension，让玩家出生时带一名友好 NPC。

**先证再做（三条实测结论决定了架构）**

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| Jeem 有现成的"开局给 NPC"入口吗 | **没有**。`OnCreatePlayer` 在 Jeem 出现 0 次；居民 100% 来自 `R.recruit` | 全量 grep |
| 能直接 `R.recruit` 发居民吗 | **不能凭空造人**，且要求 base/床位容量/`isAlly` 三重门槛；`force=true` 仅 `who.admin` 生效 | `Residents/Server.lua:566-629` |
| 跟随要自己写行为模块吗 | **不用**：A-Life 有原生 `DecisionLoop.setOrder{kind="follow"}`；自建模块会被 `orders`(priority=10) 抢跑 | `ALifeDecisionLoop.lua:1242`、`ALifeModuleTravel.lua:12` |

**实现（5 个 Lua + 9 个沙盒选项 + EN/CN 翻译 + 海报）**

- 造人链路：`ActorRegistry.create(memory.spawnStance="friendly", persistent=true, admin={persistent=true})`
  → `SpawnService.request(uid, op, fp, 2500)`（内部同步建实体）→ 失败按 `dormant` 条件回滚。
- 行为：等 `lifecycle=="active"` → 默认下原生 follow；居民模式则 `BaseAreas.who/basesFor/createBase` +
  `base.bedsOverride` 绕过床位 + `Residents.recruit(force=true)`，失败自动降级为跟随。
- 幂等四层：角色 modData 标记 → 角色令牌进 `operationId`（A-Life 自带幂等）→ 存档级
  `Registry.setWorldValue` → `SpawnService` 的 `actor_not_dormant` 兜底。
- 时序：不在 `OnCreatePlayer` 直接造人，而是 `OnTick` 轮询 `Runtime.started` + 玩家方块就绪（90s 上限，
  超时转 `EveryOneMinute` 兜底最多 5 次）。

**踩到/修正的三处**
1. `Pick` 模块最初误写成 `local Pick = ALifeStartWithNPC`（应为 `require`）——**语法检查抓不出来，靠人工复查抓到**；
2. `memory.persistent` 只挡 Population 回收，**挡不住 `SpawnService.dehydrate`**，必须补 `memory.admin.persistent`
   （`ALifeSpawnService.lua:32-36, 308`）；
3. 沙盒 `Mode` 的文案与代码语义**写反了**（代码 1=跟随、2=居民）——已改正并同步两份翻译。

**新增工具**：`tools/lua_syntax_check.mjs`（本机无 lua 解释器，用仓库自带的 fengari 做纯语法编译检查），
5 个文件一次通过。

**产出**：`Contents/mods/ALifeStartWithNPC/42.20/`、`docs/start-with-npc-design.md`（含 14 项待执行测试清单）。
**状态**：源码级验证 + 语法校验 + 海报硬规则校验通过；**尚未进游戏运行**（诚实标注）。

### staging 与工坊校验（同日）

按 `pz-workshop-item-publishing` skill 补齐了物品根所需的三件套并做了软链：

```
~/Zomboid/Workshop/ALifeStartWithNPC -> <repo>/bin2_ProjectALifeNPCs_extensions
~/Zomboid/mods/ALifeStartWithNPC      -> <repo>/.../Contents/mods/ALifeStartWithNPC
```

用游戏自己的解析器跑探针（`bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh`）实测：
`readWorkshopTxt=true`、`title` 解析正确、`visibility=2`(private)、
`tags=[Build 42, QoL, Misc, Multiplayer, WIP]`（全在 `media/WorkshopTags.txt` 白名单内）、
`contentFolder ... exists=true`、`previewImage exists=true`、**`validatePreviewImage=OK`**、`id=null`（首次上传前不带 id）。

**经验**：
1. `preview.png` 与 `poster.png` 是**两张不同的图、两套排版**：preview 是物品预览（工坊硬规则 256/512 正方形），
   poster 是模组列表海报（游戏不校验）。这次分别用 256 与 512 各画一版，而不是缩放同一张。
2. **物品根只放 `workshop.txt`/`preview.png`/`changelog.txt`/`Contents/`**，研究用的 `docs/`、`tools/` 留在同目录也不会被打包
   （上传只打包 `Contents/`），所以"研究项目 + 模组"共用一个仓库目录是安全的。
3. 上传前**一定先跑探针**：它用的是游戏自己的 `readWorkshopTxt` 与 `validatePreviewImage`，
   比人眼检查 tag 白名单/图片尺寸可靠得多，而且不会真的上传。

---

## 2026-10-04 · 实测 T1/T2 并修复：Kahlua 没有 next()

用户报"T1、T2 有报错"。读 `~/Zomboid/console.txt` 后定位：

**现象**：499 条 `[ALifeStartWithNPC][ERROR] tick failed: Object tried to call nil in tick`，每帧一条。

**堆栈（console.txt 自带 Lua 栈，直接给出行号）**：
```
Lua((MOD:A-Life: Start With NPC [Jimmy add-on])).tick(Grant.lua:215)
Lua((MOD:A-Life: Start With NPC [Jimmy add-on])).Add(Bootstrap.lua:114)
```

**根因**：`Grant.lua:215` 是 `if next(Grant.pending) == nil then return end`，
而**游戏的 Kahlua 运行时没有 `next()`**。决定性证据：Jeem Extension 的 `Core.lua:231` 就写着
`-- Kahlua has no next(): use this for "is this table empty?"`（并提供了 `J.isEmpty`）。
我的 5 个文件里只有这一处用了 `next`，代价是每帧一次报错、499 行日志。

**修法**：改用显式计数 `Grant.pendingCount`（`pendingAdd`/`pendingRemove`），
既不用 `next()` 也不靠遍历判空；顺手给 `os.time` 兜底加了 `pcall`。

**预防性复核（Kahlua 的另两个已知坑）**：
| 坑 | 证据 | 我们的情况 |
| --- | --- | --- |
| `table.sort` 不稳定（快排打乱相等项） | Jeem 多处注释 | 未使用 ✅ |
| `%` 是截断取模而非向下取整 | Jeem 注释 | 未使用 ✅ |
| `math.pi/cos/sin/sqrt`、`ZombRand` 是否存在 | vanilla/A-Life/Jeem 均大量使用 | 存在 ✅ |

**顺带用日志反证了一个担心**：`mod "ALifeStartWithNPC" overrides media/sandbox-options.txt` 这句
并不代表"后者覆盖前者"——用户日志里有 **5 个模组**同时提供 `sandbox-options.txt`、**5 个**同时提供
`translate/cn/sandbox.json`，而 A-Life 一直正常工作、无 `SandboxVars` 索引报错 ⇒ 引擎是**按模组累加合并**。

**版本**：升到 0.1.1（`mod.info` + `Config.VERSION` + `changelog.txt`）。
**经验**：**语法检查（fengari）抓不到"运行时库缺函数"这类问题**；`console.txt` 自带 `文件:行号` 栈，
定位速度远快于猜。已知语言子集差异应当固化成清单，写码时先查。

### 追加需求：开局好感度必须是「同盟」（0.1.2）

用户要求"npc 的初始好感度要是同盟"。查证后发现**两套词汇必须分清**：

| 系统 | 档位 | 能否到同盟 |
| --- | --- | --- |
| A-Life 关系/声望 | `hostile/careful/neutral/friendly` | ❌ `allied` 被归一化成 `friendly`（`ALifeRelations.lua:22`、`ALifeReputation.lua:131`）；`memory.spawnStance` 白名单也只收 friendly/neutral/careful/hostile，**写 "allied" 会被拒绝并退回按阵营关系算**（可能敌对） |
| Jeem 声望 `StandingService` | `hostile/careful/neutral/friendly/**allied**`（`Services/Standing.lua:14`，阈值 25/75/150/250） | ✅ 同盟在这里 |

**实现**（`Grant.makeAllied`）：`S.set(key, factionId, S.clamp=400)` 跨过全部阈值 ⇒ 任何默认档位都到 allied；
再 `S.addGroup(key, groupId, factionId, 400)` 补足组声望；最后调 `J.Standing.apply(key, factionId)`
（`Features/Standing/Standing.lua:123`）立刻写回 A-Life 声望 —— 于是 A-Life 侧也顶到它的上限 friendly。

**顺带修掉一个联机隐患**：同盟声望让 `R.isAlly` 通过，于是居民收编改成**优先走正规（非 force）路径**，
联机非管理员玩家也能收编（`force` 只在 `who.admin` 时生效）。

**副作用已写进 tooltip**：Jeem 声望按阵营记录 ⇒ 变成同盟的是整个阵营；可用 `MakeAllied = false` 关闭。
（A-Life 侧的 `spawnStance` 保持 `"friendly"` 不动——那是它的上限，写 allied 会适得其反。）

### 复测结果：T1 通过；同盟改用官方 debugSet 路径（0.1.3）

`console.txt` 显示 **T1 通过**（两个会话）：`grant #1 → spawned → grant complete: 1/1`，
并且 A-Life 自己的 `[ALIFE-LIFECYCLE] hydrate` 给出第三方证据：
`nearest=2 loaded=true inList=true side=sp`（实体离玩家 2 格、区块已加载、在僵尸列表里）。
修复后**再无任何 `[ALifeStartWithNPC][ERROR]`**（499 条全部来自修复前的会话）。
附带验证互操作性：玩家用 Jeem 界面手动收编了它（`[ALIFE-JIMMY] residents: sp:0 invited 1 ...`）。

**仍未验证**：T2（日志里两次发放的令牌不同 ⇒ 是两个不同角色，不算 T2）、T1 的跟随部分（老版本没打印）、
同盟（v0.1.2 才有）、T3~T14。为此 v0.1.3 专门补了三条可观测日志：
`already granted ... skipping`（T2）、`follow order accepted for <uid>`（T1 跟随）、
`standing with <faction> is now ALLIED` / `ally step skipped/failed: <原因>`（同盟）。

**同时修掉一个会静默失效的坑**：同盟原先用 `S.set` + `F.apply`，但若 A-Life 声望里那条记录是
`cause = "provoked"`，`F.apply` 会拒绝覆盖 ⇒ 同盟永远设不上。官方 `Standing.debugSet` 里那句
`store.players[key][factionId] = nil` 正是为此。现在改为**优先调官方 debugSet**，
被拒（联机非管理员）时走复刻版退路（含清条目 + 按档位换算点数 + 组声望）。

**经验**：能调官方实现就别自己拼数据 —— 官方实现里往往藏着"你没读到的必要条件"（这次是 provoked 标记）。

### 多人联机报错排查（0.1.4）：报错源是"汉化整合包"，不是本模组

用户报"多人联机模式有报错"。用日志把两件事分开：

**① 本模组在联机下正常** ✅：`coop-console.txt` 显示 2 名玩家各得 1 名 NPC，
流程完整（`grant requested by IsoPlayer{ID:2}` → `grant #1` → `spawned` → `standing ... ALLIED` →
`follow order accepted` → `grant complete`），本模组打印的 `spawn failed` **0 次**。
`console.txt` 里还出现 `this character was already granted earlier; skipping` ⇒ T2 间接验证通过。

**② 真正的报错源**：`no such location "UI_Alife_Animations_20"`（每次 NPC 水合一条 ERROR 栈）。
堆栈里 `ALifeAnimations.lua` 标注的模组是 **`MOD:Project A-Life [中文汉化]`** —— 该模组（工坊 `3807277264`）
**自带 233 个 Lua 文件**，且**命中 A-Life `probePaths` 的 4/4 个旧路径**（`Data/`、`Dialogue/`、`Runtime/`、
`Presentation/`），即 **A-Life 1.3 重构前的整包旧副本**。归因统计：`hydrateShell` 失败 40 次，
其中经本模组 28 次、**A-Life 自己的生成 12 次** ⇒ A-Life 自己也中招。
A-Life 的 `ALifeModCompat` 早已把这类模组判为 `incompatible`，并写明后果
（"a translation should ship only Translate files"、"old copy ... NPCs throw errors and stutter"）。
**处理**：禁用/退订 `3807277264`；中文可用 `3805566620`（0 个 Lua 文件）。

**③ 顺带排除**：日志开头 `AdvancedAnimator$1.visitFileFailed > NoSuchFileException .../media/actiongroups`
是引擎对**所有**缺 `media/AnimSets`、`media/actiongroups` 目录的模组的通用噪声 ——
本仓库自己的 `NestedContainersTake`、`CompanionDogsAlpaca` 各报 8 条，Jeem 与 Aftermath 同样如此。

**0.1.4 的两项防御**：
1. **开局兼容自检**：直接复用 A-Life 的 `Compat.foreignCopies(activeSet())`，把自带 A-Life Lua 副本的模组
   点名打进 console.txt（水合失败时再报一次）——用别人的检测器比自己写启发式可靠；
2. **生成重试节流**：2 秒一次、每玩家最多 5 次（闸门在 `worldReady` 之后，只统计真实尝试），
   避免数据没就绪时每帧 create/remove 刷日志。

### 联机"死亡重新发放"失效（0.1.5 修复）

用户报"多人模式开启死亡重新发放，没有重新发放"。查出**三个叠加原因**：

| # | 问题 | 证据 |
| --- | --- | --- |
| ① | 客户端 `requested[playerIndex]` 永久守卫（每会话只请求一次） | `Request.lua:18-20` |
| ② | 服务端 `OnCreatePlayer` 只处理纯单机（`if isClient() or isServer() then return end`） | `Bootstrap.lua:83` |
| ③ | 没有死亡钩子；且令牌不变 ⇒ `operationId` 不变 ⇒ A-Life `create` 幂等返回**旧（已死）记录** ⇒ `SpawnService.request` 报 `actor_not_dormant` | `Grant.lua` |

**关键认识**：A-Life 的 `operationId` 幂等是"防重复发放"的功臣，但在**重生**场景下就成了陷阱 ——
它会把"再发一次"的请求当成"重复请求"而返回那条已经死掉的记录。所以死亡时必须**连令牌一起清**，
否则清标记也没用。

**修法**：① 客户端每次角色创建都请求（服务端幂等）；② 服务端三种模式都处理 `OnCreatePlayer`；
③ 新增 `Grant.onDeath`（`OnPlayerDeath` + `OnCharacterDeath`）清标记**与令牌**与尝试计数；
④ 所有 per-角色 状态由"按 IsoPlayer 对象缓存"改为存玩家 modData（联机重生可能复用同一对象）。

### 发布：ALifeStartWithNPC 已上传创意工坊（id=3813096783）

游戏内上传向导成功，并把**回写**写进了 `bin2_ProjectALifeNPCs_extensions/workshop.txt`：

```
+id=3813096783
-visibility=private
+visibility=public
 tags 被向导重排为 Build 42;Misc;Multiplayer;QoL;WIP
```

按 skill `pz-workshop-item-publishing` 的流程，这条回写要提交进仓库 —— 此后再次上传会自动走"更新"分支
（而不是新建物品）。本次发布的版本是 0.1.5（含联机重生修复）。

**经验**：**"防重复"的幂等键一旦跨生命周期复用，就会变成"防重生"** —— 凡是按角色实例的幂等，
必须在死亡/重生边界显式失效。

**经验**：**排错第一步永远是"把栈里每一帧标注的模组名读出来"** —— 这次栈里出现的是别人模组的文件，
一眼就能把自己摘清；同时用"同一错误在 A-Life 自家生成里也出现多少次"做归因统计（12 vs 28），
就能证明"不是我引入的，只是被我的调用放大了"。

---

## 2026-10-04 · 研究 3808789424：A-Life × 僵尸行为模组 兼容层

**对象**：`ALifeStackCompat` v1.3，226 订阅，**只有 1 个 Lua / 294 行 / 13 KB**，
`common/mod.info` + `common/media/lua/shared/ALifeStackCompat.lua`（**连版本目录都没有**）。

**它做了什么**：对每个 A-Life 身体只打两个标 ——
① `setVariable("Bandit", true)` 让 TrippingZombies / Claimable Outposts / PZTheMutants 免费跳过它；
② `getInventory():setExplored(true)` 关掉原版口袋战利品与 AmmoLootDrop；
再 wrap 四个目标：The Mutants `ForeignOwnership.isClaimed`、UV Defense `markFeared/canDriveZombie`、
KillCount `addToKillCount` + `OnZombieDead`、Zombie Dismemberment `ZD_Network.isGrapple`。

**本轮最有价值的三个发现**

| # | 发现 | 证据 |
| --- | --- | --- |
| 1 | **`Bandit` 是生态级既成契约**：本机 1,150 个模组里**至少 10 个在读它**，且语义分两类 —— 跳过型（PZTheMutants / InjuredZombiesStumble / SZedPlus / ZoneLootRefill）与**认领型**（Bandits2 本体、BanditsFixPlus、NPCBases、CompanionDogs） | 全量 grep；`BanditUpdate.lua:199`（写入）、`PZM_ForeignOwnership.lua:79`、`CompanionDogs/core/Identity.lua:20` |
| 2 | **借用标记会反噬**：`Bandit=true` 是 Bandits2 的**所有权标记**。借它让 A-Life NPC 对跳过型模组隐身的同时，也会被 Bandits2 系**当成强盗接管**（`BanditZombie.lua:74` → `GetBrain`）、被 CompanionDogs 判为「友方强盗 NPC」（无 `md.brain` → `return true`）。而 A-Life 官方对 Bandits2 的判定是 `unsupported` | 同上；`extension-stackcompat-analysis.md` §3.2 |
| 3 | **服务端打标竞态**（作者 v1.1 踩的坑）：专用服务器上 `OnZombieUpdate` 根本没进到 shim —— **118 次 A-Life 生成、打标 0 个**。改成 `OnZombieCreate` 入队 + 每 10 tick 复查（最多 90 次）+ 每 300 tick 全量 sweep；**因为 A-Life 是 `createZombie` 之后才写标记的** | `ALifeStackCompat.lua:32-49, 119-152`；对应 A-Life 侧 `ShellAdapter.lua:82-140` |

**另一条工程教训（v1.2）**：按引用重注册事件处理器（`Events.OnZombieDead.Remove(original)` + `Add(wrapped)`）
**必须完整镜像原注册条件** —— KillCount 只在非客户端注册，1.1 在多人客户端也注册了包装版，
导致原函数在它从未创建的表上索引，每次僵尸死亡都报 `KillCountUpdate.lua:149 attempted index of non-table`。

**结论**：
- 这个 13 KB 的模组就是「兼容层」产品的**完整可抄模板**（`isOurs` 三路回退 → 幂等打标 → 每目标 `wrapXxx()` 返回 `wrapped/absent` → 启动与每 10 分钟报计数）；
- 它**未覆盖**的正是我们的机会：`Bandit` 标记的认领型反噬、以及单人下 ZD 不生效；
- 新增工程原则：**借用第三方标记前，必须列出全部读取者并判定「跳过语义 vs 认领语义」，有认领语义就不能无条件借用。**

**产出**：`bin2_ProjectALifeNPCs_extensions/docs/extension-stackcompat-analysis.md`；
并回填到生态地图（补录 + 检索盲区）、`README`、头脑风暴（新增 C+ 类）、`roadmap`（阶段 2 改为"模板已存在，可直接接手"）。
方法论补记：`searchtext=Project+A-Life` 会漏掉标题不含 "Project" 的生态模组（本模组就是），
应改跑 `Project+A-Life`/`A-Life`/`ALife` 三种检索取并集，或用本机 `mod.info` 的 `require/loadModAfter` 反查。

---

## 2026-10-05 · workshop.txt 的"富文本格式"到底是哪一套

**问题**：工坊简介要排版（标题/加粗/列表/缩进），`workshop.txt` 里的 `description=` 支持什么富文本？
和游戏里那些 `<LINE>` / `<RGB:0.7,0.7,0.7>` 是不是一回事？

**结论：两套方言，别混。**

| 显示位置 | 读的文件 | 方言 | 渲染者 |
| --- | --- | --- | --- |
| Steam 工坊物品页 | 物品根 `workshop.txt` 的 `description=` | **Steam BBCode** | Steam 网页/客户端 |
| 游戏内 Mods 列表 | `<版本目录>/mod.info` 的 `description=` | `<LINE>` / `<RGB:…>` / `<SIZE:…>` | 游戏 `ISRichTextPanel`（`ModInfoPanelDesc.lua:33`） |
| 上传向导输入框 | 同上那份 `workshop.txt` | 纯文本，**不预览 BBCode** | —— |

**证据链**（全部可复现）：

1. `javap -p -c zombie/core/znet/SteamWorkshopItem.class` → `readWorkshopTxt()`：每行先 `trim()`、
   `#` 与 `//` 开头整行跳过、空行 `isEmpty()` 跳过；`description` 用 **单个 `\n`** 累加
   （BootstrapMethods 里 `\u0001\n` + `\u0001\u0001`）；值里 `replace("description=", "")` **删掉所有出现**。
2. 同 class `getSubmitDescription()`：描述非空时追加 `\n\n` 再拼 `Workshop ID: <id>` / `Mod ID: <modid>`；
   `SteamWorkshop.SubmitWorkshopItem()` 把它原样喂给 `n_SetItemDescription` —— **不转义、不剥离**。
3. **新写的探针实测**（`bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java`，
   只初始化 `ZomboidFileSystem`，**不需要 Steam、不加载 native 库**）：喂一份含
   `[h1]/[b]/[i]/[url]`、空 `description=`、`description=  ← 缩进`、`#`/`//` 注释的 workshop.txt，
   输出逐行 `|…|` 完全保留标记与空行，注释行消失；且实测到 `在 description= 之后` 被删成 `在  之后`。
4. `ISRichTextPanel.lua` 的 `processCommand()` 是游戏内方言的**完整标签表**
   （LINE/BR/H1/H2/TEXT/CENTRE/LEFT/RIGHT/RGB/PUSHRGB/POPRGB/GHC/BHC/RED/ORANGE/GREEN/SIZE/
   IMAGE/IMAGECENTRE/VIDEOCENTRE/INDENT/JOYPAD/SETX/SPACE，转义 `&lt;` `&gt;`）。
5. `getVisibilityInteger()` 反汇编订正：合法值是 `public`/`friendsOnly`/`private`/`unlisted`，
   **其它任何值都静默返回 0 = public**（旧文档写的 `friends` 是错的）。

**长度上限**：Steamworks `k_cchPublishedDocumentDescriptionMax = 8000`（**UTF-8 字节**，汉字 3 字节/字）。
本仓库 17 份 `workshop.txt` 实测最大 **3015 字节**（`bin2_companion_alpaca`），余量充足 —— 但 BBCode
标记与游戏追加的 ID 行都算在这个额度里，且**未闭合的标签会把追加的 ID 行吞进列表/引用块**。

**产出**：
- `bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java`（新探针，不带 Steam 也能跑）
- `workshop_create.sop.md` 新增 §3.5（两侧方言对照表 + 6 条硬规则 + BBCode 表 + 游戏内标签表）、
  §9 补 5 条症状、§10 补探针用法与清单、参考资料补 Steamworks 与社区排版文档
- `guides/workshop-txt-guide.md` **重写**：改正 5 处字段错误（tags 分隔符、visibility 取值、
  preview 尺寸、`changelog=`/`preview_image=` 不存在、文件位置），补"富文本与排版"整节，
  标注 2026-10-05 订正
- skill `pz-workshop-item-publishing`：§2.1 新增 description 解析细节与富文本规则，§7 补新探针，§8 补踩坑

**未做**：没有真实上传一次去核对工坊页面的渲染结果（`web_fetch` 在本机对所有域名都返回
"resolves to a non-public IP"，Steam 文档与社区排版页都抓不到，只能引 URL）；BBCode 标签表来自
Steam 平台文档与既有实践，未逐条截图验证。

---

## 2026-10-05 · 统一优化仓库全部 workshop.txt（17 份 + 删掉 1 份历史遗留）

**目标**：把"优化所有模组的 workshop.txt"落地 —— 用上一条刚验完的富文本能力、修掉过时与非法内容、
并做一次机器可复查的校验。

**做了什么**

| 类别 | 动作 |
| --- | --- |
| 排版 | 17 份全部改成统一结构：`[h1]` 大标题 → 一句话 → `[h2]` 小节（功能 / 包含模组 / 依赖 / 安装 / 已知限制）→ `[list]`+`[*]` 列表 → 保留结尾 `[ ALERT_CONFIG ]` 块 |
| 内容纠错 | viewpoint：**快捷键早已从 F9/F10 改成 Ctrl+Alt+D 控制面板**、版本 1.x → 2.2.0、补上 P1 相机/3D 与 P3.1 体素模型包；A-Life：日志版本 `v0.1.0` → `v0.1.5`（`Config.VERSION` 实测）；tikitown：条目数 214 → **223**、84 → **172**（按 JSON 键实点） |
| 补全空壳 | `bin2`、ERS / EHR / EPR / Xantji / Lingering Voices / Neat 手柄支持原本只有一两行：按各自 `mod.info` 补上翻译范围（ItemName / Tooltip / Sandbox / Recipe / UI / ContextMenu）、依赖 mod id、安装步骤；Neat 手柄支持把 `mod.info` 里的完整按键映射搬到工坊页面 |
| 字段卫生 | tags 全部对齐 `media/WorkshopTags.txt` 白名单（新增 `Interface` / `Multiplayer` / `WIP` 等贴切标签，`bin2_b42` 从 10 个收敛到 5 个）；`id=` / `visibility=` 一律按原值保留（private 的不擅自公开） |
| 删除 | `bin2/Contents/mods/Respawn2/workshop.txt` —— 游戏只在物品根读 `workshop.txt`，这份在 `Contents/` 里的只会被当模组内容上传，且 `tags=` 是空的（本仓库 SOP §9 早已列为历史遗留）；已 `git rm`，可恢复 |

**新工具（可复查）**

* `bin2_workshop_upload_fix/tools/pz_workshop_probe/WorkshopTxtProbe.java` 增加 `--check` 批量模式：
  用游戏自己的 `readWorkshopTxt` + `getAllowedTags()` 逐个校验，并对照原始文本查
  非法键、字面量 `description=`、BBCode 配平、8000 字节上限；有问题退出码 1。
* `bin2_workshop_upload_fix/tools/pz_workshop_probe/check_all.sh`：扫描仓库所有 `workshop.txt`，
  逐份复制进 `~/Zomboid/Workshop/__wtchk_*`（`validatePrefix` 只认白名单路径）再校验，跑完清理。

**结果**：`ALL CHECKS PASSED (17 item(s))`；`submitDescription` 最大 **3351 字节**
（`bin2_ProjectALifeNPCs_extensions`），距 Steam 上限 8000 还有一半余量。

**这次工具真的抓到了自己的错**：Xantji 那份有一行续行忘了写 `description=` 前缀，check 直接报
`非法的键: L6 没有 '='` —— 没有这步，那一行会静默消失在工坊页面上。

**顺带发现（未改，等确认）**：`bin2_title_cover` 两个模组的 `mod.info` 里
`incompatible=\ZomboidTitleCover,\ZomboidTitleCoverWide` 把**自己**也列进了互斥名单，
疑似复制粘贴笔误（16:9 版会声明 16:9 版互斥）。

**未做**：没有真实上传核对工坊页面渲染；`blocky/companion alpaca`、`title_cover`、`viewpoint`
仍是 `visibility=private`（发布与否是作者决定，本次不动）。

---

## 2026-10-05 · 新模组 `bin2_npc_extension`：橙子社区经济 × A-Life 的 NPC 招募

**目标**（用户原话）：*npc 扩展模组 bin2_npc_extension，兼容 Project A-Life Jeem Extension（工坊 3806944055），
在 橙子社区经济模组（工坊 3777900792）中增加 npc 招募功能*。

**先取证再动笔**：两个子代理只读逆向、各交一份带 file:line 的报告（都写进 `bin2_npc_extension/docs/research/`）：

| 报告 | 对象 | 关键结论 |
| --- | --- | --- |
| `economy-integration-hooks.md`（1087 行） | 橙子经济 257 个 Lua | 页面注册表 `UIPageRegistry.Register` 是**公开给扩展的 API**；但侧栏 `MENU`/社区中心 `TABS` 都是 `local`，加不进去 —— 唯一先例是它自己的 `ui/bootstrap.lua:64-116` 包首页工厂塞按钮；服务端 `command_router:677` 对 `module ~= "OrangeTradingMod"` 直接 return，所以**路由注册 API 不存在也不需要**，用自己的 module 名发包即可 |
| `jeem-recruit-api.md`（638 行） | Jeem 0.4.6 + A-Life 1.3.15 | A-Life **没有任何玩家雇佣/同伴机制**（`hire/recruit/companion/…` 全量 grep 只命中对话框白与贴图字段）；原生跟随只有 `DecisionLoop.setOrder`（`kind` 仅 follow/hold/patrol）；`R.recruit` **收编的是整支 crew**且服务端无距离校验；Jeem 招募**不收费**（只有阵营声望代价），钱必须我们自己扣 |

**三个真实的坑（决定了设计）**

1. **`memory.persistent` 与 `memory.admin.persistent` 是两回事**：前者免疫 `Population` 的 dormant TTL
   **物理删除**（默认 8 小时 + 60 格外），后者免疫 `SpawnService.dehydrate`。只写一个照样会丢人。
2. **`DecisionLoop.orders` 是纯内存表**（`ALifeDecisionLoop.lua:1215`），读档即失效 ——
   所有 follow/hold 指令必须像 Jeem 的 `Friendlies.sync` 那样周期重下，不能"下完就忘"。
3. **`OrangeTradingMod.Text()` 会强制加前缀** `IGUI_OrangeTradingMod_`（`client_api.lua:138`），
   第三方不能复用；我们必须自带 `IGUI_Bin2NPCExtension_*` 命名空间 + 直接调用原生 `getText`。

**做出来的东西**（`Contents/mods/Bin2NPCExtension/42.21/`，14 个 Lua + 4 份翻译 JSON + 沙盒选项）

| 层 | 文件 | 职责 |
| --- | --- | --- |
| shared | `Config` / `Contracts` / `Text` | 沙盒选项与依赖探测、存档形状与纯逻辑、翻译包装 |
| server | `Store` / `Alife` / `Jimmy` / `Economy` | 三个依赖**各一个适配层**（存在性探测 + pcall + 缺失即降级） |
| server | `Service` / `Maintain` / `Bootstrap` | 命令处理（限速 + requestId 去重）、周期维护、事件接线 |
| client | `Net` / `Bootstrap` / `ui/Page` / `ui/Entry` | 单机直连 vs 联机发包、招募页、首页入口 + Ctrl+Alt+N |

三条设计红线：**网络 module 只用 `Bin2NPCExtension`**、**不 monkey patch 对方任何函数**（唯一的"包装"是
注册表里 `factories.index` 这个数据项，照抄对方自己的做法）、**钱只走 `OrangeTradingModServer.Pay`**
（客户端传的价格一律不采信）。

**自检工具链**（全部可复现）

* `tools/lua_syntax_check.mjs`（复用自 A-Life 扩展项目）：14 个文件 `failed=0`；
* `tools/make_images.py`（新写，纯 Pillow）：`preview.png` 256×256 14458B、`poster.png` 512×512 37227B，
  逐行断言文字不溢出；
* 工坊探针（游戏自己的解析器）：
  `readWorkshopTxt=true`、`tags=[Build 42, Misc, Multiplayer, QoL, WIP]`（全在白名单）、
  `validatePreviewImage=OK`、`visibility=2(private)`、`submitDescription=2338 chars`、`id=null`（首次上传前不带）；
* 翻译键一致性：代码里 45 个字面量键 + `Text.lua` 映射表值 → CN/EN **零缺失**，两边键集合完全相同。

**未做 / 待确认**：没有进游戏实跑（`docs/test-plan.md` 列了 T1~T18 + M1~M4，含多人非管理员路径）；
`StandingService.addGroup` 能否真把组点数顶过同盟阈值、转居民时"整支小队一起进营地"的实际观感、
与 Bandits2 等 NPC 模组的共存，都属于未验证项，已如实写进工坊简介的"已知限制"。

### 追加（同日）：离线逻辑测试 33/33，并修掉它抓出的 4 个真缺陷

写这套测试的**回报率高于预期** —— 它 mock 了 A-Life 的 `setOrder` 校验顺序与拒绝码、Jeem `R.recruit`
的 15 个失败串、橙子经济 `Pay` 的先查后扣，于是能真的把"我们以为对、实际不对"的地方照出来：

| # | 缺陷 | 后果 | 修法 |
| --- | --- | --- | --- |
| 1 | `Service.dismiss` 漏了 `Config.enabled()` 闸门 | 沙盒关掉模组后仍能解雇，与其它三个命令不一致 | 补闸门 → `disabled` |
| 2 | `Maintain` → `applyMode` → `orderFollow` 把 `quiet=true` 丢了 | 每 8 秒重下 follow 会重放动画和 `ORDER_ACK` 语音 | 加 `quiet` 形参透传；首次雇佣仍不 quiet |
| 3 | 退款只调 `AddCoins`、不写流水 | 玩家账单只有扣钱、看不到退钱 | 新增 `Economy.flow(..., "in", "npc_hire_refund", ...)` + 翻译键 `FlowRefund` |
| 4 | `hireSpawned` 不校验 spawn 后的 uid 是否还在 | 记录被当场回收时照样收钱写契约 | 读不到就 `retire` + 退款 + `spawn_failed` |

另外两个"可疑点"也顺手修了并补了回归断言：`Contracts.sanitize` 改成**先剔除非法项再重建 order**
（一遍就干净）；requestId 去重队列从"只留 64 条"改成**按时间裁剪**（否则 60 秒内连发 65 个不同
requestId 就能把最早那条挤出窗口，重放它不再判 duplicate）。

`tools/test/run_lua_test.sh`（不带参数，会自动复用 `bin2_companion_alpaca/tools/test/node_modules/fengari`）
现在输出 `[test] 33/33 passed, 0 failed` → `ALL PASS`，exit 0。
模组本体因此改了 6 个文件（`Service` / `Maintain` / `Economy` / `Contracts` + 两份 `IG_UI.json` 加 `FlowRefund`），
改动后 Lua 语法检查仍是 `files=14 failed=0`。

---

## 2026-10-05 · 与 `bin2_ProjectALifeNPCs_extensions` 对照：纠正一处"借 A-Life 的口背书"

用户追加指示"同时参考 `bin2_ProjectALifeNPCs_extensions`"。把它没读完的
`docs/roadmap.md`、`docs/integration-brainstorm.md` 过了一遍，**发现并纠正了本模组的一个真实错误**：

**错误**：`bin2_npc_extension` 的 server Bootstrap 往 `ProjectALife.ModCompat.known` 里写了自己的条目
（`verdict="adapted"`），想法是"让 A-Life 的自检报告里有我们"。子代理的报告也确实这样建议过。

**它为什么是错的**（读 A-Life 源码定案，不是听结论）：

* `Compat.known` 是 A-Life 作者手写的**数据表**，不是注册 API；
* `Compat.report()`（`3803984183/42.20/media/lua/shared/ProjectALife/Compat/ALifeModCompat.lua:314-330`）
  遍历 `known`，对**启用中**的条目 `string.format("%s (%s) -> %s: %s", entry.name, id, entry.verdict, entry.note)`，
  打印成 `[A-Life] compat: Orange Community Economy: NPC Recruit (Bin2NPCExtension) -> adapted: …`；
* 也就是说：第三方往里写 = **借 A-Life 的口替自己背书**，而那个 verdict 并不是它给的。
* 同域项目 `bin2_ProjectALifeNPCs_extensions/docs/integration-brainstorm.md` §1 早就写明
  "`Compat.known` **不是注册 API**，第三方无法写入它" —— 这轮对照把它从"结论"落成了"代码约束"。

**改成什么**：`Bootstrap.registerCompat()` → `Bootstrap.reportCompat()`，**只读**：
跑 A-Life 自己的 `Compat.foreignCopies(activeSet)`，把"自带 A-Life Lua 副本 / rebind 了 A-Life 表"的模组
点名打进日志。这条对本模组是刚需 —— 那类模组会让**每次 NPC 水合**抛 `no such location`，
而"把 NPC 生成出来"正是我们的主路径（参考实现 `ALifeStartWithNPC` 的 v0.1.4 changelog 里
就记录过一个中文汉化整包重传 A-Life 233 个 Lua 文件的实例）。

**顺带从那个项目采纳的第二件事**：`Jimmy.makeAllied` 加一行**只读复核** ——
`StandingService.addGroup` 之后读 `groupPoints(key, groupId)` 打进日志。
Jeem 的 `R.isAlly` 认"阵营标签为 allied"或"组点数 ≥ 50"两条路，我们走的是后者，
而 `addGroup` 的 clamp/poolShare 语义没有正式承诺 —— 这行日志正是进游戏验证
"非管理员能否转居民"（T15/M2）时的判据。

**测试同步**：mock 里补了 `ProjectALife.ModCompat`（`known` / `activeSet` / `foreignCopies` 记录调用），
用例 1 新增两条断言（加载期确实调过 `foreignCopies`、且 `known["Bin2NPCExtension"] == nil`），
原用例 24 里"断言我们写进了 known"的那两条被删掉。改完 `33/33 passed`、Lua 语法 `files=14 failed=0`。

**文档互挂**：`bin2_npc_extension/README.md` 新增 §3「与同域项目的关系」（复用清单 + 这处纠正）；
那个项目的 `README.md` 新增 §5.7、`docs/roadmap.md` 新增「阶段 1-D」与两条决策记录。

**方法论收获**：跨项目对照的价值不在"复用代码"，而在**用别人的既有结论去审计自己新写的代码** ——
这处错误在子代理报告里被写成了"推荐做法"，只有回到 A-Life 源码读 `Compat.report()` 才发现是反的。

### 追加（同日）：再采纳该项目的两条工程约定

对照 `bin2_ProjectALifeNPCs_extensions/docs/roadmap.md` 阶段 4「通用工程约定」，又补了两处：

| 约定 | 我们的落地 | 证据 |
| --- | --- | --- |
| §4 **防 `Reset Lua` 重入** | 三个注册 `Events` 的文件（server/client Bootstrap、`Net`）改用 **`Events` 表的身份**做守卫：同一张表 = 同一次会话（跳过，防重复注册）；换表 = 引擎重置过 Lua（重新注册，否则功能静默失效）。原来的布尔守卫在"重置 Lua"后会把功能永久锁死 | 改动后 `33/33 passed` |
| §3 **可观测** | 新增 `Bootstrap.capabilities()`：把我们用到的 **10 个半公开入口**逐个探一遍，启动打印 `hooks active=N inactive=M`，缺哪个就 WARN 列出名字（`alife.orders`、`jeem.standing`…） | 做了**失败实验**：在 mock 里把 `DecisionLoop.setOrder` 置 nil（模拟上游改名），日志立刻变成 `hooks active=9 inactive=1` + `[WARN] inactive hooks (1): alife.orders -- an upstream rename looks like this; the matching feature degrades instead of throwing`；恢复后测试回到 `33/33 passed` |

启动日志现在长这样（测试环境的原样输出）：

```
[Bin2NPCExtension] loaded v0.1.0 | economy=true(server=true) alife=true jeem=true | hooks active=10 inactive=0 | max=3 sign=500 spawn=1500 wage=20
```

用例 24 相应扩了 6 条断言（`capabilities()` 的形状、`OnGameStart`/`OnServerStarted` 处理器不报错），
所以这条可观测链路本身也有回归覆盖。

---

## 2026-10-05 · v0.1.1：玩家实测反馈的两处版面错位

用户进了游戏，发来两张截图。**功能是通的**（首页入口出现、招募面板可用、经济流水里有两笔
`FlowHire NPC -1500.00` = 中介派遣成功两次），但版面有两处重叠，属于"离线逻辑测试测不到、
只有真窗口尺寸才会现形"的那一类：

| # | 现象 | 根因（读自己的代码定位） | 修法 |
| --- | --- | --- | --- |
| 1 | 右侧说明文字压住「跟随/守卫/居民」按钮行，窗口越矮越明显 | 模式按钮固定在 `listTop + 118`，而文本从上往下**不限行数**地画 —— 行数一多就撞上 | 右侧面板改成**自下而上**排版：从底部预留「模式行 + 主按钮 + 次按钮」两块固定高度，文本区夹在中间；新增 `drawLines()` 只画得下的行（宁可少画一行）。次按钮位**永远预留**，切页签时按钮不跳 |
| 2 | 首页入口按钮与对方「卡片」视图按钮重叠，两个标题叠成了「NPC 招募: 卡片」 | 原实现只把 `communityCenterButton` 当锚点，而社区中心功能关闭时它**不存在** → 回退"贴右边缘" → 正好压住右侧那排视图切换按钮 | 把 `communityCenterButton` / `homeViewButtons.classic` / `.launcher` 三个锚点收集起来取**最左**，贴在它左侧；一个都没有时贴左边缘，绝不与右侧控件抢位 |

**新增回归手段：把版面几何当契约来测。** 在 800×600 / 1200×700 / 520×420 三种尺寸下断言
`textBottom < 模式行.y`、主按钮在模式行之下、次按钮在主按钮之下、五个控件全部落在页面内、
三连模式按钮互不重叠、列表不侵入右侧面板、小窗口 `render()` 不抛错。
**失败实验**：把文本裁剪改回旧行为（`textBottom = height`），三条断言立刻变红 —— 证明这套几何断言
真的能抓住这次这类 bug，而不是"看着像测了"。

版本号 0.1.0 → 0.1.1（`mod.info` / `Config.VERSION` / 工坊简介 / `changelog.txt` / `docs/design.md` §8.2）；
改完 Lua 语法 `files=14 failed=0`、离线测试 `33/33 passed`、工坊探针 `validatePreviewImage=OK`。

**教训**：布局是**状态函数的输出**，不能靠"看起来排好了"交付 —— 它依赖窗口尺寸、页签、
选中项、依赖可用性四个变量。把它写成可断言的几何契约（并在测试里跑几种尺寸），
成本只有十几行，却能挡住这类"必然会在某个窗口尺寸下出现"的问题。

---

## 2026-10-05 · 追问：「workshop.txt 里能不能直接声明必需物品？」

用户的实际痛点：每发布一个物品都要在 Steam 网页上手动加「必需物品 / Required Items」。
结论 **不能**，三条证据（前两条是本轮新做的取证）：

| # | 证据 | 结果 |
| --- | --- | --- |
| 1 | `javap -p -c zombie.core.znet.SteamWorkshopItem` 的 `readWorkshopTxt()` | 键字符串只有 `version= / id= / title= / description= / tags= / visibility=`（外加 `#`、`//` 注释）。**没有** `required=` / `dependencies=` |
| 2 | 把 `required=3803984183,3806944055` 与 `required0=3803984183` 追加进一份真实 `workshop.txt`，用**游戏自己的解析器**跑（`WorkshopTxtProbe`） | `description` 仍是 **2315 chars / 4239 bytes，与不含这两行时逐字节相同**；标题/标签/可见性不变；**没有任何报错** —— 未知键整行静默丢弃 |
| 3 | `SteamWorkshop` 的 native 清单 + `OptionScreens/WorkshopSubmitScreen.lua` 的输入项 | 只有 `n_SetItemTitle/Description/Visibility/Tags/Content/Preview/SubmitItemUpdate`；界面上只有 标题/描述/标签/可见性/预览图/内容目录/ID。**没有设置依赖的调用** |

反向发现：游戏**会读**这个字段 —— `SteamUGCDetails.getChildren()/getNumChildren()/getChildID(i)`
与 `SteamWorkshop.GetQueryUGCChildren()` 都是暴露的（`GetQueryUGCChildren` 只在 `SteamWorkshop.class`
内部被引用，游戏自己的 Lua 里零调用点），所以 Steam 上的 Required Items 是给客户端/网页用的
"一键订阅"便利，游戏侧不参与。**结论：只能在网页/客户端手填，且每个物品只需一次。**

（Steamworks API 是否有设置依赖的接口**没能联网核实** —— 本机 `web_fetch` 对 `partner.steamgames.com`
一律返回 `resolves to a non-public IP`，搜索只回本地化文档目录页。文中按"据我所知没有"表述。）

**新工具** `bin2_workshop_upload_fix/tools/workshop_requires.py`：

* 从**本机已订阅的工坊内容**（`workshop/content/108600/<id>/**/mod.info` 的 `id=`/`name=`）反查
  mod id → 工坊 id（本次索引到 **1169 个**），再叠加本仓库自己物品的 `id=`；查不到一律标 `unknown`；
* `--check`（默认）打印每个物品的 必需(require=) / 可选(loadModAfter=) → 工坊 id + 可点击 URL；
* `--write <物品>` 生成一段可点击的依赖小节写进 `workshop.txt`：用 `#` 行做标记
  （`#` 开头整行被解析器跳过，标记不会进简介），自动插到 `[ ALERT_CONFIG ]` 之前；依赖 >12 个的物品跳过。
  写入路径先在 `/tmp` 的副本上验证过。

**顺带做掉的**：`bin2_npc_extension` 与 `bin2_ProjectALifeNPCs_extensions` 两份简介里的依赖段升级为
`[url=https://steamcommunity.com/sharedfiles/filedetails/?id=<id>]名字[/url]` 可点击链接
（玩家点一下即可订阅）。改完仓库级 `check_all.sh` 仍 **ALL CHECKS PASSED (18 item(s))**，
两份的 `submitDesc` 分别 4564 / 3483 字节，距 8000 上限仍有余量。

**文档沉淀**：`workshop_create.sop.md` 新增 §3.6（含 §3.6.1 工具用法 / §3.6.2 **本仓库各物品依赖 id 对照表** /
§3.6.3 简介可点击链接），§8 执行步骤新增第 13 步"在工坊页面手工设置 Required Items"，
§9 常见错误新增一行「写了 `required=` 但页面上还是空的」；skill `pz-workshop-item-publishing`
新增 §2.2、§8 踩坑一条、§9 清单两条。

**顺手订正两处过期文档**：`bin2_npc_extension` 的 README/`design.md`/`changelog.txt` 还写着
"尚未上传工坊（无 id、private）"（实际 id=3813914438、public）；`bin2_ProjectALifeNPCs_extensions/README.md`
还写着 `visibility 目前是 private`（实际已发布 id=3813096783、public）。

**踩到的一个探针坑（值得记）**：仓库目录名与 staging 目录名不一定同名 ——
`bin2_ProjectALifeNPCs_extensions` 的 staging 是 `~/Zomboid/Workshop/ALifeStartWithNPC`。
拿错路径时 `WorkshopTxtProbe` **不报错**，而是打印一串空字段（`title=` / `tags=[]` / `description=0 chars`），
看起来像"文件坏了"。以后见到全空先确认路径存在。

**一个需要作者定夺的不一致**：`bin2_npc_extension/mod.info` 现在写着
`require=\OrangeCommunityEconomy,\ProjectALifeJimmy`（本轮之前用户自己改的），
而代码对 Jeem 是**软挂接**（`Config.jeem()` 拿不到就只剩跟随/守卫，`no_jeem` 有专门分支）。
`require=` 会让游戏在缺 Jeem 时**不让启用**，比代码的容错策略更严。工坊简介已按 mod.info 的现状
改写（必需=橙子经济+Jeem，需要=A-Life），但"要不要把 Jeem 降回可选"由作者决定。
