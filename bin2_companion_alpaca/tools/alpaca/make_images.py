"""生成 CompanionDogsAlpaca 用到的全部图片（可复现，纯本地：离线渲染器 + Pillow）。

产物与用途：
  Contents/mods/CompanionDogsAlpaca/42/media/textures/CDPortrait_<breed>.png
      犬舍/档案卡头像。名字规则来自 base：CompanionDogs_KennelUI.lua 用
      `"media/textures/CDPortrait_" .. breedKey .. ".png"`，所以文件名是**品种键**
      （alpaca / alpacafawn / ...），不是引擎品种名。
  .../media/textures/CDAlpaca_Moodle_Fleece_<32..128>.png
  .../media/textures/CDAlpaca_MoodFleeceFG_<32..128>.png
      moodle 图标与前景。base 的 loadIcon() 组合 `media/textures/<名>_<尺寸>.png`，
      尺寸必须 6 个都有（32/48/64/80/96/128），缺一个就是空方块；
      底框用原版 `media/ui/Moodles/<尺寸>/_Moodles_BGsolid.png` 并按 tintR/G/B 染色，
      所以 fg 是"叠在染色底框上的白色/浅色图形"。
  .../media/textures/CDAlpacaHoof_<尺寸>.png / CDAlpacaHoofDead_<尺寸>.png
      背包图标（偶蹄）。base 用 CDDogPaw_64；这是本模组自己的版本。
  Contents/mods/CompanionDogsAlpaca/42/icon.png      模组列表图标（base 与猫都是 64x64）
  Contents/mods/CompanionDogsAlpaca/42/poster.png    模组海报，mod.info 的 poster= 指向它（512x512）
  bin2_companion_alpaca/preview.png                  工坊预览图，256x256（validatePreviewImage 只接受
                                                     256 或 512 的正方形 PNG，<=1024000 字节）

用法：
  python make_images.py            # 全部重新生成（会调用 render_glb.py 渲染头像）
  python make_images.py --check    # 只校验已有产物的尺寸/模式/体积
  python make_images.py --skip-portraits
"""

import argparse
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.abspath(os.path.join(HERE, "..", ".."))
MOD_DIR = os.path.join(ITEM_DIR, "Contents", "mods", "CompanionDogsAlpaca", "42")
TEX_DIR = os.path.join(MOD_DIR, "media", "textures")
BODY_TEX_DIR = os.path.join(TEX_DIR, "Body")
GLB = os.path.join(MOD_DIR, "media", "models_X", "Skinned", "Alpaca_Body.glb")
RENDER = os.path.join(HERE, "render_glb.py")
OUT = os.path.join(HERE, "out")

PY = sys.executable

# 品种键 -> 毛色图集（与 CompanionDogsAlpaca_Breed.lua / AlpacaDefinitions.lua 一致）
BREEDS = [
    ("alpaca", "Alpaca"),
    ("alpacafawn", "Alpaca_Fawn"),
    ("alpacabrown", "Alpaca_Brown"),
    ("alpacablack", "Alpaca_Black"),
    ("alpacagrey", "Alpaca_Grey"),
    ("alpacarosegrey", "Alpaca_RoseGrey"),
    ("alpacasuri", "Alpaca_Suri"),
]

MOODLE_SIZES = (32, 48, 64, 80, 96, 128)
HOOF_SIZES = (48, 64, 96, 128)

FONT_DIR = "/System/Library/Fonts"
SUPP = os.path.join(FONT_DIR, "Supplemental")

BG = (18, 21, 26)
GRID = (30, 40, 52)
CARD = (11, 15, 20)
CARD_LINE = (34, 48, 60)
ACCENT = (74, 144, 226)
TEXT = (232, 238, 245)
MUTED = (139, 152, 168)
CREAM = (242, 235, 222)
FAWN = (205, 168, 120)
BROWN = (141, 97, 62)
BLACK = (52, 47, 44)
GREY = (166, 163, 158)
ROSE = (178, 156, 150)

