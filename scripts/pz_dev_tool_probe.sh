#!/usr/bin/env bash
# 探针：Project Zomboid 动物/模型/贴图/音频开发这条链路上，本机现在能用哪些工具。
#
# 分三部分：
#   A. 游戏自带的开发工具（零安装，最重要）—— 打印入口与证据路径
#   B. 通用外部工具链是否已安装 —— 打印"任务 -> 工具 -> 状态 -> 安装命令"
#   C. 对一个模组目录做资产体检（models_X / AnimSets / textures / sounds 的约定）
#
# 用法：
#   scripts/pz_dev_tool_probe.sh                      # 只探测
#   scripts/pz_dev_tool_probe.sh <mod_version_dir>    # 顺带体检某个模组版本目录（含 mod.info 的那层）
#
# 设计原则：只读，不安装任何东西；没装的工具只给出安装命令，不做网络请求。
set -uo pipefail

GAME_DIR="${PZ_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid}"
PY="${PY:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3}"
JAVA_DIR=""
for rel in "" "Project Zomboid.app/Contents/Java" "Contents/Java" "ProjectZomboid"; do
    cand="$GAME_DIR${rel:+/$rel}"
    if [[ -f "$cand/projectzomboid.jar" ]]; then JAVA_DIR="$cand"; break; fi
done

printf '== 游戏目录 ==\n  %s\n' "${JAVA_DIR:-未找到（设置 PZ_GAME_DIR=<游戏根目录>）}"

# ---------------------------------------------------------------- A. 游戏自带
printf '\n== A. 游戏自带的开发工具（无需安装）==\n'
if [[ -n "$JAVA_DIR" ]]; then
    LUA="$JAVA_DIR/media/lua"
    prove() { # prove <我们断言的文件:行号> <说明>
        local loc="$1" desc="$2"
        local f="${loc%%:*}" ln="${loc##*:}"
        if [[ -f "$f" ]] && sed -n "${ln}p" "$f" | grep -q .; then
            printf '  [OK ] %-46s %s\n' "$desc" "${loc#"$JAVA_DIR/"}"
        else
            printf '  [?? ] %-46s %s\n' "$desc" "$loc"
        fi
    }
    cat <<'TXT'
  入口（两步）：
    1) Steam 启动选项加  -debug          （Lua 侧判据：getCore():getDebug()）
    2) 游戏内：右键"装备栏物品" → Debug Menu → 切到 Dev 标签页
TXT
    prove "$LUA/client/ISUI/ISEquippedItem.lua:452"        "调试菜单入口（右键装备物品）"
    prove "$LUA/client/DebugUIs/DebugMenu/ISDebugMenu.lua:38" "Dev → Animation Viewer"
    prove "$LUA/client/DebugUIs/DebugMenu/ISDebugMenu.lua:39" "Dev → Attachment Editor"
    prove "$LUA/client/DebugUIs/DebugMenu/ISDebugMenu.lua:36" "Dev → Anim Debug Monitor"
    prove "$LUA/client/DebugUIs/AnimationClipViewer.lua:446"  "Animation Viewer 的 Animal Model 下拉"
    prove "$LUA/client/DebugUIs/AnimationClipViewer.lua:452"  "它加载 animal-editor 动画集"
    prove "$LUA/client/DebugUIs/AttachmentEditorUI.lua:1"     "附件编辑器（offset/rotate/scale）"
    prove "$LUA/client/DebugUIs/DebugContextMenu.lua:94"      "右键 → Extended Anims List"
    prove "$LUA/client/DebugUIs/DebugContextMenu.lua:105"     "右键 → Animation Text"
    prove "$LUA/client/DebugUIs/TextureViewer.lua:1"          "贴图查看器"
    prove "$LUA/client/DebugUIs/ObjectViewer.lua:1"           "对象查看器"
    prove "$LUA/client/DebugUIs/SpriteModelEditor.lua:1"      "精灵/模型编辑器"
    prove "$LUA/client/ISUI/ISDebugAvatarUI.lua:1"            "头像预览（AnimalAvatarDefinition 相关）"
    prove "$LUA/client/DebugUIs/LuaDebugger.lua:1"            "Lua 调试器"
    prove "$LUA/client/DebugUIs/LuaFileBrowser.lua:1"         "Lua 文件浏览器"
    prove "$LUA/client/DebugUIs/WatchWindow.lua:1"            "变量监视窗口"
    if [[ -f "$JAVA_DIR/media/AnimSets/animal-editor/idle/Idle.xml" ]]; then
        printf '  [OK ] %-46s %s\n' "Animation Viewer 用的动物动画集" "media/AnimSets/animal-editor/"
    fi
    printf '\n  引擎能载入的模型格式（jar 内字面量证据，靠 Assimp/jassimp）：\n'
    "$PY" - "$JAVA_DIR/projectzomboid.jar" <<'PYEOF' 2>/dev/null || true
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
probe = ["zombie/core/skinnedmodel/model/FileTask_AbstractLoadModel.class",
         "zombie/core/skinnedmodel/model/MeshAssetManager.class",
         "zombie/core/skinnedmodel/ModelManager$AnimDirReloader.class"]
