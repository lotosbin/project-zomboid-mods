"""
cypher_exporter.py: 将扫描结果导出为 Cypher 脚本

可直接用 cypher-shell 加载:
    cypher-shell -u neo4j -p password < exports.cypher

或复制粘贴到 Neo4j Browser 中执行。
"""

import os
from typing import Dict, List, Any
from .csv_exporter import GraphData


def _escape(value: str) -> str:
    """转义 Cypher 字符串字面量"""
    if not value:
        return '""'
    # 替换反斜杠与引号
    escaped = value.replace('\\', '\\\\').replace('"', '\\"')
    return f'"{escaped}"'


def export_to_cypher(data: GraphData, output_path: str) -> str:
    """
    导出为 Cypher 脚本 (.cypher 文件)
    """
    lines = []
    lines.append("// =============================================")
    lines.append("// Neo4j Cypher 导入脚本")
    lines.append("// 由 import_workshop.py 自动生成")
    lines.append("// 用法: cypher-shell -u neo4j -p password < " + os.path.basename(output_path))
    lines.append("// =============================================")
    lines.append("")

    # ---- Mod 节点 ----
    lines.append("// === Mod 节点 ===")
    seen_mods = set()
    for m in data.mods:
        if m['mod_id'] in seen_mods:
            continue
        seen_mods.add(m['mod_id'])
        cypher = (
            f"MERGE (m:Mod {{mod_id: {_escape(m['mod_id'])}}}) "
            f"SET m.name = {_escape(m.get('name', ''))}, "
            f"m.version = {_escape(m.get('version', ''))}, "
            f"m.author = {_escape(m.get('author', ''))}, "
            f"m.pz_version = {_escape(m.get('pz_version', ''))}, "
            f"m.description = {_escape(m.get('description', ''))};"
        )
        lines.append(cypher)
    lines.append("")

    # ---- Recipe 节点 ----
    lines.append("// === Recipe 节点 ===")
    seen_recipes = set()
    for r in data.recipes:
        if r['recipe_id'] in seen_recipes:
            continue
        seen_recipes.add(r['recipe_id'])
        cypher = (
            f"MERGE (r:Recipe {{recipe_id: {_escape(r['recipe_id'])}}}) "
            f"SET r.mod_id = {_escape(r.get('mod_id', ''))}, "
            f"r.syntax = {_escape(r.get('syntax', ''))}, "
            f"r.time = {r.get('time', 50)}, "
            f"r.timed_action = {_escape(r.get('timed_action', ''))}, "
            f"r.category = {_escape(r.get('category', ''))}, "
            f"r.tags = {_escape(r.get('tags', ''))};"
        )
        lines.append(cypher)
    lines.append("")

    # ---- Item 节点 ----
    lines.append("// === Item 节点 ===")
    seen_items = set()
    for i in data.items:
        if i['full_type'] in seen_items:
            continue
        seen_items.add(i['full_type'])
        cypher = (
            f"MERGE (i:Item {{full_type: {_escape(i['full_type'])}}}) "
            f"SET i.display_name = {_escape(i.get('display_name', ''))}, "
            f"i.module = {_escape(i.get('module', ''))}, "
            f"i.source_mod = {_escape(i.get('source_mod', ''))};"
        )
        lines.append(cypher)
    lines.append("")

    # ---- REQUIRES 关系 ----
    if data.requires:
        lines.append("// === REQUIRES 关系 ===")
        for from_id, to_id in data.requires:
            cypher = (
                f"MATCH (a:Mod {{mod_id: {_escape(from_id)}}}), "
                f"(b:Mod {{mod_id: {_escape(to_id)}}}) "
                f"MERGE (a)-[:REQUIRES]->(b);"
            )
            lines.append(cypher)
        lines.append("")

    # ---- BELONGS_TO 关系 ----
    if data.belongs_to:
        lines.append("// === BELONGS_TO 关系 ===")
        for recipe_id, mod_id in data.belongs_to:
            cypher = (
                f"MATCH (r:Recipe {{recipe_id: {_escape(recipe_id)}}}), "
                f"(m:Mod {{mod_id: {_escape(mod_id)}}}) "
                f"MERGE (r)-[:BELONGS_TO]->(m);"
            )
            lines.append(cypher)
        lines.append("")

    # ---- CONSUMES 关系 ----
    if data.consumes:
        lines.append("// === CONSUMES 关系 ===")
        for recipe_id, full_type, count, mode, prop in data.consumes:
            cypher = (
                f"MATCH (r:Recipe {{recipe_id: {_escape(recipe_id)}}}), "
                f"(i:Item {{full_type: {_escape(full_type)}}}) "
                f"MERGE (r)-[rel:CONSUMES {{count: {count}, mode: {_escape(mode)}, prop: {_escape(prop)}}}]->(i);"
            )
            lines.append(cypher)
        lines.append("")

    # ---- PRODUCES 关系 ----
    if data.produces:
        lines.append("// === PRODUCES 关系 ===")
        for recipe_id, full_type, count, chance in data.produces:
            cypher = (
                f"MATCH (r:Recipe {{recipe_id: {_escape(recipe_id)}}}), "
                f"(i:Item {{full_type: {_escape(full_type)}}}) "
                f"MERGE (r)-[rel:PRODUCES {{count: {count}, chance: {chance}}}]->(i);"
            )
            lines.append(cypher)
        lines.append("")

    # ---- 写文件 ----
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    return output_path
