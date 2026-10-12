#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成小红书笔记素材：4 张图文卡（用游戏原生图标）+ 文案。

每一条都可复核，来源写进「事实来源」：
  · 5 条配方与材料/产出/耗时/技能
        -> bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt
  · 中文配方名     -> .../media/lua/shared/Translate/CN/Recipes.json
  · 「新增 5 条」   -> git show aa9f32a（feat: 补齐缺失配方 5 条,版本 1.7.0）
  · 消耗条数 33/11/10/9/3 -> docs/craft-recipe-study.md 14.2（扫 969 条原版 craftRecipe）
  · 已上线         -> appworkshop_108600.acf 的 timeupdated=1791812609（2026-10-12 21:43:29）
  · 物品图标       -> docs/xhs/游戏图标素材/（@bin2_extension_mod_dev 用 pz_atlas 从
                      UI2.pack/UI.pack 导出；sprite 名→物品 ID 见 manifest.json）

用法：python3 make_note.py [输出目录]
"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1440
BG = (18, 20, 24)
CARD = (30, 34, 41)
FG = (238, 240, 244)
DIM = (150, 158, 170)
ACCENT = (255, 92, 92)
ACCENT2 = (255, 190, 80)
GOOD = (110, 210, 150)

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_DIR = os.path.join(HERE, "游戏图标素材")

FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
]


def font(size, bold=False):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size, index=1 if bold else 0)
            except Exception:
                try:
                    return ImageFont.truetype(p, size)
                except Exception:
                    continue
    return ImageFont.load_default()


def wrap(d, text, f, max_w):
    lines, cur = [], ""
    for ch in text:
        if ch == "\n":
            lines.append(cur); cur = ""; continue
        if d.textlength(cur + ch, font=f) <= max_w:
            cur += ch
        else:
            lines.append(cur); cur = ch
    if cur:
        lines.append(cur)
    return lines


def icon(sprite, size=128):
    path = os.path.join(ICON_DIR, f"{sprite}@4x.png")
    if not os.path.exists(path):
        path = os.path.join(ICON_DIR, f"{sprite}.png")
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    if im.size != (size, size):
        im = im.resize((size, size), Image.NEAREST)
    return im


def paste_icon(base, sprite, xy, size=128):
    im = icon(sprite, size)
    if im is None:
        return False
    base.paste(im, xy, im)
    return True


def new_card():
    img = Image.new("RGB", (W, H), BG)
    return img, ImageDraw.Draw(img)


def footer(d, text):
    d.text((72, H - 92), text, font=font(28), fill=DIM)


# ── 卡 1：问题 ───────────────────────────────────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 104), "僵毁 Build 42 · 原版配方缺口", font=font(38), fill=ACCENT2)
    y = 178
    for line in ["这些东西", "原版没法自己造"]:
        d.text((72, y), line, font=font(74, True), fill=FG)
        y += 94

    y += 26
    rows = [
        ("Item_NutsBolts", "螺母与螺栓", 33, ACCENT),
        ("Item_CircularSawBlade", "圆锯片", 11, ACCENT),
        ("Item_Screws", "螺丝", 10, ACCENT2),
        ("Item_Glue", "胶水", 9, ACCENT2),
        ("Item_Sawblade", "手锯条", 3, DIM),
    ]
    for sprite, name, n, color in rows:
        paste_icon(img, sprite, (72, y - 14), 74)
        d.text((170, y), name, font=font(42), fill=FG)
        d.text((496, y - 24), str(n), font=font(96, True), fill=color)
        d.text((648, y + 12), "条配方要用它", font=font(34), fill=DIM)
        y += 112

    y += 14
    d.line([(72, y), (W - 72, y)], fill=(60, 66, 76), width=2)
    y += 36
    for line in ["没有一条能用材料把它们做出来的配方，", "只能拆家具、翻箱子搜刮碰运气。"]:
        d.text((72, y), line, font=font(40), fill=(200, 206, 216))
        y += 58

    footer(d, "数据：扫描原版 969 条 craftRecipe")
    img.save(os.path.join(out, "1-缺口.png"))


