#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Bin2NPCExtension 离线 Lua 集成测试
#
# 不启动游戏：用 fengari（Lua 5.3 的 JS 实现）把模组的 14 个 Lua 文件加载进一个
# mock 出来的 PZ 环境（引擎全局 + Project A-Life + ProjectALifeJimmy + 橙子社区经济），
# 断言招募流程真的按设计工作。
#
#   用法：
#     ./run_lua_test.sh              # 缺 fengari 时先 npm i，再跑
#     ./run_lua_test.sh --quick      # 跳过 npm 安装（依赖已在 node_modules 里）
#     ./run_lua_test.sh --verbose    # 让 run.js 打出每个被测文件的完整路径
#
#   退出码：0 = ALL PASS；1 = 有断言失败 / 加载失败；2 = 环境问题（node/fengari 缺失等）
#
#   可用环境变量覆盖：
#     NODE_BIN   node/npm 所在目录（本机 node 不在默认 PATH 里）
#     NODE       node 可执行文件绝对路径（覆盖 NODE_BIN 推导）
#     NPM        npm 可执行文件绝对路径
#
# 依赖（node_modules/）刻意不入库：需要时才装。如果同级仓库
# bin2_companion_alpaca/tools/test/node_modules/fengari 已经存在，run.js 会直接复用它。
# ---------------------------------------------------------------------------
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_BIN="${NODE_BIN:-/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin}"
NODE="${NODE:-$NODE_BIN/node}"

# npm 不一定和 node 同目录，按 NPM -> $NODE_BIN/npm -> PATH 的顺序找。
resolve_npm() {
    if [[ -n "${NPM:-}" ]]; then printf '%s\n' "$NPM"; return 0; fi
    if [[ -x "$NODE_BIN/npm" ]]; then printf '%s\n' "$NODE_BIN/npm"; return 0; fi
    local found
    found="$(PATH="$NODE_BIN:$PATH" command -v npm 2>/dev/null || true)"
    [[ -n "$found" ]] && { printf '%s\n' "$found"; return 0; }
    return 1
}

QUICK=0
VERBOSE=""
for arg in "$@"; do
    case "$arg" in
        --quick)   QUICK=1 ;;
        --verbose) VERBOSE="--verbose" ;;
        -h|--help)
            sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "ERROR: unknown argument: $arg (try --help)" >&2
            exit 2 ;;
    esac
done

if [[ ! -x "$NODE" ]]; then
    echo "ERROR: node not found at '$NODE'" >&2
    echo "       set NODE_BIN=/path/to/node/bin (or NODE=/path/to/node)" >&2
    exit 2
fi

cd "$TEST_DIR"

# ---------------------------------------------------------------- 依赖
# 本目录没有 fengari 也能跑：run.js 会退回复用 bin2_companion_alpaca 的那一份。
SHARED_FENGARI="$(cd "$TEST_DIR/../../.." 2>/dev/null && pwd || true)/bin2_companion_alpaca/tools/test/node_modules/fengari"

if [[ ! -d node_modules/fengari && ! -d "$SHARED_FENGARI" ]]; then
    if [[ "$QUICK" == "1" ]]; then
        echo "ERROR: fengari is missing (neither here nor in bin2_companion_alpaca) and --quick was given" >&2
        echo "       run without --quick once, or: PATH=$NODE_BIN:\$PATH npm i fengari" >&2
        exit 2
    fi
    echo "[setup] installing fengari (offline test dependency, not committed)..."
    if ! NPM_BIN="$(resolve_npm)"; then
        echo "ERROR: npm not found; install fengari manually or set NPM=/path/to/npm" >&2
        echo "       PATH=$NODE_BIN:\$PATH npm i fengari" >&2
        exit 2
    fi
    PATH="$NODE_BIN:$PATH" "$NPM_BIN" install --silent --no-audit --no-fund
fi

# ---------------------------------------------------------------- 跑
exec "$NODE" run.js $VERBOSE