WARNINGS = []


def log(msg):
    print(f"[make_images] {msg}", flush=True)


# ----------------------------------------------------------------- 字体 / 文本


def _font(paths, size):
    for p in paths:
        if os.path.isfile(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def f_title(size):
    return _font([os.path.join(SUPP, "Arial Black.ttf"), os.path.join(SUPP, "Arial Bold.ttf")], size)


def f_bold(size):
    return _font([os.path.join(SUPP, "Arial Bold.ttf"), os.path.join(SUPP, "Arial.ttf")], size)


def f_mono(size):
    return _font([os.path.join(SUPP, "Courier New Bold.ttf")], size)


def f_cjk(size):
    return _font([os.path.join(FONT_DIR, "Hiragino Sans GB.ttc"),
                  os.path.join(FONT_DIR, "STHeiti Medium.ttc")], size)


def fit_text(draw, text, font, max_w):
    """返回能塞进 max_w 的字号；塞不下就记录告警（仓库惯例：宁可报出来也不静默溢出）。"""
    size = font.size
    while size > 6 and draw.textlength(text, font=_font_for(font, size)) > max_w:
        size -= 1
    if size != font.size:
        WARNINGS.append(f"text shrunk to {size}px to fit {max_w}px: {text[:40]}")
    return _font_for(font, size)


_FONT_CACHE = {}


def _font_for(font, size):
    key = (getattr(font, "path", "default"), size)
    if key not in _FONT_CACHE:
        p = getattr(font, "path", None)
        _FONT_CACHE[key] = ImageFont.truetype(p, size) if p else ImageFont.load_default()
    return _FONT_CACHE[key]


def grid_background(draw, size, step):
    draw.rectangle([0, 0, size, size], fill=BG)
    for x in range(0, size, step):
        draw.line([(x, 0), (x, size)], fill=GRID, width=1)
    for y in range(0, size, step):
        draw.line([(0, y), (size, y)], fill=GRID, width=1)


# ----------------------------------------------------------------- 头像


def render_portrait(breed_key, texture, size=512, azimuth=-35.0, elevation=10.0):
    """渲染头像：整只渲染后**裁到"头 + 长脖子 + 前胸"**，与 base 的犬舍头像构图一致。

    为什么要裁：base 的头像（CDPortrait_retriever.png 等）都是头胸特写，而不是全身站姿。
    羊驼最有辨识度的就是长脖子 + 立耳 + 钝吻，头胸特写正好把这三样放在画面中央。
    裁剪框用蒙皮的 alpha 外框按比例推（0.60w 见方，中心落在头颈位置），不是硬编码像素。
    """
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(OUT, f"portrait_{breed_key}.png")
    tex = os.path.join(BODY_TEX_DIR, texture + ".png")
    big = size * 2
    cmd = [PY, RENDER, GLB, tmp, "--size", f"{big}x{big}", "--bg", "transparent",
           "--azimuth", str(azimuth), "--elevation", str(elevation), "--texture", tex]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"render failed for {breed_key}: {r.stdout[-400:]} {r.stderr[-400:]}")
    im = Image.open(tmp).convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        x0, y0, x1, y1 = bbox
        w, h = x1 - x0, y1 - y0
        side = int(max(w, h) * 0.62)
        cx = x0 + w * 0.60
        cy = y0 + h * 0.30
        left = int(min(max(cx - side / 2, 0), im.width - side))
        top = int(min(max(cy - side / 2, 0), im.height - side))
        im = im.crop((left, top, left + side, top + side))
    # 贴到白色方图（base 与猫的头像都是白底），留一点边距
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    inner = int(size * 0.94)
    w, h = im.size
    scale = min(inner / w, inner / h)
    im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    canvas.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas.convert("RGB")


# ----------------------------------------------------------------- moodle 图标


