#!/usr/bin/env bash
# 用游戏自己的解析器校验本物品**四个模组**的 mod.info 与侧边栏图标路径（不需要 Steam，不启动游戏）。
#
#   ./run.sh
#
# [unknown-locally] 的含义：那个依赖不在本机的 ~/Zomboid/mods/ 里 —— 公开的第三方模组
# 是 Steam 工坊订阅、装在 steamapps/workshop/content 下，headless 探针看不到它们。
# 所以判据是"**我们自己的**依赖必须 [ok]（尤其是 Bin2NPCExtensionBase），第三方的不计分"。
#
# 两个探针：
#   ModInfoProbe —— ChooseGameInfo.getModDetails(id)，验证目录布局/mod.info/依赖解析
#   TextureProbe —— ZomboidFileSystem.getAbsolutePath("media/ui/...")，验证**带版本号子目录**
#                   下的贴图能被找到（原版侧边栏图标走的就是这条路；找不到就是空白按钮）
set -euo pipefail

ITEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
[ -n "$JAVAC" ] || { echo "找不到 javac（需要 JDK ≥ 游戏字节码版本）" >&2; exit 1; }

JAVA=""
for c in "$JAVA_DIR/../PlugIns/jre-aarch64/Contents/Home/bin/java" \
         "$JAVA_DIR/../PlugIns/jre-x86_64/Contents/Home/bin/java" \
         "$JAVA_DIR/jre64/bin/java" "$JAVA_DIR/jre/bin/java"; do
  [ -n "$c" ] && [ -x "$c" ] && { JAVA="$c"; break; }
done
[ -n "$JAVA" ] || { echo "找不到 java" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

"$JAVAC" -nowarn -cp "$JAVA_DIR/projectzomboid.jar" -d "$OUT" \
    "$HERE/ModInfoProbe.java" "$HERE/TextureProbe.java"

# 四个模组都要在 ~/Zomboid/mods/ 下有软链（见 README §5），探针才看得到
cd "$JAVA_DIR"
"$JAVA" -Djava.awt.headless=true -cp "$OUT:$JAVA_DIR/projectzomboid.jar" \
        ModInfoProbe Bin2NPCExtensionBase Bin2NPCExtension Bin2NPCExtensionYese Bin2NPCExtensionVanilla

# 原版侧边栏图标的 5 档 x 2 态：引擎必须能从 **42.21/media** 里找到它们
# （TextureProbe 会打印 ChooseGameInfo$Mod 的 media.version 目录，再用 File 确认存在；
#  tools/make_icons.py 生成这些图）
TEXTURES=()
for size in 48 64 80 96 128; do
  for state in Off On; do
    TEXTURES+=("ui/Sidebar/$size/NPC_${state}_$size.png")
  done
done
"$JAVA" -Djava.awt.headless=true -cp "$OUT:$JAVA_DIR/projectzomboid.jar" \
        TextureProbe Bin2NPCExtensionVanilla "${TEXTURES[@]}"
