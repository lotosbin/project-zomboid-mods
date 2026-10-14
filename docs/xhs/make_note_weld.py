#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成小红书笔记素材（第五篇知识贴）：制作焊条（bin2 扩展）—— 4 张图文卡 + 文案。

来源（全部自己核过，不是转述）：
  · 缺口那一侧 = 游戏自带 `media/scripts/generated/entities/**` 的 `component CraftRecipe`
    （inputs 吃 `Base.WeldingRods` 的共 **37** 条）+ 全目录 `craftRecipe`/`itemMapper` 的 outputs
    + `media/lua/**` 的战利品表（**产出一栏是 0 条**）
  · 配方本体 = 模组脚本 `bin2_Recipes.txt` 的 `Bin2MakeWeldingRods`
  · 中文名 = 游戏自带 `media/lua/shared/Translate/CN/{ItemName,Recipes}.json`

和 make_note.py / make_note_salt.py / make_note_rake.py 共用同一套画卡工具（import make_note），
这个文件只写"这一篇的内容"。图标：本篇新导了 `Item_BlowTorch`（`pz_pack_icons.py --emit`），
其余复用已有素材。

用法：python3 make_note_weld.py [输出目录]    默认 docs/xhs/笔记素材-焊条
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402
from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, icon, paste_icon, new_card, footer, draw_row,
)

OUT_DEFAULT = os.path.join(HERE, "笔记素材-焊条")

# 配方本体：照抄 bin2_Recipes.txt 的 Bin2MakeWeldingRods（卡片上的名字必须和脚本对得上）
WELD_RECIPE = dict(
    name="制作焊条", lv="金工 1 级", time="50 秒", out_n=2,
    mats=[("Item_SteelBar_Whole", 1, "钢条"),
          ("Item_Charcoal", 4, "木炭"),
          ("Item_Glue", 1, "胶水"),
          ("Item_Salt", 1, "盐")],
    prod="Item_WeldingRods",
    legend=["配方里没有工具位：材料放在台面上就能做",
            "木炭那格收 木炭 / 自制木炭 / 焦炭，任选一种"],
)

NOTE_TITLE = "僵毁 B42 焊条只能搜刮？现在能造了"  # 平台标题上限 20 字（不含空格）——数一遍再改

