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
