#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读查询 Project Zomboid 线上服务器（Source RCON）。

用途
----
不启动游戏客户端、不依赖 A2S（本机 A2S 探针不可靠），直接从本机读线上真实值：
在线人数、整份服务器选项、命令表。

安全
----
**只允许只读命令**（`players` / `help` / `showoptions`）。写操作
（servermsg / save / kickuser / changeoption / quit 等）会被本脚本直接拒绝——
管理边界未定之前不做，见 docs/server-ops/README.md §2。

凭据
----
从本机 `~/Zomboid/Server/呼噜世界41.ini` 读 `RCONPort` / `RCONPassword`。
**脚本本身不含凭据，输出也不回显凭据。**

用法
----
    python3 scripts/pz_rcon.py players
    python3 scripts/pz_rcon.py showoptions | grep -E "PublicName|Mods="
    python3 scripts/pz_rcon.py sample            # 追加一行到活动采样 CSV
    python3 scripts/pz_rcon.py sample --csv /tmp/x.csv
"""

import argparse
import csv
import datetime as dt
import os
import socket
import struct
import sys

DEFAULT_HOST = "110.42.14.5"
DEFAULT_INI = os.path.expanduser("~/Zomboid/Server/呼噜世界41.ini")
DEFAULT_CSV = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "server-ops", "activity-samples.csv",
)

# RCON 包类型（Source RCON）
AUTH = 3
EXECCOMMAND = 2
RESPONSE_VALUE = 0

READONLY = ("players", "help", "showoptions")


def read_credentials(ini_path):
    port = password = None
    with open(ini_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("RCONPort="):
                port = int(line.split("=", 1)[1].strip())
            elif line.startswith("RCONPassword="):
                password = line.split("=", 1)[1].strip()
    if not port or not password:
        sys.exit(f"读不到 RCONPort/RCONPassword：{ini_path}")
    return port, password


def pack(req_id, ptype, body):
    payload = body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<iii", len(payload) + 8, req_id, ptype) + payload


def _recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def read_packet(sock):
    header = _recv_exact(sock, 4)
    if header is None:
        return None
    (size,) = struct.unpack("<i", header)
    data = _recv_exact(sock, size)
    if data is None:
        return None
    return data[8:-2].decode("utf-8", "replace")


def drain(sock, idle=3.0, max_packets=500):
    """读到 idle 秒内没有新包为止。

    坑：`showoptions` 的一条长行会跨 RCON 包分片，所以各包 payload 必须**直接拼接**。
    用 "\\n" 拼会把长行弄断，`Mods`/`WorkshopItems` 会被数成 134/71 这种假数字。
    """
    parts = []
    sock.settimeout(idle)
    for _ in range(max_packets):
        try:
            packet = read_packet(sock)
        except (socket.timeout, OSError):
            break
        if packet is None:
            break
        parts.append(packet)
        sock.settimeout(idle)
    return "".join(parts)


def run_command(host, port, password, command):
    if command.split()[0] not in READONLY:
        sys.exit(f"拒绝：本脚本只允许只读命令 {READONLY}（收到 {command!r}）")

    sock = socket.create_connection((host, port), timeout=10)
    try:
        sock.sendall(pack(1, AUTH, password))
        read_packet(sock)
        drain(sock, idle=0.8)  # 丢掉认证后的尾部包，避免响应错位一拍

        sock.sendall(pack(2, EXECCOMMAND, command))
        return drain(sock)
    finally:
        sock.close()


def parse_players(text):
    """`Players connected (0): ` -> (0, [])"""
    marker = "Players connected ("
    idx = text.find(marker)
    if idx < 0:
        return None, []
    rest = text[idx + len(marker):]
    count = int(rest.split(")", 1)[0])
    names = rest.split("):", 1)[1].strip().rstrip(":").strip()
    return count, [n.strip() for n in names.split(",") if n.strip()]


def main():
    ap = argparse.ArgumentParser(description="只读查询 PZ 服务器（RCON）")
    ap.add_argument("command", help="players | help | showoptions | sample")
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--ini", default=DEFAULT_INI)
    ap.add_argument("--csv", default=DEFAULT_CSV)
    args = ap.parse_args()

    port, password = read_credentials(args.ini)

    if args.command != "sample":
        sys.stdout.write(run_command(args.host, port, password, args.command))
        return

    text = run_command(args.host, port, password, "players")
    count, names = parse_players(text)
    if count is None:
        sys.exit(f"读不出人数，原始输出：{text[:200]!r}")

    options = run_command(args.host, port, password, "showoptions")
    max_players = ""
    for line in options.splitlines():
        if line.startswith("* MaxPlayers="):
            max_players = line.split("=", 1)[1].strip()

    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    new_file = not os.path.exists(args.csv)
    os.makedirs(os.path.dirname(args.csv), exist_ok=True)
    with open(args.csv, "a", newline="", encoding="utf-8") as fh:
        # lineterminator 必须显式给 "\n"：csv.writer 默认写 "\r\n"，而这仓库要 LF，
        # 否则每跑一次采样都会在共享工作树里留下一条"只见行尾"的假 diff。
        writer = csv.writer(fh, lineterminator="\n")
        if new_file:
            writer.writerow(["timestamp", "host_port", "players", "max_players", "names", "source"])
        writer.writerow([now, f"{args.host}:{port}", count, max_players, ";".join(names), "rcon"])
    print(f"{now}  {args.host}:{port}  在线 {count}/{max_players}" + (f"  {names}" if names else ""))


if __name__ == "__main__":
    main()
