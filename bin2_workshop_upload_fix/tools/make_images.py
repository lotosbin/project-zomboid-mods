#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 bin2_workshop_upload_fix 的两张预览图（纯 Pillow 绘制，无需联网）：

  preview.png                                   → 工坊物品预览图，放工程根（游戏 getPreviewImage() 读它）
  Contents/mods/ZBWorkshopUploadFix/42.21/poster.png
                                                → 模组列表海报，mod.info 的 poster= 指向它

尺寸不是随便定的：游戏 `zombie.core.znet.SteamWorkshopItem.validatePreviewImage(Path)` 的字节码规则是

  1. 必须存在 / 可读 / 不是目录                → 否则 PreviewNotFound
  2. 文件 <= 1024000 字节                      → 否则 PreviewFileSize
  3. **必须正方形，且边长只能是 256 或 512**   → 否则 PreviewDimensions
  4. 能被 zombie.core.textures.PNGDecoder 解析 → 否则 PreviewFormat（即必须是 PNG）

所以 preview.png 用 **256x256**（模组海报 poster.png 不受这条约束，沿用仓库里 512x512 的观感）。
两张图配色/排版与仓库其它模组（bin2_viewpoint/poster.png）一致：深色 + 细网格 + 等宽"终端日志"卡片，
蓝 #4a90e2 为强调色，红/绿分别表示"报错 → 修好"。

用法：
    python3 make_images.py            # 重新生成两张图（会打印每行文字实测宽度，便于确认不溢出）
    python3 make_images.py --check    # 只打印现有图片尺寸与 validatePreviewImage 的规则
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)                       # bin2_workshop_upload_fix/
MOD_VERSION = os.environ.get("MOD_VERSION", "42.21")
OUT_PREVIEW = os.path.join(ITEM_DIR, "preview.png")
OUT_POSTER = os.path.join(ITEM_DIR, "Contents", "mods", "ZBWorkshopUploadFix",
                          MOD_VERSION, "poster.png")

FONT_DIR = "/System/Library/Fonts"
SUPP = os.path.join(FONT_DIR, "Supplemental")

BG = (18, 21, 26)
GRID = (30, 40, 52)
CARD = (11, 15, 20)
CARD_LINE = (34, 48, 60)
ACCENT = (74, 144, 226)          # #4a90e2（仓库惯用蓝）
TEXT = (232, 238, 245)
MUTED = (139, 152, 168)
GREEN = (127, 209, 138)
RED = (226, 100, 95)

WARNINGS: list[str] = []


# ----------------------------------------------------------------- 字体

def _font(paths, size):
    for p in paths:
        if os.path.isfile(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def f_title(size):
    return _font([os.path.join(SUPP, "Arial Black.ttf"),
                  os.path.join(SUPP, "Arial Bold.ttf")], size)


def f_bold(size):
    return _font([os.path.join(SUPP, "Arial Bold.ttf"),
                  os.path.join(SUPP, "Arial.ttf")], size)


def f_mono(size):
    return _font([os.path.join(SUPP, "Courier New Bold.ttf"),
                  os.path.join(SUPP, "Courier New.ttf")], size)


def f_cjk(size):
    return _font([os.path.join(FONT_DIR, "Hiragino Sans GB.ttc"),
                  os.path.join(SUPP, "Arial Unicode.ttf"),
                  os.path.join(SUPP, "Arial.ttf")], size)


# ----------------------------------------------------------------- 绘制助手

def centred(draw, text, y, font, fill, width, strike=False):
    """水平居中画一行；strike=True 时再画一条删除线。返回实测宽度。"""
    w = draw.textlength(text, font=font)
    if w > width:
        WARNINGS.append("溢出 %.0fpx > %dpx: %s" % (w, width, text))
    x = (width - w) / 2
    draw.text((x, y), text, font=font, fill=fill)
    if strike:
        top = y + font.size * 0.62
        draw.rectangle([x - 1, top, x + w + 1, top + max(1, font.size * 0.11)], fill=fill)
    return w


def left(draw, text, x, y, font, fill, max_w, strike=False):
    w = draw.textlength(text, font=font)
    if x + w > max_w:
        WARNINGS.append("溢出 %.0fpx > %dpx: %s" % (x + w, max_w, text))
    draw.text((x, y), text, font=font, fill=fill)
    if strike:
        top = y + font.size * 0.62
        draw.rectangle([x - 1, top, x + w + 1, top + max(1, font.size * 0.11)], fill=fill)
    return w


def grid_background(draw, size, step):
    for gx in range(0, size, step):
        draw.line([(gx, 0), (gx, size)], fill=GRID, width=1)
    for gy in range(0, size, step):
        draw.line([(0, gy), (size, gy)], fill=GRID, width=1)


def tag_pill(draw, size, text, y, size_px, pad, radius):
    font = f_bold(size_px)
    w = draw.textlength(text, font=font)
    x0, x1 = (size - w) / 2 - pad, (size + w) / 2 + pad
    y0, y1 = y, y + size_px + pad
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, outline=ACCENT, width=1)
    draw.text(((size - w) / 2, y0 + pad / 2), text, font=font, fill=ACCENT)


# ----------------------------------------------------------------- 海报 512

