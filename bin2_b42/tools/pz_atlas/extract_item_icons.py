#!/usr/bin/env python3
"""从游戏自带的贴图包里导出物品图标(真实游戏素材,不是截图也不是重绘)。

用途:写更新公告 / 小红书笔记时,要画"配方消耗了什么、产出了什么",需要物品图标。
游戏里物品图标**没有独立的 png 文件** —— B42 把它们打包进
`<游戏>/media/texturepacks/UI*.pack`(PZPK 格式:一张雪碧图 + 一张名称索引表,
索引表紧挨在它所属的那张雪碧图前面)。本脚本按物品脚本里的 `Icon=` 值定位并裁出图标。

```
# 导出某几条配方里出现的全部物品图标(推荐:自动展开 tags[...] 与 [A;B] 多选)
python3 extract_item_icons.py --recipes <recipes.txt> --out <目录>

# 按物品 fullType 导出
python3 extract_item_icons.py --items Base.NutsBolts,Base.Glue --out <目录>

# 直接按贴图名导出(名字 = 物品脚本的 Icon= 值,前面加 Item_)
python3 extract_item_icons.py --icons Item_NutsBolts,Item_Sawblade --out <目录>
```

输出:`<out>/<贴图名>.png`(游戏原生 32x32 画布)、`<out>/<贴图名>@4x.png`(最近邻放大,给图文
平台用不糊)、`<out>/manifest.json`(贴图 → 尺寸 / 所在包 / 对应物品 fullType 与中文名)。

依赖 Pillow(合成透明画布 + 放大)。本机可用 DSH 自带的 python:
`~/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3`

格式细节(实测 UI.pack / UI2.pack 都成立,见 docs/craft-recipe-study.md 第 14.8 节):
    magic "PZPK"                     4 字节;UI.pack 这类老包直接以记录开头
    记录 = uint32 名称长度 + 名称 + 8 个 uint32:
           x, y, w, h        雪碧图里的裁剪矩形
           offX, offY        画回原尺寸画布时的偏移
           origW, origH      原始画布尺寸(物品图标通常是 32x32)
    页码 = 该记录之后最近的那个 PNG —— 每张雪碧图前面紧跟着它自己的名称表
"""
from __future__ import annotations

import argparse
import collections
import glob
import io
import json
import os
import re
import struct
import sys

DEFAULT_GAME = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java")

CRAFT_ITEM_RE = re.compile(r'^\s*item\s+\d+\s+(.+?),?\s*$')
TAGSEL_RE = re.compile(r'tags\[([^\]]+)\]')
FULLTYPE_RE = re.compile(r'\b([A-Za-z_]\w*\.[A-Za-z_]\w*)\b')
SMALL_TAG = 12


# ---------------------------------------------------------------- 贴图包解析

def png_offsets(data):
    """包内所有 PNG 的起始偏移(图标雪碧图内嵌在包里,没有独立文件)"""
    out, i = [], data.find(b'\x89PNG')
    while i >= 0:
        out.append(i)
        i = data.find(b'\x89PNG', i + 4)
    return out


def find_sprite(data, pages, name):
    """按名字定向查一条 sprite 记录。

    记录 = uint32 名称长度 + 名称 + 8 个 uint32,所以"名称前 4 字节 == 名称长度"是可靠指纹;
    用 find 定位比逐字节扫全表快一个数量级(UI2.pack 有 54 MB)。
    返回 (x, y, w, h, offX, offY, origW, origH, png 偏移) 或 None。
    """
    blob = name.encode()
    start = 0
    while True:
        i = data.find(blob, start)
        if i < 0:
            return None
        start = i + 1
        if i < 4 or struct.unpack_from('<I', data, i - 4)[0] != len(blob):
            continue
        vals = struct.unpack_from('<8I', data, i + len(blob))
        x, y, w, h, off_x, off_y, orig_w, orig_h = vals
        if not (0 <= x < 8192 and 0 <= y < 8192 and 0 < w <= 512 and 0 < h <= 512
                and 0 < orig_w <= 512 and 0 < orig_h <= 512):
            continue
        page = next((o for o in pages if o > i), None)
        return vals + (page,) if page is not None else None