NOTE_BODY = """玩 Build 42 想建金属据点的人大概都撞过这堵墙：金属墙、铁门、铁栅栏、金属家具，配方上全都要「焊条」，一次吃 1 到 10 根，最常见的是 4 根。可我扫了一遍游戏自带的脚本：原版 37 条把焊条当材料的建造条目里，没有任何一条能造出焊条 —— 它只有搜刮这一条来源（五金店、工具箱、车里、翻垃圾）。

bin2 扩展里有一条「制作焊条」：

· 制作焊条 → 1 钢条 + 4 木炭 + 1 胶水 + 1 盐 → 2 焊条（金工 1 级，50 秒）
· 不要工具，材料放在台面上就能做；木炭不挑：木炭 / 自制木炭 / 焦炭都收
· 四种材料都有来源：钢条原版锻造栏就能打（4 钢块 + 4 木炭 + 锤子 + 夹钳，最基础那档锻造炉就行）；胶水和盐这个模组自己也能做

数字是怎么来的：扫游戏自带的 media/scripts，材料里吃掉焊条的建造条目共 37 条（金属墙 20 条、金属家具 13 条、铁栏路障 2 条、楼梯 1 条、动物围栏 1 条）；用量里 4 根最常见（22 条），最多的一条要 10 根。再把全目录的产物栏和战利品表翻一遍：能造出焊条的地方，0 条。

举个例子：原版最基础的「金属墙 (基础)」，材料一栏写着 4 个焊条 + 4 个丙烷喷灯 + 3 块小金属板，要金工 3 级 —— 想围个金属院子，焊条就是硬通货。

一点要说清楚的：这条配方不是这次新版加的，模组里一直就有（工坊更新说明里也列着 Bin2MakeWeldingRods 制作焊条）。我这次只是把原版那一侧的缺口数清楚了，顺手写成一篇。

模组：bin2 扩展（bin2_extension），工坊搜「bin2's B42 mods」，条目号 3628652563，需要 Build 42.21.0 以上。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""

FILES = ["1-缺口.png", "2-配方.png", "3-材料.png", "4-说明.png"]


# ── 卡 1：原版 37 条建造都要焊条，产出一栏是 0 ─────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 92), "僵毁 Build 42 · 焊条", font=font(36), fill=ACCENT2)
    d.text((72, 152), "只能搜刮，做不出来", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 276), (W - 56, 668)], radius=22, fill=CARD)
    d.text((92, 308), "游戏自带脚本里，把焊条当材料的建造条目", font=font(28), fill=DIM)
    rows = [
        ("37", "条建造条目要焊条（金属墙 / 铁门 / 栅栏 / 金属家具…）", FG),
        ("4", "根是最常见的用量（22 条要 4 根，最多的一条要 10 根）", FG),
        ("0", "条能造出焊条的配方 —— 产出一栏是空的", ACCENT),
    ]
    y = 372
    for num, label, color in rows:
        d.text((92, y), num, font=font(72, True), fill=color)
        d.text((238, y + 22), label, font=font(32), fill=(214, 219, 228))
        y += 92

    d.text((72, 700), "37 条分布在：金属墙 20 · 金属家具 13 · 铁栏路障 2", font=font(29), fill=DIM)
    d.text((72, 738), "楼梯 1 · 动物围栏 1", font=font(29), fill=DIM)

    y = 812
    paste_icon(img, "Item_WeldingRods", (92, y), 74)
    for line in wrap(d, "原版拿焊条只有一条路：搜刮。五金店、工具箱、车里、翻垃圾 —— "
                        "想要多少全看运气。", font(32), W - 260):
        d.text((192, y + 8), line, font=font(32), fill=(200, 206, 216))
        y += 44

    y += 56
    ix = 92
    for sp in ("Item_BlowTorch", "Item_MetalSheetSmall", "Item_WeldingRods"):
        paste_icon(img, sp, (ix, y), 58)
        ix += 74
    yy = y + 76
    for line in wrap(d, "例：原版最基础的「金属墙 (基础)」—— 4 个焊条 + 4 个丙烷喷灯 + "
                        "3 块小金属板，金工 3 级。", font(32), W - 184):
        d.text((92, yy), line, font=font(32), fill=(200, 206, 216))
        yy += 44

    d.text((72, 1210), "bin2 扩展里有一条「制作焊条」。", font=font(38, True), fill=ACCENT2)
    footer(d, "数据：游戏自带脚本 media/scripts 全量扫描（只读）")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：配方本体 ───────────────────────────────────────────────
def card2(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 制作焊条", font=font(36), fill=ACCENT2)
    d.text((72, 152), "1 钢条 + 4 木炭 → 2 焊条", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 272), (W - 56, 660)], radius=22, fill=CARD)
    d.text((88, 302), "制作焊条", font=font(48, True), fill=FG)
    meta = "金工 1 级 · 50 秒"
    d.text((W - 88 - d.textlength(meta, font=font(30)), 318), meta, font=font(30), fill=DIM)

    draw_row(img, d, 392, [(s, c, l) for s, c, l in WELD_RECIPE["mats"]], font(25), slot=150)
    d.text((700, 408), "→", font=font(46), fill=DIM)
    paste_icon(img, "Item_WeldingRods", (772, 392), 62)
    d.text((816, 380), "×2", font=font(36, True), fill=GOOD)

    yy = 546
    for line in WELD_RECIPE["legend"]:
        d.text((92, yy), line, font=font(28), fill=(170, 178, 190))
        yy += 42

    d.rounded_rectangle([(56, 700), (W - 56, 1140)], radius=22, fill=CARD)
    d.text((92, 728), "这条配方为什么值得做", font=font(34, True), fill=ACCENT2)
    yy = 796
    for title, body in [
        ("缺口在它这一侧", "原版 37 条建造条目都在吃焊条，能造出焊条的是 0 条。"),
        ("门槛比目标还低", "金工 1 级就能做，最基础的金属墙反倒要金工 3 级。"),
        ("不要工具", "四个格子全是材料，放在台面上就能开工。"),
        ("木炭不挑", "木炭 / 自制木炭 / 焦炭，任选一种都行。"),
    ]:
        d.ellipse([(94, yy + 12), (112, yy + 30)], fill=ACCENT2)
        d.text((136, yy), title, font=font(34), fill=FG)
        d.text((136, yy + 46), body, font=font(29), fill=DIM)
        yy += 46 + 42

    footer(d, "配方本体：模组脚本 bin2_Recipes.txt 的 Bin2MakeWeldingRods")
    img.save(os.path.join(out, FILES[1]))


# ── 卡 3：四种材料都有来源（闭环）─────────────────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 制作焊条", font=font(36), fill=ACCENT2)
    d.text((72, 152), "这四样东西都有来源", font=font(64, True), fill=FG)

    y = 288
    blocks = [
        ("Item_SteelBar_Whole", "钢条 · 原版就有",
         "锻造栏「用铁/钢块锻造铁/钢条」：4 钢块 + 4 木炭 + 锤子 + 夹钳，"
         "最基础那档锻造炉就能打；也有「铸造钢条」（高级炉 + 4 个钢坩埚 + 4 木炭 + 钢条模具）。"),
        ("Item_Charcoal", "木炭 · 原版就有",
         "烧木头就有。配方里木炭 / 自制木炭 / 焦炭任选一种，不挑。"),
        ("Item_Glue", "胶水 · 本模组",
         "熬制胶水：2 个动物骨头 + 1 个锅具 + 1 升水 → 2 胶水（烹饪 2 级）。"),
        ("Item_Salt", "盐 · 本模组",
         "制盐：1 个锅具 + 0.5 升水 + 1 个木炭 → 1 盐（烹饪 1 级，锅具做完原样留着）。"),
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

    d.text((72, y + 4), "整条线是闭环的：原版 + 本模组，四样材料都做得出。",
           font=font(34, True), fill=GOOD)
    footer(d, "来源：recipes_blacksmith_bar.txt / bin2_Recipes.txt + 游戏自带中文译名表")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：几点要知道的 + 怎么找到 ────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 110), "bin2 扩展", font=font(38), fill=ACCENT2)
    d.text((72, 178), "几点要知道的", font=font(66, True), fill=FG)

    y = 288
    items = [
        ("不是这次新版加的", "模组里一直就有这条配方；工坊条目的更新说明里也列着 Bin2MakeWeldingRods「制作焊条」。"
                             "这篇只是把原版那一侧的缺口数清楚了。"),
        ("不会变成刷材料", "焊条不能回炉（物品属性里没有可熔炼标签），1 钢条换 2 焊条是净消耗，不闭环。"),
        ("门槛比目标还低", "金工 1 级就能做，而最基础的金属墙要金工 3 级 —— 先能造焊条，才谈得上建金属据点。"),
        ("喷灯是工具", "丙烷喷灯烧完不会消失（KeepOnDeplete），真正被吃掉的耗材是焊条。"),
        ("要 Build 42.21.0 以上", "低于这个版本客户端里本模组显示不可用；42.15.0 版 v1.0.4 已 EOL。"),
    ]
    for title, body in items:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(30), W - 220):
            d.text((126, yy), line, font=font(30), fill=DIM)
            yy += 40
        y = yy + 8

    y += 4
    h = 200
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 26), "工坊搜索", font=font(30), fill=DIM)
    d.text((92, y + 66), "bin2's B42 mods", font=font(48, True), fill=FG)
    d.text((92, y + 134), "条目号 3628652563 · 线上 v1.7.1", font=font(30), fill=GOOD)

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
    want = [(s, l) for s, _c, l in WELD_RECIPE["mats"]] + [(WELD_RECIPE["prod"], "焊条")]
    for sprite, w in want + [("Item_BlowTorch", "丙烷喷灯"),
                             ("Item_MetalSheetSmall", "小金属板"),
                             ("Item_CokeCoal", "焦炭"),
                             ("Item_WoodCharcoal", "自制木炭")]:
        if sprite not in manifest:
            problems.append(f"素材里没有 {sprite}")
        elif icon(sprite) is None:
            problems.append(f"素材里没有 {sprite} 的图片文件")
        else:
            cn = [x["cn"] for x in manifest[sprite].get("items", [])]
            if cn and w and not any(w in c or c in w for c in cn):
                problems.append(f"{sprite} 卡上写「{w}」，manifest 是 {cn}")
    return problems


def write_copy(out):
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（bin2 扩展 · 制作焊条）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE.replace(" ", "")), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(FILES, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 事实来源\n\n")
        f.write("- **原版 37 条建造条目吃焊条 / 0 条产出**（2026-10-14 我自己扫的，两种数法对过账）："
                "①`grep -rhoE \"item [0-9]+ \\[Base\\.WeldingRods\\]\"` 全量 `media/scripts/generated/entities/**` "
                "= 37 行；②按 `component CraftRecipe` 块解析（python 逐行记 brace 深度）= 37 条、涉及 37 个文件，"
                "两次分布一致：`{1:2, 2:8, 3:1, 4:22, 5:2, 10:2}`，按目录 `walls 20 / furniture 13 / "
                "barricades 2 / stairs 1 / animals 1`，技能 `MetalWelding` 从 2 级到 10 级\n")
        f.write("- **产出侧是 0**：`media/scripts/**` 全目录里 `craftRecipe` 的 outputs / 任何 `itemMapper` 的**键**"
                "（键=产出，值=消耗）都没有 `Base.WeldingRods`；`media/lua/**` 里只有战利品表"
                "（`ProceduralDistributions.lua` / `Distributions.lua` / `VehicleDistributions.lua` / "
                "`Distribution_*.lua` / `Foraging/Categories/Trash.lua`）与译名文件 —— **没有生产路径**\n")
        f.write("- **配方本体**：`bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/"
                "bin2_Recipes.txt` 的 `Bin2MakeWeldingRods` —— `time = 50`、`timedAction = Making`、"
                "`Tags = AnySurfaceCraft`、`category = Metalworking`、`SkillRequired = MetalWelding:1`；"
                "`inputs`: `item 1 [Base.SteelBar]` + `item 4 [Base.Charcoal;Base.CharcoalCrafted;Base.Coke]` + "
                "`item 1 [Base.Glue]` + `item 1 [Base.Salt]`；`outputs`: `item 2 Base.WeldingRods`；**没有工具位**\n")
        f.write("- **`time` 是秒**：同一次读里 `Bin2MakeGlue` 是 `240`、`Bin2MakeNutsBolts` 是 `200`，"
                "已发布的第一篇文案写的就是「240 秒」「200 秒」⇒ 本篇的 `50` 写「50 秒」\n")
        f.write("- **物品中文名**（游戏自带 `media/lua/shared/Translate/CN/ItemName.json`，键带 `Base.` 前缀）："
                "`WeldingRods`=焊条、`SteelBar`=钢条、`SteelChunk`=钢块、`Charcoal`=木炭、"
                "`CharcoalCrafted`=自制木炭、`Coke`=焦炭、`Glue`=胶水、`Salt`=盐、`BlowTorch`=丙烷喷灯、"
                "`SmallSheetMetal`=小金属板、`Pot`=蒸煮锅、`Kettle`=水壶\n")
        f.write("- **技能名**：`IGUI_perks_MetalWelding` = **金工**（`IG_UI.json`）⇒ 写「金工 1 级」，"
                "与第一篇的写法一致；不要写「焊接」\n")
        f.write("- **配方中文名「制作焊条」**：模组自带 `media/lua/shared/Translate/CN/Recipes.json` 的 "
                "`Bin2MakeWeldingRods`；线上工坊描述里那一行也写作 `Bin2MakeWeldingRods —— 制作焊条`"
                "（2026-10-14 现取 `GetPublishedFileDetails` 核到）\n")
        f.write("- **钢条的来源**：`recipes_blacksmith_bar.txt` 的 `Forge_Bar_From_Chunk`（中文名「用铁/钢块锻造铁/钢条」）"
                "= 4 `tags[base:charcoal]` + 4 `[Base.IronChunk;Base.SteelChunk] mappers[metalType]` + 锤子 + 夹钳，"
                "`Tags = PrimitiveForge`、`SkillRequired = Blacksmith:0`，mapper 里 `Base.SteelBar = Base.SteelChunk`"
                "（**键是产出**）；另一条 `CastSteelBar`（中文名「铸造钢条」）= 4 个钢坩埚 + 夹钳 + 4 木炭 + 钢条模具\n")
        f.write("- **金属墙那个例子**：`media/scripts/generated/entities/walls/entity_metal_walllvl1.txt` 的 "
                "`component CraftRecipe` —— `item 4 [Base.BlowTorch] flags[DontRecordInput]` + "
                "`item 3 [Base.SmallSheetMetal]` + `item 4 [Base.WeldingRods] flags[DontRecordInput]`、"
                "`SkillRequired = MetalWelding:3`；entity 名 `MetalWallLvl1` 在 `Recipes.json` 里是「金属墙 (基础)」\n")
        f.write("- **喷灯是工具**：`generated/items/drainable.txt` 的 `item BlowTorch` 有 `KeepOnDeplete = true`、"
                "`UseDelta = 0.1` ⇒ 烧完留在手里，被吃掉的是焊条\n")
        f.write("- **不是刷材料**：`item WeldingRods` 定义里只有 `ItemType = base:drainable`、`MetalValue = 20.0`、"
                "`UseDelta = 0.05`，**没有 `base:smeltable*` 一类标签** ⇒ 焊条回不了炉\n")
        f.write("- **胶水 / 盐两条**：`bin2_Recipes.txt` 的 `Bin2MakeGlue`（2 骨头 + 1 锅 + 1 升水 → 2 胶水，"
                "`Cooking:2`）与 `Bin2MakeSalt`（1 锅 + 0.5 升水 + 1 木炭 → 1 盐，`Cooking:1`）；"
                "锅具都是 `mode:keep`\n")
        f.write("- **线上版本**：`mod.info` 是 `modversion=1.7.1`（本机 Steam 副本 = 已发布副本）；"
                "`GetPublishedFileDetails` 现读 `time_updated=1791884966` = 2026-10-13 17:49:26、"
                "描述里 12 条配方都在列 ⇒ 这篇写的配方**确实在线上**，不是没上传的开发版\n")
        f.write("- **图标**：`Item_BlowTorch` 是 2026-10-14 用 `pz_pack_icons.py --emit Item_BlowTorch` 从 "
                "`UI2.pack` 现导的（`rect=(408,262,32,27)`，已补进 `manifest.json`：`Base.BlowTorch` / 丙烷喷灯）；"
                "其余复用已有素材\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 标题去空格 17 字 ≤ 20；发布前跑 `node 发布笔记.js --title-check --docs <本目录>`\n")
        f.write("- [ ] 正文里**不要出现**「已更新 / 新版」这类话：这条配方不是新版加的（正文里已经写明）\n")
        f.write("- [ ] 话题 8 个与第一篇/第四篇同一组，发布前 `--dry` 查存在性\n")
        f.write("- [ ] 发布时 `live_status` 是否真在播；不在播就不要在正文里邀请来直播间\n")
        f.write("- [ ] 招人帖（`笔记素材-招人`）仍在等图 2/3 与需求方口径，**与本篇互不影响**，"
                "别在同一天连发两条以上\n")


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
        print("   %-12s %s" % (n, ("%d bytes" % os.path.getsize(p)) if os.path.exists(p) else "缺失"))


if __name__ == "__main__":
    main()