# ── 卡 2+3：5 条配方（材料 → 产出）───────────────────────────────
# sprite 名取自 游戏图标素材/ 里真实存在的文件；材料清单照抄 bin2_Recipes.txt
# 标签用游戏内实际物品名（对照 游戏图标素材/manifest.json 的 cn 字段）
HAM = "锤子"        # Base.SmithingHammer 铁匠锤（材料标签也收 base:hammer;base:ballpeenhammer）
PLI = "钳子"        # Base.MetalworkingPliers 金属加工钳（也收 base:tongs 火钳）
CHI = "凿子"        # Base.MetalworkingChisel 金属加工凿
RECIPES = [
    dict(
        name="制作螺母螺栓", lv="金工 1 级", time="200 秒", out_n=6,
        mats=[("Item_Charcoal", 1, "木炭"), ("Item_IronChunk", 1, "铁块/钢块"),
              ("Item_SmithingHammer", 0, HAM), ("Item_Pliers_Forged", 0, PLI)],
        prod="Item_NutsBolts",
    ),
    dict(
        name="制作螺丝", lv="金工 1 级", time="200 秒", out_n=6,
        mats=[("Item_Charcoal", 1, "木炭"), ("Item_IronChunk", 1, "铁块/钢块"),
              ("Item_SmithingHammer", 0, HAM), ("Item_Pliers_Forged", 0, PLI)],
        prod="Item_Screws",
    ),
    dict(
        name="制作圆锯片", lv="金工 2 级", time="300 秒", out_n=1,
        mats=[("Item_Charcoal", 2, "木炭"), ("Item_SheetMetal", 1, "金属板"),
              ("Item_SmithingHammer", 0, HAM), ("Item_HotChisel_Forged", 0, CHI),
              ("Item_Pliers_Forged", 0, PLI)],
        prod="Item_CircularSawBlade",
    ),
    dict(
        name="制作手锯条", lv="金工 2 级", time="200 秒", out_n=2,
        mats=[("Item_Charcoal", 1, "木炭"), ("Item_MetalSheetSmall", 1, "小金属板"),
              ("Item_SmithingHammer", 0, HAM), ("Item_HotChisel_Forged", 0, CHI)],
        prod="Item_Sawblade",
    ),
    dict(
        name="熬制胶水", lv="烹饪 2 级", time="240 秒", out_n=2,
        mats=[("Item_Bone", 2, "动物骨头")],
        prod="Item_Glue",
        water="1 升水 + 1 口锅（锅里那些就是水）",
        vessels=["Item_Pot", "Item_SaucepanEmpty", "Item_Pot_Forged",
                 "Item_Kettle", "Item_CopperKettle", "Item_CopperPot"],
        vessel_note="共 6 种锅具任选，用完原样留手里",
        vessel_names=["蒸煮锅", "平底煮锅", "粗制蒸煮锅", "水壶", "铜制水壶", "铜平底煮锅"],
        legend=["图标旁的字是配方里的材料；锤子/钳子/凿子都收多个变体", "制盐同样收这 6 种锅具，只多烧 0.5 升水"],
    ),
]


def draw_row(img, d, y, items, f_lab, slot=92):
    """一行「图标 + 下方标签」，items = [(sprite, cnt, label)]；slot 可放宽给名字长的行"""
    ICON, SLOT = 62, slot
    x = 92
    for sprite, cnt, label in items:
        if not paste_icon(img, sprite, (x, y), ICON):
            continue
        if cnt and cnt > 1:
            d.text((x + ICON - 18, y - 6), f"×{cnt}", font=font(26), fill=ACCENT2)
        if label:
            f = f_lab
            while d.textlength(label, font=f) > SLOT - 8 and f.size > 15:
                f = font(f.size - 1)
            d.text((x + ICON / 2 - d.textlength(label, font=f) / 2, y + ICON + 12),
                   label, font=f, fill=DIM)
        x += SLOT
    return ICON + 46


