#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成两个口味的**原版左侧侧边栏图标**（纯 Pillow 绘制，不联网）：

    Contents/mods/Bin2NPCExtensionVanilla/42.21/media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png
    Contents/mods/Bin2NPCExtensionYese/42.21/media/ui/Sidebar/<尺寸>/Trade_{On,Off}_<尺寸>.png

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

两侧的解析度都按 8 倍超采样画完再缩（LANCZOS），48px 下边缘才不会锯齿。

两个口味各画什么
----------------
  * 原版钞票口味（`NPC_*`）：人形剪影（NPC），右下角一枚金币 —— 用原版钞票雇人。
  * YeseMarket 口味（`Trade_*`）：一个交易摊位（遮阳篷 + 两根柱子 + 柜台），柜台上方一枚金币。
    这一格点下去开关的是 YeseMarket 的**幸存者交易站**窗口（见公共层
    Bin2NPCExtensionCore/Sidebar.lua 与变体里的 ui/Entry.lua）。
  * 两态语义与原版一致：Off 偏灰、On 更亮（金币带一圈光晕）。贴图名分别是
    `NPC_{On,Off}_<尺寸>.png` / `Trade_{On,Off}_<尺寸>.png`，由各口味的 ui 层写死。

用法：
    python3 tools/make_icons.py            # 重新生成两套（会打印每张图的实测尺寸）
    python3 tools/make_icons.py --check    # 只校验现有图（尺寸/模式/透明背景）
    python3 tools/make_icons.py --check --only Trade   # 只校验一套（贴图名）

注意：YeseMarket 那一套不在 tools/fork_variant.py 的机械产出里（源口味没有侧边栏入口，
替换产不出它们），所以它们在生成器的 GENERATED_ELSEWHERE 里登记，由本脚本负责。
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)                       # bin2_npc_extension/
MOD_VERSION = os.environ.get("MOD_VERSION", "42.21")

# 原版侧边栏的五个尺寸档（ISEquippedItem.setTextureWidth）
SIZES = (48, 64, 80, 96, 128)
SUPERSAMPLE = 8                                        # 先画 8 倍再缩，边缘才不锯齿

# ---- 调色板：Off 偏灰，On 更亮（与原版"Off 暗 / On 亮"的两态语义一致）----
PERSON_OFF = (185, 191, 200, 255)
PERSON_ON = (255, 255, 255, 255)
COIN_OFF = (176, 138, 62, 255)
COIN_ON = (255, 206, 92, 255)
COIN_EDGE_OFF = (120, 92, 38, 255)
COIN_EDGE_ON = (236, 170, 48, 255)
GLOW_ON = (255, 206, 92, 90)

BODY_OFF = (176, 183, 194, 255)                        # 摊位主体（篷布/柱子）
BODY_ON = (255, 255, 255, 255)
ACCENT_OFF = (118, 126, 138, 255)                      # 篷布条纹 / 柜台台面
ACCENT_ON = (192, 200, 214, 255)
COUNTER_OFF = (146, 154, 166, 255)                     # 柜台立面
COUNTER_ON = (232, 238, 246, 255)


def coin(draw, cx, cy, radius, state):
    """一枚金币：On 态先铺一圈半透明光晕，再画外圈 + 内圈 + 一道横槽。"""
    coin_fill = COIN_ON if state == "On" else COIN_OFF
    edge = COIN_EDGE_ON if state == "On" else COIN_EDGE_OFF
    if state == "On":
        glow_r = radius * 1.55
        draw.ellipse([cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r], fill=GLOW_ON)
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=edge)
    inner = radius * 0.78
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=coin_fill)
    # 硬币上的一道横槽，48px 下也能看出"这是钱"而不是一个圆点
    slot_w, slot_h = radius * 0.95, radius * 0.16
    draw.rounded_rectangle([cx - slot_w / 2, cy - slot_h / 2, cx + slot_w / 2, cy + slot_h / 2],
                           radius=slot_h / 2, fill=edge)


def render_recruit(size, state):
    """原版钞票口味：人形剪影（NPC）+ 右下角一枚金币。"""
    width, height = size
    scale = SUPERSAMPLE
    canvas = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    w, h = width * scale, height * scale

    person = PERSON_ON if state == "On" else PERSON_OFF

    # ---- 人形：头（圆）+ 肩（圆角矩形，下边与画布留一点边距）
    head_r = 0.155 * h
    head_cx, head_cy = 0.335 * w, 0.275 * h
    draw.ellipse([head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r], fill=person)

    body_top, body_bottom = 0.53 * h, 0.92 * h
    body_left, body_right = 0.125 * w, 0.545 * w
    draw.rounded_rectangle([body_left, body_top, body_right, body_bottom],
                           radius=0.10 * h, fill=person)

    # ---- 金币
    coin(draw, 0.745 * w, 0.675 * h, 0.205 * h, state)

    return canvas.resize(size, Image.LANCZOS)


