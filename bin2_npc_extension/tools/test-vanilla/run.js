#!/usr/bin/env node
// ===========================================================================
// run.js —— Bin2NPCExtensionVanilla 离线 Lua 集成测试的 fengari 驱动
// ===========================================================================
//
// 做什么：
//   1. 用 fengari（Lua 5.3 的 JS 实现）开一个全新的 Lua state，装上 Project Zomboid
//      的最小引擎桩 + 依赖的 mock（mock_env.lua 负责：Project A-Life、Jeem、
//      **原版物品栏（Base.Money 钞票）与原版 ISUI / 左侧侧边栏**）。
//      本口味不依赖任何经济模组，所以 mock 里没有经济模组，取而代之的是
//      "一个实例 = 一个单位、没有堆叠、穿戴容器看不到"的原版物品栏；
//   2. 实现 **PZ 语义的 require**：两个被测模组的 media/lua/{client,shared,server} 都是搜索根，
//      "Bin2NPCExtensionCore/Config" -> <模组>/media/lua/<层>/Bin2NPCExtensionCore/Config.lua；
//      同一文件只执行一次（引擎按绝对路径缓存，这里用 package.loaded 等价模拟），
//      并用 package.searchers 计数器证明"没有任何文件需要被 require 二次加载"；
//   3. 按引擎真实加载顺序执行被测的 19 个 Lua 文件（公共层 14 + 本口味 5）；
//   4. 做一次**静态翻译检查**（不进 Lua VM）：扫源码里的 T("...") / Text.get("...")
//      字面量（含 `T(cond and "A" or "B")` 这种条件键），断言 CN/EN 的 IG_UI.json
//      里都有对应键且键集合一致；
//   5. 做一次**静态图标检查**：读 media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png 的
//      PNG 头，校验 5 档 × 2 态的真实像素/RGBA，并把这份"磁盘上真的存在"的清单注入
//      Lua（__iconFiles）—— mock 的 getTexture 照引擎语义"找不到就返回 nil"，
//      于是"贴图路径写错 / 漏生成一档"在离线测试里就会红；
//   6. 从 media/sandbox-options.txt 解析出**游戏里真正生效的沙盒默认值**并注入 Lua
//      （__sandboxDefaults）：SandboxVars 的值来自这个文件，不是公共层 Config.DEFAULTS；
//   7. 执行 test_recruit.lua 的 50 条断言，用它的返回值当进程退出码。
//
// 用法：node run.js            （通常由 run_lua_test.sh 调起）
//      node run.js --verbose  （把每个被测文件的实际路径也打出来）
'use strict';

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

// ------------------------------------------------------------------ 路径
const TEST_DIR = __dirname;
// 两个模组：公共层 Bin2NPCExtensionBase + 本口味。口味的 mod.info 里声明了 require=公共层，
// 所以引擎会把公共层的文件排在前面（引擎如何保证见下面「加载顺序」的字节码证据）。
const MOD_VERSION_DIR = path.resolve(TEST_DIR, '..', '..', 'Contents', 'mods', 'Bin2NPCExtensionVanilla', '42.21');
const BASE_VERSION_DIR = path.resolve(TEST_DIR, '..', '..', 'Contents', 'mods', 'Bin2NPCExtensionBase', '42.21');
const MEDIA_LUA_DIR = path.join(MOD_VERSION_DIR, 'media', 'lua');
const TRANSLATE_DIR = path.join(MEDIA_LUA_DIR, 'shared', 'Translate');
/** 原版侧边栏图标：<mod>/media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png（见 tools/make_icons.py）。 */
const SIDEBAR_DIR = path.join(MOD_VERSION_DIR, 'media', 'ui', 'Sidebar');
const SIDEBAR_SIZES = [48, 64, 80, 96, 128];
const SANDBOX_FILE = path.join(MOD_VERSION_DIR, 'media', 'sandbox-options.txt');
const MODULE_NAME = 'Bin2NPCExtensionVanilla';

/** 语言 -> { 完整键: 文案 }。测试用 MOCK.useCnTranslations() 打开，就能断言真实文案。 */
const textsByLanguage = {};
const MOCK_FILE = path.join(TEST_DIR, 'mock_env.lua');
const TEST_FILE = path.join(TEST_DIR, 'test_recruit.lua');

