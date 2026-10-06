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
import json
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
    "module", "version", "coreApi", "tag", "sandboxTable",
    "textPrefix", "playerPrefix", "flowItem", "money",
    "economyGlobal", "economyServerGlobal", "economyModId", "economyName", "currencyName",
)

# 跨口味必须唯一的字段（撞车 = 两边写同一张表 / 抢同一套选项 / 互相盖翻译键）
UNIQUE_KEYS = ("module", "tag", "sandboxTable", "textPrefix", "playerPrefix", "flowItem")

# 公共层里**允许**出现的"口味 spec 值"：
#   currencyName 是"钱叫什么"的显示词（钞票 / 金币 / 社区货币）。它不是身份 —— 公共层的
#   Cash.lua 必须能说清楚"原版钞票物品"这件事，而"钞票"正是原版口味的 currencyName。
#   真正要防的身份是 module / tag / 表名 / 翻译前缀 / 上游全局名 / 上游 mod id：任何一个
#   出现在公共层，都意味着某个口味会去写另一个口味的存档、余额或翻译键。
#   所以下面的取值表里刻意**不含** currencyName。


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
    """从 Profile.lua 的 spec 表里取出 `key = <字面量>`（字符串或数字）。

    sibling 有两种写法（见公共层 Namespace.lua）：两个口味时是字符串，三个以上口味时是
    字符串表。两种都要能解析出来，否则"sibling 不能指向自己"这条断言会在最需要它的时候
    静默失效（历史上真的漏过一次）。
    """
    spec = {}
    for key in PROFILE_KEYS:
        match = re.search(r'^\s*%s\s*=\s*("(?:[^"\\]|\\.)*"|\d+)\s*,?\s*$' % key, text, re.M)
        if match:
            raw = match.group(1)
            spec[key] = raw[1:-1] if raw.startswith('"') else int(raw)
    table_match = re.search(r"^\s*sibling\s*=\s*\{(.*?)\}\s*,?\s*$", text, re.M | re.S)
    if table_match:
        spec["sibling"] = re.findall(r'"((?:[^"\\]|\\.)*)"', table_match.group(1))
    else:
        match = re.search(r'^\s*sibling\s*=\s*("(?:[^"\\]|\\.)*")\s*,?\s*$', text, re.M)
        if match:
            spec["sibling"] = match.group(1)[1:-1]
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


def money_providers():
    """公共层支持哪些收钱方式：Namespace.lua 的 Core.MONEY_PROVIDERS 表的键。"""
    path = os.path.join(MODS_DIR, BASE_MOD, VERSION_DIR, "media", "lua", "shared", CORE, "Namespace.lua")
    match = re.search(r"Core\.MONEY_PROVIDERS\s*=\s*\{(.*?)\}", read(path), re.S)
    if not match:
        raise SystemExit("Namespace.lua 里找不到 Core.MONEY_PROVIDERS 声明")
    return set(re.findall(r"^\s*(\w+)\s*=", match.group(1), re.M))


def check_base_isolation(problems, verbose):
    """A. 公共层里不得出现任何口味的身份字面量。"""
    tokens = {}
    for name, profile in discover_flavours().items():
        spec = parse_lua_spec(read(profile))
        values = [name, spec.get("module", "")] + [spec.get(k, "") for k in
                  ("tag", "sandboxTable", "textPrefix", "playerPrefix", "flowItem",
                   "economyGlobal", "economyServerGlobal", "economyModId", "economyName")]
        if spec.get("sibling"):
            values += spec["sibling"] if isinstance(spec["sibling"], list) else [spec["sibling"]]
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


