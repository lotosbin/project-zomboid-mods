#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CompanionDogsBlockyAlpaca 的翻译校验（发布前必跑）。

规则与写实羊驼那套一致（都来自官方手册第 6 节的坑）：
  1. JSON 必须能解析，且**不能有重复键**（重复键会被后一个静默吃掉）；
  2. 文件不能带 BOM（带 BOM 的语言文件不编译，而且报错会指向另一个文件）；
  3. 同一批键必须在所有语言里都存在（少一个，那个语言就显示原始 key）；
  4. 文案里不能有裸的 `%`（getText 是格式化器，裸 `%` 会让显示它的窗口崩掉；`%1` / `%%` 合法）。

本 addon 额外做一条**交叉一致性检查**：`CompanionDogsBlockyAlpaca_Breed.lua` 里声明的
每个品种键都必须有 `IGUI_PD_Breed_<key>`，每个 engineBreed 都必须有 `IGUI_Breed_<engine>`，
描述键同理 —— 漏一个，玩家看到的就是原始 key。

用法：python3 check_translations.py [--dir <Translate 目录>]
"""
import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TRANS = os.path.abspath(os.path.join(
    HERE, "..", "..", "Contents", "mods", "CompanionDogsBlockyAlpaca", "42",
    "media", "lua", "shared", "Translate"))
DEFAULT_BREED_LUA = os.path.abspath(os.path.join(
    HERE, "..", "..", "Contents", "mods", "CompanionDogsBlockyAlpaca", "42",
    "media", "lua", "shared", "CompanionDogsBlockyAlpaca_Breed.lua"))

LANGS = ["EN", "CN", "CH"]


def load_no_dup(path, errs):
    raw = io.open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        errs.append(f"{path}: 带 BOM（语言文件不能带 BOM）")
    dups = []
    text = raw.decode("utf-8")

    def hook(pairs):
        seen = set()
        for k, _ in pairs:
            if k in seen:
                dups.append(k)
            seen.add(k)
        return dict(pairs)

    data = json.loads(text, object_pairs_hook=hook)
    for k in dups:
        errs.append(f"{path}: 重复键 {k}")
    return data


def check_percent(path, data, errs):
    for k, v in data.items():
        if not isinstance(v, str):
            continue
        stripped = re.sub(r"%%|%[0-9]", "", v)
        if "%" in stripped:
            errs.append(f"{path}: 键 {k} 里有裸的 %")


def breed_table(lua_path, errs):
    """从 Breed.lua 里抓出 (key, engine) 对照表（不跑 Lua，纯正则，够用且不引入依赖）。"""
    if not os.path.exists(lua_path):
        errs.append(f"{lua_path}: 找不到 Breed.lua")
        return []
    text = io.open(lua_path, encoding="utf-8").read()
    table = text[text.index("local COATS"):]
    # 表以"行首的 }"结束：不能用第一个 '}'（那是第一个品种项自己的右花括号）
    table = table[:table.index("\n}")]
    pairs = re.findall(r'key\s*=\s*"([^"]+)"\s*,\s*engine\s*=\s*"([^"]+)"', table)
    if not pairs:
        errs.append("Breed.lua: 没抓到 COATS 表（正则失配？）")
    return pairs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_TRANS)
    ap.add_argument("--breed-lua", default=DEFAULT_BREED_LUA)
    args = ap.parse_args()

    errs = []
    data = {}
    for lang in LANGS:
        p = os.path.join(args.dir, lang, "IG_UI.json")
        if not os.path.exists(p):
            errs.append(f"缺少语言文件 {p}")
            continue
        data[lang] = load_no_dup(p, errs)
        check_percent(p, data[lang], errs)

    if len(data) > 1:
        keysets = {lang: set(d.keys()) for lang, d in data.items()}
        base_lang = LANGS[0] if LANGS[0] in keysets else sorted(keysets)[0]
        for lang, ks in keysets.items():
            missing = keysets[base_lang] - ks
            extra = ks - keysets[base_lang]
            for k in sorted(missing):
                errs.append(f"{lang}: 缺少键 {k}（{base_lang} 里有）")
            for k in sorted(extra):
                errs.append(f"{lang}: 多出键 {k}（{base_lang} 里没有）")

    # 交叉一致性：Breed.lua 的每个品种都要有名字键 + 描述键
    pairs = breed_table(args.breed_lua, errs)
    en = data.get("EN", {})
    for key, engine in pairs:
        for need in (f"IGUI_PD_Breed_{key}", f"IGUI_Breed_{engine}", f"IGUI_PD_BreedDesc_{key}"):
            if need not in en:
                errs.append(f"EN: 缺少 Breed.lua 需要的键 {need}")
            for lang in LANGS:
                if lang in data and need not in data[lang]:
                    errs.append(f"{lang}: 缺少 Breed.lua 需要的键 {need}")

    print(f"langs      : {', '.join(sorted(data))}")
    for lang in sorted(data):
        print(f"  {lang}: {len(data[lang])} keys")
    print(f"breeds     : {len(pairs)} ({', '.join(k for k, _ in pairs)})")
    if errs:
        print("RESULT: FAIL")
        for e in errs:
            print("  - " + e)
        return 1
    print("RESULT: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
