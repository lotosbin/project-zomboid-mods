#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A2S（Source 查询协议）只读探针：不碰 RCON、不需要任何凭据。

为什么另外有它：RCON 是本服唯一能读配置的通路，但 2026-10-16 晚上单条命令要 34~49 秒
（10-15 整轮 5 条命令才约 9 秒），而且它**一次只服务一个连接**——我并发探测把它卡死过一次。
A2S 走 UDP、无状态、亚秒级返回，所以它适合干两件事：

  1) **快速发现「有人了」**：采样循环要等一整轮 RCON 跑完（1~2 分钟）才会结束并叫人，
     而渠道要在**同一刻**做 A2S 交叉验证——越早发现越值钱。
  2) RCON 卡住时，仍然知道服务器在不在 Steam 视野里、以及有几个人。

它**不是「多一个样本」**：同刻同机的 A2S 与 RCON 只算**仪器交叉验证**，不算多一个时间点。
它**也不是身份证据**：A2S_PLAYER 给的是账号名，但同一个账号可以有多个角色（README §3.4）。

用法：
    python3 scripts/a2s_query.py info                 # 名字/地图/人数，打印可读信息
    python3 scripts/a2s_query.py info --csv X         # 追加一行到采样表（source=a2s）
    python3 scripts/a2s_query.py info --alert-on-players   # 有人则退出码 3
    python3 scripts/a2s_query.py players              # 账号名列表（分数/时长一并打印）
    python3 scripts/a2s_query.py watch 60 20          # 每 20 秒查一次、最多 60 次，有人就停

退出码：0 = 正常；3 = 有人在线（仅在 --alert-on-players 或 watch 下）；1 = 查不通。

**报文格式的坑（我踩过，记在这里免得再踩）**：INFO 请求被问 challenge 时，
challenge 必须接在**结尾的 \\x00 之后**（`TSource Engine Query\\x00` + 4 字节 challenge）。
我早先按 `TSource Engine Query` + challenge 发（把 \\x00 换成了 challenge），服务器一律不回，
于是我一度在记录里写下「本服 A2S 查不出东西」——**错的，是我自己的报文错，不是服务器**。
"""

import argparse
import csv
import os
import socket
import struct
import sys
import time

HOST_DEFAULT = "110.42.14.5"
PORT_DEFAULT = 21217  # 游戏端口；RCON 在 21523，是另一条通路

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_DEFAULT = os.path.join(REPO, "docs", "server-ops", "activity-samples.csv")


class A2SError(Exception):
    pass


def _udp(payload, host, port, timeout):
    """发一个 UDP 包并等一个应答；超时返回 None。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(payload, (host, port))
        data, _ = s.recvfrom(65535)
        return data
    except socket.timeout:
        return None
    finally:
        s.close()


def _request(payload, host, port, timeout):
    """发请求；若被 challenge，则按正确格式带上 challenge 重发。"""
    data = _udp(payload, host, port, timeout)
    if data is None:
        raise A2SError("超时（服务器没回包）")
    if len(data) >= 5 and data[4:5] == b"A":
        # challenge 接在结尾 \x00 之后 —— 这一步错了我之前一直查不通
        data = _udp(payload + data[5:9], host, port, timeout)
        if data is None:
            raise A2SError("带 challenge 重发后超时")
    return data


def _rd_str(b, i):
    j = b.index(b"\x00", i)
    return b[i:j].decode("utf-8", "replace"), j + 1


