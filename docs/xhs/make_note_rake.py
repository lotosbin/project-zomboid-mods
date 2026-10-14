#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成小红书笔记素材（第三篇知识贴）：锻造耙头（bin2 扩展 v1.7.1）—— 4 张图文卡 + 文案。

来源：`bin2_b42/Changelog.txt` 的 `[ 10/13/2026 ]` 段 + 模组脚本 `bin2_Recipes.txt` 的
`Bin2ForgeRakeHead` + 游戏自带 `recipes_blacksmith_heads.txt` / `recipes_assembly.txt`。

和 make_note.py / make_note_salt.py 共用同一套画卡工具（import make_note），这个文件只写"这一篇的内容"。
图标：这一篇要用的 耙头/钉耙/铁条(1/4)/金属加工冲头/长棍/猎刀 是 2026-10-13 用
`pz_pack_icons.py` 从游戏 texturepacks 里现导的（原来那 47 张里没有），已补进 manifest.json。

用法：python3 make_note_rake.py [输出目录]    默认 docs/xhs/笔记素材-耙头
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402
from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, icon, paste_icon, new_card, footer, draw_row, recipes_card,
)

OUT_DEFAULT = os.path.join(HERE, "笔记素材-耙头")

# 配方本体：照抄 bin2_Recipes.txt 的 Bin2ForgeRakeHead（tags 写法 ⇒ 卡片上写的名字必须对得上 tag 的持有者）
RAKE_RECIPE = dict(
    name="锻造耙头", lv="锻造 7 级", time="任意锻造炉", out_n=1,
    mats=[("Item_IronBar_Quarter", 4, "铁条"),
          ("Item_Charcoal", 5, "木炭"),
          ("Item_SmithingHammer", 0, "铁匠锤"),
          ("Item_BlacksmithTongs", 0, "夹钳"),
          ("Item_Punch_Forged", 0, "金属加工冲头")],
    prod="Item_RakeHead",
    legend=["材料那格是「铁条 (1/4)」：4 个就是 1 整根铁条",
            "木炭也收 自制木炭 / 焦炭；炉子最基础那档就够",
            "铁匠锤那格也收 圆头锤（锻造）",
            "三件工具都是「保留」：做完原样留在手里"],
)

NOTE_TITLE = "僵毁 B42 钉耙造不出来？现在能锻耙头了"  # 平台标题上限 20 字（不含空格）——数一遍再改