def check_sandbox(problems, verbose):
    """C. 每个口味的沙盒选项：`translation=` / `_tooltip=` / `page=` / enum 各档都要有翻译键。

    这条守的是一类很显眼的线上缺陷：选项界面里显示成 `Bin2NPCExtensionVanilla.SignPrice`
    这种生键名（沙盒选项不会因为我们少写一条翻译就报错，只会难看）。
    """
    for name, _ in sorted(discover_flavours().items()):
        version = os.path.join(MODS_DIR, name, VERSION_DIR)
        options_path = os.path.join(version, "media", "sandbox-options.txt")
        if not os.path.isfile(options_path):
            problems.append("%s: 缺 media/sandbox-options.txt" % name)
            continue
        text = read(options_path)
        keys = set()
        for pattern in (r"^\s*translation\s*=\s*([\w.]+)\s*,", r"^\s*_tooltip\s*=\s*([\w.]+)\s*,",
                        r"^\s*page\s*=\s*([\w.]+)\s*,"):
            keys.update("Sandbox_" + value for value in re.findall(pattern, text, re.M))
        enum_count = re.search(r"numValues\s*=\s*(\d+)", text)
        for value in re.findall(r"^\s*valueTranslation\s*=\s*([\w.]+)\s*,", text, re.M):
            for index in range(1, int(enum_count.group(1)) + 1 if enum_count else 4):
                keys.add("Sandbox_%s_option%d" % (value, index))

        for language in ("CN", "EN"):
            json_path = os.path.join(version, "media", "lua", "shared", "Translate",
                                     language, "Sandbox.json")
            if not os.path.isfile(json_path):
                problems.append("%s: 缺 Translate/%s/Sandbox.json" % (name, language))
                continue
            try:
                data = json.loads(read(json_path))
            except ValueError as error:
                problems.append("%s: Translate/%s/Sandbox.json 不是合法 JSON（%s）"
                                % (name, language, error))
                continue
            missing = sorted(key for key in keys if key not in data)
            if missing:
                problems.append("%s: %s 的 Sandbox.json 缺 %d 个键（沙盒界面会显示生键名）：%s"
                                % (name, language, len(missing), ", ".join(missing[:6])))
        if verbose:
            print("  %-26s 沙盒选项翻译键 %d 个（CN/EN 都有）" % (name, len(keys)))


def check_flavours(problems, api, providers, verbose):
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
        listed = []
        if sibling is not None:
            listed = sibling if isinstance(sibling, list) else [sibling]
            for one in listed:
                if one == spec.get("module"):
                    problems.append("%s: sibling 指向自己（%r）—— 会让 takenBySibling 读自己的存档，"
                                    "把「重招自己人」误判成「被别人雇走」" % (name, one))
                elif one not in flavours:
                    problems.append("%s: sibling=%r 不是本物品里的另一个口味" % (name, one))
        # 多个口味时，"只写一个兄弟"会留下一个可以被两边同时雇走的漏洞：
        # 同一个 A-Life NPC 只能属于一个人，所以每个口味必须列全其它口味。
        missing = sorted(other for other in flavours if other != name and other not in listed)
        if missing and len(flavours) > 1:
            problems.append("%s: sibling 没列全其它口味，漏了 %s —— 同一个 NPC 会被两边同时雇走"
                            % (name, ", ".join(missing)))
        if spec.get("money") not in (None,) and spec.get("money") not in providers:
            problems.append("%s: Profile 的 money=%r 不是公共层支持的收钱方式（%s）"
                            % (name, spec.get("money"), ", ".join(sorted(providers))))
        if verbose:
            shown = sibling
            if isinstance(shown, list):
                shown = "{" + ", ".join(shown) + "}"
            print("  %-26s module=%-26s coreApi=%s money=%-8s sibling=%s"
                  % (name, spec.get("module"), spec.get("coreApi"),
                     spec.get("money", "upstream"), shown))


def main():
    parser = argparse.ArgumentParser(description="公共层隔离守卫")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    problems = []
    api = core_api()
    providers = money_providers()
    print("== 公共层隔离检查（Core.API = %d，收钱方式：%s）==" % (api, ", ".join(sorted(providers))))
    check_structure(problems)
    check_base_isolation(problems, args.verbose)
    check_flavours(problems, api, providers, args.verbose)
    check_sandbox(problems, args.verbose)

    if problems:
        print("\n%d 处问题：" % len(problems))
        for line in problems:
            print("  - " + line)
        return 1
    print("\n公共层零身份 + %d 个口味互不撞车：OK" % len(discover_flavours()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
