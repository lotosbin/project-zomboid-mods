"""
import_workshop.py: 一键扫描 Workshop 仓库 + 导出 Neo4j 数据

用法:
    python -m mod_dependency_analyzer.import_workshop
    python -m mod_dependency_analyzer.import_workshop --format csv
    python -m mod_dependency_analyzer.import_workshop --format cypher
    python -m mod_dependency_analyzer.import_workshop --push  # 直接 push 到 Neo4j
"""

import argparse
import json
import os
import sys
import logging
from datetime import date
from typing import Dict, List, Set

from .scanners import mod_scanner, recipe_scanner_b41, recipe_scanner_b42
from .exporters.csv_exporter import GraphData, export_to_csv, export_summary
from .exporters.cypher_exporter import export_to_cypher

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%H:%M:%S',
)
logger = logging.getLogger(__name__)


# 不属于模组物品而是 PZ 内置 module
PZ_BUILTIN_MODULES = {
    'Base', 'Radio', 'farming', 'Sewing', 'Radio', 'Survival',
}


def load_item_name_translations(workshop_root: str) -> Dict[str, str]:
    """
    扫描所有 mod 的 ItemName.json 翻译文件,返回 {fullType: 中文名}
    """
    result = {}
    for dirpath, dirnames, filenames in os.walk(workshop_root):
        # 跳过无关目录
        dirnames[:] = [d for d in dirnames if d not in
                       ('learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea', '.vscode')]
        for filename in filenames:
            if filename == 'ItemName.json':
                full_path = os.path.join(dirpath, filename)
                try:
                    with open(full_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    for key, value in data.items():
                        # key 格式: "ItemName_Base.Apple" -> fullType = "Base.Apple"
                        if key.startswith('ItemName_'):
                            ft = key[len('ItemName_'):]
                            result[ft] = value
                except Exception as e:
                    logger.warning(f"无法解析 {full_path}: {e}")
    return result


def load_recipe_translations(workshop_root: str) -> Dict[str, str]:
    """
    扫描所有 mod 的 Recipe.json / Recipes.json 翻译文件,返回 {recipeId: 中文名}
    """
    result = {}
    for dirpath, dirnames, filenames in os.walk(workshop_root):
        dirnames[:] = [d for d in dirnames if d not in
                       ('learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea', '.vscode')]
        for filename in filenames:
            if filename in ('Recipe.json', 'Recipes.json'):
                full_path = os.path.join(dirpath, filename)
                try:
                    with open(full_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    for key, value in data.items():
                        # key 格式: "Recipe_XXX" (B42 官方) 或 "XXX" (裸 key,本仓库方案)
                        if key.startswith('Recipe_'):
                            rid = key[len('Recipe_'):]
                        else:
                            rid = key
                        result[rid] = value
                except Exception as e:
                    logger.warning(f"无法解析 {full_path}: {e}")
    return result


def build_graph_data(workshop_root: str) -> GraphData:
    """
    主入口:扫描整个 Workshop 仓库,构建 GraphData
    """
    data = GraphData()

    # ---- Step 1: 扫描 mod.info ----
    logger.info("扫描 mod.info...")
    mod_infos = mod_scanner.scan_workshop(workshop_root)
    logger.info(f"找到 {len(mod_infos)} 个 mod.info")

    # 多个版本的 mod 只取最新版本
    # 同一 mod_id 出现多次时,保留最高 versionMin
    latest_mods: Dict[str, mod_scanner.ModInfo] = {}
    for m in mod_infos:
        if m.mod_id not in latest_mods:
            latest_mods[m.mod_id] = m
        else:
            cur = latest_mods[m.mod_id]
            # 比较 pz_version (字符串比较,数字越大越新)
            if (m.pz_version or '0') > (cur.pz_version or '0'):
                latest_mods[m.mod_id] = m

    # 添加 Mod 节点
    for mod_id, m in latest_mods.items():
        data.mods.append({
            'mod_id': mod_id,
            'name': m.name,
            'version': m.version,
            'author': m.author,
            'pz_version': m.pz_version,
            'description': m.description,
        })

    # 添加 REQUIRES 关系 (从 modpack 的 require 列表 + 翻译补丁的 require)
    # 注意:modpack 的 require 含大量外部 mod,本仓库不一定有这些 mod
    # 所以只添加**本仓库存在的** mod_id 之间的 REQUIRES 关系
    known_mod_ids = set(latest_mods.keys())
    for mod_id, m in latest_mods.items():
        for req in m.requires:
            req_clean = req.lstrip('\\')
            if req_clean in known_mod_ids:
                data.requires.append((mod_id, req_clean))

    # ---- Step 2: 加载翻译 ----
    logger.info("加载 ItemName/Recipe 翻译...")
    item_trans = load_item_name_translations(workshop_root)
    recipe_trans = load_recipe_translations(workshop_root)
    logger.info(f"ItemName 翻译: {len(item_trans)} 条, Recipe 翻译: {len(recipe_trans)} 条")

    # ---- Step 3: 扫描所有 recipe 文件 ----
    logger.info("扫描 recipe 文件...")

    def _is_recipe_file(path: str) -> bool:
        """判断文件是否是 recipe 定义文件"""
        if not path.endswith('.txt'):
            return False
        name = os.path.basename(path).lower()
        # B41: Recipes.txt 或 *Recipes.txt
        # B42: recipes/xxx.txt 或 recipes_xxx.txt
        # 关键特征: 文件名包含 "recipe" (不区分大小写)
        if 'recipe' in name:
            return True
        # 排除 item 定义文件 (文件名含 "item")
        if 'item' in name:
            return False
        return False

    recipe_files = []
    for dirpath, dirnames, filenames in os.walk(workshop_root):
        dirnames[:] = [d for d in dirnames if d not in
                       ('learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea', '.vscode')]
        for filename in filenames:
            full_path = os.path.join(dirpath, filename)
            if _is_recipe_file(full_path):
                recipe_files.append(full_path)

    logger.info(f"找到 {len(recipe_files)} 个 recipe 文件")

    # 解析每个 recipe 文件,关联到对应的 mod
    for rf in recipe_files:
        # 找到对应的 mod_id (从路径反推)
        # 例: .../bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt
        #     -> bin2_extension/42.19.0
        relative = os.path.relpath(rf, workshop_root)
        parts = relative.split(os.sep)
        # 找 'Contents/mods' 之后的结构
        mod_id = None
        mod_version = None
        for i, p in enumerate(parts):
            if p == 'mods' and i + 1 < len(parts):
                # mods/<mod_id>/<version>/...
                mod_id = parts[i + 1]
                if i + 2 < len(parts):
                    mod_version = parts[i + 2]
                break
        # 兜底:用父目录名
        if not mod_id:
            mod_id = os.path.basename(os.path.dirname(os.path.dirname(rf)))

        # 读取并解析
        with open(rf, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        # 自动判断 B41 还是 B42
        is_b42 = 'craftRecipe' in content
        if is_b42:
            recipes = recipe_scanner_b42.parse_b42(content)
            syntax = 'B42'
        else:
            recipes = recipe_scanner_b41.parse_b41(content)
            syntax = 'B41'

        for r in recipes:
            # 添加 Recipe 节点
            data.recipes.append({
                'recipe_id': r.recipe_id,
                'mod_id': mod_id,
                'syntax': syntax,
                'time': getattr(r, 'time', 50),
                'timed_action': getattr(r, 'timed_action', ''),
                'category': getattr(r, 'category', ''),
                'tags': getattr(r, 'tags', ''),
            })
            # BELONGS_TO 关系
            data.belongs_to.append((r.recipe_id, mod_id))

            # 添加 inputs (CONSUMES)
            for inp in r.inputs:
                # B41 没有 module 前缀,自动补 Base.
                item = inp.item
                if '.' not in item:
                    item = f'Base.{item}'
                data.consumes.append((
                    r.recipe_id, item, inp.count, inp.mode, inp.prop
                ))
                # 添加 Item 节点
                display = item_trans.get(item, '')
                module = item.split('.', 1)[0] if '.' in item else 'Base'
                data.items.append({
                    'full_type': item,
                    'display_name': display,
                    'module': module,
                    'source_mod': 'Base' if module in PZ_BUILTIN_MODULES else module,
                })

            # 添加 outputs (PRODUCES)
            for out in r.outputs:
                item = out.item
                if '.' not in item:
                    item = f'Base.{item}'
                data.produces.append((
                    r.recipe_id, item, out.count, 1.0
                ))
                # 添加 Item 节点
                display = item_trans.get(item, '')
                module = item.split('.', 1)[0] if '.' in item else 'Base'
                data.items.append({
                    'full_type': item,
                    'display_name': display,
                    'module': module,
                    'source_mod': 'Base' if module in PZ_BUILTIN_MODULES else module,
                })

    logger.info(f"图数据汇总: {len(data.mods)} Mod, {len(data.recipes)} Recipe, "
                f"{len(data.items)} Item, {len(data.requires)} REQUIRES, "
                f"{len(data.belongs_to)} BELONGS_TO, "
                f"{len(data.consumes)} CONSUMES, {len(data.produces)} PRODUCES")

    return data


def push_to_neo4j(data: GraphData, uri: str, user: str, password: str):
    """直接 push 到 Neo4j"""
    from .recipe_graph import RecipeGraph
    g = RecipeGraph(uri=uri, user=user, password=password)

    # 清空旧数据 (可选)
    # g.clear_all()

    # Mod
    for m in data.mods:
        g.add_mod(
            mod_id=m['mod_id'],
            name=m.get('name', ''),
            author=m.get('author', ''),
            version=m.get('version', ''),
            description=m.get('description', ''),
        )

    # Item
    seen_items = set()
    for i in data.items:
        if i['full_type'] in seen_items:
            continue
        seen_items.add(i['full_type'])
        g.add_item(
            full_type=i['full_type'],
            display_name=i.get('display_name', ''),
            module=i.get('module', ''),
            source_mod=i.get('source_mod', 'Base'),
        )

    # Recipe
    for r in data.recipes:
        g.add_recipe(
            recipe_id=r['recipe_id'],
            mod_id=r.get('mod_id', ''),
            syntax=r.get('syntax', 'B42'),
            time=r.get('time', 50),
            timed_action=r.get('timed_action', ''),
            category=r.get('category', ''),
            tags=r.get('tags', ''),
        )

    # 关系
    for from_id, to_id in data.requires:
        g.add_dependency(from_id, to_id)
    for recipe_id, mod_id in data.belongs_to:
        g.add_belongs_to(recipe_id, mod_id)
    for recipe_id, full_type, count, mode, prop in data.consumes:
        g.add_consumes(recipe_id, full_type, count, mode, prop)
    for recipe_id, full_type, count, chance in data.produces:
        g.add_produces(recipe_id, full_type, count, chance)

    stats = g.get_statistics()
    logger.info(f"已 push 到 Neo4j. 统计: {stats}")
    g.close()


def main():
    parser = argparse.ArgumentParser(description='扫描 Workshop 仓库 + 导出 Neo4j 数据')
    parser.add_argument('--root', default='/Users/liubinbin/Zomboid/Workshop',
                        help='Workshop 根目录 (默认: /Users/liubinbin/Zomboid/Workshop)')
    parser.add_argument('--output', default=None,
                        help='导出目录 (默认: <root>/mod_dependency_analyzer/exports/<date>/)')
    parser.add_argument('--format', choices=['csv', 'cypher', 'both'], default='both',
                        help='导出格式 (默认 both)')
    parser.add_argument('--push', action='store_true',
                        help='直接 push 到 Neo4j (需 Neo4j 运行中)')
    parser.add_argument('--neo4j-uri', default='bolt://localhost:7687')
    parser.add_argument('--neo4j-user', default='neo4j')
    parser.add_argument('--neo4j-password', default='password')

    args = parser.parse_args()

    # 默认输出目录
    if not args.output:
        today = date.today().isoformat()
        args.output = os.path.join(
            args.root, 'mod_dependency_analyzer', 'exports', today
        )

    # 构建图数据
    data = build_graph_data(args.root)

    # 导出
    if args.format in ('csv', 'both'):
        paths = export_to_csv(data, args.output)
        summary_path = export_summary(data, args.output)
        logger.info(f"CSV 导出: {paths}")
        logger.info(f"摘要: {summary_path}")

    if args.format in ('cypher', 'both'):
        cypher_path = os.path.join(args.output, 'import.cypher')
        export_to_cypher(data, cypher_path)
        logger.info(f"Cypher 导出: {cypher_path}")

    # 推送
    if args.push:
        push_to_neo4j(
            data,
            uri=args.neo4j_uri,
            user=args.neo4j_user,
            password=args.neo4j_password,
        )


if __name__ == '__main__':
    main()