def lookup_sprites(game_dir, pattern, wanted):
    """→ {sprite 名: (包路径, 记录)};只读需要的包,按名字定向查"""
    found = {}
    packs = sorted(glob.glob(os.path.join(game_dir, "media", "texturepacks", pattern)))
    if not packs:
        sys.exit(f"在 {game_dir}/media/texturepacks 下找不到匹配 {pattern} 的贴图包")
    for pack in packs:
        todo = wanted - set(found)
        if not todo:
            break
        data = open(pack, 'rb').read()
        pages = png_offsets(data)
        for name in sorted(todo):
            rect = find_sprite(data, pages, name)
            if rect:
                found[name] = (pack, rect)
    return found


def load_page(pack_path, page_offset):
    from PIL import Image
    data = open(pack_path, 'rb').read()
    end = data.find(b'IEND', page_offset)
    return Image.open(io.BytesIO(data[page_offset:end + 8])).convert("RGBA")


# ---------------------------------------------------------------- 物品脚本

def parse_item_scripts(game_dir):
    """→ ({fullType: Icon 名}, {tag: {fullType}}, {fullType: 中文名})"""
    icons, tags = {}, collections.defaultdict(set)
    state = {"module": None, "name": None, "icon": None, "tags": None}

    def flush():
        if state["name"] is None:
            return
        full = f"{state['module']}.{state['name']}"
        if state["icon"]:
            icons[full] = state["icon"]
        if state["tags"]:
            for tag in state["tags"].split(';'):
                tag = tag.strip()
                if tag:
                    tags[tag].add(full)

    for path in glob.glob(os.path.join(game_dir, "media", "scripts", "**", "*.txt"), recursive=True):
        for line in open(path, encoding="utf-8", errors="replace"):
            m = re.match(r'\s*module\s+(\w+)', line)
            if m:
                flush()
                state.update(module=m.group(1), name=None, icon=None, tags=None)
                continue
            m = re.match(r'\s*item\s+(\w+)\s*$', line)
            if m:
                flush()
                state.update(name=m.group(1), icon=None, tags=None)
                continue
            m = re.match(r'\s*Icon\s*=\s*([\w\-\.]+)', line)
            if m:
                state["icon"] = m.group(1)
                continue
            m = re.match(r'\s*Tags\s*=\s*([^,\n]+)', line)
            if m:
                state["tags"] = m.group(1)
        flush()
        state.update(module=None, name=None, icon=None, tags=None)

    names = {}
    path = os.path.join(game_dir, "media", "lua", "shared", "Translate", "CN", "ItemName.json")
    if os.path.exists(path):
        try:
            names.update(json.load(open(path, encoding="utf-8")))
        except Exception:
            pass
    return icons, tags, names


def items_from_recipes(recipe_files, tags):
    """配方脚本里被引用的全部 fullType(tags[...] 展开成小标签的成员;大标签不算等价族)"""
    wanted = set()
    for path in recipe_files:
        for line in open(path, encoding="utf-8", errors="replace"):
            if not CRAFT_ITEM_RE.match(line) and '-fluid' not in line:
                continue
            for tag in TAGSEL_RE.findall(line):
                for one in tag.split(';'):
                    members = tags.get(one.strip(), set())
                    if 0 < len(members) <= SMALL_TAG:
                        wanted |= members
            wanted |= set(FULLTYPE_RE.findall(line))
    return wanted


# ---------------------------------------------------------------- 导出

def export(found, out_dir, scale, previous=None):
    """previous: 已有的 manifest(增量导出时保留上次导出的条目,不把目录里的记录冲掉)"""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    pages = {}
    manifest = dict(previous or {})
    for sprite, (pack, rect) in sorted(found.items()):
        x, y, w, h, off_x, off_y, orig_w, orig_h, page_offset = rect
        key = (pack, page_offset)
        if key not in pages:
            pages[key] = load_page(pack, page_offset)
        canvas = Image.new("RGBA", (orig_w, orig_h), (0, 0, 0, 0))
        canvas.paste(pages[key].crop((x, y, x + w, y + h)), (off_x, off_y))
        canvas.save(os.path.join(out_dir, f"{sprite}.png"))
        if scale > 1:
            canvas.resize((orig_w * scale, orig_h * scale), Image.NEAREST).save(
                os.path.join(out_dir, f"{sprite}@{scale}x.png"))
        manifest[sprite] = {"pack": os.path.basename(pack), "size": [orig_w, orig_h],
                            "rect": [x, y, w, h], "items": []}
    return manifest


