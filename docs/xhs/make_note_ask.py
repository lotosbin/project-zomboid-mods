#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成小红书笔记素材（第三篇）：**征求玩家建议** —— 4 张图文卡（用游戏原生图标）+ 文案。

这一篇和前两篇不同：前两篇是"我们做了什么"，这一篇是"你想要什么"。
所以取舍也不一样：**正文不摆选项**。摆选项会把回答引到我想到的方向上，
征求就白做了（口径来自 Thread thread:47db2704 里和各成员定下的做法）。

可复核的事实来源（都写进 文案.md 的「事实来源」）：
  · 原版做不出盐 / 969 条 craftRecipe -> 扫游戏自带 media/scripts/generated/recipes/*.txt（见 make_note_salt.py）
  · 1.7.0 五条配方与「没有一条能用材料把它们做出来的配方」口径 -> 第一篇已发笔记 + @bin2_extension_mod_dev 复核
  · 已上线（v1.7.0）-> appworkshop_108600.acf 条目 3628652563 的 timeupdated=1791812609（2026-10-12 21:43:29）
                       + Steam 本地副本 mods/bin2_extension/42.19.0/mod.info 的 modversion=1.7.0
  · 制盐配方本体 -> Steam 本地副本 mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt 的 Bin2MakeSalt
  · 接 / 不接四类 -> @bin2_extension_mod_dev 2026-10-13 10:12 在 Thread 47db2704 给的判据
  · 结论留痕（能做的/不能做的/被拒的都写理由）-> @过程改进组长 的 docs/社区建议/README.md 三态口径

用法：python3 make_note_ask.py [输出目录]    默认 docs/xhs/笔记素材-征集建议
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402  复用同一套画卡工具（font/wrap/icon/卡片/页脚）
from make_note import (  # noqa: E402
    W, H, CARD, FG, DIM, ACCENT, ACCENT2, GOOD,
    font, wrap, icon, paste_icon, new_card, footer,
)
from PIL import ImageDraw  # noqa: E402

OUT_DEFAULT = os.path.join(HERE, "笔记素材-征集建议")

NOTE_TITLE = "你们想要什么模组？"

NOTE_BODY = """我们在给《僵尸毁灭工程》Build 42 做中文模组，现在想问一个问题：你缺什么？

我们做的事很小、但很具体：补上原版里「本该能做、却做不出来」的东西。最近做了两件：

· 让废料有用 —— 螺母与螺栓、圆锯片、螺丝、胶水、手锯条，原版没有一条能用材料把它们做出来的配方，现在能自己做了（5 条配方，v1.7.0）
· 能自己煮盐 —— 原版 969 条配方里没有一条能产出盐，可装罐头、腌菜、做烘焙一直要盐；现在 1 口锅 + 0.5 升水 + 1 块木炭就能煮出 1 份盐（6 种锅都能用）

接下来做什么，我想听玩家的。

什么样的建议最有用：

· 最好的一句是「原版里本来该能做、但游戏里没有任何路径的东西」
· 说清场景就够：你什么时候卡住、想要的结果长什么样。比如「装罐头总缺盐，想能自己煮盐」——上面第二条就是这么来的
· 不用会写代码，也不用知道该怎么做

先说清哪几类我们做不了，省得你白等：

· 改平衡数值（伤害、价格、掉率）
· 把别的模组整包合并进来
· 需要从零画美术的
· 会形成材料循环的：拿 1 块料能无限刷成品，这种一律不做

说完之后会发生什么：

1. 每条都会被记下来（原文 + 出处），汇总成一张清单，交到做模组的人手里
2. 逐条过：能做的排进计划；不能做的，写明是哪条门槛挡住的
3. 被拒绝的也留痕——下次有人再提，能直接看到理由

不承诺「一定做」，也不承诺在评论区逐条回复；但每条都会进清单，给出「做 / 不做 + 理由」。

评论区直接说。没有选项，也不用懂代码。

模组在工坊搜「bin2's B42 mods」（条目号 3628652563）。

#僵尸毁灭工程 #僵毁 #projectzomboid #僵毁mod #B42 #生存游戏 #单机游戏 #游戏模组"""

FILES = ["1-提问.png", "2-做过什么.png", "3-怎么提.png", "4-会怎么处理.png"]

# 卡 2 用的图标：都要在 游戏图标素材/ 里真实存在（check_icons 会自检）
DID_ITEMS = [
    ("Item_IronScrap", "铁废料"),
    ("Item_NutsBolts", "螺母与螺栓"),
    ("Item_CircularSawBlade", "圆锯片"),
    ("Item_Screws", "螺丝"),
    ("Item_Glue", "胶水"),
    ("Item_Sawblade", "手锯条"),
]

# 卡 2 上排图标：只放"产出"（铁废料是材料，混在里面会让人以为它也是产出）
PRODUCT_ICONS = [
    ("Item_NutsBolts", "螺母与螺栓"),
    ("Item_Screws", "螺丝"),
    ("Item_CircularSawBlade", "圆锯片"),
]


# ── 卡 1：提问 ────────────────────────────────────────────────────
def card1(out):
    img, d = new_card()
    d.text((72, 104), "僵尸毁灭工程 Build 42 · 中文模组", font=font(36), fill=ACCENT2)

    y = 200
    for line in ["你们想要", "什么模组？"]:
        d.text((72, y), line, font=font(88, True), fill=FG)
        y += 112

    y += 24
    for line, f, c in [
        ("我们在给《僵尸毁灭工程》做中文模组，", 40, (206, 212, 222)),
        ("补上原版里「本该能做、却做不出来」的东西。", 40, (206, 212, 222)),
        ("现在想听玩家的：你缺什么？", 46, FG),
    ]:
        d.text((72, y), line, font=font(f, f >= 46), fill=c)
        y += 62

    y += 48
    d.rounded_rectangle([(56, y), (W - 56, y + 300)], radius=26, fill=(33, 40, 34))
    d.text((92, y + 36), "在哪说", font=font(30), fill=DIM)
    d.text((92, y + 82), "评论区直接说", font=font(64, True), fill=FG)
    for i, line in enumerate(["没有选项，也不用懂代码；",
                              "你说什么，我们就看什么。"]):
        d.text((92, y + 178 + i * 46), line, font=font(34), fill=GOOD)

    y += 348
    for f, c, line in [
        (38, FG, "我们不把别的模组的功能整包合并，"),
        (38, FG, "只做「原版缺的那一块」。"),
    ]:
        d.text((72, y), line, font=font(f), fill=c)
        y += 58

    d.text((72, y + 20), "模组在工坊搜 bin2's B42 mods", font=font(30), fill=DIM)

    footer(d, "这篇是征求建议，不是发布新功能")
    img.save(os.path.join(out, FILES[0]))


# ── 卡 2：我们最近做过什么（证明不是空喊）────────────────────────
def card2(out):
    img, d = new_card()
    d.text((72, 92), "先说我们做过什么", font=font(36), fill=ACCENT2)
    d.text((72, 152), "最近两件事", font=font(66, True), fill=FG)

    # ① 五条配方
    y = 292
    h = 424
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=CARD)
    d.text((92, y + 32), "①  让废料有用", font=font(46, True), fill=FG)
    d.text((92, y + 100), "这些以前没有一条能用材料把它们做出来的配方：",
           font=font(30), fill=DIM)
    x = 92
    for sprite, label in PRODUCT_ICONS:
        paste_icon(img, sprite, (x, y + 148), 90)
        d.text((x + 45 - d.textlength(label, font=font(24)) / 2, y + 252),
               label, font=font(24), fill=DIM)
        x += 200
    d.text((92, y + 306), "现在能自己做了：螺母与螺栓 / 螺丝 / 圆锯片 / 手锯条 / 胶水",
           font=font(32), fill=GOOD)
    d.text((92, y + 356), "5 条配方 · v1.7.0 · 2026-10-12 上线", font=font(28), fill=DIM)

    # ② 制盐
    y = 748
    h = 372
    d.rounded_rectangle([(56, y), (W - 56, y + h)], radius=24, fill=CARD)
    paste_icon(img, "Item_Salt", (92, y + 40), 96)
    d.text((216, y + 48), "②  能自己煮盐", font=font(46, True), fill=FG)
    d.text((92, y + 140), "原版 969 条配方里，能产出盐的是 0 条；",
           font=font(32), fill=DIM)
    d.text((92, y + 186), "可装罐头、腌菜、做烘焙一直要盐。", font=font(32), fill=DIM)
    paste_icon(img, "Item_SaucepanEmpty", (92, y + 244), 78)
    paste_icon(img, "Item_Charcoal", (186, y + 244), 78)
    paste_icon(img, "Item_Salt", (280, y + 244), 78)
    d.text((386, y + 262), "1 口锅 + 0.5 升水 + 1 块木炭 → 1 盐",
           font=font(31), fill=GOOD)
    d.text((386, y + 306), "6 种锅都能用", font=font(28), fill=DIM)

    footer(d, "都已上线：工坊搜 bin2's B42 mods（条目号 3628652563）")
    img.save(os.path.join(out, FILES[1]))


# ── 卡 3：什么样的建议最有用 ─────────────────────────────────────
def card3(out):
    img, d = new_card()
    d.text((72, 92), "怎么提，我们才用得上", font=font(36), fill=ACCENT2)
    d.text((72, 152), "什么样的建议最有用", font=font(62, True), fill=FG)

    y = 280
    d.rounded_rectangle([(56, y), (W - 56, y + 236)], radius=24, fill=(33, 40, 34))
    d.text((92, y + 28), "最好的一句是", font=font(30), fill=DIM)
    yy = y + 76
    for line in wrap(d, "「原版里本来该能做、但游戏里没有任何路径的东西」",
                     font(42, True), W - 190):
        d.text((92, yy), line, font=font(42, True), fill=FG)
        yy += 56

    y = 540
    for title, body in [
        ("说清场景就够", "你什么时候卡住、想要的结果长什么样。"),
        ("举个真例子", "「装罐头总缺盐，想能自己煮盐」——第二条就是这么来的。"),
        ("不用懂代码", "也不用知道该怎么实现，那是我们的事。"),
    ]:
        d.ellipse([(78, y + 12), (98, y + 32)], fill=ACCENT2)
        d.text((126, y), title, font=font(38, True), fill=FG)
        yy = y + 56
        for line in wrap(d, body, font(31), W - 210):
            d.text((126, yy), line, font=font(31), fill=DIM)
            yy += 42
        y = yy + 16

    y += 10
    d.text((72, y), "先说清这几类我们做不了，省得你白等：", font=font(33, True), fill=ACCENT)
    y += 54
    for line in ["改平衡数值（伤害 / 价格 / 掉率）",
                 "把别的模组整包合并 · 需要从零画美术",
                 "会形成材料循环的：拿 1 块料能无限刷成品"]:
        d.text((72, y), line, font=font(30), fill=(200, 206, 216))
        y += 44

    footer(d, "这几类是按模组侧给的判据写的，不是随口推的")
    img.save(os.path.join(out, FILES[2]))


# ── 卡 4：说完之后会发生什么 ─────────────────────────────────────
def card4(out):
    img, d = new_card()
    d.text((72, 92), "不是喊完就散", font=font(36), fill=ACCENT2)
    d.text((72, 152), "说完之后会发生什么", font=font(62, True), fill=FG)

    y = 296
    items = [
        ("每条都记下来", "原文 + 出处（哪条笔记、哪一楼），汇总成一张清单，交到做模组的人手里。"),
        ("逐条过", "能做的排进计划；不能做的，写明是哪条门槛挡住的。"),
        ("被拒绝也留痕", "下次有人再提同一件事，能直接看到理由，不用重新问一遍。"),
    ]
    for i, (title, body) in enumerate(items, 1):
        d.rounded_rectangle([(56, y), (W - 56, y + 196)], radius=22, fill=CARD)
        d.text((92, y + 30), "%d" % i, font=font(56, True), fill=ACCENT2)
        d.text((156, y + 34), title, font=font(42, True), fill=FG)
        yy = y + 100
        for line in wrap(d, body, font(31), W - 280):
            d.text((156, yy), line, font=font(31), fill=DIM)
            yy += 42
        y += 216

    y += 26
    d.rounded_rectangle([(56, y), (W - 56, y + 200)], radius=26, fill=(33, 40, 34))
    d.text((92, y + 26), "不承诺「一定做」，也不承诺在评论区逐条回复",
           font=font(30), fill=DIM)
    d.text((92, y + 70), "但每条都会进清单、给出「做 / 不做 + 理由」。", font=font(36, True), fill=FG)
    d.text((92, y + 146), "评论区直接说。", font=font(36, True), fill=ACCENT2)

    footer(d, "清理方式与去标识化：只留原文与出处，不留昵称")
    img.save(os.path.join(out, FILES[3]))


def check_icons():
    """自检：脚本引用的 sprite 必须真在素材里（manifest 有、且图片文件在）。"""
    manifest_path = os.path.join(mn.ICON_DIR, "manifest.json")
    problems = []
    used = [s for s, _ in DID_ITEMS] + ["Item_Salt", "Item_SaucepanEmpty", "Item_Charcoal"]
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
    for sprite in used:
        if manifest and sprite not in manifest:
            problems.append(f"manifest 里没有 {sprite}")
        if icon(sprite) is None:
            problems.append(f"素材里没有 {sprite} 的图片文件")
    return problems


def write_copy(out):
    with open(os.path.join(out, "文案.md"), "w", encoding="utf-8") as f:
        f.write("# 小红书笔记文案（征求模组建议）\n\n")
        f.write("## 标题（%d 字）\n\n%s\n\n" % (len(NOTE_TITLE), NOTE_TITLE))
        f.write("## 正文\n\n%s\n\n" % NOTE_BODY)
        f.write("## 配图（按顺序上传）\n\n")
        for i, n in enumerate(FILES, 1):
            f.write("%d. %s\n" % (i, n))
        f.write("\n## 内容取舍（为什么这么写）\n\n")
        f.write("- **不摆选项**：摆选项会把回答引到我想到的方向上，征求就白做了。"
                "这一条是和 @过程改进组长、@bin2_extension_mod_dev 在 Thread 47db2704 里定下的，"
                "所以正文里不出现「你想要 A 还是 B」，也不出现任何备选方向的清单\n")
        f.write("- **先说自己做过什么**：玩家不知道我们靠不靠得住，空喊「提建议」没人理。"
                "所以卡 2 只放**已上线**的两件（都经我或模组侧回读过线上状态）\n")
        f.write("- **先说清做不了什么**：判据照抄模组侧给的\"不接\"四类，"
                "不是我自己推的；这样收到的建议才落在能做的范围里\n")
        f.write("- **承诺只承诺能兑现的**：写「每条都会进清单、给出做/不做 + 理由」而不是「每条都会做」，"
                "也**不承诺在评论区逐条回复**（几百条评论做不到，机制也不是逐条回复）——"
                "三态（能做的 / 不能做的 + 理由 / 被拒绝 + 理由）是 `docs/社区建议/README.md` 的口径。"
                "这条是 @bin2_extension_mod_dev 2026-10-13 10:20 复核时提的，**发布前已改**\n")
        f.write("- **不用「整合包」这个词**：我们自己的工坊页简介里就写着「一个上百个 mod 的中文化整合包」，"
                "在正文里说「不做整合包」玩家一对照就会问「那你们做的算什么」。"
                "所以收窄成「不把别的模组的功能整包合并进来」（与卡 3 同义）。同样是 10:20 复核提的\n")
        f.write("\n## 事实来源\n\n")
        f.write("- **原版 969 条配方里能产出盐的是 0 条**：扫游戏自带 "
                "`media/scripts/generated/recipes/*.txt` 全部 `craftRecipe` 的 `outputs` 块，"
                "产出 `Base.Salt` / `Base.SeasoningSalt` 的为 0（盐只作为 inputs 出现）；"
                "复核口径与命令见 `笔记素材-制盐/文案.md`\n")
        f.write("- **「没有一条能用材料把它们做出来的配方」**（螺母与螺栓 / 圆锯片 / 螺丝 / 胶水 / 手锯条）："
                "这是第一篇笔记（2026-10-12 22:37 已发）的口径，已经过 @bin2_extension_mod_dev 逐句复核——"
                "**螺丝另有 `OpenBox100` 开箱路径**，所以不能写「做不出来」，只能写"
                "「没有一条能用材料把它们做出来的配方」\n")
        f.write("- **已上线（v1.7.0）**：`appworkshop_108600.acf` 里条目 `3628652563` 的 "
                "`timeupdated=1791812609`（2026-10-12 21:43:29），且 Steam 本地副本 "
                "`steamapps/workshop/content/108600/3628652563/mods/bin2_extension/42.19.0/mod.info` 的 "
                "`modversion=1.7.0` —— 玩家手上那份就是它\n")
        f.write("- **制盐配方本体**：同副本的 `media/scripts/recipes/bin2_Recipes.txt` 的 `Bin2MakeSalt`"
                "（6 个锅具 fullType + `-fluid 0.5 categories[Water]` + 三种木炭 + `outputs` 只留 `Base.Salt`）\n")
        f.write("- **「不接」四类**：@bin2_extension_mod_dev 2026-10-13 10:12 在 Thread 47db2704 给的判据"
                "（改平衡数值 / 整合别的模组 / 需要从零画美术 / 会形成材料循环）；"
                "其中的\"回炉\"闸门：回炉产出 ≥ 配方消耗 = 拿 1 块料刷无限成品\n")
        f.write("- **结论三态与留痕**：`docs/社区建议/README.md`（@过程改进组长 建）——"
                "`已采纳` 必须指向 commit/任务，`已拒绝` 必须写理由\n")
        f.write("- **图标**：`docs/xhs/游戏图标素材/`（pz_atlas 自 UI2.pack / UI.pack 导出，"
                "sprite → 物品见 manifest.json）\n")
        f.write("- **评论收集与去标识化**：@过程改进组长 2026-10-13 10:11 的口径——"
                "快照只存 `原文 + 笔记链接 + 抓取时间`，不留昵称 / 头像 / uid，不塞整页 HTML\n")
        f.write("\n## 发布前待核\n\n")
        f.write("- [ ] 发布时 `live_status` 是否真在播；不在播就不要在正文里邀请来直播间（正文没写直播）\n")
        f.write("- [ ] 与前两篇不重复：这篇是**征求建议**，正文不复述上一篇的配方细节"
                "（只各留一句做\"我们做过什么\"的证据）\n")
        f.write("- [ ] 发布后**回读公开侧**确认可见（后台分页签 + 公开侧作者页），并写明读数时间\n")
        f.write("- [ ] 话题必须是**真话题**（走建议下拉），不能只在正文里写 # 文字\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT_DEFAULT
    os.makedirs(out, exist_ok=True)

    problems = check_icons()
    if problems:
        print("⚠️ 图标对不上，先别发布：")
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
        print("   %-16s %s" % (n, ("%d bytes" % os.path.getsize(p)) if os.path.exists(p) else "缺失"))


if __name__ == "__main__":
    main()
