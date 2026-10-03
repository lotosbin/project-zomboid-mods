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
ZombieBuddy `@Patch` 注解语义表 + 离线自测套路、改 jar 的整包重写纪律、工坊物品交付与
`validatePreviewImage` 硬性规则、以及一份交付前自检清单。

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
