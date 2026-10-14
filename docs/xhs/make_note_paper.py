#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成小红书笔记素材（第六篇知识贴）：造纸（bin2 扩展 1.7.2）—— 4 张图文卡 + 文案。

来源（全部自己核过，不是转述）：
  · 缺口那一侧 = 本机游戏安装树 `media/scripts` 全树 grep `SheetPaper2` 只命中 2 处：
    物品定义 `generated/items/literature.txt:1833` 与 `generated/recipes/recipes_traps.txt:411`
    （`craftRecipe MakeFirecracker` 的 inputs，九种纸任选一格）⇒ **产出它的配方 0 条**
    （这条 grep 覆盖全 scripts 树，`evolvedrecipe` 的 ResultItem / `itemMapper` 的键也在这棵树里，
    所以"第二条通路"是同一个证据，不是另找的）
  · 配方本体 = 模组脚本 `bin2_Recipes.txt` 的 `Bin2MakePaper`（commit f5a227a）
  · 中文名 = 游戏自带 `media/lua/shared/Translate/CN/{ItemName,Recipes}.json`
  · 木板来源 = 游戏自带 `generated/recipes/recipes_carpentry.txt` 的 `SawLogs`（中文名「锯原木」）
  · 燃料值 = 游戏自带 `media/lua/server/Camping/camping_fuel.lua`

和 make_note.py / make_note_salt.py / make_note_rake.py / make_note_weld.py 共用同一套画卡工具
（import make_note），这个文件只写"这一篇的内容"。图标：本篇新导了 `Item_Paper`（纸张）、
`Item_Plank`（木板）、`Item_Logs`（原木）、`Item_Firewood_Log`（木柴，备用）——为此给
`pz_pack_icons.py` 加了旧格式 pack 的解析（UI.pack 没有 PZPK magic、页尾带 0xDEADBEEF）。

★ 红线：这篇只能**在 1.7.2 真的上线之后**发（发布前现读 `GetPublishedFileDetails` 核
  `time_updated` / 本机 Steam 副本 `modversion=1.7.2`）；技术侧只跑过游戏自带的离线解析器，
  **没在游戏里点过这条配方** ⇒ 正文只写配方本身，不写手感/效果。

★ **已发布：2026-10-14 19:58 提交、20:0x 过审公开（noteId `6acf6e580000000018028a8a`）。**
  ⚠ 按下「发布」后页面立刻跳到的 `/explore/6acda527000000001802d14c` **不是这篇的 noteId**（公开侧搜不到）——
  **noteId 以后台「笔记管理」+ 公开侧作者页为准**，别拿"按后那一瞬的 URL"当依据。
  线上版本依据是 **@bin2_extension_mod_dev 19:54 的远端读数**（`time_updated=1791978762` = 19:52:42、
  `file_size` 194997→198614）＋ @human 19:53「已上传」——**本机 Steam 副本当时还是 1.7.1**（Steam 没拉更新），
  所以"本机副本＝线上副本"这条老路这次**没走通也不要拿来当判据**（见 `docs/社区建议/README.md` 的口径）。
  已发布的那份正文/配图是原样，不要再改；再跑一次这个生成器得到的是同一份（含这行说明）。


用法：python3 make_note_paper.py [输出目录]    默认 docs/xhs/笔记素材-造纸
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402
from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, icon, paste_icon, new_card, footer, draw_row,
)

OUT_DEFAULT = os.path.join(HERE, "笔记素材-造纸")
MOD_INFO = os.path.join(HERE, "..", "..", "bin2_b42", "Contents", "mods",
                        "bin2_extension", "42.19.0", "mod.info")


def mod_version():
    """卡片上的版本号从模组 mod.info 现读，别手写（手写迟早和仓库对不上）。"""
    try:
        with open(MOD_INFO, encoding="utf-8") as f:
            m = re.search(r"^modversion=(.+)$", f.read(), re.M)
        return m.group(1).strip() if m else "?"
    except OSError:
        return "?"


VERSION = mod_version()

# 配方本体：照抄 bin2_Recipes.txt 的 Bin2MakePaper（卡片上的名字必须和脚本对得上）
PAPER_RECIPE = dict(
    name="造纸", lv="烹饪 1 级", time="120 秒", out_n=12,
    mats=[("Item_Plank", 1, "木板"),
          ("Item_Pot", 1, "锅具"),
          ("Item_WaterDrop", 1, "1 升水")],
    prod="Item_Paper",
    legend=["任意平面就能做，不用工作台",
            "锅具收 6 种、用完原样留手里（这里画的是蒸煮锅）"],
)