def draw_fleece_glyph(size, fg_only):
    """画"一坨羊毛 + 羊驼头"的图标。

    在 4 倍画布上画再降采样，等于免费抗锯齿。fg 版本不加底框（底框由游戏按 tint 染色）。
    """
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (250, 248, 242, 255)
    line = (58, 50, 42, 255)

    if not fg_only:
        pad = int(s * 0.06)
        d.ellipse([pad, pad, s - pad, s - pad], fill=(244, 236, 214, 255), outline=line,
                  width=max(2, int(s * 0.030)))

    # 身体：三个交叠的圆当羊毛团
    body = [(0.32, 0.70, 0.20), (0.50, 0.66, 0.23), (0.68, 0.71, 0.18)]
    for cx, cy, r in body:
        x, y, rr = cx * s, cy * s, r * s
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=ink, outline=line,
                  width=max(2, int(s * 0.022)))
    # 脖子与头
    d.polygon([(0.30 * s, 0.74 * s), (0.40 * s, 0.60 * s), (0.52 * s, 0.44 * s),
               (0.62 * s, 0.52 * s), (0.52 * s, 0.68 * s), (0.44 * s, 0.80 * s)],
              fill=ink, outline=line)
    d.ellipse([0.44 * s, 0.28 * s, 0.70 * s, 0.52 * s], fill=ink, outline=line,
              width=max(2, int(s * 0.022)))
    # 两只香蕉耳
    for ex in (0.47, 0.62):
        d.polygon([(ex * s, 0.34 * s), ((ex + 0.07) * s, 0.34 * s), ((ex + 0.035) * s, 0.15 * s)],
                  fill=ink, outline=line)
    # 眼睛
    d.ellipse([0.52 * s, 0.37 * s, 0.56 * s, 0.41 * s], fill=line)
    d.ellipse([0.61 * s, 0.37 * s, 0.65 * s, 0.41 * s], fill=line)
    return im.resize((size, size), Image.LANCZOS)


def make_moodle_icons():
    written = []
    for size in MOODLE_SIZES:
        for name, fg_only in (("CDAlpaca_Moodle_Fleece", False), ("CDAlpaca_MoodFleeceFG", True)):
            im = draw_fleece_glyph(size, fg_only)
            p = os.path.join(TEX_DIR, f"{name}_{size}.png")
            im.save(p, format="PNG", optimize=True)
            written.append(p)
    return written


# ----------------------------------------------------------------- 偶蹄图标


def draw_hoof(size, dead):
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    top = (208, 196, 178, 255) if not dead else (150, 146, 140, 255)
    bottom = (86, 70, 56, 255) if not dead else (74, 72, 70, 255)
    line = (44, 38, 32, 255)
    w = int(s * 0.022)
    for cx in (0.36, 0.64):
        x0, x1 = (cx - 0.15) * s, (cx + 0.15) * s
        y0, y1 = 0.22 * s, 0.80 * s
        d.rounded_rectangle([x0, y0, x1, y1], radius=int(s * 0.09), fill=bottom, outline=line, width=w)
        d.rounded_rectangle([x0, y0, x1, y0 + (y1 - y0) * 0.42], radius=int(s * 0.09),
                            fill=top, outline=line, width=w)
    if dead:
        d.line([(0.30 * s, 0.34 * s), (0.70 * s, 0.66 * s)], fill=(30, 26, 24, 255),
               width=max(2, int(s * 0.030)))
    return im.resize((size, size), Image.LANCZOS)


def make_hoof_icons():
    written = []
    for size in HOOF_SIZES:
        for name, dead in (("CDAlpacaHoof", False), ("CDAlpacaHoofDead", True)):
            p = os.path.join(TEX_DIR, f"{name}_{size}.png")
            draw_hoof(size, dead).save(p, format="PNG", optimize=True)
            written.append(p)
    return written


# ----------------------------------------------------------------- 模组图标 / 海报


