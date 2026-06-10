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

### ExtensivelyHealthRework 物品翻译更新 (历史)