// ------------------------------------------------------------------ fengari
// node_modules 刻意不入库：优先用本次 test 目录里的，其次复用 bin2_companion_alpaca
// 已经装好的那一份（同一台机器上不用再下一遍）。
function loadFengari() {
    const candidates = [
        path.join(TEST_DIR, 'node_modules', 'fengari'),
        path.resolve(TEST_DIR, '..', '..', '..', 'bin2_companion_alpaca', 'tools', 'test', 'node_modules', 'fengari'),
    ];
    for (const dir of candidates) {
        const entry = path.join(dir, 'src', 'fengari.js');
        if (fs.existsSync(entry)) {
            return { fengari: require(dir), from: dir };
        }
    }
    process.stderr.write('[run] FATAL: fengari not found. Tried:\n');
    for (const dir of candidates) process.stderr.write(`  - ${dir}\n`);
    process.stderr.write('      run ./run_lua_test.sh (without --quick) to install it\n');
    process.exit(2);
}

const { fengari, from: fengariFrom } = loadFengari();
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

// ------------------------------------------------------------------ 被测文件（引擎加载顺序）
const SHARED = 'media/lua/shared';
const SERVER = 'media/lua/server';
const CLIENT = 'media/lua/client';

// 公共层的 14 个文件（按 Namespace.bind 的依赖顺序）——它们全是 shared 层的不纯函数式工厂，
// 加载时只定义工厂、不产生副作用，所以放 shared 是安全的（多人客户端也会加载，但什么也不做）。
const CORE_MODULES = [
    'Namespace', 'Config', 'Text', 'Contracts', 'Store', 'Economy', 'Cash', 'Alife', 'Jimmy',
    'Service', 'Maintain', 'Net', 'ServerBootstrap', 'ClientBootstrap',
];

// 本口味自己的 5 个 Lua 文件。加载顺序 = 引擎真实的层顺序：
//   shared（所有模组）-> client（所有模组）-> server（所有模组）
// 依据（javap 读 projectzomboid.jar）：
//   * LuaManager.LoadDirBase() 依次调 LoadDirBase("shared") 与 LoadDirBase("client")；
//     GameServer 走 LoadDirBase("shared")/("client",true)/("server")。
//   * LoadDirBase 按 ZomboidFileSystem.getModIDs() 的顺序遍历模组，对每个模组的
//     <media>/lua/<层> 调 searchFolders；收集完 loadList 后逐个 RunLua。
// 所以"公共层的 shared 一定早于口味的 client/server"是引擎保证的，不依赖模组顺序。
//
// ui/Panel 排在 ui/Icon 之前：Icon.lua 里 `require "Bin2NPCExtensionVanilla/ui/Panel"`，
// 引擎无论在 client 层先跑到哪一个文件，两个文件都只会被执行一次（RunLuaInternal 按绝对路径
// 缓存）；这里显式按依赖顺序排，正是为了让"每个文件正好执行一次"在驱动里也成立。
const FLAVOUR_MODULES = [
    [SHARED, `${MODULE_NAME}/Profile`],
    [CLIENT, `${MODULE_NAME}/ui/Panel`],
    [CLIENT, `${MODULE_NAME}/ui/Icon`],
    [CLIENT, `${MODULE_NAME}/Bootstrap`],
    [SERVER, `${MODULE_NAME}/Bootstrap`],
];

/** 被测文件：root 是绝对目录，module 是它在 require 世界里的名字。 */
const MOD_FILES = [
    ...CORE_MODULES.map((name) => ({
        root: BASE_VERSION_DIR,
        rel: `${SHARED}/Bin2NPCExtensionCore/${name}.lua`,
        module: `Bin2NPCExtensionCore/${name}`,
    })),
    ...FLAVOUR_MODULES.map(([tier, module]) => ({
        root: MOD_VERSION_DIR,
        rel: `${tier}/${module}.lua`,
        module,
    })),
];

// 去重后的模块名（本口味里 client/Bootstrap 与 server/Bootstrap 同名，共 18 个名字 19 个文件）
const REQUIRE_NAMES = [...new Set(MOD_FILES.map((file) => file.module))];

// 语言包
const LANGUAGES = ['CN', 'EN'];
const TRANSLATION_FILE = 'IG_UI.json';

