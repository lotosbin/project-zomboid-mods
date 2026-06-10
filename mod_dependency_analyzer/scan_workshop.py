"""
scan_workshop.py: 扫描 Steam Workshop 目录,只处理 B42 模组,生成 Neo4j 导出

B42 识别规则 (优先级从高到低):
1. mod.info 含 `versionMin=42.x` 字段
2. 父目录名以 `42.x` / `42.0` / `42.13` / `42.15` 等开头 (PZ Workshop 标准结构)
3. mod name 含 `B42` / `[B42]`

输出:
- mod_dependency_analyzer/exports/<date>-workshop/
  - nodes.csv
  - relationships.csv
  - import.cypher
  - summary.md
"""

import argparse
import json
import os
import sys
import logging
import re
from datetime import date
from typing import Dict, List, Set, Optional

# 让 import 找到同包模块
import importlib
_pkg_root = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _pkg_root)

# 作为包导入以支持相对导入
import importlib.util
_spec_init = importlib.util.spec_from_file_location(
    "mod_dependency_analyzer", os.path.join(_pkg_root, "__init__.py"),
    submodule_search_locations=[_pkg_root]
)
_pkg = importlib.util.module_from_spec(_spec_init)
sys.modules["mod_dependency_analyzer"] = _pkg
_spec_init.loader.exec_module(_pkg)

# 现在可以包内绝对导入
from mod_dependency_analyzer.scanners import mod_scanner, recipe_scanner_b41, recipe_scanner_b42
from mod_dependency_analyzer.exporters.csv_exporter import GraphData, export_to_csv, export_summary
from mod_dependency_analyzer.exporters.cypher_exporter import export_to_cypher
from mod_dependency_analyzer import import_workshop
PZ_BUILTIN_MODULES = import_workshop.PZ_BUILTIN_MODULES
load_item_name_translations = import_workshop.load_item_name_translations
load_recipe_translations = import_workshop.load_recipe_translations

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%H:%M:%S',
)
logger = logging.getLogger(__name__)


WORKSHOP_ROOT_DEFAULT = "/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600"


# PZ 模组版本目录的正则 (如 42.0, 42.13, 42.13.1, 42.15.0, 42.19.0)
RE_PZ_VERSION_DIR = re.compile(r"^42\.\d+(?:\.\d+)?$")

# mod name 中的 B42 标识
RE_B42_NAME_TAG = re.compile(r"\[?B42\]?", re.IGNORECASE)


def is_b42_mod_info(path: str) -> bool:
    """
    判断单个 mod.info 是否属于 B42 模组
    规则:
    1. mod.info 内含 `versionMin=42.x`
    2. 父目录名匹配 42.x 模式 (e.g. 42.0, 42.13, 42.15.0)
    3. mod name 含 [B42] 或 B42
    """
    if not os.path.isfile(path):
        return False

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # 规则 1: versionMin=42.
    if re.search(r'^\s*versionMin\s*=\s*42\.', content, re.MULTILINE | re.IGNORECASE):
        return True

    # 规则 2: 父目录是 42.x
    parent_name = os.path.basename(os.path.dirname(path))
    if RE_PZ_VERSION_DIR.match(parent_name):
        return True

    # 规则 3: name 含 B42
    name_match = re.search(r'^\s*name\s*=\s*(.+)', content, re.MULTILINE)
    if name_match and RE_B42_NAME_TAG.search(name_match.group(1)):
        return True

    return False


def find_all_mod_info(workshop_root: str) -> List[str]:
    """扫描 workshop 根目录,找到所有 mod.info 路径"""
    results = []
    for entry in sorted(os.listdir(workshop_root)):
        # 跳过隐藏目录
        if entry.startswith('.'):
            continue
        mod_root = os.path.join(workshop_root, entry, 'mods')
        if not os.path.isdir(mod_root):
            continue
        # 递归找 mod.info
        for dirpath, dirnames, filenames in os.walk(mod_root):
            for filename in filenames:
                if filename == 'mod.info':
                    full = os.path.join(dirpath, filename)
                    if not full.startswith('/.'):  # 跳过隐藏
                        results.append(full)
    return results


