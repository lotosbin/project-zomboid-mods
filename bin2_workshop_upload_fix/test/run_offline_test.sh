#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 离线自测：验证 ZombieBuddy 的补丁机制对本模组的补丁类成立。
#
#   不启动游戏、不上传任何东西；只在一个临时 JVM 里：
#     1. 用 ZombieBuddy 自带的 PatchTransformer 把 @Patch.* 别名注解翻译成 ByteBuddy 的 @Advice.*；
#     2. 把它挂到一个假的 submitUpdate() 目标上并调用，确认补丁代码执行、且没有跳过原方法；
#     3. 对照组证明 @Return(readOnly=false) 能改写 boolean 返回值。
#
# 用法：
#   ./run_offline_test.sh
#
# 可用环境变量覆盖：PZ_JAVA_DIR / ZB_JAR / JAVAC
# ---------------------------------------------------------------------------
set -euo pipefail

ITEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_VERSION="${MOD_VERSION:-42.21}"
SRC_DIR="$ITEM_DIR/Contents/mods/ZBWorkshopUploadFix/$MOD_VERSION/src"
TEST_DIR="$ITEM_DIR/test"

PZ_JAVA_DIR="${PZ_JAVA_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java}"
ZB_JAR="${ZB_JAR:-$PZ_JAVA_DIR/ZombieBuddy.jar}"

# 与 build.sh 相同的选择逻辑：B42.21 的游戏 class 是 Java 25，需要 javac >= 25
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
JAVAC="$(pick_javac)" || { echo "ERROR: 需要 JDK >= 25；可用 JAVAC=... 指定" >&2; exit 1; }
JAVA="$(dirname "$JAVAC")/java"
[[ -x "$JAVA" ]] || JAVA="$(command -v java)"
JAR_BIN="$(dirname "$JAVAC")/jar"

for f in "$PZ_JAVA_DIR/projectzomboid.jar" "$ZB_JAR"; do
    [[ -f "$f" ]] || { echo "ERROR: not found: $f" >&2; exit 1; }
done

echo "== ZBWorkshopUploadFix offline test =="
echo "src     : $SRC_DIR"
echo "test    : $TEST_DIR"
echo "game jar: $PZ_JAVA_DIR/projectzomboid.jar"
echo "zb jar  : $ZB_JAR"

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$SRC_DIR" "$TEST_DIR" -name '*.java' | sort)

"$JAVAC" -nowarn --release 17 -encoding UTF-8 \
    -cp "$PZ_JAVA_DIR/projectzomboid.jar:$ZB_JAR" \
    -d "$OUT/classes" \
    "${SOURCES[@]}"

# 自测需要一个提供 Instrumentation 的小 agent；
# 清单必须声明 redefine/retransform，否则 ZombieBuddy 的 PatchTransformer 无法重定义补丁类。
printf 'Premain-Class: zbworkshopfix.test.TestAgent\nCan-Redefine-Classes: true\nCan-Retransform-Classes: true\n' > "$OUT/agent.mf"
"$JAR_BIN" --create --file "$OUT/testagent.jar" \
    --manifest "$OUT/agent.mf" -C "$OUT/classes" zbworkshopfix/test/TestAgent.class

echo
"$JAVA" \
    -javaagent:"$OUT/testagent.jar" \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    -cp "$OUT/classes:$PZ_JAVA_DIR/projectzomboid.jar:$ZB_JAR" \
    zbworkshopfix.test.RunAdviceTest
