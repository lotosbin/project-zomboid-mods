"""
recipe_scanner_b42.py: 解析 B42 新式 `craftRecipe X {}` 语法

B42 语法示例:
    module Bin2Recipe
    {
        craftRecipe Bin2MakeCheese
        {
            time = 50,
            timedAction = Making,
            Tags = AnySurfaceCraft,
            category = Cooking,
            inputs
            {
                item 1 [Base.Bowl] mode:keep flags[Prop1],
                item 1 [Base.CheeseCloth],
                item 1 [Base.Milk],
                -fluid 1.0 [Petrol],
            }
            outputs
            {
                item 1 Base.Cheese,
            }
        }
    }

字段:
- time = N           (秒,默认 50)
- timedAction = X
- Tags = A;B;C
- category = X
- inputs { item N [fullType;fullType] mode:keep flags[F1;F2] }
- outputs { item N fullType }
- 液体: -fluid N [FluidID]
"""

import re
from typing import Dict, List, Optional
from dataclasses import dataclass, field


@dataclass
class B42Input:
    """B42 原料/工具描述"""
    item: str               # 物品 fullType (不带 [])
    count: int = 1
    mode: str = "consume"   # consume / keep / destroy
    prop: str = ""          # Prop1 / Prop2 / 多选
    is_fluid: bool = False  # True 表示是液体


@dataclass
class B42Output:
    """B42 产出描述"""
    item: str
    count: int = 1


@dataclass
class B42Recipe:
    """单个 B42 craftRecipe 的解析结果"""
    recipe_id: str
    module: str = ""
    inputs: List[B42Input] = field(default_factory=list)
    outputs: List[B42Output] = field(default_factory=list)
    time: int = 50
    timed_action: str = ""
    category: str = ""
    tags: str = ""
    need_to_learn: bool = False
    on_create: str = ""
    on_test: str = ""


# module 块开始
RE_MODULE_START = re.compile(r"^\s*module\s+(\w+)\s*\{?", re.MULTILINE)

# craftRecipe 块开始
RE_RECIPE_START = re.compile(r"^\s*craftRecipe\s+(\w+)\s*\{", re.MULTILINE)

# 简单字段 (key = value,)
RE_TIME = re.compile(r"^\s*time\s*=\s*(\d+)\s*,?\s*$", re.MULTILINE | re.IGNORECASE)
RE_TIMED_ACTION = re.compile(r"^\s*timedAction\s*=\s*(\w+)\s*,?\s*$", re.MULTILINE | re.IGNORECASE)
RE_TAGS = re.compile(r"^\s*Tags\s*=\s*([^\n,]+(?:;[^,\n]+)*)\s*,?\s*$", re.MULTILINE | re.IGNORECASE)
RE_CATEGORY = re.compile(r"^\s*category\s*=\s*(\w+)\s*,?\s*$", re.MULTILINE | re.IGNORECASE)
RE_NEED_LEARN = re.compile(r"^\s*needTo(?:B|b)eLearn\s*=\s*true\s*,?\s*$", re.MULTILINE | re.IGNORECASE)
RE_ON_CREATE = re.compile(r"^\s*OnCreate\s*=\s*(\S+)\s*,?\s*$", re.MULTILINE)
RE_ON_TEST = re.compile(r"^\s*OnTest\s*=\s*(\S+)\s*,?\s*$", re.MULTILINE)

# inputs/outputs 块边界
RE_INPUTS_START = re.compile(r"^\s*inputs\s*\{", re.MULTILINE | re.IGNORECASE)
RE_OUTPUTS_START = re.compile(r"^\s*outputs\s*\{", re.MULTILINE | re.IGNORECASE)
RE_BLOCK_END = re.compile(r"^\s*\}\s*$", re.MULTILINE)

# item N [Type1;Type2;...] mode:keep flags[Prop1;Prop2]
RE_ITEM_LINE = re.compile(
    r"^\s*item\s+(\d+)\s+"               # item N
    r"\[([^\]]+)\]"                        # [Types]
    r"(\s+mode:\w+)?"                      # mode:keep
    r"(\s+flags\[[^\]]+\])?"               # flags[...]
    r"\s*,?\s*$"
)
# item N Type (无 [], outputs 块用)
RE_OUTPUT_LINE = re.compile(
    r"^\s*item\s+(\d+)\s+(\S+?)\s*,?\s*$"
)
# -fluid N [FluidID]
RE_FLUID_LINE = re.compile(
    r"^\s*-fluid\s+([\d.]+)\s+\[(\w+)\]\s*,?\s*$"
)


def _parse_flags(flags_str: str) -> tuple[str, str]:
    """从 'flags[Prop1;MayDegradeLight]' 提取 mode/prop 信息"""
    mode = "consume"
    prop = ""
    if not flags_str:
        return mode, prop
    flags_str = flags_str.strip()
    m = re.match(r"flags\[(.+)\]", flags_str)
    if m:
        flag_list = m.group(1).split(";")
        if "Prop1" in flag_list:
            prop = "Prop1"
        if "Prop2" in flag_list:
            prop = "Prop2" if not prop else prop + ";Prop2"
    return mode, prop


def _parse_mode(mode_str: str) -> str:
    """从 'mode:keep' 提取 mode"""
    if not mode_str:
        return "consume"
    m = re.match(r"mode:(\w+)", mode_str.strip())
    return m.group(1) if m else "consume"


