#!/usr/bin/env node
// ===========================================================================
// run_blocky.js —— CompanionDogsBlockyAlpaca 的离线 Lua 集成测试驱动
// ===========================================================================
//
// 与写实羊驼那套（../alpaca/test/run.js）同源，区别只在"被测文件"与"前置依赖"：
//   本 addon **不是新物种**，它的 Lua 依赖 CompanionDogsAlpaca 先注册 "alpaca" 物种，
//   所以加载顺序是：mock base -> 写实羊驼的 Breed+Definitions -> 方块羊驼的三个文件。
//
// 另外有一个 nil 依赖探针：在一个**全新 state**里只加载方块羊驼的文件（没有 base、
// 也没有物种提供者），要求它安静早退、不建全局、不报错。
//
// 用法：node run_blocky.js [--verbose]
'use strict';

const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const ROOT = path.resolve(__dirname, '..', '..', '..');           // 仓库根
const ALPACA_DIR = path.join(ROOT, 'bin2_companion_alpaca', 'Contents', 'mods', 'CompanionDogsAlpaca', '42');
const BLOCKY_DIR = path.join(ROOT, 'bin2_blocky_alpaca', 'Contents', 'mods', 'CompanionDogsBlockyAlpaca', '42');

// 前置：物种提供者（写实羊驼）的 shared 文件。Parts 也加载，顺便验证两者能共存。
const PROVIDER_FILES = [
    path.join(ALPACA_DIR, 'media/lua/shared/CompanionDogsAlpaca_Breed.lua'),
    path.join(ALPACA_DIR, 'media/lua/shared/Definitions/animal/AlpacaDefinitions.lua'),
    path.join(ALPACA_DIR, 'media/lua/shared/Definitions/animal/CompanionDogsAlpaca_Parts.lua'),
];

// 被测：方块羊驼的三个 shared 文件
const BLOCKY_FILES = [
    path.join(BLOCKY_DIR, 'media/lua/shared/CompanionDogsBlockyAlpaca_Breed.lua'),
    path.join(BLOCKY_DIR, 'media/lua/shared/Definitions/animal/BlockyAlpacaDefinitions.lua'),
    path.join(BLOCKY_DIR, 'media/lua/shared/Definitions/animal/CompanionDogsBlockyAlpaca_Parts.lua'),
];

const MOCK_FILE = path.join(ROOT, 'bin2_companion_alpaca', 'tools', 'test', 'mock_base.lua');
const TEST_FILE = path.join(__dirname, 'test_blocky.lua');

// 依赖缺失时不该出现的全局（探针用）
const FORBIDDEN_GLOBALS = [
    'CompanionDogs', 'CompanionDogsAlpaca', 'CompanionDogsBlockyAlpaca',
    'AnimalDefinitions', 'AnimalAvatarDefinition', 'AnimalPartsDefinitions',
];

function die(msg) {
    process.stderr.write(`[run_blocky] FATAL: ${msg}\n`);
    process.exit(2);
}

function readLuaError(L) {
    const msg = lua.lua_tostring(L, -1);
    return msg === null ? '(non-string lua error)' : to_jsstring(msg);
}

function installPrint(L) {
    lua.lua_pushjsfunction(L, function (L) {
        const n = lua.lua_gettop(L);
        const parts = [];
        for (let i = 1; i <= n; i++) {
            let s;
            if (lua.lua_type(L, i) === lua.LUA_TSTRING) {
                s = to_jsstring(lua.lua_tostring(L, i));
            } else {
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

function loadAndRun(L, file, label) {
    if (lauxlib.luaL_loadfile(L, file) !== lua.LUA_OK) {
        throw new Error(`load ${label} (${file}): ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        throw new Error(`run ${label} (${file}): ${readLuaError(L)}`);
    }
}

/** 只加载方块羊驼（无 base / 无物种提供者）：应当安静早退。 */
function nilDepsProbe() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    let error = '';
    for (const f of BLOCKY_FILES) {
        try {
            loadAndRun(L, f, path.basename(f));
        } catch (e) {
            error = e.message;
            break;
        }
    }
    let created = '';
    if (!error) {
        const names = FORBIDDEN_GLOBALS.map((n) => `"${n}"`).join(', ');
        const code = `local names = { ${names} }
local out = {}
for i = 1, #names do
    if _G[names[i]] ~= nil then out[#out + 1] = names[i] end
end
return table.concat(out, ",")`;
        if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK
            || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
            error = `probe chunk failed: ${readLuaError(L)}`;
        } else {
            created = to_jsstring(lua.lua_tostring(L, -1));
        }
    }
    return { ok: error === '', error, created };
}

function installHostFunctions(L) {
    lua.lua_pushjsfunction(L, function (L) {
        const probe = nilDepsProbe();
        lua.lua_newtable(L);
        lua.lua_pushboolean(L, probe.ok);
        lua.lua_setfield(L, -2, to_luastring('ok'));
        lua.lua_pushstring(L, to_luastring(probe.error));
        lua.lua_setfield(L, -2, to_luastring('error'));
        lua.lua_pushstring(L, to_luastring(probe.created));
        lua.lua_setfield(L, -2, to_luastring('created'));
        return 1;
    });
    lua.lua_setglobal(L, to_luastring('host_nil_deps_probe'));
}

function main() {
    const verbose = process.argv.includes('--verbose');
    process.stdout.write('== CompanionDogsBlockyAlpaca offline Lua test (fengari / Lua 5.3) ==\n');
    process.stdout.write(`blocky mod dir  : ${BLOCKY_DIR}\n`);
    process.stdout.write(`provider mod dir: ${ALPACA_DIR}\n`);
    process.stdout.write('load order      :\n');
    for (const f of PROVIDER_FILES) {
        process.stdout.write(`  - ${verbose ? f : 'provider/' + path.basename(f)}\n`);
    }
    for (const f of BLOCKY_FILES) {
        process.stdout.write(`  - ${verbose ? f : 'blocky/' + path.basename(f)}\n`);
    }
    process.stdout.write('\n');

    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    installPrint(L);
    installHostFunctions(L);

    try {
        loadAndRun(L, MOCK_FILE, 'mock_base.lua');
        for (const f of PROVIDER_FILES) loadAndRun(L, f, path.basename(f));
        for (const f of BLOCKY_FILES) loadAndRun(L, f, path.basename(f));
    } catch (e) {
        die(`addon did not load: ${e.message}`);
    }

    if (lauxlib.luaL_loadfile(L, TEST_FILE) !== lua.LUA_OK) {
        die(`load test_blocky.lua: ${readLuaError(L)}`);
    }
    if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
        die(`test_blocky.lua crashed: ${readLuaError(L)}`);
    }
    const failures = lua.lua_gettop(L) >= 1 ? lua.lua_tonumber(L, -1) : 1;
    process.exit(failures === 0 ? 0 : 1);
}

main();
