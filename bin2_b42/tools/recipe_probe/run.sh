#!/usr/bin/env bash
# 用游戏自己的脚本解析器离线校验 recipe 脚本(不启动游戏、不需要 Steam)。
#
#   ./run.sh                          # 校验 bin2_extension 42.19.0 的配方
#   ./run.sh <recipes.txt> [<more.txt> ...]
#
# 原理:引擎只在它扫描到的目录里找脚本(ScriptManager.Load() → ZomboidFileSystem 的
# media/scripts + 已启用 mod 的 media/scripts)。headless 下没有"已启用 mod"这回事,
# 所以本脚本把待校验文件**临时**复制进 <游戏>/media/scripts/generated/recipes/,
# 跑完立刻删除(EXIT trap,即使中途失败也会删)。
# 判断标准:输出 must 出现 ALL RECIPES PARSED,且待校验行的 keep/destroy/fluidMode/amount
# 与脚本里写的意图一致。
#
# 依赖:JDK ≥ 25(游戏字节码是 class file 69.0,老 JDK 会报"错误的类文件版本")。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_MOD="$(cd "$HERE/../.." && pwd)"

GAME_DIR="${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid}"
JAVA_DIR=""
for rel in "" "Contents/Java" "Project Zomboid.app/Contents/Java" "ProjectZomboid"; do
  cand="$GAME_DIR${rel:+/$rel}"
  if [ -f "$cand/projectzomboid.jar" ]; then JAVA_DIR="$cand"; break; fi
done
[ -n "$JAVA_DIR" ] || { echo "找不到 projectzomboid.jar,请设 PZ_GAME_DIR" >&2; exit 1; }

# 游戏字节码版本高,必须用新 JDK 编译(优先 temurin-25,其次 PATH 上的 javac)
JAVAC=""
for c in "$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac" \
         "$(command -v javac 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVAC="$c"; break; }
done
[ -n "$JAVAC" ] || { echo "找不到 javac(需要 JDK ≥ 25)" >&2; exit 1; }

# 用游戏自带的 JRE 运行,保证与游戏同一运行时
JAVA=""
for c in "$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java" \
         "$JAVA_DIR/../PlugIns/jre-x86_64/Contents/Home/bin/java" \
         "$JAVA_DIR/jre64/bin/java" "$JAVA_DIR/jre/bin/java"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVA="$c"; break; }
done
[ -n "$JAVA" ] || { echo "找不到 java" >&2; exit 1; }

# 待校验的配方脚本
FILES=("$@")
if [ "${#FILES[@]}" -eq 0 ]; then
  FILES=("$REPO_MOD/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt")
fi

STAGE_DIR="$JAVA_DIR/media/scripts/generated/recipes"
COPIED=()
STAGED_IDS=()
cleanup() {
  local f
  for f in "${COPIED[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
  if [ "${#COPIED[@]}" -gt 0 ]; then
    for f in "${COPIED[@]}"; do
      if [ -e "$f" ]; then echo "警告: 临时脚本没删掉: $f" >&2; fi
    done
  fi
  # 必须显式返回 0:EXIT trap 里最后一条命令若失败,set -e 会把整个脚本的退出码改成 1,
  # 让 java 探针的退出码失去意义(调用方会误判校验失败)。
  return 0
}
trap cleanup EXIT

for src in "${FILES[@]}"; do
  [ -f "$src" ] || { echo "找不到配方文件: $src" >&2; exit 1; }
  base="$(basename "$src")"
  dst="$STAGE_DIR/zz_probe_$base"
  cp "$src" "$dst"
  COPIED+=("$dst")
  echo "临时载入: $dst"
  # 从文件里取出所有 craftRecipe ID
  while read -r id; do
    [ -n "$id" ] && STAGED_IDS+=("$id")
  done < <(grep -oE 'craftRecipe[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$src" | awk '{print $2}')
done

[ "${#STAGED_IDS[@]}" -gt 0 ] || { echo "这些文件里没有 craftRecipe" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"; cleanup' EXIT
"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d "$OUT" "$HERE/RecipeProbe.java"

# cwd 必须是游戏的 Java 目录(引擎按相对路径解析 media/)
cd "$JAVA_DIR"
"$JAVA" -Djava.awt.headless=true -cp "$OUT:$JAVA_DIR/projectzomboid.jar" \
        RecipeProbe "${STAGED_IDS[@]}"