def recipe_block(img, d, r, y, rh):
    """一格配方：材料图标 + 名称标签 → 产出图标 + 数量"""
    d.rounded_rectangle([(56, y), (W - 56, y + rh)], radius=22, fill=CARD)
    d.text((88, y + 14), r["name"], font=font(42, True), fill=FG)
    meta = f'{r["lv"]} · {r["time"]}'
    d.text((W - 88 - d.textlength(meta, font=font(30)), y + 24), meta, font=font(30), fill=DIM)

    f_lab = font(23)
    ICON, SLOT = 62, 92
    iy = y + 76
    x = 92
    for sprite, cnt, label in r["mats"]:
        if not paste_icon(img, sprite, (x, iy), ICON):
            continue
        if cnt > 1:
            d.text((x + ICON - 18, iy - 6), f"×{cnt}", font=font(26), fill=ACCENT2)
        lab = label.split("/")[0].split("（")[0]
        f = f_lab
        while d.textlength(lab, font=f) > SLOT - 8 and f.size > 15:
            f = font(f.size - 1)
        d.text((x + ICON / 2 - d.textlength(lab, font=f) / 2, iy + ICON + 12),
               lab, font=f, fill=DIM)
        x += SLOT

    d.text((x + 4, iy + 16), "→", font=font(40), fill=DIM)
    px = x + 58
    if paste_icon(img, r["prod"], (px, iy), ICON):
        d.text((px + ICON - 20, iy - 12), f'×{r["out_n"]}', font=font(36, True), fill=GOOD)

    # 需要容器/流体的配方另起几行。先把「要画几行」量出来，再把富余高度平摊成行距，
    # 这样内容不会被挤在顶上、也不会在中间留一块突兀的空白
    rows = []
    if r.get("water"):
        rows.append(("water", None))
    if r.get("vessels"):
        rows.append(("vessel_note", None))
        rows.append(("vessels", None))
    if r.get("legend"):
        rows.append(("legend", None))
    if not rows:
        return y + rh

    ROW_H = {"water": 74, "vessel_note": 40, "vessels": 108, "legend": 40 * len(r.get("legend") or []) + 20}
    used = (iy - y) + ICON + 46 + sum(ROW_H[k] for k, _ in rows)
    extra = max(0, rh - used) // (len(rows) + 1)

    ny = iy + ICON + 46 + extra
    for kind, _ in rows:
        if kind == "water":
            paste_icon(img, "Item_Pot_Water", (92, ny), 62)
            d.text((176, ny + 16), r["water"], font=font(30), fill=ACCENT2)
        elif kind == "vessel_note":
            d.text((92, ny), r.get("vessel_note", ""), font=font(28), fill=ACCENT2)
        elif kind == "vessels":
            names = r.get("vessel_names") or []
            items = [(s, 0, names[i] if i < len(names) else "") for i, s in enumerate(r["vessels"])]
            draw_row(img, d, ny, items, f_lab, slot=158)
        else:
            yy = ny + 6
            for line in r["legend"]:
                d.text((92, yy), line, font=font(27), fill=(150, 158, 170))
                yy += 40
        ny += ROW_H[kind] + extra
    return y + rh



def block_min_height(r):
    """这条配方至少要多高才画得下：标题 70 + 图标行 62 + 标签 46，
    需要锅具行再加 100，需要额外容器行再加 92"""
    h = 70 + 62 + 46
    if r.get("water"):
        h += 92
    if r.get("vessels"):
        h += 100
    if r.get("legend"):
        h += 40 * len(r["legend"]) + 20
    return h


def recipes_card(out, fname, header_small, header_big, rs, baseline, gap, note_lines, footer_text):
    """baseline = 一行普通配方想要的高度；总高不够/富余时按比例伸缩，让整张卡填满"""
    img, d = new_card()
    d.text((72, 92), header_small, font=font(36), fill=ACCENT2)
    d.text((72, 152), header_big, font=font(64, True), fill=FG)

    top, bottom = 258, H - 132                 # 页脚留白
    avail = bottom - top - gap * (len(rs) - 1)
    note_h = (40 + 46 * len(note_lines)) if note_lines else 0
    avail -= (note_h + gap if note_lines else 0)

    need = sum(block_min_height(r) for r in rs)
    nat = baseline * len(rs)
    target = max(avail, need)                  # 空间富余就撑满，不够就压到最低需求
    scale = target / nat
    heights = [max(block_min_height(r), round(baseline * scale)) for r in rs]
    # 缩放后可能溢出，从最高的那块往下削
    while sum(heights) > avail and max(heights) > max(block_min_height(r) for r in rs):
        i = heights.index(max(heights))
        heights[i] -= 4

    y = top
    for r, h in zip(rs, heights):
        y = recipe_block(img, d, r, y, h) + gap

    if note_lines:
        d.rounded_rectangle([(56, y), (W - 56, y + note_h)], radius=20, fill=(24, 28, 34))
        yy = y + 22
        for line in note_lines:
            d.text((92, yy), line, font=font(30), fill=(206, 212, 222))
            yy += 46
    footer(d, footer_text)
    img.save(os.path.join(out, fname))


