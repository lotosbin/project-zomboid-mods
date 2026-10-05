#!/usr/bin/env node
// ===========================================================================
// run.js —— Bin2NPCExtension 离线 Lua 集成测试的 fengari 驱动
// ===========================================================================
//
// 做什么：
//   1. 用 fengari（Lua 5.3 的 JS 实现）开一个全新的 Lua state，装上 Project Zomboid
//      的最小引擎桩 + 三个依赖的 mock（mock_env.lua 负责）；
//   2. 实现 **PZ 语义的 require**：media/lua/{client,shared,server} 作为搜索根，
//      "Bin2NPCExtension/Config" -> media/lua/<root>/Bin2NPCExtension/Config.lua；
//      同一文件只执行一次（package.loaded 缓存），并用 package.searchers 计数器证明；
//   3. 按引擎真实加载顺序（与任务书一致）dofile 被测的 14 个 Lua 文件；
//   4. 做一次**静态翻译检查**（不进 Lua VM）：扫源码里的 T("...") / Text.get("...")
//      字面量，断言 CN/EN 的 IG_UI.json 里都有对应键且键集合一致；
//   5. 执行 test_recruit.lua 的 30 条断言，用它的返回值当进程退出码。
//
// 用法：node run.js            （通常由 run_lua_test.sh 调起）
//      node run.js --verbose  （把每个被测文件的实际路径也打出来）
'use strict';

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

// ------------------------------------------------------------------ 路径
const TEST_DIR = __dirname;
const MOD_VERSION_DIR = path.resolve(TEST_DIR, '..', '..', 'Contents', 'mods', 'Bin2NPCExtension', '42.21');
const MEDIA_LUA_DIR = path.join(MOD_VERSION_DIR, 'media', 'lua');
const TRANSLATE_DIR = path.join(MEDIA_LUA_DIR, 'shared', 'Translate');
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

const MOD_FILES = [
    `${SHARED}/Bin2NPCExtension/Config.lua`,
    `${SHARED}/Bin2NPCExtension/Text.lua`,
    `${SHARED}/Bin2NPCExtension/Contracts.lua`,
    `${SERVER}/Bin2NPCExtension/Store.lua`,
    `${SERVER}/Bin2NPCExtension/Alife.lua`,
    `${SERVER}/Bin2NPCExtension/Jimmy.lua`,
    `${SERVER}/Bin2NPCExtension/Economy.lua`,
    `${SERVER}/Bin2NPCExtension/Service.lua`,
    `${SERVER}/Bin2NPCExtension/Maintain.lua`,
    `${SERVER}/Bin2NPCExtension/Bootstrap.lua`,
    `${CLIENT}/Bin2NPCExtension/Net.lua`,
    `${CLIENT}/Bin2NPCExtension/ui/Page.lua`,
    `${CLIENT}/Bin2NPCExtension/ui/Entry.lua`,
    `${CLIENT}/Bin2NPCExtension/Bootstrap.lua`,
];

// 每个被测文件在 require 世界里对应的模块名（两个 Bootstrap 在不同根目录下，名字相同，
// 所以这里显式列出而不是从路径推导）。
const REQUIRE_NAMES = [
    'Bin2NPCExtension/Config',
    'Bin2NPCExtension/Text',
    'Bin2NPCExtension/Contracts',
    'Bin2NPCExtension/Store',
    'Bin2NPCExtension/Alife',
    'Bin2NPCExtension/Jimmy',
    'Bin2NPCExtension/Economy',
    'Bin2NPCExtension/Service',
    'Bin2NPCExtension/Maintain',
    'Bin2NPCExtension/Bootstrap',
    'Bin2NPCExtension/Net',
    'Bin2NPCExtension/ui/Page',
    'Bin2NPCExtension/ui/Entry',
];

// 语言包
const LANGUAGES = ['CN', 'EN'];
const TRANSLATION_FILE = 'IG_UI.json';

