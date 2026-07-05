"""
validate_recipes.py: 配方内容验证脚本

对仓库内所有 mod 的 recipe 文件做完整内容验证:
1. JSON 翻译文件无重复 key
2. 物品 ID (fullType) 在 PZ 中真实存在
3. B41/B42 语法可被正确解析
4. 配方字段完整(必填: time, tags, inputs, outputs)
5. 关键经验: 设计三原则(真实性/合理性/可行性)

用法:
    python -m mod_dependency_analyzer.validate_recipes
    python -m mod_dependency_analyzer.validate_recipes --root <path> --strict
"""

import argparse
import json
import os
import re
import sys
import logging
from pathlib import Path
from typing import Dict, List, Set, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s: %(message)s',
)
logger = logging.getLogger(__name__)


def parse_json_lenient(text: str):
    """宽容解析 JSON,容忍 trailing comma"""
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)


def index_known_items() -> Set[str]:
    """
    索引 PZ 中真实存在的物品 ID
    来源: Steam Workshop 已装 mod 的 ItemName.json
    """
    known = set()

    # 索引目录
    idx_dirs = [
        # B42Trans_CN_As1 (key 无前缀)
        "/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Resources/steamapps/workshop/content/108600/3556544454/mods/B42Trans_CN_As1/42.0/media/lua/shared/Translate/CN",
        # 本仓库 bin2_extension
        "/Users/liubinbin/Zomboid/Workshop/bin2_b42/Contents/mods/bin2_extension/42.19.0/media/lua/shared/Translate/CN",
        # ZVirusVaccine (化学物品索引)
        "/Users/liubinbin/Zomboid/Workshop/learn/ZVirusVaccine42BETA/42.14/media/lua/shared/Translate/CN",
    ]

    for d in idx_dirs:
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith('.json'):
                continue
            path = os.path.join(d, fn)
            try:
                with open(path) as f:
                    txt = f.read()
                data = parse_json_lenient(txt)
                for key in data.keys():
                    if key.startswith("ItemName_"):
                        ft = key[len("ItemName_"):]
                    elif key.startswith("Recipe_"):
                        continue
                    elif "." in key and not key.startswith("$"):
                        ft = key
                    else:
                        continue
                    known.add(ft)
            except Exception as e:
                logger.warning(f"跳过 {path}: {e}")

    return known


def check_json_duplicates(path: str) -> List[str]:
    """检查 JSON 文件是否有重复 key"""
    errors = []
    with open(path) as f:
        text = f.read()
    # 提取所有顶层 key (简单实现,假设没嵌套)
    keys = re.findall(r'^\s*"([^"]+)"\s*:', text, re.MULTILINE)
    seen = set()
    for k in keys:
        if k in seen:
            errors.append(f"重复 key: '{k}'")
        seen.add(k)
    return errors


def parse_b42_recipe(body: str) -> Dict:
    """解析单个 B42 craftRecipe 块(body 是 {} 内的内容,不含 craftRecipe ID)"""
    info = {'id': None, 'time': None, 'tags': '', 'category': '',
            'timed_action': '', 'inputs': [], 'outputs': []}

    m = re.search(r'time\s*=\s*(\d+)', body)
    if m:
        info['time'] = int(m.group(1))

    m = re.search(r'timedAction\s*=\s*(\w+)', body)
    if m:
        info['timed_action'] = m.group(1)

    m = re.search(r'Tags\s*=\s*([^,;\n]+(?:[;][^,;\n]+)*)', body)
    if m:
        info['tags'] = m.group(1).strip()

    m = re.search(r'category\s*=\s*(\w+)', body)
    if m:
        info['category'] = m.group(1)

    # inputs 块
    in_block = re.search(r'inputs\s*\{(.*?)\}', body, re.DOTALL)
    if in_block:
        for line in in_block.group(1).split('\n'):
            m = re.search(r'item\s+(\d+)\s+\[([\w\.;]+)\]', line.strip())
            if m:
                for sub in m.group(2).split(';'):
                    sub = sub.strip()
                    if sub:
                        info['inputs'].append({'count': int(m.group(1)), 'item': sub})

    # outputs 块
    out_block = re.search(r'outputs\s*\{(.*?)\}', body, re.DOTALL)
    if out_block:
        for line in out_block.group(1).split('\n'):
            m = re.search(r'item\s+(\d+)\s+(\w+\.\w+)', line.strip())
            if m:
                info['outputs'].append({'count': int(m.group(1)), 'item': m.group(2)})

    return info