NOTE_TITLE = "僵毁 B42 纸张只能搜刮？现在能造了"  # 平台标题上限 20 字（不含空格）——数一遍再改

NOTE_BODY = """给队友留张字条、给据点做个标记，或者在做那个实验室模组的人，大概都撞过同一件事：纸（游戏里的「纸张」）只能搜刮 —— 书架上、办公桌里、文件柜里，翻到几张算几张。

我扫了一遍游戏自带的脚本：整个 media/scripts 里「纸张」（Base.SheetPaper2）一共只出现两处 —— 一条物品定义，和一条配方的材料格。能产出它的配方：0 条。

bin2 扩展 1.7.2 里加了一条「造纸」：

· 造纸 → 1 木板 + 1 锅具（做完保留）+ 1 升水 → 12 纸张（烹饪 1 级，120 秒）
· 任意平面就能做，不用工作台；锅具收 6 种：平底煮锅 / 铜平底煮锅 / 蒸煮锅 / 粗制蒸煮锅 / 水壶 / 铜制水壶
· 木板来自原版的「锯原木」：1 原木 + 1 手锯（保留，会磨损）→ 3 木板，木工 5 经验

为什么一次给 12 张：纸的消耗面里最大的一口是那个实验室模组（Zombie Virus Vaccine）——它的画架有 5 条配方，一条要 12 张、四条各要 6 张，化学反应台要 1 张。原版里吃纸的地方只有一条「制作爆竹」，而且那格是九种纸任选其一。所以一次 12 张，正好够最大的一条，不用为一张画架重复 12 遍动作。

顺带说一句：这不是刷燃料的路子 —— 1 块木板在营火里是 2 小时燃料，它换来的 12 张纸加起来烧不到这个数。

同一个版本里还顺手订正了几处名称（本模组原先把蒸煮锅显示成「陶锅」、夹钳显示成「简易木钳」）——现在物品名一律跟游戏自带译名一致，工坊描述里那条工具名也订正了。

模组：bin2 扩展（bin2_extension），工坊搜「bin2's B42 mods」，条目号 3628652563，需要 Build 42.21.0 以上。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""

FILES = ["1-缺口.png", "2-配方.png", "3-材料.png", "4-说明.png"]


# ── 卡 1：纸张只有搜刮一条来源，产出它的配方 0 条 ─────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 92), "僵毁 Build 42 · 纸张", font=font(36), fill=ACCENT2)
    d.text((72, 152), "只能搜刮，做不出来", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 276), (W - 56, 668)], radius=22, fill=CARD)
    d.text((92, 308), "游戏自带脚本（media/scripts 全树）里，纸张出现", font=font(28), fill=DIM)
    rows = [
        ("2", "处 —— 一条物品定义 + 一条配方的材料格", FG),
        ("0", "条配方能产出它 —— 产出一栏是空的", ACCENT),
        ("1", "条原版配方吃纸：制作爆竹（九种纸任选一格）", FG),
    ]
    y = 372
    for num, label, color in rows:
        d.text((92, y), num, font=font(72, True), fill=color)
        d.text((238, y + 22), label, font=font(30), fill=(214, 219, 228))
        y += 92

    d.text((72, 700), "想要纸只有一条路：搜刮书架、办公桌、文件柜、垃圾堆。", font=font(29), fill=DIM)
    d.text((72, 740), "想手写一张字条，也得先翻到一张纸。", font=font(29), fill=DIM)

    y = 818
    paste_icon(img, "Item_Paper", (92, y), 74)
    for line in wrap(d, "还有一口大消耗在第三方模组那边：实验室模组（Zombie Virus Vaccine）"
                        "的画架，一条配方要 12 张纸。", font(31), W - 260):
        d.text((192, y + 8), line, font=font(31), fill=(200, 206, 216))
        y += 44

    d.text((72, 1180), "bin2 扩展 1.7.2 里加了一条「造纸」。", font=font(38, True), fill=ACCENT2)
    footer(d, "数据：本机游戏安装树 media/scripts 全树扫描（只读）")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：配方本体 ───────────────────────────────────────────────
def card2(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 造纸", font=font(36), fill=ACCENT2)
    d.text((72, 152), "1 木板 + 1 升水 → 12 纸张", font=font(62, True), fill=FG)

    d.rounded_rectangle([(56, 272), (W - 56, 660)], radius=22, fill=CARD)
    d.text((88, 302), "造纸", font=font(48, True), fill=FG)
    meta = "烹饪 1 级 · 120 秒"
    d.text((W - 88 - d.textlength(meta, font=font(30)), 318), meta, font=font(30), fill=DIM)

    draw_row(img, d, 392, [(s, c, l) for s, c, l in PAPER_RECIPE["mats"]], font(25), slot=160)
    d.text((676, 408), "→", font=font(46), fill=DIM)
    paste_icon(img, "Item_Paper", (748, 392), 62)
    d.text((792, 380), "×12", font=font(36, True), fill=GOOD)

    yy = 546
    for line in PAPER_RECIPE["legend"]:
        d.text((92, yy), line, font=font(28), fill=(170, 178, 190))
        yy += 42

    d.rounded_rectangle([(56, 700), (W - 56, 1150)], radius=22, fill=CARD)
    d.text((92, 728), "这条配方为什么值得做", font=font(34, True), fill=ACCENT2)
    yy = 796
    for title, body in [
        ("缺口在它这一侧", "全 scripts 树里，能产出纸张的配方是 0 条，只有搜刮一条路。"),
        ("门槛很低", "烹饪 1 级就能做，120 秒一条，产出 12 张。"),
        ("不用工作台", "配方带 AnySurfaceCraft，任意平面就能开工。"),
        ("锅具不是耗材", "6 种锅具任选一种，做完原样留手里（mode:keep）。"),
        ("一次够最大的一条", "实验室画架最大的那条要 12 张，一次正好够。"),
    ]:
        d.ellipse([(94, yy + 12), (112, yy + 30)], fill=ACCENT2)
        d.text((136, yy), title, font=font(34), fill=FG)
        d.text((136, yy + 46), body, font=font(29), fill=DIM)
        yy += 46 + 40

    footer(d, "配方本体：模组脚本 bin2_Recipes.txt 的 Bin2MakePaper")
    img.save(os.path.join(out, FILES[1]))


# ── 卡 3：材料都有来源（闭环）────────────────────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 造纸", font=font(36), fill=ACCENT2)
    d.text((72, 152), "这几样东西都有来源", font=font(64, True), fill=FG)

    y = 288
    blocks = [
        ("Item_Plank", "木板 · 原版「锯原木」",
         "1 原木 + 1 手锯（保留，可能磨损）→ 3 木板，木工 5 经验、230 秒。"),
        ("Item_Logs", "原木 · 原版就有",
         "砍树就有，也能在仓库、伐木场一类地方搜到。"),
        ("Item_Pot", "锅具 · 原版就有",
         "平底煮锅 / 铜平底煮锅 / 蒸煮锅 / 粗制蒸煮锅 / 水壶 / 铜制水壶，"
         "6 种任选，用完原样留着。"),
        ("Item_WaterDrop", "水 · 1 升",
         "带水的容器里舀 1 升（配方收 Water 类液体，锅里有水也算）。"),
    ]
    for sprite, title, body in blocks:
        d.rounded_rectangle([(56, y), (W - 56, y + 196)], radius=20, fill=CARD)
        paste_icon(img, sprite, (92, y + 30), 62)
        d.text((180, y + 26), title, font=font(38, True), fill=FG)
        yy = y + 84
        for line in wrap(d, body, font(30), W - 300):
            d.text((180, yy), line, font=font(30), fill=(186, 193, 204))
            yy += 40
        y += 212

    d.text((72, y + 4), "整条线是闭环的：原版锯木头 + 本模组造纸，纸不用再靠运气。",
           font=font(32, True), fill=GOOD)
    footer(d, "来源：recipes_carpentry.txt 的 SawLogs / bin2_Recipes.txt + 游戏自带中文译名表")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：几点要知道的 + 怎么找到 ────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 110), "bin2 扩展", font=font(38), fill=ACCENT2)
    d.text((72, 178), "几点要知道的", font=font(66, True), fill=FG)

    y = 288
    items = [
        ("12 张是照消耗量定的", "实验室画架 5 条配方里，1 条要 12 张、4 条各要 6 张，化学台 1 张 —— "
                               "一次 12 张正好够最大的一条。"),
        ("不会变成刷燃料", "1 块木板是 2 小时营火燃料；它换来的 12 张纸加起来烧不到 2 小时。"),
        ("纸也能写字", "纸张在游戏里可以书写（一页），做标记、留字条都用得上。"),
        ("同一版订正了名称", "物品名一律跟游戏自带译名一致（原先显示成「陶锅」「简易木钳」的两条已订正），"
                           "工坊描述里的工具名也改了。"),
        ("要 Build 42.21.0 以上", "低于这个版本客户端里本模组显示不可用。"),
    ]
    for title, body in items:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(30), W - 220):
            d.text((126, yy), line, font=font(30), fill=DIM)
            yy += 40
        y = yy + 8

    y += 6
    h = 200
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 26), "工坊搜索", font=font(30), fill=DIM)
    d.text((92, y + 66), "bin2's B42 mods", font=font(48, True), fill=FG)
    d.text((92, y + 134), "条目号 3628652563 · v%s" % VERSION, font=font(30), fill=GOOD)

    footer(d, "图标：游戏原生素材（texturepacks 导出，见 pz_pack_icons.py）")
    img.save(os.path.join(out, FILES[3]))


def check_icons():
    """自检：脚本引用的 sprite 必须真在素材里，且卡上写的物品名必须和 manifest 的中文名一致。"""
    manifest_path = os.path.join(mn.ICON_DIR, "manifest.json")
    if not os.path.exists(manifest_path):
        return ["没有 manifest.json，没法核对物品名"]
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    problems = []
    want = [(s, l) for s, _c, l in PAPER_RECIPE["mats"]] + [(PAPER_RECIPE["prod"], "纸张")]
    for sprite, w in want + [("Item_Logs", "原木"), ("Item_Pot", "蒸煮锅"),
                             ("Item_SaucepanEmpty", "平底煮锅"), ("Item_WaterDrop", "")]:
        if sprite not in manifest:
            problems.append(f"素材里没有 {sprite}")
        elif icon(sprite) is None:
            problems.append(f"素材里没有 {sprite} 的图片文件")
        else:
            cn = [x["cn"] for x in manifest[sprite].get("items", [])]
            if w == "锅具" or w == "1 升水":
                continue          # 卡上是"锅具/水"的统称，不对具体物品名
            if cn and w and not any(w in c or c in w for c in cn):
                problems.append(f"{sprite} 卡上写「{w}」，manifest 是 {cn}")
    return problems


def write_copy(out):
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（bin2 扩展 · 造纸）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE.replace(" ", "")), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(FILES, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 事实来源\n\n")
        f.write("- **纸张只有两处、产出 0 条**（2026-10-14 我自己在本机游戏安装树跑 "
                "`grep -rn SheetPaper2 <游戏>/media/scripts`）：命中恰好 2 行 —— "
                "`generated/items/literature.txt:1833`（`item SheetPaper2` 定义：`Icon = Paper`、"
                "`Weight = 0.1`、`ItemType = base:literature`、`CanBeWrite = true`、`PageToWrite = 1`）与 "
                "`generated/recipes/recipes_traps.txt:411`（**`craftRecipe MakeFirecracker` 的 inputs** 里的"
                "一格 OR 列表：`SheetPaper2;GraphPaper;Brochure;Flier;Paperwork;LetterHandwritten;Doodle;"
                "DoodleKids;GenericMail`）。因为这条 grep 覆盖整棵 scripts 树，`evolvedrecipe` 的 "
                "`ResultItem` / `itemMapper` 的键若引用它也会被命中 ⇒ **没有任何配方产出纸张**。"
                "该配方 outputs 是 `item 1 Base.Firecracker_Crafted`，中文名「制作爆竹」"
                "（`Recipes.json` 的 `MakeFirecracker`）\n")
        f.write("- **配方本体**：`bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/"
                "bin2_Recipes.txt` 的 `Bin2MakePaper`（commit `f5a227a`）—— `time = 120`、"
                "`timedAction = Making`、`Tags = AnySurfaceCraft;Cooking`、`category = Cooking`、"
                "`SkillRequired = Cooking:1`、`xpAward = Cooking:5`；`inputs`: `item 1 [Base.Plank]` + "
                "`item 1 [Base.Saucepan;Base.SaucepanCopper;Base.Pot;Base.PotForged;Base.Kettle;"
                "Base.Kettle_Copper] mode:keep flags[ItemCount]` + `-fluid 1.0 categories[Water] "
                "mode:mixture`；`outputs`: `item 12 Base.SheetPaper2`\n")
        f.write("- **`time` 是秒**：同文件 `Bin2MakeGlue = 240`、`Bin2MakeNutsBolts = 200`，"
                "已发布的第一篇文案写的就是「240 秒」「200 秒」⇒ 本篇的 `120` 写「120 秒」\n")
        f.write("- **物品中文名**（游戏自带 `media/lua/shared/Translate/CN/ItemName.json`）："
                "`SheetPaper2`=纸张、`Plank`=木板、`Log`=原木、`Pot`=蒸煮锅、`Saucepan`=平底煮锅、"
                "`SaucepanCopper`=铜平底煮锅、`PotForged`=粗制蒸煮锅、`Kettle`=水壶、"
                "`Kettle_Copper`=铜制水壶、`Saw`=手锯；技能 `IGUI_perks_Cooking` = **烹饪**（`IG_UI.json`）\n")
        f.write("- **配方中文名「造纸」**：模组自带 `media/lua/shared/Translate/CN/Recipes.json` 的 "
                "`Bin2MakePaper`\n")
        f.write("- **木板来源**：游戏自带 `generated/recipes/recipes_carpentry.txt:3` 的 `SawLogs`"
                "（中文名「锯原木」）—— `time = 230`、`category = Carpentry`、`xpAward = Woodwork:5`、"
                "`inputs`: `item 1 [Base.Log] flags[Prop2]` + `item 1 tags[base:saw] mode:keep "
                "flags[MayDegradeLight;Prop1]`；`outputs`: `item 3 Base.Plank`\n")
        f.write("- **不是刷燃料**（游戏自带 `media/lua/server/Camping/camping_fuel.lua`）："
                "`Plank = 2.0`（小时）、`SheetPaper2 = 5/60.0`（= 5 分钟）；同文件注释写明"
                "「程序化算出的值更小时会采用更小的那个」，而 literature 类按 `重量 × 1/4` 算"
                "（纸张 0.1kg ⇒ 0.025 小时 = 1.5 分钟）⇒ **两种读法下 12 张纸（≤1 小时）都烧不到"
                "1 块木板的 2 小时**。正文因此只说「烧不到这个数」，不写死分钟数\n")
        f.write("- **实验室那条消耗**（第三方，服务器模组包里就有）：工坊条目 `3615135168` 的 "
                "`ZVirusVaccine42BETA` —— `.../generated/entities/lab/craftRecipes/recipes_LabEasel.txt` "
                "5 条 `craftRecipe`（1×12 + 4×6）、`recipes_LabChemistrySet.txt` 1×1，42.14 与 42.20 "
                "两份同数，且都写在 `module Base` 里 ⇒ 吃的就是 `Base.SheetPaper2`。"
                "**这组数我自己核过、@过程改进组长 也独立复核过**（不是转述）\n")
        f.write("- **线上版本**：`mod.info` 是 `modversion=%s`、`versionMin=42.21.0`；发布前**必须现读**"
                "`GetPublishedFileDetails(3628652563)` + 本机 Steam 副本，确认线上就是这一版"
                "（技术侧 19:4x 现读 `time_updated=1791884966` = 2026-10-13 17:49:26，"
                "也就是 1.7.2 还没上传）\n" % VERSION)
        f.write("- **图标**：`Item_Paper`（纸张）、`Item_Plank`（木板）、`Item_Logs`（原木）、"
                "`Item_Firewood_Log`（木柴，备用）是 2026-10-14 用 `pz_pack_icons.py --emit` 现导的 —— "
                "为此给那个脚本加了**旧格式 pack** 的解析（`UI.pack` 没有 `PZPK` magic、头 4 字节是版本号 8、"
                "页尾分隔符 `0xDEADBEEF`）；导出的 `Item_Pot` rect=(159,248,29,30) 与 dev 早先工具"
                "记在 manifest 里的 rect 逐字相同，可作交叉校验\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 标题去空格 %d 字 ≤ 20；发布前跑 `node 发布笔记.js --title-check --docs <本目录>`\n"
                % len(NOTE_TITLE.replace(" ", "")))
        f.write("- [ ] **必须先核线上 1.7.2**：现读 `GetPublishedFileDetails(3628652563)` 的 "
                "`time_updated`/`file_size` 与本机 Steam 副本一致，且副本 `mod.info` 是 "
                "`modversion=1.7.2`、`bin2_Recipes.txt` 里有 `Bin2MakePaper`。**没上线不发**（红线）\n")
        f.write("- [ ] 正文/卡片**不写**「实测过」「手感」这类话：技术侧只跑过游戏自带的离线解析器，"
                "这条配方**没在游戏里点过**（合成界面可见性、timedAction 都没人看过）\n")
        f.write("- [ ] 卡片上的版本号是现读模组 `mod.info` 得来的；若发布时线上不是这一版，先查清再发\n")
        f.write("- [ ] 话题 8 个与前几篇同一组，发布前 `--dry` 查存在性\n")
        f.write("- [ ] 招人帖（`笔记素材-招人`）仍在等图 2/3，**别在同一天连发两条以上**\n")


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

    print("已生成：", out, "（模组版本 %s）" % VERSION)
    for n in FILES + ["文案.md"]:
        p = os.path.join(out, n)
        print("   %-12s %s" % (n, ("%d bytes" % os.path.getsize(p)) if os.path.exists(p) else "缺失"))


if __name__ == "__main__":
    main()
