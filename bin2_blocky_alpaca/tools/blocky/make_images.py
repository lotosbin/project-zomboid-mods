#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CompanionDogsBlockyAlpaca 的图片资产：4 张品种头像 + 模组图标 + 海报 + 工坊预览。

排版与配色**刻意沿用写实羊驼那套**（深色 + 细网格 + 等宽"终端卡片"），
这样两个 addon 在工坊/模组列表里看起来是一家人。

复用写实羊驼的 `make_images.py` 里的字体/网格/贴图工具（import 进来，不复制代码），
只把路径与文案换成方块版。头像构图同理：base 的犬舍头像都是头胸特写，
但方块羊驼的头在竖直脖子的顶端，所以裁切中心要比写实版更靠上一点。

用法：
    python3 make_images.py            # 生成全部图片
    python3 make_images.py --check    # 只校验现有图片的尺寸/体积规则
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ALPACA_TOOLS = os.path.abspath(os.path.join(HERE, "..", "..", "..",
                                            "bin2_companion_alpaca", "tools", "alpaca"))
sys.path.insert(0, ALPACA_TOOLS)

import make_images as AI                      # noqa: E402  字体 / 网格背景 / 文本测量
from PIL import Image, ImageDraw              # noqa: E402

ITEM_DIR = os.path.abspath(os.path.join(HERE, "..", ".."))
MOD_DIR = os.path.join(ITEM_DIR, "Contents", "mods", "CompanionDogsBlockyAlpaca", "42")
GLB = os.path.join(MOD_DIR, "media", "models_X", "Skinned", "BlockyAlpaca_Body.glb")
BODY_TEX_DIR = os.path.join(MOD_DIR, "media", "textures", "Body")
TEX_DIR = os.path.join(MOD_DIR, "media", "textures")
OUT = os.path.join(HERE, "out")
PY = sys.executable
RENDER = os.path.join(ALPACA_TOOLS, "render_glb.py")

BG, TEXT, MUTED, ACCENT, CREAM = AI.BG, AI.TEXT, AI.MUTED, AI.ACCENT, AI.CREAM
CARD_LINE = AI.CARD_LINE

# (品种键, 贴图名, 圆点颜色)  —— 与 Breed.lua / Definitions 的表一一对应
BREEDS = [
    ("blockycream", "BlockyAlpaca",       (238, 228, 206)),
    ("blockybrown", "BlockyAlpaca_Brown", (150, 108, 74)),
    ("blockygray",  "BlockyAlpaca_Gray",  (152, 150, 148)),
    ("blockyspot",  "BlockyAlpaca_Spot",  (228, 216, 194)),
]


def log(msg):
    print(f"[blocky-images] {msg}", flush=True)


def render_portrait(breed_key, texture, size=512, azimuth=-30.0, elevation=12.0):
    """渲染"头 + 竖脖 + 前胸"特写（方块头的裁切中心比写实版更靠上）。"""
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(OUT, f"portrait_{breed_key}.png")
    tex = os.path.join(BODY_TEX_DIR, texture + ".png")
    big = size * 2
    cmd = [PY, RENDER, GLB, tmp, "--size", f"{big}x{big}", "--bg", "transparent",
           "--azimuth", str(azimuth), "--elevation", str(elevation), "--texture", tex]
    import subprocess
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"render failed for {breed_key}: {r.stdout[-300:]} {r.stderr[-300:]}")
    im = Image.open(tmp).convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        x0, y0, x1, y1 = bbox
        w, h = x1 - x0, y1 - y0
        side = int(max(w, h) * 0.74)
        cx = x0 + w * 0.52
        cy = y0 + h * 0.24          # 方块脖子是竖直柱，头在更靠上的位置
        left = int(min(max(cx - side / 2, 0), im.width - side))
        top = int(min(max(cy - side / 2, 0), im.height - side))
        im = im.crop((left, top, left + side, top + side))
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    inner = int(size * 0.94)
    w, h = im.size
    scale = min(inner / w, inner / h)
    im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    canvas.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas.convert("RGB")


def make_portraits():
    out = []
    for key, tex, _ in BREEDS:
        im = render_portrait(key, tex)
        p = os.path.join(TEX_DIR, f"CDPortrait_{key}.png")
        im.save(p, format="PNG", optimize=True)
        log(f"portrait {key:12s} -> {os.path.basename(p)} {os.path.getsize(p)} bytes")
        out.append(p)
    return out


def make_icon():
    """模组列表图标：64x64（与 base/写实羊驼一致）。直接用品种头像缩小 + 细边框。"""
    im = Image.open(os.path.join(TEX_DIR, "CDPortrait_blockycream.png")).convert("RGB")
    small = im.resize((64, 64), Image.LANCZOS)
    d = ImageDraw.Draw(small)
    d.rectangle([0, 0, 63, 63], outline=(32, 40, 52))
    p = os.path.join(MOD_DIR, "icon.png")
    small.save(p, format="PNG", optimize=True)
    log(f"icon -> {os.path.basename(p)} {os.path.getsize(p)} bytes")
    return p


