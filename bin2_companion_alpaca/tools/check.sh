#!/usr/bin/env bash
# CompanionDogsAlpaca 发布前自检：把一个 addon 能静态验证的东西全部验一遍。
#
# 覆盖：
#   1. Lua 5.1 语法（lua 二进制本机没有，用 npm 的 luaparse；装到临时目录，不进仓库）
#   2. 翻译文件：JSON 可解析 / 无重复键 / 无 BOM / 无裸 % / 三种语言键集合一致 / 自有键齐全
#   3. glb 结构：骨骼<=60、顶层 identity、21 个必需剪辑、accessor 不越界、POSITION min/max、
#      蒙皮一致性、平移通道不爆（共享 accessor 双重叠加的回归检测）、有 TEXCOORD_0、
#      顶点数是 3 的倍数、索引是 0..N-1 连续
#   3b. 第三方 CC0 原件 sha256（换几何来源时必须可追溯到确切文件）
#   4. 图片：头像/图标/海报/工坊预览的尺寸与体积（预览图必须是 256 或 512 的正方形 PNG）
#   5. 声音：9 条 .ogg 的声道/采样率/时长
#   6. 工坊物品：有 id= 时用游戏自己的解析器探针验（可选，需要 Java + 游戏 jar）
#
# 用法：
#   tools/check.sh            # 全跑（工坊探针只在 staging 存在时跑）
#   tools/check.sh --quick    # 跳过需要联网抓 luaparse 的 Lua 语法检查
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_DIR="$(cd "$HERE/.." && pwd)"
ALPACA="$HERE/alpaca"
PY="${PY:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3}"
NODE_BIN_DIR="${NODE_BIN_DIR:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin}"
QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

fail=0
step() { printf '\n== %s ==\n' "$1"; }
bad()  { fail=$((fail + 1)); }

[[ -x "$PY" ]] || { echo "ERROR: python not found at $PY (set PY=...)" >&2; exit 2; }

step "Lua 5.1 语法"
if [[ "$QUICK" == "1" ]]; then
    echo "skipped (--quick)"
else
    LUACHECK="${LUACHECK:-/tmp/luaparse_check}"
    if [[ ! -d "$LUACHECK/node_modules/luaparse" ]]; then
        mkdir -p "$LUACHECK"
        ( cd "$LUACHECK" && PATH="$NODE_BIN_DIR:$PATH" npm i --silent luaparse@0.3.1 >/dev/null 2>&1 )
    fi
    cat > "$LUACHECK/check.js" <<'JS'
const fs = require('fs');
const luaparse = require('luaparse');
let bad = 0;
for (const f of process.argv.slice(2)) {
  try {
    luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1' });
    console.log('OK   ' + f.replace(/^.*CompanionDogsAlpaca\//, ''));
  } catch (e) {
    bad++; console.log('FAIL ' + f + ' :: ' + e.message);
  }
}
process.exit(bad ? 1 : 0);
JS
    if ! PATH="$NODE_BIN_DIR:$PATH" node "$LUACHECK/check.js" \
        $(find "$ITEM_DIR" -name "*.lua" | sort); then bad; fi
fi

step "翻译"
"$PY" "$ALPACA/check_translations.py" || bad

step "声音范围一致性（脚本 distanceMax <-> registerVoices / SOUND_LOOPED）"
"$PY" "$ALPACA/check_sound_ranges.py" || bad

step "第三方 CC0 原件完整性（sha256）"
if [[ -f "$ALPACA/vendor/SHA256SUMS" ]]; then
    ( cd "$ALPACA/vendor" && shasum -a 256 -c SHA256SUMS ) || bad
else
    echo "skipped (vendor/SHA256SUMS missing)"
fi

step "glb 结构"
"$PY" "$ALPACA/validate_glb.py" || bad

step "图片"
"$PY" "$ALPACA/make_images.py" --check || bad

step "声音"
"$PY" "$ALPACA/make_sounds.py" --check || bad

step "Lua 集成测试（fengari 上跑 Lua，mock base API）"
if [[ -x "$ITEM_DIR/tools/test/run_lua_test.sh" ]]; then
    "$ITEM_DIR/tools/test/run_lua_test.sh" ${QUICK:+--quick} || bad
else
    echo "skipped (tools/test/run_lua_test.sh not present)"
fi

step "工坊物品（游戏自己的解析器）"
PROBE="$ITEM_DIR/../bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh"
STAGE="$HOME/Zomboid/Workshop/$(basename "$ITEM_DIR")"
if [[ -x "$PROBE" && -d "$STAGE" ]]; then
    "$PROBE" "" "$STAGE" || bad
else
    echo "skipped (probe or staging missing: $PROBE / $STAGE)"
fi

printf '\n== 结论 ==\n'
if [[ "$fail" -eq 0 ]]; then
    echo "全部通过"
else
    echo "$fail 项失败" >&2
fi
exit "$fail"