def make_icon():
    """模组列表图标：base 与猫都是 64x64。用白色头像整体缩到 64 并加细边框。"""
    im = Image.open(os.path.join(OUT, "portrait_alpaca.png")).convert("RGB")
    small = im.resize((64, 64), Image.LANCZOS)
    d = ImageDraw.Draw(small)
    d.rectangle([0, 0, 63, 63], outline=(32, 40, 52))
    p = os.path.join(MOD_DIR, "icon.png")
    small.save(p, format="PNG", optimize=True)
    return p


def _paste_render(canvas, path, box, bg=None):
    im = Image.open(path).convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    x0, y0, x1, y1 = box
    scale = min((x1 - x0) / im.width, (y1 - y0) / im.height)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    canvas.alpha_composite(im, (x0 + ((x1 - x0) - im.width) // 2, y0 + ((y1 - y0) - im.height) // 2))


def make_poster(size=512):
    """模组海报（正方形）。左栏标题 + 要点，右栏头胸像，底部毛色圆点与依赖。

    排版约束（来自上一版的实测）：文字与渲染图必须在**不同的横向区间**里，
    左栏文本最宽到 0.42w，渲染图从 0.44w 开始 —— 否则全身照会压住要点文字。
    """
    im = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(im)
    grid_background(d, size, max(16, size // 24))

    m = int(size * 0.055)
    col_w = int(size * 0.37)
    title = fit_text(d, "CD: Alpacas", f_title(int(size * 0.105)), col_w)
    d.text((m, int(size * 0.07)), "CD: Alpacas", font=title, fill=TEXT)
    d.text((m, int(size * 0.175)), "羊驼", font=f_cjk(int(size * 0.075)), fill=CREAM)
    sub = fit_text(d, "Companion Dogs add-on", f_bold(int(size * 0.043)), col_w)
    d.text((m, int(size * 0.255)), "Companion Dogs add-on", font=sub, fill=ACCENT)
    d.text((m, int(size * 0.305)), "Build 42 (42.19+)", font=f_mono(int(size * 0.033)), fill=MUTED)

    lines = [
        "pack animal",
        "2.2x a dog's load",
        "early alarm call",
        "best herder",
        "no hunting",
        "herbivore",
        "heat sensitive",
    ]
    y = int(size * 0.385)
    for line in lines:
        d.text((m, y), "- " + line, font=f_mono(int(size * 0.029)), fill=TEXT)
        y += int(size * 0.042)

    # 右侧头胸像
    _paste_render(im, os.path.join(OUT, "portrait_alpaca.png"),
                  (int(size * 0.44), int(size * 0.045), int(size * 0.985), int(size * 0.79)))

    swatches = [CREAM, FAWN, BROWN, BLACK, GREY, ROSE, (246, 240, 228)]
    r = int(size * 0.021)
    x = m + r
    cy = int(size * 0.845)
    for c in swatches:
        d.ellipse([x - r, cy - r, x + r, cy + r], fill=c, outline=(40, 48, 60))
        x += int(r * 2.5)
    d.text((int(size * 0.60), int(size * 0.828)), "7 fleeces", font=f_mono(int(size * 0.031)), fill=MUTED)
    d.line([(m, int(size * 0.90)), (size - m, int(size * 0.90))], fill=CARD_LINE)
    d.text((m, int(size * 0.912)), "REQUIRES Companion Dogs 0.7.4+",
           font=f_bold(int(size * 0.038)), fill=ACCENT)
    d.text((m, int(size * 0.955)), "sandbox: Alpaca spawn multiplier",
           font=f_mono(int(size * 0.030)), fill=MUTED)
    return im.convert("RGB")


def make_preview(size=256):
    """工坊预览图（256 正方形，硬性规则见文件头）。小尺寸用另一套排版，不缩放 512 的设计。"""
    im = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(im)
    grid_background(d, size, max(12, size // 16))

    m = int(size * 0.06)
    d.text((m, int(size * 0.07)), "CD: Alpacas", font=f_title(int(size * 0.135)), fill=TEXT)
    d.text((m, int(size * 0.22)), "羊驼", font=f_cjk(int(size * 0.10)), fill=CREAM)
    d.text((m, int(size * 0.34)), "Companion Dogs add-on", font=f_bold(int(size * 0.062)), fill=ACCENT)
    d.text((m, int(size * 0.42)), "Build 42", font=f_mono(int(size * 0.055)), fill=MUTED)

    _paste_render(im, os.path.join(OUT, "portrait_alpaca.png"),
                  (int(size * 0.10), int(size * 0.46), size - int(size * 0.06), int(size * 0.94)))

    d.line([(m, int(size * 0.945)), (size - m, int(size * 0.945))], fill=CARD_LINE)
    return im.convert("RGB")


# ----------------------------------------------------------------- 校验 / 主流程


def check():
    bad = 0
    expect = []
    for breed, _ in BREEDS:
        expect.append((os.path.join(TEX_DIR, f"CDPortrait_{breed}.png"), (512, 512)))
    for s in MOODLE_SIZES:
        expect.append((os.path.join(TEX_DIR, f"CDAlpaca_Moodle_Fleece_{s}.png"), (s, s)))
        expect.append((os.path.join(TEX_DIR, f"CDAlpaca_MoodFleeceFG_{s}.png"), (s, s)))
    for s in HOOF_SIZES:
        expect.append((os.path.join(TEX_DIR, f"CDAlpacaHoof_{s}.png"), (s, s)))
        expect.append((os.path.join(TEX_DIR, f"CDAlpacaHoofDead_{s}.png"), (s, s)))
    expect.append((os.path.join(MOD_DIR, "icon.png"), (64, 64)))
    expect.append((os.path.join(MOD_DIR, "poster.png"), (512, 512)))
    expect.append((os.path.join(ITEM_DIR, "preview.png"), (256, 256)))

    for p, size in expect:
        if not os.path.isfile(p):
            log(f"MISSING {os.path.relpath(p, ITEM_DIR)}")
            bad += 1
            continue
        im = Image.open(p)
        sz = os.path.getsize(p)
        ok = im.size == size
        if "preview.png" in p and sz > 1024000:
            ok = False
        if not ok:
            bad += 1
        log(f"{'OK ' if ok else 'BAD'} {os.path.relpath(p, ITEM_DIR)} {im.size} {im.mode} {sz} bytes")
    log(f"check: {len(expect) - bad}/{len(expect)} ok")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description="generate every image CompanionDogsAlpaca ships")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--skip-portraits", action="store_true")
    args = ap.parse_args()

    if args.check:
        return check()

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)

    if not args.skip_portraits:
        for breed, texture in BREEDS:
            im = render_portrait(breed, texture)
            p = os.path.join(TEX_DIR, f"CDPortrait_{breed}.png")
            im.save(p, format="PNG", optimize=True)
            log(f"portrait {breed:15s} -> {os.path.basename(p)} {os.path.getsize(p)} bytes")

    for p in make_moodle_icons():
        log(f"moodle icon -> {os.path.basename(p)}")
    for p in make_hoof_icons():
        log(f"hoof icon   -> {os.path.basename(p)}")

    p = make_icon()
    log(f"mod icon    -> {os.path.relpath(p, ITEM_DIR)} {os.path.getsize(p)} bytes")
    p = os.path.join(MOD_DIR, "poster.png")
    make_poster(512).save(p, format="PNG", optimize=True)
    log(f"poster      -> {os.path.relpath(p, ITEM_DIR)} {os.path.getsize(p)} bytes")
    p = os.path.join(ITEM_DIR, "preview.png")
    make_preview(256).save(p, format="PNG", optimize=True)
    log(f"preview     -> {os.path.relpath(p, ITEM_DIR)} {os.path.getsize(p)} bytes")

    if WARNINGS:
        for w in WARNINGS:
            log(f"WARN {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
