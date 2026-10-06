-- ===========================================================================
-- test_recruit.lua —— Bin2NPCExtensionVanilla 的离线集成断言
--                     （原版钞票结算 Base.Money + 左侧侧边栏图标入口）
-- ===========================================================================
--
-- 环境由 run.js + mock_env.lua 准备好：
--   * MOCK        —— 引擎桩 / A-Life + Jeem + **原版物品栏 + 原版 ISUI/侧边栏** mock /
--                    调用记录 / 时间推进 / 断言框架
--   * Bin2NPCExtensionVanilla / Bin2NPCExtensionCore / ProjectALife / ProjectALifeJimmy
--     —— 被测的 19 个文件（公共层 14 + 本口味 5）跑完后的产物
--   * Config.__iconFiles / __sandboxDefaults —— run.js 从**磁盘与 sandbox-options.txt**
--     静态校验/解析出来的真值（图标 5 档 × 2 态、沙盒 14 个选项的默认值）
--
-- 50 条用例，分五段：
--   A 1-5    装载与身份（19 文件 / 18 require 名 / spec / sibling / 公共层守卫）
--   B 6-28   钱的算术（balance / pay / refund / 发包 / wage / 端到端）
--   C 29-38  左侧侧边栏图标入口（hook / 位置 / 尺寸 / 贴图 / 点击 / 热键兜底）
--   D 39-47  招募窗口（命令 / 列表 / revision / close）
--   E 48-50  翻译与沙盒静态检查
--
-- 返回失败条数（run.js 用它当退出码：0 = ALL PASS）。
-- ===========================================================================

local M = MOCK

-- ---------------------------------------------------------------- 被测对象
local Config = Bin2NPCExtensionVanilla
local Core = Bin2NPCExtensionCore
local Contracts = Config.Contracts
local Store = Config.Store
local Service = Config.Service
local Alife = Config.Alife
local Jimmy = Config.Jimmy
local Net = Config.Net
local Cash = Config.Economy
local Panel = Config.RecruitPanel
local Icon = Config.Entry

--[[
    窗口类从 `Panel.Window` 拿：Panel.lua 里的两个 UI 类都是 `local`（不会漏进 _G），
    UI 模块表把它们挂出来给测试与排障用 —— 这条本身就是 A1 用例在守的不变量。
]]
local WindowClass = Panel.Window

-- 用例总数：runTest 会把它当断言前缀用，新增用例时同步改这一个数字
local TOTAL = 50
local failures = 0
local passed = 0

