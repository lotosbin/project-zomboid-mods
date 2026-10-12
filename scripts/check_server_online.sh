#!/usr/bin/env bash
# 检查 Project Zomboid 服务器是否登记在 Steam 主服务器上。
#
# 这是目前唯一一条不需要服务器凭据的外部存活信号（详见 docs/server-ops/README.md）。
# 局限：读的是 Steam 主服务器的登记表，掉线不会立刻反映；不返回在线人数与模组列表。
#
# 用法:
#   scripts/check_server_online.sh                     # 默认 110.42.14.5:21217（云猫咖）
#   scripts/check_server_online.sh <ip>:<port>
#
# 退出码: 0 = 已登记, 1 = 未登记, 2 = 请求失败（网络/接口问题，不代表服务器状态）
set -uo pipefail

ADDR="${1:-110.42.14.5:21217}"
API="https://api.steampowered.com/ISteamApps/GetServersAtAddress/v1/"

# -sS：静默但仍把错误打到 stderr，失败时才看得出是超时、DNS 还是被限流
json="$(curl -sS -m 15 --get --data-urlencode "addr=${ADDR}" "$API")" || {
    echo "请求 Steam 接口失败（网络问题，不等于服务器掉线）" >&2
    exit 2
}

if [ -z "$json" ]; then
    echo "Steam 接口返回空响应（不等于服务器掉线）" >&2
    exit 2
fi

ADDR="$ADDR" python3 -c '
import json, os, sys

raw = sys.stdin.read()
try:
    resp = json.loads(raw)["response"]
except Exception:
    print("无法解析 Steam 接口响应（不等于服务器掉线）: " + raw[:200], file=sys.stderr)
    sys.exit(2)

addr = os.environ["ADDR"]
servers = [s for s in resp.get("servers", []) if s.get("addr") == addr]

if not servers:
    print(f"未在 Steam 主服务器上找到 {addr}（服务器可能已停止对外登记）")
    sys.exit(1)

s = servers[0]
appid = s.get("appid")
if appid != 108600:
    print(f"注意: {addr} 登记的是 AppID {appid}，不是 Project Zomboid (108600)")

steamid = s.get("steamid")
gamedir = s.get("gamedir")
vac = s.get("secure")
gameport = s.get("gameport")
print(f"已登记: {addr}  steamid={steamid}  appid={appid}  gamedir={gamedir}  "
      f"vac={vac}  gameport={gameport}")
sys.exit(0)
' <<<"$json"
