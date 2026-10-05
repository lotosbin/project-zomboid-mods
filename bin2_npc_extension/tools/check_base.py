#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
公共层隔离守卫（bin2_npc_extension 的持续不变量，随时可跑）。

背景：Contents/mods/Bin2NPCExtensionBase 是「A-Life/Jeem 适配 + 契约模型 + 维护循环 + 命令路由」
的公共实现，两个口味（橙子社区经济版 / YeseMarket 版）在运行时各自把它实例化一次。
"抽取"能长期成立的前提是两条纪律，这个脚本把它们变成可执行断言：

  A. **公共层零身份**：公共层里不允许出现任何口味的身份字面量
     （mod id / 存档表名 / 沙盒表名 / 翻译前缀 / 玩家键前缀 / 账单条目 / 经济模组的全局名、
     id、显示名、货币叫法 / 工坊 id）。一旦泄漏，另一个口味就会拿到错的表名或错的前缀 ——
     而这种错误在游戏里表现为"存档写进了别人的表"或"翻译全是键名"，很难查。

  B. **口味之间不撞车**：两个口味的 module / tag / sandboxTable / textPrefix / playerPrefix
     必须两两不同（否则两边会写同一张存档表、抢同一套沙盒选项、互相盖翻译键）；并且
     sibling 必须指向**另一个**口味，不能指向自己。
     （b 的 sibling 自指是真实发生过的 bug：生成器的"翻 id"被随后的全局替换吃掉，
       YeseMarket 版把 sibling 写成了自己，导致重招被解雇/阵亡的 NPC 会误报
       "已被其他玩家雇走"。见 docs/develop_log_2026-10-05.md。）

用法：
    python3 tools/check_base.py            # 全部检查
    python3 tools/check_base.py --verbose
