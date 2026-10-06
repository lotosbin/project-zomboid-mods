#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 bin2_npc_extension 的两张图（纯 Pillow 绘制，无需联网）：

  preview.png                                   → 工坊物品预览图，放物品根（游戏 getPreviewImage() 读它）
  Contents/mods/Bin2NPCExtension/42.21/poster.png → 模组列表海报，mod.info 的 poster= 指向它

尺寸是硬约束，不是审美选择。游戏 `zombie.core.znet.SteamWorkshopItem.validatePreviewImage(Path)`：

  1. 存在 / 可读 / 不是目录                → 否则 PreviewNotFound
  2. 文件 <= 1024000 字节                  → 否则 PreviewFileSize
  3. **正方形，边长只能是 256 或 512**     → 否则 PreviewDimensions
  4. 能被 zombie.core.textures.PNGDecoder 解析 → 否则 PreviewFormat（必须是 PNG）

poster.png 不受这条约束，沿用仓库习惯的 512x512。
排版沿用仓库其它模组的观感：深色 + 细网格 + 等宽"终端日志"卡片，橙色 #ff6d14 为强调色
（与橙子社区经济的主色一致）。

用法：
    python3 make_images.py            # 重新生成两张图（会打印每行文字实测宽度）
    python3 make_images.py --check    # 只打印现有图片尺寸与 validatePreviewImage 规则
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)                       # bin2_npc_extension/
MOD_VERSION = os.environ.get("MOD_VERSION", "42.21")
MODS_DIR = os.path.join(ITEM_DIR, "Contents", "mods")
OUT_PREVIEW = os.path.join(ITEM_DIR, "preview.png")


def poster_path(mod_id: str) -> str:
    """每个模组自己的海报：mod.info 的 poster= 指向它（四个模组各一张，不再互相复制）。"""
    return os.path.join(MODS_DIR, mod_id, MOD_VERSION, "poster.png")


FONT_DIR = "/System/Library/Fonts"
SUPP = os.path.join(FONT_DIR, "Supplemental")

BG = (18, 21, 26)
GRID = (30, 40, 52)
CARD = (11, 15, 20)
CARD_LINE = (34, 48, 60)
ACCENT = (255, 109, 20)          # #ff6d14（橙子社区经济的强调色）
ORANGE = ACCENT                  # 海报里三个口味各自的强调色（见下面的 FLAVOURS）
TEXT = (232, 238, 245)
MUTED = (139, 152, 168)
GREEN = (127, 209, 138)
GOLD = (255, 173, 38)
STEEL = (110, 168, 255)

