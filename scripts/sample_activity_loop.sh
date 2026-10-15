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
# 退出码：**0 = 正常跑完**（哪怕中间有采样失败）；**3 = 采到有人在线，主动提前结束**。
# 那个 3 是故意的：这轮跑在无人值守的后台作业里，而作业**只在结束时**叫醒人，
# 所以"有人了"必须让它当场结束、立刻有人处理（渠道要在同一刻做 A2S 交叉验证）。
# 收到 3 之后：去报名字，然后**补一轮**把剩下的点采完。
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
  out=$("$PY" "$REPO/scripts/pz_rcon.py" sample --csv "$CSV" --alert-on-players 2>&1)
  code=$?
  if [ "$code" -eq 0 ]; then
    echo "[$i/$TIMES] $out"
  elif [ "$code" -eq 3 ]; then
    # 「有人了」是要**立刻**通知渠道的事件（他们的稿子能不能提前发就看这个），
    # 而这轮采样跑在无人值守的后台作业里、只在结束时才叫醒人。
    # ⇒ 主动结束这一轮，让采到名字后几秒内就有人来处理（晚到 22:00 收尾的话，
    #   人早走了、渠道也没法在同一刻做 A2S 交叉验证，这条证据就废了）。
    echo "[$i/$TIMES] *** 有人在线 —— 这轮提前结束，去报名字 ***"
    echo "$out"
    echo "[采样] 因『有人在线』提前结束于 $(date '+%F %T %Z')（第 $i/$TIMES 次之后）"
    echo "[采样] 剩下的点：处理完告警后要再补一轮"
    exit 3
  else
    # 采样失败不中止整轮：记下来继续，缺的点就是缺的点
    FAIL=$((FAIL + 1))
    echo "[$i/$TIMES] 采样失败（code=${code}）：$out" >&2
  fi
  if [ "$i" -lt "$TIMES" ]; then
    SLEEP=$((INTERVAL - ($(date +%s) - T0)))
    [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
  fi
done

echo "[采样] 结束 $(date '+%F %T %Z')  成功 $((TIMES - FAIL))/$TIMES"
exit 0