def _parse_input_line(line: str) -> Optional[B42Input]:
    """解析一行 inputs 块"""
    line = line.strip()
    if not line or line.startswith('//') or line.startswith('#'):
        return None

    # -fluid N [FluidID]
    m = RE_FLUID_LINE.match(line)
    if m:
        fluid_id = m.group(2)
        return B42Input(
            item=fluid_id,
            count=int(float(m.group(1))),  # 升数,可能是 1.0
            mode="consume",
            is_fluid=True
        )

    # item N [Type]
    m = RE_ITEM_LINE.match(line)
    if m:
        count = int(m.group(1))
        types_str = m.group(2)
        # 多个 type 用 ; 分隔,只取第一个
        item = types_str.split(';')[0].strip()
        mode = _parse_mode(m.group(3) or "")
        _, prop = _parse_flags(m.group(4) or "")
        return B42Input(item=item, count=count, mode=mode, prop=prop, is_fluid=False)

    return None


def _parse_output_line(line: str) -> Optional[B42Output]:
    """解析一行 outputs 块"""
    line = line.strip()
    if not line or line.startswith('//') or line.startswith('#'):
        return None
    m = RE_OUTPUT_LINE.match(line)
    if m:
        return B42Output(item=m.group(2), count=int(m.group(1)))
    return None


def _find_block_end(content: str, start: int) -> int:
    """从 start 位置开始,找到匹配的 '}' 位置 (返回 '}' 的索引)"""
    depth = 1
    i = start
    while i < len(content) and depth > 0:
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
        i += 1
    return i - 1  # 返回 '}' 位置


def parse_b42(content: str, default_module: str = "Base") -> List[B42Recipe]:
    """
    解析 B42 风格 .txt 全部 craftRecipe
    """
    results = []

    # 当前 module
    module = default_module
    m_mod = RE_MODULE_START.search(content)
    if m_mod:
        module = m_mod.group(1)

    for m in RE_RECIPE_START.finditer(content):
        recipe_id = m.group(1)
        start = m.end()
        # 找 recipe 块的结束 '}'
        recipe_end = _find_block_end(content, start)
        recipe_block = content[start:recipe_end]

        recipe = B42Recipe(recipe_id=recipe_id, module=module)

        # 解析顶层字段 (在 recipe 块内,但不在 inputs/outputs 子块内)
        # 先抽出 inputs / outputs 块的位置
        m_in = RE_INPUTS_START.search(recipe_block)
        m_out = RE_OUTPUTS_START.search(recipe_block)

        # 顶层字段区域
        if m_in:
            top_level_end = m_in.start()
        elif m_out:
            top_level_end = m_out.start()
        else:
            top_level_end = len(recipe_block)

        top_level = recipe_block[:top_level_end]

        # 解析 time
        m_time = RE_TIME.search(top_level)
        if m_time:
            recipe.time = int(m_time.group(1))

        # 解析 timedAction
        m_ta = RE_TIMED_ACTION.search(top_level)
        if m_ta:
            recipe.timed_action = m_ta.group(1)

        # 解析 Tags
        m_tags = RE_TAGS.search(top_level)
        if m_tags:
            recipe.tags = m_tags.group(1).strip()

        # 解析 category
        m_cat = RE_CATEGORY.search(top_level)
        if m_cat:
            recipe.category = m_cat.group(1)

        # 解析 needToBeLearn
        if RE_NEED_LEARN.search(top_level):
            recipe.need_to_learn = True

        # 解析 OnCreate
        m_oc = RE_ON_CREATE.search(top_level)
        if m_oc:
            recipe.on_create = m_oc.group(1).rstrip(',')

        # 解析 OnTest
        m_ot = RE_ON_TEST.search(top_level)
        if m_ot:
            recipe.on_test = m_ot.group(1).rstrip(',')

        # 解析 inputs 块
        if m_in:
            in_start = m_in.end()
            in_end = _find_block_end(recipe_block, in_start)
            in_block = recipe_block[in_start:in_end]
            for line in in_block.split('\n'):
                inp = _parse_input_line(line)
                if inp:
                    recipe.inputs.append(inp)

        # 解析 outputs 块
        if m_out:
            out_start = m_out.end()
            out_end = _find_block_end(recipe_block, out_start)
            out_block = recipe_block[out_start:out_end]
            for line in out_block.split('\n'):
                out = _parse_output_line(line)
                if out:
                    recipe.outputs.append(out)

        results.append(recipe)

    return results


if __name__ == '__main__':
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else '/Users/liubinbin/Zomboid/Workshop/bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt'
    with open(path) as f:
        content = f.read()
    recipes = parse_b42(content)
    print(f"B42 解析结果: {len(recipes)} 个 recipe")
    for r in recipes:
        print(f"\n=== {r.recipe_id} (module={r.module}, time={r.time}) ===")
        print(f"  tags={r.tags}, category={r.category}, timedAction={r.timed_action}")
        print(f"  inputs:  {[(i.item, i.count, i.mode, i.prop, 'fluid' if i.is_fluid else 'item') for i in r.inputs]}")
        print(f"  outputs: {[(o.item, o.count) for o in r.outputs]}")
