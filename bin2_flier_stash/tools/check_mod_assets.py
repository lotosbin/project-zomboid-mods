#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bin2_flier_stash 的静态自检（不启动游戏）：
  1) 战利品表里的每个物品 ID 都必须在游戏物品定义里存在（否则玩家拿到的是空手）
  2) Lua 里 getText("...") 用到的每个键都必须在本模组自己的翻译文件里（否则玩家看到键名）
  3) 顺手调 scripts/lua_syntax_check.sh 过一遍语法（拿到就用，拿不到就跳过并说明）

用法：
  python3 bin2_flier_stash/tools/check_mod_assets.py [--game-dir <Project Zomboid.app>]
退出码：0 全部通过；1 有失败项；2 环境问题（找不到游戏目录等）。
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.abspath(os.path.join(HERE, "..", "Contents", "mods", "bin2_flier_stash", "42.21"))
CONFIG = os.path.join(MOD_ROOT, "media", "lua", "shared", "Bin2FlierStash", "Bin2FlierStash_Config.lua")
TRANSLATION = os.path.join(MOD_ROOT, "media", "lua", "shared", "Translate", "CN", "UI.json")
LUA_CHECK = os.path.abspath(os.path.join(HERE, "..", "..", "scripts", "lua_syntax_check.sh"))
DEFAULT_GAME = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app"
)

fails = []


def item_is_defined(scripts_dir, item_id):
    """物品定义形如单独一行 `item Flier`；配方里是 `item 1 [Base.X]`，不会误命中。"""
    short = item_id.split(".", 1)[1] if "." in item_id else item_id
    pat = re.compile(r"^\s*item\s+" + re.escape(short) + r"\s*$", re.M)
    for dirpath, _dirnames, filenames in os.walk(scripts_dir):
        for fn in filenames:
            if not fn.endswith(".txt"):
                continue
            try:
                with open(os.path.join(dirpath, fn), "r", errors="ignore") as fh:
                    if pat.search(fh.read()):
                        return os.path.join(dirpath, fn)
            except OSError:
                continue
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-dir", default=os.environ.get("PZ_GAME_DIR", DEFAULT_GAME))
    args = ap.parse_args()

    scripts_dir = os.path.join(args.game_dir, "Contents", "Java", "media", "scripts")
    if not os.path.isdir(scripts_dir):
        print("FAIL 找不到游戏 scripts 目录: %s（用 --game-dir 指定）" % scripts_dir)
        return 2

    # 1) 战利品表
    with open(CONFIG, encoding="utf-8") as fh:
        cfg = fh.read()
    loot = re.findall(r'item\s*=\s*"(Base\.[A-Za-z0-9_]+)"', cfg)
    if not loot:
        fails.append("战利品表解析出 0 条 —— 正则或文件结构变了")
    seen = {}
    for item in loot:
        seen[item] = seen.get(item, 0) + 1
        where = item_is_defined(scripts_dir, item)
        if where:
            print("  ok   %-26s %s" % (item, os.path.relpath(where, scripts_dir)))
        else:
            print("  FAIL %-26s 游戏物品定义里找不到" % item)
            fails.append("战利品物品不存在: %s" % item)
    print("战利品表: %d 条（去重 %d 个 ID）" % (len(loot), len(seen)))

    # 2) 翻译键
    with open(TRANSLATION, encoding="utf-8") as fh:
        keys = {k for k in json.load(fh) if not k.startswith("$")}
    used = set()
    for dirpath, _dirnames, filenames in os.walk(MOD_ROOT):
        for fn in filenames:
            if fn.endswith(".lua"):
                with open(os.path.join(dirpath, fn), encoding="utf-8") as fh:
                    used |= set(re.findall(r'getText\(\s*"([^"]+)"\s*\)', fh.read()))
    for key in sorted(used):
        if key in keys:
            print("  ok   %s" % key)
        else:
            print("  FAIL %s 在本模组 UI.json 里没有" % key)
            fails.append("缺翻译键: %s" % key)
    print("翻译键: 代码用到 %d 个，UI.json 定义 %d 个" % (len(used), len(keys)))

    # 3) Lua 语法（外部工具，缺了不算失败）
    if os.path.isfile(LUA_CHECK):
        r = subprocess.run([LUA_CHECK, os.path.abspath(os.path.join(HERE, ".."))],
                           capture_output=True, text=True)
        tail = (r.stdout or r.stderr).strip().splitlines()
        print("Lua 语法: %s" % (tail[-1] if tail else "(无输出)"))
        if r.returncode != 0:
            fails.append("Lua 语法检查失败")
    else:
        print("Lua 语法: 跳过（没找到 %s）" % LUA_CHECK)

    print()
    if fails:
        print("结果: 失败 %d 项" % len(fails))
        for f in fails:
            print("  - %s" % f)
        return 1
    print("结果: 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