local function runTest(index, name, fn)
    local test = M.next_test(TOTAL, name)
    M.setNowMs(M.state.nowMs + 10000)          -- 让 Service 的 400ms / 60s 限速窗口过期
    local ok, err = pcall(fn)
    if not ok then
        -- 测试体自己抛出的 Lua 错误一律算失败：绝不把崩溃当成"通过"
        test.problems[#test.problems + 1] = "lua error: " .. tostring(err)
    end
    if M.finish_test(index) then
        passed = passed + 1
    else
        failures = failures + 1
    end
end

--[[
    Service.dispatch 的返回契约有两种形态：
      * 走到 Service.push 的分支 -> payload 表（payload.result.code）
      * 早退的失败分支 -> 裸字符串 code（结果记在 Service 内部的 lastResult，
        下一次 RequestState 才会通过 payload.result 露出来）
    这里两种都接受，但"必须是这两种之一"。
]]
local function resultCode(reply)
    if type(reply) == "table" then return reply.result and reply.result.code or nil end
    if type(reply) == "string" then return reply end
    return nil
end

local MUTATING = {
    HireExisting = true, HireSpawned = true, SetMode = true, Dismiss = true,
}

-- 测试里的命令入口：改状态命令之间自动推进时间，避免撞上 Service 的 400ms 防连点
local function d(player, command, args)
    if player ~= nil and MUTATING[command] == true then M.advanceMs(10000) end
    return Service.dispatch(player, command, args)
end

--- 全局唯一的 requestId：Service 的重放窗口是 60 秒，整个进程内不能重复用同一个 id
local requestSeq = 0
local function U(label)
    requestSeq = requestSeq + 1
    return tostring(label) .. "#" .. tostring(requestSeq)
end

-- 沙盒真值（来自 media/sandbox-options.txt，run.js 注入）
local SANDBOX = M.sandboxDefaults()
local SIGN = SANDBOX.SignPrice
local SPAWN = SANDBOX.SpawnPrice
local DAILY_WAGE = SANDBOX.DailyWage

local CN_KEYS = Config.__cnKeys or {}
local EN_KEYS = Config.__enKeys or {}
local CN_SANDBOX = Config.__cnSandboxKeys or {}
local EN_SANDBOX = Config.__enSandboxKeys or {}

-- 每个 test 开头的干净状态：保留依赖全局，清掉 A-Life / 存档 / 调用记录 / 物品栏 / UI
local function resetWorld(options)
    options = options or {}
    local previousNow = M.state.nowMs
    -- 先把上一轮开着的窗口关掉（单例挂在全局类表上，不跟着 MOCK.state 走）
    if WindowClass ~= nil and WindowClass.instance ~= nil then WindowClass.instance:close() end
    M.reset({ keepSandbox = true })
    M.setSandboxMissing(false)
    M.setSandboxTableMissing(false)
    -- 沙盒选项回到**随包发布的默认值**（media/sandbox-options.txt），不是公共层兜底值
    for key, value in pairs(M.sandboxDefaults()) do M.setSandbox(key, value) end
    if options.sandbox then
        for key, value in pairs(options.sandbox) do M.setSandbox(key, value) end
    end
    M.clearModData()
    M.__spawnFailure = nil          -- 造人失败注入不能跨用例泄漏
    M.setClient(false)
    M.setServer(false)
    -- 时钟必须单调前进：Service 的 lastCommandAt / seenRequests 是模块级 local
    M.setNowMs(math.max(previousNow, M.state.nowMs) + 60000)
    M.player:setPosition(100, 100, 0)
    M.state.uiElements = {}
    M.state.playerData = {}
    -- Net.cache 是模块级表：换一张新的，让 revision 从 0 重新数
    Net.cache = {
        contracts = {}, capabilities = {}, limits = { max = 0, used = 0 },
        prices = { sign = 0, spawn = 0, wage = 0 }, coins = 0, candidates = nil,
    }
    Net.resultSeq = nil
    return M
end

--[[
    临时包一层 Net.send，把"客户端到底发了哪条命令"记下来。

    为什么需要：单机下 Net.send 直接调 Service.dispatch，**不走 sendClientCommand**，
    引擎层面没有别的可观测点。
]]
local function spySend(fn)
    local sent = {}
    local realSend = Net.send
    Net.send = function(command, args, mutating)
        sent[#sent + 1] = { command = tostring(command), args = args, mutating = mutating == true }
        return realSend(command, args, mutating)
    end
    local ok, err = pcall(fn)
    Net.send = realSend
    if not ok then error(err, 0) end
    return sent
end

--[[
    窗口的"发命令/列表"用例统一跑在**联机客户端**模式下：
    单机下 Net.send 会真的在本地跑一遍 Service.dispatch，服务端推回来的状态会立刻覆盖
    测试手工摆好的 Net.cache —— 而列表用例正是靠 Net.cache 摆数据。
    联机客户端下 Net.send 只发 sendClientCommand，观察到的是真实的网络命令。
]]
local function asClient(fn)
    M.setClient(true)
    local ok, err = pcall(fn)
    M.setClient(false)
    if not ok then error(err, 0) end
end

local function clientCommands(name)
    local out = {}
    for _, call in ipairs(M.calls_named("sendClientCommand")) do
        if name == nil or call.command == name then out[#out + 1] = call end
    end
    return out
end

local function lastCommand()
    local all = M.calls_named("sendClientCommand")
    return all[#all]
end

--- 侧边栏面板上属于我们的图标有几个（正常情况下 0 或 1）
local function countIcons(panel)
    local total = 0
    for _, child in ipairs(panel:getChildren()) do
        if child.internal == "BIN2NPCRECRUIT" then total = total + 1 end
    end
    return total
end

-- ===========================================================================
-- A. 装载与身份
-- ===========================================================================
runTest(1, "loader: 19 files (public 14 + flavour 5), 18 require names, no file read twice, expected globals", function()
    M.assert_eq(Config.__loadedCount, 19, "loaded file count")
    M.assert_eq(Config.__moduleFileCount, 19, "module file count")
    M.assert_eq(Config.MODULE, "Bin2NPCExtensionVanilla", "Config.MODULE")
    M.assert_eq(Bin2NPCExtensionVanilla, Config, "the global is the namespace table")
    M.assert_truthy(type(Config.SPEC) == "table" and Config.SPEC.module == Config.MODULE,
        "the namespace carries the spec that built it (for troubleshooting)")

    -- 公共层把它自己按依赖顺序绑到了本口味的命名空间上（Namespace.bind）
    for _, name in ipairs({ "Text", "Contracts", "Store", "Economy", "Alife", "Jimmy",
        "Service", "Maintain", "Net", "ServerBootstrap", "ClientBootstrap" }) do
        M.assert_truthy(type(Config[name]) == "table", "public-layer module bound: " .. name)
    end
    M.assert_truthy(type(Config.RecruitPanel) == "table", "client ui/Panel ran")
    M.assert_truthy(type(Config.Entry) == "table", "client ui/Icon ran")
    M.assert_eq(#Config.__requireNames, 18, "18 distinct require names for 19 files")
    M.assert_eq(#Config.__coreModules, 14, "14 modules in the public layer")

    -- 自动加载已经把 19 个文件都跑完了，所以**没有任何** require 需要让 searcher 去读盘。
    -- 这一条同时守住两件事：文件只执行一次（引擎的真实语义），以及没有写错的模块名。
    local reloaded = {}
    for _, name in ipairs(Config.__requireNames) do
        local count = M.requireCounts[name] or 0
        if count > 0 then reloaded[#reloaded + 1] = name .. "=" .. tostring(count) end
    end
    M.assert_eq(#reloaded, 0, "modules that had to be read from disk again: " .. table.concat(reloaded, ", "))

    -- 兼容自检在加载期就跑过一次，而且是只读的
    M.assert_truthy(M.count_calls("foreignCopies") >= 1,
        "the compat self-check ran at load time and called ModCompat.foreignCopies")
    M.assert_falsy(ProjectALife.ModCompat.known["Bin2NPCExtensionVanilla"] ~= nil,
        "this mod must NOT write itself into ProjectALife.ModCompat.known")

    --[[
        只多出预期全局：`Bin2NPCExtensionVanilla`（口味命名空间）与 `Bin2NPCExtensionCore`
        （公共层注册表）。

        这条曾经是红的：Panel.lua 里 `Bin2NpcRecruitList` / `Bin2NpcRecruitWindow` 两个 UI 类名
        忘了写 `local`，直接漏进 _G（第三方模组可以撞名）。现在两个类都是 local，并挂在
        `Panel.RecruitList` / `Panel.Window` 上给测试与排障用 —— 所以这里既要断言"没有多余全局"，
        也要断言"从 Panel 上仍然拿得到"。
    ]]
    local allowed = { Bin2NPCExtensionVanilla = true, Bin2NPCExtensionCore = true }
    local unexpected = {}
    for _, name in ipairs(M.newGlobals()) do
        if allowed[name] ~= true then unexpected[#unexpected + 1] = name end
    end
    table.sort(unexpected)
    M.assert_eq(table.concat(unexpected, ","), "",
        "the only new globals are the flavour namespace and the public-layer registry")
    M.assert_truthy(rawget(_G, "Bin2NpcRecruitList") == nil, "the list class is local (not a global)")
    M.assert_truthy(rawget(_G, "Bin2NpcRecruitWindow") == nil, "the window class is local (not a global)")
    M.assert_truthy(WindowClass ~= nil and WindowClass.instance == nil,
        "the window class is reachable through Panel.Window")
    M.assert_truthy(Panel.RecruitList ~= nil, "the list class is reachable through Panel.RecruitList")
end)

runTest(2, "loader: a second require hits package.loaded, and install() is idempotent", function()
    resetWorld()
    local profile = require "Bin2NPCExtensionVanilla/Profile"
    M.assert_truthy(profile == Config, "require Profile returns the very same namespace table")
    local coreContracts = require "Bin2NPCExtensionCore/Contracts"
    M.assert_eq(type(coreContracts), "function", "公共层模块导出的是工厂函数")
    M.assert_truthy(require("Bin2NPCExtensionCore/Contracts") == coreContracts,
        "a second require returns the very same factory (package.loaded hit)")
    M.assert_truthy(require("Bin2NPCExtensionVanilla/ui/Panel") == Panel, "require ui/Panel is the same table")
    M.assert_truthy(require("Bin2NPCExtensionVanilla/ui/Icon") == Icon, "require ui/Icon is the same table")
    M.assert_eq(M.requireCounts["Bin2NPCExtensionVanilla/Profile"] or 0, 0,
        "…and the custom searcher was never consulted")

    --[[
        幂等判据在**工厂**里（ClientBootstrap.lua:34 / ServerBootstrap.lua:39 比较 Events 表的身份），
        所以再调一次工厂只会拿回同一张表，不会重复注册事件。
    ]]
    local ticks = M.handler_count("OnTick")
    local commands = M.handler_count("OnClientCommand")
    local keys = M.handler_count("OnKeyPressed")
    M.assert_truthy(require("Bin2NPCExtensionCore/ServerBootstrap")(Config) == Config.ServerBootstrap,
        "re-invoking the ServerBootstrap factory returns the very same table")
    M.assert_truthy(require("Bin2NPCExtensionCore/ClientBootstrap")(Config) == Config.ClientBootstrap,
        "…and the same for ClientBootstrap")
    M.assert_eq(M.handler_count("OnTick"), ticks, "…and re-invoking the factory registers nothing")

    --[[
        install() 自身也必须幂等。

        工厂里那道判据只保证"同一个 NS 不会被建两次"，挡不住"install 被调两次"：引擎的
        "Reset Lua" 会重跑所有 Lua 文件，口味的 client/server Bootstrap.lua 会再调一次 install。
        没有这道闸，OnTick 会注册两遍（Maintain 每帧跑两次）、Ctrl+Alt+N 会"开了又关"。
        公共层现在在 install() 开头比较 Events 表的身份（与工厂同一判据），所以这里应当
        **一条处理器都不多**。
    ]]
    Config.ClientBootstrap.install()
    Config.ServerBootstrap.install()
    M.assert_eq(M.handler_count("OnTick"), ticks, "a second install() registers no extra OnTick")
    M.assert_eq(M.handler_count("OnClientCommand"), commands, "…nor OnClientCommand")
    M.assert_eq(M.handler_count("OnKeyPressed"), keys, "…nor OnKeyPressed")
    M.assert_eq(M.handler_count("OnGameStart"), M.handler_count("OnGameStart"),
        "…and the count is stable across a repeat call")
end)

runTest(3, "profile: spec identity (MODULE / VERSION / coreApi=2 / money=cash / TAG / TABLE / prefixes)", function()
    M.assert_eq(Config.MODULE, "Bin2NPCExtensionVanilla", "MODULE")
    M.assert_eq(Config.VERSION, "0.4.0", "VERSION")
    M.assert_eq(Config.SPEC.coreApi, 2, "spec.coreApi")
    M.assert_eq(Core.API, 2, "Core.API")
    M.assert_eq(Config.SPEC.money, "cash", "spec.money")
    M.assert_eq(Config.MONEY_KIND, "cash", "the bound MONEY_KIND")
    M.assert_eq(Core.MONEY_PROVIDERS.cash, "Cash", "cash -> Cash.lua")
    M.assert_eq(Core.MONEY_PROVIDERS.upstream, "Economy", "upstream -> Economy.lua")
    M.assert_eq(Config.TAG, "Bin2NPCExtensionVanilla.Contracts.v1", "TAG (own save table)")
    M.assert_eq(Config.TABLE, "Bin2NPCExtensionVanilla", "sandbox TABLE (own options)")
    M.assert_eq(Config.TEXT_PREFIX, "IGUI_Bin2NPCExtensionVanilla_", "TEXT_PREFIX")
    M.assert_eq(Config.PLAYER_PREFIX, "Bin2NPCExtensionVanillaPlayer_", "PLAYER_PREFIX")
    M.assert_eq(Config.FLOW_ITEM, "Bin2NPCExtensionVanilla.contract", "FLOW_ITEM")
    M.assert_eq(Config.SCHEMA, 1, "SCHEMA")
    M.assert_eq(Config.SPEC.currencyName, "钞票", "currencyName")
    M.assert_truthy(type(Config.UI_HINT) == "string" and Config.UI_HINT ~= "",
        "the flavour ships a diagnostic hint for the client entry")
    M.assert_contains(Config.UI_HINT, "ISEquippedItem", "…and it names the vanilla sidebar")

    -- 绑上来的"钱"必须真的是 Cash.lua：Economy.lua 的实现没有 ITEM / BUNDLE 这两个字段
    M.assert_truthy(Config.Economy == Cash, "Config.Economy is the bound provider")
    M.assert_eq(Cash.ITEM, "Base.Money", "cash knows the vanilla note")
    M.assert_eq(Cash.BUNDLE, "Base.MoneyBundle", "cash knows the bundle")
    M.assert_eq(Cash.BUNDLE_VALUE, 100, "one bundle = 100 notes (craftRecipe UnbundleMoney)")
    M.assert_eq(Cash.available(), true, "cash needs no upstream economy mod")
    M.assert_eq(type(Cash.ITEM), "string", "…so this provider is not Economy.lua")
    M.assert_eq(Cash.flow(nil, "out", "npc_hire", "FlowHire", 10), false,
        "cash has no ledger: flow() honestly reports \"not recorded\"")
end)

runTest(4, "profile: SIBLING_MODULES lists exactly the other two flavours (no self, no collision)", function()
    local siblings = Config.SIBLING_MODULES
    M.assert_eq(#siblings, 2, "two siblings")
    M.assert_eq(siblings[1], "Bin2NPCExtension", "sibling 1 = the orange community economy flavour")
    M.assert_eq(siblings[2], "Bin2NPCExtensionYese", "sibling 2 = the YeseMarket flavour")
    M.assert_eq(Config.SIBLING_MODULE, "Bin2NPCExtension", "SIBLING_MODULE keeps the first id")
    for _, id in ipairs(siblings) do
        M.assert_truthy(id ~= Config.MODULE,
            "a sibling never points at this mod itself (the historical bug): " .. tostring(id))
    end
    -- 身份字段是本口味自己的：与另外两个口味撞车 = 串档 / 覆盖对方沙盒选项
    for _, other in ipairs({ "Bin2NPCExtension", "Bin2NPCExtensionYese" }) do
        M.assert_truthy(Config.TAG ~= other .. ".Contracts.v1", "TAG must not collide with " .. other)
        M.assert_truthy(Config.TABLE ~= other, "sandbox TABLE must not collide with " .. other)
        M.assert_truthy(Config.TEXT_PREFIX ~= "IGUI_" .. other .. "_", "TEXT_PREFIX vs " .. other)
        M.assert_truthy(Config.PLAYER_PREFIX ~= other .. "Player_", "PLAYER_PREFIX vs " .. other)
        M.assert_truthy(Config.FLOW_ITEM ~= other .. ".contract", "FLOW_ITEM vs " .. other)
    end
    M.assert_contains(Config.TABLE, "Bin2NPCExtensionVanilla", "the sandbox table carries this flavour's name")
end)

runTest(5, "public layer: namespace() refuses coreApi / money mismatches and normalizes siblings", function()
    M.assert_eq(Core.namespace({ module = "Probe", coreApi = 999 }), nil, "coreApi mismatch -> refuse")
    M.assert_eq(Core.namespace({}), nil, "missing module -> refuse")
    M.assert_eq(Core.namespace({ module = "Probe", coreApi = Core.API, money = "bitcoin" }), nil,
        "unknown money provider -> refuse (never silently degrade to \"no economy mod\")")
    M.assert_eq(Core.moneyProviderNames(), "cash, upstream", "the provider list is sorted and complete")
    local ns = Core.namespace({ module = "Probe", coreApi = Core.API })
    M.assert_eq(ns.MONEY_KIND, "upstream", "money defaults to the upstream economy mod")
    M.assert_eq(ns.TAG, "Probe.Contracts.v1", "TAG has a default")
    M.assert_eq(ns.TEXT_PREFIX, "IGUI_Probe_", "TEXT_PREFIX has a default")
    M.assert_eq(#ns.SIBLING_MODULES, 0, "no sibling -> empty list")
    local selfRef = Core.namespace({ module = "Probe", coreApi = Core.API, sibling = { "Other", "Probe" } })
    M.assert_eq(#selfRef.SIBLING_MODULES, 1, "a self-referencing sibling is dropped")
    M.assert_eq(selfRef.SIBLING_MODULES[1], "Other", "…keeping the order of the rest")
end)

-- ===========================================================================
-- B. 钱的算术（原版钞票）
-- ===========================================================================
runTest(6, "inventory mock: B42 has no stacking — one instance is one unit and getCount means nothing", function()
    resetWorld()
    local notes = M.giveNotes(3)
    M.assert_eq(#notes, 3, "three note instances")
    M.assert_eq(notes[1]:CanStack(), false, "CanStack() is false (engine: iconst_0; ireturn)")
    M.assert_eq(notes[1]:getCount(), 1, "count is 1")
    -- 就算有人调 setCount（引擎里这只是字段写：不入档、不同步），计数也不会变
    notes[1]:setCount(50)
    M.assert_eq(notes[1]:getCount(), 50, "setCount() did write the local field…")
    M.assert_eq(M.pocketValue(), 3, "…but counting is by instance, never by getCount")
    M.assert_eq(Cash.balance(M.player), 3, "balance counts instances")
    M.assert_eq(M.moneyValue(), 3, "the test's own ledger agrees")
end)

runTest(7, "cash.balance: notes only (and an empty inventory is 0, not nil)", function()
    resetWorld()
    M.assert_eq(Cash.balance(M.player), 0, "empty inventory -> 0")
    M.giveNotes(7)
    M.assert_eq(Cash.balance(M.player), 7, "7 notes -> 7")
    M.assert_eq(Cash.balance(M.player), M.moneyValue(), "matches the test's independent ledger")
    M.inv.main(M.player):AddItem("Base.Hammer")
    M.assert_eq(Cash.balance(M.player), 7, "a hammer is not money")
    M.assert_eq(Cash.balance({}), nil, "a player without getInventory() reads as nil, not 0")
end)

runTest(8, "cash.balance: notes + bundles (one bundle = 100)", function()
    resetWorld()
    M.giveNotes(7)
    M.giveBundles(2)
    M.assert_eq(Cash.balance(M.player), 207, "7 + 2*100")
    M.assert_eq(M.pocketValue(), 207, "the engine-level recursion agrees")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 2, "two bundle instances")
    M.assert_eq(#M.instances("Base.Money"), 7, "seven note instances")
end)

runTest(9, "cash.balance: money in a sub-container (a wallet inside the backpack) is counted", function()
    resetWorld()
    local pack = M.backpack(0)
    M.inv.put(M.inv.main(M.player), pack)
    local wallet = M.wallet(3, pack:getInventory())      -- 钱包在背包里，背包在主背包里
    M.assert_eq(wallet:getInventory():getCountType("Base.Money"), 3, "the wallet really holds 3 notes")
    M.assert_eq(M.inv.main(M.player):getCountType("Base.Money"), 0, "…but not directly in the main inventory")
    M.assert_eq(M.inv.main(M.player):getCountTypeRecurse("Base.Money"), 3, "the engine-level call recurses")
    M.assert_eq(Cash.balance(M.player), 3, "balance reaches into the wallet")
    M.assert_eq(M.moneyValue(), 3, "the test's own ledger agrees")
end)

runTest(10, "cash.balance: money in a WORN container (setWornItem already detached it from the inventory)", function()
    resetWorld()
    M.giveNotes(4)                                        -- 散钞留在主背包
    local pack = M.backpack(0)
    M.addItems(pack:getInventory(), "Base.Money", 5)      -- 背包里 5 张
    M.inv.put(M.inv.main(M.player), pack)                 -- 先放进主背包
    M.assert_eq(Cash.balance(M.player), 9, "bag still in the inventory: 4 + 5")
    M.inv.wear(M.player, "back", pack)                    -- 穿上：引擎会把它从主背包里 Remove 掉
    -- 先证明"陷阱"是真的：引擎口径的递归**已经看不到**那 5 张
    M.assert_eq(M.inv.main(M.player):getCountTypeRecurse("Base.Money"), 4,
        "the mock really detached the worn bag from the main inventory")
    M.assert_eq(M.pocketValue(), 4, "…so the main-inventory-only ledger says 4")
    M.assert_eq(#M.instances("Base.Money"), 9, "the notes are still on the player (inside the worn bag)")
    M.assert_eq(Cash.balance(M.player), 9,
        "balance must walk worn containers (BodyLocations + getWornItems + loc:getId())")
    M.assert_eq(M.moneyValue(), 9, "the test's own ledger agrees")
end)

runTest(11, "cash.balance/pay: money ONLY inside a worn container is still spendable", function()
    resetWorld()
    M.wearBackpack(6)
    M.assert_eq(M.pocketValue(), 0, "the main inventory sees nothing")
    M.assert_eq(#M.instances("Base.Money"), 6, "…but the notes are on the player")
    M.assert_eq(Cash.balance(M.player), 6, "balance sees the worn backpack")
    M.assert_eq(Cash.pay(M.player, 6), true, "and it can be spent")
    M.assert_eq(M.moneyValue(), 0, "paid in full")
    local sends = M.calls_named("sendRemoveItemsFromContainer")
    M.assert_eq(#sends, 1, "one remove batch")
    M.assert_truthy(sends[1].container ~= M.inv.main(M.player),
        "the packet names the WORN container, not the main inventory")
    M.assert_eq(M.count_calls("sendAddItemsToContainer"), 0, "no change (exact amount)")
end)

runTest(12, "cash.pay: exact notes — deletes exactly N instances and sends one remove batch", function()
    resetWorld()
    local notes = M.giveNotes(10)
    M.assert_eq(#notes, 10, "10 notes")
    M.assert_eq(Cash.pay(M.player, 6), true, "payment succeeds")
    M.assert_eq(M.moneyValue(), 4, "10 - 6")
    M.assert_eq(#M.instances("Base.Money"), 4, "four notes left")
    M.assert_eq(M.count_calls("sendAddItemsToContainer"), 0, "no change was handed out")
    M.assert_eq(M.count_calls("sendAddItemToContainer"), 0, "…and no singular add either")
    local sends = M.calls_named("sendRemoveItemsFromContainer")
    M.assert_eq(#sends, 1, "exactly one remove batch")
    M.assert_truthy(sends[1].container == M.inv.main(M.player), "the packet names the container it took from")
    M.assert_eq(sends[1].items:size(), 6, "and carries the 6 deleted notes")
    local kept = {}
    for _, note in ipairs(M.instances("Base.Money")) do kept[note.__serial] = true end
    for index = 0, sends[1].items:size() - 1 do
        local sent = sends[1].items:get(index)
        M.assert_eq(kept[sent.__serial], nil, "the packet item is really gone (not a copy)")
        M.assert_truthy(sent.__container == nil, "…and detach cleared its container (engine: Remove sets null)")
    end
    M.assert_truthy(M.count_calls("RemoveAll") >= 1, "the deletion went through ItemContainer.RemoveAll")
end)

runTest(13, "cash.pay: not enough notes — break ONE bundle and hand back the change", function()
    resetWorld()
    M.giveNotes(3)
    M.giveBundles(2)
    local before = M.moneyValue()
    M.assert_eq(before, 203, "3 + 2*100")
    M.assert_eq(Cash.pay(M.player, 30), true, "payment succeeds")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 1, "exactly one bundle was broken")
    M.assert_eq(#M.instances("Base.Money"), 73, "100 - (30 - 3) = 73 notes of change")
    M.assert_eq(M.moneyValue(), 173, "203 - 30")
    M.assert_eq(before - M.moneyValue(), 30, "the net change is exactly the price")
    local removes = M.calls_named("sendRemoveItemsFromContainer")
    M.assert_eq(#removes, 2, "two remove batches: the 3 notes, then the 1 bundle")
    M.assert_eq(removes[1].items:size(), 3, "first batch = the 3 notes")
    M.assert_eq(removes[2].items:size(), 1, "second batch = the broken bundle")
    local adds = M.calls_named("sendAddItemsToContainer")
    M.assert_eq(#adds, 1, "one add batch: the change")
    M.assert_truthy(adds[1].container == M.inv.main(M.player), "the change goes into the main inventory")
    M.assert_eq(adds[1].items:size(), 73, "73 notes of change")
end)

runTest(14, "cash.pay: an exact bundle — no change is created", function()
    resetWorld()
    M.giveBundles(2)
    M.assert_eq(Cash.pay(M.player, 100), true, "payment succeeds")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 1, "one bundle spent")
    M.assert_eq(#M.instances("Base.Money"), 0, "no change for an exact amount")
    M.assert_eq(M.count_calls("sendAddItemsToContainer"), 0, "…and nothing was added")
    M.assert_eq(M.moneyValue(), 100, "200 - 100")
end)

runTest(15, "cash.pay: three bundles for 250 — taken one by one, 50 change", function()
    resetWorld()
    M.giveBundles(3)
    M.assert_eq(Cash.pay(M.player, 250), true, "payment succeeds")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 0, "all three bundles were broken")
    M.assert_eq(#M.instances("Base.Money"), 50, "300 - 250 = 50 change")
    M.assert_eq(M.moneyValue(), 50, "300 - 250")
    local removes = M.calls_named("sendRemoveItemsFromContainer")
    M.assert_eq(#removes, 3, "bundles are removed one at a time (one packet each)")
    M.assert_eq(removes[1].items:size(), 1, "each batch is a single bundle")
    M.assert_eq(M.calls_named("sendAddItemsToContainer")[1].items:size(), 50, "50 notes of change")
end)

runTest(16, "cash.pay: notes are spent before bundles (never break a bundle while notes are left)", function()
    resetWorld()
    M.giveNotes(3)
    M.giveBundles(1)
    M.assert_eq(Cash.pay(M.player, 3), true, "payment succeeds")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 1, "the bundle is untouched")
    M.assert_eq(#M.instances("Base.Money"), 0, "the 3 notes paid it exactly")
    M.assert_eq(M.count_calls("sendRemoveItemsFromContainer"), 1, "one batch only")
    M.assert_eq(M.moneyValue(), 100, "103 - 3")
end)

runTest(17, "cash.pay: not enough money — false/no_funds and NOT ONE item is touched", function()
    resetWorld()
    M.giveNotes(5)
    M.giveBundles(1)                       -- 105 < 500
    local before = M.snapshot()
    local ok, why = Cash.pay(M.player, 500)
    M.assert_eq(ok, false, "payment fails")
    M.assert_eq(why, "no_funds", "with the translatable reason key")
    M.assert_eq(M.snapshot(), before, "the instance-by-instance snapshot is unchanged")
    M.assert_eq(M.moneyValue(), 105, "balance unchanged")
    M.assert_eq(M.count_calls("RemoveAll"), 0, "no container was even asked to remove")
    M.assert_eq(M.count_calls("sendRemoveItemsFromContainer"), 0, "nothing was synced (nothing happened)")
    M.assert_eq(M.count_calls("sendAddItemsToContainer"), 0, "…and nothing was added")
end)

runTest(18, "cash.pay: a price <= 0 is a no-op success; a missing player is no_economy", function()
    resetWorld()
    M.giveNotes(2)
    local before = M.snapshot()
    M.assert_eq(Cash.pay(M.player, 0), true, "0 is free")
    M.assert_eq(Cash.pay(M.player, -5), true, "a negative price is free too")
    M.assert_eq(M.snapshot(), before, "nothing moved")
    M.assert_eq(M.count_calls("RemoveAll"), 0, "no container call at all")
    M.assert_eq(Cash.pay(nil, 10), false, "no player -> payment fails")
    M.assert_eq(select(2, Cash.pay(nil, 10)), "no_economy", "…with no_economy, never no_funds")
    M.assert_eq(Cash.balance(nil), nil, "no player -> balance is nil (not 0)")
    M.assert_eq(Cash.refund(nil, 10), false, "no player -> refund fails")
end)

runTest(19, "cash.pay: every deletion/addition is explicitly sent (setDrawDirty alone is not sync)", function()
    resetWorld()
    M.giveNotes(1)
    M.giveBundles(1)
    M.assert_eq(Cash.pay(M.player, 51), true, "1 note + 1 bundle(100), change 50")
    M.assert_eq(#M.instances("Base.Money"), 50, "50 notes of change")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 0, "the bundle is gone")
    M.assert_eq(M.moneyValue(), 50, "101 - 51")
    local removes = M.calls_named("sendRemoveItemsFromContainer")
    local adds = M.calls_named("sendAddItemsToContainer")
    M.assert_eq(#removes, 2, "one remove batch per container-level deletion")
    M.assert_eq(#adds, 1, "one add batch for the change")
    for _, send in ipairs(removes) do
        M.assert_truthy(send.container == M.inv.main(M.player), "remove packet names the main inventory")
        M.assert_truthy(send.items:size() > 0, "remove packet carries a non-empty batch")
    end
    M.assert_truthy(adds[1].container == M.inv.main(M.player), "add packet names the main inventory")
    M.assert_eq(adds[1].items:size(), 50, "add packet carries the 50 change notes")
    -- 引擎里 Remove/AddItems 自己不发包：mock 一次都没替被测代码补发（上面的断言正是因此才有意义）
    M.assert_eq(M.count_calls("sendRemoveItemFromContainer"), 0, "the singular remove API is unused")
    M.assert_eq(M.count_calls("sendAddItemToContainer"), 0, "the singular add API is unused")
    M.assert_eq(M.inv.main(M.player):isDrawDirty(), true,
        "setDrawDirty is only the local UI flag — the packets above are the real sync")
end)

runTest(20, "cash.refund: notes are handed back into the main inventory and the packet is sent", function()
    resetWorld()
    M.giveNotes(10)
    M.assert_eq(Cash.refund(M.player, 42), true, "refund succeeds")
    M.assert_eq(#M.instances("Base.Money"), 52, "10 + 42")
    M.assert_eq(M.moneyValue(), 52, "52 notes on the player")
    local adds = M.calls_named("sendAddItemsToContainer")
    M.assert_eq(#adds, 1, "one add batch")
    M.assert_truthy(adds[1].container == M.inv.main(M.player), "into the main inventory")
    M.assert_eq(adds[1].items:size(), 42, "42 fresh note instances")
    for index = 0, adds[1].items:size() - 1 do
        M.assert_truthy(adds[1].items:get(index).__type == "Base.Money", "each instance is a Base.Money")
    end
    M.assert_eq(Cash.refund(M.player, 0), false, "refunding nothing reports false")
end)

runTest(21, "cash: pay then refund restores the original balance exactly (bundles get broken)", function()
    resetWorld()
    M.giveNotes(2)
    M.giveBundles(1)
    local before = M.moneyValue()
    M.assert_eq(before, 102, "2 + 100")
    M.assert_eq(Cash.pay(M.player, 60), true, "pay 60: 2 notes + break the bundle (change 42)")
    M.assert_eq(M.moneyValue(), 42, "102 - 60")
    M.assert_eq(#M.instances("Base.MoneyBundle"), 0, "the bundle was broken (B42 cannot part-pay a bundle)")
    M.assert_eq(Cash.refund(M.player, 60), true, "refund 60")
    M.assert_eq(M.moneyValue(), before, "back to the original value")
    M.assert_eq(#M.instances("Base.Money"), 102, "…as 102 single notes (the bundle is gone for good)")
    M.assert_eq(Cash.refund({}, 10), false, "a player without an inventory cannot be refunded")
end)

runTest(22, "cash.wage: follows the sandbox wage options (WageEnabled=false -> 0)", function()
    resetWorld()
    M.assert_eq(Cash.wage(), DAILY_WAGE, "default daily wage from the sandbox file (" .. tostring(DAILY_WAGE) .. ")")
    M.assert_eq(Cash.wage(), Config.dailyWage(), "…and equals Config.dailyWage()")
    M.setSandbox("WageEnabled", false)
    M.assert_eq(Cash.wage(), 0, "wages off -> 0")
    M.setSandbox("WageEnabled", true)
    M.setSandbox("DailyWage", 137)
    M.assert_eq(Cash.wage(), 137, "a changed daily wage is honoured")
    M.setSandbox("DailyWage", DAILY_WAGE)
    M.assert_eq(Cash.wage(), DAILY_WAGE, "…and follows back")
    M.setSandboxMissing(true)
    M.assert_eq(Cash.wage(), Config.DEFAULTS.DailyWage, "no SandboxVars at all -> public-layer fallback")
    M.setSandboxMissing(false)
end)

runTest(23, "sandbox: the shipped defaults (50/200/5) match the public-layer fallback", function()
    resetWorld()
    local defaults = M.sandboxDefaults()
    M.assert_eq(defaults.SignPrice, 50, "sandbox-options.txt SignPrice default")
    M.assert_eq(defaults.SpawnPrice, 200, "sandbox-options.txt SpawnPrice default")
    M.assert_eq(defaults.DailyWage, 5, "sandbox-options.txt DailyWage default")
    M.assert_eq(Config.signPrice(), 50, "in game the sandbox value wins")
    M.assert_eq(Config.spawnPrice(), 200, "…for the spawn price too")
    M.assert_eq(Config.dailyWage(), 5, "…and for the wage")
    --[[
        两边必须一致：`Config.DEFAULTS` 是"整个沙盒表读不到"时的兜底（例如存档早于模组的沙盒表），
        而口味在 spec.defaults 里覆盖了它。曾经不一致（兜底还是另两个口味的 500/1500/20，
        比随包发布的默认值大 10 倍），只有那种边角情况才看得到 —— 正是这类"平时看不见"的
        分叉最该被断言钉住。
    ]]
    M.assert_eq(Config.DEFAULTS.SignPrice, 50, "public-layer fallback SignPrice matches the shipped default")
    M.assert_eq(Config.DEFAULTS.SpawnPrice, 200, "public-layer fallback SpawnPrice matches")
    M.assert_eq(Config.DEFAULTS.DailyWage, 5, "public-layer fallback DailyWage matches")
    M.assert_eq(Config.DEFAULTS_OVERRIDE.SignPrice, 50, "the override came from spec.defaults")
    M.setSandboxTableMissing(true)
    M.assert_eq(Config.signPrice(), 50, "with our sandbox table missing the fallback is still 50")
    M.assert_eq(Config.spawnPrice(), 200, "…200")
    M.assert_eq(Config.dailyWage(), 5, "…5")
    M.setSandboxTableMissing(false)
    M.assert_eq(Config.signPrice(), 50, "with the table present the shipped default is used")
    -- 另外两个口味没有被这份覆盖影响（它们仍是 500/1500/20 的那套）
    M.assert_eq(Config.DEFAULTS.MaxContracts, 3, "keys not listed in spec.defaults keep the public-layer value")
    M.assert_eq(Config.DEFAULTS.RecruitRadius, 6, "…including unrelated options")
end)

runTest(24, "e2e: HireExisting charges exactly SignPrice out of the player's notes", function()
    resetWorld()
    local uid = M.addActor({ uid = "palife:van:1" })
    M.giveBundles(1)
    M.giveNotes(30)                                  -- 130
    local before = M.moneyValue()
    M.assert_eq(before, 130, "130 on the player")
    local reply = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r24a") })
    M.assert_eq(resultCode(reply), "hired", "the hire succeeded")
    M.assert_eq(before - M.moneyValue(), SIGN, "exactly SignPrice was charged")
    M.assert_eq(M.moneyValue(), 130 - SIGN, "80 left")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_truthy(contract ~= nil and contract.status == "active", "a contract exists")
    M.assert_eq(contract.price, SIGN, "the contract records the charged price")
    M.assert_eq(contract.mode, "follow", "in the requested post")
    M.assert_truthy(M.count_calls("sendRemoveItemsFromContainer") > 0, "the deduction was synced to clients")
    M.assert_truthy(M.count_calls("sendAddItemsToContainer") > 0, "the change was synced too")
    M.assert_eq(M.pocketValue(), 80, "the engine-level ledger agrees")
end)

runTest(25, "e2e: the same hire works through ServerBootstrap's OnClientCommand handler", function()
    resetWorld()
    local handlers = M.handler_count("OnClientCommand")
    M.assert_truthy(handlers >= 1, "ServerBootstrap installed an OnClientCommand handler")
    local uid = M.addActor({ uid = "palife:van:2" })
    M.giveBundles(1)                                  -- 100
    local before = M.moneyValue()
    local count, err = M.trigger("OnClientCommand", Config.MODULE, "HireExisting", M.player,
        { uid = uid, mode = "guard", requestId = U("r25a") })
    M.assert_eq(err, nil, "the handler did not error: " .. tostring(err))
    M.assert_eq(count, handlers, "every registered handler ran")
    M.assert_eq(before - M.moneyValue(), SIGN, "charged exactly SignPrice")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_truthy(contract ~= nil, "a contract exists")
    M.assert_eq(contract.mode, "guard", "…in guard mode (Alife.orderHold accepted)")
    -- 别的模组的 module 必须被挡在路由外（命令通道只认我们自己的 mod id）
    local after = M.moneyValue()
    M.trigger("OnClientCommand", "SomeOtherMod", "HireExisting", M.player,
        { uid = uid, mode = "follow", requestId = U("r25b") })
    M.assert_eq(M.moneyValue(), after, "a foreign module can never trigger a hire")
end)

runTest(26, "e2e: a failed HireSpawned refunds the whole SpawnPrice and leaves no contract", function()
    resetWorld()
    M.giveBundles(3)                                  -- 300
    local before = M.moneyValue()
    M.assert_eq(before, 300, "300 on the player")
    M.failNextSpawn("shell_hydration_failed")
    local reply = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r26a") })
    M.assert_eq(resultCode(reply), "spawn_failed", "the failure is reported to the client")
    M.assert_eq(M.moneyValue(), before, "the money is back to where it was (full refund)")
    M.assert_truthy(M.count_calls("sendAddItemsToContainer") > 0, "the refund was synced to clients")
    M.assert_eq(Contracts.activeCount(Store.node(M.player, false)), 0, "no contract was created")
    -- 造人成功时则必须**真的扣掉** SpawnPrice
    local uid = M.addActor({ uid = "palife:van:spawn1", lifecycle = "active" })
    local ok = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r26b") })
    M.assert_eq(resultCode(ok), "summoned", "the second spawn succeeded")
    local spent = before - M.moneyValue()
    M.assert_eq(spent, SPAWN, "…and it cost exactly SpawnPrice (" .. tostring(spent) .. ")")
    M.assert_eq(Contracts.activeCount(Store.node(M.player, false)), 1, "one contract now exists")
    M.assert_truthy(uid ~= nil, "the mock really created an actor record")
end)

runTest(27, "e2e: an unaffordable hire fails with no_funds and produces no contract", function()
    resetWorld()
    local uid = M.addActor({ uid = "palife:van:3" })
    M.giveNotes(10)                                   -- 10 < 50
    local reply = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r27a") })
    M.assert_eq(resultCode(reply), "no_funds", "the failure reason reaches the client")
    M.assert_eq(M.moneyValue(), 10, "no money was taken")
    M.assert_eq(M.count_calls("RemoveAll"), 0, "nothing was removed from any container")
    M.assert_eq(Contracts.activeCount(Store.node(M.player, false)), 0, "no contract")
    M.assert_eq(Cash.available(), true, "…even though the money provider itself is available")
end)

runTest(28, "e2e: no economy mod is installed at all — cash still reports available", function()
    resetWorld()
    M.assert_eq(rawget(_G, "YeseMarketServer"), nil, "no YeseMarket server global")
    M.assert_eq(rawget(_G, "OrangeTradingModServer"), nil, "no orange economy server global")
    M.assert_eq(rawget(_G, "OrangeTradingMod"), nil, "no orange economy client global")
    M.assert_eq(Config.economy(), nil, "the upstream probe (Config.economy) finds nothing")
    M.assert_eq(Cash.available(), true, "cash payment needs no upstream mod")
    local state = Service.state(M.player)
    M.assert_eq(state.capabilities.economy, true, "the panel's capability flag says money works")
    M.assert_eq(state.coins, 0, "and the wallet reads 0")
    M.giveNotes(12)
    M.assert_eq(Service.state(M.player).coins, 12, "the wallet reflects the notes")
    M.assert_eq(state.prices.sign, SIGN, "the advertised price is the sandbox one")
end)

-- ===========================================================================
-- C. 左侧侧边栏图标入口
-- ===========================================================================
runTest(29, "sidebar: the entry was hooked at load time, and install() never wraps twice", function()
    resetWorld()
    M.assert_truthy(Icon.hooked == ISEquippedItem,
        "Entry.install ran at load time (client Bootstrap) and remembers the class table")
    local initialise, prerender = ISEquippedItem.initialise, ISEquippedItem.prerender
    M.assert_eq(Icon.install(), true, "install() returns true (the vanilla sidebar exists)")
    M.assert_truthy(ISEquippedItem.initialise == initialise, "a second install does not wrap initialise again")
    M.assert_truthy(ISEquippedItem.prerender == prerender, "…nor prerender")
    -- "确实包了一层" 的实证：面板 initialise 之后 shrinkWrap 被调了两次
    local panel = M.newSidebarPanel(0, 48)
    M.assert_eq(countIcons(panel), 1, "exactly one recruit icon was appended")
    M.assert_eq(panel.shrinkWrapCalls, 2, "vanilla initialise + our append each call shrinkWrap")
end)

runTest(30, "sidebar: install() degrades to false when ISEquippedItem is missing (no throw)", function()
    resetWorld()
    local real = ISEquippedItem
    ISEquippedItem = nil
    local ok, result = pcall(Icon.install)
    M.assert_eq(ok, true, "install() does not throw")
    M.assert_eq(result, false, "…it reports false so the public layer keeps retrying / logs the hint")
    -- 原版类改名或被别的模组换成非函数时也必须如实失败
    ISEquippedItem = { initialise = "not a function", prerender = function() end }
    M.assert_eq(Icon.install(), false, "a renamed / replaced vanilla class also fails cleanly")
    ISEquippedItem = real
    M.assert_eq(Icon.install(), true, "restoring the real class brings the entry back")
    M.assert_truthy(Icon.hooked == real, "…and the hook still points at the real class (no re-wrap)")
    M.assert_truthy(ISEquippedItem.initialise == real.initialise, "the real class kept its wrapper")
end)

runTest(31, "sidebar: the icon sits below the last vanilla button and the panel grows to include it", function()
    resetWorld()
    local panel = M.newSidebarPanel(0, 48)
    local icon = panel.bin2NpcIcon
    M.assert_truthy(icon ~= nil, "panel.bin2NpcIcon exists (the idempotency guard lives on the panel)")
    M.assert_eq(icon.internal, "BIN2NPCRECRUIT", "internal id (vanilla dispatch style)")
    M.assert_eq(icon.Type, "ISButton", "it is an ISButton (ISEquippedItem:shrinkWrap only counts those)")
    M.assert_eq(icon:getY(), panel.mapBtn:getBottom() + 15, "y = last vanilla button bottom + 15")
    M.assert_truthy(icon:getY() > panel.mapBtn:getBottom(), "strictly below the vanilla buttons")
    M.assert_eq(icon:getWidth(), 48, "width follows the measured size bucket")
    M.assert_eq(icon:getHeight(), 36, "height is 0.75 * size")
    M.assert_eq(panel:getHeight(), icon:getBottom(), "shrinkWrap counted the icon into the panel height")
    M.assert_eq(panel.shrinkWrapCalls, 2, "shrinkWrap was called again right after the append")
    M.assert_truthy(icon.parent == panel, "the icon's parent is the panel")
    M.assert_eq(icon.displayBackground, false, "vanilla look: no button background")
    M.assert_eq(icon.ignoreWidth, true, "vanilla look: ignoreWidthChange")
    M.assert_eq(icon.ignoreHeight, true, "vanilla look: ignoreHeightChange")
    M.assert_truthy(#M.calls_named("addMouseOverToolTipItem") >= 1, "a hover tooltip was registered")
end)

runTest(32, "sidebar: the size bucket is measured from the vanilla buttons (48 -> 48, 96 -> 96, 78 -> 80)", function()
    resetWorld()
    local small = M.newSidebarPanel(0, 48)
    M.assert_eq(small.bin2NpcIcon.bin2NpcSize, 48, "48 bucket measured from invBtn")
    M.assert_eq(small.bin2NpcIcon:getWidth(), 48, "button width")
    local large = M.newSidebarPanel(0, 96)
    M.assert_eq(large.bin2NpcIcon.bin2NpcSize, 96, "96 bucket")
    M.assert_eq(large.bin2NpcIcon:getWidth(), 96, "button width")
    M.assert_eq(large.bin2NpcIcon:getHeight(), 72, "0.75 * 96")
    -- 非整数宽度也要落到最近的档（原版哪天改成非整数宽）
    local odd = M.newSidebarPanel(0, 78)
    M.assert_eq(odd.bin2NpcIcon.bin2NpcSize, 80, "78 -> nearest bucket 80")
    M.assert_eq(odd.bin2NpcIcon:getWidth(), 80, "the icon uses the bucket width, not the raw 78")
    -- 五个档都能量出来（tools/make_icons.py 生成的就是这五档）
    for _, size in ipairs({ 48, 64, 80, 96, 128 }) do
        local panel = M.newSidebarPanel(0, size)
        M.assert_eq(panel.bin2NpcIcon.bin2NpcSize, size, "bucket " .. size)
    end
    local injected = {}
    for _, size in ipairs(Config.__sidebarSizes) do injected[tostring(size)] = true end
    M.assert_eq(#Config.__sidebarSizes, 5, "the injected bucket list has five entries")
    for _, size in ipairs({ 48, 64, 80, 96, 128 }) do
        M.assert_eq(injected[tostring(size)], true, "injected bucket " .. size)
    end
end)

runTest(33, "sidebar: every requested texture really exists on disk (mock getTexture mirrors the filesystem)", function()
    resetWorld()
    local panel = M.newSidebarPanel(0, 48)
    M.assert_eq(panel.bin2NpcIcon.image.__path, "media/ui/Sidebar/48/NPC_Off_48.png",
        "the icon starts with the 48 Off texture (getTexture returned it, so the file exists)")
    M.newSidebarPanel(0, 96)
    local known = Config.__iconFiles or {}
    local requested = {}
    for _, call in ipairs(M.calls_named("getTexture")) do requested[call.path] = true end
    M.assert_eq(requested["media/ui/Sidebar/48/NPC_Off_48.png"], true, "48 Off path was requested")
    M.assert_eq(requested["media/ui/Sidebar/96/NPC_Off_96.png"], true, "96 Off path was requested")
    M.assert_eq(M.count_calls("getTexture.missing"), 0, "no requested texture was missing on disk")
    M.assert_eq(Config.__iconFileCount, 10, "run.js verified 10 png files (5 sizes x 2 states)")
    local matched = 0
    for path, present in pairs(known) do
        M.assert_eq(present, true, "verified on disk: " .. tostring(path))
        matched = matched + 1
    end
    M.assert_eq(matched, 10, "…and all ten are in the injected list")
    for _, size in ipairs({ 48, 64, 80, 96, 128 }) do
        for _, state in ipairs({ "On", "Off" }) do
            local path = "media/ui/Sidebar/" .. size .. "/NPC_" .. state .. "_" .. size .. ".png"
            M.assert_eq(known[path], true, "on disk: " .. path)
        end
    end
    -- mock 记录下来的路径集合与磁盘清单一一对应（不能有"请求了但磁盘上没有"的路径）
    local unknown = {}
    for path in pairs(requested) do
        if known[path] ~= true then unknown[#unknown + 1] = path end
    end
    M.assert_eq(#unknown, 0, "requested paths that are not on disk: " .. table.concat(unknown, ", "))
end)

runTest(34, "sidebar: only player 0 gets the icon (the vanilla button column is player-0 only)", function()
    resetWorld()
    local p1 = M.newSidebarPanel(1, 48)
    M.assert_eq(p1.invBtn, nil, "player 1 has no vanilla button column at all")
    M.assert_eq(p1.bin2NpcIcon, nil, "…and therefore no recruit icon")
    M.assert_eq(p1.shrinkWrapCalls, 1, "only the vanilla shrinkWrap ran")
    M.assert_eq(countIcons(p1), 0, "no icon was appended on player 1")
    local p0 = M.newSidebarPanel(0, 48)
    M.assert_eq(countIcons(p0), 1, "player 0 still gets exactly one")
    M.assert_truthy(getPlayerData(1).equipped == p1, "player 1's panel is registered under its own player data")
    M.assert_truthy(getPlayerData(0).equipped == p0, "…and player 0's under its own")
end)

runTest(35, "sidebar: a rebuilt panel gets its own icon and the module keeps no panel reference", function()
    resetWorld()
    local first = M.newSidebarPanel(0, 48)
    first:addToUIManager()
    local firstIcon = first.bin2NpcIcon
    M.assert_truthy(firstIcon ~= nil, "the first panel got an icon")
    -- 模拟玩家改"侧边栏尺寸"：原版 checkSidebarSizeOption 会 removeFromUIManager 后重建整个面板
    first:removeFromUIManager()
    M.assert_eq(M.uiHas(first.javaObject), false, "the old panel is out of the UIManager")
    local second = M.newSidebarPanel(0, 96)
    M.assert_truthy(second.bin2NpcIcon ~= nil, "the rebuilt panel has an icon")
    M.assert_truthy(second.bin2NpcIcon ~= firstIcon, "…and it is a new button, not the dead one")
    M.assert_eq(second.bin2NpcIcon.bin2NpcSize, 96, "sized from the new panel's vanilla buttons")
    M.assert_truthy(first.bin2NpcIcon == firstIcon, "the old panel still holds its own field (nothing was rewritten)")
    M.assert_truthy(getPlayerData(0).equipped == second, "player data points at the new panel")
    -- 模块上不能留面板引用，否则改尺寸后会去操作一个已经死掉的面板
    local stale = {}
    for name, value in pairs(Icon) do
        if type(value) == "table" and (value.chr ~= nil or value.bin2NpcIcon ~= nil) then
            stale[#stale + 1] = tostring(name)
        end
    end
    M.assert_eq(#stale, 0, "no panel is stored on the Icon module: " .. table.concat(stale, ", "))
    M.assert_truthy(Icon.hooked == ISEquippedItem, "the only table the module keeps is the hooked class")
end)

runTest(36, "sidebar: prerender keeps the icon texture in sync with the window state", function()
    resetWorld()
    local panel = M.newSidebarPanel(0, 48)
    local icon = panel.bin2NpcIcon
    M.assert_eq(icon.image.__path, "media/ui/Sidebar/48/NPC_Off_48.png", "closed -> Off texture")
    local window = Panel.open(M.player)
    M.assert_truthy(window ~= nil, "the window opened")
    panel:prerender()                                  -- 原版每帧都跑；我们的钩子在它之后刷新
    M.assert_eq(icon.image.__path, "media/ui/Sidebar/48/NPC_On_48.png", "open -> On texture")
    Panel.close()
    panel:prerender()
    M.assert_eq(icon.image.__path, "media/ui/Sidebar/48/NPC_Off_48.png", "closed again -> Off texture")
    M.assert_eq(icon.bin2NpcSize, 48, "the measured bucket did not change")
    M.assert_eq(panel.shrinkWrapCalls, 2, "…so refreshIcon did not shrinkWrap again (no per-frame churn)")
end)

runTest(37, "sidebar: clicking the icon toggles the window while the UIManager stays consistent", function()
    resetWorld()
    local panel = M.newSidebarPanel(0, 48)
    local icon = panel.bin2NpcIcon
    M.assert_eq(M.uiCount(), 0, "no UI element yet")
    M.assert_eq(Panel.isOpen(), false, "the panel starts closed")
    icon:click()                                       -- 引擎调 onclick(target, button)
    M.assert_eq(Panel.isOpen(), true, "first click opens it")
    M.assert_eq(M.uiCount(), 1, "the window is in the UIManager")
    M.assert_eq(icon.image.__path, "media/ui/Sidebar/48/NPC_On_48.png", "…and the icon switched to On")
    icon:click()
    M.assert_eq(Panel.isOpen(), false, "second click closes it")
    M.assert_eq(M.uiCount(), 0, "…and it is removed from the UIManager")
    M.assert_eq(icon.image.__path, "media/ui/Sidebar/48/NPC_Off_48.png", "icon back to Off")
    --[[
        回调约定：ISButton:onMouseUp 调 onclick(self.target, self, ...)，第一个参数是面板。
        用"别的按钮"调我们的回调必须什么都不做（internal 判定失败就 return）——
        写成单参数签名（把面板当按钮）会让 internal 永远不成立，这里就会红。
    ]]
    icon.onclick(panel, { internal = "MAP" })
    M.assert_eq(Panel.isOpen(), false, "a button whose internal id is not ours is ignored")
    M.assert_eq(M.uiCount(), 0, "…and no window was added")
    M.assert_truthy(icon.target == panel, "the button's click target is the panel")
end)

runTest(38, "hotkey: Entry.open() opens the window even with no sidebar at all", function()
    resetWorld()
    local real = ISEquippedItem
    ISEquippedItem = nil                               -- 原版侧边栏整体不可用（别的模组换了 HUD）
    M.assert_eq(Icon.open(), true, "the hotkey path opens the window anyway")
    M.assert_eq(Panel.isOpen(), true, "the panel is open")
    ISEquippedItem = real
    M.assert_eq(Icon.open(), false, "calling it again closes the panel (same path as the icon)")
    M.assert_eq(Panel.isOpen(), false, "closed")
    -- 翻译文案承诺了 Ctrl+Alt+N：两种语言都必须写清楚
    M.useCnTranslations()
    M.assert_contains(Config.Text.get("IconTooltip"), "Ctrl+Alt+N", "the CN tooltip promises the hotkey")
    M.state.translations = Config.__enText
    M.assert_contains(Config.Text.get("IconTooltip"), "Ctrl+Alt+N", "the EN tooltip promises the hotkey")
    M.state.translations = nil
    M.assert_truthy(M.handler_count("OnKeyPressed") >= 1, "the public layer bound a key handler")
    -- 真的按一次 Ctrl+Alt+N（isCtrlKeyDown/isAltKeyDown 由 mock 置真）
    M.assert_truthy(Keyboard ~= nil and Keyboard.KEY_N ~= nil, "Keyboard.KEY_N exists")
    M.trigger("OnKeyPressed", Keyboard.KEY_N)
    M.assert_eq(Panel.isOpen(), true, "Ctrl+Alt+N opened the recruit panel")
    Config.RecruitPanel.close()
end)

-- ===========================================================================
-- D. 招募窗口
-- ===========================================================================
runTest(39, "window: opening requests the state, switching to the hire tab scans candidates", function()
    resetWorld()
    local sent = spySend(function() Panel.open(M.player) end)
    M.assert_eq(sent[1].command, "RequestState", "opening sends RequestState")
    M.assert_eq(sent[1].mutating, false, "…as a non-mutating command")
    local window = WindowClass.instance
    M.assert_truthy(window ~= nil, "the window exists")
    M.assert_eq(window.mode, "roster", "the roster tab is the default view")
    M.assert_truthy(window.player == M.player, "the window is bound to the local player")
    local more = spySend(function() window:setMode("hire") end)
    M.assert_eq(more[1].command, "ScanCandidates", "the hire tab scans candidates")
    M.assert_truthy(type(more[1].args) == "table", "…with an args table")
    local back = spySend(function() window:setMode("roster") end)
    M.assert_eq(back[1].command, "RequestState", "going back to the roster requests the state again")
end)

runTest(40, "window: the roster lists contracts, the hire tab lists candidates minus the hired ones", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        M.pushFromServer({
            contracts = {
                { uid = "u1", name = "Alex", mode = "follow", status = "active", price = 50 },
                { uid = "u2", name = "Dana", mode = "guard", status = "active", price = 50 },
                { uid = "u3", name = "Dead", mode = "follow", status = "dead" },
            },
            candidates = {
                { uid = "u1", name = "Alex", distance = 2, hostile = false },
                { uid = "u2", name = "Dana", distance = 3, hostile = false },
                { uid = "u9", name = "New", distance = 4, hostile = true },
            },
            capabilities = { enabled = true, alife = true, economy = true, jeem = false },
            limits = { max = 3, used = 2 },
            prices = { sign = 50, spawn = 200, wage = 5 },
            coins = 0,
        })
        window:rebuild()
        M.assert_eq(#window.list.items, 3, "the roster shows every contract (dead ones included)")
        M.assert_eq(window.list.items[1].text, "Alex", "row 1 title")
        M.assert_eq(window.list.items[3].item.status, "dead", "a dead contract is still listed")
        window:setMode("hire")
        M.assert_eq(#window.list.items, 1, "candidates minus the two already on the roster")
        M.assert_eq(window.list.items[1].item.uid, "u9", "…leaving only the new one")
        M.assert_eq(window.list.items[1].item.hostile, true, "hostile candidates are flagged for the UI")
        window:setMode("summon")
        M.assert_eq(#window.list.items, 0, "the summon tab lists nothing")
        M.assert_eq(window.list.addItemCalls, 4, "exactly four rows were ever added (3 + 1 + 0)")
    end)
end)

runTest(41, "window: rebuild preserves the scroll position, and the summon tab adds no rows", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)      -- Panel.open 自己会 syncState 一次
        M.pushFromServer({
            contracts = { { uid = "u1", name = "A", mode = "follow", status = "active" } },
            candidates = {}, prices = {}, capabilities = {}, limits = {},
        })
        window.list.yScroll = 40
        local scrollCalls = window.list.setYScrollCalls
        window:rebuild()
        M.assert_eq(window.list.yScroll, 40, "the scroll offset survived the rebuild")
        M.assert_eq(window.list.setYScrollCalls, scrollCalls + 1, "…and rebuild restored it exactly once")
        M.assert_truthy(window.list.scrollHeight > 0, "the list re-computed its scroll height")
        local clears = window.list.clearCalls
        window.mode = "summon"
        window:rebuild()
        M.assert_eq(#window.list.items, 0, "the summon tab adds no rows")
        M.assert_eq(window.list.clearCalls, clears + 1, "…but it still cleared the list")
        M.assert_eq(window.list.setYScrollCalls, scrollCalls + 1, "…and did not touch the scroll position")
    end)
end)

runTest(42, "window: the hire tab's primary action sends HireExisting{uid, mode, requestId}", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        M.pushFromServer({
            contracts = {},
            candidates = { { uid = "u9", name = "New", distance = 3 } },
            capabilities = { enabled = true, alife = true, economy = true },
            limits = { max = 3, used = 0 },
            prices = { sign = 50, spawn = 200, wage = 5 },
        })
        window:setMode("hire")
        M.assert_eq(#clientCommands("ScanCandidates"), 1, "the tab change scanned candidates")
        local before = #clientCommands()
        window:primaryAction()
        M.assert_eq(#clientCommands(), before, "nothing selected -> nothing sent")
        window:onRowSelected({ uid = "u9" })
        M.assert_eq(window.selectedUid, "u9", "the row is selected")
        window:primaryAction()
        local sent = lastCommand()
        M.assert_eq(sent.command, "HireExisting", "the command name")
        M.assert_eq(sent.module, Config.MODULE, "our own module (never borrow A-Life's channel)")
        M.assert_eq(sent.args.uid, "u9", "the selected uid")
        M.assert_eq(sent.args.mode, Config.defaultMode(), "the default post when nothing was picked")
        M.assert_truthy(type(sent.args.requestId) == "string", "mutating commands carry a requestId")
        M.assert_truthy(sent.player == M.player, "sent for the local player")
    end)
end)

runTest(43, "window: the summon tab's primary action sends HireSpawned{mode}", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        M.pushFromServer({
            contracts = {}, candidates = {},
            capabilities = { enabled = true, alife = true, economy = true },
            limits = { max = 3, used = 0 },
            prices = { sign = 50, spawn = 200, wage = 5 },
        })
        window:setMode("summon")
        window:setPendingMode("guard")
        M.assert_eq(window.pendingMode, "guard", "the pending post is remembered")
        window:primaryAction()
        local sent = lastCommand()
        M.assert_eq(sent.command, "HireSpawned", "the command name")
        M.assert_eq(sent.args.mode, "guard", "the chosen post")
        M.assert_eq(sent.args.uid, nil, "no uid: the server picks the actor")
        M.assert_truthy(sent.args.requestId ~= nil, "mutating command")
    end)
end)

runTest(44, "window: the roster tab sends SetMode ONLY when the post actually changed", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        M.pushFromServer({
            contracts = { { uid = "u1", name = "A", mode = "resident", status = "active" } },
            candidates = {},
            capabilities = { enabled = true, alife = true, economy = true, jeem = true },
            limits = { max = 3, used = 1 },
            prices = { sign = 50, spawn = 200, wage = 5 },
        })
        window:rebuild()
        window:onRowSelected({ uid = "u1" })
        M.assert_eq(window.selectedUid, "u1", "the contract row is selected")
        M.assert_eq(window:selectedContract().mode, "resident", "…and it is a resident contract")
        --[[
            历史上"居民化被拒（resident（上游返回）），已降级为跟随"的根因：
            旧版把**当前岗位**再发一遍，等于请 Jeem 再收编一次已经住进来的人。
            这条必须钉死：岗位没变 -> 一条命令都不发。
        ]]
        window:setPendingMode("resident")
        M.assert_eq(window.pendingMode, "resident", "pending == the contract's post")
        local before = #clientCommands()
        window:primaryAction()
        M.assert_eq(#clientCommands(), before, "NOTHING is sent when the post is unchanged")
        M.assert_eq(window.btnPrimary.enable, false, "the apply button is disabled in that state")
        -- 真的换了岗位才发，而且只发一次
        window:setPendingMode("guard")
        M.assert_eq(window.btnPrimary.enable, true, "changed post -> the apply button is enabled")
        window:primaryAction()
        local sent = lastCommand()
        M.assert_eq(sent.command, "SetMode", "changed post -> SetMode")
        M.assert_eq(sent.args.uid, "u1", "the uid")
        M.assert_eq(sent.args.mode, "guard", "the new post")
        M.assert_eq(#clientCommands("SetMode"), 1, "exactly one SetMode")
        M.assert_eq(window.pendingMode, nil, "the pending post is cleared after sending")
        -- 选人会把"待应用岗位"清掉（别把上一个人选的岗位带到他头上）
        window:onRowSelected({ uid = "u1" })
        M.assert_eq(window.pendingMode, nil, "selecting a row clears the pending post")
    end)
end)

runTest(45, "window: dismiss sends Dismiss{uid} for the selected contract only", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        M.pushFromServer({
            contracts = { { uid = "u1", name = "A", mode = "follow", status = "active" } },
            candidates = {},
            capabilities = { enabled = true, alife = true, economy = true },
            limits = { max = 3, used = 1 },
            prices = { sign = 50, spawn = 200, wage = 5 },
        })
        window:rebuild()
        local before = #clientCommands()
        window:dismissAction()
        M.assert_eq(#clientCommands(), before, "nothing selected -> nothing sent")
        window:onRowSelected({ uid = "u1" })
        M.assert_eq(window.btnDismiss.visible, true, "the dismiss button shows for a selected contract")
        window:dismissAction()
        local sent = lastCommand()
        M.assert_eq(sent.command, "Dismiss", "the command")
        M.assert_eq(sent.args.uid, "u1", "with the uid")
        M.assert_eq(sent.args.mode, nil, "and nothing else")
        M.assert_eq(window.selectedUid, nil, "the selection is cleared")
        M.assert_eq(window.btnDismiss.visible, false, "…and the dismiss button hides again")
    end)
end)

runTest(46, "window: the list is rebuilt only when the state revision changes", function()
    resetWorld()
    asClient(function()
        local window = Panel.open(M.player)
        window:syncState()
        local clears = window.list.clearCalls
        M.assert_eq(clears, 1, "the first sync built the list once")
        window:syncState()
        window:syncState()
        M.assert_eq(window.list.clearCalls, clears, "further syncs at the same revision do not rebuild")
        M.pushFromServer({
            contracts = { { uid = "u1", name = "A", mode = "follow", status = "active" } },
            candidates = {}, prices = {}, capabilities = {}, limits = {},
        })
        M.assert_truthy(tonumber(Net.cache.revision) > 0, "the pushed state bumped the revision")
        window:syncState()
        M.assert_eq(window.list.clearCalls, clears + 1, "a new revision rebuilds exactly once")
        M.assert_eq(#window.list.items, 1, "…and the new contract shows up")
        M.assert_eq(window.seenRevision, tonumber(Net.cache.revision), "the window remembers the revision")
    end)
end)

runTest(47, "window: close() removes the element from the UIManager and clears the singleton", function()
    resetWorld()
    local window = Panel.open(M.player)
    M.assert_truthy(WindowClass.instance == window, "the singleton is set")
    M.assert_eq(M.uiCount(), 1, "one UI element")
    M.assert_eq(Panel.isOpen(), true, "isOpen() agrees")
    window:close()
    M.assert_eq(WindowClass.instance, nil, "the singleton is cleared")
    M.assert_eq(M.uiCount(), 0, "the element was removed from the UIManager")
    M.assert_eq(window:getIsVisible(), false, "…and it is hidden, not just detached")
    M.assert_eq(Panel.isOpen(), false, "isOpen() agrees again")
    M.assert_eq(Panel.close(), nil, "closing again is a harmless no-op")
    -- 再开一次拿到的是新窗口，而不是那个已经摘掉的
    local again = Panel.open(M.player)
    M.assert_truthy(again ~= window, "reopening builds a fresh window")
    M.assert_eq(M.uiCount(), 1, "…and the UIManager holds exactly one window again")
    again:close()
end)

-- ===========================================================================
-- E. 翻译与沙盒（静态检查）
-- ===========================================================================
runTest(48, "translations: every scanned key exists in CN and EN, and both languages match the files", function()
    local source = Config.__sourceKeys or {}
    M.assert_truthy(#source >= 80, "the scanner found the translation keys (" .. tostring(#source) .. ")")
    M.assert_eq(#source, 83, "…exactly the 83 literal keys this flavour uses")
    local missingCn, missingEn = {}, {}
    for _, key in ipairs(source) do
        if CN_KEYS[key] ~= true then missingCn[#missingCn + 1] = key end
        if EN_KEYS[key] ~= true then missingEn[#missingEn + 1] = key end
    end
    M.assert_eq(#missingCn, 0, "CN IG_UI.json is missing: " .. table.concat(missingCn, ", "))
    M.assert_eq(#missingEn, 0, "EN IG_UI.json is missing: " .. table.concat(missingEn, ", "))

    local cnOnly, enOnly = {}, {}
    for key in pairs(CN_KEYS) do if EN_KEYS[key] ~= true then cnOnly[#cnOnly + 1] = key end end
    for key in pairs(EN_KEYS) do if CN_KEYS[key] ~= true then enOnly[#enOnly + 1] = key end end
    table.sort(cnOnly)
    table.sort(enOnly)
    M.assert_eq(#cnOnly, 0, "present in CN but not EN: " .. table.concat(cnOnly, ", "))
    M.assert_eq(#enOnly, 0, "present in EN but not CN: " .. table.concat(enOnly, ", "))
    local cnCount, enCount = 0, 0
    for _ in pairs(CN_KEYS) do cnCount = cnCount + 1 end
    for _ in pairs(EN_KEYS) do enCount = enCount + 1 end
    M.assert_eq(cnCount, 94, "IG_UI.json ships 94 keys (the file is the source of truth)")
    M.assert_eq(enCount, 94, "…in both languages")

    --[[
        扫描器的两条硬性要求：
          * `T(cond and "A" or "B")` 这种条件键必须被扫到（本口味 Panel.lua 里就是这种写法，
            老做法会取到比较值 "hire"，于是"漏翻 hire"这种假问题与"真漏翻 HireHint"一起被掩盖）；
          * 空白串 / 比较值不能被当成键。
    ]]
    local bogus = {}
    for _, key in ipairs(source) do
        if key == "" or key == "hire" or key == "follow" or key == "resident" then
            bogus[#bogus + 1] = key
        end
    end
    M.assert_eq(#bogus, 0, "the scanner never picks up comparison values / empty strings")
    M.assert_eq(CN_KEYS.HireHint, true, "HireHint (a conditional key) exists")
    M.assert_eq(CN_KEYS.RosterHint, true, "RosterHint (a conditional key) exists")
    M.assert_eq(CN_KEYS.DetailHostile, true, "DetailHostile exists")
    M.assert_eq(CN_KEYS.DetailFriendly, true, "DetailFriendly exists")

    -- 有些键在源码里是变量传的（扫不到），必须单独点名
    for _, key in ipairs({ "PageTitle", "IconTooltip", "EntryButton", "EntryTooltip", "CurrencyAmount",
        "NoticeDone", "NoticeFailed", "NoticeDegraded", "FlowHire", "FlowRefund", "CampName",
        "SummonHint1", "SummonHint2", "SummonHint3", "ReasonNoFunds", "ReasonUpstream",
        "ReasonResidentRefused", "ReasonAlreadyResident", "Wallet", "WageLine", "ApplyMode",
        "StatusUnpaid", "ReasonNoEconomy", "WarnNoEconomy" }) do
        M.assert_eq(CN_KEYS[key], true, "CN has " .. key)
        M.assert_eq(EN_KEYS[key], true, "EN has " .. key)
    end
    M.assert_eq(CN_KEYS.Prefix, nil, "no stray 'Prefix' key")
end)

runTest(49, "sandbox: the mock's defaults come from sandbox-options.txt and every option is translated", function()
    local defaults = M.sandboxDefaults()
    local names = Config.__sandboxOptionNames or {}
    M.assert_eq(#names, 14, "sandbox-options.txt declares 14 options")
    M.assert_eq(Config.__sandboxOptionCount, 14, "…and run.js parsed every one of them")
    for _, name in ipairs(names) do
        M.assert_truthy(defaults[name] ~= nil, "a default was parsed for " .. name)
        M.assert_eq(CN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla." .. name], true, "CN name: " .. name)
        M.assert_eq(EN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla." .. name], true, "EN name: " .. name)
        M.assert_eq(CN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla." .. name .. "_tooltip"], true,
            "CN tooltip: " .. name)
        M.assert_eq(EN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla." .. name .. "_tooltip"], true,
            "EN tooltip: " .. name)
    end
    -- 沙盒选项的键必须与公共层 Config.DEFAULTS 完全对齐（键名漂移 = 选项永远读不到）
    for key in pairs(Config.DEFAULTS) do
        M.assert_truthy(defaults[key] ~= nil, "Config.DEFAULTS key exists in sandbox-options.txt: " .. key)
    end
    M.assert_eq(CN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla"], true, "the sandbox page title exists")
    M.assert_eq(EN_SANDBOX["Sandbox_Bin2NPCExtensionVanilla"], true, "…in EN too")
    local cnSandbox, enSandbox = 0, 0
    for _ in pairs(CN_SANDBOX) do cnSandbox = cnSandbox + 1 end
    for _ in pairs(EN_SANDBOX) do enSandbox = enSandbox + 1 end
    M.assert_eq(cnSandbox, 37, "Sandbox.json ships 37 keys")
    M.assert_eq(enSandbox, 37, "…in both languages")
end)

runTest(50, "window: the panel shows the sandbox prices and the real note balance in this flavour's words", function()
    resetWorld()
    M.giveNotes(37)
    local state = Service.state(M.player)
    M.assert_eq(state.coins, 37, "the wallet reads the notes, not an economy mod balance")
    M.assert_eq(state.prices.sign, SIGN, "the sign price comes from the sandbox file")
    M.assert_eq(state.prices.spawn, SPAWN, "the spawn price")
    M.assert_eq(state.prices.wage, DAILY_WAGE, "the daily wage")
    M.assert_eq(state.capabilities.economy, true, "money is available")
    M.useCnTranslations()
    M.assert_contains(Config.Text.get("CurrencyAmount", "50"), "钞票", "CN renders amounts as notes")
    M.assert_contains(Config.Text.get("PageTitle"), "原版钞票", "the title says this flavour pays in vanilla notes")
    M.assert_not_contains(Config.Text.get("PageTitle"), "橙子", "…and never mentions another flavour's currency")
    M.state.translations = nil
    -- 面板真的能把这四行画出来（render 走一遍不报错）
    local window = Panel.open(M.player)
    window:render()
    M.assert_truthy(window.renderCalls >= 1, "render() ran end to end")
    M.assert_eq(window.title, Config.Text.get("PageTitle"), "the window title uses the flavour's key")
    window:close()
end)

-- ===========================================================================
-- 汇总
-- ===========================================================================
print("")
print(string.format("[test] %d/%d passed, %d failed", passed, TOTAL, failures))
if passed + failures ~= TOTAL then
    print(string.format("[test] WARNING: %d cases ran but TOTAL says %d", passed + failures, TOTAL))
    failures = failures + 1
end
return failures
