#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ViewpointMac 构建脚本
#
#   编译 src/ 下的 Java 源码，产出 mod 目录里的 media/java/client/ViewpointMac.jar
#
# 用法：
#   ./build.sh              # 编译打包
#   ./build.sh clean        # 清理构建目录
#
# 可用环境变量覆盖：
#   PZ_JAVA_DIR  游戏 Java 目录（含 projectzomboid.jar）
#   ZB_JAR       ZombieBuddy.jar 路径（编译期注解来源）
#   JAVAC        javac 可执行文件
# ---------------------------------------------------------------------------
set -euo pipefail

ITEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$ITEM_DIR/Contents/mods/ViewpointMac"
# B42 版本化布局：mod.info 与 media 位于版本子目录（与 pz3d / Viewpoint 的工坊包一致）
MOD_VERSION="${MOD_VERSION:-42.21}"
VERSION_DIR="$MOD_DIR/$MOD_VERSION"
SRC_DIR="$VERSION_DIR/src"
OUT_DIR="$ITEM_DIR/build/classes"
JAR_OUT="$VERSION_DIR/media/java/client/ViewpointMac.jar"

PZ_JAVA_DIR="${PZ_JAVA_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java}"
ZB_JAR="${ZB_JAR:-$PZ_JAVA_DIR/ZombieBuddy.jar}"
JAVAC="${JAVAC:-javac}"
JAR="${JAR:-jar}"

if [[ "${1:-}" == "clean" ]]; then
    rm -rf "$ITEM_DIR/build"
    echo "cleaned: $ITEM_DIR/build"
    exit 0
fi

echo "== ViewpointMac build =="
echo "mod dir : $MOD_DIR"
echo "version : $MOD_VERSION"

if [[ ! -f "$PZ_JAVA_DIR/projectzomboid.jar" ]]; then
    echo "ERROR: projectzomboid.jar not found in: $PZ_JAVA_DIR" >&2
    echo "       set PZ_JAVA_DIR to the game's Contents/Java directory and retry." >&2
    exit 1
fi
if [[ ! -f "$ZB_JAR" ]]; then
    echo "ERROR: ZombieBuddy.jar not found at: $ZB_JAR" >&2
    echo "       install ZombieBuddy first (see mod README) or set ZB_JAR." >&2
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$(dirname "$JAR_OUT")"

# 收集源码（macOS 自带 bash 3.2 没有 mapfile，用 while read 兼容）
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$SRC_DIR" -name '*.java' | sort)
if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "ERROR: no java sources under $SRC_DIR" >&2
    exit 1
fi

echo "sources : ${#SOURCES[@]} file(s)"
echo "game jar: $PZ_JAVA_DIR/projectzomboid.jar"
echo "zb jar  : $ZB_JAR"

"$JAVAC" --release 17 -encoding UTF-8 -Xlint:all \
    -cp "$PZ_JAVA_DIR/projectzomboid.jar:$ZB_JAR" \
    -d "$OUT_DIR" \
    "${SOURCES[@]}"

rm -f "$JAR_OUT"
"$JAR" --create --file "$JAR_OUT" -C "$OUT_DIR" .

echo "built   : $JAR_OUT"
"$JAR" --list --file "$JAR_OUT" | sed 's/^/          /'