def query_info(host, port, timeout=8.0):
    """A2S_INFO：名字/地图/人数/版本。返回 dict。"""
    data = _request(b"\xFF\xFF\xFF\xFFTSource Engine Query\x00", host, port, timeout)
    if not (len(data) >= 5 and data[4:5] == b"I"):
        raise A2SError("不是 I 应答：" + data[:48].hex())

    i = 5
    protocol = data[i]
    i += 1
    name, i = _rd_str(data, i)
    mapname, i = _rd_str(data, i)
    folder, i = _rd_str(data, i)
    game, i = _rd_str(data, i)
    appid = struct.unpack_from("<H", data, i)[0]
    i += 2
    players = data[i]
    i += 1
    max_players = data[i]
    i += 1
    bots = data[i]
    i += 1
    server_type = chr(data[i])
    i += 1
    environment = chr(data[i])
    i += 1
    visibility = data[i]
    i += 1
    vac = data[i]
    i += 1
    version, i = _rd_str(data, i)

    # EDF（extra data flag）：可选字段，按位决定后面还有什么。留原始十六进制一起交出，
    # 这样"我解析得对不对"是可核查的，而不是靠我说它对。
    edf = data[i] if i < len(data) else 0
    i += 1 if i < len(data) else 0
    port = steamid = keywords = gameid = spectator = None
    try:
        if edf & 0x80:
            port = struct.unpack_from("<H", data, i)[0]
            i += 2
        if edf & 0x10:
            steamid = struct.unpack_from("<Q", data, i)[0]
            i += 8
        if edf & 0x40:
            spec_port = struct.unpack_from("<H", data, i)[0]
            i += 2
            spectator = _rd_str(data, i)[0]
            i = data.index(b"\x00", i) + 1
        if edf & 0x20:
            keywords, i = _rd_str(data, i)
        if edf & 0x01:
            gameid = struct.unpack_from("<Q", data, i)[0]
            i += 8
    except (struct.error, ValueError, IndexError) as e:
        # 解析不全就说解析不全，别猜
        keywords = keywords or "<EDF 解析未走完: %s>" % e

    return {
        "protocol": protocol,
        "edf": edf,
        "a2s_port": port,
        "a2s_steamid": steamid,
        "a2s_keywords": keywords,
        "a2s_gameid": gameid,
        "a2s_spectator": spectator,
        "name": name,
        "map": mapname,
        "folder": folder,
        "game": game,
        "appid": appid,
        "players": players,
        "max_players": max_players,
        "bots": bots,
        "server_type": server_type,
        "environment": environment,
        "visibility": visibility,
        "vac": vac,
        "version": version,
        "trailing": data[i:].hex(),
        "raw_len": len(data),
    }


def query_players(host, port, timeout=8.0):
    """A2S_PLAYER：账号名/分数/时长。返回 (count, [ {index,name,score,duration} ], 剩余字节)。

    challenge 的走法和 INFO **不一样**：PLAYER 要把 challenge 放在 `\\xff\\xff\\xff\\xffU` 之后
    （即 `...U` + 4 字节 challenge），不能像 INFO 那样把中间的 `\\xff\\xff\\xff\\xff` 留着。
    我第一版照 INFO 的写法发，服务器就一直回**新的** challenge，永远等不到 D 应答。

    注意：本服**没有**多余的字段，标准格式即可（同事早先以为有条目后的 4 字节 duration
    被塞进了别处，后来确认那是他自己的解析器 bug）。解析完的剩余字节原样带出来，
    这样"格式对不对"是可核查的，而不是靠我说它对。
    """
    data = None
    payload = b"\xFF\xFF\xFF\xFFU\xFF\xFF\xFF\xFF"
    for _ in range(3):
        r = _udp(payload, host, port, timeout)
        if r is None:
            raise A2SError("超时（服务器没回包）")
        if len(r) >= 5 and r[4:5] == b"D":
            data = r
            break
        if len(r) >= 9 and r[4:5] == b"A":
            payload = b"\xFF\xFF\xFF\xFFU" + r[5:9]
            continue
        raise A2SError("不是 D 应答：" + r[:48].hex())
    if data is None:
        raise A2SError("连发 3 次都被挡回（始终不是 D 应答）")

    count = data[5]
    i = 6
    out = []
    for _ in range(count):
        index = data[i]
        i += 1
        pname, i = _rd_str(data, i)
        score = struct.unpack_from("<i", data, i)[0]
        i += 4
        duration = struct.unpack_from("<f", data, i)[0]
        i += 4
        out.append({"index": index, "name": pname, "score": score, "duration": duration})
    return count, out, data[i:].hex()


def append_csv(path, players, max_players, names):
    """追加一行原始读数。列义与 RCON 采样器一致，用 source 列区分来源。

    names 留原始字节（这里已是 decode 后的字符串；RCON 侧才需要留原始字节，
    因为它可能返回非 UTF-8）。A2S 的 INFO 不带名字，所以 names 为空。
    """
    new = not os.path.exists(path)
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")  # 显式 LF，否则留下假 diff
        if new:
            w.writerow(["timestamp", "host_port", "players", "max_players", "names", "source"])
        w.writerow(
            [
                time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                f"{HOST_DEFAULT}:{PORT_DEFAULT}",
                players,
                max_players,
                ";".join(names),
                "a2s",
            ]
        )


