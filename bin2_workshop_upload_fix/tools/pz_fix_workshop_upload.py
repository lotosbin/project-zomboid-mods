#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
修复 Project Zomboid 在 macOS / Linux 上"上传创意工坊失败"的问题。

症状
----
在游戏内的 Workshop 上传向导（Page7）里点击上传后，日志只显示::

    start update of existing item ID=xxxxxxxxxx
    error requesting Steam to update the item
    finished

Steam 客户端 `logs/workshop_log.txt` 里**只有** "Create new workshop item ... (OK)"，
没有任何 update / 上传记录；创意工坊物品保持 0.000 B。Windows 上同一个模组一切正常。

根因
----
`zombie.core.znet.SteamWorkshopItem.submitUpdate()` 的字节码等价于::

    public boolean submitUpdate() {
        boolean ok = RenderThread.invokeQueryOnRenderContext(this::confirmUpload); // 弹原生确认框
        return ok && SteamWorkshop.instance.SubmitWorkshopItem(this);              // ok 必须 == 1
    }

`confirmUpload` 用 LWJGL 的 `org.lwjgl.util.tinyfd.TinyFileDialogs.tinyfd_messageBox(
title, msg, "okcancel", "warning", 2)`，只有返回值 **== 1** 才算确认。

在 macOS 上 tinyfd 的实现是拼一段 AppleScript 交给 `osascript` 执行：

    set {vButton} to {button returned} of ( display dialog "..." with title "..." with icon caution )
    if vButton is "Yes" then ... else if vButton is "OK" then ... else return 0

`display dialog` 不指定 buttons 时只有一个**本地化**的默认按钮：
中文系统返回 "好"（本机实测）…… 它与脚本里写死的英文
"Yes"/"OK"/"No" 都不相等，于是走到 `else` → **return 0** → tinyfd 返回 0 →
`submitUpdate()` 返回 false → Lua 打出 "error requesting Steam to update the item"，
`SubmitItemUpdate` 从未被调用（所以 Steam 客户端日志里什么都没有，物品一直是空的）。

Windows 上 tinyfd 走 Win32 MessageBox（IDOK/IDCANCEL 是数字，与语言无关）所以正常；
Linux 上 tinyfd 依赖 zenity/kdialog/yad/gxmessage/Xdialog 等外部程序，一旦找不到
（Steam 启动的游戏没有终端、Bazzite 等精简发行版默认不带）就返回 -1，同样 != 1。

修复
----
这个原生确认框在 macOS / Linux 上本来就只有一个"确定"按钮（没有取消），它的返回值
不该成为上传的前置条件。本脚本改写 `SteamWorkshopItem.class` 里 `submitUpdate()`
的 4 个字节，去掉这个判断（确认框仍然会弹，只是不再拦截上传）::

    iload_1; ifeq +28      ->      nop; nop; nop; nop

改动只影响这一个方法。jar 用"整包重写"的方式更新：除目标成员外，所有条目的
名称/时间/压缩方式/属性/顺序都原样保留，重写后 CRC、压缩后长度、data descriptor
全部自洽（`ZipFile` / `ZipInputStream` / `unzip` 都能正常读）；写盘时覆写原路径，
inode 不变，权限与 xattr 都保留。

用法
----
    python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py            # 自动找游戏并修复（会先备份）
    python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --dry-run  # 只检查，不写盘（对 --restore 同样生效）
    python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --verify   # 只检查：0=已修，1=未修，2=未知
    python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --restore  # 还原备份
    python3 bin2_workshop_upload_fix/tools/pz_fix_workshop_upload.py --game-dir "/path/to/Project Zomboid.app"

注意：游戏更新/Steam"验证文件完整性"会覆盖 projectzomboid.jar，重跑本脚本即可。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

# ---------------------------------------------------------------- 常量

MEMBER = "zombie/core/znet/SteamWorkshopItem.class"

