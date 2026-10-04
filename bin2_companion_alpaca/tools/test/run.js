#!/usr/bin/env node
// ===========================================================================
// run.js —— 离线 Lua 集成测试的 fengari 驱动
// ===========================================================================
//
// 做什么：
//   1. 用 fengari（Lua 5.3 的 JS 实现）开一个全新的 Lua state，装上 Project Zomboid
//      的最小引擎桩（mock_base.lua 负责），模拟"游戏已经加载完 CompanionDogs base"；
//   2. 按引擎真实加载顺序 dofile 被测的 5 个 addon Lua 文件（shared -> client/server）；
//   3. 执行 test_alpaca.lua 的 11 条断言，用它的返回值当进程退出码。
//
// 另外暴露一个宿主函数 host_nil_base_probe()：**在另一个全新的 state 里**（没有 base）
// 把同样 5 个文件再加载一遍，用来验证"base 缺失时静默早退、不建全局"。断言 1 用它。
//
// 用法：node run.js            （通常由 run_lua_test.sh 调起）
//      node run.js --verbose  （把每个被测文件的实际路径也打出来）
'use strict';

const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

// ------------------------------------------------------------------ 路径
const MOD_VERSION_DIR = path.resolve(__dirname, '..', '..', 'Contents', 'mods', 'CompanionDogsAlpaca', '42');

// 引擎加载顺序：shared 先，client/server 最后（server 依赖 client 之前的一切）。
const ADDON_FILES = [
    'media/lua/shared/CompanionDogsAlpaca_Breed.lua',
    'media/lua/shared/Definitions/animal/AlpacaDefinitions.lua',
    'media/lua/shared/Definitions/animal/CompanionDogsAlpaca_Parts.lua',
    'media/lua/client/CompanionDogsAlpaca_Moodle.lua',
    'media/lua/server/CompanionDogsAlpaca_Climate.lua',
];

const MOCK_FILE = path.join(__dirname, 'mock_base.lua');
const TEST_FILE = path.join(__dirname, 'test_alpaca.lua');

// 断言 1 会检查：base 缺失时这些全局一个都不该被创建
const FORBIDDEN_GLOBALS = [
    'CompanionDogs',
    'CompanionDogsAlpaca',
    'AnimalDefinitions',
    'AnimalAvatarDefinition',
    'AnimalPartsDefinitions',
];

// ------------------------------------------------------------------ 小工具
function die(msg) {
    process.stderr.write(`[run] FATAL: ${msg}\n`);
    process.exit(2);
}

function readLuaError(L) {
    const msg = lua.lua_tostring(L, -1);
    return msg === null ? '(non-string lua error)' : to_jsstring(msg);
}

/** 覆写 print，保证与 JS 的 console 输出严格同序（fengari 默认 print 已同步，这里只是统一）。 */
function installPrint(L) {
    lua.lua_pushjsfunction(L, function (L) {
        const n = lua.lua_gettop(L);
        const parts = [];
        for (let i = 1; i <= n; i++) {
            let s;
            if (lua.lua_type(L, i) === lua.LUA_TSTRING) {
                s = to_jsstring(lua.lua_tostring(L, i));
            } else {
                // 用 Lua 自己的 tostring，保证表/函数/数字的打印与游戏日志一致
                lua.lua_getglobal(L, to_luastring('tostring'));
                lua.lua_pushvalue(L, i);
                if (lua.lua_pcall(L, 1, 1, 0) === lua.LUA_OK) {
                    s = to_jsstring(lua.lua_tostring(L, -1));
                } else {
                    s = '?';
                }
                lua.lua_pop(L, 1);
            }
            parts.push(s);
        }
        process.stdout.write(parts.join('\t') + '\n');
        return 0;
    });
    lua.lua_setglobal(L, to_luastring('print'));
}