def main():
    ap = argparse.ArgumentParser(description="A2S 只读探针（不碰 RCON）")
    ap.add_argument("mode", choices=["info", "players", "watch"])
    ap.add_argument("times", nargs="?", type=int, default=0, help="watch：查多少次")
    ap.add_argument("interval", nargs="?", type=int, default=20, help="watch：间隔秒")
    ap.add_argument("--host", default=HOST_DEFAULT)
    ap.add_argument("--port", type=int, default=PORT_DEFAULT)
    ap.add_argument("--timeout", type=float, default=8.0)
    ap.add_argument("--csv", default=None, help="追加一行读数到该表（watch 下默认开启）")
    ap.add_argument("--alert-on-players", action="store_true", help="有人则退出码 3")
    args = ap.parse_args()

    if args.mode == "watch":
        times = args.times or 60
        csv_path = args.csv or CSV_DEFAULT
        print(
            "[a2s] start %s  times=%d interval=%ds  csv=%s"
            % (time.strftime("%F %T"), times, args.interval, csv_path)
        )
        fails = 0
        for n in range(1, times + 1):
            t0 = time.time()
            try:
                info = query_info(args.host, args.port, args.timeout)
            except A2SError as e:
                fails += 1
                # 失败就是"缺一个点"，与"读到 0"分开写
                print("[%d/%d] A2S_FAIL %s" % (n, times, e))
            else:
                names = []
                if info["players"] > 0:
                    try:
                        _, plist, _ = query_players(args.host, args.port, args.timeout)
                        names = [p["name"] for p in plist]
                    except A2SError as e:
                        print("[%d/%d] A2S_PLAYER_FAIL %s" % (n, times, e))
                line = "%s players=%d/%d name=%r" % (
                    time.strftime("%F %T"),
                    info["players"],
                    info["max_players"],
                    info["name"],
                )
                if names:
                    line += " names=%r" % (names,)
                print("[%d/%d] %s" % (n, times, line))
                append_csv(csv_path, info["players"], info["max_players"], names)
                if info["players"] > 0:
                    print("[a2s] *** PLAYERS PRESENT (%d) — 立刻报 ***" % info["players"])
                    print("[a2s] 停于 %s（第 %d/%d 次之后）" % (time.strftime("%F %T"), n, times))
                    return 3
            if n < times:
                sleep = args.interval - (time.time() - t0)
                if sleep > 0:
                    time.sleep(sleep)
        print("[a2s] done %s  fail=%d/%d" % (time.strftime("%F %T"), fails, times))
        return 0

    try:
        if args.mode == "info":
            info = query_info(args.host, args.port, args.timeout)
            for k in (
                "name",
                "map",
                "folder",
                "game",
                "appid",
                "players",
                "max_players",
                "bots",
                "visibility",
                "vac",
                "version",
                "protocol",
                "edf",
                "a2s_port",
                "a2s_steamid",
                "a2s_keywords",
                "a2s_gameid",
                "raw_len",
                "trailing",
            ):
                print("%-12s = %r" % (k, info[k]))
            if args.csv:
                append_csv(args.csv, info["players"], info["max_players"], [])
            if args.alert_on_players and info["players"] > 0:
                print("ALERT_PLAYERS_PRESENT count=%d source=a2s" % info["players"])
                return 3
            return 0

        count, plist, trailing = query_players(args.host, args.port, args.timeout)
        print("count = %d" % count)
        for p in plist:
            print(
                "  #%d name=%r score=%d duration=%.1fs"
                % (p["index"], p["name"], p["score"], p["duration"])
            )
        print("trailing_bytes = %r" % trailing)  # 空 = 格式吃干净了，可核查
        if args.csv:
            append_csv(args.csv, count, 0, [p["name"] for p in plist])
        if args.alert_on_players and count > 0:
            print("ALERT_PLAYERS_PRESENT count=%d source=a2s" % count)
            return 3
        return 0
    except A2SError as e:
        print("A2S 查不通：%s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
