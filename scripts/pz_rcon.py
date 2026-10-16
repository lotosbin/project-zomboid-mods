#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读查询 Project Zomboid 线上服务器（Source RCON）。

用途
----
不启动游戏客户端、不依赖 A2S（A2S 会**间歇性整段哑掉**，见下），直接从本机读线上真实值：
在线人数、整份服务器选项、命令表。

与 `scripts/a2s_query.py` 的关系
--------------------------------
那条通路（UDP，免凭据）**能查通**，且它的读数是独立于 RCON 的第二个来源；
但它今晚实测会**几分钟内完全没有应答**，所以**不能拿它兜底告警**——告警仍然只靠本脚本。
（我早先在本文件里写过"本机 A2S 探针不可靠"，那是因为**我自己的报文写错了**
challenge 的位置，不是服务器的毛病，已更正。）

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

原始字节
--------
有人时，除 CSV 那行外另把 `players` 应答的**原始 payload 字节**（hex）追加到
`docs/server-ops/activity-names-raw.log`。原因：名字要拿去和"本人"比对时，
对方要的是**原始字节**而不是解码后的字符串（传输里可能被编成控制字节）。
采样多在无人值守时跑，**解码再落盘就等于把原始字节丢了**——
之后回头补是补不回来的（人可能已经下线），所以必须在采样的那一刻留存。
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
DEFAULT_RAW_LOG = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "server-ops", "activity-names-raw.log",
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
    """返回 payload 的**原始字节**（已剥掉包长/req_id/类型头与结尾的两个 NUL）。

    刻意不解码：解码交给调用方，需要留存原始字节的地方（名字）才能拿到无损的那一份。
    """
    header = _recv_exact(sock, 4)
    if header is None:
        return None
    (size,) = struct.unpack("<i", header)
    data = _recv_exact(sock, size)
    if data is None:
        return None
    return data[8:-2]


def drain(sock, idle=3.0, max_packets=500):
    """读到 idle 秒内没有新包为止，返回拼接后的原始字节。

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
    return b"".join(parts)


def run_command(host, port, password, command):
    """执行只读命令，返回应答的**原始字节**。"""
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
    ap.add_argument("--raw-log", default=DEFAULT_RAW_LOG)
    ap.add_argument(
        "--alert-on-players",
        action="store_true",
        help="采样时若有人在线（含人数>0 但名字读不出），打印 ALERT_PLAYERS_PRESENT 并以退出码 3 结束",
    )
    args = ap.parse_args()

    port, password = read_credentials(args.ini)

    if args.command != "sample":
        sys.stdout.write(run_command(args.host, port, password, args.command).decode("utf-8", "replace"))
        return

    players_raw = run_command(args.host, port, password, "players")
    text = players_raw.decode("utf-8", "replace")
    count, names = parse_players(text)
    if count is None:
        sys.exit(f"读不出人数，原始输出：{text[:200]!r}")

    options = run_command(args.host, port, password, "showoptions").decode("utf-8", "replace")
    max_players = ""
    game_port = ""
    for line in options.splitlines():
        if line.startswith("* MaxPlayers="):
            max_players = line.split("=", 1)[1].strip()
        elif line.startswith("* DefaultPort="):
            game_port = line.split("=", 1)[1].strip()

    # 记的是**游戏端口**（DefaultPort，对外那个 21217），不是 RCON 端口 ——
    # 否则同一个服会因为"走 RCON 还是走 A2S"而在表里变成两个不同的键，
    # 按服务器分组时就把它拆开了。走的哪条通道由 source 列负责说。
    server = f"{args.host}:{game_port or port}"

    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    new_file = not os.path.exists(args.csv)
    os.makedirs(os.path.dirname(args.csv), exist_ok=True)
    with open(args.csv, "a", newline="", encoding="utf-8") as fh:
        # lineterminator 必须显式给 "\n"：csv.writer 默认写 "\r\n"，而这仓库要 LF，
        # 否则每跑一次采样都会在共享工作树里留下一条"只见行尾"的假 diff。
        writer = csv.writer(fh, lineterminator="\n")
        if new_file:
            writer.writerow(["timestamp", "host_port", "players", "max_players", "names", "source"])
        writer.writerow([now, server, count, max_players, ";".join(names), "rcon"])

    # 有人时另存**原始字节**（hex）。CSV 的 names 列是解码后的字符串，已经把
    # 传输层的东西洗掉了（QQ运营 同一个人 10:41 读成 hex c0bb450162696e32、
    # 10:50 读成干净的 62696e32 ⇒ 前 4 字节是传输产物，不是名字的一部分）。
    # 采样无人值守，**解码再落盘就等于把原始字节丢了**，回头补不回来（人可能已下线）。
    if names:
        os.makedirs(os.path.dirname(args.raw_log), exist_ok=True)
        # 末列那份"人看的"文本必须转义：这是 TSV，且 `players` 应答里本来就可能
        # 带 `\n`（多行）或制表符，直接写会让一条记录裂成两条、把后面所有行错位。
        # 权威字段始终是 hex 那列，文本列只是给人读的。
        readable = (
            text.strip()
            .replace("\\", "\\\\")
            .replace("\t", "\\t")
            .replace("\r", "\\r")
            .replace("\n", "\\n")
        )
        with open(args.raw_log, "a", encoding="utf-8") as fh:
            fh.write(
                f"{now}\t{server}\t{count}\t{players_raw.hex()}\t{readable}\n"
            )

    print(f"{now}  {server}  在线 {count}/{max_players}" + (f"  {names}" if names else ""))
    if names:
        print(f"原始字节 hex：{players_raw.hex()}")

    # 「有人了」是要立刻通知渠道的事件（他们的稿子能不能提前发就看这个），
    # 而这一轮采样是跑在**无人值守的后台作业**里的 —— 作业只在**结束时**叫醒我。
    # 所以有人时就用一个独特的退出码**主动结束这轮作业**，让我在采到人的后几秒内被叫醒，
    # 而不是等到 22:00 收尾才看到"20:20 进来过一个人"（那时人早走了，
    # 渠道也没法在同一刻做 A2S 交叉验证——晚一分钟这条证据就废了）。
    # **触发条件含 `count > 0` 而不只是"名字非空"**：恰好是"人数>0 但名字读不出"那一种，
    # 最需要渠道那侧的 A2S 来补（他们的读数是另一条独立通道），所以那种更要立刻叫醒人。
    # 代价：后面没跑的点要等处理完再补一轮，这是刻意的取舍。
    if args.alert_on_players and (names or count > 0):
        print(
            f"ALERT_PLAYERS_PRESENT\t{now}\t{server}\tcount={count}"
            f"\tnames={'/'.join(names) if names else '(读不出)'}"
            f"\traw={players_raw.hex()}"
        )
        sys.exit(3)


if __name__ == "__main__":
    main()