# ── 卡 4：几点要知道的（收尾/行动卡）─────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 110), "bin2 扩展 v1.7.0", font=font(38), fill=ACCENT2)
    d.text((72, 178), "几点要知道的", font=font(66, True), fill=FG)

    y = 300
    items = [
        ("工具不消耗", "锤子／凿子／钳子／火钳和锅具用完原样留在手里，只吃材料和水。"),
        ("顺带修了刷物品 bug", "制盐原先只烧木炭、不消耗水，有木炭就能无限刷盐；这版补上 0.5 升水的消耗，并支持 6 种锅具。"),
        ("要 B42.21.0 以上", "低于这个版本会显示不可用；42.15 的 v1.0.4 已标 EOL，请用 42.19.0+。"),
        ("不用额外工具台", "配方就在「制作」菜单里，分类是金工／烹饪，按技能等级解锁。"),
    ]
    for title, body in items:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(32), W - 220):
            d.text((126, yy), line, font=font(32), fill=DIM)
            yy += 42
        y = yy + 30

    # 收尾：告诉人怎么找到它
    y += 8
    h = 214
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 28), "工坊搜索", font=font(30), fill=DIM)
    d.text((92, y + 70), "bin2's B42 mods", font=font(48, True), fill=FG)
    d.text((92, y + 142), "条目号 3628652563 · 2026-10-12 已更新到 v1.7.0",
           font=font(30), fill=GOOD)

    footer(d, "图标：游戏原生素材（UI2.pack / UI.pack 导出）")
    img.save(os.path.join(out, "4-说明.png"))


NOTE_TITLE = "僵毁 B42 里最缺的东西，终于能自己造了"

