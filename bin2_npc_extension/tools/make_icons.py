#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Bin2NPCExtensionVanilla 的原版左侧侧边栏图标（纯 Pillow 绘制，不联网）：

    Contents/mods/Bin2NPCExtensionVanilla/42.21/media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png

为什么尺寸是硬约束（不是审美选择）
----------------------------------
原版侧边栏 `media/lua/client/ISUI/ISEquippedItem.lua`：

  * `setTextureWidth()` 按 `getCore():getOptionSidebarSize()` 把 `TEXTURE_WIDTH` 定成
    48 / 64 / 80 / 96 / 128（外加 size==6 走字号分支）；
  * `TEXTURE_HEIGHT = TEXTURE_WIDTH * 0.75`；
  * 贴图路径写死为 `media/ui/Sidebar/<TEXTURE_WIDTH>/<名字>_<On|Off>_<TEXTURE_WIDTH>.png`。

实测原版贴图的真实像素（`sips -g pixelWidth -g pixelHeight`）就是 48x36 / 64x48 / 80x60 /
96x72 / 128x96 —— 与上面两行完全一致。所以我们的图标必须**每一档都出**这两态，
比例也要一致；否则玩家在选项里换"侧边栏尺寸"时，我们的图标要么被拉伸要么错位
（`ISButton:render` 对"比按钮大"的贴图走 drawTextureScaledAspect，一拉伸就糊）。

画什么
------
左侧一个人形剪影（NPC），右下角一枚金币（用原版钞票雇人）——
Off 偏灰、On 更亮且金币带一圈光晕，与原版"Off 暗 / On 亮"的两态语义一致。

用法：
    python3 tools/make_icons.py            # 重新生成（会打印每张图的实测尺寸）
    python3 tools/make_icons.py --check    # 只校验现有图（尺寸/模式/文件大小）
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)                       # bin2_npc_extension/
MOD_VERSION = os.environ.get("MOD_VERSION", "42.21")
VANILLA_MOD = "Bin2NPCExtensionVanilla"

# 原版侧边栏的五个尺寸档（ISEquippedItem.setTextureWidth）
SIZES = (48, 64, 80, 96, 128)
SUPERSAMPLE = 8                                        # 先画 8 倍再缩，边缘才不锯齿

PERSON_OFF = (185, 191, 200, 255)
PERSON_ON = (255, 255, 255, 255)
COIN_OFF = (176, 138, 62, 255)
COIN_ON = (255, 206, 92, 255)
COIN_EDGE_OFF = (120, 92, 38, 255)
COIN_EDGE_ON = (214, 152, 40, 255)
GLOW_ON = (255, 206, 92, 90)


def target_dir(size: int) -> str:
    return os.path.join(ITEM_DIR, "Contents", "mods", VANILLA_MOD, MOD_VERSION,
                        "media", "ui", "Sidebar", str(size))


def icon_path(size: int, state: str) -> str:
    return os.path.join(target_dir(size), "NPC_%s_%d.png" % (state, size))


def render_icon(size: tuple[int, int], state: str) -> Image.Image:
    """按 8 倍超采样画一张；size 是本档的 (宽, 高) = (W, 0.75W)。"""
    width, height = size
    scale = SUPERSAMPLE
    canvas = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    w, h = width * scale, height * scale

    person = PERSON_ON if state == "On" else PERSON_OFF
    coin = COIN_ON if state == "On" else COIN_OFF
    edge = COIN_EDGE_ON if state == "On" else COIN_EDGE_OFF

    # ---- 人形：头（圆）+ 肩（圆角矩形，下边与画布留一点边距）
    head_r = 0.155 * h
    head_cx, head_cy = 0.335 * w, 0.275 * h
    draw.ellipse([head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r], fill=person)

    body_top, body_bottom = 0.53 * h, 0.92 * h
    body_left, body_right = 0.125 * w, 0.545 * w
    radius = 0.10 * h
    draw.rounded_rectangle([body_left, body_top, body_right, body_bottom],
                           radius=radius, fill=person)

    # ---- 金币：右下角，On 态先铺一圈半透明光晕
    coin_r = 0.205 * h
    coin_cx, coin_cy = 0.745 * w, 0.675 * h
    if state == "On":
        glow_r = coin_r * 1.55
        draw.ellipse([coin_cx - glow_r, coin_cy - glow_r, coin_cx + glow_r, coin_cy + glow_r], fill=GLOW_ON)
    draw.ellipse([coin_cx - coin_r, coin_cy - coin_r, coin_cx + coin_r, coin_cy + coin_r],
                 fill=edge)
    inner = coin_r * 0.78
    draw.ellipse([coin_cx - inner, coin_cy - inner, coin_cx + inner, coin_cy + inner], fill=coin)
    # 硬币上的一道横槽，48px 下也能看出"这是钱"而不是一个圆点
    slot_w, slot_h = coin_r * 0.95, coin_r * 0.16
    draw.rounded_rectangle([coin_cx - slot_w / 2, coin_cy - slot_h / 2,
                            coin_cx + slot_w / 2, coin_cy + slot_h / 2],
                           radius=slot_h / 2, fill=edge)

    return canvas.resize(size, Image.LANCZOS)


def write_icons() -> int:
    written = 0
    for width in SIZES:
        height = int(round(width * 0.75))
        os.makedirs(target_dir(width), exist_ok=True)
        for state in ("Off", "On"):
            image = render_icon((width, height), state)
            path = icon_path(width, state)
            image.save(path, "PNG", optimize=True)
            print("  %-58s %dx%d  %d bytes"
                  % (os.path.relpath(path, ITEM_DIR), image.width, image.height,
                     os.path.getsize(path)))
            written += 1
    return written


def check_icons() -> int:
    problems = 0
    for width in SIZES:
        height = int(round(width * 0.75))
        for state in ("Off", "On"):
            path = icon_path(width, state)
            if not os.path.isfile(path):
                print("  [缺] %s" % os.path.relpath(path, ITEM_DIR))
                problems += 1
                continue
            with Image.open(path) as image:
                got = image.size
                mode = image.mode
                has_alpha = image.convert("RGBA").getextrema()[3][0] < 255
            want = (width, height)
            flags = []
            if got != want:
                flags.append("尺寸应为 %s，实际 %s" % (want, got))
            if mode != "RGBA":
                flags.append("模式应为 RGBA，实际 %s" % mode)
            if not has_alpha:
                flags.append("整张不透明（侧边栏图标必须有透明背景）")
            if flags:
                print("  [错] %s：%s" % (os.path.relpath(path, ITEM_DIR), "；".join(flags)))
                problems += 1
            else:
                print("  [ok] %-58s %dx%d %s"
                      % (os.path.relpath(path, ITEM_DIR), got[0], got[1], mode))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="生成/校验原版侧边栏 NPC 图标")
    parser.add_argument("--check", action="store_true", help="只校验现有图标")
    args = parser.parse_args()

    print("== 原版侧边栏图标（%s）==" % ("校验" if args.check else "生成"))
    if args.check:
        problems = check_icons()
        if problems:
            print("\n%d 处问题" % problems)
            return 1
        print("\n图标齐全且尺寸正确（%d 档 x 2 态）" % len(SIZES))
        return 0
    written = write_icons()
    print("\n已生成 %d 张" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