# ----------------------------------------------------------------- 四个口味的海报
# 一个工坊物品里现在是四个模组（公共层 + 三个口味）。以前三个口味共用同一张海报，
# 在游戏模组列表里根本分不出谁是谁；这里每张海报带上自己的强调色、依赖模组和入口说明。
FLAVOURS = {
    "Bin2NPCExtension": {
        "accent": ACCENT,
        "pill": "A-LIFE x JEEM x ORANGE ECONOMY",
        "tagline": "橙子社区经济 · 佣兵中介",
        "rows": [
            ("$ npc hire --uid palife:0042", MUTED, False),
            ("[Bin2NPCExtension] spawned friendly npc", MUTED, False),
            ("[Bin2NPCExtension] follow order accepted", MUTED, False),
            ("paid 500.00  |  wage 20.00 / day", GOLD, False),
        ],
        "active": "contract active: follow / guard / resident",
        "footer": "社区货币雇佣 · 日薪 · 居民 / 守卫 / 跟随",
        "entry": "入口：经济窗口首页「NPC 招募」/ Ctrl+Alt+N",
    },
    "Bin2NPCExtensionYese": {
        "accent": GOLD,
        "pill": "A-LIFE x JEEM x YESEMARKET",
        "tagline": "YeseMarket · 金币中介",
        "rows": [
            ("$ npc hire --uid palife:0042", MUTED, False),
            ("[Bin2NPCExtensionYese] spawned friendly npc", MUTED, False),
            ("[Bin2NPCExtensionYese] follow order accepted", MUTED, False),
            ("paid 500 coins  |  wage 20 / day", GOLD, False),
        ],
        "active": "contract active: follow / guard / resident",
        "footer": "金币雇佣 · 日薪 · 居民 / 守卫 / 跟随",
        "entry": "入口：YeseMarket 导航栏「NPC 招募」/ Ctrl+Alt+N",
    },
    "Bin2NPCExtensionVanilla": {
        "accent": GREEN,
        "pill": "A-LIFE x JEEM x VANILLA CASH",
        "tagline": "纯原版 · 用钞票雇人",
        "rows": [
            ("$ npc hire --cash", MUTED, False),
            ("[Bin2NPCExtensionVanilla] spawned friendly npc", MUTED, False),
            ("[Bin2NPCExtensionVanilla] broke a bundle, gave change", MUTED, False),
            ("paid 50 notes  |  wage 5 / day  (1 bundle = 100)", GOLD, False),
        ],
        "active": "contract active: follow / guard / resident",
        "footer": "原版钞票雇佣 · 一捆钞票 = 100 张",
        "entry": "入口：屏幕左侧 NPC 图标 / Ctrl+Alt+N",
    },
    "Bin2NPCExtensionBase": {
        "accent": STEEL,
        "pill": "PUBLIC LAYER · NO FLAVOUR",
        "tagline": "公共层 · 三个口味共用同一份逻辑",
        "rows": [
            ("[Bin2NPCExtensionCore] namespace bound", MUTED, False),
            ("[Bin2NPCExtensionCore] core API 2", MUTED, False),
            ("[Bin2NPCExtensionCore] money = upstream / cash", MUTED, False),
            ("[Bin2NPCExtensionCore] not a player-facing mod", MUTED, False),
        ],
        "active": "enable one flavour; this layer comes along",
        "footer": "橙子社区经济 / YeseMarket / 原版钞票",
        "entry": "勾选任一 flavour 时游戏会自动一并启用本模组",
    },
}

WARNINGS: list[str] = []


# ----------------------------------------------------------------- 字体

def _font(paths, size):
    for p in paths:
        if os.path.isfile(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def f_title(size):
    return _font([os.path.join(FONT_DIR, "HelveticaNeue.ttc"),
                  os.path.join(FONT_DIR, "Helvetica.ttc"),
                  os.path.join(SUPP, "Arial.ttf")], size)


def f_bold(size):
    return _font([os.path.join(SUPP, "Arial Bold.ttf"),
                  os.path.join(FONT_DIR, "HelveticaNeue.ttc"),
                  os.path.join(SUPP, "Arial.ttf")], size)


def f_mono(size):
    return _font([os.path.join(FONT_DIR, "Menlo.ttc"),
                  os.path.join(SUPP, "Courier New Bold.ttf"),
                  os.path.join(SUPP, "Arial.ttf")], size)


def f_cjk(size):
    return _font([os.path.join(FONT_DIR, "Hiragino Sans GB.ttc"),
                  os.path.join(SUPP, "Arial Unicode.ttf"),
                  os.path.join(SUPP, "Arial.ttf")], size)


# ----------------------------------------------------------------- 绘制助手

def centred(draw, text, y, font, fill, width, strike=False):
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


def tag_pill(draw, size, text, y, size_px, pad, radius, accent=None):
    colour = accent if accent is not None else ACCENT
    font = f_bold(size_px)
    w = draw.textlength(text, font=font)
    if w + pad * 2 > size - 8:
        WARNINGS.append("标签溢出 %.0fpx: %s" % (w + pad * 2, text))
    x0, x1 = (size - w) / 2 - pad, (size + w) / 2 + pad
    y0, y1 = y, y + size_px + pad
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, outline=colour, width=1)
    draw.text(((size - w) / 2, y0 + pad / 2), text, font=font, fill=colour)


# ----------------------------------------------------------------- 海报 512

