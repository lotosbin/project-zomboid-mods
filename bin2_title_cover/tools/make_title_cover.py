#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""程序化生成 PZ 主菜单封面美术（无网络、无外部素材，纯 Pillow）。

背景（为什么要这么画）：Build 42 的 `zombie.gameStates.MainScreenState.renderBackground()` 字节码为

    if (Core.getInstance().getOptionDoVideoEffects()) { if (renderVideo()) return; }
    renderOriginalBackground(1.0f - lightningDelta * 0.6f);

`renderVideo()` 播放 `media/videos/title_screen_background.bik`；只有"不做视频效果"时才走
`renderOriginalBackground()`，它按 `scale = screenHeight / 1080` 绘制下面这套可被模组覆盖的纹理：

    左半底图   media/ui/Title.png           1024x1024  -> (x, 0,     1024*scale, 1024*scale)
    右半底图   media/ui/Title2.png           896x1024  -> (x+1024*scale, 0, 896*scale, 1024*scale)
    顶部条     media/ui/Title.png 缩放       1024x1024  -> (x, 0, 1024*scale, 56*scale)
    左条       media/ui/Title3.png          1024x56
    右条       media/ui/Title4.png           896x56
    x = min(0, screenWidth - (1024+896)*scale)   # 居中，宽度不够时向右裁切

所以 16:9 变体的画布是 1920x1024（1024 + 896），16:10/带鱼屏变体是 2560x1280（1280 + 1280）。
"顶部条"是把左半底图压到 56 高，因此画面顶部 56 像素必须自成一体（本脚本的标题文字整体
压在画布顶部 30% 之内，就是为了让这条裁切不切断字）。

用法：
    python3 make_title_cover.py            # 生成全部变体的美术与预览图
    python3 make_title_cover.py --check    # 只校验已生成文件（尺寸/模式/字节数/非纯色）
