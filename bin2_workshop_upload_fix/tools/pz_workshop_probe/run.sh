#!/usr/bin/env bash
# 运行创意工坊上传链路自检（不触发上传）。
#
#   ./run.sh                                  # 自动找游戏 + 自动挑 ~/Zomboid/Workshop 里最新的待上传目录
#   ./run.sh /path/to/ProjectZomboid          # 指定游戏目录（app 包根 / Contents/Java / Linux 游戏根均可）
#   ./run.sh "" ~/Zomboid/Workshop/MyMod      # 只指定待上传目录
#
# 前置：Steam 客户端已登录；游戏没在跑也没关系（本脚本只初始化 Steam API，不会上传）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="${1:-${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid}}"
WS_DIR="${2:-${PZ_WS_FOLDER:-}}"

# ---- 统一成含 projectzomboid.jar 的目录 --------------------------------------
JAVA_DIR=""
for rel in "" "Contents/Java" "Project Zomboid.app/Contents/Java" "ProjectZomboid"; do
  cand="$GAME_DIR${rel:+/$rel}"
  if [ -f "$cand/projectzomboid.jar" ]; then JAVA_DIR="$cand"; break; fi
done
[ -n "$JAVA_DIR" ] || { echo "找不到 projectzomboid.jar，请把游戏目录作为第一个参数传入" >&2; exit 1; }

# ---- 待上传目录：默认取 ~/Zomboid/Workshop 下最新的一个 ----------------------
if [ -z "$WS_DIR" ]; then
  WS_DIR="$(ls -dt "$HOME"/Zomboid/Workshop/*/ 2>/dev/null | while read -r d; do
              [ -f "$d/workshop.txt" ] && { echo "${d%/}"; break; }
            done)"
fi
[ -n "$WS_DIR" ] || { echo "没找到待上传目录，请作为第二个参数传入 ~/Zomboid/Workshop/<模组>" >&2; exit 1; }
[ -f "$WS_DIR/workshop.txt" ] || { echo "$WS_DIR 下没有 workshop.txt" >&2; exit 1; }

# ---- 选 javac（要 ≥ 游戏字节码版本；B42.21 是 Java 25）与 java ----------------
JAVAC=""
for c in "$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac" \
         "$(command -v javac 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVAC="$c"; break; }
done
[ -n "$JAVAC" ] || { echo "找不到 javac（需要 JDK ≥ 游戏版本）" >&2; exit 1; }

JAVA=""
for c in "$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java" \
         "$JAVA_DIR/../PlugIns/jre-x86_64/Contents/Home/bin/java" \
         "$JAVA_DIR/jre64/bin/java" "$JAVA_DIR/jre/bin/java" \
         "$(command -v java 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVA="$c"; break; }
done
[ -n "$JAVA" ] || { echo "找不到 java" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== game dir : $JAVA_DIR"
echo "== workshop : $WS_DIR"
echo "== javac    : $JAVAC"
echo "== java     : $JAVA"
echo

"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d "$OUT" "$HERE/WorkshopProbe.java"

# 必须 cwd 到游戏目录：steam_appid.txt 是相对路径读取的
cd "$JAVA_DIR"
PZ_JAVA_DIR="$JAVA_DIR" PZ_WS_FOLDER="$WS_DIR" \
  "$JAVA" -Djava.library.path="$JAVA_DIR" -Dzomboid.steam=1 -Djava.awt.headless=true \
          --enable-native-access=ALL-UNNAMED \
          -cp "$JAVA_DIR/projectzomboid.jar:$OUT" WorkshopProbe