for ext in (".glb", ".fbx", ".x"):
    where = [n for n in probe if n in z.namelist() and ext.encode() in z.read(n)]
    print(f"  [{'OK ' if where else '?? '}] {ext:5s} 引用它的类：{len(where)}/{len(probe)}")
n_j = len([n for n in z.namelist() if n.startswith('jassimp')])
print(f"  [OK ] Assimp 绑定 jassimp 类数：{n_j}")
PYEOF
    printf '\n  也可以不进菜单，直接在调试控制台调用（两者都是 Java 暴露的全局函数）：\n'
    printf '      showAnimationViewer()      -- 动画查看器（选 Animal Model 会出现你的动物）\n'
    printf '      showAttachmentEditor()     -- 附件编辑器（帽子/驮袋挂点就靠它调）\n'
    printf '  其它有用的全局：getAllAnimalsDefinitions() / getAnimationViewerState() / setAnimationRecorderActive(true)\n'
else
    printf '  （跳过：没找到游戏目录）\n'
fi

# ---------------------------------------------------------------- B. 外部工具
printf '\n== B. 通用外部工具链 ==\n'
have() { command -v "$1" >/dev/null 2>&1 && command -v "$1" || echo ""; }
row() { # row <任务> <工具> <可执行名> <安装命令>
    local task="$1" tool="$2" exe="$3" how="$4" p
    p="$(have "$exe")"
    if [[ -n "$p" ]]; then printf '  [有] %-22s %-14s %s\n' "$task" "$tool" "$p"
    else printf '  [无] %-22s %-14s 装：%s\n' "$task" "$tool" "$how"; fi
}
row "3D 全流程/重定向/UV/烘焙" "Blender"      blender        "brew install --cask blender"
row "网格格式转换/检查"        "assimp"       assimp         "brew install assimp"
row "FBX→glTF"                 "FBX2glTF"     FBX2glTF       "npm i -g fbx2gltf"
row "glTF 检查/优化/变换"      "gltf-transform" gltf-transform "npm i -g @gltf-transform/cli"
row "glTF 压缩"                "gltfpack"     gltfpack       "上游 releases（github.com/zeux/meshoptimizer），无 brew formula"
row "glTF 官方校验器"          "gltf-validator" gltf_validator "npm i -g gltf-validator"
row "网格处理/测量"            "meshlab"      meshlabserver  "brew install --cask meshlab"
row "UV 展开"                  "xatlas"       xatlas         "pip install xatlas"
row "音频处理/转码"            "ffmpeg"       ffmpeg         "brew install ffmpeg"
row "音频处理"                 "sox"          sox            "brew install sox"
row "位图批处理"               "ImageMagick"  magick         "brew install imagemagick"
row "矢量/图标"                "Inkscape"     inkscape       "brew install --cask inkscape"