def render_market(size, state):
    """YeseMarket 口味：交易摊位（遮阳篷 + 两根柱子 + 柜台）+ 柜台上方一枚金币。"""
    width, height = size
    scale = SUPERSAMPLE
    canvas = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    w, h = width * scale, height * scale

    body = BODY_ON if state == "On" else BODY_OFF
    accent = ACCENT_ON if state == "On" else ACCENT_OFF
    counter = COUNTER_ON if state == "On" else COUNTER_OFF

    # ---- 遮阳篷：一条横带 + 三道竖条纹（一眼看出是"摊位"而不是一个方块）
    canopy_top, canopy_bottom = 0.09 * h, 0.36 * h
    draw.rounded_rectangle([0.04 * w, canopy_top, 0.96 * w, canopy_bottom],
                           radius=0.07 * h, fill=body)
    stripe_w = 0.075 * w
    for center in (0.25 * w, 0.50 * w, 0.75 * w):
        draw.rectangle([center - stripe_w / 2, canopy_top + 0.05 * h,
                        center + stripe_w / 2, canopy_bottom - 0.03 * h], fill=accent)

    # ---- 两根柱子（撑住篷子）
    for left in (0.135 * w, 0.795 * w):
        draw.rectangle([left, canopy_bottom - 0.02 * h, left + 0.07 * w, 0.72 * h], fill=body)

    # ---- 柜台：台面（深一点）+ 立面
    draw.rounded_rectangle([0.04 * w, 0.66 * h, 0.96 * w, 0.92 * h],
                           radius=0.06 * h, fill=counter)
    draw.rectangle([0.04 * w, 0.66 * h, 0.96 * w, 0.745 * h], fill=accent)

    # ---- 金币：柜台上方、两根柱子之间
    coin(draw, 0.50 * w, 0.525 * h, 0.135 * h, state)

    return canvas.resize(size, Image.LANCZOS)


# 口味 -> (模组目录名, 贴图基名, 画法)。贴图基名必须与各口味 ui 层里的 spec.texture 一致。
FLAVOURS = (
    {"mod": "Bin2NPCExtensionVanilla", "texture": "NPC", "render": render_recruit,
     "what": "人形剪影 + 金币（原版钞票雇人）"},
    {"mod": "Bin2NPCExtensionYese", "texture": "Trade", "render": render_market,
     "what": "交易摊位（遮阳篷 + 柜台 + 金币）—— 开关幸存者交易站"},
)


def target_dir(flavour, size):
    return os.path.join(ITEM_DIR, "Contents", "mods", flavour["mod"], MOD_VERSION,
                        "media", "ui", "Sidebar", str(size))


def icon_path(flavour, size, state):
    return os.path.join(target_dir(flavour, size),
                        "%s_%s_%d.png" % (flavour["texture"], state, size))


def selected_flavours(only):
    if only is None:
        return FLAVOURS
    wanted = [f for f in FLAVOURS if f["texture"] == only or f["mod"] == only]
    if not wanted:
        raise SystemExit("--only 只认 %s"
                         % " / ".join("%s(%s)" % (f["texture"], f["mod"]) for f in FLAVOURS))
    return tuple(wanted)


def write_icons(flavours):
    written = 0
    for flavour in flavours:
        for width in SIZES:
            height = int(round(width * 0.75))
            os.makedirs(target_dir(flavour, width), exist_ok=True)
            for state in ("Off", "On"):
                image = flavour["render"]((width, height), state)
                path = icon_path(flavour, width, state)
                image.save(path, "PNG", optimize=True)
                print("  %-62s %dx%d  %d bytes"
                      % (os.path.relpath(path, ITEM_DIR), image.width, image.height,
                         os.path.getsize(path)))
                written += 1
    return written


def check_icons(flavours):
    problems = 0
    for flavour in flavours:
        for width in SIZES:
            height = int(round(width * 0.75))
            for state in ("Off", "On"):
                path = icon_path(flavour, width, state)
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
                    print("  [ok] %-62s %dx%d %s"
                          % (os.path.relpath(path, ITEM_DIR), got[0], got[1], mode))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="生成/校验两个口味的原版侧边栏图标")
    parser.add_argument("--check", action="store_true", help="只校验现有图标")
    parser.add_argument("--only", default=None,
                        help="只处理一套（贴图名 NPC/Trade，或模组目录名）")
    args = parser.parse_args()
    flavours = selected_flavours(args.only)

    print("== 原版侧边栏图标（%s）==" % ("校验" if args.check else "生成"))
    for flavour in flavours:
        print("  %s -> %s_*  %s" % (flavour["mod"], flavour["texture"], flavour["what"]))
    print("")

    if args.check:
        problems = check_icons(flavours)
        if problems:
            print("\n%d 处问题" % problems)
            return 1
        print("\n图标齐全且尺寸正确（%d 套 x %d 档 x 2 态 = %d 张）"
              % (len(flavours), len(SIZES), len(flavours) * len(SIZES) * 2))
        return 0

    written = write_icons(flavours)
    print("\n已生成 %d 张" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