def make_poster(size=512):
    """海报：左栏标题 + 要点，右栏头胸像，底部毛色圆点与依赖。

    与写实羊驼同一套排版约束：文本只占左栏 0.37w，渲染图从 0.44w 起，避免压字。
    """
    im = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(im)
    AI.grid_background(d, size, max(16, size // 24))

    m = int(size * 0.055)
    col_w = int(size * 0.37)
    d.text((m, int(size * 0.065)), "CD: Blocky", font=AI.f_title(int(size * 0.098)), fill=TEXT)
    d.text((m, int(size * 0.163)), "Alpacas", font=AI.f_title(int(size * 0.098)), fill=CREAM)
    d.text((m, int(size * 0.272)), "方块羊驼", font=AI.f_cjk(int(size * 0.072)), fill=CREAM)
    sub = AI.fit_text(d, "voxel breeds for Companion Dogs", AI.f_bold(int(size * 0.036)), col_w)
    d.text((m, int(size * 0.352)), "voxel breeds for Companion Dogs", font=sub, fill=ACCENT)
    d.text((m, int(size * 0.392)), "Build 42 (42.19+)", font=AI.f_mono(int(size * 0.031)), fill=MUTED)

    lines = [
        "23 boxes, 0 assets",
        "same species",
        "same stats & voice",
        "pack animal 2.2x",
        "herbivore",
        "heat sensitive",
    ]
    y = int(size * 0.455)
    for line in lines:
        d.text((m, y), "- " + line, font=AI.f_mono(int(size * 0.028)), fill=TEXT)
        y += int(size * 0.040)

    AI._paste_render(im, os.path.join(OUT, "portrait_blockycream.png"),
                     (int(size * 0.44), int(size * 0.04), int(size * 0.985), int(size * 0.78)))

    r = int(size * 0.021)
    x = m + r
    cy = int(size * 0.845)
    for _, _, c in BREEDS:
        d.ellipse([x - r, cy - r, x + r, cy + r], fill=c, outline=(40, 48, 60))
        x += int(r * 2.5)
    d.text((int(size * 0.44), int(size * 0.828)), "4 blocky fleeces",
           font=AI.f_mono(int(size * 0.029)), fill=MUTED)
    d.line([(m, int(size * 0.90)), (size - m, int(size * 0.90))], fill=CARD_LINE)
    d.text((m, int(size * 0.912)), "REQUIRES Companion Dogs + CD: Alpacas",
           font=AI.f_bold(int(size * 0.031)), fill=ACCENT)
    d.text((m, int(size * 0.955)), "sandbox: Alpaca spawn multiplier",
           font=AI.f_mono(int(size * 0.028)), fill=MUTED)
    return im.convert("RGB")


def make_preview(size=256):
    """工坊预览图（256 正方形；游戏的硬性规则见 pz-workshop-item-publishing 技能）。"""
    im = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(im)
    AI.grid_background(d, size, max(12, size // 16))
    m = int(size * 0.06)
    d.text((m, int(size * 0.06)), "CD: Blocky", font=AI.f_title(int(size * 0.125)), fill=TEXT)
    d.text((m, int(size * 0.175)), "Alpacas", font=AI.f_title(int(size * 0.125)), fill=CREAM)
    d.text((m, int(size * 0.295)), "方块羊驼", font=AI.f_cjk(int(size * 0.095)), fill=CREAM)
    d.text((m, int(size * 0.385)), "voxel add-on", font=AI.f_bold(int(size * 0.058)), fill=ACCENT)
    AI._paste_render(im, os.path.join(OUT, "portrait_blockycream.png"),
                     (int(size * 0.06), int(size * 0.42), size - int(size * 0.04), size - int(size * 0.03)))
    d.line([(m, int(size * 0.945)), (size - m, int(size * 0.945))], fill=CARD_LINE)
    return im.convert("RGB")


def check():
    bad = 0
    rules = [
        (os.path.join(ITEM_DIR, "preview.png"), {256, 512}, 1024000, "工坊预览"),
        (os.path.join(MOD_DIR, "poster.png"), None, 2 * 1024 * 1024, "海报"),
        (os.path.join(MOD_DIR, "icon.png"), {64, 128}, 512 * 1024, "模组图标"),
    ]
    for key, _, _ in BREEDS:
        rules.append((os.path.join(TEX_DIR, f"CDPortrait_{key}.png"), {512}, 1024 * 1024, "品种头像"))
    for path, sizes, maxbytes, what in rules:
        if not os.path.exists(path):
            log(f"check: {what} 缺失 {path}")
            bad += 1
            continue
        im = Image.open(path)
        sz = os.path.getsize(path)
        ok = (sizes is None or (im.width == im.height and im.width in sizes)) and sz <= maxbytes
        if not ok:
            bad += 1
        log(f"check: {what:8s} {os.path.basename(path):32s} {im.width}x{im.height} {sz:>8d} bytes "
            f"{'OK' if ok else 'FAIL'}")
    log(f"check: {len(rules) - bad}/{len(rules)} ok")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--skip-portraits", action="store_true")
    args = ap.parse_args()
    if args.check:
        return 1 if check() else 0
    if not args.skip_portraits:
        make_portraits()
    make_icon()
    p = os.path.join(MOD_DIR, "poster.png")
    make_poster(512).save(p, format="PNG", optimize=True)
    log(f"poster -> {os.path.relpath(p, ITEM_DIR)} {os.path.getsize(p)} bytes")
    p = os.path.join(ITEM_DIR, "preview.png")
    make_preview(256).save(p, format="PNG", optimize=True)
    log(f"preview -> {os.path.relpath(p, ITEM_DIR)} {os.path.getsize(p)} bytes")
    return 1 if check() else 0


if __name__ == "__main__":
    sys.exit(main())