"""

from __future__ import annotations

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)
MODS_DIR = os.path.join(ITEM_DIR, "Contents", "mods")
BASE_MOD = "Bin2NPCExtensionBase"
CORE = "Bin2NPCExtensionCore"
VERSION_DIR = "42.21"

TEXT_EXT = (".lua", ".json", ".txt", ".info", ".md")

# 公共层自己的名字：它们**必然**包含橙子口味的 mod id 作为前缀（"Bin2NPCExtension" + Base/Core），
# 这是用户点名要的目录名，不是身份泄漏。检查前先摘掉它们。
BASE_OWN_NAMES = (CORE, BASE_MOD, "Bin2NPCBase")

PROFILE_KEYS = (
    "module", "version", "coreApi", "tag", "sandboxTable", "sibling",
    "textPrefix", "playerPrefix", "flowItem",
    "economyGlobal", "economyServerGlobal", "economyModId", "economyName", "currencyName",
)

# 跨口味必须唯一的字段（撞车 = 两边写同一张表 / 抢同一套选项 / 互相盖翻译键）
UNIQUE_KEYS = ("module", "tag", "sandboxTable", "textPrefix", "playerPrefix", "flowItem")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def walk_text_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
        for name in sorted(filenames):
            if name.lower().endswith(TEXT_EXT):
                yield os.path.join(dirpath, name)


def parse_lua_spec(text):
    """从 Profile.lua 的 spec 表里取出 `key = <字面量>`（字符串或数字）。"""
    spec = {}
    for key in PROFILE_KEYS:
        match = re.search(r'^\s*%s\s*=\s*("(?:[^"\\]|\\.)*"|\d+)\s*,?\s*$' % key, text, re.M)
        if match:
            raw = match.group(1)
            spec[key] = raw[1:-1] if raw.startswith('"') else int(raw)
    return spec


def parse_mod_info(text):
    fields = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            fields.setdefault(key.strip(), value.strip())
    return fields


def discover_flavours():
    """口味 = 在 media/lua/shared/<自己的名字>/Profile.lua 里有 spec 的模组。"""
    flavours = {}
    for name in sorted(os.listdir(MODS_DIR)):
        if name == BASE_MOD:
            continue
        profile = os.path.join(MODS_DIR, name, VERSION_DIR, "media", "lua", "shared", name, "Profile.lua")
        if not os.path.isfile(profile):
            continue
        flavours[name] = profile
    return flavours


def core_api():
    path = os.path.join(MODS_DIR, BASE_MOD, VERSION_DIR, "media", "lua", "shared", CORE, "Namespace.lua")
    if not os.path.isfile(path):
        raise SystemExit("找不到公共层入口：%s" % path)
    match = re.search(r"^Core\.API\s*=\s*(\d+)", read(path), re.M)
    if not match:
        raise SystemExit("Namespace.lua 里找不到 Core.API 声明")
    return int(match.group(1))


def check_base_isolation(problems, verbose):
    """A. 公共层里不得出现任何口味的身份字面量。"""
    tokens = {}
    for name, profile in discover_flavours().items():
        spec = parse_lua_spec(read(profile))
        values = [name, spec.get("module", "")] + [spec.get(k, "") for k in
                  ("tag", "sandboxTable", "textPrefix", "playerPrefix", "flowItem",
                   "economyGlobal", "economyServerGlobal", "economyModId", "economyName", "currencyName")]
        info = os.path.join(MODS_DIR, name, VERSION_DIR, "mod.info")
        if os.path.isfile(info):
            text = read(info)
            values += re.findall(r"(\d{9,10})", text)          # 工坊 id
        for value in values:
            if isinstance(value, str) and len(value) >= 3:
                tokens.setdefault(value, set()).add(name)
    # "橙子社区经济" 这类显示名可能只以子串形式出现在注释里：再补一层中文片段
    for value in list(tokens):
        if re.search(r"[\u4e00-\u9fff]", value):
            for piece in re.findall(r"[\u4e00-\u9fff]{2,}", value):
                tokens.setdefault(piece, set()).add(sorted(tokens[value])[0])

    base_root = os.path.join(MODS_DIR, BASE_MOD)
    leaks = 0
    for path in walk_text_files(base_root):
        rel = os.path.relpath(path, base_root)
        for number, line in enumerate(read(path).splitlines(), start=1):
            scanned = line
            for own in BASE_OWN_NAMES:
                scanned = scanned.replace(own, "\x00")
            if rel.endswith("mod.info"):
                # mod.info 只有 id/require/loadModAfter 是"身份字段"；name/description 是给玩家看的
                # 说明文案，提到口味名是正常的（也是必要的）。所以这里只扫身份字段。
                key = line.partition("=")[0].strip()
                if key not in ("id", "require", "loadModAfter", "loadModBefore"):
                    continue
            for token, owners in sorted(tokens.items()):
                if token in scanned:
                    leaks += 1
                    problems.append("公共层身份泄漏：%s:%d 出现 %r（属于口味 %s）"
                                    % (rel, number, token, "/".join(sorted(owners))))
    if verbose:
        print("  扫描身份标记 %d 个，泄漏 %d 处" % (len(tokens), leaks))
    return leaks


def check_structure(problems):
    """公共层的结构约束：自己不该有沙盒表、翻译表、或依赖某个口味。"""
    base_version = os.path.join(MODS_DIR, BASE_MOD, VERSION_DIR)
    for rel, why in (
        ("media/sandbox-options.txt", "沙盒选项表是**每个口味一套**，放公共层会让两边抢同一张表"),
        ("media/lua/shared/Translate", "翻译键前缀是每个口味自己的，放公共层会互相盖"),
    ):
        if os.path.exists(os.path.join(base_version, rel)):
            problems.append("公共层不该有 %s（%s）" % (rel, why))

    info_path = os.path.join(base_version, "mod.info")
    if not os.path.isfile(info_path):
        problems.append("公共层缺 mod.info")
        return
    fields = parse_mod_info(read(info_path))
    if fields.get("id") != BASE_MOD:
        problems.append("公共层 mod.info 的 id 应为 %s，实际 %r" % (BASE_MOD, fields.get("id")))
    if "require" in fields:
        problems.append("公共层不该有 require=（它是依赖链的根，不能反过来依赖口味）：%r"
                        % fields["require"])
    if not fields.get("modversion"):
        problems.append("公共层 mod.info 缺 modversion")


def check_flavours(problems, api, verbose):
    """B. 每个口味：coreApi 一致、module 与 mod.info 的 id 相同、依赖公共层、字段两两不撞车。"""
    flavours = discover_flavours()
    if not flavours:
        problems.append("没找到任何口味（%s 下应有 media/lua/shared/<名字>/Profile.lua）" % MODS_DIR)
        return
    seen = {}
    for name, profile in sorted(flavours.items()):
        spec = parse_lua_spec(read(profile))
        info_path = os.path.join(MODS_DIR, name, VERSION_DIR, "mod.info")
        fields = parse_mod_info(read(info_path)) if os.path.isfile(info_path) else {}

        if spec.get("coreApi") != api:
            problems.append("%s: Profile 的 coreApi=%r，公共层 Core.API=%d（必须相等）"
                            % (name, spec.get("coreApi"), api))
        if spec.get("module") != name:
            problems.append("%s: Profile 的 module=%r 与目录/mod.info 的 id 不一致"
                            % (name, spec.get("module")))
        if fields.get("id") != name:
            problems.append("%s: mod.info 的 id=%r 与目录名不一致" % (name, fields.get("id")))
        required = [part.strip().lstrip("\\") for part in fields.get("require", "").split(",") if part.strip()]
        if BASE_MOD not in required:
            problems.append("%s: mod.info 的 require= 里没有 %s（否则玩家不会自动带上公共层）"
                            % (name, BASE_MOD))
        if fields.get("modversion") != spec.get("version"):
            problems.append("%s: mod.info 的 modversion=%r 与 Profile 的 version=%r 不一致"
                            % (name, fields.get("modversion"), spec.get("version")))

        for key in UNIQUE_KEYS:
            value = spec.get(key)
            if value in (None, ""):
                problems.append("%s: Profile 缺 %s" % (name, key))
                continue
            if (key, value) in seen:
                problems.append("%s 与 %s 的 %s 撞车：%r" % (name, seen[(key, value)], key, value))
            else:
                seen[(key, value)] = name

        sibling = spec.get("sibling")
        if sibling is not None:
            if sibling == spec.get("module"):
                problems.append("%s: sibling 指向自己（%r）—— 会让 takenBySibling 读自己的存档，"
                                "把「重招自己人」误判成「被别人雇走」" % (name, sibling))
            elif sibling not in flavours:
                problems.append("%s: sibling=%r 不是本物品里的另一个口味" % (name, sibling))
        if verbose:
            print("  %-22s module=%-22s coreApi=%s sibling=%s"
                  % (name, spec.get("module"), spec.get("coreApi"), spec.get("sibling")))


def main():
    parser = argparse.ArgumentParser(description="公共层隔离守卫")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    problems = []
    api = core_api()
    print("== 公共层隔离检查（Core.API = %d）==" % api)
    check_structure(problems)
    check_base_isolation(problems, args.verbose)
    check_flavours(problems, api, args.verbose)

    if problems:
        print("\n%d 处问题：" % len(problems))
        for line in problems:
            print("  - " + line)
        return 1
    print("\n公共层零身份 + %d 个口味互不撞车：OK" % len(discover_flavours()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
