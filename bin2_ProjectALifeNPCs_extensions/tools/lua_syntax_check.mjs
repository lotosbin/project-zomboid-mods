#!/usr/bin/env node
/**
 * Lua 语法检查器（只编译不执行）
 *
 * 为什么需要：本机没有独立 Lua 解释器，但仓库里已有 fengari（纯 JS 的 Lua 5.3 VM，
 * 见 bin2_companion_alpaca/tools/test/node_modules/fengari），可以直接给 Lua 源码做语法校验。
 * 用途：改完 .lua 后立刻检查，避免把语法错误带进游戏（游戏的报错定位很差）。
 *
 * 用法：
 *   node tools/lua_syntax_check.mjs <文件或目录> [...]
 *   node tools/lua_syntax_check.mjs --quiet <目录>
 * 退出码：0 = 全部通过；1 = 有语法错误
 *
 * 注意：只做**语法**检查，不做语义/未定义全局检查（那需要真实游戏环境）。
 */
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';

const FENGARI_BASE = '/Volumes/StorageMacMini/liubinbin/Github/lotosbin/project-zomboid-mods/bin2_companion_alpaca/tools/test/';
const require = createRequire(FENGARI_BASE);
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const args = process.argv.slice(2);
const quiet = args.includes('--quiet');
const targets = args.filter((a) => a !== '--quiet');
if (targets.length === 0) {
  console.error('usage: node lua_syntax_check.mjs [--quiet] <file-or-dir> [...]');
  process.exit(2);
}

const files = [];
for (const t of targets) {
  if (fs.statSync(t).isDirectory()) {
    const walk = (d) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith('.lua')) files.push(p);
      }
    };
    walk(t);
  } else if (t.endsWith('.lua')) files.push(t);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let bad = 0;
for (const file of files.sort()) {
  const src = fs.readFileSync(file, 'utf8');
  const status = lauxlib.luaL_loadbuffer(L, to_luastring(src), src.length, to_luastring('@' + file));
  if (status === lua.LUA_OK) {
    if (!quiet) console.log('OK   ' + file);
  } else {
    bad++;
    console.error('FAIL ' + file + ' -> ' + to_jsstring(lua.lua_tostring(L, -1)).split('\n')[0]);
    lua.lua_pop(L, 1);
  }
}
console.log(`\nlua syntax: files=${files.length} failed=${bad}`);
process.exit(bad ? 1 : 0);