// 静态翻译检查扫这些文件：公共层里所有会取翻译的模块 + 口味的两个 UI 文件。
// 翻译键前缀与 JSON 都在**口味**这边（公共层零身份），所以两边都要扫。
// 本口味的钱实现是 Cash.lua（不是 Economy.lua），两份都扫：谁调用了 Text.get 都要被查到。
const TRANSLATION_SOURCES = [
    { root: MOD_VERSION_DIR, rel: `${CLIENT}/${MODULE_NAME}/ui/Panel.lua` },
    { root: MOD_VERSION_DIR, rel: `${CLIENT}/${MODULE_NAME}/ui/Icon.lua` },
    ...['Text', 'Net', 'Jimmy', 'Economy', 'Cash', 'Service', 'Maintain', 'Alife', 'ClientBootstrap']
        .map((name) => ({ root: BASE_VERSION_DIR, rel: `${SHARED}/Bin2NPCExtensionCore/${name}.lua` })),
];

// ------------------------------------------------------------------ 小工具
function die(message, code) {
    process.stderr.write(`[run] FATAL: ${message}\n`);
    process.exit(code === undefined ? 2 : code);
}

function readLuaError(L) {
    const message = lua.lua_tostring(L, -1);
    return message === null ? '(non-string lua error)' : to_jsstring(message);
}

/** 覆写 print，保证与 JS 输出严格同序。 */
function installPrint(L) {
    lua.lua_pushjsfunction(L, function (L) {
        const n = lua.lua_gettop(L);
        const parts = [];
        for (let i = 1; i <= n; i++) {
            let text;
            if (lua.lua_type(L, i) === lua.LUA_TSTRING) {
                text = to_jsstring(lua.lua_tostring(L, i));
            } else {
                lua.lua_getglobal(L, to_luastring('tostring'));
                lua.lua_pushvalue(L, i);
                if (lua.lua_pcall(L, 1, 1, 0) === lua.LUA_OK) {
                    text = to_jsstring(lua.lua_tostring(L, -1));
                } else {
                    text = '?';
                }
                lua.lua_pop(L, 1);
            }
            parts.push(text);
        }
        process.stdout.write(parts.join('\t') + '\n');
        return 0;
    });
    lua.lua_setglobal(L, to_luastring('print'));
}

/**
 * 执行一个模组文件，并把它登记进 package.loaded —— 这是**引擎语义的忠实模拟**。
 *
 * 引擎的 LuaManager.RunLuaInternal 按**绝对路径**缓存（loaded / loadedReturn），
 * 命中就把上次的返回值直接还给你，所以一个文件每次 Lua 会话只执行一次；
 * 显式 require 拿到的就是这一份。不登记的话，模组内部的 require 会把同一个文件再跑一遍 ——
 * 旧的测试驱动正是这样（当时靠模组自己的幂等守卫兜住），于是"测试比引擎更严"成了假象：
 * 引擎里根本不会发生的双重执行，在测试里却天天发生。现在按引擎来。
 */
