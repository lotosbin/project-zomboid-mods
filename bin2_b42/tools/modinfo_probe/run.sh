#!/usr/bin/env bash
# 用游戏自己的解析器校验 bin2_b42 各模组的 mod.info + 版本门禁（不启动游戏、不改游戏目录）。
#
#   ./run.sh                                   # 校验 Contents/mods/ 下所有模组目录
#   ./run.sh <模组目录> [<模组目录> ...]
#
# 校验内容：目录布局与 mod.info 能被解析、引擎会挑中哪个版本子目录、versionMin/versionMax
# 在当前版本上是否放行，以及在"低一个小版本"的模拟客户端上是否确实关掉。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B42="$(cd "$HERE/../.." && pwd)"

GAME_DIR="${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid}"
JAVA_DIR=""
for rel in "" "Contents/Java" "Project Zomboid.app/Contents/Java" "ProjectZomboid"; do
  cand="$GAME_DIR${rel:+/$rel}"
  if [ -f "$cand/projectzomboid.jar" ]; then JAVA_DIR="$cand"; break; fi
done
[ -n "$JAVA_DIR" ] || { echo "找不到 projectzomboid.jar，请设 PZ_GAME_DIR" >&2; exit 1; }

JAVAC=""
for c in "$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac" \
         "$(command -v javac 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVAC="$c"; break; }
done
[ -n "$JAVAC" ] || { echo "找不到 javac（需要 JDK ≥ 游戏字节码版本，当前是 25）" >&2; exit 1; }

JAVA=""
for c in "$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java" \
         "$JAVA_DIR/../PlugIns/jre-x86_64/Contents/Home/bin/java" \
         "$JAVA_DIR/jre64/bin/java" "$JAVA_DIR/jre/bin/java"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVA="$c"; break; }
done
[ -n "$JAVA" ] || { echo "找不到 java" >&2; exit 1; }

MOD_DIRS=("$@")
if [ "${#MOD_DIRS[@]}" -eq 0 ]; then
  for d in "$B42"/Contents/mods/*/; do
    [ -d "$d" ] && MOD_DIRS+=("${d%/}")
  done
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d "$OUT" "$HERE/ModInfoProbe.java"

# 探针最后会 cd 到游戏目录（引擎按相对路径解析 media/），所以模组目录必须先转成绝对路径
ABS_DIRS=()
for d in "${MOD_DIRS[@]}"; do
  case "$d" in
    --*) ABS_DIRS+=("$d");;                                  # 透传 --game=... 开关
    *)   ABS_DIRS+=("$(cd "$(dirname "$d")" && pwd)/$(basename "$d")");;
  esac
done

# cwd 必须是游戏的 Java 目录
cd "$JAVA_DIR"
"$JAVA" -Djava.awt.headless=true -cp "$OUT:$JAVA_DIR/projectzomboid.jar" \
        ModInfoProbe "${ABS_DIRS[@]}"
