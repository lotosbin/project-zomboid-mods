"""
csv_exporter.py: 将扫描结果导出为 Neo4j CSV 格式

可直接用 `neo4j-admin import` 批量导入:
    neo4j-admin import \
        --nodes=nodes.csv \
        --relationships=relationships.csv

节点 CSV 格式:
    modId:ID,name,version,author,:LABEL
    bin2_extension,bin2扩展,1.1.1,bin^2,Mod

关系 CSV 格式:
    :START_ID,:END_ID,:TYPE,count,mode,prop
    Bin2MakeCheese,Base.Cheese,PRODUCES,1,,
"""

import csv
import os
from typing import Dict, List, Any
from dataclasses import dataclass, field


@dataclass
class GraphData:
    """内存中的图数据汇总"""
    mods: List[Dict] = field(default_factory=list)       # [{mod_id, name, version, author, pz_version, description}]
    recipes: List[Dict] = field(default_factory=list)   # [{recipe_id, mod_id, syntax, time, timed_action, category, tags}]
    items: List[Dict] = field(default_factory=list)     # [{full_type, display_name, module, source_mod}]
    requires: List[tuple] = field(default_factory=list) # [(from_mod_id, to_mod_id)]
    belongs_to: List[tuple] = field(default_factory=list)  # [(recipe_id, mod_id)]
    consumes: List[tuple] = field(default_factory=list) # [(recipe_id, full_type, count, mode, prop)]
    produces: List[tuple] = field(default_factory=list) # [(recipe_id, full_type, count, chance)]


def export_to_csv(data: GraphData, output_dir: str) -> Dict[str, str]:
    """
    导出为 Neo4j CSV 格式
    返回 {文件名: 完整路径}
    """
    os.makedirs(output_dir, exist_ok=True)

    paths = {}

    # ---- nodes.csv ----
    nodes_path = os.path.join(output_dir, 'nodes.csv')
    with open(nodes_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)

        # 头
        writer.writerow(['modId:ID', 'name', 'version', 'author', 'pzVersion', 'description', ':LABEL'])

        # Mod 节点
        seen_mod_ids = set()
        for m in data.mods:
            if m['mod_id'] in seen_mod_ids:
                continue
            seen_mod_ids.add(m['mod_id'])
            writer.writerow([
                m['mod_id'],
                m.get('name', ''),
                m.get('version', ''),
                m.get('author', ''),
                m.get('pz_version', ''),
                m.get('description', ''),
                'Mod',
            ])

        # Recipe 节点
        seen_recipe_ids = set()
        for r in data.recipes:
            if r['recipe_id'] in seen_recipe_ids:
                continue
            seen_recipe_ids.add(r['recipe_id'])
            writer.writerow([
                r['recipe_id'],
                '',  # Recipe 没有 name
                r.get('mod_id', ''),
                r.get('syntax', ''),
                r.get('time', ''),
                r.get('timed_action', ''),
                'Recipe',
            ])

        # Item 节点
        seen_items = set()
        for i in data.items:
            if i['full_type'] in seen_items:
                continue
            seen_items.add(i['full_type'])
            writer.writerow([
                i['full_type'],
                i.get('display_name', ''),
                i.get('module', ''),
                i.get('source_mod', ''),
                '',  # 留空
                '',
                'Item',
            ])
    paths['nodes.csv'] = nodes_path

    # ---- relationships.csv ----
    rel_path = os.path.join(output_dir, 'relationships.csv')
    with open(rel_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)

        # 头
        writer.writerow([':START_ID', ':END_ID', ':TYPE', 'count', 'mode', 'prop', 'chance'])

        # REQUIRES (Mod -> Mod)
        for from_id, to_id in data.requires:
            writer.writerow([from_id, to_id, 'REQUIRES', '', '', '', ''])

        # BELONGS_TO (Recipe -> Mod)
        for recipe_id, mod_id in data.belongs_to:
            writer.writerow([recipe_id, mod_id, 'BELONGS_TO', '', '', '', ''])

        # CONSUMES (Recipe -> Item, with count/mode/prop)
        for recipe_id, full_type, count, mode, prop in data.consumes:
            writer.writerow([recipe_id, full_type, 'CONSUMES', count, mode, prop, ''])

        # PRODUCES (Recipe -> Item, with count/chance)
        for recipe_id, full_type, count, chance in data.produces:
            writer.writerow([recipe_id, full_type, 'PRODUCES', count, '', '', chance])
    paths['relationships.csv'] = rel_path

    return paths


def export_summary(data: GraphData, output_dir: str) -> str:
    """导出统计摘要 (Markdown 格式)"""
    path = os.path.join(output_dir, 'summary.md')
    with open(path, 'w', encoding='utf-8') as f:
        f.write("# Neo4j 导入数据摘要\n\n")
        f.write(f"- Mod 节点数: {len(set(m['mod_id'] for m in data.mods))}\n")
        f.write(f"- Recipe 节点数: {len(set(r['recipe_id'] for r in data.recipes))}\n")
        f.write(f"- Item 节点数: {len(set(i['full_type'] for i in data.items))}\n")
        f.write(f"- REQUIRES 关系数: {len(data.requires)}\n")
        f.write(f"- BELONGS_TO 关系数: {len(data.belongs_to)}\n")
        f.write(f"- CONSUMES 关系数: {len(data.consumes)}\n")
        f.write(f"- PRODUCES 关系数: {len(data.produces)}\n\n")

        f.write("## Mod 列表\n\n")
        seen = set()
        for m in data.mods:
            if m['mod_id'] in seen:
                continue
            seen.add(m['mod_id'])
            f.write(f"- **{m['mod_id']}** v{m.get('version', '?')} ({m.get('pz_version', '?')})")
            if m.get('requires'):
                f.write(f" — 依赖: {', '.join(m['requires'])}")
            f.write("\n")

        f.write("\n## Recipe 列表\n\n")
        seen = set()
        for r in data.recipes:
            if r['recipe_id'] in seen:
                continue
            seen.add(r['recipe_id'])
            f.write(f"- **{r['recipe_id']}** ({r.get('syntax', '?')}, time={r.get('time', '?')}) — mod: {r.get('mod_id', '?')}\n")

    return path
