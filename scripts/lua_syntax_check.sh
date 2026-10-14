#!/usr/bin/env bash
# 用游戏自带的 Lua 编译器（luaj-kahluafork fork）检查 .lua 语法 —— 不启动游戏、不需要开 Steam。
#
# 为什么这么做：本机 javac 是 17/21，而游戏 class 文件是 Java 25 的，编译期读不了 ⇒ 检查器只用反射
# 按名字取游戏类，编译不需要游戏 jar；运行时用游戏自带的 JRE（Java 25）跑。
#
# 用法：
#   scripts/lua_syntax_check.sh <文件或目录> [...]        # 目录会递归找 *.lua
# 环境变量：
#   PZ_GAME_DIR  游戏 .app 路径（默认 macOS Steam 安装路径）
#   PZ_JAVA      覆盖 java 可执行文件
#
# 退出码：0 = 全部通过；1 = 有文件语法错（会逐条打印 文件:行:期望什么）；2 = 参数/环境问题。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app}"
JAR="$GAME/Contents/Java/projectzomboid.jar"

if [ ! -f "$JAR" ]; then
  echo "找不到游戏 jar: $JAR" >&2
  echo "用 PZ_GAME_DIR=<你的 .app 路径> 指定，例如：PZ_GAME_DIR='/path/Project Zomboid.app' $0 ." >&2
  exit 2
fi

JAVA="${PZ_JAVA:-}"
if [ -z "$JAVA" ]; then
  for cand in \
    "$GAME/Contents/PlugIns/jre-aarch64/Contents/Home/bin/java" \
    "$GAME/Contents/PlugIns/jre-x86_64/Contents/Home/bin/java"; do
    if [ -x "$cand" ]; then JAVA="$cand"; break; fi
  done
fi
if [ -z "$JAVA" ]; then
  echo "找不到游戏自带 JRE，可用 PZ_JAVA=/path/to/java 指定（需要 Java 25 才能读游戏的 class 文件）" >&2
  exit 2
fi

if ! command -v javac >/dev/null 2>&1; then
  echo "需要 javac（只用来编译检查器本身；检查器不引用游戏类，17/21 均可）" >&2
  exit 2
fi

OUT="${PZ_LUACHECK_OUT:-${TMPDIR:-/tmp}/bin2_lua_syntax_check}"   # 编译产物放临时目录，别污染仓库
mkdir -p "$OUT"
if [ ! -f "$OUT/LuaSyntaxCheck.class" ] || [ "$HERE/LuaSyntaxCheck.java" -nt "$OUT/LuaSyntaxCheck.class" ]; then
  javac -nowarn -d "$OUT" "$HERE/LuaSyntaxCheck.java" || exit 2
fi

exec "$JAVA" -cp "$JAR:$OUT" LuaSyntaxCheck "$@"
