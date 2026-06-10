# Neo4j 合成树导入工具

> Project Zomboid 模组与配方合成图导入 Neo4j 数据库的完整工具链。
>
> 关联: [[../../docs/craft-recipe-study]] (B42 配方语法学习笔记)

## 概述

`mod_dependency_analyzer/` 是本仓库的 Neo4j 导入工具,用于:

1. 扫描仓库内所有 mod(`mod.info`)
2. 扫描所有 recipe 文件(B41 + B42 两种语法)
3. 加载中文翻译(ItemName / Recipe)
4. 导出为 **Neo4j CSV** 或 **Cypher 脚本**
5. 可选: 直接 push 到本地 Neo4j 实例

## 数据模型

### 节点类型

| 节点 | 必填属性 | 可选属性 | 唯一约束 |
|------|----------|----------|----------|
| `Mod` | `mod_id` | `name`, `version`, `author`, `pz_version`, `description` | mod_id |
| `Recipe` | `recipe_id` | `mod_id`, `syntax`, `time`, `timed_action`, `category`, `tags` | recipe_id |
| `Item` | `full_type` | `display_name`, `module`, `source_mod` | full_type |

### 关系类型

```
(Recipe)-[:BELONGS_TO]->(Mod)
(Recipe)-[:CONSUMES {count, mode, prop}]->(Item)
(Recipe)-[:PRODUCES {count, chance}]->(Item)
(Mod)-[:REQUIRES]->(Mod)
```

- `CONSUMES.mode`: `consume` (消耗) / `keep` (保留,如工具) / `destroy` (销毁)
- `CONSUMES.prop`: `Prop1` (主手) / `Prop2` (副手) / `Prop1;Prop2`
- `PRODUCES.chance`: 概率,默认 1.0

## 文件结构

```
mod_dependency_analyzer/
├── README.md                          # 项目概述
├── models.py                          # 现有:ModDependencyGraph (仅 mod 依赖)
├── recipe_graph.py                    # 扩展:RecipeGraph (含 Recipe/Item/合成图)
├── scanners/
│   ├── __init__.py
│   ├── mod_scanner.py                 # 扫描 mod.info
│   ├── recipe_scanner_b41.py          # 解析 B41 `recipe X {}` 语法
│   └── recipe_scanner_b42.py          # 解析 B42 `craftRecipe X {}` 语法
├── exporters/
│   ├── __init__.py
│   ├── csv_exporter.py                # 输出 nodes.csv + relationships.csv
│   └── cypher_exporter.py             # 输出 import.cypher
├── import_workshop.py                 # 一键入口 CLI
├── docs/
│   └── recipe_graph_import.md         # 本文档
└── exports/
    └── YYYY-MM-DD/                    # 每次导出的数据
        ├── nodes.csv
        ├── relationships.csv
        ├── import.cypher
        └── summary.md
```

## 使用方法

### 1. 导出离线数据 (无需 Neo4j)

```bash
cd /Users/liubinbin/Zomboid/Workshop
python3 -m mod_dependency_analyzer.import_workshop
```

默认导出 CSV + Cypher 到 `mod_dependency_analyzer/exports/<今日日期>/`

### 2. 只导出某一种格式

```bash
python3 -m mod_dependency_analyzer.import_workshop --format csv
python3 -m mod_dependency_analyzer.import_workshop --format cypher
```

### 3. 直接 push 到 Neo4j (需 Neo4j 运行)

```bash
python3 -m mod_dependency_analyzer.import_workshop --push
# 或自定义连接
python3 -m mod_dependency_analyzer.import_workshop --push \
    --neo4j-uri bolt://localhost:7687 \
    --neo4j-user neo4j \
    --neo4j-password your_password
```

### 4. 启动本地 Neo4j

```bash
# Docker 方式
docker run -d --name neo4j \
    -p 7474:7474 -p 7687:7687 \
    -e NEO4J_AUTH=neo4j/password \
    neo4j:latest

# 或 brew 方式
brew install neo4j
brew services start neo4j
```

## 导入数据到 Neo4j

### 方法 1: CSV 导入 (推荐,快速)

```bash
# 1. 清空数据库 (首次导入)
docker exec -it neo4j rm -rf /data/databases/neo4j

# 2. 导入
docker exec -it neo4j neo4j-admin import \
    --nodes=/var/lib/neo4j/import/nodes.csv \
    --relationships=/var/lib/neo4j/import/relationships.csv

# 3. 重启 Neo4j
docker restart neo4j
```

### 方法 2: Cypher 脚本 (适合增量)

```bash
# 在 Neo4j Browser (http://localhost:7474) 中粘贴 import.cypher 内容
# 或用 cypher-shell:
cypher-shell -u neo4j -p password < mod_dependency_analyzer/exports/2026-06-10/import.cypher
```

## 常用查询示例

打开 Neo4j Browser: http://localhost:7474

### 查询 1: 查看所有 Mod

```cypher
MATCH (m:Mod) RETURN m.mod_id, m.name, m.version, m.pz_version
ORDER BY m.mod_id
```

### 查询 2: 查看奶酪的合成树 (一层)