"""

from __future__ import annotations

import argparse
import hashlib
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------- 基本参数

# 固定随机种子 => 每次生成完全一致的美术（可复现是硬要求）
SEED = 0x5A4D4249

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ROOT = os.path.dirname(HERE)          # bin2_title_cover/

# 变体定义：name -> (画布宽, 画布高)
#   16:9  = 1024+896 宽 x 1024 高（左右两半正好铺满 16:9 屏幕）
#   16:10 = 1280+1280 宽 x 1280 高（更高的画布，宽屏下左右留黑边而不是裁切）
VARIANTS = {
    # 16:9：两半各 960x1024，正好铺满 1920x1080（scale=1）
    "v16": (1920, 1024),
    # 21:9 / 16:10：两半各 1280x1280，在 2560x1080 上铺满、在 16:9 上居中裁掉两侧
    "v219": (1280 + 1280, 1280),
}

# 标题文字整体只占画布顶部这个比例 —— 保证引擎那条 56px 高位裁切不会切到字
TITLE_BAND = 0.30

# 地平线（尸潮与建筑"站"在这条线上，也是地面反光的中心）
GROUND_Y = 0.845

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Impact.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "C:/Windows/Fonts/impact.ttf",
    "C:/Windows/Fonts/ariblk.ttf",
]

# 中文副标题要单独找字体：Impact 不含汉字，硬用会画成一排方块（第一次生成就踩了这个坑）
CJK_FONT_CANDIDATES = [
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/simhei.ttf",
]


def _first_existing(paths: list[str]) -> str:
    for path in paths:
        if os.path.isfile(path):
            return path
    return ""


def find_font() -> str:
    """标题（拉丁）粗体字。找不到就直接失败（不要静默用点阵字体凑数）。"""
    path = _first_existing(FONT_CANDIDATES)
    if not path:
        raise SystemExit(
            "找不到可用的粗体标题字体，请把 TTF 路径加进 FONT_CANDIDATES。\n"
            "已尝试：\n  " + "\n  ".join(FONT_CANDIDATES)
        )
    return path


def find_cjk_font() -> str:
    """中文副标题字体；找不到就退回拉丁字体并在日志里说明（不静默画成方块）。"""
    path = _first_existing(CJK_FONT_CANDIDATES)
    if not path:
        print("[warn] 找不到中文字体，副标题将用拉丁字体渲染（汉字可能变方块）")
        return find_font()
    return path


def rng(tag: str) -> random.Random:
    """按标签派生独立随机流：新增一层不会打乱其它层的随机序列。"""
    h = hashlib.sha256(f"{SEED}:{tag}".encode()).digest()
    return random.Random(int.from_bytes(h[:8], "big"))


def load_rgb(path: str) -> np.ndarray:
    """读成 (h, w, 3) float32，0..1。所有合成都在这个表示上做。"""
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0


def screen(base: np.ndarray, layer: np.ndarray, alpha: float = 1.0) -> np.ndarray:
    """滤色混合。用来叠"发光"层（天空、火光、边缘光）：黑=不改变底色。"""
    if alpha != 1.0:
        layer = layer * alpha
    return 1.0 - (1.0 - base) * (1.0 - np.clip(layer, 0.0, 1.0))


# ---------------------------------------------------------------- 各图层

def make_sky(w: int, h: int) -> np.ndarray:
    """夜空 + 星星 + 城市光污染（越靠地平线越暖，像是远处在烧）。

    亮度基准说明：第一版把天空压到 0.03~0.09，结果在游戏里几乎是纯黑的一片、
    上半幅看不出任何东西。这里整体抬到"能看见但依然是夜"的区间（0.08~0.30），
    并把地面反光交给后面的滤色层，保证剪影依然够黑。
    """
    y = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    x = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]

    top = np.array([0.080, 0.095, 0.140], dtype=np.float32)
    mid = np.array([0.120, 0.120, 0.155], dtype=np.float32)
    bot = np.array([0.290, 0.200, 0.135], dtype=np.float32)

    t = np.clip(y / 0.72, 0.0, 1.0) ** 1.15
    sky = top[None, None, :] * (1 - t)[..., None] + mid[None, None, :] * t[..., None]
    low = np.clip((y - 0.52) / 0.48, 0.0, 1.0) ** 1.5
    sky = sky * (1 - low)[..., None] + bot[None, None, :] * low[..., None]

    # 地平线附近的暖色雾光团（几团错开的径向光）
    glow = np.zeros((h, w, 3), dtype=np.float32)
    r = rng("sky-glow")
    for cx, cy, rad, strength in [
        (0.20, 0.94, 0.55, 1.00), (0.52, 0.97, 0.62, 0.80),
        (0.80, 0.93, 0.50, 0.70), (0.35, 0.90, 0.34, 0.45),
    ]:
        cx += r.uniform(-0.03, 0.03)
        cy += r.uniform(-0.02, 0.02)
        d = np.sqrt(((x - cx) * (w / h)) ** 2 + (y - cy) ** 2)
        glow += np.exp(-(d / rad) ** 2)[..., None] * np.array(
            [0.75, 0.36, 0.14], dtype=np.float32) * strength
    glow *= np.clip((y - 0.45) / 0.55, 0.0, 1.0)[..., None] ** 1.4
    sky = screen(sky, glow * 0.70)

    # 星星：越靠下越淡
    canvas = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(canvas)
    rs = rng("stars")
    for _ in range(int(w * h / 700)):
        sx = rs.randrange(w)
        sy = int(abs(rs.gauss(0.18, 0.22)) * h)
        if sy >= h * 0.66:
            continue
        b = rs.uniform(70, 255) * (1.0 - sy / (h * 0.66)) ** 1.3
        rr = rs.choice([0, 0, 0, 1])
        sd.ellipse([sx - rr, sy - rr, sx + rr, sy + rr], fill=int(b))
    star_layer = np.zeros((h, w, 3), dtype=np.float32)
    star_layer[..., 0] = np.asarray(canvas, dtype=np.float32) / 255.0
    star_layer[..., 1] = star_layer[..., 0]
    star_layer[..., 2] = np.minimum(1.0, star_layer[..., 0] * 1.15)
    return screen(sky, star_layer * 0.9)


def make_clouds(w: int, h: int) -> np.ndarray:
    """分形噪声云：返回 **提亮系数**（0 表示不改变天空，1 表示整片云亮起来）。

    方向很重要：云是让夜空"有东西可看"的来源，如果拿去压暗天空，黑底上什么都看不见
    （第一版就是这么废掉的）。这里改成提亮 —— 云被城市火光从下方照亮的观感。
    """
    cloud = np.zeros((h, w), dtype=np.float32)
    total = 0.0
    for octave, base in enumerate([3, 6, 12, 24], start=1):
        weight = 1.0 / (2 ** (octave - 1))
        gw, gh = max(2, base * 4), max(2, base * 2)
        small = np.asarray(
            Image.effect_noise((gw, gh), 110.0).resize((w, h), Image.BICUBIC),
            dtype=np.float32) / 128.0
        cloud += small * weight
        total += weight
    cloud /= total
    cloud = np.clip((cloud - 0.36) * 2.0, 0.0, 1.0)

    # 云集中在中上部（贴近地平线的地方让位给火光）
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    cloud *= np.clip(1.15 - abs(yy - 0.26) * 1.9, 0.0, 1.0)

    layer = np.zeros((h, w, 3), dtype=np.float32)
    layer[..., 0] = cloud * 0.085
    layer[..., 1] = cloud * 0.082
    layer[..., 2] = cloud * 0.100
    return layer


def make_ruins(w: int, h: int) -> Image.Image:
    """远景废墟天际线（只画建筑与楼顶火点；地面暖光由 make_fog_band 单独负责）。

    基线放在 GROUND_Y：建筑"站在"地面线上，后面的尸潮与主角才有同一个地平。
    """
    sil = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fire = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sil)
    fd = ImageDraw.Draw(fire)

    horizon = int(h * (GROUND_Y - 0.50))            # 建筑最高只能到画布 10% 处（给标题留位）
    base_y = int(h * GROUND_Y)
    r = rng("ruins")

    x = -int(w * 0.02)
    while x < w:
        bw = r.randint(int(w * 0.013), int(w * 0.048))
        # 越靠中间越高，形成"英雄居中"的轮廓线
        centre_bias = 1.0 - min(1.0, abs((x + bw / 2) / w - 0.5) * 1.7)
        tall = r.uniform(0.30, 1.00) * (0.42 + 0.58 * centre_bias)
        bh = int((base_y - horizon) * tall) + int(h * 0.035)
        top = base_y - bh

        # 楼体：上深下略暖，避免大块死黑（太黑的话天空一亮，楼就变成没信息的黑块）
        shade = int(r.uniform(30, 58))
        sd.rectangle([x, top, x + bw, base_y], fill=(shade, shade - 4, shade + 8, 255))

        # 窗户：极少数亮着（暖色），其余是比楼体更暗的格子
        cw, ch = max(3, bw // r.randint(5, 8)), max(4, bh // r.randint(9, 16))
        gap_x, gap_y = max(2, cw // 2), max(2, ch // 2)
        gy = top + gap_y
        while gy + ch < base_y - gap_y:
            gx = x + gap_x
            while gx + cw < x + bw - gap_x:
                if r.random() < 0.045:
                    warm = r.randint(180, 255)
                    fd.rectangle([gx, gy, gx + cw, gy + ch],
                                 fill=(warm, int(warm * 0.62), int(warm * 0.24),
                                       r.randint(150, 235)))
                else:
                    sd.rectangle([gx, gy, gx + cw, gy + ch],
                                 fill=(max(0, shade - 9), max(0, shade - 11), shade, 255))
                gx += cw + gap_x
            gy += ch + gap_y

        # 顶部残缺：随机削掉几块 + 露出钢筋
        for _ in range(r.randint(0, 3)):
            cw2 = r.randint(int(bw * 0.2), max(int(bw * 0.2) + 1, int(bw * 0.6)))
            cxx = r.randint(x, max(x, x + bw - cw2))
            chh = r.randint(int(bh * 0.04), max(int(bh * 0.05), int(bh * 0.18)))
            sd.rectangle([cxx, top, cxx + cw2, top + chh], fill=(0, 0, 0, 0))
            for _ in range(r.randint(1, 4)):
                rx = r.randint(cxx, cxx + cw2)
                sd.line([rx, top, rx + r.randint(-4, 4), top - r.randint(3, 12)],
                        fill=(shade, shade, shade + 5, 255), width=max(1, bw // 60))

        # 楼顶火点：小三角火苗
        if r.random() < 0.30:
            fx = r.randint(x + bw // 5, max(x + bw // 5, x + bw * 4 // 5))
            fh = r.randint(int(h * 0.02), int(h * 0.055))
            for k in range(6):
                fw = max(1, int((1 - k / 6) * h * 0.012))
                col = (255, int(200 - k * 20), int(90 - k * 12), int(210 - k * 26))
                fd.polygon([(fx - fw, top - fh * k // 6), (fx + fw, top - fh * k // 6),
                            (fx, top - fh * (k + 1) // 6)], fill=col)
        # 天线/水塔：给天际线加细高元素，否则一排等宽方块看着像条形码
        if r.random() < 0.36:
            ax = r.randint(x + bw // 6, max(x + bw // 6, x + bw * 5 // 6))
            ah = r.randint(int(h * 0.03), int(h * 0.11))
            sd.line([ax, top, ax, top - ah], fill=(shade, shade, shade + 8, 255),
                    width=max(1, bw // 26))
            if r.random() < 0.55:
                sd.line([ax - bw // 5, top - ah * 0.60, ax + bw // 5, top - ah * 0.60],
                        fill=(shade, shade, shade + 8, 255), width=max(1, bw // 40))
        x += bw + r.randint(int(w * 0.001), int(w * 0.008))

    # 建筑底部的暖色反光：让天际线"烧起来"（只往上散一点点）
    band = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for k in range(int(h * 0.06)):
        a = int(90 * (1 - k / (h * 0.06)) ** 2)
        yy = base_y - k
        if 0 <= yy < h:
            bd.line([0, yy, w, yy], fill=(255, 150, 70, a))
    fire.alpha_composite(band)

    return sil.filter(ImageFilter.GaussianBlur(0.6)), fire.filter(ImageFilter.GaussianBlur(1.6))


def make_fog_band(w: int, h: int) -> Image.Image:
    """地平线雾光：以 GROUND_Y 为中心向上下衰减的暖光带（不是一条硬边）。

    坑：这里必须**由亮度直接生成 alpha**。第一版用 `Image.new("RGBA", ..., (0,0,0,0))`
    画完直接返回 —— Pillow 新建图层不会因为你 setpixel 了就自动带上 alpha，结果整张
    贴图是"全不透明黑"，alpha_composite 一到这一步就把天空整片刷黑。
    """
    y = np.arange(h, dtype=np.float32)[:, None]
    gy = h * GROUND_Y
    above = np.clip((gy - y) / (h * 0.16), 0.0, 1.0)
    below = np.clip((y - gy) / (h * 0.20), 0.0, 1.0)
    glow = 0.55 * np.exp(-((y - gy) / (h * 0.075)) ** 2)
    glow = np.clip(glow * (1.0 - 0.55 * above) * (1.0 - 0.70 * below), 0.0, 1.0)

    col = np.array([1.00, 0.58, 0.30], dtype=np.float32)
    rgb = np.repeat(glow, w, axis=1)[..., None] * col[None, None, :] * 0.85
    alpha = np.repeat(np.clip(glow * 1.15, 0.0, 1.0), w, axis=1)

    rgba = np.dstack([np.clip(rgb, 0, 1), alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def draw_ground(img: Image.Image, w: int, h: int) -> None:
    """地面：GROUND_Y 以下近黑，但保留一点暖色底（后面 getGroundGlow 会提亮）。"""
    d = ImageDraw.Draw(img)
    gy = int(h * GROUND_Y)
    d.rectangle([0, gy, w, h], fill=(0, 0, 0, 255))


def get_ground_glow(w: int, h: int) -> np.ndarray:
    """地面反光（滤色用）：在"地面线"附近最强，这里就是主角背光的来源。"""
    y = np.arange(h, dtype=np.float32)[:, None]
    gy = h * GROUND_Y
    glow = np.clip((y - gy) / (h * 0.16), 0.0, 1.0) * np.exp(-((y - gy) / (h * 0.052)) ** 2)
    col = np.array([1.00, 0.46, 0.16], dtype=np.float32)
    return np.repeat(glow, w, axis=1)[..., None] * col[None, None, :] * 0.85


def draw_props(img: Image.Image, w: int, h: int) -> None:
    """前景道具：倾斜电线杆、枯树、废车（最后画，压在主角之上）。"""
    d = ImageDraw.Draw(img)
    gy = int(h * GROUND_Y)
    r = rng("props")

    # 倾斜电线杆（左）
    px, py = w * 0.048, gy + 0.02 * h
    d.line([px, py, px + 0.042 * w, py - 0.78 * h], fill=(4, 4, 6, 255),
           width=int(0.010 * w))
    for k in (0.34, 0.50, 0.66):
        yy = py - 0.78 * h * k
        xx = px + 0.042 * w * k
        d.line([xx - 0.032 * w, yy + 0.018 * h, xx + 0.028 * w, yy - 0.010 * h],
               fill=(4, 4, 6, 255), width=int(0.005 * w))

    # 枯树（右）
    tx, ty = w * 0.955, gy + 0.01 * h
    d.line([tx, ty, tx + 0.004 * w, ty - 0.34 * h], fill=(4, 4, 6, 255),
           width=int(0.010 * w))
    for a, ln in [(-0.55, 0.13), (-0.30, 0.16), (0.15, 0.14), (0.42, 0.11)]:
        d.line([tx + 0.004 * w, ty - 0.26 * h,
                tx + 0.004 * w + a * 0.09 * w, ty - 0.26 * h - ln * h],
               fill=(4, 4, 6, 255), width=int(0.0045 * w))

    # 废车（左侧中景）
    cx, cy = w * 0.145, gy + 0.035 * h
    cwid, chgt = 0.115 * w, 0.062 * h
    d.polygon([(cx, cy), (cx + cwid * 0.14, cy - chgt * 0.72),
               (cx + cwid * 0.70, cy - chgt * 0.95), (cx + cwid, cy - chgt * 0.30),
               (cx + cwid, cy)], fill=(4, 4, 6, 255))
    for wx in (0.20, 0.80):
        rr = 0.020 * h
        d.ellipse([cx + cwid * wx - rr, cy - rr * 0.9, cx + cwid * wx + rr, cy + rr * 1.2],
                  fill=(4, 4, 6, 255))


def draw_rubble_row(img: Image.Image, w: int, h: int) -> None:
    """地面线上的碎石带：打破"一条直线"的地面，制造层次。"""
    d = ImageDraw.Draw(img)
    gy = int(h * GROUND_Y)
    r = rng("rubble")
    for _ in range(int(w / h * 60)):
        rx = r.uniform(-0.01 * w, 1.01 * w)
        rw = r.uniform(0.010, 0.045) * w
        rh = r.uniform(0.010, 0.030) * h
        d.polygon([(rx, gy + rh * 0.4), (rx + rw * 0.35, gy - rh),
                   (rx + rw * 0.75, gy - rh * 0.4), (rx + rw, gy + rh * 0.6)],
                  fill=(0, 0, 0, 255))
    # 几根斜插的钢筋/木板
    for _ in range(int(w / h * 6)):
        rx = r.uniform(0, w)
        rh = r.uniform(0.02, 0.06) * h
        d.line([rx, gy + 0.01 * h, rx + r.uniform(-0.02, 0.02) * w, gy - rh],
               fill=(0, 0, 0, 255), width=max(2, int(0.0018 * w)))


def draw_zombie(d: ImageDraw.ImageDraw, x: float, ground_y: float, height: float,
                colour: tuple[int, int, int, int], facing: int,
                r: random.Random, arms: str = "reach") -> None:
    """画一只僵尸剪影。facing=+1 朝右，-1 朝左。"""
    c = colour
    hh = height
    hip = ground_y - 0.47 * hh
    sh = ground_y - 0.80 * hh
    head_r = 0.072 * hh

    lean = facing * 0.035 * hh              # 躯干前倾（蹒跚感）

    # 腿：两条，随机一前一后
    for sgn, spread in ((1, r.uniform(0.05, 0.13)), (-1, r.uniform(0.05, 0.13))):
        foot_x = x + sgn * spread * hh
        knee_x = x + sgn * spread * hh * 0.55 + r.uniform(-0.02, 0.02) * hh
        w1 = 0.052 * hh
        d.line([x, hip, knee_x, ground_y - 0.24 * hh], fill=c, width=int(max(2, w1)))
        d.line([knee_x, ground_y - 0.24 * hh, foot_x, ground_y], fill=c,
               width=int(max(2, w1 * 0.82)))

    # 躯干
    torso_w = 0.145 * hh
    d.polygon([
        (x - torso_w / 2, hip + 0.02 * hh),
        (x + torso_w / 2, hip + 0.02 * hh),
        (x + torso_w * 0.58 + lean, sh),
        (x - torso_w * 0.58 + lean, sh),
    ], fill=c)

    # 头（略前伸）
    hx = x + lean + facing * 0.028 * hh
    d.ellipse([hx - head_r, sh - head_r * 2.15, hx + head_r, sh - head_r * 0.15], fill=c)

    # 手臂
    aw = max(2, int(0.040 * hh))
    sx = x + lean
    if arms == "reach":
        for sgn in (1, -1):
            y0 = sh + 0.02 * hh + sgn * 0.012 * hh
            d.line([sx - 0.05 * hh * facing, y0,
                    sx + facing * 0.26 * hh, y0 - 0.10 * hh], fill=c, width=aw)
    elif arms == "up":
        d.line([sx - 0.05 * hh, sh, sx - 0.16 * hh, sh - 0.30 * hh], fill=c, width=aw)
        d.line([sx + 0.05 * hh, sh, sx + 0.13 * hh, sh - 0.26 * hh], fill=c, width=aw)
    else:  # 垂下
        d.line([sx - 0.055 * hh, sh, sx - 0.10 * hh, sh + 0.34 * hh], fill=c, width=aw)
        d.line([sx + 0.055 * hh, sh, sx + 0.09 * hh, sh + 0.31 * hh], fill=c, width=aw)


def make_horde(w: int, h: int) -> Image.Image:
    """尸潮：远→近三层，越远越小越淡（大气透视），整体"站"在 GROUND_Y 上。

    密度用"随机散布 + 每层独立计数"而不是等距排布：第一版用 `(i+rand)/n` 均匀铺，
    渲染出来是一排间隔一致的等距小人，一眼假。这里改成聚簇散布（每层先撒若干簇心，
    再在簇心周围正态撒人），才会像"尸潮"而不是"仪仗队"。
    """
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gy = h * GROUND_Y
    r = rng("horde")

    def scatter(count: int, size_lo: float, size_hi: float, alpha: int, lift: float,
                jitter: float, arms_w: list[float]) -> Image.Image:
        """在画布上按簇散布一层僵尸。"""
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # 簇心：让密度有起伏（尸潮是成团的，不是均匀的）。
        # 左 1/4 是原版主菜单按钮区，密度压低一点，避免和 UI 抢注意力。
        clusters = []
        while len(clusters) < max(3, int(w / h * 6)):
            cx = r.uniform(-0.05 * w, 1.05 * w)
            if cx < 0.25 * w and r.random() < 0.65:
                continue
            clusters.append(cx)
        for _ in range(count):
            cx = r.choice(clusters)
            zx = r.gauss(cx, jitter * w)
            if zx < -0.05 * w or zx > 1.05 * w:
                continue
            zy = gy - lift * h + r.gauss(0.0, 0.010 * h)
            zh = h * r.uniform(size_lo, size_hi)
            facing = 1 if r.random() < 0.5 else -1
            arms = r.choices(["reach", "up", "down"], weights=arms_w)[0]
            draw_zombie(d, zx, zy, zh, (16, 15, 19, alpha), facing, r, arms)
        return img

    layer.alpha_composite(
        scatter(int(w / h * 58), 0.050, 0.080, 115, 0.000, 0.070, [6, 1, 3])
        .filter(ImageFilter.GaussianBlur(1.2)))
    layer.alpha_composite(
        scatter(int(w / h * 44), 0.072, 0.108, 155, 0.012, 0.060, [6, 1, 3])
        .filter(ImageFilter.GaussianBlur(1.0)))
    layer.alpha_composite(
        scatter(int(w / h * 32), 0.098, 0.145, 195, 0.026, 0.050, [5, 1, 4])
        .filter(ImageFilter.GaussianBlur(0.9)))

    # 中层 + 近层：更大、更黑，但给主角位（右下 1/3）留空
    for size_lo, size_hi, alpha, blur, lift, jitter in [
            (0.15, 0.23, 232, 0.9, 0.042, 0.16),
            (0.23, 0.33, 250, 1.5, 0.062, 0.20)]:
        for _ in range(int(w / h * 9)):
            zx = r.uniform(0.0, w)
            if 0.62 * w < zx < 0.90 * w:
                continue
            zy = gy + lift * h + r.gauss(0.0, 0.012 * h)
            zh = h * r.uniform(size_lo, size_hi)
            facing = 1 if r.random() < 0.5 else -1
            arms = r.choices(["reach", "up", "down"], weights=[5, 1, 4])[0]
            single = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            draw_zombie(ImageDraw.Draw(single), zx, zy, zh, (8, 8, 11, alpha), facing, r, arms)
            layer.alpha_composite(single.filter(ImageFilter.GaussianBlur(blur)))
    return layer


def make_hero(w: int, h: int) -> Image.Image:
    """主角：近黑剪影 + 边缘光（背光来自地面暖反光）。"""
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    w_, h_ = w, h
    hx = w_ * 0.760
    ground = h_ * GROUND_Y + h_ * 0.030          # 站在地面线略下方一点，像踩在近景上
    hh = h_ * 0.52

    body = Image.new("RGBA", (w_, h_), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    hip = ground - 0.50 * hh
    sh = ground - 0.82 * hh
    tw = 0.155 * hh
    # 躯干（肩略宽于腰）
    bd.polygon([(hx - tw * 0.46, hip + 0.02 * hh), (hx + tw * 0.46, hip + 0.02 * hh),
                (hx + tw * 0.66, sh), (hx - tw * 0.66, sh)], fill=(3, 3, 4, 255))
    # 双腿（自然站立，不是木桩）
    for sgn in (1, -1):
        knee = (hx + sgn * 0.075 * hh, ground - 0.24 * hh)
        bd.line([hx + sgn * 0.045 * hh, hip, knee[0], knee[1]],
                fill=(3, 3, 4, 255), width=int(0.062 * hh))
        bd.line([knee[0], knee[1], hx + sgn * 0.085 * hh, ground],
                fill=(3, 3, 4, 255), width=int(0.052 * hh))
        # 靴子
        bd.ellipse([hx + sgn * 0.085 * hh - 0.030 * hh, ground - 0.020 * hh,
                    hx + sgn * 0.085 * hh + 0.045 * hh, ground + 0.016 * hh],
                   fill=(3, 3, 4, 255))
    # 头 + 颈
    head_r = 0.070 * hh
    bd.rectangle([hx - 0.030 * hh, sh - 0.055 * hh, hx + 0.030 * hh, sh + 0.010 * hh],
                 fill=(3, 3, 4, 255))
    bd.ellipse([hx - head_r, sh - head_r * 2.30, hx + head_r, sh - head_r * 0.10],
               fill=(3, 3, 4, 255))
    # 持械：右手前举握杆，杆斜向左下
    bd.line([hx - 0.05 * hh, sh + 0.04 * hh, hx - 0.26 * hh, sh + 0.10 * hh],
            fill=(3, 3, 4, 255), width=int(0.048 * hh))
    bd.line([hx + 0.06 * hh, sh + 0.05 * hh, hx - 0.16 * hh, sh + 0.20 * hh],
            fill=(3, 3, 4, 255), width=int(0.044 * hh))
    bd.line([hx - 0.22 * hh, sh + 0.06 * hh, hx - 0.60 * hh, sh + 0.42 * hh],
            fill=(3, 3, 4, 255), width=int(0.022 * hh))

    # 边缘光：剪影平移取差集 => 上/右侧一圈亮边
    ox, oy = int(0.010 * w_), int(0.012 * h_)
    rim = ImageChops.subtract(body, ImageChops.offset(body, ox, oy))
    rim = rim.filter(ImageFilter.GaussianBlur(1.3))
    rim_col = Image.new("RGBA", (w_, h_), (255, 172, 92, 0))
    rim_col.putalpha(rim.getchannel("A"))

    # 背光光晕：在剪影后面垫一层大地暖光，让主角从暗背景里"脱"出来
    halo = body.filter(ImageFilter.GaussianBlur(max(5, int(0.022 * h_))))
    halo_a = np.asarray(halo.getchannel("A"), dtype=np.float32) / 255.0
    halo_col = np.zeros((h_, w_, 4), dtype=np.float32)
    halo_col[..., 0] = 1.00
    halo_col[..., 1] = 0.44
    halo_col[..., 2] = 0.18
    halo_col[..., 3] = np.clip(halo_a * 1.6, 0.0, 0.34)
    layer.alpha_composite(Image.fromarray((halo_col * 255).astype(np.uint8), "RGBA"))
    layer.alpha_composite(rim_col)
    layer.alpha_composite(body)
    return layer


def make_lightning(w: int, h: int, layered: Image.Image) -> Image.Image:
    """闪电层：在同一构图上加冷白增亮，作为 Title_lightning*.png 的等价物。"""
    r = rng("lightning")
    cloud = np.zeros((h, w), dtype=np.float32)
    for base in (4, 9, 18):
        gw, gh = base * 4, base * 2
        small = np.asarray(Image.effect_noise((gw, gh), 90.0).resize((w, h), Image.BICUBIC),
                           dtype=np.float32) / 128.0
        cloud += small
    cloud = np.clip((cloud / 3.0 - 0.44) * 2.4, 0.0, 1.0)

    # 一道主放电：从云层折线劈向地平线
    bolt = Image.new("L", (w, h), 0)
    bd = ImageDraw.Draw(bolt)
    bx = w * r.uniform(0.30, 0.46)
    by = h * 0.05
    pts = [(bx, by)]
    while by < h * 0.56:
        bx += r.uniform(-0.035, 0.035) * w
        by += r.uniform(0.05, 0.11) * h
        pts.append((bx, by))
    bd.line(pts, fill=210, width=max(2, int(0.0028 * w)))
    bolt = bolt.filter(ImageFilter.GaussianBlur(1.4))

    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([bx - 0.20 * w, h * 0.02, bx + 0.20 * w, h * 0.55], fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(0.10 * w))

    bright = (cloud * 0.55 + np.asarray(bolt, dtype=np.float32) / 255.0 * 0.9
              + np.asarray(glow, dtype=np.float32) / 255.0 * 0.35)
    bright = np.clip(bright, 0.0, 1.0)
    # 近地部分收敛，避免把地平线洗白
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    bright *= np.clip(1.25 - yy * 1.35, 0.0, 1.0)

    lum = np.asarray(layered.convert("L"), dtype=np.float32) / 255.0
    bright *= np.clip(lum * 2.2 + 0.25, 0.0, 1.0)     # 只在有内容的地方闪光

    layer = np.zeros((h, w, 3), dtype=np.float32)
    layer[..., 0] = bright * 0.72
    layer[..., 1] = bright * 0.82
    layer[..., 2] = bright * 1.00
    base = np.asarray(layered.convert("RGB"), dtype=np.float32) / 255.0
    arr = np.clip(base + layer, 0.0, 1.0)
    return Image.fromarray((arr * 255.0).astype(np.uint8), "RGB")


# ---------------------------------------------------------------- 文字与质感

def _distress_text_mask(mask: Image.Image, r: random.Random) -> Image.Image:
    """做旧：用噪点+划痕啃掉字边，得到破损/风化的轮廓。"""
    w, h = mask.size
    noise = Image.effect_noise((w, h), 64.0).filter(ImageFilter.GaussianBlur(0.8))
    na = np.asarray(noise, dtype=np.float32)
    keep = np.clip((na - 92.0) / 60.0, 0.0, 1.0)
    edge = mask.filter(ImageFilter.GaussianBlur(1.0))
    m = np.asarray(mask, dtype=np.float32) / 255.0
    e = np.asarray(edge, dtype=np.float32) / 255.0
    out = m * (1.0 - e * 0.55) + m * np.clip(keep * 1.6, 0.0, 1.0) * 0.45
    out = np.clip(out, 0.0, 1.0)

    scratches = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(scratches)
    for _ in range(int(w / 120)):
        sx, sy = r.uniform(0, w), r.uniform(0, h)
        sd.line([sx, sy, sx + r.uniform(-0.06, 0.06) * w, sy + r.uniform(0.01, 0.05) * h],
                fill=255, width=r.randint(1, 3))
    scratches = scratches.filter(ImageFilter.GaussianBlur(0.7))
    out = np.clip(out - np.asarray(scratches, dtype=np.float32) / 255.0 * 0.65, 0.0, 1.0)
    return Image.fromarray((out * 255.0).astype(np.uint8), "L")


def make_title_text(w: int, h: int, font_path: str, cjk_path: str) -> Image.Image:
    """标题文字层（RGBA，已把描边/偏置影/两行配色合好）。

    排版策略：先按画布高度取一个体面的字号，**实测**三行总高（含行距）后整体等比缩放到
    顶部安全区内再垂直居中 —— 不同画布尺寸共用一套逻辑，且不会把字排到安全区外。
    """
    r = rng("title")
    band_h = int(h * TITLE_BAND)
    pad = int(h * 0.014)
    line_gap = int(h * 0.012)

    main, sub, tag = "PROJECT ZOMBOID", "僵尸毁灭工程", "BUILD 42  ·  APOCALYPSE"
    lines = [(tag, 0.17, False), (main, 0.70, False), (sub, 0.26, True)]

    base = int(h * 0.155)
    for _ in range(40):
        fonts = [ImageFont.truetype(cjk_path if cjk else font_path,
                                    max(8, int(base * f))) for _, f, cjk in lines]
        heights, widths = [], []
        probe = ImageDraw.Draw(Image.new("L", (1, 1)))
        for (text, _, _), fnt in zip(lines, fonts):
            box = probe.textbbox((0, 0), text, font=fnt)
            heights.append(box[3] - box[1])
            widths.append(box[2] - box[0])
        total = sum(heights) + line_gap * (len(lines) - 1)
        if (total <= band_h - 2 * pad and max(widths) <= w * 0.90) or base <= 9:
            break
        base = int(base * 0.94)

    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    y = max(pad, (band_h - total) // 2)
    for (text, _, _), fnt, hgt in zip(lines, fonts, heights):
        box = md.textbbox((0, 0), text, font=fnt)
        md.text((int(w * 0.5 - (box[2] - box[0]) / 2), y), text, font=fnt, fill=255)
        y += hgt + line_gap

    assert y - line_gap <= band_h, f"标题文字超出顶部 {TITLE_BAND:.0%} 安全区（{y} > {band_h}）"
    assert max(widths) <= w * 0.92, f"标题过宽：{max(widths)} > {w * 0.92:.0f}"

    mask = _distress_text_mask(mask, r)
    # 轻微半调：细横纹啃掉一点亮度，制造旧印刷感
    yy = np.arange(h)[:, None]
    halftone = (1.0 - 0.18 * (np.sin(yy * np.pi / 3.0) > 0.85)).astype(np.float32)
    mask = Image.fromarray(
        (np.asarray(mask, dtype=np.float32) * halftone).astype(np.uint8), "L")

    # 只有主标题行用"白字 + 血红偏置影"；上下两行小字用血红，整体是经典海报配色
    main_top = heights[0] + line_gap
    main_bot = main_top + heights[1]
    main_band = mask.copy()
    main_arr = np.asarray(mask, dtype=np.float32)
    keep = np.zeros_like(main_arr)
    keep[max(0, main_top - line_gap // 2):main_bot + line_gap // 2, :] = 1.0
    main_band = Image.fromarray((main_arr * keep).astype(np.uint8), "L")
    sub_band = Image.fromarray((main_arr * (1.0 - keep)).astype(np.uint8), "L")

    def _tinted(band: Image.Image, colour: tuple[int, int, int]) -> Image.Image:
        img = Image.new("RGBA", (w, h), colour + (0,))
        img.putalpha(band)
        return img

    shadow = _tinted(ImageChops.offset(main_band, max(2, w // 640), max(2, h // 420)),
                     (150, 16, 20))
    solid = _tinted(main_band, (238, 232, 224))
    accent = _tinted(sub_band, (176, 26, 26))

    # 描边/冷光：主标题下面垫一圈冷白，避免白字糊在灰云上
    grown = main_band.filter(ImageFilter.MaxFilter(5))
    ring = ImageChops.subtract(grown, main_band).filter(ImageFilter.GaussianBlur(1.8))
    outline = Image.new("RGBA", (w, h), (196, 222, 240, 0))
    outline.putalpha(ring)

    combined = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    combined.alpha_composite(outline)
    combined.alpha_composite(shadow)
    combined.alpha_composite(solid)
    combined.alpha_composite(accent)
    return combined


def apply_grain_and_vignette(img: np.ndarray, r: random.Random) -> np.ndarray:
    """胶片颗粒 + 暗角 + 轻微色偏，压住"程序生成"的干净感。"""
    h, w = img.shape[:2]
    grain = np.asarray(Image.effect_noise((w, h), 26.0), dtype=np.float32) / 128.0 - 1.0
    img = np.clip(img + (grain * 0.035)[..., None], 0.0, 1.0)

    yy = np.linspace(-1.0, 1.0, h, dtype=np.float32)[:, None]
    xx = np.linspace(-1.0, 1.0, w, dtype=np.float32)[None, :]
    d = np.sqrt(xx ** 2 + (yy * 1.05) ** 2) / 1.414
    vig = np.clip(1.0 - 0.55 * d ** 2.1, 0.0, 1.0)
    img = img * vig[..., None] ** 1.05

    tint = np.array([1.02, 0.995, 1.05], dtype=np.float32)
    img = np.clip(img * tint[None, None, :], 0.0, 1.0)
    return img


# ---------------------------------------------------------------- 合成

def render_cover(w: int, h: int, font_path: str, cjk_path: str) -> Image.Image:
    """返回封面（RGB）。

    图层顺序（由远及近，直接决定观感，改顺序前先想清楚）：
      天空 → 云 → 废墟天际线 → 地平线雾光 → 地面 → 碎石带 → 地面反光(滤色)
      → 尸潮 → 主角 → 前景道具 → 标题 → 颗粒/暗角/半调
    """
    sky = make_sky(w, h)
    sky = screen(sky, make_clouds(w, h))               # 云是"被火光打亮的"，所以用滤色
    canvas = Image.fromarray((sky * 255.0).astype(np.uint8), "RGB").convert("RGBA")

    ruins, ruin_fire = make_ruins(w, h)
    canvas.alpha_composite(ruins)
    canvas.alpha_composite(ruin_fire)
    canvas.alpha_composite(make_fog_band(w, h))

    draw_ground(canvas, w, h)
    draw_rubble_row(canvas, w, h)

    # 地面反光：纯黑区域用滤色提亮 => 主角脚下有背光，但剪影本身仍是黑的
    base = np.asarray(canvas.convert("RGB"), dtype=np.float32) / 255.0
    lit = np.clip(base + get_ground_glow(w, h), 0.0, 1.0)
    glow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_layer.paste(Image.fromarray((lit * 255).astype(np.uint8), "RGB"), (0, 0))
    # 只保留"相对原图变亮"的部分，避免把上半部分也覆盖掉
    diff = np.clip(lit - base, 0.0, 1.0).max(axis=2)
    alpha = Image.fromarray((np.clip(diff * 12.0, 0, 1) * 255).astype(np.uint8), "L")
    glow_layer.putalpha(alpha)
    canvas.alpha_composite(glow_layer)

    canvas.alpha_composite(make_horde(w, h))
    canvas.alpha_composite(make_hero(w, h))
    draw_props(canvas, w, h)

    canvas.alpha_composite(make_title_text(w, h, font_path, cjk_path))

    r = rng("finish")
    arr = np.asarray(canvas.convert("RGB"), dtype=np.float32) / 255.0
    arr = apply_grain_and_vignette(arr, r)
    cover = Image.fromarray((arr * 255.0).astype(np.uint8), "RGB")

    # 注意：**不**产出 Title_lightning*.png 的满幅版本。引擎把 4 条闪电都按"整幅正方形高"
    # 绘制，而且是 glBlendFunc(770, 1) **加法混合** —— 给它一张满幅亮图会在主菜单上叠出
    # 一条撕开画面的白带。闪电开关（lightningDelta）在原版里恒为 0（MainScreen.update 从不
    # 设置 lightningTimelineMarker），因此这几张贴图根本不会被用到，交回原版即可。
    return _halftone(cover)


def _halftone(img: Image.Image) -> Image.Image:
    """粗半调网点叠加（设计参考里的 Grunge 半调）。"""
    w, h = img.size
    step = max(3, int(min(w, h) / 340))
    small = Image.effect_noise((max(2, w // step), max(2, h // step)), 90.0)
    dots = small.point(lambda v: 255 if v > 150 else 0).convert("L")
    dots = dots.resize((w, h), Image.NEAREST)
    d = np.asarray(dots, dtype=np.float32) / 255.0
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = arr * (1.0 - 0.07 * d)[..., None]
    return Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), "RGB")


# ---------------------------------------------------------------- 输出

def make_preview(cover: Image.Image, size: int = 256) -> Image.Image:
    """工坊预览图：must 是正方形 256 或 512（SteamWorkshopItem.validatePreviewImage）。"""
    cw, ch = cover.size
    side = min(cw, ch)
    left = (cw - side) // 2
    crop = cover.crop((left, 0, left + side, side)).resize((size, size), Image.LANCZOS)
    return crop


def make_poster(cover: Image.Image, size: int = 512) -> Image.Image:
    """模组列表海报：居中裁成正方形 512（仓库惯例）。"""
    return make_preview(cover, size)


def make_icon(cover: Image.Image, size: int = 64) -> Image.Image:
    return make_preview(cover, size)


def split_variant(cover: Image.Image, left_w: int) -> dict[str, Image.Image]:
    """把整幅封面切成引擎要的那几块纹理。

    Title.png / Title2.png：左右两半底图，按"整幅正方形高"绘制，所以必须是完整画面。

    Title3.png / Title4.png：原版是 1024x56 / 896x56 的顶栏条。**但引擎实际按
    `1024*scale` 的高（= 整幅正方形）来画它们**（`56f*scale` 算进局部变量后从未被读取），
    所以这里输出"宽x1024、仅顶部 56 行不透明、其余全透明"的 RGBA：
      * 引擎若按 56 行画 -> 与设计意图完全一致；
      * 引擎若按整幅画 -> 下面是全透明，alpha 混合下不会盖住画面。
    直接给"整幅不透明画面"会让顶部条在混合模式下变成一条横贯屏幕的色带。
    """
    w, h = cover.size
    right_w = w - left_w
    left = cover.crop((0, 0, left_w, h)).convert("RGB")
    right = cover.crop((left_w, 0, w, h)).convert("RGB")

    def strip(x0: int, x1: int) -> Image.Image:
        band = cover.crop((x0, 0, x1, 56)).convert("RGBA")
        out = Image.new("RGBA", (x1 - x0, h), (0, 0, 0, 0))
        out.paste(band, (0, 0))
        return out

    return {"left": left, "right": right, "strip": strip(0, left_w),
            "strip2": strip(left_w, w)}


def write_png(img: Image.Image, path: str) -> int:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    return os.path.getsize(path)


def build(check_only: bool = False) -> int:
    font_path = find_font()
    cjk_path = find_cjk_font()
    print(f"font     = {font_path}")
    print(f"cjk font = {cjk_path}")
    failures: list[str] = []

    for name, (w, h) in VARIANTS.items():
        left_w = w // 2
        out_dir = os.path.join(OUT_ROOT, "base", "art", name)
        # (宽, 高, 模式, 是否要求"仅顶部 56 行不透明")
        files = {
            "Title.png": (left_w, h, "RGB", False),
            "Title2.png": (w - left_w, h, "RGB", False),
            "Title3.png": (left_w, h, "RGBA", True),
            "Title4.png": (w - left_w, h, "RGBA", True),
        }

        if check_only:
            for fn, want in files.items():
                path = os.path.join(out_dir, fn)
                if not os.path.isfile(path):
                    failures.append(f"{name}/{fn}: 缺失")
                    continue
                with Image.open(path) as im:
                    if im.size != want[:2]:
                        failures.append(f"{name}/{fn}: 尺寸 {im.size} != {want[:2]}")
                    if im.mode != want[2]:
                        failures.append(f"{name}/{fn}: 模式 {im.mode} != {want[2]}")
                    arr = np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0
                    if arr.mean() < 0.02:
                        failures.append(f"{name}/{fn}: 近乎纯黑（mean={arr.mean():.4f}），疑似空图")
                    if want[3]:
                        a = np.asarray(im.getchannel("A"), dtype=np.uint8)
                        if a[56:].max() > 4:
                            failures.append(f"{name}/{fn}: 第 56 行以下不透明（max={a[56:].max()}），"
                                            "加法混合时会盖住画面")
                print(f"  OK(checked) {name}/{fn} {os.path.getsize(path)}B")
            continue

        print(f"[{name}] 渲染 {w}x{h} ...")
        cover = render_cover(w, h, font_path, cjk_path)

        # 守卫：整幅全黑（历史上真发生过 —— 一张不透明黑色贴图把天空整片盖掉）
        cm = np.asarray(cover, dtype=np.float32).mean() / 255.0
        if cm < 0.05:
            raise SystemExit(f"[{name}] 封面几乎全黑（mean={cm:.4f}），拒绝输出")
        print(f"  cover mean luma = {cm:.3f}")

        parts = split_variant(cover, left_w)
        targets = {
            "Title.png": parts["left"],
            "Title2.png": parts["right"],
            "Title3.png": parts["strip"],
            "Title4.png": parts["strip2"],
        }
        for fn, want in files.items():
            img = targets[fn]
            assert img.size == want[:2], f"{name}/{fn} 尺寸 {img.size} != {want[:2]}"
            assert img.mode == want[2], f"{name}/{fn} 模式错误：{img.mode}"
            if want[3]:
                a = np.asarray(img.getchannel("A"), dtype=np.uint8)
                assert a[56:].max() <= 4, f"{name}/{fn} 第 56 行以下必须全透明"
            size = write_png(img, os.path.join(out_dir, fn))
            print(f"  {fn:24s} {img.size[0]}x{img.size[1]}  {size/1024:.0f} KB")

        # 工坊预览 / 海报 / 图标
        prev = make_preview(cover, 256)
        assert prev.size == (256, 256) and prev.mode == "RGB"
        psize = write_png(prev, os.path.join(OUT_ROOT, "base", f"preview_{name}.png"))
        if psize > 1024000:
            failures.append(f"{name}/preview.png 超过 1024000 字节：{psize}")

        post = make_poster(cover, 512)
        assert post.size == (512, 512)
        write_png(post, os.path.join(OUT_ROOT, "base", f"poster_{name}.png"))
        write_png(make_icon(cover, 64), os.path.join(OUT_ROOT, "base", f"icon_{name}.png"))
        write_png(cover, os.path.join(OUT_ROOT, "base", f"cover_{name}.png"))
        print(f"  preview_{name}.png 256x256 {psize/1024:.0f} KB")

    if failures:
        print("\n校验失败：", file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        return 1
    print("\n全部完成。")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 PZ 主菜单封面美术（程序化、可复现）")
    ap.add_argument("--check", action="store_true", help="只校验已生成文件")
    args = ap.parse_args()
    return build(check_only=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
