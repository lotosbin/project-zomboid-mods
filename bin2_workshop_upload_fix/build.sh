#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ZBWorkshopUploadFix 构建脚本
#
#   编译 42.21/src/ 下的 Java 源码，产出模组目录里的
#   media/java/client/ZBWorkshopUploadFix.jar
#
# 用法：
#   ./build.sh              # 编译打包
#   ./build.sh clean        # 清理构建目录
#
# 可用环境变量覆盖：
#   PZ_JAVA_DIR  游戏 Java 目录（含 projectzomboid.jar）
#   ZB_JAR       ZombieBuddy.jar 路径（编译期注解来源）
#   JAVAC        javac 可执行文件
#   JAR          jar 可执行文件
#
# 注意：B42.21 的 projectzomboid.jar 是 Java 25 字节码，javac 必须 >= 游戏版本才能读它；
# 这里用 --release 17 产出 Java 17 字节码（与 ZombieBuddy 2.x 一致）。
# ---------------------------------------------------------------------------
set -euo pipefail

ITEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$ITEM_DIR/Contents/mods/ZBWorkshopUploadFix"
MOD_VERSION="${MOD_VERSION:-42.21}"
VERSION_DIR="$MOD_DIR/$MOD_VERSION"
SRC_DIR="$VERSION_DIR/src"
OUT_DIR="$ITEM_DIR/build/classes"
JAR_OUT="$VERSION_DIR/media/java/client/ZBWorkshopUploadFix.jar"

PZ_JAVA_DIR="${PZ_JAVA_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java}"
ZB_JAR="${ZB_JAR:-$PZ_JAVA_DIR/ZombieBuddy.jar}"
JAR="${JAR:-jar}"

# 选一个能读游戏字节码的 javac：B42.21 的 projectzomboid.jar 是 Java 25（主版本 69），
# javac 17 会报 "class file has wrong version 69.0, should be 61.0"。
pick_javac() {
    local candidates=() c ver
    [[ -n "${JAVAC:-}" ]] && candidates+=("$JAVAC")
    candidates+=("$HOME/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac")
    [[ -n "${JAVA_HOME:-}" ]] && candidates+=("$JAVA_HOME/bin/javac")
    candidates+=("$(command -v javac 2>/dev/null || true)")
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -x "$c" ]] || continue
        ver="$("$c" -version 2>&1 | sed -E 's/^[^0-9]*([0-9]+).*/\1/' | head -1)"
        if [[ -n "$ver" && "$ver" -ge 25 ]]; then printf '%s\n' "$c"; return 0; fi
    done
    return 1
}
JAVAC="$(pick_javac)" || {
    echo "ERROR: 需要 JDK >= 25（B42.21 的游戏 class 是 Java 25）；可用 JAVAC=... 指定" >&2
    exit 1
}

if [[ "${1:-}" == "clean" ]]; then
    rm -rf "$ITEM_DIR/build"
    echo "cleaned: $ITEM_DIR/build"
    exit 0
fi

echo "== ZBWorkshopUploadFix build =="
echo "mod dir : $MOD_DIR"
echo "version : $MOD_VERSION"

if [[ ! -f "$PZ_JAVA_DIR/projectzomboid.jar" ]]; then
    echo "ERROR: projectzomboid.jar not found in: $PZ_JAVA_DIR" >&2
    echo "       set PZ_JAVA_DIR to the game's Contents/Java directory and retry." >&2
    exit 1
fi
if [[ ! -f "$ZB_JAR" ]]; then
    echo "ERROR: ZombieBuddy.jar not found at: $ZB_JAR" >&2
    echo "       install ZombieBuddy first (see README) or set ZB_JAR." >&2
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

"$JAVAC" --release 17 -encoding UTF-8 \
    -cp "$PZ_JAVA_DIR/projectzomboid.jar:$ZB_JAR" \
    -d "$OUT_DIR" \
    "${SOURCES[@]}"

rm -f "$JAR_OUT"
"$JAR" --create --file "$JAR_OUT" -C "$OUT_DIR" .

echo "built   : $JAR_OUT"
"$JAR" --list --file "$JAR_OUT" | sed 's/^/          /'

echo "== 补丁注解自检（应看到 Patch / Patch\$OnExit / Patch\$Return）=="
JAVAP="$(dirname "$(command -v "$JAVAC")")/javap"
"$JAVAP" -v -p -cp "$JAR_OUT" \
    'com.lotosbin.zbworkshopfix.Patch_SteamWorkshopItem$Patch_submitUpdate' 2>/dev/null \
    | grep -E 'Patch\$|Patch;' | head -5 || true