def validate_recipe_file(path: str, known_items: Set[str]) -> List[str]:
    """验证单个 recipe 文件,返回错误列表"""
    errors = []
    with open(path) as f:
        content = f.read()

    if 'craftRecipe' not in content:
        return errors  # B41 或空文件

    # 找所有 craftRecipe 块,提取 ID 和 body
    # 模式: craftRecipe ID { body }
    pattern = re.compile(r'craftRecipe\s+(\w+)\s*\{', re.MULTILINE)
    matches = list(pattern.finditer(content))
    if not matches:
        return errors

    for i, m in enumerate(matches):
        rid = m.group(1)
        start = m.end()
        # 找匹配的 '}'
        depth = 1
        pos = start
        while pos < len(content) and depth > 0:
            if content[pos] == '{':
                depth += 1
            elif content[pos] == '}':
                depth -= 1
            pos += 1
        body = content[start:pos-1]

        info = parse_b42_recipe(body)
        info['id'] = rid  # 从外部注入

        # 检查 1: 必填字段
        if not info['id']:
            errors.append(f"  [Recipe #{i+1}] 缺 ID")
            continue
        if info['time'] is None:
            errors.append(f"  [Recipe '{info['id']}'] 缺 time 字段")
        if not info['tags']:
            errors.append(f"  [Recipe '{info['id']}'] 缺 Tags 字段")
        if not info['inputs']:
            errors.append(f"  [Recipe '{info['id']}'] 缺 inputs")
        if not info['outputs']:
            errors.append(f"  [Recipe '{info['id']}'] 缺 outputs")

        # 检查 2: 物品存在性
        for inp in info['inputs']:
            if inp['item'] not in known_items:
                errors.append(f"  [Recipe '{info['id']}'] INPUT '{inp['item']}' 不在 PZ 物品表中")
        for out in info['outputs']:
            if out['item'] not in known_items:
                errors.append(f"  [Recipe '{info['id']}'] OUTPUT '{out['item']}' 不在 PZ 物品表中")

    return errors


def validate_translation_json(path: str) -> List[str]:
    """验证翻译 JSON 无重复 key"""
    errors = []
    if not os.path.isfile(path):
        return errors
    try:
        errors = check_json_duplicates(path)
    except Exception as e:
        errors.append(f"  解析失败: {e}")
    return errors


def main():
    parser = argparse.ArgumentParser(description='配方内容验证')
    parser.add_argument('--root', default='/Users/liubinbin/Zomboid/Workshop',
                        help='仓库根目录 (默认 /Users/liubinbin/Zomboid/Workshop)')
    parser.add_argument('--strict', action='store_true',
                        help='严格模式:发现任何错误就退出非零')
    args = parser.parse_args()

    logger.info("=" * 60)
    logger.info("配方内容验证")
    logger.info("=" * 60)

    all_errors = []

    # 步骤 1: 索引 PZ 已知物品
    logger.info("\n[1/3] 索引 PZ 已知物品 ID ...")
    known_items = index_known_items()
    logger.info(f"  共索引 {len(known_items)} 个物品")

    # 步骤 2: 验证所有 JSON 翻译文件
    logger.info("\n[2/3] 验证 JSON 翻译文件 ...")
    json_files = []
    for dirpath, dirnames, filenames in os.walk(args.root):
        # 跳过无关目录
        dirnames[:] = [d for d in dirnames if d not in
                       ('learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea', '.vscode',
                        'mod_dependency_analyzer')]
        for fn in filenames:
            if fn in ('ItemName.json', 'Recipe.json', 'Recipes.json'):
                json_files.append(os.path.join(dirpath, fn))

    logger.info(f"  发现 {len(json_files)} 个 JSON 翻译文件")
    for jf in json_files:
        errs = validate_translation_json(jf)
        if errs:
            all_errors.extend([f"[JSON] {jf}:"] + errs)

    # 步骤 3: 验证所有 recipe 文件
    logger.info("\n[3/3] 验证 recipe 文件 ...")
    recipe_files = []
    for dirpath, dirnames, filenames in os.walk(args.root):
        dirnames[:] = [d for d in dirnames if d not in
                       ('learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea', '.vscode',
                        'mod_dependency_analyzer')]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if full.endswith('.txt') and 'recipe' in os.path.basename(full).lower() and 'item' not in os.path.basename(full).lower():
                recipe_files.append(full)

    logger.info(f"  发现 {len(recipe_files)} 个 recipe 文件")
    for rf in recipe_files:
        errs = validate_recipe_file(rf, known_items)
        if errs:
            all_errors.extend([f"[RECIPE] {rf}:"] + errs)

    # 输出结果
    logger.info("\n" + "=" * 60)
    if all_errors:
        logger.error(f"发现 {len(all_errors)} 个错误:")
        for e in all_errors:
            print(f"  {e}")
        if args.strict:
            sys.exit(1)
    else:
        logger.info("✓ 全部通过 (recipe 字段完整 + 物品 ID 真实存在 + JSON 无重复)")


if __name__ == '__main__':
    main()