NOTE_BODY = """玩 Build 42 的时候有没有这种感觉：要做点东西，配方要求「螺母与螺栓」，但这玩意儿根本没地方造，只能拆家具、翻垃圾桶碰运气。

我把原版 969 条配方全扫了一遍，发现真不是错觉：
螺母与螺栓被 33 条配方要用，圆锯片 11 条，螺丝 10 条，胶水 9 条，手锯条 3 条——没有一条能用材料把它们做出来的配方。

（螺丝严格说有一条「开盒装螺丝 → 100 螺丝」，但那只是把搜刮到的盒子拆开，不是生产。）

bin2 扩展 v1.7.0 这次一次补齐了这 5 条：

· 制作螺母螺栓 → 1 木炭 + 1 铁料 + 锤子 + 钳子，200 秒出 6 个（金工 1 级）
· 制作螺丝 → 同上，200 秒出 6 个（金工 1 级）
· 制作圆锯片 → 2 木炭 + 1 金属板 + 锤子 + 凿子 + 钳子，300 秒出 1 个（金工 2 级）
· 制作手锯条 → 1 木炭 + 1 小金属板 + 锤子 + 凿子，200 秒出 2 个（金工 2 级）
· 熬制胶水 → 2 动物骨头 + 1 锅具 + 1 升水，240 秒出 2 个（烹饪 2 级）

几个细节：
· 工具和锅具用完原样留在手里，只消耗材料和水；锤子/钳子/凿子都收多个变体，不必凑特定那一把
· 铁料也不挑：铁块、钢块、铁废料、钢废料、铁片、钢片都收
· 顺带修了个刷物品 bug：制盐配方原先不消耗水，有木炭就能无限刷盐，这版补上了 0.5 升水的消耗，锅具也支持 6 种
· 需要 Build 42.21.0 以上；42.15 的 v1.0.4 已 EOL

模组：bin2 扩展（bin2_extension），工坊搜「bin2's B42 mods」，条目号 3628652563，2026-10-12 已更新到 v1.7.0。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "笔记素材")
    os.makedirs(out, exist_ok=True)

    missing = set()
    for r in RECIPES:
        for s, _c, _l in r["mats"] + [(r["prod"], 0, "")]:
            if icon(s) is None:
                missing.add(s)
    if missing:
        print("⚠️ 缺这些图标（会留空）：" + "、".join(sorted(missing)))
        sys.exit(1)

    # 自检：脚本引用的 sprite 必须真在素材里，且卡上写的容器名必须和 manifest 的中文名一致
    # （之前把 Item_Pot 写成「陶锅」、Item_CopperPot 写成「铜锅」，都是这一步抓出来的）
    manifest_path = os.path.join(ICON_DIR, "manifest.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
        problems = []
        for r in RECIPES:
            for sprite, _c, label in r["mats"]:
                if sprite not in manifest:
                    problems.append(f"素材里没有 {sprite}")
            if r["prod"] not in manifest:
                problems.append(f"素材里没有 {r['prod']}")
            for i, sprite in enumerate(r.get("vessels") or []):
                cn = [x["cn"] for x in manifest.get(sprite, {}).get("items", [])]
                want = (r.get("vessel_names") or [])[i] if i < len(r.get("vessel_names") or []) else None
                if want and not any(want in c or c in want for c in cn):
                    problems.append(f"{sprite} 卡上写「{want}」，manifest 是 {cn}")
        if problems:
            print("⚠️ 图标/名称对不上，先别发布：")
            for p in problems:
                print("   -", p)
            sys.exit(1)

    card1(out)
    # 卡片分工：4 条纯金属配方一张；熬胶要画「6 种锅具」那一排，单独给一张整图
    recipes_card(
        out, "2-配方-1.png", "bin2 扩展 v1.7.0 · 新增 5 条配方", "金属这四条",
        [RECIPES[0], RECIPES[1], RECIPES[3], RECIPES[2]], 220, 28,
        ["锤子/钳子/凿子都收多个变体，不必凑特定那一把",
         "工具用完原样留手里；铁料不挑，铁块/钢块/废料/铁片都收"],
        "图标：游戏原生素材 · 材料照抄模组脚本 bin2_Recipes.txt")
    recipes_card(
        out, "3-配方-2.png", "bin2 扩展 v1.7.0 · 新增 5 条配方 · 第 5 条", "熬制胶水",
        [RECIPES[4]], 470, 28,
        ["动物骨头到处都有，锅具用完原样留在手里",
         "水是流体、没有独立物品图标；那把带水的锅是原版贴图，示意用"],
        "配方分类：金工 / 烹饪 · 按技能等级解锁，无需额外工具台")
    card4(out)

    files = ["1-缺口.png", "2-配方-1.png", "3-配方-2.png", "4-说明.png"]
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（bin2 扩展 v1.7.0）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(files, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 事实来源\n\n")
        f.write("- 消耗条数 33/11/10/9/3：`python3 bin2_b42/tools/recipe_gap/scan_recipe_gaps.py` 现跑复现，"
                "详见 `docs/craft-recipe-study.md` 14.2（扫 969 条原版 craftRecipe / 5079 个物品）\n")
        f.write("- **螺丝的口径**：`Base.Screws` 在扫描结果里确实出现在 `produced` 里，唯一一条是 "
                "`OpenBox100`（`Base.ScrewsBox` → 100 螺丝，`category = Packing`，见 "
                "`media/scripts/generated/recipes/recipes_packing.txt`）。那是拆战利品、不是从材料生产，"
                "所以正文写成「没有一条能用材料把它们做出来的配方」并单独加括号说明，**不写「没有任何配方能造出它」**\n")
        f.write("- 铁料六个成员的中文名取自游戏自带 "
                "`media/lua/shared/Translate/CN/ItemName.json`：铁块/钢块/铁片/钢片/**铁废料/钢废料**"
                "（`IronScrap`=铁废料、`SteelScrap`=钢废料，不要写成「铁屑/钢屑」）\n")
        f.write("- 「新增 5 条」：git `aa9f32a` feat(bin2_extension): 补齐缺失配方 5 条,版本 1.7.0\n")
        f.write("- 材料/产出/耗时/技能/中文名：`bin2_b42/Contents/mods/bin2_extension/42.19.0/"
                "media/scripts/recipes/bin2_Recipes.txt` + `media/lua/shared/Translate/CN/Recipes.json`\n")
        f.write("- 已上线：`appworkshop_108600.acf` timeupdated=1791812609（2026-10-12 21:43:29），"
                "Steam 副本 mod.info 为 modversion=1.7.0\n")
        f.write("- 图标：`docs/xhs/游戏图标素材/`（pz_atlas 自 UI2.pack / UI.pack 导出，对应见 manifest.json）\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 发布时 `live_status` 是否真在播；不在播就不要在正文里邀请来直播间\n")

    print("已生成：", out)
    for n in sorted(os.listdir(out)):
        print("   ", n)


if __name__ == "__main__":
    main()
