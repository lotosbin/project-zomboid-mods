#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成小红书笔记素材（第七篇知识贴）：纸甲 + 拆枕头取海绵（bin2 扩展 1.7.3）—— 4 张图文卡 + 文案。

来源（全部自己核过）：
  · 配方本体 = 模组脚本 `bin2_Recipes.txt`：`Bin2MakePaperArmorBody`(295 行)、
    `Bin2MakePaperArmorForearm`(312)、`Bin2MakeSponge`(347)；mod.info `modversion=1.7.3`
  · 中文名 = 模组 `Recipes.json`（制作纸胸甲 / 制作纸护臂 (左) / 拆枕头取海绵）
    ＋ 游戏自带 `ItemName.json`（杂志胸甲 / 杂志护臂 (左) / 枕头 / 海绵 / 管道胶带 / 纸张）
  · 原版期刊护甲 = `recipes_tailoring_armor.txt`（8 期刊+4 胶带 / 1 期刊+2 胶带），本模组未改
  · 海绵的两口消耗 = `recipes_gasmasks.txt` 的 `MakeCraftedGasMaskFilter`、`RechargeFilters`，
    两条都带 NeedToBeLearn = true ⇔ 「能做海绵 ≠ 能用海绵」

★ 红线：只写"过了脚本解析器"，**不写"实测可用"**；正文里保留"还没在游戏里真做过一件"。
★ 上线判据：远端 `time_updated` 变新（2026-10-19 14:05:06，207717 字节）——本机副本不参与判断。

用法：python3 make_note_paperarmor.py [输出目录]    默认 docs/xhs/笔记素材-纸甲
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, paste_icon, new_card, footer, draw_row,
)

OUT_DEFAULT = os.path.join(HERE, "笔记素材-纸甲")
MOD_INFO = os.path.join(HERE, "..", "..", "bin2_b42", "Contents", "mods",
                        "bin2_extension", "42.19.0", "mod.info")


def mod_version():
    try:
        with open(MOD_INFO, encoding="utf-8") as f:
            m = re.search(r"^modversion=(.+)$", f.read(), re.M)
        return m.group(1).strip() if m else "?"
    except OSError:
        return "?"


VERSION = mod_version()

FILES = ["1-缺口.png", "2-纸胸甲.png", "3-纸护臂与海绵.png", "4-说明.png"]


# ── 卡 1：原版能拿期刊做护甲，纸张做不了 ─────────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 92), "僵毁 Build 42 · 纸张 → 护甲", font=font(36), fill=ACCENT2)
    d.text((72, 152), "纸能做的东西，又多一样", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 276), (W - 56, 700)], radius=22, fill=CARD)
    d.text((92, 306), "游戏自带脚本里，护甲这条路的现状", font=font(28), fill=DIM)
    rows = [
        ("2", "条原版配方拿期刊做护甲 —— 杂志胸甲、杂志护臂", FG),
        ("0", "条配方拿纸张做护甲 —— 纸张只能做爆竹材料", ACCENT),
        ("12", "张纸刚好是一次「造纸」的产量", GOOD),
    ]
    y = 372
    for num, label, color in rows:
        d.text((92, y), num, font=font(72, True), fill=color)
        d.text((238, y + 22), label, font=font(30), fill=(214, 219, 228))
        y += 100

    d.text((72, 736), "期刊护甲的原版代价：8 本期刊 + 4 卷管道胶带 → 杂志胸甲", font=font(29), fill=DIM)
    d.text((72, 780), "纸甲就照这条代价换算，不额外加难度门槛。", font=font(29), fill=DIM)

    y = 860
    paste_icon(img, "Item_Paper", (92, y), 70)
    paste_icon(img, "Item_DuctTape", (200, y), 70)
    d.text((300, y + 6), "纸张来自 1.7.2 的「造纸」：", font=font(31), fill=(200, 206, 216))
    d.text((300, y + 50), "1 木板 + 1 锅具 + 1 升水 → 12 张", font=font(31, True), fill=FG)

    d.text((72, 1030), "1.7.3 加了两条：" , font=font(38, True), fill=ACCENT2)
    d.text((72, 1090), "「制作纸胸甲」、「制作纸护臂 (左)」", font=font(54, True), fill=FG)
    footer(d, "数据：模组脚本 bin2_Recipes.txt + 游戏自带 recipes_tailoring_armor.txt")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：制作纸胸甲 ────────────────────────────────────────────
