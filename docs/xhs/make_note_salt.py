#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成小红书笔记素材（第二篇）：制盐 —— 4 张图文卡（用游戏原生图标）+ 文案。

来源是**开发日志**（`docs/rolling_log.md` 2026-10-12「制盐配方「支持其他锅具」：
顺手挖出无限刷盐 + 锅具翻倍 + 一个空操作 flag」那一条）+ `bin2_b42/Changelog.txt` 的 1.6.2 段。

和 `make_note.py`（第一篇，1.7.0 五条配方）共用同一套画卡工具与配色，所以直接 import 它，
不复制画卡代码；这一篇只写"这一篇的内容"。

每一条都可复核，来源写进 文案.md 的「事实来源」：
  · 原版做不出盐        -> 扫 media/scripts/generated/recipes/*.txt 的 outputs 块（969 条 craftRecipe，0 条命中）
  · 盐被 7 条配方消耗    -> 同上 inputs 块（烘焙 4 / 料理 2 / 装罐 1）
  · 世界来源、消耗条数    -> bin2_b42/tools/recipe_gap/scan_recipe_gaps.py 现跑
  · 配方本体（6 锅具 + 0.5 升水 + 木炭 → 盐） -> bin2_Recipes.txt 的 Bin2MakeSalt
  · 中文物品名          -> 游戏自带 media/lua/shared/Translate/CN/ItemName.json
  · 三条改动与 0.5 升的由来 -> Changelog.txt 1.6.2 段 + docs/rolling_log.md 2026-10-12 条
  · 已上线（不用等上传）  -> 工坊条目 3628652563 的 Steam 本地副本里就是改好的这份

用法：python3 make_note_salt.py [输出目录]    默认 docs/xhs/笔记素材-制盐

⚠️ 这篇已于 2026-10-13 07:29 发出（已过审公开），默认输出目录里放的就是**已发内容的证据**：
   别往那里重跑（会覆盖）。要复用这套卡，先改输出的目录名。
⚠️ 再跑之前先看 `笔记素材-制盐/文案.md` 末尾的「已发后的更正」：卡上「净水脏水都行」里的
   「脏水」按游戏内名称应写「污染的水」（`Fluid_Name_TaintedWater`）——这里保持原样，
   是为了让脚本还能**逐字复现已发出的那 4 张卡**。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402  复用同一套画卡工具（font/wrap/icon/卡片/页脚）
from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, icon, paste_icon, new_card, footer, draw_row, recipes_card,
)
from PIL import ImageDraw  # noqa: E402

OUT_DEFAULT = os.path.join(HERE, "笔记素材-制盐")

# 6 种锅具：sprite 名 -> 游戏内中文名（后者核对 ItemName.json 与 manifest.json 的 cn）
POTS = [
    ("Item_SaucepanEmpty", "平底煮锅"),
    ("Item_CopperPot", "铜平底煮锅"),
    ("Item_Pot", "蒸煮锅"),
    ("Item_Pot_Forged", "粗制蒸煮锅"),
    ("Item_Kettle", "水壶"),
    ("Item_CopperKettle", "铜制水壶"),
]

SALT_RECIPE = dict(
    name="制盐", lv="烹饪 1 级", time="不需要额外工作台", out_n=1,
    mats=[("Item_Charcoal", 1, "木炭"), ("Item_SaucepanEmpty", 1, "锅具")],
    prod="Item_Salt",
    water="0.5 升水（净水 / 脏水都行，取自身边的容器）",
    # 6 种锅具留给卡 3 单独讲，这张卡只放"一条配方"本身，免得两张卡说同一件事
    legend=["木炭也不挑：木炭 / 自制木炭 / 焦炭都能用",
            "锅具容量最小的是平底煮锅（0.6 升），所以水要 0.5 升",
            "锅具不再挑：6 种锅都能用（见下一张）"],
)

NOTE_TITLE = "僵毁 B42 盐造不出来？现在能自己煮了"

NOTE_BODY = """玩 Build 42 装罐头、腌菜、做烘焙，配方动不动就要「盐」。

我把原版 969 条 craftRecipe 全扫了一遍：没有一条能产出盐，也没有一条能产出调味盐。原版想拿盐只有两条路——搜刮，或者采集时从 JunkFood 表里翻出来。

可盐一直在被消耗：
· 烘焙 4 条：面包面团、馅饼面团、法棍面包团、软饼
· 料理 2 条：披萨、牛油果酱
· 装罐 1 条：罐装腌制食品（还得配醋）

bin2 扩展里这条「制盐」配方就是干这个的：

· 1 只锅具 + 0.5 升水 + 1 块木炭 → 1 盐（烹饪 1 级，不需要额外工作台）
· 水不挑：净水、脏水都行，取自身边的容器
· 木炭不挑：木炭 / 自制木炭 / 焦炭都收
· 锅具用完原样留在手里，锅里剩下的水也还在

v1.7.0 里它改了三处：

1. 以前只认「平底煮锅」，拿着蒸煮锅做不出盐；现在这 6 种锅都能用：平底煮锅 / 铜平底煮锅 / 蒸煮锅 / 粗制蒸煮锅 / 水壶 / 铜制水壶
2. 修掉一个我们自己的 bug：这条配方原先不消耗任何液体，只要木炭够就能无限刷盐；现在要蒸发 0.5 升水
3. 还修了一个：锅具本来是「保留」的，却又出现在产出里，等于做一次多一口锅

为什么是 0.5 升？因为容量最小的平底煮锅只有 0.6 升，水要得再多，就只有大锅能用了。

模组：bin2 扩展（bin2_extension），工坊搜「bin2's B42 mods」，条目号 3628652563，2026-10-12 已更新到 v1.7.0，需要 Build 42.21.0 以上。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""

FILES = ["1-缺口.png", "2-配方-1.png", "3-配方-2.png", "4-说明.png"]


# ── 卡 1：原版造不出盐 ────────────────────────────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 92), "僵毁 Build 42 · 盐", font=font(36), fill=ACCENT2)
    d.text((72, 152), "盐，原版造不出来", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 292), (W - 56, 552)], radius=22, fill=CARD)
    d.text((92, 330), "原版 craftRecipe", font=font(30), fill=DIM)
    d.text((92, 374), "969", font=font(104, True), fill=FG)
    d.text((92, 496), "条（Build 42.21）", font=font(28), fill=DIM)
    d.text((600, 330), "其中能产出「盐」的", font=font(30), fill=DIM)
    d.text((600, 374), "0", font=font(104, True), fill=ACCENT)
    d.text((600, 496), "条（调味盐同样是 0）", font=font(28), fill=DIM)

    d.text((72, 616), "但盐一直在被消耗：", font=font(42, True), fill=FG)

    y = 692
    rows = [
        ("烘焙 4 条", "面包面团 / 馅饼面团 / 法棍面包团 / 软饼"),
        ("料理 2 条", "披萨 / 牛油果酱"),
        ("装罐 1 条", "罐装腌制食品（还得配醋）"),
    ]
    for title, body in rows:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(36), fill=FG)
        yy = y + 52
        for line in wrap(d, body, font(32), W - 200):
            d.text((126, yy), line, font=font(32), fill=DIM)
            yy += 42
        y = yy + 22

    y += 10
    paste_icon(img, "Item_Salt", (92, y), 74)
    yy = y + 8
    for line in wrap(d, "原版拿盐只有两条路：搜刮，或者采集时从 JunkFood 表里翻出来。",
                     font(32), W - 260):
        d.text((192, yy), line, font=font(32), fill=(200, 206, 216))
        yy += 44

    d.text((72, 1198), "所以我们给 bin2 扩展加了一条「制盐」配方。",
           font=font(38, True), fill=ACCENT2)

    footer(d, "数据：扫原版 969 条 craftRecipe 的 outputs 块（tools/recipe_gap）")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：制盐配方本体 ────────────────────────────────────────────
def card2(out):
    recipes_card(
        out, FILES[1], "bin2 扩展 v1.7.0 · 制盐", "一口锅 + 半升水 + 木炭",
        [SALT_RECIPE], 470, 28,
        ["盐的用途：面包面团 / 馅饼面团 / 法棍面包团 / 软饼",
         "披萨 / 牛油果酱 / 罐装腌制食品（罐装还得配醋）",
         "水是流体、没有独立物品图标；那把带水的锅是原版贴图，示意用"],
        "配方本体：模组脚本 bin2_Recipes.txt 的 Bin2MakeSalt")


# ── 卡 3：6 种锅都能用 ───────────────────────────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 v1.7.0 · 锅具不再挑", font=font(36), fill=ACCENT2)
    d.text((72, 152), "6 种锅都能用", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 268), (W - 56, 606)], radius=22, fill=CARD)
    d.text((92, 300), "以前只认「平底煮锅」，拿着蒸煮锅做不出盐。", font=font(32), fill=DIM)
    d.text((92, 356), "现在这 6 种都行：", font=font(36), fill=FG)
    draw_row(img, d, 416, [(s, 0, n) for s, n in POTS], font(24), slot=158)
    d.text((92, 552), "锅具用完原样留在手里，锅里剩下的水还在。", font=font(30), fill=DIM)

    y = 672
    for line in ["水：0.5 升，净水脏水都行，取自身边的容器。",
                 "木炭：木炭 / 自制木炭 / 焦炭任选。",
                 "为什么是 0.5 升？容量最小的平底煮锅只有 0.6 升，",
                 "要得再多就只有大锅能用了。"]:
        d.text((72, y), line, font=font(34), fill=(206, 212, 222))
        y += 54

    # 收尾：一句话说清这条配方的全部要求（也是给不想看细节的人看的）
    y = 950
    d.rounded_rectangle([(56, y), (W - 56, y + 250)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 26), "一句话", font=font(30), fill=DIM)
    d.text((92, y + 68), "手里有什么锅，就用什么锅煮盐", font=font(44, True), fill=FG)
    paste_icon(img, "Item_Salt", (92, y + 150), 74)
    d.text((192, y + 168), "1 锅具 + 0.5 升水 + 1 木炭 → 1 盐",
           font=font(34), fill=ACCENT2)

    footer(d, "图标：游戏原生素材（UI2.pack / UI.pack 导出）")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：这版改了什么 + 怎么找到 ─────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 110), "bin2 扩展 v1.7.0", font=font(38), fill=ACCENT2)
    d.text((72, 178), "这版改了三处", font=font(66, True), fill=FG)

    y = 300
    items = [
        ("6 种锅具任选", "原来只认平底煮锅（Base.Saucepan）；现在平底煮锅 / 铜平底煮锅 / 蒸煮锅 / "
                         "粗制蒸煮锅 / 水壶 / 铜制水壶都能用。"),
        ("修掉「无限刷盐」", "这条配方原先不消耗任何液体，只要有木炭就能凭空出盐；现在要蒸发 0.5 升水。"),
        ("修掉「锅具翻倍」", "锅具本来是「保留」，却又出现在产出里 —— 做一次锅里外各一个；现在只产出盐。"),
        ("要 42.21.0 以上", "1.7.0 把 versionMin 抬到 Build 42.21.0，低于这个版本的客户端里本模组显示不可用。"),
    ]
    for title, body in items:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(31), W - 220):
            d.text((126, yy), line, font=font(31), fill=DIM)
            yy += 41
        y = yy + 26

    y += 6
    h = 214
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 28), "工坊搜索", font=font(30), fill=DIM)
    d.text((92, y + 70), "bin2's B42 mods", font=font(48, True), fill=FG)
    d.text((92, y + 142), "条目号 3628652563 · 2026-10-12 已更新到 v1.7.0",
           font=font(30), fill=GOOD)

    footer(d, "配方的语义只有引擎说了算：tools/recipe_probe 离线解析（不启动游戏）")
    img.save(os.path.join(out, FILES[3]))


def check_icons():
    """自检：脚本引用的 sprite 必须真在素材里，且卡上写的锅具名必须和 manifest 的中文名一致。"""
    manifest_path = os.path.join(mn.ICON_DIR, "manifest.json")
    if not os.path.exists(manifest_path):
        return []
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    problems = []
    used = [s for s, _ in POTS] + [s for s, _c, _l in SALT_RECIPE["mats"]] + [SALT_RECIPE["prod"]]
    for sprite in used:
        if sprite not in manifest:
            problems.append(f"素材里没有 {sprite}")
        elif icon(sprite) is None:
            problems.append(f"素材里没有 {sprite} 的图片文件")
    for sprite, want in POTS:
        cn = [x["cn"] for x in manifest.get(sprite, {}).get("items", [])]
        if cn and not any(want in c or c in want for c in cn):
            problems.append(f"{sprite} 卡上写「{want}」，manifest 是 {cn}")
    # 锅具的中文名还要对得上游戏自带的 ItemName.json（这次是照它改的）
    return problems


def write_copy(out):
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（bin2 扩展 · 制盐）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(FILES, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 事实来源\n\n")
        f.write("- **原版做不出盐**：扫游戏自带 `media/scripts/generated/recipes/*.txt` 的全部 "
                "`craftRecipe`（969 条）的 `outputs` 块，产出 `Base.Salt` / `Base.SeasoningSalt` "
                "的是 **0 条**（盐只作为 inputs 出现）\n")
        f.write("- **盐被 7 条配方消耗**（烘焙 4 / 料理 2 / 装罐 1）：`recipes_baking.txt` 的 "
                "`MakeBreadDough` `MakeBiscuits` `MakePieDough` `MakeBaguetteDough`、"
                "`recipes_cooking.txt` 的 `MakePizza` `MakeGuacamole`、`recipes_jarring.txt` 的 `MakeJar`。"
                "正文按类别写、不写总数，因为其中几条写的是 `[Base.Salt;Base.SeasoningSalt]`（有替代品），"
                "按「配方条数」还是「物品条数」数会得到不同的数\n")
        f.write("- **世界来源 / 消耗条数**：`bin2_b42/tools/recipe_gap/scan_recipe_gaps.py` 现跑，"
                "输出里 `Base.Salt` 那行是「消耗 6 · 世界来源: 采集(JunkFood.lua)」、"
                "`Base.SeasoningSalt` 是「消耗 5 · 同来源」⇒ 原版拿盐只有搜刮 / 采集两条路，"
                "只有引擎与这份扫描说了算，不是常识\n")
        f.write("- **配方本体**：`bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/"
                "bin2_Recipes.txt` 的 `Bin2MakeSalt`（6 个锅具 fullType + `-fluid 0.5 categories[Water]` "
                "+ 木炭三种 + `outputs` 只留 `Base.Salt`）；配方中文名「制盐」取自同模组的 "
                "`media/lua/shared/Translate/CN/Recipes.json`\n")
        f.write("- **物品中文名**：游戏自带 `media/lua/shared/Translate/CN/ItemName.json` —— "
                "`Saucepan`=平底煮锅、`SaucepanCopper`=铜平底煮锅、`Pot`=蒸煮锅、`PotForged`=粗制蒸煮锅、"
                "`Kettle`=水壶、`Kettle_Copper`=铜制水壶、`Salt`=盐、`SeasoningSalt`=调味盐、"
                "`Charcoal`=木炭、`CharcoalCrafted`=自制木炭、`Coke`=焦炭\n")
        f.write("- **盐的用途那串配方名**：同样取自游戏自带 `Recipes.json`（`MakeBiscuits`=制作软饼，"
                "**不是「饼干」**；`MakeJar`=制作罐装腌制食品），别按常识改写\n")
        f.write("- **三条改动与 0.5 升的由来**：`bin2_b42/Changelog.txt` 的 1.6.2 段 + "
                "`docs/rolling_log.md` 2026-10-12「制盐配方「支持其他锅具」…」那一条"
                "（用引擎源码取证：`flags[NotEmpty]` 对 FluidContainer 是空操作、`-fluid` 由上下文匹配、"
                "原配方既是「凭空出盐」又是「锅具翻倍」两把刷子）\n")
        f.write("- **已上线，不用等上传**：工坊条目 3628652563 的 Steam 本地副本 "
                "`steamapps/workshop/content/108600/3628652563/mods/bin2_extension/42.19.0/` 里，"
                "`bin2_Recipes.txt` 的 `Bin2MakeSalt` 已经是「6 锅具 + `-fluid 0.5` + 只产出盐」，"
                "且 `Changelog.txt` 里 1.6.2 段就在 —— 玩家手上那份就是改好的；"
                "acf 的 `timeupdated`=1791812609（2026-10-12 21:43:29）。"
                "（1.6.2 本身没单独上传过，改动是随 1.7.0 一起上去的）\n")
        f.write("- **图标**：`docs/xhs/游戏图标素材/`（pz_atlas 自 UI2.pack / UI.pack 导出，"
                "sprite → 物品见 manifest.json）\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 发布时 `live_status` 是否真在播；不在播就不要在正文里邀请来直播间\n")
        f.write("- [ ] 这一篇和上一篇（1.7.0 五条配方，2026-10-12 22:37 已发）主题不同、"
                "但同属 v1.7.0：**正文不要重复上一篇的「5 条配方」清单**\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT_DEFAULT
    os.makedirs(out, exist_ok=True)

    problems = check_icons()
    if problems:
        print("⚠️ 图标/名称对不上，先别发布：")
        for p in problems:
            print("   -", p)
        sys.exit(1)

    card1(out)
    card2(out)
    card3(out)
    card4(out)
    write_copy(out)

    print("已生成：", out)
    for n in FILES + ["文案.md"]:
        p = os.path.join(out, n)
        print("   %-14s %s" % (n, ("%d bytes" % os.path.getsize(p)) if os.path.exists(p) else "缺失"))


if __name__ == "__main__":
    main()