def make_sheet(found, manifest, out_dir, out_path, font_path, scale):
    """把导出的图标拼成一张总览图(带中文名),方便一眼挑图"""
    import math
    from PIL import Image, ImageDraw, ImageFont
    cells = []
    for sprite in sorted(found):
        cn = " / ".join(i["cn"] or i["fullType"] for i in manifest[sprite]["items"]) or sprite
        cells.append((sprite, cn))
    cols = 8
    cell = 32 * scale + 42
    rows = math.ceil(len(cells) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (24, 26, 32, 255))
    draw = ImageDraw.Draw(sheet)
    font = None
    for candidate in ([font_path] if font_path else []) + [
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"]:
        if candidate and os.path.exists(candidate):
            try:
                font = ImageFont.truetype(candidate, 13)
                break
            except Exception:
                continue
    for n, (sprite, cn) in enumerate(cells):
        name = f"{sprite}@{scale}x.png" if scale > 1 else f"{sprite}.png"
        icon = Image.open(os.path.join(out_dir, name))
        x = (n % cols) * cell + (cell - icon.width) // 2
        y = (n // cols) * cell + 8
        sheet.paste(icon, (x, y), icon)
        if font:
            width = draw.textlength(cn, font=font)
            draw.text(((n % cols) * cell + (cell - width) / 2, (n // cols) * cell + cell - 24),
                      cn, fill=(228, 228, 234), font=font)
    sheet.convert("RGB").save(out_path)
    return sheet.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=os.environ.get("PZ_GAME_DIR", DEFAULT_GAME))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "exports"))
    ap.add_argument("--packs", default="UI*.pack", help="贴图包通配符(图标在 UI*.pack 里)")
    ap.add_argument("--recipes", nargs="*", default=[])
    ap.add_argument("--items", default="")
    ap.add_argument("--icons", default="")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--sheet", default="", help="额外输出一张带中文名的总览图")
    ap.add_argument("--font", default="", help="总览图用的字体(默认 macOS 冬青黑/ Arial Unicode)")
    args = ap.parse_args()

    if not os.path.isdir(os.path.join(args.game, "media", "texturepacks")):
        sys.exit(f"找不到 {args.game}/media/texturepacks,用 --game 指定游戏安装目录")

    icons, tags, names = parse_item_scripts(args.game)

    full_types = {f.strip() for f in args.items.split(",") if f.strip()}
    if args.recipes:
        full_types |= items_from_recipes(args.recipes, tags)
    full_types = {f if '.' in f else f"Base.{f}" for f in full_types}

    sprites = {s.strip() for s in args.icons.split(",") if s.strip()}
    no_icon = []
    for full in sorted(full_types):
        icon = icons.get(full)
        if not icon:
            no_icon.append(full)
            continue
        sprites.add(icon if icon.startswith("Item_") else f"Item_{icon}")

    found = lookup_sprites(args.game, args.packs, sprites)
    manifest_path = os.path.join(args.out, "manifest.json")
    previous = {}
    if os.path.exists(manifest_path):            # 增量导出:保留目录里已有的条目
        try:
            previous = json.load(open(manifest_path, encoding="utf-8"))
        except Exception:
            previous = {}
    manifest = export(found, args.out, args.scale, previous)
    for full in sorted(full_types):
        icon = icons.get(full)
        if not icon:
            continue
        sprite = icon if icon.startswith("Item_") else f"Item_{icon}"
        if sprite in manifest:
            manifest[sprite]["items"].append({"fullType": full, "cn": names.get(full, "")})
    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    print(f"请求 {len(sprites)} 个图标,导出 {len(manifest)} 个 → {args.out}")
    if args.sheet:
        size = make_sheet(found, manifest, args.out, args.sheet, args.font, args.scale)
        print(f"总览图 {size[0]}x{size[1]} → {args.sheet}")
    for sprite in sorted(sprites - set(found)):
        print(f"  !! 贴图包里没找到 {sprite}")
    if no_icon:
        print(f"  {len(no_icon)} 个物品在脚本里没有 Icon 字段: {', '.join(no_icon[:8])}"
              + (" …" if len(no_icon) > 8 else ""))


if __name__ == "__main__":
    main()