# submitUpdate() 里 "istore_1; iload_1; ifeq +N; getstatic; aload_0; invokevirtual;
#                     ifeq +7; iconst_1; goto +4; iconst_0; ireturn" 的字节序列。
# 反编译（javap -c）见 docs/pz-steam-workshop-upload-macos-linux-fix.md。
GATE_RE = re.compile(
    rb"\x3c\x1b\x99..\xb2..\x2a\xb6..\x99\x00\x07\x04\xa7\x00\x04\x03\xac",
    re.S,
)
# 已被本脚本改写后的样子（用于幂等判断）
GATE_PATCHED_RE = re.compile(
    rb"\x3c\x00\x00\x00\x00\xb2..\x2a\xb6..\x99\x00\x07\x04\xa7\x00\x04\x03\xac",
    re.S,
)

BACKUP_SUFFIX = ".pzfix.bak"
INFO_SUFFIX = ".pzfix.json"


# ---------------------------------------------------------------- 定位游戏

def _steam_library_roots() -> list[str]:
    """返回所有 Steam 库根目录（含 steamapps 的父目录）。"""
    roots: list[str] = []
    home = os.path.expanduser("~")
    for candidate in (
        os.path.join(home, "Library/Application Support/Steam"),   # macOS
        os.path.join(home, ".steam/steam"),                        # Linux
        os.path.join(home, ".steam/root"),
        os.path.join(home, ".local/share/Steam"),
        os.path.join(home, ".var/app/com.valvesoftware.Steam/data/Steam"),  # Flatpak
    ):
        if os.path.isdir(candidate):
            roots.append(candidate)

    # libraryfolders.vdf 里登记的其它库
    extra = []
    for root in list(roots):
        vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
        if not os.path.isfile(vdf):
            continue
        try:
            text = open(vdf, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for path in re.findall(r'"path"\s*"([^"]+)"', text):
            path = path.replace("\\\\", "\\")
            if os.path.isdir(path):
                extra.append(path)
    for path in extra:
        if path not in roots:
            roots.append(path)
    return roots


def find_game_java_dirs() -> list[str]:
    """找出所有候选的"含 projectzomboid.jar"的目录。"""
    found: list[str] = []
    for root in _steam_library_roots():
        base = os.path.join(root, "steamapps", "common", "ProjectZomboid")
        for sub in (
            os.path.join("Project Zomboid.app", "Contents", "Java"),  # macOS
            "ProjectZomboid",                                          # 部分 Linux 布局
            ".",                                                       # Linux 标准布局
        ):
            cand = os.path.join(base, sub)
            if os.path.isfile(os.path.join(cand, "projectzomboid.jar")):
                real = os.path.realpath(cand)
                if real not in found:
                    found.append(real)
    return found


def resolve_game_dir(path: str) -> str | None:
    """把用户给的目录（app 包根 / Contents/Java / 游戏根）统一成含 jar 的目录。"""
    for rel in ("", "Contents/Java", "Project Zomboid.app/Contents/Java", "."):
        cand = os.path.join(path, rel) if rel else path
        if os.path.isfile(os.path.join(cand, "projectzomboid.jar")):
            return cand
    return None


# ---------------------------------------------------------------- jar 读写

def read_member(jar: str, member: str) -> bytes:
    with zipfile.ZipFile(jar) as z:
        return z.read(member)


def rewrite_jar_with_member(jar: str, member: str, new_data: bytes) -> dict:
    """
    用整包重写的方式替换 jar 中某个成员的内容。

    除目标成员外，所有条目的名称/时间/压缩方式/属性/顺序都原样保留，因此重写后的
    CRC、压缩后长度和 data descriptor 全部自洽，ZipFile 与 ZipInputStream 都能读。
    写盘时直接覆写原路径（inode 不变 ⇒ 权限与 xattr 保留），并先对临时文件做自检。
    """
    tmp = jar + ".pzfix.tmp"
    n_entries = 0
    n_replaced = 0
    new_info = None
    try:
        with zipfile.ZipFile(jar) as zin, zipfile.ZipFile(tmp, "w", allowZip64=True) as zout:
            for info in zin.infolist():
                is_dir = info.is_dir()
                if info.filename == member:
                    data = new_data
                    n_replaced += 1
                elif is_dir:
                    data = b""
                else:
                    data = zin.read(info)
                zi = zipfile.ZipInfo(info.filename, info.date_time)
                zi.compress_type = info.compress_type if not is_dir else zipfile.ZIP_STORED
                zi.external_attr = info.external_attr
                zi.internal_attr = info.internal_attr
                zi.create_system = info.create_system
                zi.comment = info.comment
                zout.writestr(zi, data, compress_type=zi.compress_type)
                n_entries += 1
        if n_replaced != 1:
            raise RuntimeError("expected exactly 1 member named %s, got %d" % (member, n_replaced))

        # 自检：临时包能打开、CRC 全对、目标成员内容正确
        with zipfile.ZipFile(tmp) as z:
            if z.testzip() is not None:
                raise RuntimeError("rebuilt archive failed CRC check")
            if z.read(member) != new_data:
                raise RuntimeError("rebuilt archive member mismatch")
            new_info = z.getinfo(member)

        # 覆写原文件内容（inode 不变 ⇒ 权限/xattr 保留）
        with open(tmp, "rb") as src, open(jar, "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return {"entries": n_entries, "csize": new_info.compress_size, "usize": new_info.file_size}


# ---------------------------------------------------------------- 补丁本身

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch_member(data: bytes) -> tuple[bytes, str]:
    """返回 (patch 后的字节, 状态)。状态: patched / already / incompatible:<原因>"""
    if GATE_PATCHED_RE.search(data) and not GATE_RE.search(data):
        return data, "already"
    hits = list(GATE_RE.finditer(data))
    if len(hits) != 1:
        return data, "incompatible:%d" % len(hits)
    m = hits[0]
    new = bytearray(data)
    # iload_1(0x1b) + ifeq(0x99 xx xx) -> nop * 4
    if new[m.start() + 1] != 0x1B or new[m.start() + 2] != 0x99:
        return data, "incompatible:pattern"
    new[m.start() + 1:m.start() + 5] = b"\x00\x00\x00\x00"
    return bytes(new), "patched"


def _info_path(jar: str) -> str:
    return jar + INFO_SUFFIX


def _load_info(jar: str) -> dict | None:
    try:
        with open(_info_path(jar), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- 子命令

def cmd_verify(jar: str) -> int:
    _, status = patch_member(read_member(jar, MEMBER))
    if status == "already":
        print("[ok]   already patched : %s" % jar)
        return 0
    if status == "patched":
        print("[todo] not patched     : %s" % jar)
        return 1
    print("[warn] unknown layout  : %s (%s)" % (jar, status))
    return 2


def cmd_restore(jar: str, dry_run: bool = False, force: bool = False) -> int:
    backup = jar + BACKUP_SUFFIX
    if not os.path.isfile(backup):
        print("[skip] no backup       : %s" % backup)
        return 1
    want = (_load_info(jar) or {}).get("original_member_sha256")
    have = sha256(read_member(backup, MEMBER))
    if want and have != want:
        print("[fail] backup hash mismatch (recorded %s, backup %s)"
              % (want[:16], have[:16]), file=sys.stderr)
        if not force:
            print("       备份已被替换/损坏，拒绝还原；确认无误可加 --force", file=sys.stderr)
            return 2
    if dry_run:
        print("[dry ] would restore    : %s" % jar)
        return 0
    with open(backup, "rb") as src, open(jar, "wb") as dst:
        shutil.copyfileobj(src, dst, 1 << 20)
    if sha256(read_member(jar, MEMBER)) != have:
        print("[fail] restore verification failed", file=sys.stderr)
        return 3
    print("[ok]   restored         : %s" % jar)
    return 0


def cmd_patch(jar: str, dry_run: bool) -> int:
    data = read_member(jar, MEMBER)
    new, status = patch_member(data)
    if status == "already":
        print("[ok]   already patched : %s" % jar)
        return 0
    if status.startswith("incompatible"):
        print("[fail] pattern not found exactly once (%s) - 游戏版本可能已变化，"
              "请先看 bin2_workshop_upload_fix/docs/pz-steam-workshop-upload-macos-linux-fix.md" % status, file=sys.stderr)
        return 2

    backup = jar + BACKUP_SUFFIX
    info = _load_info(jar)
    if os.path.isfile(backup):
        # 备份必须与当初记录的"原始成员"一致，否则它已被替换，不能继续用作还原点
        if info and sha256(read_member(backup, MEMBER)) != info.get("original_member_sha256"):
            print("[fail] existing backup %s does not match its metadata, 拒绝覆盖" % backup,
                  file=sys.stderr)
            return 2
        print("[info] backup exists   : %s" % backup)
    print("[info] target          : %s" % jar)
    print("[info] member          : %s" % MEMBER)
    print("[info] original sha256 : %s" % sha256(data)[:32])
    print("[info] patched  sha256 : %s" % sha256(new)[:32])
    if dry_run:
        print("[dry ] would patch submitUpdate(): iload_1; ifeq -> nop x4 (整包重写 jar)")
        return 0

    if not os.path.isfile(backup):
        with open(jar, "rb") as src, open(backup, "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
        with open(_info_path(jar), "w", encoding="utf-8") as f:
            json.dump({"original_member_sha256": sha256(data), "member": MEMBER}, f, indent=2)
        print("[ok]   backup          : %s" % backup)

    stat = rewrite_jar_with_member(jar, MEMBER, new)
    print("[info] rebuilt jar     : entries=%d, member csize=%d usize=%d"
          % (stat["entries"], stat["csize"], stat["usize"]))

    # 回读自检
    check, status2 = patch_member(read_member(jar, MEMBER))
    if status2 != "already" or check != new:
        print("[fail] verification failed, restoring backup", file=sys.stderr)
        cmd_restore(jar, force=True)
        return 3
    print("[ok]   patched + verified")
    print("")
    print("说明：确认框仍会弹出，但不再阻止上传。开着游戏时请重启游戏后再上传。")
    print("还原：python3 %s --restore" % os.path.basename(__file__))
    return 0


# ---------------------------------------------------------------- 入口

def _collect_jars(game_dir: str | None) -> list[str] | None:
    if game_dir:
        resolved = resolve_game_dir(game_dir)
        if resolved is None:
            print("[fail] %s 下没有 projectzomboid.jar" % game_dir, file=sys.stderr)
            return None
        return [os.path.join(resolved, "projectzomboid.jar")]
    jars = [os.path.join(d, "projectzomboid.jar") for d in find_game_java_dirs()]
    jars = [j for j in jars if os.path.isfile(j)]
    if not jars:
        print("[fail] 没找到 projectzomboid.jar，请用 --game-dir 指定 Contents/Java", file=sys.stderr)
        return None
    return jars


def main() -> int:
    ap = argparse.ArgumentParser(
        description="修复 PZ 在 macOS/Linux 上无法上传创意工坊的问题")
    ap.add_argument("--game-dir", help="游戏目录（app 包根 / Contents/Java / Linux 游戏根目录，默认自动查找）")
    ap.add_argument("--dry-run", action="store_true", help="只检查，不写盘（对 --restore 同样生效）")
    ap.add_argument("--force", action="store_true", help="--restore 时忽略备份哈希不一致")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="只报告当前状态（0=已修，1=未修，2=未知）")
    mode.add_argument("--restore", action="store_true", help="从备份还原")
    args = ap.parse_args()

    if sys.platform.startswith("win"):
        print("Windows 上 tinyfd 用 Win32 MessageBox，不存在这个问题，无需修复。")
        return 0

    jars = _collect_jars(args.game_dir)
    if jars is None:
        return 1

    rc = 0
    for jar in jars:
        if args.restore:
            rc = max(rc, cmd_restore(jar, dry_run=args.dry_run, force=args.force))
        elif args.verify:
            rc = max(rc, cmd_verify(jar))
        else:
            rc = max(rc, cmd_patch(jar, args.dry_run))
    return rc


if __name__ == "__main__":
    sys.exit(main())
