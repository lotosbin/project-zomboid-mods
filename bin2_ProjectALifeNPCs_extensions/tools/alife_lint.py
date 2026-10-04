#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A-Life `.alife` 数据文件校验器。

用途：写 A-Life 扩展的 provider 数据（阵营/NPC 档案）时，在进游戏前先本地校验格式。
规则全部来自实测的核心模组实现（Project A-Life v1.3.15）：
  - 头：`@alife-records <version>`，版本必须 <= 1，否则 record_version
  - 记录头：`<kind> <id>`，kind ∈ {faction, member}，id 匹配 ^[%w_%-%.]+$
  - 字段行：固定两空格缩进 + `<group>.<field> <value>`
  - 记录尾：裸 `end`
  - 注释：以 `--` 开头；空行忽略
  - 跨记录：member 的 `general.faction` 必须能在 faction 表中找到，否则 orphanedProfiles
  - 删除语义：`general.deleted true`（不是物理删除）

用法：
    python3 alife_lint.py <file-or-dir> [...]
    python3 alife_lint.py --strict <path>      # 有 warning 也返回非 0
退出码：0 = 通过；1 = 有错误；2 = 用法/读取问题
"""

import argparse
import os
import re
import sys

HEADER_RE = re.compile(r"^@alife-records\s+(\d+)\s*$")
RECORD_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)\s*$")
# 值可省略：`  look.beard` / `  presence.towns` 表示空值（核心数据里有 666 处这种写法）
FIELD_RE = re.compile(r"^  ([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)(?:\s+(.*))?$")
ID_RE = re.compile(r"^[%w_%-%.]+$".replace("%w", "A-Za-z0-9_"))
KINDS = ("faction", "member")
# 已知的必填字段（用"文件侧字段名"，不是内存路径！Codec.schema 会做 who.*→general.* 之类的映射）
#   faction 文件侧 about.title  → 内存 general.name
#   member  文件侧 who.faction / who.title → 内存 general.faction / general.name
# 两种命名都能通过解码器（实测）：
#   A-Life 自带数据用"文件侧名"  who.title / who.faction
#   Aftermath 等扩展用"内存路径名" general.name / general.faction
REQUIRED = {
    "faction": [("about.title", "general.name")],
    "member": [("who.faction", "general.faction"), ("who.title", "general.name")],
}


class Problem:
    def __init__(self, path, line, code, detail):
        self.path, self.line, self.code, self.detail = path, line, code, detail

    def __str__(self):
        loc = f"{self.path}:{self.line}" if self.line else self.path
        return f"{loc}: {self.code}: {self.detail}"


def parse(path, text, errors, warnings, records):
    """逐行解析，返回本文件声明的记录列表。"""
    lines = text.splitlines()
    header_seen = False
    current = None  # {kind, id, line, fields:set}

    for idx, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n\r")
        if line.strip() == "":
            continue
        if line.startswith("--"):
            continue
        if not header_seen:
            m = HEADER_RE.match(line)
            if m:
                version = int(m.group(1))
                if version > 1:
                    errors.append(Problem(path, idx, "record_version",
                                          f"header version {version} > supported 1"))
                header_seen = True
                continue
            errors.append(Problem(path, idx, "bad_line", "missing '@alife-records <version>' header"))
            return records
        if line == "end":
            if current is None:
                errors.append(Problem(path, idx, "stray_end", "'end' without an open record"))
            else:
                records.append(current)
                current = None
            continue
        if not line.startswith(" "):
            m = RECORD_RE.match(line)
            if not m:
                errors.append(Problem(path, idx, "bad_line", f"cannot parse record header: {line!r}"))
                continue
            if current is not None:
                errors.append(Problem(path, current["line"], "unclosed_record",
                                      f"record {current['kind']} {current['id']} not closed before line {idx}"))
                current = None
            kind, rid = m.group(1), m.group(2)
            if kind not in KINDS:
                errors.append(Problem(path, idx, "wrong_kind", f"unsupported kind {kind!r}"))
            if not ID_RE.match(rid):
                errors.append(Problem(path, idx, "bad_line", f"invalid record id {rid!r}"))
            current = {"kind": kind, "id": rid, "line": idx, "fields": set(),
                       "values": {}, "source": path}
            continue
        m = FIELD_RE.match(line)
        if not m:
            if line.startswith("   "):
                errors.append(Problem(path, idx, "bad_line", "indent must be exactly two spaces"))
            else:
                errors.append(Problem(path, idx, "bad_field", f"cannot parse field: {line!r}"))
            continue
        if current is None:
            errors.append(Problem(path, idx, "outside_record", f"field outside any record: {m.group(1)}"))
            continue
        key, value = m.group(1), (m.group(2) or "")
        if key in current["fields"]:
            errors.append(Problem(path, idx, "duplicate_field", f"{key} declared twice in {current['id']}"))
        current["fields"].add(key)
        current["values"][key] = value

    if current is not None:
        errors.append(Problem(path, current["line"], "unclosed_record",
                              f"record {current['kind']} {current['id']} missing 'end' at EOF"))
    if not header_seen:
        errors.append(Problem(path, 0, "bad_line", "empty file or missing header"))
    return records


def main():
    ap = argparse.ArgumentParser(description="Validate Project A-Life .alife data files")
    ap.add_argument("paths", nargs="+", help="files or directories")
    ap.add_argument("--strict", action="store_true", help="treat warnings as errors")
    ap.add_argument("--quiet", action="store_true", help="only print the summary")
    ap.add_argument("--max-print", type=int, default=20, help="max problems printed per class")
    ap.add_argument("--require-identity", action="store_true",
                    help="treat member records without who.faction/who.title as errors "
                         "(use when authoring an upsert file)")
    args = ap.parse_args()

    targets = []
    for p in args.paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                targets += [os.path.join(root, f) for f in files if f.endswith(".alife")]
        elif os.path.isfile(p):
            targets.append(p)
        else:
            print(f"[ERROR] not found: {p}")
            return 2
    if not targets:
        print("[ERROR] no .alife files found")
        return 2

    errors, warnings, records = [], [], []
    file_has_factions = {}
    for path in sorted(targets):
        try:
            with open(path, encoding="utf-8-sig") as fh:
                text = fh.read()
        except OSError as exc:
            print(f"[ERROR] cannot read {path}: {exc}")
            return 2
        pr = parse(path, text, errors, warnings, records)
        file_has_factions[path] = any(r["kind"] == "faction" for r in pr)
        if not args.quiet:
            kinds = {}
            for r in pr:
                kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
            stat = " ".join(f"{k}={v}" for k, v in sorted(kinds.items())) or "empty"
            print(f"[OK] {path}: {stat}")

    # 跨记录校验
    #   - 含 faction 记录的文件 = core/upsert，必填字段缺失算 warning
    #   - 纯 member 文件 = provider/overlay（只覆盖部分字段），缺失属正常，降级为 info
    factions = {r["id"] for r in records if r["kind"] == "faction"}
    orphaned, infos = 0, []
    for r in records:
        if r["kind"] != "member":
            continue
        for alternatives in REQUIRED["member"]:
            if any(k in r["fields"] for k in alternatives):
                continue
            msg = f"member {r['id']} missing " + " / ".join(alternatives)
            # 默认不把"缺身份字段"当错误：A-Life 自带的 merge provider 与 Aftermath 的
            # overlay 记录本来就只声明部分字段（如 outfitA.*）。作者模式才强制。
            if args.require_identity:
                warnings.append(Problem(r["source"], r["line"], "bad_field", msg))
            else:
                infos.append(Problem(r["source"], r["line"], "overlay_or_merge", msg))
        target = r["values"].get("who.faction") or r["values"].get("general.faction")
        if target and target not in factions:
            orphaned += 1
            warnings.append(Problem(r["source"], r["line"], "orphaned",
                                    f"member {r['id']} references unknown faction {target}"))

    print("")
    print(f"files={len(targets)} records={len(records)} "
          f"factions={sum(1 for r in records if r['kind'] == 'faction')} "
          f"members={sum(1 for r in records if r['kind'] == 'member')} "
          f"errors={len(errors)} warnings={len(warnings)} orphaned={orphaned} "
          f"overlays_ok={len(infos)}")
    for p in errors[:args.max_print]:
        print(f"[ERROR] {p}")
    for p in warnings[:args.max_print]:
        print(f"[WARN ] {p}")
    if len(errors) > args.max_print or len(warnings) > args.max_print:
        print(f"[NOTE ] 输出已截断（--max-print {args.max_print}）")

    if errors or (args.strict and warnings):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