def render_poster(mod_id: str, size: int = 512) -> Image.Image:
    flavour = FLAVOURS[mod_id]
    accent = flavour["accent"]
    s = size / 512.0
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)

    grid_background(d, size, max(8, int(32 * s)))
    tag_pill(d, size, flavour["pill"], int(26 * s), int(12 * s), int(11 * s), int(6 * s), accent)

    centred(d, "NPC Recruit", int(88 * s), f_title(int(50 * s)), TEXT, size)
    centred(d, flavour["tagline"], int(150 * s), f_cjk(int(20 * s)), MUTED, size)

    bw = int(120 * s)
    d.rectangle([(size - bw) / 2, int(196 * s), (size + bw) / 2, int(201 * s)], fill=accent)

    cx0, cy0, cx1, cy1 = int(30 * s), int(224 * s), size - int(30 * s), int(384 * s)
    d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=int(10 * s), fill=CARD,
                        outline=CARD_LINE, width=max(1, int(1.5 * s)))

    mono = f_mono(int(13 * s))
    lx = cx0 + int(14 * s)
    y = cy0 + int(16 * s)
    for text, colour, strike in flavour["rows"]:
        left(d, text, lx, y, mono, colour, cx1 - int(10 * s), strike)
        y += int(26 * s)
    left(d, flavour["active"], lx, y + int(8 * s), mono, GREEN, cx1 - int(10 * s))

    centred(d, "Project A-Life  ·  Jeem Extension  ·  Build 42", int(420 * s),
            f_bold(int(15 * s)), MUTED, size)
    centred(d, flavour["footer"], int(452 * s), f_cjk(int(15 * s)), MUTED, size)
    centred(d, flavour["entry"], int(478 * s), f_cjk(int(13 * s)), accent, size)
    return img


# ----------------------------------------------------------------- 工坊预览 256

def render_preview(size: int = 256) -> Image.Image:
    """游戏只接受正方形且边长 256/512 的 preview.png；这里用 256，所以文案缩短、字号另配。

    这是**物品级**预览：一个物品里四个模组，所以主标题之后直接列三个口味与公共层。
    """
    s = size / 256.0
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)

    grid_background(d, size, max(8, int(16 * s)))
    tag_pill(d, size, "A-LIFE x JEEM x 3 FLAVOURS", int(12 * s), int(8 * s), int(7 * s), int(4 * s), ACCENT)

    centred(d, "NPC Recruit", int(42 * s), f_title(int(26 * s)), TEXT, size)
    centred(d, "一个物品 · 三个口味 + 公共层", int(74 * s), f_cjk(int(12 * s)), MUTED, size)

    bw = int(72 * s)
    d.rectangle([(size - bw) / 2, int(98 * s), (size + bw) / 2, int(101 * s)], fill=ACCENT)

    cx0, cy0, cx1, cy1 = int(12 * s), int(112 * s), size - int(12 * s), int(196 * s)
    d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=int(6 * s), fill=CARD, outline=CARD_LINE, width=1)

    mono = f_mono(int(9 * s))
    lx = cx0 + int(8 * s)
    right = cx1 - int(5 * s)
    rows = [
        ("橙子社区经济版   社区货币", ORANGE, False),
        ("YeseMarket 版     金币", GOLD, False),
        ("原版钞票版        钞票", GREEN, False),
        ("公共层 Bin2NPCExtensionBase", MUTED, False),
    ]
    y = cy0 + int(11 * s)
    for text, colour, strike in rows:
        left(d, text, lx, y, mono, colour, right, strike)
        y += int(16 * s)
    left(d, "每个口味各有独立的存档表与沙盒选项", lx, y + int(4 * s), mono, MUTED, right)

    centred(d, "Build 42  ·  Ctrl+Alt+N", int(214 * s), f_bold(int(11 * s)), MUTED, size)
    centred(d, "橙子经济 / YeseMarket / 原版钞票", int(234 * s), f_cjk(int(11 * s)), MUTED, size)
    return img


# ----------------------------------------------------------------- 入口

TARGETS = [(OUT_PREVIEW, lambda: render_preview(256), 256)] + [
    (poster_path(mod_id), (lambda mid: (lambda: render_poster(mid, 512)))(mod_id), 512)
    for mod_id in sorted(FLAVOURS)
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
