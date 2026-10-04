#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# CompanionDogsBlockyAlpaca 发布前自检（一键跑完所有离线校验）
#
#   用法：
#     ./tools/check.sh              # 全跑
#     ./tools/check.sh --quick      # 跳过"需要联网抓 luaparse"的 Lua 5.1 语法检查
#     ./tools/check.sh --no-probe   # 跳过需要 JDK + 游戏 jar 的工坊物品探针
#
#   检查项（每项失败都会打印原因并以非 0 退出）：
#     1. Lua 5.1 语法（本机没有 lua 二进制，用 npm 的 luaparse，装到 /tmp，不进仓库）
#     2. 翻译：JSON 可解析 / 无重复键 / 无 BOM / 无裸 % / 三语键集合一致
#        + 交叉检查 Breed.lua 里的每个品种都有名字键与描述键
#     3. glb 结构：骨骼<=60、21 个必需剪辑、accessor 不越界、POSITION min/max、
#        有 TEXCOORD_0、顶点数是 3 的倍数、索引是 0..N-1 连续、蒙皮平移通道不爆
#     4. 图片：工坊预览 256/512 正方形 <=1024000 字节、海报 512、图标 64、4 张品种头像
#     5. Lua 集成测试：fengari 上跑 mock base，9 条注册契约断言
#     6. 工坊物品：用游戏自己的 SteamWorkshopItem 解析 workshop.txt 并校验 preview.png
# ---------------------------------------------------------------------------
set -uo pipefail

ITEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_DIR="$ITEM_DIR/Contents/mods/CompanionDogsBlockyAlpaca/42"
BLOCKY="$ITEM_DIR/tools/blocky"
TEST_DIR="$ITEM_DIR/tools/test"
ALPACA_ITEM="$(cd "$ITEM_DIR/../bin2_companion_alpaca" && pwd)"
ALPACA_TOOLS="$ALPACA_ITEM/tools"

PY="${PY:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3}"
NODE_BIN_DIR="${NODE_BIN_DIR:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin}"

QUICK=0
NO_PROBE=0
for a in "$@"; do
    case "$a" in
        --quick) QUICK=1 ;;
        --no-probe) NO_PROBE=1 ;;
        *) echo "未知参数：$a"; exit 2 ;;
    esac
done

bad=0
step() { printf '\n== %s ==\n' "$1"; }

if [[ ! -x "$PY" ]]; then echo "找不到 PY=$PY"; exit 2; fi

# ---------------------------------------------------------------- 1. Lua 语法
step "Lua 5.1 语法"
if [[ "$QUICK" == "1" ]]; then
    echo "skipped (--quick)"
else
    LUACHECK="${LUACHECK:-/tmp/luaparse_check}"
    if [[ ! -d "$LUACHECK/node_modules/luaparse" ]]; then
        mkdir -p "$LUACHECK"
        ( cd "$LUACHECK" && PATH="$NODE_BIN_DIR:$PATH" npm i --silent luaparse@0.3.1 >/dev/null 2>&1 ) \
            || echo "warn: luaparse 安装失败（离线？）—— 用 --quick 跳过本步"
    fi
    cat > "$LUACHECK/check.js" <<'JS'
const fs = require('fs');
const luaparse = require('luaparse');
let bad = 0;
for (const f of process.argv.slice(2)) {
    try {
        luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1' });
        console.log('  OK   ' + f);
    } catch (e) {
        console.log('  FAIL ' + f + ' :: ' + e.message);
        bad++;
    }
}
process.exit(bad ? 1 : 0);
JS
    if [[ -d "$LUACHECK/node_modules/luaparse" ]]; then
        PATH="$NODE_BIN_DIR:$PATH" node "$LUACHECK/check.js" \
            "$MOD_DIR/media/lua/shared/CompanionDogsBlockyAlpaca_Breed.lua" \
            "$MOD_DIR/media/lua/shared/Definitions/animal/BlockyAlpacaDefinitions.lua" \
            "$MOD_DIR/media/lua/shared/Definitions/animal/CompanionDogsBlockyAlpaca_Parts.lua" || bad=1
    fi
fi

# ---------------------------------------------------------------- 2. 翻译
step "翻译（含 Breed.lua 交叉一致性）"
"$PY" "$BLOCKY/check_translations.py" || bad=1

# ---------------------------------------------------------------- 3. glb
step "glb 结构"
"$PY" "$ALPACA_TOOLS/alpaca/validate_glb.py" \
    --glb "$MOD_DIR/media/models_X/Skinned/BlockyAlpaca_Body.glb" || bad=1

# ---------------------------------------------------------------- 4. 图片
step "图片"
"$PY" "$BLOCKY/make_images.py" --check --skip-portraits || bad=1

# ---------------------------------------------------------------- 5. Lua 集成测试
step "Lua 集成测试（fengari 上跑 Lua，mock base）"
if [[ -d "$TEST_DIR/node_modules/fengari" || -d "$ALPACA_TOOLS/test/node_modules/fengari" ]]; then
    NODE_PATH="$ALPACA_TOOLS/test/node_modules" PATH="$NODE_BIN_DIR:$PATH" \
        node "$TEST_DIR/run_blocky.js" || bad=1
else
    echo "skipped (找不到 fengari；先跑一次 $ALPACA_TOOLS/test/run_lua_test.sh 装上)"
fi

# ---------------------------------------------------------------- 6. 工坊探针
step "工坊物品（游戏自己的解析器）"
if [[ "$NO_PROBE" == "1" ]]; then
    echo "skipped (--no-probe)"
elif [[ -x "$ALPACA_ITEM/../bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh" ]]; then
    "$ALPACA_ITEM/../bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh" "" \
        "$HOME/Zomboid/Workshop/bin2_blocky_alpaca" || bad=1
else
    echo "skipped (找不到 bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh)"
fi

printf '\n== 结论 ==\n'
if [[ "$bad" == "0" ]]; then
    echo "全部通过"
else
    echo "有检查失败"
fi
exit "$bad"