```cypher
MATCH (r:Recipe {recipe_id: 'Bin2MakeCheese'})-[:CONSUMES]->(i:Item)
RETURN r.recipe_id AS recipe,
       i.full_type AS input,
       i.display_name AS 中文名,
       i.module AS module
```

### 查询 3: 奶酪的完整合成树 (递归展开)

```cypher
MATCH path = (i:Item {full_type: 'Base.Cheese'})<-[:PRODUCES*1..5]-(r:Recipe)
              -[:CONSUMES*1..5]->(sub:Item)
WHERE ALL(n IN nodes(path) WHERE n:Recipe OR n:Item)
RETURN [n IN nodes(path) | COALESCE(n.recipe_id, n.full_type)] AS path,
       length(path) AS depth
ORDER BY depth
LIMIT 50
```

### 查询 4: 反向 — 哪些配方能产出某物品

```cypher
MATCH (r:Recipe)-[p:PRODUCES]->(i:Item {full_type: 'Base.ShortBat'})
RETURN r.recipe_id, r.mod_id, r.syntax, p.count
```

### 查询 5: 模组依赖图 (合并 modpack + 中文补丁)

```cypher
MATCH (a:Mod)-[r:REQUIRES]->(b:Mod)
RETURN a.mod_id AS 主动, type(r) AS 关系, b.mod_id AS 依赖
ORDER BY a.mod_id
```

### 查询 6: 工具型原料 (mode=keep)

```cypher
MATCH (r:Recipe)-[c:CONSUMES {mode: 'keep'}]->(i:Item)
RETURN r.recipe_id AS recipe, i.full_type AS tool, c.prop AS hand
```

### 查询 7: 跨模组合成 (A mod 配方 + B mod 物品)

```cypher
MATCH (r:Recipe)-[:CONSUMES]->(i:Item)
WHERE r.mod_id <> i.source_mod
RETURN r.recipe_id, r.mod_id AS recipe_mod, i.full_type, i.source_mod
```

### 查询 8: 统计信息

```cypher
MATCH (m:Mod) WITH count(m) AS mod_n
MATCH (r:Recipe) WITH mod_n, count(r) AS recipe_n
MATCH (i:Item) WITH mod_n, recipe_n, count(i) AS item_n
MATCH ()-[c:CONSUMES]->() WITH mod_n, recipe_n, item_n, count(c) AS consumes_n
MATCH ()-[p:PRODUCES]->() WITH mod_n, recipe_n, item_n, consumes_n, count(p) AS produces_n
MATCH ()-[req:REQUIRES]->()
RETURN mod_n AS Mod数,
       recipe_n AS Recipe数,
       item_n AS Item数,
       consumes_n AS 原料关系,
       produces_n AS 产物关系,
       count(req) AS 模组依赖
```

## 当前扫描结果(2026-06-10)

扫描仓库 `/Users/liubinbin/Zomboid/Workshop` 得到的快照:

| 指标 | 数量 |
|------|------|
| Mod 节点 | 14 (去除多版本重复) |
| Recipe 节点 | 5 (3 B42 + 2 B41) |
| Item 节点 | 11 (含完整中文名) |
| REQUIRES 关系 | 10 (modpack 依赖) |
| BELONGS_TO 关系 | 5 |
| CONSUMES 关系 | 10 |
| PRODUCES 关系 | 9 |

### Recipe 清单

| Recipe ID | 语法 | mod | 原料 | 产物 |
|-----------|------|-----|------|------|
| Bin2DisassembleCrudeWoodenTongs | B42 | bin2_extension | CrudeWoodenTongs | ShortBat×2, RippedSheets×1 |
| Bin2DisassembleSplint | B42 | bin2_extension | Splint | ShortBat×2, RippedSheets×1 |
| Bin2MakeCheese | B42 | bin2_extension | Bowl(keep), CheeseCloth, Milk, Sugar, Salt, Vinegar2 | Cheese |
| DisassembleCrudeWoodenTongs | B41 | bin2_extension (EOL) | CrudeWoodenTongs | ShortBat×2, RippedSheets×1 |
| DisassembleSplint | B41 | bin2_extension (EOL) | Splint | ShortBat×2, RippedSheets×1 |

## 扩展方向

### 已规划(后续 PR)

- [ ] 扫描 Steam Workshop 已装 mod
- [ ] 解析 PZ 原版 items.txt / recipes_carpentry.txt 等
- [ ] 跨 mod 物品引用追踪(Xantji.RubberProjectile223 是哪个原 mod 配方的产物)
- [ ] Web 可视化(Flask + D3.js force-directed graph)
- [ ] recipe 工具合成递归展开(碗也是 Item,可继续问"做碗需要什么")

### 当前限制

1. **不扫描 Steam Workshop 目录**: 仓库 modpack 的 require 列表里很多 mod 不在本仓库,所以部分 REQUIRES 关系被过滤掉
2. **不解析 PZ 原版**: 看不到 Base.* 物品的具体产出配方路径,只能看到仓库内 recipe 的输入
3. **B41 keep/destroy 优先级**: 当前实现中,如果某物品既出现在 keep 行又在 inputs 默认行,会保留后出现的设定

## 维护者

- **作者**: bin^2
- **实施日期**: 2026-06-10
- **关联文档**: `docs/craft-recipe-study.md`、`docs/rolling_log.md`