printf '\n  Python 侧（本仓库工具用的是独立运行时）：\n'
if [[ -x "$PY" ]]; then
    "$PY" - <<'PYEOF'
import importlib
tasks = [
    ("gltf 读写/校验", "pygltflib", "pip install pygltflib"),
    ("网格处理/测量", "trimesh", "pip install trimesh"),
    ("体素/网格化", "scipy", "pip install scipy"),
    ("图像处理", "PIL", "（已随运行时提供 Pillow）"),
    ("数值", "numpy", "（已随运行时提供）"),
    ("噪声场", "noise", "pip install noise"),
    ("音频读写", "soundfile", "pip install soundfile"),
    ("音频分析", "librosa", "pip install librosa"),
]
for name, mod, how in tasks:
    try:
        m = importlib.import_module(mod)
        print(f"  [有] {name:16s} {mod:12s} {getattr(m, '__version__', '?')}")
    except Exception:
        print(f"  [无] {name:16s} {mod:12s} 装：pip install {mod}" if how.startswith("pip") else f"  [无] {name:16s} {mod:12s}")
PYEOF
else
    printf '  （跳过：没找到 PY=%s）\n' "$PY"
fi

# ---------------------------------------------------------------- C. 资产体检
MOD="${1:-}"
if [[ -n "$MOD" ]]; then
    printf '\n== C. 资产体检：%s ==\n' "$MOD"
    [[ -f "$MOD/mod.info" ]] && printf '  mod.info        OK\n' || printf '  mod.info        缺失！\n'
    for d in media/models_X/Skinned media/AnimSets media/textures/Body media/sound media/scripts; do
        if [[ -d "$MOD/$d" ]]; then
            printf '  %-22s %s 个文件\n' "$d/" "$(find "$MOD/$d" -type f | wc -l | tr -d ' ')"
        else
            printf '  %-22s —\n' "$d/"
        fi
    done
    echo "  模型：";  find "$MOD/media/models_X" -type f 2>/dev/null | sed "s|$MOD/|    |" | head -6
    echo "  动画集 node（每个变量一个 xml）："; find "$MOD/media/AnimSets" -name "*.xml" 2>/dev/null | sed "s|$MOD/|    |" | head -6
    echo "  生成模型的 scripts 声明（model 块）："; grep -rl "^ *model " "$MOD/media/scripts" 2>/dev/null | sed "s|$MOD/|    |" | head -4
    echo "  贴图的体积/尺寸体检（UI 图标可以任意尺寸；身体图集按生态惯例 512 或 1024 正方形）："
    "$PY" - "$MOD" <<'PYEOF' 2>/dev/null || true
import os, sys
from PIL import Image
root = sys.argv[1]
BODY_OK = {512, 1024}
issues = 0
for dp, _, fns in os.walk(os.path.join(root, "media", "textures")):
    for fn in sorted(fns):
        if not fn.lower().endswith(".png"):
            continue
        p = os.path.join(dp, fn)
        sz = os.path.getsize(p)
        w, h = Image.open(p).size
        rel = os.path.relpath(p, root)
        if sz > 2 * 1024 * 1024:
            print(f"    [大] {rel} {w}x{h} {sz} bytes（>2MB，注意工坊体积）")
            issues += 1
        if os.sep + "Body" + os.sep in p and (w != h or w not in BODY_OK):
            print(f"    [怪] {rel} {w}x{h}（身体图集惯例是 512/1024 正方形）")
            issues += 1
if issues == 0:
    print("    没有异常")
PYEOF
fi

printf '\n完成。工具选型与"哪个脚本可以被替代"的说明见 docs/pz-dev-tooling.md\n'