function loadAndRun(L, file, label, moduleName) {
    if (lauxlib.luaL_loadfile(L, file) !== lua.LUA_OK) {
        throw new Error(`load ${label} (${file}): ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
        throw new Error(`run ${label} (${file}): ${readLuaError(L)}`);
    }
    if (moduleName) {
        lua.lua_getglobal(L, to_luastring('__dshSetLoaded'));
        lua.lua_pushstring(L, to_luastring(moduleName));
        lua.lua_pushvalue(L, -3);                       // chunk 的返回值
        if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
            throw new Error(`package.loaded[${moduleName}]: ${readLuaError(L)}`);
        }
    }
    lua.lua_pop(L, 1);                                  // 丢掉（已登记的）返回值
}

// ------------------------------------------------------------------ PZ 风格 require
/**
 * 把 media/lua/{client,shared,server} 当搜索根，并统计每次 require 的调用次数。
 * 同一文件只执行一次由 package.loaded 保证（Lua 标准行为）。
 */
function installRequire(L) {
    // 两个模组的 lua 根都要能搜到（引擎的 LuaManager.paths 就是"所有启用模组的 media/lua"）。
    // 公共层放前面，与 require= 造成的模组顺序一致；实际两边模块名不重叠，顺序不影响结果。
    const roots = [];
    for (const versionDir of [BASE_VERSION_DIR, MOD_VERSION_DIR]) {
        for (const tier of [CLIENT, SHARED, SERVER]) {
            roots.push(path.join(versionDir, 'media', 'lua', tier));
        }
    }
    const setup = `
local MOCK = MOCK
local roots = { ${roots.map((r) => `"${r}"`).join(', ')} }
local function missing(name)
    local tried = {}
    for _, root in ipairs(roots) do
        local file = root .. "/" .. name .. ".lua"
        tried[#tried + 1] = file
        local chunk, err = loadfile(file)
        if chunk ~= nil then return chunk end
        -- loadfile 的失败信息里通常带 "No such file"/"cannot open"；语法错误则必须立刻抛出
        local message = tostring(err)
        if not string.find(message, "No such file", 1, true)
                and not string.find(message, "cannot open", 1, true)
                and not string.find(message, "ENOENT", 1, true) then
            error(err, 0)
        end
    end
    return nil, "module '" .. tostring(name) .. "' not found (tried " .. table.concat(tried, ", ") .. ")"
end
-- 供 run.js 把"自动加载过的文件"登记进 package.loaded（等价于引擎按绝对路径缓存 loadedReturn）
function __dshSetLoaded(name, value) package.loaded[name] = value end
local baseSearcher = package.searchers[2]
local customSearcher = function(name)
    MOCK.requireCounts[name] = (MOCK.requireCounts[name] or 0) + 1
    local chunk = missing(name)
    if chunk ~= nil then return chunk end
    -- 引擎自带的模块（string / table / ...）交给原来的 searcher；
    -- 其它名字说明我们少装了一个 mock，必须显式报错而不是静默返回 nil
    local base = baseSearcher(name)
    if base ~= nil then return base end
    error("no mock installed for module '" .. tostring(name) .. "'", 0)
end
package.searchers[2] = customSearcher
`;
    if (lauxlib.luaL_loadstring(L, to_luastring(setup)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`install require: ${readLuaError(L)}`);
    }
}

// ------------------------------------------------------------------ 静态翻译检查
/**
 * 逐字符扫 Lua 源码，跳过注释与字符串，收集：
 *   - T("key") / Text.get("key") 这类调用里的字面量键
 *   - Text.lua 里 REASONS / PREFIXES 映射表的键（值一侧的 "ReasonXxx"）
 */
const MARK = '\u0001';          // 我们在源码里插的"翻译键在此"标记
const NON_KEY_STRINGS = { 'grounds': true };

/**
 * 逐字符扫 Lua 源码（跳过注释；字符串原样保留），在会消费翻译键的位置插标记：
 *   - T("Key") / Text.get("Key") / Config.Text.get("Key") / Text.reason("Key")
 *   - T(cond and "KeyA" or "KeyB")：条件表达式的两个键（见下面 readConditionalKeys）
 *   - REASONS / PREFIXES 这类 <name> = "ReasonXxx" 映射表的**值**
 *   - labelKey = "FlowHire" 这类显式键传递
 * 然后从每个标记往后找第一个字符串字面量，作为键。
 */
function extractLiteralKeys(relativeFiles) {
    const callKeys = new Set();
    const mappingKeys = new Set();
    const perFile = {};

    // 注释剔除（字符串、长字符串、长注释都跳过；其它字符原样保留）
    const stripComments = (source) => {
        let out = '';
        let i = 0;
        const n = source.length;
        while (i < n) {
            const ch = source[i];
            const next = source[i + 1];
            if (ch === '-' && next === '-') {
                const long = source.slice(i).match(/^--\[(=*)\[/);
                if (long) {
                    const closer = `]${long[1]}]`;
                    const end = source.indexOf(closer, i + long[0].length);
                    i = end === -1 ? n : end + closer.length;
                } else {
                    const end = source.indexOf('\n', i);
                    i = end === -1 ? n : end;
                }
                out += ' ';
                continue;
            }
            if (ch === '"' || ch === "'") {
                let j = i + 1;
                let closed = false;
                while (j < n) {
                    if (source[j] === '\\') { out += source.slice(i, j + 2); j += 2; continue; }
                    if (source[j] === ch) { j += 1; closed = true; break; }
                    if (source[j] === '\n') break;
                    j += 1;
                }
                out += source.slice(i, closed ? j : Math.min(j, n));
                i = closed ? j : j;
                continue;
            }
            if (ch === '[') {
                const long = source.slice(i).match(/^\[(=*)\[/);
                if (long) {
                    const closer = `]${long[1]}]`;
                    const end = source.indexOf(closer, i + long[0].length);
                    i = end === -1 ? n : end + closer.length;
                    i = Math.min(i, n);
                    continue;
                }
            }
            out += ch;
            i += 1;
        }
        return out;
    };

    // 从 from 开始找第一个字符串字面量（允许跨行、跳过空白与逗号前的 { } 等）
    const readStringAt = (source, from) => {
        let i = from;
        const n = source.length;
        while (i < n) {
            const ch = source[i];
            if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') { i += 1; continue; }
            break;
        }
        if (i >= n) return null;
        const quote = source[i];
        if (quote !== '"' && quote !== "'") return null;
        let j = i + 1;
        let value = '';
        while (j < n) {
            const ch = source[j];
            if (ch === '\\') { value += source[j + 1]; j += 2; continue; }
            if (ch === quote) return value;
            if (ch === '\n') return null;
            value += ch;
            j += 1;
        }
        return null;
    };

    // <ident> = "ReasonXxx" 这种映射表只在 Text.lua 里有；其它文件的 `x = "follow"` 是数据不是翻译键。
    const MAPPING_TABLE_FILE = `${SHARED}/Bin2NPCExtensionCore/Text.lua`;

    /*
        条件键：`T(self.mode == "hire" and "HireHint" or "RosterHint")`。

        模板原来的做法（取 `T(` 之后的第一个字面量）在这种写法上会取到比较值 "hire"，
        于是测试要么误报"漏翻 hire"，要么被迫放过整行。这里补一条规则：
        当第一个实参不是字面量时，在**该调用的配对括号内**收集 `and` / `or` 后面的
        字面量 —— 那才是键（比较值在 and/or 之前，不会被收进来）。
    */
    const readConditionalKeys = (source, from) => {
        let i = from;
        const n = source.length;
        let depth = 0;
        let j = i;
        for (; j < n; j++) {
            if (source[j] === '(') depth += 1;
            else if (source[j] === ')') {
                depth -= 1;
                if (depth === 0) break;
            }
        }
        const segment = source.slice(i, j);
        const keys = [];
        const re = /(?:\band\b|\bor\b)\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g;
        let match;
        while ((match = re.exec(segment)) !== null) {
            const raw = match[1];
            keys.push(raw.slice(1, -1).replace(/\\(.)/g, '$1'));
        }
        return keys;
    };

    for (const source of relativeFiles) {
        const absolute = path.join(source.root, source.rel);
        const raw = fs.readFileSync(absolute, 'utf8');
        const code = stripComments(raw);
        const keys = [];
        const markers = [
            // T("Key") / Text.get("Key") / Config.Text.get("Key") / Text.reason("Key")
            { re: /(?<![\w.])T\s*\(\s*/g, kind: 'call' },
            { re: /(?<![\w.])Text\.get\s*\(\s*/g, kind: 'call' },
            { re: /(?<![\w.])Text\.reason\s*\(\s*/g, kind: 'call' },
            // labelKey = "FlowHire"：Economy.record 通过 labelKey 传键
            { re: /labelKey\s*=\s*/g, kind: 'mapping' },
        ];
        if (source.rel === MAPPING_TABLE_FILE) {
            markers.push({ re: /(?:^|[\s,{])\w+\s*=\s*/gm, kind: 'mapping' });
        }
        for (const { re, kind } of markers) {
            re.lastIndex = 0;
            let match;
            while ((match = re.exec(code)) !== null) {
                const value = readStringAt(code, re.lastIndex);
                if (value === null) {
                    // 第一个实参不是字面量（`T(key)` / `T(cond and "A" or "B")`）：
                    // 前者本来就扫不到（键在变量里，由 useCnTranslations 的运行时断言覆盖），
                    // 后者要按 and/or 规则补扫。
                    if (kind === 'call') {
                        for (const conditional of readConditionalKeys(code, re.lastIndex - 1)) {
                            if (conditional === '' || NON_KEY_STRINGS[conditional] === true) continue;
                            callKeys.add(conditional);
                            keys.push(conditional);
                        }
                    }
                    continue;
                }
                if (value === '') continue;
                if (NON_KEY_STRINGS[value] === true) continue;
                if (kind === 'call') {
                    callKeys.add(value);
                } else {
                    mappingKeys.add(value);
                }
                keys.push(value);
            }
        }
        perFile[source.rel] = keys;
    }

    return { callKeys, mappingKeys, perFile };
}


function loadTranslations() {
    const result = {};
    for (const language of LANGUAGES) {
        const file = path.join(TRANSLATE_DIR, language, TRANSLATION_FILE);
        if (!fs.existsSync(file)) die(`missing translation file: ${file}`);
        let parsed;
        try {
            parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (error) {
            die(`invalid JSON in ${file}: ${error.message}`);
        }
        const keys = new Set();
        const texts = {};
        const prefix = 'IGUI_Bin2NPCExtensionVanilla_';
        for (const full of Object.keys(parsed)) {
            if (typeof parsed[full] !== 'string' || parsed[full] === '') {
                die(`${language}: empty translation for ${full}`);
            }
            if (!full.startsWith(prefix)) die(`${language}: key without our prefix: ${full}`);
            keys.add(full.slice(prefix.length));
            texts[full] = parsed[full];
        }
        result[language] = keys;
        textsByLanguage[language] = texts;
    }
    return result;
}

// ------------------------------------------------------------------ 静态图标检查
/**
 * 读 PNG 头（8 字节签名 + IHDR：宽/高/位深/色彩类型）。
 * 这就是 tools/make_icons.py --check 的等价检查：尺寸必须是 <尺寸> x <尺寸>*0.75、
 * 必须是 RGBA（色型 6）—— 侧边栏图标要透明背景，否则会糊住原版面板。
 */
function readPngHeader(file) {
    const buffer = fs.readFileSync(file);
    if (buffer.length < 33) return null;
    const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    if (!buffer.subarray(0, 8).equals(signature)) return null;
    if (buffer.toString('ascii', 12, 16) !== 'IHDR') return null;
    return {
        width: buffer.readUInt32BE(16),
        height: buffer.readUInt32BE(20),
        bitDepth: buffer[24],
        colorType: buffer[25],
    };
}

/** 5 档 × 2 态的侧边栏图标必须在磁盘上、且尺寸/色型正确。返回可注入 Lua 的清单。 */
function checkSidebarIcons() {
    const verified = {};
    const problems = [];
    for (const size of SIDEBAR_SIZES) {
        const height = Math.round(size * 0.75);
        for (const state of ['Off', 'On']) {
            const rel = `media/ui/Sidebar/${size}/NPC_${state}_${size}.png`;
            const absolute = path.join(MOD_VERSION_DIR, rel);
            if (!fs.existsSync(absolute)) {
                problems.push(`missing ${rel}`);
                continue;
            }
            const header = readPngHeader(absolute);
            if (header === null) {
                problems.push(`${rel}: not a PNG`);
                continue;
            }
            if (header.width !== size || header.height !== height) {
                problems.push(`${rel}: ${header.width}x${header.height}, want ${size}x${height}`);
                continue;
            }
            if (header.colorType !== 6) {
                problems.push(`${rel}: PNG color type ${header.colorType}, want 6 (RGBA)`);
                continue;
            }
            verified[rel] = true;
        }
    }
    return { verified, problems };
}

// ------------------------------------------------------------------ 静态沙盒检查
/**
 * 从 media/sandbox-options.txt 解析每个选项的**默认值**。
 *
 * 为什么必须从文件里读而不是抄一份常量：游戏里的 SandboxVars 就是这份文件生成的，
 * 它才是"玩家什么都没改时真正生效的价格"；公共层 Config.DEFAULTS 只是沙盒表整个缺失时的
 * 兜底。两者在版本之间可能漂移（本口味现状就有差异，见 test_recruit.lua 的 B9 用例），
 * 所以 mock 的默认沙盒必须取自这份文件。
 */
function parseSandboxOptions() {
    const source = fs.readFileSync(SANDBOX_FILE, 'utf8');
    const re = /^\s*option\s+([A-Za-z0-9_.]+)\s*=\s*\{([\s\S]*?)^\s*\}/gm;
    const options = [];
    let match;
    while ((match = re.exec(source)) !== null) {
        const full = match[1];
        const body = match[2];
        const found = body.match(/default\s*=\s*([^,\n]+)/);
        let value = null;
        if (found) {
            const raw = found[1].trim();
            if (raw === 'true' || raw === 'false') value = raw === 'true';
            else if (/^-?\d+(\.\d+)?$/.test(raw)) value = Number(raw);
        }
        const key = body.match(/translation\s*=\s*([A-Za-z0-9_.]+)/);
        options.push({ name: full.split('.').pop(), full, value, translation: key ? key[1] : null });
    }
    return options;
}

/** 沙盒选项的翻译（Sandbox.json，前缀是 Sandbox_ 而不是 IGUI_）。只用完整键做集合断言。 */
function loadSandboxTranslations() {
    const result = {};
    for (const language of LANGUAGES) {
        const file = path.join(TRANSLATE_DIR, language, 'Sandbox.json');
        if (!fs.existsSync(file)) die(`missing translation file: ${file}`);
        let parsed;
        try {
            parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (error) {
            die(`invalid JSON in ${file}: ${error.message}`);
        }
        const keys = new Set();
        for (const full of Object.keys(parsed)) {
            if (typeof parsed[full] !== 'string' || parsed[full] === '') {
                die(`${language}: empty sandbox translation for ${full}`);
            }
            if (!full.startsWith('Sandbox_')) die(`${language}: sandbox key without the Sandbox_ prefix: ${full}`);
            keys.add(full);
        }
        result[language] = keys;
    }
    return result;
}

/** 把收集到的键注入 Lua：Config.__sourceKeys / __cnKeys / __enKeys + 图标与沙盒清单 */
function installStaticKeys(L) {
    const scan = extractLiteralKeys(TRANSLATION_SOURCES);
    const translations = loadTranslations();
    const sandboxTranslations = loadSandboxTranslations();
    const all = new Set([...scan.callKeys, ...scan.mappingKeys]);
    const icons = checkSidebarIcons();
    if (icons.problems.length > 0) {
        die(`sidebar icons are broken:\n  - ${icons.problems.join('\n  - ')}`);
    }
    const sandboxOptions = parseSandboxOptions();
    const sandboxDefaults = {};
    for (const option of sandboxOptions) {
        if (option.value === null) die(`sandbox option without a parsable default: ${option.full}`);
        sandboxDefaults[option.name] = option.value;
    }

    const luaArray = (values) => `{ ${[...values].sort().map((v) => `"${v}"`).join(', ')} }`;
    const luaSet = (values) => `{ ${[...values].map((v) => `["${v}"] = true`).join(', ')} }`;
    const luaMap = (map) => `{ ${Object.keys(map).sort()
        .map((k) => `[${JSON.stringify(k)}] = ${JSON.stringify(map[k])}`).join(', ')} }`;
    const luaTable = (map, formatter) => `{ ${Object.keys(map).sort()
        .map((k) => `[${JSON.stringify(k)}] = ${formatter(map[k])}`).join(', ')} }`;

    const code = `
Bin2NPCExtensionVanilla = Bin2NPCExtensionVanilla or {}
Bin2NPCExtensionVanilla.__sourceKeys = ${luaArray(all)}
Bin2NPCExtensionVanilla.__cnKeys = ${luaSet(translations.CN)}
Bin2NPCExtensionVanilla.__enKeys = ${luaSet(translations.EN)}
Bin2NPCExtensionVanilla.__cnText = ${luaMap(textsByLanguage.CN)}
Bin2NPCExtensionVanilla.__enText = ${luaMap(textsByLanguage.EN)}
Bin2NPCExtensionVanilla.__loadedCount = ${MOD_FILES.length}
Bin2NPCExtensionVanilla.__requireNames = ${luaArray(REQUIRE_NAMES)}
Bin2NPCExtensionVanilla.__coreModules = ${luaArray(CORE_MODULES.map((n) => `Bin2NPCExtensionCore/${n}`))}
Bin2NPCExtensionVanilla.__moduleFileCount = ${MOD_FILES.length}
-- 磁盘上真实存在的侧边栏图标（run.js 校验过尺寸与 RGBA）；mock 的 getTexture 用它当"文件系统"
Bin2NPCExtensionVanilla.__iconFiles = ${luaSet(Object.keys(icons.verified))}
Bin2NPCExtensionVanilla.__iconFileCount = ${Object.keys(icons.verified).length}
Bin2NPCExtensionVanilla.__sidebarSizes = ${luaArray(SIDEBAR_SIZES)}
-- media/sandbox-options.txt 里的默认值（游戏里真正生效的那一份）
Bin2NPCExtensionVanilla.__sandboxDefaults = ${luaTable(sandboxDefaults, (v) => JSON.stringify(v))}
Bin2NPCExtensionVanilla.__sandboxOptionNames = ${luaArray(sandboxOptions.map((o) => o.name))}
Bin2NPCExtensionVanilla.__sandboxOptionCount = ${sandboxOptions.length}
-- 沙盒翻译（Sandbox.json）的完整键集合：CN/EN 必须一一对应，且每个选项都要有名字与 tooltip
Bin2NPCExtensionVanilla.__cnSandboxKeys = ${luaSet(sandboxTranslations.CN)}
Bin2NPCExtensionVanilla.__enSandboxKeys = ${luaSet(sandboxTranslations.EN)}
`;
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`install static keys: ${readLuaError(L)}`);
    }
    return { scan, translations, all, icons, sandboxOptions, sandboxTranslations };
}

// ------------------------------------------------------------------ preload
/**
 * 引擎 UI 基类的 require 桩。
 *
 * 本口味的 ui/Panel.lua 与 ui/Icon.lua 都显式 `require "ISUI/..."`（只是顺序声明），
 * 游戏里这些文件由 client 层自动加载；mock_env.lua 里装的是同名全局桩，这里用
 * package.preload 把它们暴露给 require —— 这样这些 require **不会**落进
 * package.searchers[2]（那个计数器用来证明"没有模组文件需要二次读盘"）。
 */
function installPreloads(L) {
    const code = `
package.preload["ISUI/ISPanel"] = function() return ISPanel end
package.preload["ISUI/ISUIElement"] = function() return ISUIElement end
package.preload["ISUI/ISButton"] = function() return ISButton end
package.preload["ISUI/ISScrollingListBox"] = function() return ISScrollingListBox end
package.preload["ISUI/ISCollapsableWindow"] = function() return ISCollapsableWindow end
package.preload["ISUI/ISCollapsableWindowJoypad"] = function() return ISCollapsableWindowJoypad end
package.preload["ISUI/ISEquippedItem"] = function() return ISEquippedItem end
`;
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`install preloads: ${readLuaError(L)}`);
    }
}

// ------------------------------------------------------------------ main
function main() {
    const verbose = process.argv.includes('--verbose');

    process.stdout.write('== Bin2NPCExtensionVanilla offline Lua test (fengari / Lua 5.3) ==\n');
    process.stdout.write(`mod version dir : ${MOD_VERSION_DIR}\n`);
    process.stdout.write(`fengari         : ${verbose ? fengariFrom : path.basename(fengariFrom)}\n`);
    process.stdout.write(`mock            : ${verbose ? MOCK_FILE : path.basename(MOCK_FILE)}\n`);
    process.stdout.write(`assertions      : ${verbose ? TEST_FILE : path.basename(TEST_FILE)}\n`);
    process.stdout.write('load order      :\n');
    for (const file of MOD_FILES) {
        process.stdout.write(`  - ${verbose ? path.join(file.root, file.rel) : file.rel}\n`);
    }
    process.stdout.write('\n');

    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    installPrint(L);

    try {
        installPreloads(L);
        loadAndRun(L, MOCK_FILE, 'mock_env.lua');
        installRequire(L);
        // 加载被测文件之前的全局快照（断言 1 用）。放在 installRequire 之后：
        // 断言统计的是"模组文件多出来的全局"，不该把测试驱动自己的 helper 算进去。
        if (lauxlib.luaL_loadstring(L, to_luastring('MOCK.captureGlobals()')) !== lua.LUA_OK
                || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
            throw new Error(`captureGlobals: ${readLuaError(L)}`);
        }
        for (const file of MOD_FILES) {
            loadAndRun(L, path.join(file.root, file.rel), file.rel, file.module);
        }
        // 静态检查（不进 Lua VM 的业务，只把结果塞进 Config）
        const statics = installStaticKeys(L);
        process.stdout.write(`translation keys : ${statics.all.size} literal keys scanned from `
            + `${TRANSLATION_SOURCES.length} lua files; CN=${statics.translations.CN.size} EN=${statics.translations.EN.size}\n`);
        process.stdout.write(`sidebar icons    : ${Object.keys(statics.icons.verified).length} png verified`
            + ` (${SIDEBAR_SIZES.length} sizes x 2 states, RGBA + exact pixel size)\n`);
        process.stdout.write(`sandbox defaults : ${statics.sandboxOptions.length} options parsed from sandbox-options.txt `
            + `(CN=${statics.sandboxTranslations.CN.size} EN=${statics.sandboxTranslations.EN.size} sandbox keys)\n\n`);
    } catch (error) {
        die(`load failed: ${error.message}`);
    }

    if (lauxlib.luaL_loadfile(L, TEST_FILE) !== lua.LUA_OK) {
        die(`load ${path.basename(TEST_FILE)}: ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
        die(`test_recruit.lua crashed: ${readLuaError(L)}`);
    }

    const failures = lua.lua_gettop(L) >= 1 ? lua.lua_tonumber(L, -1) : 1;
    process.stdout.write(failures === 0 ? '\nALL PASS\n' : `\n${failures} FAILED\n`);
    process.exit(failures === 0 ? 0 : 1);
}

main();