def card2(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 制作纸胸甲", font=font(36), fill=ACCENT2)
    d.text((72, 152), "12 张纸 + 4 卷胶带 → 杂志胸甲", font=font(54, True), fill=FG)

    d.rounded_rectangle([(56, 272), (W - 56, 664)], radius=22, fill=CARD)
    d.text((88, 302), "制作纸胸甲", font=font(48, True), fill=FG)
    meta = "缝纫 1 级 · 100 秒"
    d.text((W - 88 - d.textlength(meta, font=font(30)), 318), meta, font=font(30), fill=DIM)

    draw_row(img, d, 392, [("Item_Paper", 12, "纸张"),
                           ("Item_DuctTape", 4, "管道胶带")], font(25), slot=170)
    d.text((470, 404), "→", font=font(46), fill=DIM)
    paste_icon(img, "Item_MagazineArmour_Chest", (552, 388), 66)
    d.text((620, 376), "杂志胸甲", font=font(34, True), fill=GOOD)
    d.text((620, 420), "（原版那件）", font=font(26), fill=DIM)

    yy = 552
    for line in ["任意平面就能做，不用工作台（AnySurfaceCraft）",
                 "做出来的不是新物品 —— 就是游戏原本那件杂志胸甲"]:
        d.text((92, yy), line, font=font(28), fill=(170, 178, 190))
        yy += 42

    d.rounded_rectangle([(56, 700), (W - 56, 1150)], radius=22, fill=CARD)
    d.text((92, 728), "为什么是 12 张", font=font(34, True), fill=ACCENT2)
    yy = 796
    for title, body in [
        ("一次造纸正好 12 张", "做一件胸甲刚好用完，不用为一件甲反复造纸。"),
        ("代价继承原版", "纸甲沾水即毁 —— 便宜，但下雨天别穿。"),
        ("原版两条没动", "8 期刊+4 胶带那条期刊护甲照旧能造。"),
        ("不新增物品", "不新增图标、不改原版物品定义，装了就能用。"),
    ]:
        d.ellipse([(94, yy + 12), (112, yy + 30)], fill=ACCENT2)
        d.text((136, yy), title, font=font(34), fill=FG)
        d.text((136, yy + 46), body, font=font(29), fill=DIM)
        yy += 86

    footer(d, f"配方：bin2_Recipes.txt 的 Bin2MakePaperArmorBody（模组 {VERSION}）")
    img.save(os.path.join(out, FILES[1]))


# ── 卡 3：纸护臂 + 拆枕头取海绵 ─────────────────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 另外两条", font=font(36), fill=ACCENT2)
    d.text((72, 152), "护臂，还有海绵", font=font(64, True), fill=FG)

    # 上：纸护臂
    d.rounded_rectangle([(56, 268), (W - 56, 660)], radius=22, fill=CARD)
    d.text((88, 296), "制作纸护臂 (左)", font=font(44, True), fill=FG)
    meta = "手持 · 100 秒"
    d.text((W - 88 - d.textlength(meta, font=font(28)), 312), meta, font=font(28), fill=DIM)
    draw_row(img, d, 380, [("Item_Paper", 4, "纸张"),
                           ("Item_DuctTape", 2, "管道胶带")], font(24), slot=150)
    d.text((430, 392), "→", font=font(44), fill=DIM)
    paste_icon(img, "Item_MagazineArmour", (508, 376), 64)
    d.text((576, 366), "杂志护臂 (左)", font=font(32, True), fill=GOOD)
    d.text((576, 408), "护臂一件就碎，纸的代价照付", font=font(26), fill=DIM)

    # 下：拆枕头
    d.rounded_rectangle([(56, 700), (W - 56, 1180)], radius=22, fill=CARD)
    d.text((88, 728), "拆枕头取海绵", font=font(44, True), fill=FG)
    meta = "手持 · 30 秒"
    d.text((W - 88 - d.textlength(meta, font=font(28)), 744), meta, font=font(28), fill=DIM)
    draw_row(img, d, 812, [("Item_Pillow", 1, "枕头"),
                           ("Item_Scissors", 1, "剪刀/锋利刀"), ], font(23), slot=170)
    d.text((470, 824), "→", font=font(44), fill=DIM)
    paste_icon(img, "Item_Sponge", (548, 810), 62)
    d.text((612, 800), "×2 海绵", font=font(34, True), fill=GOOD)
    d.text((612, 848), "刀剪是保留的，会磨损", font=font(26), fill=DIM)

    yy = 930
    for line in wrap(d, "原版「海绵」只有搜刮和杂物两条来路，而防毒面具的两条配方都要吃它"
                        "（制作防毒面具滤芯、更换过滤器，各 1 块；两条都得先学会）。", font(28), W - 190):
        d.text((92, yy), line, font=font(28), fill=(190, 198, 210))
        yy += 40
    d.text((92, yy + 10), "一个枕头正好够两次滤芯。", font=font(28, True), fill=ACCENT2)

    footer(d, f"配方：Bin2MakePaperArmorForearm / Bin2MakeSponge（模组 {VERSION}）")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：边界与说法 ───────────────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 三句话", font=font(36), fill=ACCENT2)
    d.text((72, 152), "装上之前，先说清边界", font=font(60, True), fill=FG)

    y = 280
    blocks = [
        ("名字别混", "配方叫「制作纸胸甲」，做出来的是游戏原本那件「杂志胸甲」——"
                     "我们没做新护甲，只是多了一条用纸的路。"),
        ("代价照旧", "纸甲沾水即毁、护臂一件就碎；12 张纸 = 一次造纸的产量。"),
        ("还没实测", ["这三条只过了游戏自带的脚本解析器",
                     "（16 条配方全部解析通过），我还没在游戏里",
                     "真做过一件 —— 合成面板里能不能点出来，要等你试。"]),
    ]
    for title, body in blocks:
        lines = body if isinstance(body, list) else wrap(d, body, font(30), W - 200)
        h = 104 + 42 * len(lines)
        d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=20, fill=CARD)
        d.text((92, y + 24), title, font=font(38, True), fill=ACCENT2)
        yy = y + 78
        for line in lines:
            d.text((92, yy), line, font=font(30), fill=(214, 219, 228))
            yy += 42
        y += h + 28

    d.text((72, 1120), "模组：bin2 扩展 · 工坊搜 bin2's B42 mods", font=font(32), fill=FG)
    d.text((72, 1170), "条目 3628652563 · 需要 Build 42.21.0 以上", font=font(30), fill=DIM)
    footer(d, f"版本 {VERSION} · 数据来源见文案.md 的事实段")
    img.save(os.path.join(out, FILES[3]))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT_DEFAULT
    os.makedirs(out, exist_ok=True)
    card1(out)
    card2(out)
    card3(out)
    card4(out)
    print(f"已生成 4 张到 {out}（模组版本 {VERSION}）")


if __name__ == "__main__":
    main()
