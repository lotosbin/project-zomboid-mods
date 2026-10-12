#!/usr/bin/env python3
"""扫描原版脚本,找出"配方体系里的缺口"。

判据(全部来自游戏自带的脚本,不猜):
  · 消耗 = 某条 craftRecipe 的 inputs 里出现,且**不是** mode:keep / Prop1 / Prop2 / ToolLeft /
    ToolRight 这类"工具位"(工具只是被拿在手里,不算材料)
  · 产出 = 某条 craftRecipe 的 outputs 里直接出现,或出现在它引用的 itemMapper 的**键**上
    (mapper 语义:`输出物品 = 触发它的输入物品`,键是产出、值是消耗 —— 见
     generated/entities/blacksmith/craftRecipes/recipes_blacksmith_bar.txt 的 mappers[metalType])
  · 世界来源 = 拆家具产出(Moveables 的 addScrapItem) / 采集表(Foraging/Categories/*.lua)

缺口分类:
  A. 只能搜刮的材料  : 被配方当材料消耗,但没有任何配方能产出,也没有世界来源
  B. 有世界来源的材料: 同上,但能靠拆家具/采集拿到(不算堵死)
  C. 做得出没人用    : 有配方产出,但没有任何配方把它当材料消耗(成品居多,一般不是缺口)

用法:
    python3 scan_recipe_gaps.py                 # 打印报告
    python3 scan_recipe_gaps.py --json gaps.json
    python3 scan_recipe_gaps.py --top 80 --lang CN
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sys

DEFAULT_GAME = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java")

TOOL_FLAGS = {"Prop1", "Prop2", "ToolLeft", "ToolRight", "HandcraftOnly"}

MODULE_RE = re.compile(r'^\s*module\s+([A-Za-z_]\w*)')
ITEM_RE = re.compile(r'^\s*item\s+([A-Za-z_]\w*)\s*$')
TAGS_RE = re.compile(r'^\s*Tags\s*=\s*([^,\n]+?)\s*,?\s*$')
CRAFT_RE = re.compile(r'^\s*craftRecipe\s+([A-Za-z_]\w*)\s*$')
CAT_RE = re.compile(r'^\s*category\s*=\s*([^,\n]+?)\s*,?\s*$')
SECT_RE = re.compile(r'^\s*(inputs|outputs)\s*$')
ITEMREF_RE = re.compile(r'^\s*item\s+(\d+(?:\.\d+)?)\s+(.+?),?\s*$')
FLUID_RE = re.compile(r'^\s*-fluid\s+([\d.]+)\s+(.+?),?\s*$')
MAPPER_OPEN_RE = re.compile(r'^\s*itemMapper\s+([A-Za-z_]\w*)\s*$')
MAPPER_LINE_RE = re.compile(r'^\s*([A-Za-z_]\w*|\w+\.\w+)\s*=\s*([A-Za-z_]\w*|\w+\.\w+)\s*,?\s*$')
BRACKET_RE = re.compile(r'\[\s*([^\]]+?)\s*\]')
TAGSEL_RE = re.compile(r'tags\[([^\]]+)\]')
FLAGS_RE = re.compile(r'flags\[([^\]]+)\]')
KEYED_BRACKET_RE = re.compile(r'(?:tags|flags|mappers)\[[^\]]*\]')
FULLTYPE_RE = re.compile(r'\b([A-Za-z_]\w*\.[A-Za-z_]\w*)\b')
SCRAP_RE = re.compile(r'addScrapItem\s*\(\s*"([^"]*)"\s*,\s*"([^"]+)"')


def parse_items(scripts_dir):
    """→ {fullType: {"tags": set(), "file": rel}}"""
    items = {}
    for path in glob.glob(os.path.join(scripts_dir, "**", "*.txt"), recursive=True):
        module = None
        current = None
        for line in open(path, encoding="utf-8", errors="replace"):
            m = MODULE_RE.match(line)
            if m:
                module, current = m.group(1), None
                continue
            m = ITEM_RE.match(line)
            if m and module:
                current = f"{module}.{m.group(1)}"
                items.setdefault(current, {"tags": set(), "file": os.path.relpath(path, scripts_dir)})
                continue
            m = TAGS_RE.match(line)
            if m and current:
                items[current]["tags"].update(t.strip() for t in m.group(1).split(";") if t.strip())
    return items


def parse_recipes(scripts_dir):
    """→ [recipe dict]"""
    recipes = []
    for path in glob.glob(os.path.join(scripts_dir, "**", "*.txt"), recursive=True):
        module = None
        rec = None
        section = None
        mapper = None
        for line in open(path, encoding="utf-8", errors="replace"):
            m = MODULE_RE.match(line)
            if m and rec is None:
                module = m.group(1)
                continue
            m = CRAFT_RE.match(line)
            if m:
                rec = {"name": m.group(1), "module": module, "category": None, "tags": [],
                       "inputs": [], "outputs": [], "fluids": [], "mappers": {},
                       "file": os.path.relpath(path, scripts_dir)}
                recipes.append(rec)
                section, mapper = None, None
                continue
            if rec is None:
                continue
            if re.match(r'^\s*\}', line):
                if mapper:
                    mapper = None
                elif section:
                    section = None
                else:
                    rec = None
                continue
            m = MAPPER_OPEN_RE.match(line)
            if m:
                mapper = rec["mappers"].setdefault(m.group(1), {})
                continue
            if mapper is not None:
                m = MAPPER_LINE_RE.match(line)
                if m:
                    mapper[m.group(1)] = m.group(2)
                continue
            m = SECT_RE.match(line)
            if m:
                section = m.group(1)
                continue
            m = CAT_RE.match(line)
            if m and section is None and rec["category"] is None:
                rec["category"] = m.group(1)
                continue
            m = TAGS_RE.match(line)
            if m and section is None:
                rec["tags"] = [t.strip() for t in m.group(1).split(";") if t.strip()]
                continue
            m = FLUID_RE.match(line)
            if m and section == "inputs":
                rec["fluids"].append({"amount": float(m.group(1)), "raw": m.group(2)})
                continue
            m = ITEMREF_RE.match(line)
            if m and section:
                # 数量允许小数(原版有 3 行写成 item 1.0 / 2.0 / 5.0,只认整数会整行漏掉)
                amount = float(m.group(1))
                rec[section].append(parse_input(int(amount) if amount.is_integer() else amount, m.group(2)))
    return recipes


def parse_input(count, selector):
    compact = selector.replace(" ", "")
    entry = {"count": count, "raw": selector, "fts": [], "tags": [], "mappers": [],
             "keep": "mode:keep" in compact, "tool": False}
    flags = FLAGS_RE.search(selector)
    if flags:
        entry["tool"] = any(f.strip() in TOOL_FLAGS for f in flags.group(1).split(";"))
    mappers = re.search(r'mappers\[([^\]]+)\]', selector)
    if mappers:
        entry["mappers"] = [x.strip() for x in mappers.group(1).split(";") if x.strip()]
    # tags[...] / flags[...] / mappers[...] 也带方括号,必须先全部摘掉再找物品列表:
    # 否则 `tags[base:hammer] flags[Prop1]` 会把 Prop1 当物品、`Base.HandScytheBlade flags[IsBlunt]`
    # 会把 IsBlunt 当物品而**漏掉真正的 Base.HandScytheBlade**(假阳性 + 假阴性同时发生)。
    without_keyed = KEYED_BRACKET_RE.sub("", selector)
    bracket = BRACKET_RE.search(without_keyed)
    if bracket:
        entry["fts"] = [x.strip().split(":")[-1] for x in bracket.group(1).split(";")
                        if x.strip() and x.strip() != "*"]   # [*] 是"任意物品"通配,不是物品 ID
    else:
        if "mapper:" in compact:
            entry["mapper_ref"] = compact.split("mapper:")[-1]
        else:
            m = FULLTYPE_RE.search(without_keyed)
            if m:
                entry["fts"] = [m.group(1)]
    tags = TAGSEL_RE.search(selector)
    if tags:
        entry["tags"] = [x.strip() for x in tags.group(1).split(";") if x.strip()]
    return entry


def parse_evolved_recipes(scripts_dir):
    """`media/scripts/generated/evolvedrecipes.txt` 的 evolvedrecipe 块 —— B42 里"往容器里加料做熟食"
    这类产出(米饭锅、糖锅、空罐……)全在这里,不算 craftRecipe,漏掉会把它们误判成"做不出来"。

    块内的映射写作 `基础容器 = 产出`(例如 RicePan 块里 `Base.Saucepan = Base.RicePan` 与
    `ResultItem = Base.RicePan`),所以**值**才是产出。
    → {fullType: set(evolvedrecipe 名)}
    """
    produced = collections.defaultdict(set)
    block_re = re.compile(r'evolvedrecipe\s+([A-Za-z_]\w*)\s*\{(.*?)\n    \}', re.S)
    for path in glob.glob(os.path.join(scripts_dir, "**", "*.txt"), recursive=True):
        text = open(path, encoding="utf-8", errors="replace").read()
        if "evolvedrecipe" not in text:
            continue
        for name, body in block_re.findall(text):
            result = re.search(r'ResultItem\s*=\s*([A-Za-z_]\w*\.[A-Za-z_]\w*)', body)
            if result:
                produced[result.group(1)].add(f"evolvedrecipe:{name}")
            for _key, value in re.findall(r'([A-Za-z_]\w*\.[A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*\.[A-Za-z_]\w*)', body):
                produced[value].add(f"evolvedrecipe:{name}")
    return produced


def parse_world_sources(media_dir):
    """→ {fullType: set(来源说明)}"""
    sources = collections.defaultdict(set)
    moveables = os.path.join(media_dir, "lua/shared/Moveables/ISMoveableDefinitions.lua")
    if os.path.exists(moveables):
        text = open(moveables, encoding="utf-8", errors="replace").read()
        for obj, item in SCRAP_RE.findall(text):
            sources[item].add(f"拆家具({obj})")
    for path in glob.glob(os.path.join(media_dir, "lua/shared/Foraging/**/*.lua"), recursive=True):
        base = os.path.basename(path)
        for m in re.finditer(r'=\s*"(Base\.[A-Za-z_]\w*)"', open(path, encoding="utf-8", errors="replace").read()):
            sources[m.group(1)].add(f"采集({base})")
    return sources


def load_names(media_dir, lang):
    names = {}
    for filename in ("ItemName.json", f"ItemName_{lang}.json"):
        path = os.path.join(media_dir, f"lua/shared/Translate/{lang}", filename)
        if os.path.exists(path):
            try:
                names.update(json.load(open(path, encoding="utf-8")))
            except Exception:
                pass
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=os.environ.get("PZ_GAME_DIR", DEFAULT_GAME))
    ap.add_argument("--json")
    ap.add_argument("--top", type=int, default=50)
    ap.add_argument("--lang", default="CN")
    args = ap.parse_args()

    media = os.path.join(args.game, "media")
    scripts = os.path.join(media, "scripts")
    if not os.path.isdir(scripts):
        sys.exit(f"找不到 {scripts}，用 --game 指定游戏安装目录")

    items = parse_items(scripts)
    recipes = parse_recipes(scripts)
    evolved = parse_evolved_recipes(scripts)
    world = parse_world_sources(media)
    names = load_names(media, args.lang)

    def name(ft):
        return names.get(ft, "") or names.get("ItemName_" + ft, "")

    produced = collections.defaultdict(set)
    consumed = collections.defaultdict(set)
    tool_used = collections.defaultdict(set)
    for rec in recipes:
        for out in rec["outputs"]:
            for ft in out["fts"]:
                produced[ft].add(rec["name"])
            for mapper_name in out.get("mapper_ref", []) if isinstance(out.get("mapper_ref"), list) else ([out["mapper_ref"]] if out.get("mapper_ref") else []):
                for key, value in rec["mappers"].get(mapper_name, {}).items():
                    produced[key if key != "default" else value].add(rec["name"])
        for inp in rec["inputs"]:
            bucket = tool_used if (inp["keep"] or inp["tool"]) else consumed
            for ft in inp["fts"]:
                bucket[ft].add(rec["name"])
            for tag in inp["tags"]:
                for ft, meta in items.items():
                    if tag in meta["tags"]:
                        bucket[ft].add(rec["name"])

    # 同一条 input 里的"可替代品":比如 [Base.Charcoal;Base.CharcoalCrafted;Base.Coke] 里
    # CharcoalCrafted 能造出来,那 Base.Charcoal 就不是缺口(玩家有别的选择)
    entry_ft = collections.defaultdict(list)   # fullType -> [(同一条 input 里的其他 fullType)]
    for rec in recipes:
        for inp in rec["inputs"]:
            if inp["keep"] or inp["tool"]:
                continue
            for ft in inp["fts"]:
                entry_ft[ft].append([other for other in inp["fts"] if other != ft])

    # tags[...] 这种"按标签选料"的输入没有显式兄弟,但**小标签**本身就是等价族:
    # base:thread(6 个成员)里任一都能顶替,而 base:hasmetal(上千个)不算替代关系。
    tag_members = collections.defaultdict(set)
    for ft, meta in items.items():
        for tag in meta["tags"]:
            tag_members[tag].add(ft)
    SMALL_TAG = 12
    for rec in recipes:
        for inp in rec["inputs"]:
            if inp["keep"] or inp["tool"]:
                continue
            for tag in inp["tags"]:
                members = tag_members.get(tag, set())
                if not 0 < len(members) <= SMALL_TAG:
                    continue
                for ft in members:
                    entry_ft[ft].append([other for other in members if other != ft])

    def producible_siblings(ft):
        covered = set()
        for others in entry_ft.get(ft, ()):
            for other in others:
                if other in produced:
                    covered.add(other)
        return covered

    for ft, recipes_ in evolved.items():
        produced[ft].update(recipes_)

    def bucket_of(ft):
        if ft in consumed and ft not in produced:
            covered = producible_siblings(ft)
            if covered:
                return "有替代品的材料"
            return "有世界来源的材料" if ft in world else "真缺口(只能搜刮)"
        if ft in produced and ft not in consumed and ft not in tool_used:
            return "做得出没人用"
        return None

    groups = collections.defaultdict(list)
    for ft in items:
        group = bucket_of(ft)
        if group:
            groups[group].append(ft)
    for group in groups:
        groups[group].sort(key=lambda ft: -len(consumed.get(ft, ())))

    print(f"脚本目录: {scripts}")
    print(f"物品 {len(items)} 个 / craftRecipe {len(recipes)} 条")
    print(f"  被当材料消耗: {len(consumed)}    被当工具使用: {len(tool_used)}    有配方产出: {len(produced)}")
    for group in ("真缺口(只能搜刮)", "有世界来源的材料", "有替代品的材料", "做得出没人用"):
        print(f"  {group}: {len(groups[group])}")

    for group in ("真缺口(只能搜刮)", "有世界来源的材料"):
        print(f"\n=== {group} —— 按被多少条配方消耗排序(前 {args.top}) ===")
        print(f"{'物品':40s} {'名称':20s} {'消耗':>4s}  标签 / 世界来源")
        for ft in groups[group][:args.top]:
            tags = ";".join(t for t in sorted(items[ft]["tags"]) if t.startswith("base:"))[:60]
            extra = ("  世界来源: " + ";".join(sorted(world[ft])[:2])) if ft in world else ""
            print(f"{ft:40s} {name(ft)[:18]:20s} {len(consumed[ft]):4d}  {tags}{extra}")

    if args.json:
        payload = {
            "items": {ft: {"tags": sorted(meta["tags"]), "name": name(ft)} for ft, meta in items.items()},
            "consumed": {ft: sorted(v) for ft, v in consumed.items()},
            "toolUsed": {ft: sorted(v) for ft, v in tool_used.items()},
            "produced": {ft: sorted(v) for ft, v in produced.items()},
            "worldSources": {ft: sorted(v) for ft, v in world.items()},
            "producibleSiblings": {ft: sorted(v) for ft, v in ((f, producible_siblings(f)) for f in consumed) if v},
            "groups": {group: fts for group, fts in groups.items()},
        }
        json.dump(payload, open(args.json, "w"), ensure_ascii=False, indent=1)
        print(f"\n已写出 {args.json}")


if __name__ == "__main__":
    main()
