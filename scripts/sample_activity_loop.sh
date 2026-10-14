#!/usr/bin/env bash
# 活动采样循环：按固定间隔把 ① 的在线人数追加进 docs/server-ops/activity-samples.csv
#
# 为什么要攒时间点：单点读数（比如"早上 9 点 0 人"）证明不了任何事——另一个服在那个点也是 0。
# 判断"晚上到底有没有人"只能看一串时刻。同机同刻的 A2S 与 RCON 只算仪器交叉验证，不算多一个样本。
#
# 用法：
#   scripts/sample_activity_loop.sh                # 默认 13 次 × 600 秒（20:00–22:00）
#   scripts/sample_activity_loop.sh 6 300          # 6 次 × 300 秒
#   CSV=/tmp/t.csv scripts/sample_activity_loop.sh 2 5   # 试跑，别污染真表
#
# 只读：底层调 scripts/pz_rcon.py，它硬编码只允许 players/help/showoptions。

set -u

TIMES="${1:-13}"
INTERVAL="${2:-600}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSV="${CSV:-$REPO/docs/server-ops/activity-samples.csv}"
PY="${PYTHON:-python3}"

echo "[采样] 开始 $(date '+%F %T %Z')  次数=$TIMES  间隔=${INTERVAL}s  目标表=$CSV"

FAIL=0
for i in $(seq 1 "$TIMES"); do
  # 从本次开始的时刻算间隔，而不是"跑完再睡"——否则每次都漂移约 10 秒（RCON 握手 + 两次查询），
  # 13 次下来错过 20:00/20:10… 这些整点，和同事的 A2S 点（20:30 / 21:00）也对不齐。
  T0=$(date +%s)
  if out=$("$PY" "$REPO/scripts/pz_rcon.py" sample --csv "$CSV" 2>&1); then
    echo "[$i/$TIMES] $out"
  else
    # 采样失败不中止整轮：记下来继续，缺的点就是缺的点
    FAIL=$((FAIL + 1))
    echo "[$i/$TIMES] 采样失败：$out" >&2
  fi
  if [ "$i" -lt "$TIMES" ]; then
    SLEEP=$((INTERVAL - ($(date +%s) - T0)))
    [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
  fi
done

echo "[采样] 结束 $(date '+%F %T %Z')  成功 $((TIMES - FAIL))/$TIMES"
exit 0