NOTE_BODY = """玩 Build 42 建农庄、种地、做农耕，钉耙是绕不开的工具；要修它、要做它，都得先有「耙头」。

我把游戏自带的锻造配方查了一遍：原版 19 条锻造配方里，有 13 条能打出各种「头」——锄头头、园艺叉头、铁铲头、镰刀、各种斧头和锤头都有自己的配方，唯独没有耙头。原版拿耙头只有两条路：搜刮，或者把一整把钉耙拆掉。

bin2 扩展 v1.7.1 补的就是这一条：

· 锻造耙头 → 4 个铁条 (1/4) + 5 个木炭 + 铁匠锤 + 夹钳 + 金属加工冲头 → 1 耙头（锻造 7 级，任意锻造炉）
· 4 个 1/4 铁条就是原版 1 整根铁条（原版那 4 个换 1 根的配方就在锻造栏里）
· 木炭不挑：木炭 / 自制木炭 / 焦炭都收；炉子也不挑：最基础那档就行（和原版园艺叉头同一档）
· 三件工具全是「保留」：铁匠锤、夹钳、金属加工冲头，做完原样留在手里

打出来的耙头怎么用？原版本来就有那条装配配方（游戏里叫「组装超长工具」）：
耙头 + 长棍 + 锤子 + 锋利小刀 → 钉耙（维护 1 级）。

顺带一个连带效果：原版做「耙头棒球棍」那类武器本来就要吃一个耙头，而以前耙头只能靠拆钉耙，供给被卡死；现在耙头能锻了，这些配方也就不卡了。

也确认过不会变成刷材料：4 个 1/4 铁条熔掉是 4 个铁块，打成耙头再熔只剩 2 个铁块，越熔越少。

边界写清楚：这条配方只做过离线脚本解析校验（用游戏自带的脚本解析器把模组全部 12 条配方跑通），还没在游戏里实测过——锻造面板里能不能选中、手感如何，哪一步对不上，评论区说一声。

模组：bin2 扩展（bin2_extension），工坊搜「bin2's B42 mods」，条目号 3628652563，2026-10-13 已更新（这条配方是 v1.7.1 加进来的），需要 Build 42.21.0 以上。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""

FILES = ["1-缺口.png", "2-配方.png", "3-装配.png", "4-说明.png"]


# ── 卡 1：原版能锻各种头，唯独没有耙头 ─────────────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 92), "僵毁 Build 42 · 耙头", font=font(36), fill=ACCENT2)
    d.text((72, 152), "原版就是没有耙头", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 276), (W - 56, 668)], radius=22, fill=CARD)
    d.text((92, 308), "游戏自带的锻造配方（recipes_blacksmith_heads）", font=font(28), fill=DIM)
    rows = [
        ("19", "条锻造配方", FG),
        ("13", "条能打出各种「头」（锄头 / 园艺叉 / 铁铲 / 斧头…）", FG),
        ("0", "条能做出「耙头」", ACCENT),
    ]
    y = 372
    for num, label, color in rows:
        d.text((92, y), num, font=font(72, True), fill=color)
        d.text((238, y + 22), label, font=font(33), fill=(214, 219, 228))
        y += 92

    d.text((72, 724), "原版拿耙头只有两条路：", font=font(42, True), fill=FG)

    y = 806
    paste_icon(img, "Item_Rake", (92, y), 74)
    for line in wrap(d, "搜刮碰运气，或者把一整把钉耙拆掉——"
                        "拆解配方里，钉耙拆出来的正是耙头（外加一根断掉的长棍）。",
                     font(32), W - 260):
        d.text((192, y + 8), line, font=font(32), fill=(200, 206, 216))
        y += 44

    y += 96
    paste_icon(img, "Item_RakeHead", (92, y), 74)
    for line in wrap(d, "所以「耙头棒球棍」这类原版武器配方一直卡着："
                        "它本来就要吃一个耙头，而耙头没有可制造的来源。",
                     font(32), W - 260):
        d.text((192, y + 8), line, font=font(32), fill=(200, 206, 216))
        y += 44

    d.text((72, 1210), "v1.7.1 给 bin2 扩展加了一条「锻造耙头」。", font=font(38, True), fill=ACCENT2)
    footer(d, "数据：游戏自带的锻造配方文件（19 条 craftRecipe）")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：配方本体 ───────────────────────────────────────────────
def card2(out):
    recipes_card(
        out, FILES[1], "bin2 扩展 · 锻造耙头（v1.7.1 新增）", "4 个 1/4 铁条 + 木炭",
        [RAKE_RECIPE], 520, 28,
        ["配方分类在「锻造」里，7 级解锁；一次出 1 个耙头",
         "打出来之后怎么用，看下一张"],
        "配方本体：模组脚本 bin2_Recipes.txt 的 Bin2ForgeRakeHead")


# ── 卡 3：打出来的耙头怎么用（原版装配配方）───────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "bin2 扩展 · 耙头的用法（装配是原版配方）", font=font(36), fill=ACCENT2)
    d.text((72, 152), "装上长棍就是钉耙", font=font(64, True), fill=FG)

    d.rounded_rectangle([(56, 268), (W - 56, 700)], radius=22, fill=CARD)
    d.text((92, 300), "这一步不用模组加东西 —— 原版本来就有这条装配配方", font=font(30), fill=DIM)
    d.text((92, 344), "游戏里叫「组装超长工具」，维护 1 级", font=font(30), fill=ACCENT2)

    draw_row(img, d, 424,
             [("Item_RakeHead", 0, "耙头"), ("Item_Shaft", 0, "长棍"),
              ("Item_Hammer_Forged", 0, "锤子"), ("Item_HuntingKnife", 0, "锋利小刀")],
             font(25), slot=150)
    d.text((92, 590), "→", font=font(46), fill=DIM)
    paste_icon(img, "Item_Rake", (150, 566), 74)
    d.text((250, 588), "钉耙（Base.Rake）", font=font(36), fill=GOOD)

    y = 760
    rows = [
        ("锤子不挑", "游戏里收 base:hammer / clubhammer / mallet 那一类：羊角锤、铁匠锤、圆头锤、石工锤、木锤都行。"),
        ("小刀要锋利", "配方要求「锋利小刀」这一整类（base:sharpknife），猎刀、厨房刀、小刀都可以。"),
        ("顺带：耙头还能装武器", "原版「耙头棒球棍 / 长手柄 (耙头)」那条武器配方也要吃一个耙头，以前卡供给，现在不卡了。"),
    ]
    for title, body in rows:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(31), W - 220):
            d.text((126, yy), line, font=font(31), fill=DIM)
            yy += 41
        y = yy + 26

    footer(d, "装配配方：游戏自带 recipes_assembly.txt 的 AssembleLongerImplement")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：这版要知道的 + 怎么找到 ─────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 110), "bin2 扩展 v1.7.1", font=font(38), fill=ACCENT2)
    d.text((72, 178), "几点要知道的", font=font(66, True), fill=FG)

    y = 300
    items = [
        ("锻造 7 级", "原版各种「头」的等级从 1 到 8 级不等（园艺叉头 8 级、铁铲头 6 级、圆头锤头 4 级），耙头定在 7 级。"),
        ("最基础那档炉子就够", "配方带 PrimitiveForge 标签，和原版园艺叉头同一档；不需要更高级的锻造炉。"),
        ("不会变成刷材料", "4 个 1/4 铁条熔掉是 4 个铁块，打成耙头再熔只剩 2 个铁块 —— 来回熔是亏的。"),
        ("没进游戏实测过", "只有离线校验：用游戏自带的脚本解析器把模组全部 12 条配方跑通，界面与手感还没实测。"),
        ("要 Build 42.21.0 以上", "低于这个版本客户端里本模组显示不可用；42.15.0 版 v1.0.4 已 EOL。"),
    ]
    for title, body in items:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38), fill=FG)
        yy = y + 58
        for line in wrap(d, body, font(31), W - 220):
            d.text((126, yy), line, font=font(31), fill=DIM)
            yy += 41
        y = yy + 24

    y += 4
    h = 200
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 26), "工坊搜索", font=font(30), fill=DIM)
    d.text((92, y + 66), "bin2's B42 mods", font=font(48, True), fill=FG)
    d.text((92, y + 134), "条目号 3628652563 · 2026-10-13 已更新",
           font=font(30), fill=GOOD)

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
    used = [(s, l) for s, _c, l in RAKE_RECIPE["mats"]] + [(RAKE_RECIPE["prod"], "耙头")]
    # 卡片上还会出现的：钉耙 / 长棍 / 锤子 / 锋利小刀（后者是「哪一类」，所以不核中文名）
    for sprite, want in used + [("Item_Rake", "钉耙"), ("Item_Shaft", "长棍")]:
        if sprite not in manifest:
            problems.append(f"素材里没有 {sprite}")
        elif icon(sprite) is None:
            problems.append(f"素材里没有 {sprite} 的图片文件")
        else:
            cn = [x["cn"] for x in manifest[sprite].get("items", [])]
            if cn and want and not any(want in c or c in want for c in cn):
                problems.append(f"{sprite} 卡上写「{want}」，manifest 是 {cn}")
    return problems


def write_copy(out):
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（bin2 扩展 · 锻造耙头 / v1.7.1）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(FILES, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 事实来源\n\n")
        f.write("- **原版 19 条锻造配方 / 13 条产出各种「头」/ 0 条产出耙头**：游戏自带 "
                "`media/scripts/generated/entities/blacksmith/craftRecipes/recipes_blacksmith_heads.txt` 里 "
                "`craftRecipe` 共 **19** 个，其中 `outputs` 里出现 `item N Base.*Head` 的 **13** 个"
                "（另有 6 个是长柄武器/钉头锤一类，不是「头」）；全量扫 `media/scripts/**` 的 `craftRecipe`，"
                "`outputs` 里出现 `Base.RakeHead` 的只有**拆解/装配/改装**三条，**没有任何锻造产出**\n")
        f.write("- **原版拿耙头的两条路**：`recipes_disassembly.txt` 的 `DismantleLongImplement`"
                "（输入含 `Base.Rake`，`itemMapper` 里 `Base.RakeHead = Base.Rake`）；"
                "另一条是搜刮（战利品表）。`recipes_improvised_weapons.txt` 的 `MakeRakeHeadWeapon` 是"
                "**消耗**耙头做武器（`item 1 [Base.RakeHead]`），不是来源\n")
        f.write("- **配方本体**：`bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/"
                "bin2_Recipes.txt` 的 `Bin2ForgeRakeHead` —— `time=500`、`SkillRequired=Blacksmith:7`、"
                "`Tags=PrimitiveForge`、`inputs`: `item 4 tags[base:barstockquarter]` + "
                "`item 5 tags[base:charcoal]` + `item 1 tags[base:smithinghammer] mode:keep` + "
                "`item 1 tags[base:tongs] mode:keep` + `item 1 tags[base:metalworkingpunch] mode:keep`；"
                "`outputs`: `item 1 Base.RakeHead`；**没有** `NeedToBeLearn`（刻意不加：原版那两份授予名单里"
                "没有模组配方名，加了会变成 8 级才认识、7 级做不出来）\n")
        f.write("- **tag 到底是谁**（2026-10-13 我逐个查的，这里是本篇「名词必须能指回游戏 JSON」的关键）："
                "`base:metalworkingpunch` → `Base.MetalworkingPunch` = **金属加工冲头**（`weapon.txt` 的 Tags 行）；"
                "`Base.MetalworkingChisel` = **金属加工凿**，带的是 `base:metalworkingchisel`，**不满足**耙头这条 —— "
                "线上工坊描述与 Changelog 原先写「金属加工凿」，是我核出来、@bin2_extension_mod_dev 已改（`8d129ce`）。"
                "`base:smithinghammer` → 铁匠锤 / 圆头锤 / 圆头锤（锻造）；`base:charcoal` → 木炭 / 自制木炭 / 焦炭；"
                "`base:barstockquarter` → `Base.IronBarQuarter` = 铁条 (1/4)；`base:tongs` → `Base.Tongs` = 夹钳\n")
        f.write("- **4 个 1/4 = 1 整根**：`recipes_blacksmith_bar.txt` 那条（`item 4 "
                "[Base.IronChunk;Base.SteelChunk;Base.IronBarQuarter;Base.SteelBarQuarter;2:Base.IronBarHalf;…]`"
                " + 4 木炭 + 锤子 + 夹钳）`itemMapper` 里 `Base.IronBar = Base.IronBarQuarter`\n")
        f.write("- **不构成刷材料**：`recipes_blacksmith_furnaces_i.txt` 的 `ExtractIronFromSmallItem` = "
                "1 个 `base:smeltableironsmall` → **1** 铁块（铁条 (1/4) 就带这个 tag，4 个 = 4 铁块）；"
                "`ExtractIronFromMediumItem` = 1 个 `base:smeltableironmedium` → **2** 铁块"
                "（`Base.RakeHead` 的 Tags 里有它）\n")
        f.write("- **装配那一步**：`recipes_assembly.txt` 的 `AssembleLongerImplement`（中文名「组装超长工具」，"
                "`SkillRequired = Maintenance:1`）：`tags[base:hammer;base:clubhammer;base:mallet]` + "
                "`tags[base:sharpknife]`（`SharpnessCheck;IsNotDull`）+ 头部列表（含 `Base.RakeHead`）+ "
                "`item 1 [Base.LongStick]`；`itemMapper` 里 `Base.Rake = Base.RakeHead`\n")
        f.write("- **物品中文名**：游戏自带 `media/lua/shared/Translate/CN/ItemName.json` —— "
                "`RakeHead`=耙头、`Rake`=钉耙、`LongStick`=长棍、`IronBarQuarter`=铁条 (1/4)、`IronBar`=铁条、"
                "`MetalworkingPunch`=金属加工冲头、`SmithingHammer`=铁匠锤、`Tongs`=夹钳、`Charcoal`=木炭、"
                "`HuntingKnife`=猎刀。**注意 `LongHandle_RakeHead` = 「长手柄 (耙头)」是武器，不是装配材料**\n")
        f.write("- **配方名「组装超长工具」**：游戏自带 `media/lua/shared/Translate/CN/Recipes.json` 的 "
                "`AssembleLongerImplement`\n")
        f.write("- **已上线（2026-10-13 17:49:26）**：远端读数（不是本机缓存）—— "
                "`POST api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/` "
                "`itemcount=1&publishedfileids[0]=3628652563` → `time_updated=1791884966` = "
                "**2026-10-13 17:49:26**、`file_size=194997`、描述里 `1.7.1` 与「锻造耙头」都在。"
                "**判据：`acf` 变了 ⇒ 上传发生过；`acf` 没变 ≠ 没上传（它是本地缓存）；线上是什么版本只认远端**\n")
        f.write("- **图标**：`docs/xhs/游戏图标素材/`，本篇新用了 6 个（`Item_RakeHead` `Item_Rake` "
                "`Item_IronBar_Quarter` `Item_Punch_Forged` `Item_Shaft` `Item_HuntingKnife`），"
                "由 `docs/xhs/pz_pack_icons.py` 从 `media/texturepacks/UI2.pack` 现导；"
                "该脚本先用已有的 `Item_Charcoal` 做过像素级对账（与旧图完全一致）\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 发布时 `live_status` 是否真在播；不在播就不要在正文里邀请来直播间\n")
        f.write("- [ ] 这篇与已发布的 1.7.0 两篇同属「补原版缺口」系列，**正文不要重复前两篇的清单**\n")
        f.write("- [ ] 线上工坊描述仍写着「金属加工凿」（17:49:26 那版）——**渠道文案一律写「金属加工冲头」**，"
                "描述覆盖要 @human 再传一次工坊条目\n")


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