def scan_workshop_b42(workshop_root: str) -> List[mod_scanner.ModInfo]:
    """
    扫描整个 Workshop 目录,只保留 B42 mod
    """
    logger.info(f"扫描 Workshop 目录: {workshop_root}")
    all_mod_info = find_all_mod_info(workshop_root)
    logger.info(f"找到 {len(all_mod_info)} 个 mod.info, 过滤 B42...")

    b42_mods = []
    skipped = 0
    for path in all_mod_info:
        if is_b42_mod_info(path):
            info = mod_scanner.parse_mod_info(path)
            if info:
                b42_mods.append(info)
        else:
            skipped += 1

    logger.info(f"识别为 B42: {len(b42_mods)} 个, 跳过非 B42: {skipped} 个")
    return b42_mods


def _is_recipe_file(path: str) -> bool:
    """判断文件是否是 recipe 定义文件 (从 import_workshop 复制)"""
    if not path.endswith('.txt'):
        return False
    name = os.path.basename(path).lower()
    if 'recipe' in name and 'item' not in name:
        return True
    return False


def build_workshop_graph_data(workshop_root: str) -> GraphData:
    """扫描 Workshop 目录构建 GraphData (B42 only)"""
    data = GraphData()

    # ---- Step 1: 扫描 mod.info (B42 过滤) ----
    b42_mods = scan_workshop_b42(workshop_root)
    if not b42_mods:
        logger.warning("未找到任何 B42 mod")
        return data

    # 同一 mod_id 出现多次,保留最高 versionMin
    # 优先保留 "短 id" (无 /),因为部分模组同时存在
    # 顶层 mod.info (短 id) 与 版本目录 mod.info (长 id,带 /)
    latest: Dict[str, mod_scanner.ModInfo] = {}
    for m in b42_mods:
        if m.mod_id not in latest:
            latest[m.mod_id] = m
        else:
            cur = latest[m.mod_id]
            # 优先选短 id (无 /)
            if '/' in cur.mod_id and '/' not in m.mod_id:
                latest[m.mod_id] = m
                continue
            if '/' in m.mod_id and '/' not in cur.mod_id:
                continue
            # 都不含 /,比 versionMin
            if (m.pz_version or '0') > (cur.pz_version or '0'):
                latest[m.mod_id] = m

    # 处理 mod_id 冲突:同 mod 有短/长两个 id,合并到短 id
    short_to_long: Dict[str, str] = {}
    for mod_id in list(latest.keys()):
        if '/' in mod_id:
            short_id = mod_id.split('/', 1)[1]
            # 如果短 id 已存在,合并到短 id
            if short_id in latest:
                short_to_long[mod_id] = short_id
            else:
                # 把 mod_id 重命名为短 id
                info = latest.pop(mod_id)
                info.mod_id = short_id
                latest[short_id] = info
                short_to_long[mod_id] = short_id

    # 修正 requires 列表中的 / 长 id
    for mod_id, m in latest.items():
        m.requires = [short_to_long.get(r.lstrip('\\'), r.lstrip('\\')) for r in m.requires]

    # 添加 Mod 节点
    for mod_id, m in latest.items():
        data.mods.append({
            'mod_id': mod_id,
            'name': m.name,
            'version': m.version,
            'author': m.author,
            'pz_version': m.pz_version,
            'description': m.description,
        })

    # 添加 REQUIRES 关系
    known = set(latest.keys())
    for mod_id, m in latest.items():
        for req in m.requires:
            req_clean = req.lstrip('\\')
            if req_clean in known:
                data.requires.append((mod_id, req_clean))

    # ---- Step 2: 翻译加载 ----
    logger.info("加载 ItemName/Recipe 翻译...")
    item_trans = load_item_name_translations(workshop_root)
    recipe_trans = load_recipe_translations(workshop_root)
    logger.info(f"ItemName 翻译: {len(item_trans)} 条, Recipe 翻译: {len(recipe_trans)} 条")

    # ---- Step 3: 扫描 recipe 文件 ----
    recipe_files = []
    for dirpath, dirnames, filenames in os.walk(workshop_root):
        # 跳过隐藏目录与示例 mod
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        for filename in filenames:
            full = os.path.join(dirpath, filename)
            if _is_recipe_file(full):
                recipe_files.append(full)
    logger.info(f"找到 {len(recipe_files)} 个 recipe 文件 (Workshop 内)")

    # 解析每个 recipe 文件
    for rf in recipe_files:
        # 关联到 mod_id (从路径反推)
        # 路径模式: <workshop>/<workshop_id>/mods/<mod_id>/<version>/media/scripts/...
        relative = os.path.relpath(rf, workshop_root)
        parts = relative.split(os.sep)
        mod_id = None
        for i, p in enumerate(parts):
            if p == 'mods' and i + 1 < len(parts):
                mod_id = parts[i + 1]
                break
        if not mod_id:
            mod_id = os.path.basename(os.path.dirname(os.path.dirname(rf)))

        with open(rf, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        is_b42 = 'craftRecipe' in content
        if is_b42:
            recipes = recipe_scanner_b42.parse_b42(content)
            syntax = 'B42'
        else:
            recipes = recipe_scanner_b41.parse_b41(content)
            syntax = 'B41'

        for r in recipes:
            data.recipes.append({
                'recipe_id': r.recipe_id,
                'mod_id': mod_id,
                'syntax': syntax,
                'time': getattr(r, 'time', 50),
                'timed_action': getattr(r, 'timed_action', ''),
                'category': getattr(r, 'category', ''),
                'tags': getattr(r, 'tags', ''),
            })
            data.belongs_to.append((r.recipe_id, mod_id))

            for inp in r.inputs:
                item = inp.item
                if '.' not in item:
                    item = f'Base.{item}'
                data.consumes.append((r.recipe_id, item, inp.count, inp.mode, inp.prop))
                display = item_trans.get(item, '')
                module = item.split('.', 1)[0] if '.' in item else 'Base'
                data.items.append({
                    'full_type': item,
                    'display_name': display,
                    'module': module,
                    'source_mod': 'Base' if module in PZ_BUILTIN_MODULES else module,
                })

            for out in r.outputs:
                item = out.item
                if '.' not in item:
                    item = f'Base.{item}'
                data.produces.append((r.recipe_id, item, out.count, 1.0))
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


def main():
    parser = argparse.ArgumentParser(description='扫描 Steam Workshop B42 模组 + 导出 Neo4j')
    parser.add_argument('--root', default=WORKSHOP_ROOT_DEFAULT,
                        help=f'Steam Workshop 根目录 (默认: {WORKSHOP_ROOT_DEFAULT})')
    parser.add_argument('--output', default=None,
                        help='导出目录 (默认: <root>/mod_dependency_analyzer/exports/<date>-workshop/)')
    parser.add_argument('--format', choices=['csv', 'cypher', 'both'], default='both')

    args = parser.parse_args()

    if not args.output:
        today = date.today().isoformat()
        args.output = os.path.join(_pkg_root, 'exports', f'{today}-workshop')

    data = build_workshop_graph_data(args.root)

    if args.format in ('csv', 'both'):
        export_to_csv(data, args.output)
        export_summary(data, args.output)
        logger.info(f"CSV 导出: {args.output}")

    if args.format in ('cypher', 'both'):
        cypher_path = os.path.join(args.output, 'import.cypher')
        export_to_cypher(data, cypher_path)
        logger.info(f"Cypher 导出: {cypher_path}")


if __name__ == '__main__':
    main()
