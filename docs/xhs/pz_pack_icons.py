#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从游戏 `media/texturepacks/*.pack` 里导出物品图标（32×32 + @4x）。

为什么要自己解 pack：`docs/xhs/游戏图标素材/` 里那 47 张是 @bin2_extension_mod_dev 早先
用他的工具导的（工具没进仓库）。做「锻造耙头」这篇笔记时缺 耙头/钉耙/铁条(1/4)/金属加工冲头/长棍
这 5 个图标，所以把格式自己解出来、写成这个脚本，以后缺哪个补哪个。

**pack 格式**（2026-10-13 自己解出来的，用 `Item_Charcoal` 与 manifest 里的 rect 对过账）：
    "PZPK" | int version | int pageCount
    每一页： int nameLen + 页名（如 "UI20"） + int entryCount + int ? +
             entryCount × [ int nameLen + 精灵名 + 8×int32(x, y, w, h, ox, oy, cellW, cellH) ] +
             整页 PNG
    ⇒ 取图 = 在该页 PNG 上裁 `(x, y, w, h)`，贴到 `cellW×cellH` 透明画布上的 `(ox, oy)`。

用法：
    python3 pz_pack_icons.py --list Item_Rake Item_RakeHead        # 只查：在哪一页、rect 是多少
    python3 pz_pack_icons.py --emit Item_RakeHead Item_Punch_Forged
                                      [--out 游戏图标素材] [--packs <目录>]

**它不改 manifest.json**（那里面每条还带 fullType / 中文名，得对着游戏 ItemName.json 人肉确认）；
导完自己去 manifest 里补一条 —— 卡片脚本的自检就是拿 manifest 里的中文名对账的。
"""
import argparse
import glob
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "游戏图标素材")
DEFAULT_PACKS = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/"
    "Project Zomboid.app/Contents/Java/media/texturepacks")
CELL = 32
SCALE = 4


def parse_pack(path):
    """→ [dict(name=页名, entries={精灵名: (x,y,w,h,ox,oy,cellW,cellH)}, png_slice=(start,end))]"""
    with open(path, "rb") as f:
        b = f.read()
    if b[:4] == b"PZPK":
        page_count = struct.unpack_from("<I", b, 0x0C)[0]
        p = 0x0C
    else:
        # 旧格式（UI.pack / IconsMoveables.pack / ApCom.pack …）：没有 magic、没有总页数，
        # 头 4 字节是版本号（UI.pack=8、IconsMoveables.pack=1），一页接一页读到文件尾；
        # 每页 PNG 之后跟一个 4 字节分隔符 0xDEADBEEF（2026-10-14 解 Item_Paper/Item_Plank 时试出来的）。
        # 页内结构与 PZPK 相同（nameLen / name / entryCount / 4 字节 / entryCount×条目）。
        page_count = None
        p = 0x04
    pages = []
    while p < len(b) and (page_count is None or len(pages) < page_count):
        if p + 8 > len(b):
            break
        name_len = struct.unpack_from("<I", b, p)[0]
        if not 0 < name_len < 64:
            break
        name = b[p + 4:p + 4 + name_len].decode("ascii", "replace")
        q = p + 4 + name_len
        entry_count = struct.unpack_from("<I", b, q)[0]
        q += 8
        entries = {}
        for _ in range(entry_count):
            l2 = struct.unpack_from("<I", b, q)[0]
            sprite = b[q + 4:q + 4 + l2].decode("ascii", "replace")
            entries[sprite] = struct.unpack_from("<8i", b, q + 4 + l2)
            q += 4 + l2 + 32
        start = b.find(b"\x89PNG\r\n\x1a\n", q)
        if start < 0:
            break
        end = b.find(b"IEND", start) + 8
        pages.append(dict(name=name, entries=entries, png_slice=(start, end)))
        p = end
        if page_count is None and b[p:p + 4] == b"\xef\xbe\xad\xde":   # 旧格式的页尾分隔符
            p += 4
    return pages


def find(packs_dir, sprites):
    """→ {精灵名: (pack路径, 页序号, 页名, 字段)}；找不到的进 missing"""
    found, missing = {}, []
    for path in sorted(glob.glob(os.path.join(packs_dir, "*.pack"))):
        try:
            pages = parse_pack(path)
        except Exception:
            continue                                    # 别的 pack 不是这个版本，跳过
        for i, pg in enumerate(pages):
            for s in sprites:
                if s in pg["entries"] and s not in found:
                    found[s] = (path, i, pg["name"], pg["entries"][s])
    for s in sprites:
        if s not in found:
            missing.append(s)
    return found, missing


def emit(found, out_dir):
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    cache, made = {}, []
    for sprite, (path, _i, _pname, f) in sorted(found.items()):
        x, y, w, h, ox, oy, cell_w, cell_h = f
        if path not in cache:
            with open(path, "rb") as fh:
                b = fh.read()
            pages = parse_pack(path)
            cache[path] = (b, pages)
        b, pages = cache[path]
        idx = [j for j, pg in enumerate(pages) if sprite in pg["entries"]][0]
        s, e = pages[idx]["png_slice"]
        import io
        page = Image.open(io.BytesIO(b[s:e])).convert("RGBA")
        cell = Image.new("RGBA", (cell_w or CELL, cell_h or CELL), (0, 0, 0, 0))
        cell.paste(page.crop((x, y, x + w, y + h)), (ox, oy))
        if cell.size != (CELL, CELL):
            cell = cell.resize((CELL, CELL), Image.NEAREST)
        cell.save(os.path.join(out_dir, sprite + ".png"))
        cell.resize((CELL * SCALE, CELL * SCALE), Image.NEAREST).save(
            os.path.join(out_dir, sprite + "@4x.png"))
        made.append(sprite)
    return made


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--packs", default=DEFAULT_PACKS)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--list", nargs="*", metavar="SPRITE")
    ap.add_argument("--emit", nargs="*", metavar="SPRITE")
    a = ap.parse_args()
    sprites = a.list if a.list else (a.emit or [])
    if not sprites:
        ap.error("给 --list 或 --emit 一个精灵名")
    found, missing = find(a.packs, sprites)
    for s in sprites:
        if s in found:
            path, i, pname, f = found[s]
            print("%-24s %s 页%d(%s)  rect=%s" % (s, os.path.basename(path), i, pname, f))
        else:
            print("%-24s 没找到（换 pack 目录？或这名字不是精灵名——物品的精灵名看 mod.info/物品定义的 Icon=）" % s)
    if a.emit:
        if missing:
            print("✗ 缺 %s，什么都没导（避免半套图标）" % "、".join(missing))
            return 1
        made = emit(found, a.out)
        print("已导出到 %s：%s" % (a.out, "、".join(made)))
        print("⚠ 记得去 manifest.json 补这些精灵的 fullType / 中文名（卡片脚本的自检靠它）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