// 静态翻译检查扫这些文件（这是任务书点名的清单）
const TRANSLATION_SOURCES = [
    `${CLIENT}/Bin2NPCExtension/ui/Page.lua`,
    `${SHARED}/Bin2NPCExtension/Text.lua`,
    `${CLIENT}/Bin2NPCExtension/ui/Entry.lua`,
    `${CLIENT}/Bin2NPCExtension/Net.lua`,
    `${SERVER}/Bin2NPCExtension/Jimmy.lua`,
    `${SERVER}/Bin2NPCExtension/Economy.lua`,
    `${SERVER}/Bin2NPCExtension/Service.lua`,
    `${SERVER}/Bin2NPCExtension/Maintain.lua`,
    `${SERVER}/Bin2NPCExtension/Alife.lua`,
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

function loadAndRun(L, file, label) {
    if (lauxlib.luaL_loadfile(L, file) !== lua.LUA_OK) {
        throw new Error(`load ${label} (${file}): ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`run ${label} (${file}): ${readLuaError(L)}`);
    }
}

// ------------------------------------------------------------------ PZ 风格 require
/**
 * 把 media/lua/{client,shared,server} 当搜索根，并统计每次 require 的调用次数。
 * 同一文件只执行一次由 package.loaded 保证（Lua 标准行为）。
 */
function installRequire(L) {
    const roots = [CLIENT, SHARED, SERVER];   // 客户端优先：ui/page_registry 这类通用名归客户端
    const setup = `
local MOCK = MOCK
local roots = { ${roots.map((r) => `"${r}"`).join(', ')} }
local function missing(name)
    local tried = {}
    for _, root in ipairs(roots) do
        local file = "${MOD_VERSION_DIR}/" .. root .. "/" .. name .. ".lua"
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
    const MAPPING_TABLE_FILE = `${SHARED}/Bin2NPCExtension/Text.lua`;

    for (const relative of relativeFiles) {
        const absolute = path.join(MOD_VERSION_DIR, relative);
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
        if (relative === MAPPING_TABLE_FILE) {
            markers.push({ re: /(?:^|[\s,{])\w+\s*=\s*/gm, kind: 'mapping' });
        }
        for (const { re, kind } of markers) {
            re.lastIndex = 0;
            let match;
            while ((match = re.exec(code)) !== null) {
                const value = readStringAt(code, re.lastIndex);
                if (value === null || value === '') continue;
                if (NON_KEY_STRINGS[value] === true) continue;
                if (kind === 'call') {
                    callKeys.add(value);
                } else {
                    mappingKeys.add(value);
                }
                keys.push(value);
            }
        }
        perFile[relative] = keys;
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
        const prefix = 'IGUI_Bin2NPCExtension_';
        for (const full of Object.keys(parsed)) {
            if (typeof parsed[full] !== 'string' || parsed[full] === '') {
                die(`${language}: empty translation for ${full}`);
            }
            if (!full.startsWith(prefix)) die(`${language}: key without our prefix: ${full}`);
            keys.add(full.slice(prefix.length));
        }
        result[language] = keys;
    }
    return result;
}

/** 把收集到的键注入 Lua：Config.__sourceKeys / __cnKeys / __enKeys */
function installStaticKeys(L) {
    const scan = extractLiteralKeys(TRANSLATION_SOURCES);
    const translations = loadTranslations();
    const all = new Set([...scan.callKeys, ...scan.mappingKeys]);

    const luaArray = (values) => `{ ${[...values].sort().map((v) => `"${v}"`).join(', ')} }`;
    const luaSet = (values) => `{ ${[...values].map((v) => `["${v}"] = true`).join(', ')} }`;

    const code = `
Bin2NPCExtension = Bin2NPCExtension or {}
Bin2NPCExtension.__sourceKeys = ${luaArray(all)}
Bin2NPCExtension.__cnKeys = ${luaSet(translations.CN)}
Bin2NPCExtension.__enKeys = ${luaSet(translations.EN)}
Bin2NPCExtension.__loadedCount = ${MOD_FILES.length}
Bin2NPCExtension.__requireNames = ${luaArray(REQUIRE_NAMES)}
Bin2NPCExtension.__moduleFileCount = ${MOD_FILES.length}
`;
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`install static keys: ${readLuaError(L)}`);
    }
    return { scan, translations, all };
}

// ------------------------------------------------------------------ preload
/** Page.lua 的 require "ui/page_registry"：在游戏里加载的是橙子经济的真实文件，这里用 mock。 */
function installPreloads(L) {
    const code = `
-- 橙子经济的页面注册表：Page.lua 里 require "ui/page_registry" 在游戏里就是加载它，
-- 这里返回 mock_env.lua 里按真实源码复刻的那份注册表。
package.preload["ui/page_registry"] = function()
    return OrangeTradingMod.UIPageRegistry
end
package.preload["ui/theme"] = function()
    return { Colors = {}, Metrics = {} }
end
-- 引擎 UI 基类：mock_env.lua 里装的是同名全局桩
package.preload["ISUI/ISPanel"] = function() return ISPanel end
package.preload["ISUI/ISUIElement"] = function() return ISUIElement end
package.preload["ISUI/ISButton"] = function() return ISButton end
package.preload["ISUI/ISScrollingListBox"] = function() return ISScrollingListBox end
`;
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`install preloads: ${readLuaError(L)}`);
    }
}

// ------------------------------------------------------------------ main
function main() {
    const verbose = process.argv.includes('--verbose');

    process.stdout.write('== Bin2NPCExtension offline Lua test (fengari / Lua 5.3) ==\n');
    process.stdout.write(`mod version dir : ${MOD_VERSION_DIR}\n`);
    process.stdout.write(`fengari         : ${verbose ? fengariFrom : path.basename(fengariFrom)}\n`);
    process.stdout.write(`mock            : ${verbose ? MOCK_FILE : path.basename(MOCK_FILE)}\n`);
    process.stdout.write(`assertions      : ${verbose ? TEST_FILE : path.basename(TEST_FILE)}\n`);
    process.stdout.write('load order      :\n');
    for (const relative of MOD_FILES) {
        process.stdout.write(`  - ${verbose ? path.join(MOD_VERSION_DIR, relative) : relative}\n`);
    }
    process.stdout.write('\n');

    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    installPrint(L);

    try {
        installPreloads(L);
        loadAndRun(L, MOCK_FILE, 'mock_env.lua');
        // 加载被测文件之前的全局快照（断言 1 用）
        if (lauxlib.luaL_loadstring(L, to_luastring('MOCK.captureGlobals()')) !== lua.LUA_OK
                || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
            throw new Error(`captureGlobals: ${readLuaError(L)}`);
        }
        installRequire(L);
        for (const relative of MOD_FILES) {
            loadAndRun(L, path.join(MOD_VERSION_DIR, relative), relative);
        }
        // 静态翻译检查（不进 Lua VM 的业务，只把结果塞进 Config）
        const statics = installStaticKeys(L);
        process.stdout.write(`translation keys : ${statics.all.size} literal keys scanned from `
            + `${TRANSLATION_SOURCES.length} lua files; CN=${statics.translations.CN.size} EN=${statics.translations.EN.size}\n\n`);
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