/** loadfile + pcall，出错时抛出带文件名的可读错误。 */
function loadAndRun(L, file, label) {
    if (lauxlib.luaL_loadfile(L, file) !== lua.LUA_OK) {
        throw new Error(`load ${label} (${file}): ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`run ${label} (${file}): ${readLuaError(L)}`);
    }
}

// ------------------------------------------------------------------ 断言 1 的探针
/**
 * 在一个**全新、没有 base** 的 state 里按同样顺序加载 5 个 addon 文件：
 * 任何一笔报错、或任何被禁止的全局被创建，都要如实报出来。
 * @returns {boolean} ok
 * @returns {string} error
 * @returns {string} created 逗号分隔的"不该存在却存在了"的全局名
 */
function nilBaseProbe() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    let error = '';
    for (const rel of ADDON_FILES) {
        try {
            loadAndRun(L, path.join(MOD_VERSION_DIR, rel), rel);
        } catch (e) {
            error = e.message;
            break;
        }
    }

    let created = '';
    if (!error) {
        // 用 Lua 自己枚举全局，避免手写 lua_next 的索引错误
        const names = FORBIDDEN_GLOBALS.map((n) => `"${n}"`).join(', ');
        const code = `local names = { ${names} }
local out = {}
for i = 1, #names do
    if _G[names[i]] ~= nil then out[#out + 1] = names[i] end
end
return table.concat(out, ",")`;
        if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
            error = `probe chunk failed: ${readLuaError(L)}`;
        } else {
            created = to_jsstring(lua.lua_tostring(L, -1));
        }
    }
    return { ok: error === '', error, created };
}

/** 注册宿主函数 host_nil_base_probe()，把探针结果作为一个 Lua 表压回调用方 state。 */
function installHostFunctions(L) {
    lua.lua_pushjsfunction(L, function (L) {
        const probe = nilBaseProbe();
        lua.lua_newtable(L);
        lua.lua_pushboolean(L, probe.ok);
        lua.lua_setfield(L, -2, to_luastring('ok'));
        lua.lua_pushstring(L, to_luastring(probe.error));
        lua.lua_setfield(L, -2, to_luastring('error'));
        lua.lua_pushstring(L, to_luastring(probe.created));
        lua.lua_setfield(L, -2, to_luastring('created'));
        return 1;
    });
    lua.lua_setglobal(L, to_luastring('host_nil_base_probe'));
}

// ------------------------------------------------------------------ main
function main() {
    const verbose = process.argv.includes('--verbose');

    process.stdout.write('== CompanionDogsAlpaca offline Lua test (fengari / Lua 5.3) ==\n');
    process.stdout.write(`mod version dir : ${MOD_VERSION_DIR}\n`);
    process.stdout.write(`mock            : ${verbose ? MOCK_FILE : path.basename(MOCK_FILE)}\n`);
    process.stdout.write(`assertions      : ${verbose ? TEST_FILE : path.basename(TEST_FILE)}\n`);
    process.stdout.write('load order      :\n');
    for (const rel of ADDON_FILES) {
        process.stdout.write(`  - ${verbose ? path.join(MOD_VERSION_DIR, rel) : rel}\n`);
    }
    process.stdout.write('\n');

    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    installPrint(L);
    installHostFunctions(L);

    try {
        loadAndRun(L, MOCK_FILE, 'mock_base.lua');
        for (const rel of ADDON_FILES) loadAndRun(L, path.join(MOD_VERSION_DIR, rel), rel);
    } catch (e) {
        die(`addon did not load: ${e.message}`);
    }

    if (lauxlib.luaL_loadfile(L, TEST_FILE) !== lua.LUA_OK) {
        die(`load test_alpaca.lua: ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
        die(`test_alpaca.lua crashed: ${readLuaError(L)}`);
    }

    const failures = lua.lua_gettop(L) >= 1 ? lua.lua_tonumber(L, -1) : 1;
    process.exit(failures === 0 ? 0 : 1);
}

main();