def render_poster(size: int = 512) -> Image.Image:
    s = size / 512.0
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)

    grid_background(d, size, max(8, int(32 * s)))
    tag_pill(d, size, "ZOMBIEBUDDY  RUNTIME PATCH", int(26 * s), int(13 * s), int(12 * s), int(6 * s))

    title = f_title(int(52 * s))
    centred(d, "ZB Workshop", int(96 * s), title, TEXT, size)
    centred(d, "Upload Fix", int(156 * s), title, TEXT, size)

    bw = int(120 * s)
    d.rectangle([(size - bw) / 2, int(224 * s), (size + bw) / 2, int(229 * s)], fill=ACCENT)

    # 终端卡片：4 行日志（红=报错，绿=修好后）
    cx0, cy0, cx1, cy1 = int(34 * s), int(258 * s), size - int(34 * s), int(390 * s)
    d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=int(10 * s), fill=CARD,
                        outline=CARD_LINE, width=max(1, int(1.5 * s)))

    mono = f_mono(int(14 * s))
    lx = cx0 + int(14 * s)
    rows = [
        ("$ upload -> steam workshop", MUTED, False),
        ("start update of existing item ID=3811968819", MUTED, False),
        ("error requesting Steam to update the item", RED, True),
    ]
    y = cy0 + int(16 * s)
    for text, colour, strike in rows:
        left(d, text, lx, y, mono, colour, cx1 - int(10 * s), strike)
        y += int(26 * s)
    left(d, "[ZBWorkshopUploadFix] Submit = true", lx, y + int(6 * s), mono, GREEN, cx1 - int(10 * s))

    centred(d, "macOS / Linux  ·  Project Zomboid Build 42", int(438 * s), f_bold(int(15 * s)), MUTED, size)
    centred(d, 'tinyfd 返回「好」≠ "OK"  →  补一次 Submit', int(468 * s), f_cjk(int(14 * s)), MUTED, size)
    return img


# ----------------------------------------------------------------- 工坊预览 256

def render_preview(size: int = 256) -> Image.Image:
    """游戏只接受正方形且边长 256/512 的 preview.png；这里用 256，所以文案缩短、字号另配。"""
    s = size / 256.0
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)

    grid_background(d, size, max(8, int(16 * s)))
    tag_pill(d, size, "ZOMBIEBUDDY PATCH", int(13 * s), int(9 * s), int(9 * s), int(4 * s))

    title = f_title(int(27 * s))
    centred(d, "ZB Workshop", int(46 * s), title, TEXT, size)
    centred(d, "Upload Fix", int(78 * s), title, TEXT, size)

    bw = int(72 * s)
    d.rectangle([(size - bw) / 2, int(112 * s), (size + bw) / 2, int(115 * s)], fill=ACCENT)

    cx0, cy0, cx1, cy1 = int(14 * s), int(128 * s), size - int(14 * s), int(206 * s)
    d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=int(6 * s), fill=CARD, outline=CARD_LINE, width=1)

    mono = f_mono(int(10 * s))
    lx = cx0 + int(9 * s)
    right = cx1 - int(6 * s)
    rows = [
        ("$ upload -> workshop", MUTED, False),
        ("start update ID=3811968819", MUTED, False),
        ("error requesting Steam", RED, True),
    ]
    y = cy0 + int(12 * s)
    for text, colour, strike in rows:
        left(d, text, lx, y, mono, colour, right, strike)
        y += int(16 * s)
    left(d, "patched: Submit = true", lx, y + int(5 * s), mono, GREEN, right)

    centred(d, "macOS / Linux  ·  Build 42", int(218 * s), f_bold(int(11 * s)), MUTED, size)
    centred(d, 'tinyfd「好」≠ "OK"', int(236 * s), f_cjk(int(10 * s)), MUTED, size)
    return img


# ----------------------------------------------------------------- 入口

TARGETS = [
    (OUT_PREVIEW, lambda: render_preview(256), 256),
    (OUT_POSTER, lambda: render_poster(512), 512),
]


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 preview.png(256) / poster.png(512)")
    ap.add_argument("--check", action="store_true", help="只打印现有图片尺寸")
    args = ap.parse_args()

    if args.check:
        for path, _, size in TARGETS:
            if os.path.isfile(path):
                with Image.open(path) as im:
                    print("%s  %dx%d  %d bytes" % (path, im.width, im.height, os.path.getsize(path)))
            else:
                print("%s  (缺失)" % path)
        print("\nvalidatePreviewImage 规则: 存在/可读 + <=1024000 字节 + 正方形且边长 256 或 512 + PNG")
        return 0

    for path, render, size in TARGETS:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img = render()
        if img.size != (size, size):
            print("ERROR: %s 尺寸 %s != %dx%d" % (path, img.size, size, size), file=sys.stderr)
            return 1
        img.save(path, "PNG", optimize=True)
        print("wrote %s  %dx%d  %d bytes" % (path, size, size, os.path.getsize(path)))

    if WARNINGS:
        print("\n文字溢出告警：")
        for w in WARNINGS:
            print("  " + w)
        return 1
    print("\n所有文字均在画布内")
    return 0


if __name__ == "__main__":
    sys.exit(main())
