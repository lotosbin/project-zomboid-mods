#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成小红书「招人」素材：怎么找到我们（1 张卡）。

**这一篇的文字口径全部来自服务器侧素材 `docs/server-ops/recruiting.md`（2026-10-13 订正到 437d340），
不是我自己写的**：地址/端口、无需申请（线上 `Open=true`）、上限 32 人、模组数写"一百多个条目、还在加"。
**不写**：在线人数、玩法模式（线上 `PVP=true` 与名字里的 PVE 冲突未定）、KOOK 链接（两个短链未定）。

和 make_note.py / make_note_salt.py / make_note_rake.py 共用同一套画卡工具（import make_note）。

用法：python3 make_note_recruit.py [输出目录]    默认 docs/xhs/笔记素材-招人
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_note as mn  # noqa: E402
from make_note import W, H, CARD, FG, DIM, ACCENT2, GOOD, font, wrap, new_card, footer  # noqa: E402

OUT_DEFAULT = os.path.join(HERE, "笔记素材-招人")

# ── 口径常量（改这里就等于改稿；名字/端口只能来自服务器侧素材）────────────
SERVER_NAME = "呼噜小世界"          # 线上 PublicName = [CN][PVE]呼噜小世界4长期生存挑战（列表里搜这个前缀能搜到）
SERVER_ADDR = "110.42.14.5:21217"   # 端口 21217；16261 是游戏默认端口、本服没登记，写它是错的
MODPACK = "一百多个工坊条目（两百来个模组，还在加）"

FACTS = [
    "公开服、无密码",
    "不用申请，搜到就能进",
    "上限 32 人",
]


def card_find(out):
    img, d = new_card()
    d.text((72, 104), "Project Zomboid · Build 42", font=font(38), fill=ACCENT2)

    y = 186
    for line in ["服务器列表里搜", "「" + SERVER_NAME + "」"]:
        d.text((72, y), line, font=font(74, True), fill=FG)
        y += 96

    y += 8
    for line in wrap(d, "（列表里显示的全名：[CN][PVE]" + SERVER_NAME + "4长期生存挑战）", font(30), W - 144):
        d.text((72, y), line, font=font(30), fill=DIM)
        y += 44

    # 地址块
    y += 24
    box = (72, y, W - 72, y + 132)
    d.rounded_rectangle(box, radius=20, fill=CARD)
    d.text((104, y + 26), "也可以直接连", font=font(30), fill=DIM)
    d.text((104, y + 66), SERVER_ADDR, font=font(56, True), fill=GOOD)
    y = box[3] + 44

    # 三条事实
    for t in FACTS:
        d.ellipse((76, y + 14, 96, y + 34), fill=GOOD)
        d.text((120, y), t, font=font(42), fill=FG)
        y += 66

    # 下载提醒（对新手同时是门槛，必须和"模组多"同段出现）
    y += 22
    d.line((72, y, W - 72, y), fill=(60, 66, 76), width=2)
    y += 30
    d.text((72, y), "第一次进服要等下载", font=font(44, True), fill=ACCENT2)
    y += 66
    for line in wrap(d, "服里装了" + MODPACK + "。第一次进服要等一会儿下载，"
                        "别在下载界面反复退出重进。", font(36), W - 144):
        d.text((72, y), line, font=font(36), fill=FG)
        y += 52

    y += 26
    d.text((72, y), "进服卡住？评论区说一声就行", font=font(36), fill=DIM)

    footer(d, "怎么找到我们 · 长期档 · 无密码")
    img.save(os.path.join(out, "招人卡1-怎么找到我们.png"))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT_DEFAULT
    os.makedirs(out, exist_ok=True)
    card_find(out)
    print("已生成到", out)
    print("  招人卡1-怎么找到我们.png")
    print("服务器名：", SERVER_NAME, "／地址：", SERVER_ADDR)
    print("提醒：图 2/3 是 B 站侧从那场直播录屏抽的帧（带文件名+时间戳、不带玩家昵称），不在这里生成。")


if __name__ == "__main__":
    main()
