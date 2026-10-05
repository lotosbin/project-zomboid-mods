#!/usr/bin/env bash
# 批量自检仓库里所有 workshop.txt（用游戏自己的解析器，不需要 Steam）。
#
#   ./check_all.sh                 # 默认扫仓库根（脚本上溯 4 层）下所有 */workshop.txt
#   ./check_all.sh /path/to/repo   # 指定仓库根
#
# 原理：SteamWorkshopItem 的构造函数会过 ZomboidFileSystem.validatePrefix()，只认
# ~/Zomboid/Workshop/… 这类白名单路径 —— 所以把每份 workshop.txt 复制到
# ~/Zomboid/Workshop/__wtchk_<n>/ 下再喂给探针，跑完删掉。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$HERE/../../../.." && pwd)}"

# ---- 找游戏目录（含 projectzomboid.jar）--------------------------------------
GAME_DIR="${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid}"
JAVA_DIR=""
for rel in "" "Contents/Java" "Project Zomboid.app/Contents/Java" "ProjectZomboid"; do
  cand="$GAME_DIR${rel:+/$rel}"
  if [ -f "$cand/projectzomboid.jar" ]; then JAVA_DIR="$cand"; break; fi
done
[ -n "$JAVA_DIR" ] || { echo "找不到 projectzomboid.jar，请设 PZ_GAME_DIR" >&2; exit 1; }

# ---- 选 javac（要 ≥ 游戏字节码版本；B42.21 是 Java 25）与 java -----------------
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
STAGE_ROOT="$HOME/Zomboid/Workshop/__wtchk"
rm -rf "$STAGE_ROOT"; mkdir -p "$STAGE_ROOT"
cleanup() { rm -rf "$OUT" "$STAGE_ROOT"; }
trap cleanup EXIT

echo "== repo     : $ROOT"
echo "== game dir : $JAVA_DIR"
echo "== javac    : $JAVAC"
echo

"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d "$OUT" "$HERE/WorkshopTxtProbe.java"

# ---- 每份 workshop.txt 复制进白名单 staging（保留可读的目录名）-----------------
STAGED=()
i=0
while IFS= read -r f; do
  i=$((i + 1))
  rel="${f#"$ROOT"/}"
  stage="$STAGE_ROOT/$(printf '%02d' "$i")_$(echo "${rel%/workshop.txt}" | tr '/' '_')"
  mkdir -p "$stage"
  cp "$f" "$stage/workshop.txt"
  STAGED+=("$stage")
done < <(cd "$ROOT" && find . -name workshop.txt -not -path './.git/*' | sed 's|^\./||' | sort | sed "s|^|$ROOT/|")

[ "${#STAGED[@]}" -gt 0 ] || { echo "没找到任何 workshop.txt" >&2; exit 1; }

cd "$JAVA_DIR"
"$JAVA" -Djava.awt.headless=true -cp "$OUT:$JAVA_DIR/projectzomboid.jar" \
       WorkshopTxtProbe --check "${STAGED[@]}"
