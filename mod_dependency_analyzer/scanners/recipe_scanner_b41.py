"""
recipe_scanner_b41.py: 解析 B41 旧式 `recipe X {}` 语法

B41 语法示例 (Recipes.txt):
    module Bin2Recipe
    {
        recipe DisassembleCrudeWoodenTongs
        {
            CrudeWoodenTongs,
            Result:ShortBat=2,
            Result:RippedSheets=1,
            Time:5.0,
            OnGiveXP:Recipe_GiveXP,
        }
    }

字段:
- 原料:  `ItemName,`           (无前缀,数量默认 1)
- 产出:  `Result:ItemName=N,`  (N 为数量)
- 工具:  `keep ItemName` / `destroy ItemName`
- 时间:  `Time:N`
- 经验:  `OnGiveXP:FuncName`
- 占用:  `Prop1:Item` / `Prop2:Item`
- 动画:  `AnimNode:NodeName`
"""

import re
from typing import Dict, List, Optional
from dataclasses import dataclass, field


@dataclass
class B41Input:
    """B41 原料/工具描述"""
    item: str               # 物品 fullType
    count: int = 1
    mode: str = "consume"   # consume / keep / destroy
    prop: str = ""          # Prop1 / Prop2


@dataclass
class B41Output:
    """B41 产出描述"""
    item: str
    count: int = 1


@dataclass
class B41Recipe:
    """单个 B41 recipe 的解析结果"""
    recipe_id: str
    module: str = ""
    inputs: List[B41Input] = field(default_factory=list)
    outputs: List[B41Output] = field(default_factory=list)
    time: float = 50.0
    on_give_xp: str = ""
    anim_node: str = ""


# module 块开始
RE_MODULE_START = re.compile(r"^\s*module\s+(\w+)\s*\{?", re.MULTILINE)

# recipe 块开始: `recipe ID {`
RE_RECIPE_START = re.compile(r"^\s*recipe\s+(\w+)\s*\{", re.MULTILINE)

# Result:Item=Count
RE_RESULT = re.compile(r"^\s*Result:(\w+)\s*=\s*(\d+)\s*,?\s*$", re.MULTILINE)

# Time:N
RE_TIME = re.compile(r"^\s*Time:\s*([\d.]+)\s*,?\s*$", re.MULTILINE)

# OnGiveXP:Func
RE_XP = re.compile(r"^\s*OnGiveXP:\s*(\S+)\s*,?\s*$", re.MULTILINE)

# AnimNode:Node
RE_ANIM = re.compile(r"^\s*AnimNode:\s*(\S+)\s*,?\s*$", re.MULTILINE)

# keep Item / destroy Item
RE_KEEP_DESTROY = re.compile(r"^\s*(keep|destroy)\s+(\w+)\s*,?\s*$", re.MULTILINE)

# Prop1:Item / Prop2:Item
RE_PROP = re.compile(r"^\s*Prop([12]):\s*(\w+)\s*,?\s*$", re.MULTILINE)


def parse_b41(content: str, default_module: str = "Base") -> List[B41Recipe]:
    """
    解析 B41 风格 .txt 全部 recipe
    """
    results = []

    # 提取当前 module 名字 (用于跨 module 引用)
    module = default_module
    m_mod = RE_MODULE_START.search(content)
    if m_mod:
        module = m_mod.group(1)

    # 找出所有 recipe 块的范围
    for m in RE_RECIPE_START.finditer(content):
        recipe_id = m.group(1)
        start = m.end()

        # 找到匹配的 '}' (按括号配对)
        depth = 1
        i = start
        while i < len(content) and depth > 0:
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
            i += 1
        block = content[start:i-1]

        # 解析块内
        recipe = B41Recipe(recipe_id=recipe_id, module=module)
        seen_items = set()  # 用于去重 (keep/destroy 优先于默认)

        for line in block.split('\n'):
            line_stripped = line.strip()
            if not line_stripped:
                continue

            # Result:Item=Count
            m_res = RE_RESULT.match(line)
            if m_res:
                recipe.outputs.append(B41Output(item=m_res.group(1), count=int(m_res.group(2))))
                continue

            # Time
            m_time = RE_TIME.match(line)
            if m_time:
                recipe.time = float(m_time.group(1))
                continue

            # OnGiveXP
            m_xp = RE_XP.match(line)
            if m_xp:
                # 去掉末尾的逗号
                recipe.on_give_xp = m_xp.group(1).rstrip(',')
                continue

            # AnimNode
            m_anim = RE_ANIM.match(line)
            if m_anim:
                recipe.anim_node = m_anim.group(1)
                continue

            # keep / destroy
            m_kd = RE_KEEP_DESTROY.match(line)
            if m_kd:
                mode = m_kd.group(1)
                item = m_kd.group(2)
                recipe.inputs.append(B41Input(item=item, count=1, mode=mode))
                seen_items.add(item)
                continue

            # Prop1/Prop2
            m_prop = RE_PROP.match(line)
            if m_prop:
                item = m_prop.group(2)
                prop = f"Prop{m_prop.group(1)}"
                # 标记主手/副手占用
                for inp in recipe.inputs:
                    if inp.item == item:
                        inp.prop = prop
                continue

            # 默认原料:  `ItemName,` (排除已知关键字)
            if line_stripped.endswith(','):
                item = line_stripped.rstrip(',').strip()
                if (item and not item.startswith('//') and not item.startswith('#')
                        and item not in seen_items):
                    recipe.inputs.append(B41Input(item=item, count=1, mode="consume"))
                    seen_items.add(item)

        results.append(recipe)

    return results


if __name__ == '__main__':
    # 自测:用 bin2_extension 42.15.0 的 Recipes.txt
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else '/Users/liubinbin/Zomboid/Workshop/bin2_b42/Contents/mods/bin2_extension/42.15.0/media/scripts/Recipes.txt'
    with open(path) as f:
        content = f.read()
    recipes = parse_b41(content)
    print(f"B41 解析结果: {len(recipes)} 个 recipe")
    for r in recipes:
        print(f"\n=== {r.recipe_id} (module={r.module}, time={r.time}) ===")
        print(f"  inputs:  {[(i.item, i.count, i.mode, i.prop) for i in r.inputs]}")
        print(f"  outputs: {[(o.item, o.count) for o in r.outputs]}")
        if r.on_give_xp:
            print(f"  on_give_xp: {r.on_give_xp}")
