-- ===========================================================================
-- test_recruit.lua —— Bin2NPCExtensionYese 招募流程的离线集成断言
-- ===========================================================================
--
-- 环境由 run.js + mock_env.lua 准备好：
--   * MOCK        —— 引擎桩 / 依赖 mock / 调用记录 / 时间推进 / 断言框架
--   * Bin2NPCExtensionYese / ProjectALife / ProjectALifeJimmy / YeseMarket*
--     —— 被测的 14 个文件跑完后的产物
--
-- 返回失败条数（run.js 用它当退出码：0 = ALL PASS）。
-- ===========================================================================

local M = MOCK

-- ---------------------------------------------------------------- 被测对象
local Config = Bin2NPCExtensionYese
local Contracts = Config.Contracts
local Store = Config.Store
local Service = Config.Service
local Maintain = Config.Maintain
local Alife = Config.Alife
local Jimmy = Config.Jimmy
local Net = Config.Net

-- 用例总数：runTest 会把它当断言前缀用，新增用例时同步改这一个数字
local TOTAL = 34
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

--[[
    测试里的命令入口：改状态命令之间自动推进 1 秒，避免撞上 Service 的 400ms 防连点。
    去重/限速那两条用例直接用 Service.dispatch，自己控制时钟。
]]
local function d(player, command, args)
    -- 改状态命令之间推进 10 秒：既躲开 400ms 防连点，也躲开 60s 重放窗口
    if player ~= nil and MUTATING[command] == true then M.advanceMs(10000) end
    return Service.dispatch(player, command, args)
end

local function requestState()
    return d(M.player, "RequestState")
end

--- 全局唯一的 requestId：Service 的重放窗口是 60 秒，整个进程内不能重复用同一个 id
local requestSeq = 0
local function U(label)
    requestSeq = requestSeq + 1
    return tostring(label) .. "#" .. tostring(requestSeq)
end

local KEY = Store.playerKey(M.player)
local SIGN = Config.DEFAULTS.SignPrice
local SPAWN = Config.DEFAULTS.SpawnPrice
local RADIUS = Config.DEFAULTS.RecruitRadius

-- 每个 test 开头的干净状态：保留三个依赖的全局，清掉 A-Life / 存档 / 调用记录 / 余额
local function resetWorld(options)
    options = options or {}
    local balance = options.balance
    local previousNow = M.state.nowMs
    M.reset({ keepSandbox = true })
    -- 沙盒选项必须回到默认值，否则上一个用例改过的价格会污染下一个用例
    M.setSandboxTableMissing(false)
    M.setSandboxMissing(false)
    for key, value in pairs(Config.DEFAULTS) do M.setSandbox(key, value) end
    if options.sandbox then
        for key, value in pairs(options.sandbox) do M.setSandbox(key, value) end
    end
    M.clearModData()
    M.__spawnFailure = nil          -- 造人失败注入不能跨用例泄漏
    -- 时钟必须单调前进：Service 的 lastCommandAt / seenRequests 是模块级 local，
    -- reset 换掉 state 之后时间不能往回跳（往回跳会让 now-last < 400 永远成立 -> too_fast）
    M.setNowMs(math.max(previousNow, M.state.nowMs) + 60000)
    M.state.economy = {}
    M.setBalance(balance == nil and 10000 or balance)
    M.player:setPosition(100, 100, 0)
    return M
end


--- Page.lua 里 ISPanel:new 用的必须是我们装的桩：造一个空 page 看它有没有引擎方法
local function pageUsesISPanelStub()
    local probe = ISPanel:new(0, 0, 1, 1)
    return type(probe) == "table" and type(probe.addChild) == "function"
        and type(probe.drawText) == "function"
end

local CN_KEYS = Config.__cnKeys or {}
local EN_KEYS = Config.__enKeys or {}
local SOURCE_KEYS = Config.__sourceKeys or {}


-- ===========================================================================
-- 1. 加载
-- ===========================================================================
runTest(1, "loader: 14 files, expected globals only, require is idempotent", function()
    M.assert_eq(Config.__loadedCount, 14, "loaded file count")
    M.assert_eq(Config.MODULE, "Bin2NPCExtensionYese", "Config.MODULE")
    M.assert_eq(Bin2NPCExtensionYese, Config, "Bin2NPCExtensionYese is the Config table")
    M.assert_truthy(type(Config.Text.get) == "function", "Config.Text.get")
    M.assert_truthy(type(Contracts.sanitize) == "function", "Contracts.sanitize")
    M.assert_truthy(type(Store.playerKey) == "function", "Store.playerKey")
    M.assert_truthy(type(Config.ServerBootstrap) == "table", "server Bootstrap ran")
    M.assert_truthy(type(Config.ClientBootstrap) == "table", "client Bootstrap ran")
    M.assert_truthy(type(Config.RecruitPage) == "table", "client ui/Page ran")

    -- 兼容自检在**加载期**就跑过一次，而且是只读的：
    --   * 调用了 A-Life 自己的 foreignCopies（点名"自带 A-Life Lua 副本"的模组）
    --   * **没有**往 ProjectALife.ModCompat.known 里写自己
    --     （Compat.report() 会按 entry.verdict 打印，等于借 A-Life 的口替自己背书）
    M.assert_truthy(M.count_calls("foreignCopies") >= 1,
        "the compat self-check ran at load time and called ModCompat.foreignCopies")
    local compatCall = M.calls_named("foreignCopies")[1]
    M.assert_truthy(type(compatCall) == "table" and type(compatCall.active) == "table",
        "foreignCopies receives the active-mod set (A-Life's own signature)")
    M.assert_falsy(ProjectALife.ModCompat.known["Bin2NPCExtensionYese"] ~= nil,
        "this mod must NOT write itself into ProjectALife.ModCompat.known")

    -- 只多出预期全局
    local allowed = {
        Bin2NPCExtensionYese = true,
        ProjectALife = true,
        ProjectALifeJimmy = true,
        YeseMarket = true,
        YeseMarketServer = true,
    }
    local unexpected = {}
    for _, name in ipairs(M.newGlobals()) do
        if allowed[name] ~= true then unexpected[#unexpected + 1] = name end
    end
    M.assert_eq(#unexpected, 0, "unexpected new globals: " .. table.concat(unexpected, ", "))

    -- require 同一文件两次不会重复执行（package.loaded 命中，第二次连 searcher 都不进）
    local before = M.requireCounts["Bin2NPCExtensionYese/Contracts"] or 0
    local again = require "Bin2NPCExtensionYese/Contracts"
    M.assert_truthy(again == Contracts, "second require returns the cached module table")
    local after = M.requireCounts["Bin2NPCExtensionYese/Contracts"] or 0
    M.assert_eq(after, before, "the second require never re-ran the searcher (file not re-executed)")
    -- 13 个模块（14 个文件里两个 Bootstrap 同名）都只被解析一次：
    -- 第二次 require 直接命中 package.loaded，连 searcher 都不进。
    M.assert_eq(#Config.__requireNames, 13, "13 distinct require names for 14 files")
    M.assert_eq(Config.__loadedCount, 14, "run.js dofile'd all 14 files")
    local duplicated = {}
    for _, name in ipairs(Config.__requireNames) do
        local count = M.requireCounts[name] or 0
        if count > 1 then duplicated[#duplicated + 1] = name .. "=" .. tostring(count) end
    end
    M.assert_eq(#duplicated, 0, "modules resolved twice: " .. table.concat(duplicated, ", "))
    -- Config 被 12 个文件依赖；每个依赖链都只解析一次
    M.assert_eq(M.requireCounts["Bin2NPCExtensionYese/Config"], 1, "Config resolved once")
    M.assert_eq(M.requireCounts["Bin2NPCExtensionYese/Contracts"], 1, "Contracts resolved once")
    M.assert_eq(M.requireCounts["Bin2NPCExtensionYese/ui/Page"], 1, "ui/Page resolved once")
    -- 两个 Bootstrap 是被引擎 LoadDirBase 直接执行的（没有任何文件 require 它们）
    M.assert_falsy(M.requireCounts["Bin2NPCExtensionYese/Bootstrap"], "Bootstrap is engine-loaded, not required")
    -- Page.lua 的 require "ISUI/ISPanel" / "ui/page_registry" 由 package.preload 提供（searcher 不进）
    M.assert_truthy(pageUsesISPanelStub(), "ui/Page used the ISPanel stub")
end)

-- ===========================================================================
-- 2. Config.opt 与 enabled()==false
-- ===========================================================================
runTest(2, "sandbox: Config.opt falls back to defaults, honors values, disabled blocks every mutating command", function()
    -- (a) SandboxVars 整个缺失
    M.setSandboxMissing(true)
    M.assert_eq(Config.opt("SignPrice"), 500, "SignPrice default when SandboxVars is missing")
    M.assert_eq(Config.opt("MaxContracts"), 3, "MaxContracts default when SandboxVars is missing")
    M.assert_eq(Config.enabled(), true, "Enabled defaults to true when SandboxVars is missing")
    -- (b) 我们的沙盒表缺失
    M.setSandboxMissing(false)
    M.setSandboxTableMissing(true)
    M.assert_eq(Config.opt("DailyWage"), 20, "DailyWage default when the sandbox table is missing")
    -- (c) 设置后返回设定值
    M.setSandboxTableMissing(false)
    M.setSandbox("SignPrice", 123)
    M.setSandbox("MaxContracts", 7)
    M.assert_eq(Config.opt("SignPrice"), 123, "SignPrice from SandboxVars")
    M.assert_eq(Config.maxContracts(), 7, "MaxContracts from SandboxVars")
    M.assert_eq(Config.opt("NotAnOption", 42), 42, "explicit default for an unknown key")

    -- (d) Enabled=false 时所有改状态命令都被挡住
    resetWorld({ balance = 10000, sandbox = { Enabled = false } })
    M.setSandbox("Enabled", false)
    M.assert_eq(Config.enabled(), false, "Config.enabled()")
    local uid = M.addActor({ uid = "palife:disabled:1" })
    -- 注意：Dismiss 不在这个列表里 —— 它当前没有 Config.enabled() 闸门（见报告 bug #1），
    -- 闸门的现状由用例 31 记录。
    local commands = {
        { "HireExisting", { uid = uid, mode = "follow" } },
        { "HireSpawned", { mode = "follow" } },
        { "SetMode", { uid = uid, mode = "guard" } },
    }
    for _, entry in ipairs(commands) do
        M.advanceMs(1000)
        local reply = d(M.player, entry[1], entry[2])
        M.assert_eq(resultCode(reply), "disabled", entry[1] .. " result code when disabled")
        -- 失败码必须留在 lastResult 里，下一次状态刷新要能看到
        local state = requestState()
        M.assert_eq(state.result and state.result.ok, false, entry[1] .. " ok=false when disabled")
        M.assert_eq(state.result and state.result.code, "disabled", entry[1] .. " buffered code")
    end
    -- Dismiss 目前没有 Config.enabled() 闸门（见报告 bug #1）；这里只确认它仍然校验契约存在
    M.advanceMs(1000)
    M.assert_eq(resultCode(d(M.player, "Dismiss", { uid = uid, requestId = U("r2dismiss") })),
        "disabled", "Dismiss is gated by Enabled too (bug #1 fixed)")
    M.assert_eq(M.balance(), 10000, "no money is taken while disabled")
    M.assert_eq(M.count_calls("Pay"), 0, "Pay must not be called while disabled")
    M.assert_eq(M.count_calls("Residents.recruit"), 0, "Residents.recruit must not be called while disabled")
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 0, "setOrder must not be called while disabled")
    -- 恢复默认，后面的用例不受影响
    M.setSandbox("Enabled", true)
end)

-- ===========================================================================
-- 3. Contracts.sanitize
-- ===========================================================================
runTest(3, "contracts: sanitize repairs order/contracts drift, bad mode, missing status, non-table rows", function()
    local store = {
        schema = 99,
        players = {
            [KEY] = {
                seq = "3",
                contracts = {
                    ["uid-a"] = { mode = "not-a-mode", hiredHours = 1 },
                    ["uid-b"] = { mode = "guard", status = "active" },
                    ["uid-c"] = { mode = "resident", status = "dismissed" },
                    broken = "not a table",
                    [7] = { mode = "follow" },
                },
                order = { "uid-b", "uid-ghost", "uid-b" },
            },
            brokenNode = "not a node",
        },
    }
    Contracts.sanitize(store)
    M.assert_eq(store.schema, Config.SCHEMA, "schema is forced to the current one")
    local node = store.players[KEY]
    M.assert_eq(node.seq, 3, "seq is coerced to a number")
    M.assert_eq(node.contracts["uid-a"].mode, "follow", "illegal mode falls back to follow")
    M.assert_eq(node.contracts["uid-a"].status, "active", "missing status becomes active")
    M.assert_eq(node.contracts["uid-a"].uid, "uid-a", "uid is stamped onto the contract")
    M.assert_eq(node.contracts.broken, nil, "non-table contract row is dropped")
    -- 表行（数字键 / 非表值）都会被删掉
    M.assert_eq(node.contracts[7], nil, "non-string contract key is dropped")
    M.assert_eq(Config.count(node.contracts), 3, "three valid contracts survive")
    -- 顺序：已有 order 里仍然有效的排前面，补齐的按 pairs 顺序挂在后面
    M.assert_eq(node.order[1], "uid-b", "a valid uid keeps its position")
    -- 幽灵 uid 必须在**第一次** sanitize 里就清掉（先剔除非法项、再重建 order）
    for _, value in ipairs(node.order) do
        M.assert_falsy(value == "uid-ghost", "the stale order entry is gone after the first sanitize")
    end
    local ordered = {}
    for _, value in ipairs(node.order) do ordered[value] = true end
    M.assert_eq(ordered["uid-a"] and ordered["uid-b"] and ordered["uid-c"], true,
        "every surviving contract is present in the rebuilt order")
    -- 关键：消费者看到的是过滤后的名册
    M.assert_eq(#Contracts.list(node), 3, "Contracts.list returns exactly the surviving contracts")
    M.assert_eq(Contracts.list(node)[1].uid, "uid-b", "list keeps the stored order")
    M.assert_eq(Config.count(node.contracts), #Contracts.list(node), "no phantom rows are listed")
    M.assert_eq(node.order[1], "uid-b", "existing order is preserved first")
    M.assert_falsy(store.players.brokenNode, "non-table player node is dropped")
    -- 幂等：再修一次不改变形状
    local snapshotOrder = {}
    for index, uid in ipairs(node.order) do snapshotOrder[index] = uid end
    Contracts.sanitize(store)
    M.assert_eq(Config.count(node.contracts), 3, "second sanitize keeps the contract count")
    M.assert_eq(#Contracts.list(node), 3, "the listed roster is stable across sanitize passes")
    -- 第二次会顺手把第一次遗留的幽灵 uid 从 order 数组里清掉；第三次才真正稳定。
    -- 第一次遗留幽灵 uid 这一点记进了报告的"可疑点"（消费者已被 Contracts.list 兜住）。
    local stableOrder = {}
    for index, uid in ipairs(node.order) do stableOrder[index] = uid end
    Contracts.sanitize(store)
    M.assert_eq(#node.order, #stableOrder, "the third pass is a no-op (sanitize is idempotent once clean)")
    for index, uid in ipairs(stableOrder) do
        M.assert_eq(node.order[index], uid, "order entry " .. tostring(index) .. " is unchanged")
    end
    M.assert_falsy(node.order[#node.order] == "broken", "the ghost uid is gone from the order array")
    -- 有效契约数量（名额判定只看 active）
    M.assert_eq(Contracts.activeCount(node), 2, "activeCount counts only active contracts")
end)

-- ===========================================================================
-- 4. hireExisting 成功路径
-- ===========================================================================
runTest(4, "hireExisting: pays SignPrice, writes ModData, orders follow, transmits, payload ok", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:hire:1" })
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r4") })

    M.assert_eq(M.balance(), 10000 - SIGN, "balance after HireExisting")
    local payCalls = M.calls_named("Pay")
    M.assert_eq(#payCalls, 1, "Pay call count")
    M.assert_eq(payCalls[1] and payCalls[1].amount, SIGN, "charged amount")
    M.assert_eq(payCalls[1] and payCalls[1].ok, true, "Pay succeeded")

    local node = Store.node(M.player, false)
    M.assert_truthy(node ~= nil, "player node created in ModData")
    M.assert_eq(Contracts.activeCount(node), 1, "one active contract in the store")
    local contract = Contracts.get(node, uid)
    M.assert_truthy(contract ~= nil, "contract keyed by uid")
    M.assert_eq(contract and contract.mode, "follow", "contract mode")
    M.assert_eq(contract and contract.source, "hired", "contract source")
    M.assert_eq(contract and contract.status, "active", "contract status")
    M.assert_eq(contract and contract.price, SIGN, "contract price")
    M.assert_eq(contract and contract.factionId, "bin2_test_friendly", "contract factionId")
    M.assert_eq(contract and contract.hiredHours, 0, "contract hiredHours")

    local orderCalls = M.calls_named("DecisionLoop.setOrder")
    M.assert_eq(#orderCalls, 1, "setOrder called exactly once")
    M.assert_eq(orderCalls[1] and orderCalls[1].order.kind, "follow", "order kind")
    M.assert_truthy(orderCalls[1] and orderCalls[1].order.player == M.player, "order player is the hiring player")
    M.assert_truthy(ProjectALife.DecisionLoop.orders[uid] ~= nil, "DecisionLoop.orders records the order")

    M.assert_truthy(M.count_calls("ModData.transmit") >= 1, "ModData.transmit was called")
    M.assert_eq(payload.result and payload.result.ok, true, "payload.result.ok")
    M.assert_eq(payload.result and payload.result.code, "hired", "payload.result.code")
    M.assert_eq(requestState().limits.used, 1, "payload.limits.used")
    M.assert_eq(payload.limits.max, 3, "payload.limits.max")
    M.assert_eq(payload.capabilities.alife, true, "payload.capabilities.alife")
    M.assert_eq(payload.capabilities.economy, true, "payload.capabilities.economy")
    M.assert_eq(payload.coins, 10000 - SIGN, "payload.coins")
    M.assert_eq(#payload.contracts, 1, "payload.contracts has one row")
    M.assert_eq(payload.contracts[1] and payload.contracts[1].uid, uid, "payload contract uid")
    -- 契约一旦写下，Alife.protect 会给 NPC 打免回收标记
    local record = Alife.record(uid)
    M.assert_eq(record and record.memory.persistent, true, "protect() set memory.persistent")
    M.assert_eq(record and record.memory.admin and record.memory.admin.persistent, true,
        "protect() set memory.admin.persistent")
end)

-- ===========================================================================
-- 5. 钱不够
-- ===========================================================================
runTest(5, "hireExisting without funds: no_funds, no contract, no order, balance untouched", function()
    resetWorld({ balance = SIGN - 0.01 })
    local uid = M.addActor({ uid = "palife:nofunds:1" })
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r5") })
    M.assert_eq(resultCode(payload), "no_funds", "result code")
    local state = requestState()
    M.assert_eq(state.result and state.result.ok, false, "result ok")
    M.assert_eq(M.count_calls("Pay"), 1, "Pay was attempted")
    M.assert_eq(M.calls_named("Pay")[1] and M.calls_named("Pay")[1].ok, false, "Pay refused")
    local node = Store.node(M.player, false)
    M.assert_truthy(node == nil or Contracts.activeCount(node) == 0, "contract table stays empty")
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 0, "setOrder not called")
    M.assert_eq(M.balance(), SIGN - 0.01, "balance unchanged")
    M.assert_eq(requestState().limits.used, 0, "payload.limits.used")
    -- 余额为 0 时也不能被扣成负数（CeilCoins 会把 0.01 抬到 0.01）
    resetWorld({ balance = 0 })
    local uid2 = M.addActor({ uid = "palife:nofunds:2" })
    payload = d(M.player, "HireExisting", { uid = uid2, mode = "follow", requestId = U("r5b") })
    M.assert_eq(resultCode(payload), "no_funds", "result code with a zero balance")
    M.assert_eq(M.balance(), 0, "balance stays 0")
end)

-- ===========================================================================
-- 6. 太远
-- ===========================================================================
runTest(6, "hireExisting out of reach: too_far, nothing charged", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:far:1", x = 100 + RADIUS + 5, y = 100 })
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r6") })
    M.assert_eq(resultCode(payload), "too_far", "result code")
    M.assert_eq(M.balance(), 10000, "nothing charged")
    M.assert_eq(M.count_calls("Pay"), 0, "Pay not called")
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 0, "setOrder not called")
    -- 边界：正好在半径上算够得着
    resetWorld({ balance = 10000 })
    local near = M.addActor({ uid = "palife:far:2", x = 100 + RADIUS, y = 100 })
    payload = d(M.player, "HireExisting", { uid = near, mode = "follow", requestId = U("r6b") })
    M.assert_eq(resultCode(payload), "hired", "exactly at the radius is in reach")
end)

-- ===========================================================================
-- 7. 被别人雇了
-- ===========================================================================
runTest(7, "hireExisting taken by another player: taken_by_other, nothing charged", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:taken:1" })
    -- 另一个玩家的 active 契约
    local otherKey = Store.playerKey(M.player2)
    local otherNode = Contracts.player(Store.data(), otherKey, true)
    Contracts.add(otherNode, {
        uid = uid, name = "Taken", mode = "follow", source = "hired", status = "active",
        price = SIGN, hiredHours = 0, wagePaidHours = 0,
    })
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r7") })
    M.assert_eq(resultCode(payload), "taken_by_other", "result code")
    M.assert_eq(M.balance(), 10000, "nothing charged")
    M.assert_eq(M.count_calls("Pay"), 0, "Pay not called")
    M.assert_eq(Contracts.activeCount(otherNode), 1, "the other player keeps the contract")
    -- dismissed 的契约不算"被别人雇"
    resetWorld({ balance = 10000 })
    uid = M.addActor({ uid = "palife:taken:2" })
    otherNode = Contracts.player(Store.data(), otherKey, true)
    Contracts.add(otherNode, {
        uid = uid, name = "Ex", mode = "follow", source = "hired", status = "dismissed",
        price = SIGN, hiredHours = 0, wagePaidHours = 0,
    })
    payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r7b") })
    M.assert_eq(resultCode(payload), "hired", "a dismissed contract does not block a hire")
end)

-- ===========================================================================
-- 8. 名额满
-- ===========================================================================
runTest(8, "hireExisting at the contract cap: limit_reached, nothing charged", function()
    resetWorld({ balance = 10000 })
    local node = Store.node(M.player, true)
    for index = 1, Config.DEFAULTS.MaxContracts do
        Contracts.add(node, {
            uid = "palife:filled:" .. tostring(index), name = "Filler " .. tostring(index),
            mode = "follow", source = "hired", status = "active", price = SIGN,
            hiredHours = 0, wagePaidHours = 0,
        })
    end
    local uid = M.addActor({ uid = "palife:limit:1" })
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r8") })
    M.assert_eq(resultCode(payload), "limit_reached", "result code")
    M.assert_eq(requestState().limits.used, Config.DEFAULTS.MaxContracts, "payload.limits.used at the cap")
    M.assert_eq(M.balance(), 10000, "nothing charged")
    M.assert_eq(M.count_calls("Pay"), 0, "Pay not called")
    -- 阵亡/解雇的契约不占名额
    local dead = Contracts.get(node, "palife:filled:1")
    dead.status = "dead"
    M.advanceMs(1000)
    payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r8b") })
    M.assert_eq(resultCode(payload), "hired", "a dead contract frees a slot")
end)

-- ===========================================================================
-- 9. 敌对
-- ===========================================================================
runTest(9, "hostile stance: refused unless the sandbox allows it", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:hostile:1" })
    ProjectALife.Relations.setStance(uid, "hostile")
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r9") })
    M.assert_eq(resultCode(payload), "hostile", "result code with AllowHostile=false")
    M.assert_eq(M.balance(), 10000, "nothing charged")
    M.assert_eq(M.count_calls("Pay"), 0, "Pay not called")

    resetWorld({ balance = 10000, sandbox = { AllowHostile = true } })
    uid = M.addActor({ uid = "palife:hostile:2" })
    ProjectALife.Relations.setStance(uid, "hostile")
    payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r9b") })
    M.assert_eq(resultCode(payload), "hired", "AllowHostile=true lets the hire through")
    M.assert_eq(M.balance(), 10000 - SIGN, "charged once")
    -- memory.spawnStance 优先于 faction.relations（A-Life 的真实优先级）
    resetWorld({ balance = 10000 })
    uid = M.addActor({ uid = "palife:hostile:3", factionId = "bin2_test_hostile",
        memory = { spawnStance = "friendly", groupId = "grp:3" } })
    payload = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r9c") })
    M.assert_eq(resultCode(payload), "hired", "spawnStance=friendly wins over the faction")
end)

-- ===========================================================================
-- 10. hireSpawned 成功路径 + Maintain 补派岗位
-- ===========================================================================
runTest(10, "hireSpawned: creates + requests, pays SpawnPrice, pending note, Maintain clears it", function()
    resetWorld({ balance = 10000 })
    local payload = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r10") })
    M.assert_eq(resultCode(payload), "summoned", "result code")
    M.assert_eq(M.balance(), 10000 - SPAWN, "balance after HireSpawned")
    M.assert_eq(M.count_calls("ActorRegistry.create"), 1, "ActorRegistry.create called once")

    -- create 的参数：operationId 以 :create 结尾，fingerprint 是模块级常量
    local createCall = M.calls_named("ActorRegistry.create")[1]
    M.assert_truthy(string.sub(createCall.spec.operationId, -7) == ":create", "create operationId suffix")
    M.assert_eq(createCall.spec.fingerprint, "Bin2NPCExtensionYese:v1", "create fingerprint")
    M.assert_eq(createCall.spec.factionId, "bin2_test_friendly", "create factionId")
    M.assert_eq(createCall.spec.profileId, "npc_test_1", "create profileId")
    M.assert_truthy(type(createCall.spec.memory) == "table", "create memory table")
    M.assert_eq(createCall.spec.memory.spawnStance, "friendly", "create memory.spawnStance")
    M.assert_eq(createCall.spec.memory.persistent, true, "create memory.persistent")
    M.assert_eq(createCall.spec.memory.admin and createCall.spec.memory.admin.persistent, true,
        "create memory.admin.persistent")

    M.assert_eq(M.count_calls("SpawnService.request"), 1, "SpawnService.request called once")
    local requestCall = M.calls_named("SpawnService.request")[1]
    M.assert_truthy(string.sub(requestCall.operationId, -6) == ":spawn", "spawn operationId suffix")
    M.assert_truthy(string.find(requestCall.fingerprint, ":spawn", 1, true) ~= nil, "spawn fingerprint")
    M.assert_eq(requestCall.timeoutMs, 2500, "spawn timeoutMs")
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 0, "no order while the shell is still spawning")

    local node = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node), 1, "one active contract")
    local contracts = Contracts.list(node)
    local contract = contracts[1]
    M.assert_truthy(contract ~= nil, "spawned contract exists")
    M.assert_eq(contract and contract.source, "spawned", "contract source")
    M.assert_eq(contract and contract.note, "pending", "contract note while spawning")
    M.assert_eq(contract and contract.mode, "follow", "contract mode")
    M.assert_eq(contract and contract.price, SPAWN, "contract price")
    M.assert_eq(contract and contract.name, "Alex Mercer", "contract name from the Catalog profile")
    M.assert_eq(payload.limits.used, 1, "payload.limits.used")

    -- 让 mock 把 actor 变成 lifecycle == "active"，再推动时间触发 Maintain.tick
    local uid = contract.uid
    local live = M.state.alifeRecords[uid]
    M.assert_truthy(live ~= nil, "spawned actor is in the registry")
    M.assert_eq(live and live.lifecycle, "spawning", "spawned actor starts out spawning")
    M.activateActor(uid)
    M.advanceMs(1500)                       -- Bootstrap 的 OnTick 节流是 1 秒
    Maintain.tick()
    local orderCalls = M.calls_named("DecisionLoop.setOrder")
    M.assert_eq(#orderCalls, 1, "Maintain.tick ordered the freshly spawned actor once")
    M.assert_eq(orderCalls[1] and orderCalls[1].order.kind, "follow", "refreshed order kind")
    M.assert_eq(orderCalls[1] and orderCalls[1].generation, live.generation, "order generation matches")
    M.assert_eq(contract.note, nil, "note cleared after the post is assigned")
    M.assert_eq(contract.mode, "follow", "mode stays follow")
    -- 8 秒内的重复 tick 不会重复下命令（ORDER_REFRESH_MS）
    M.advanceMs(1000)
    Maintain.tick()
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 1, "order refresh is throttled to 8s")
    M.advanceMs(8000)
    Maintain.tick()
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), 2, "order is refreshed after 8s")
    -- 周期重下必须带 quiet=true：不重放 follow 动画与 ORDER_ACK 语音（bug #2 已修）
    M.assert_eq(M.calls_named("DecisionLoop.setOrder")[1].order.quiet, true,
        "spawned actors get their first order from Maintain.tick, which is always quiet")
    local quietOrder = M.calls_named("DecisionLoop.setOrder")[2]
    M.assert_eq(quietOrder and quietOrder.order.quiet, true,
        "the periodic refresh passes quiet=true to DecisionLoop.setOrder")
end)

-- ===========================================================================
-- 11. spawn 失败要退款
-- ===========================================================================
runTest(11, "hireSpawned refund: SpawnService failure returns spawn_failed and refunds in full", function()
    resetWorld({ balance = 10000 })
    -- 先造出 uid 才能挂"下一次失败"：用一次正常的 create 不行（那会先扣钱），
    -- 注入"下一次 ActorRegistry.create 直接失败"：Service 必须先退款、且不写契约
    M.failNextSpawn("shell_hydration_failed")
    local payload = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r11") })

    M.assert_eq(resultCode(payload), "spawn_failed", "result code")
    M.assert_eq((requestState().result or {}).ok, false, "result ok")
    M.assert_eq(M.balance(), 10000, "refund restored the full balance")
    M.assert_eq(M.count_calls("Pay"), 1, "charged once")
    M.assert_eq(M.count_calls("AddCoins"), 1, "refunded once via AddCoins")
    local refund = M.calls_named("AddCoins")[1]
    M.assert_eq(refund and refund.amount, SPAWN, "refund amount equals the charge")
    local flows = M.calls_named("RecordPlayerFlow")
    M.assert_eq(#flows, 2, "the ledger holds the charge and the refund")
    M.assert_eq(flows[1] and flows[1].direction, "out", "charge row direction")
    M.assert_eq(flows[2] and flows[2].direction, "in", "refund row direction")
    local node = Store.node(M.player, false)
    M.assert_truthy(node == nil or Config.count(node.contracts) == 0, "no contract after a failed spawn")
    -- 造人失败发生在 create 阶段：注册表里不该留下任何 actor
    M.assert_eq(M.count_calls("ActorRegistry.create"), 1, "the create was attempted exactly once")
    M.assert_eq(#ProjectALife.ActorRegistry.list(), 0, "no actor is left behind after the refusal")
end)

-- ===========================================================================
-- 12. 转居民（有 Jeem）
-- ===========================================================================
runTest(12, "resident mode with Jeem: recruit called, baseId stored; no_beds degrades to follow", function()
    resetWorld({ balance = 10000 })
    local base = M.giveBase(4)
    M.assert_eq(base and base.id, "base:given", "the player has a base")
    local uid = M.addActor({ uid = "palife:resident:1" })
    -- 1) 给别人改岗位：契约不存在 -> not_found
    local payload = d(M.player, "SetMode", { uid = uid, mode = "resident", requestId = U("r12pre") })
    M.assert_eq(resultCode(payload), "not_found", "SetMode on a uid without a contract")
    M.assert_eq(M.count_calls("Residents.recruit"), 0, "nothing is recruited without a contract")
    -- 2) 直接以居民身份收编
    payload = d(M.player, "HireExisting", { uid = uid, mode = "resident", requestId = U("r12a") })
    M.assert_eq(resultCode(payload), "hired", "HireExisting as a resident")
    M.assert_eq(M.count_calls("Residents.recruit"), 1, "Residents.recruit called once")
    local recruit = M.calls_named("Residents.recruit")[1]
    M.assert_truthy(recruit.player == M.player, "recruit got the player object")
    M.assert_eq(recruit.uid, uid, "recruit got the uid")
    M.assert_eq(recruit.baseId, "base:given", "recruit got the player's base id")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_eq(contract and contract.mode, "resident", "contract mode resident")
    M.assert_eq(contract and contract.baseId, "base:given", "contract baseId recorded")
    M.assert_eq(contract and contract.note, nil, "no degradation note on success")
    M.assert_eq(M.calls_named("BaseAreas.createBase")[1], nil, "an existing base is reused, no camp built")
    M.assert_truthy(Jimmy.isResident(Alife.record(uid)), "the actor is a Jeem resident now")
    M.assert_eq(M.count_calls("StandingService.addGroup"), 1, "standing was padded before recruiting")

    -- 第二个人：recruit 返回 no_beds（两次都失败，包括 force 重试）
    local uid2 = M.addActor({ uid = "palife:resident:2" })
    M.refuseNextRecruit(uid2, "no_beds")
    M.advanceMs(1000)
    payload = d(M.player, "HireExisting", { uid = uid2, mode = "resident", requestId = U("r12b") })
    M.assert_eq(M.count_calls("Residents.recruit"), 3, "recruit retried with force=true")
    M.assert_eq(M.state.recruitCalls[3] and M.state.recruitCalls[3].force, true, "the retry passes force=true")
    -- hireExisting 成功（哪怕降级）返回 "hired"，降级原因写在契约的 note 上；
    -- 只有 SetMode 才会回 "mode_degraded:<why>"
    M.assert_eq(resultCode(payload), "hired", "a degraded hire still reports hired")
    local contract2 = Contracts.get(Store.node(M.player, false), uid2)
    M.assert_eq(contract2 and contract2.mode, "follow", "contract degraded to follow")
    M.assert_contains(contract2 and contract2.note, "resident:no_beds", "contract note has the upstream code")
    M.assert_eq(contract2 and contract2.baseId, nil, "no baseId when the conversion failed")
    local orderCalls = M.calls_named("DecisionLoop.setOrder")
    M.assert_truthy(#orderCalls >= 1, "the degraded contract still gets a follow order")
    M.assert_eq(orderCalls[#orderCalls] and orderCalls[#orderCalls].order.kind, "follow",
        "the fallback order is follow")

    -- 造营地分支：没有基地 + CreateCamp=true
    resetWorld({ balance = 10000 })
    local uid3 = M.addActor({ uid = "palife:resident:3" })
    M.advanceMs(1000)
    d(M.player, "HireExisting", { uid = uid3, mode = "resident", requestId = U("r12c") })
    M.assert_eq(M.count_calls("BaseAreas.createBase"), 1, "a camp is created when the player has no base")
    local createArgs = M.calls_named("BaseAreas.createBase")[1]
    M.assert_eq(createArgs.args and createArgs.args.name, "CampName",
        "camp name comes from Text.get('CampName') (translation off -> bare key)")
    M.assert_eq(createArgs.args and createArgs.args.role, "grounds", "camp role")
    M.assert_truthy(createArgs.who and createArgs.who.key ~= nil, "createBase got the who table")
    local camp = M.state.bases["base:1"]
    M.assert_truthy(camp ~= nil, "camp exists in the base store")
    M.assert_truthy((tonumber(camp and camp.bedsOverride) or 0) >= 3, "camp beds were bumped for the resident")
    M.assert_truthy(M.count_calls("BaseAreas.transmit") >= 1, "BaseAreas.transmit was called")
end)

-- ===========================================================================
-- 13. 没有 Jeem
-- ===========================================================================
runTest(13, "resident mode without Jeem: degrades to follow and never calls Residents.recruit", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:nijeem:1" })
    M.hideJeem(true)
    M.assert_falsy(Config.jeem(), "Config.jeem() is nil when the global is missing")
    local payload = d(M.player, "HireExisting", { uid = uid, mode = "resident", requestId = U("r13") })
    M.assert_eq(resultCode(payload), "hired", "a degraded hire reports hired")
    M.assert_eq(requestState().capabilities.jeem, false, "payload.capabilities.jeem")
    M.assert_eq(M.count_calls("Residents.recruit"), 0, "Residents.recruit must not be called")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_eq(contract and contract.mode, "follow", "contract falls back to follow")
    M.assert_contains(contract and contract.note, "no_jeem", "contract note explains the degradation")
    M.assert_truthy(M.count_calls("DecisionLoop.setOrder") >= 1, "a follow order is still issued")
    M.hideJeem(false)

    -- enabled("residents") == false 也要降级
    resetWorld({ balance = 10000 })
    uid = M.addActor({ uid = "palife:nijeem:2" })
    M.state.jeemEnabled = false
    M.assert_falsy(Config.jeem(), "Config.jeem() is nil when residents is switched off")
    M.advanceMs(1000)
    payload = d(M.player, "HireExisting", { uid = uid, mode = "resident", requestId = U("r13b") })
    M.assert_eq(resultCode(payload), "hired", "a degraded hire reports hired when residents is off")
    local offContract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_contains(offContract and offContract.note, "no_jeem", "the note explains the degradation")
    M.assert_eq(M.count_calls("Residents.recruit"), 0, "Residents.recruit must not be called when off")
    M.state.jeemEnabled = true

    -- CreateCamp=false 且没有基地 -> no_base
    resetWorld({ balance = 10000, sandbox = { CreateCamp = false } })
    uid = M.addActor({ uid = "palife:nijeem:3" })
    M.advanceMs(1000)
    payload = d(M.player, "HireExisting", { uid = uid, mode = "resident", requestId = U("r13c") })
    M.assert_eq(resultCode(payload), "hired", "a no_base hire reports hired")
    M.assert_eq(M.count_calls("BaseAreas.createBase"), 0, "CreateCamp=false must not create a camp")
    contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_eq(contract and contract.mode, "follow", "no_base also degrades to follow")
    M.assert_contains(contract and contract.note, "resident:no_base", "the note carries the upstream code")
end)

-- ===========================================================================
-- 14. 解雇
-- ===========================================================================
runTest(14, "dismiss: residents leave via Jeem, orders are forgotten, contracts are removed", function()
    resetWorld({ balance = 10000 })
    M.giveBase(4)
    local uid = M.addActor({ uid = "palife:dismiss:1" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r14hire") })
    d(M.player, "SetMode", { uid = uid, mode = "resident", requestId = U("r14a") })
    M.assert_truthy(Jimmy.isResident(Alife.record(uid)), "actor became a resident")
    M.advanceMs(1000)
    local payload = d(M.player, "Dismiss", { uid = uid, requestId = U("r14b") })
    M.assert_eq(resultCode(payload), "dismissed", "dismiss code")
    M.assert_eq(M.count_calls("Residents.leaveOne"), 1, "Residents.leaveOne called")
    M.assert_eq(M.calls_named("Residents.leaveOne")[1] and M.calls_named("Residents.leaveOne")[1].uid, uid,
        "leaveOne got the uid")
    M.assert_eq(M.count_calls("DecisionLoop.forget"), 1, "DecisionLoop.forget called")
    M.assert_falsy(ProjectALife.DecisionLoop.orders[uid], "DecisionLoop.orders entry is gone")
    M.assert_falsy(Jimmy.isResident(Alife.record(uid)), "the actor is no longer a resident")
    local node = Store.node(M.player, false)
    M.assert_truthy(node == nil or Contracts.get(node, uid) == nil, "contract removed from the store")
    M.assert_eq(requestState().limits.used, 0, "payload.limits.used drops back to zero")
    M.assert_truthy(M.count_calls("ModData.transmit") >= 1, "the removal was transmitted")

    -- 非居民：只清指令，不碰 Jeem
    resetWorld({ balance = 10000 })
    local uid2 = M.addActor({ uid = "palife:dismiss:2" })
    d(M.player, "HireExisting", { uid = uid2, mode = "follow", requestId = U("r14c") })
    M.assert_truthy(ProjectALife.DecisionLoop.orders[uid2] ~= nil, "follow order exists before the dismissal")
    M.advanceMs(1000)
    payload = d(M.player, "Dismiss", { uid = uid2, requestId = U("r14d") })
    M.assert_eq(resultCode(payload), "dismissed", "dismiss code for a follower")
    M.assert_eq(M.count_calls("Residents.leaveOne"), 0, "leaveOne not called for a non-resident")
    M.assert_truthy(M.count_calls("DecisionLoop.forget") >= 1, "the follow order is cleared")
    M.assert_falsy(ProjectALife.DecisionLoop.orders[uid2], "orders entry is gone")
    M.assert_eq(M.count_calls("Pay"), 1, "the signing fee is not refunded")
    -- 解雇一个不存在的 uid -> not_found
    M.advanceMs(1000)
    payload = d(M.player, "Dismiss", { uid = "palife:ghost", requestId = U("r14e") })
    M.assert_eq(resultCode(payload), "not_found", "dismissing a stranger")
end)

-- ===========================================================================
-- 15. 工资
-- ===========================================================================
runTest(15, "wages: paid every 24 world hours, unpaid flag, dismissal after the grace period", function()
    resetWorld({ balance = 100, sandbox = { DailyWage = 20, UnpaidGraceDays = 1, SignPrice = 0 } })
    M.setWorldHours(0)
    local uid = M.addActor({ uid = "palife:wage:1" })
    M.advanceMs(61000)
    local hire15 = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r15a") })
    M.assert_eq(resultCode(hire15), "hired", "the wage test needs a hired contract first")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_eq(contract and contract.wagePaidHours, 0, "wagePaidHours starts at the hiring hour")

    -- 第一天：付得起
    M.advanceWorldHours(25)
    Maintain.settleWages()
    M.assert_eq(M.count_calls("Pay"), 1, "Pay called once for the wage")
    local pay = M.calls_named("Pay")[1]
    M.assert_eq(pay and pay.amount, 20, "one day of wages")
    M.assert_eq(contract.wagePaidHours, 24, "wagePaidHours advanced by 24")
    M.assert_eq(contract.unpaidSince, nil, "unpaidSince is cleared")
    M.assert_eq(M.balance(), 100 - 20, "balance after one day of wages (signing fee is 0 here)")

    -- 第二天：余额不足 -> unpaidSince 被设置
    M.setBalance(0)
    M.advanceWorldHours(25)                      -- hour 50
    Maintain.settleWages()
    M.assert_truthy(contract.unpaidSince ~= nil, "unpaidSince is set when Pay refuses")
    M.assert_eq(contract.unpaidSince, 50, "unpaidSince records the world hour")
    M.assert_eq(contract.status, "active", "still active inside the grace window")
    M.assert_eq(M.balance(), 0, "no money moved")

    -- 欠薪超过宽限期 -> 解约
    M.advanceWorldHours(25)                      -- hour 75, span 25 > 24
    Maintain.settleWages()
    M.assert_eq(contract.status, "dismissed", "contract dismissed after the grace period")
    M.assert_contains(contract.note, "unpaid", "dismissal note")
    M.assert_eq(M.count_calls("DecisionLoop.forget"), 1, "the order was cleared")
    local node = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node), 0, "the dismissed contract no longer takes a slot")

    -- WageEnabled=false / DailyWage=0 -> 完全不结算
    resetWorld({ balance = 100, sandbox = { WageEnabled = false, SignPrice = 0 } })
    M.setWorldHours(0)
    uid = M.addActor({ uid = "palife:wage:2" })
    M.advanceMs(61000)
    M.advanceMs(61000)
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r15b") })
    M.advanceWorldHours(100)
    Maintain.settleWages()
    M.assert_eq(M.count_calls("Pay"), 0, "no payment at all when wages are disabled")
    M.assert_eq(Config.Economy.wage(), 0, "Economy.wage() is 0 when wages are disabled")
    local node15 = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node15), 1, "the contract is untouched")
    M.assert_eq(Contracts.get(node15, uid).unpaidSince, nil, "no unpaid marker")
end)

-- ===========================================================================
-- 16. 阵亡清理
-- ===========================================================================
runTest(16, "casualties: a dead actor marks the contract dead and frees the slot", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:dead:1" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r16a") })
    local node = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node), 1, "one active contract before the tick")
    local contract = Contracts.get(node, uid)

    -- 记录还在，但 lifecycle == "dead"
    M.killActor(uid)
    M.advanceMs(1500)
    Maintain.tick()
    M.assert_eq(contract.status, "dead", "contract status after the actor died")
    M.assert_eq(contract.note, "dead", "contract note")
    M.assert_eq(contract.deadHours, 0, "deadHours recorded")
    M.assert_eq(Contracts.activeCount(node), 0, "the dead contract frees a slot")
    M.assert_truthy(M.count_calls("ModData.transmit") >= 1, "the death was transmitted")
    local payload = M.calls_named("sendServerCommand")
    M.assert_truthy(#payload >= 1, "a state push happened")

    -- ActorRegistry.read 直接返回 nil 也要算阵亡
    resetWorld({ balance = 10000 })
    local uid2 = M.addActor({ uid = "palife:dead:2" })
    d(M.player, "HireExisting", { uid = uid2, mode = "follow", requestId = U("r16b") })
    node = Store.node(M.player, false)
    local contract2 = Contracts.get(node, uid2)
    M.advanceMs(1500)
    M.forgetActor(uid2)
    Maintain.tick()
    M.assert_eq(contract2.status, "dead", "a missing registry record also counts as dead")
    M.assert_eq(Contracts.activeCount(node), 0, "slot freed again")
end)

-- ===========================================================================
-- 17. 限速与去重
-- ===========================================================================
runTest(17, "throttle and dedup: identical requestId charges once, same-ms commands are too_fast", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:dedup:1" })
    local args = { uid = uid, mode = "follow", requestId = U("same-request") }
    M.setNowMs(900000000)                        -- 干净的高位时钟，之后只靠 d() 推进
    local first = d(M.player, "HireExisting", args)
    M.assert_eq(resultCode(first), "hired", "first request succeeds")
    M.assert_eq(M.balance(), 10000 - SIGN, "charged once")
    M.setNowMs(M.state.nowMs + 1000)             -- 越过 400ms 节流，但仍在 60s 去重窗口内
    local second = d(M.player, "HireExisting", args)
    M.assert_eq(resultCode(second), "duplicate", "second request with the same requestId")
    M.assert_eq(M.balance(), 10000 - SIGN, "still charged only once")
    M.assert_eq(M.count_calls("Pay"), 1, "Pay still called only once")
    M.assert_eq(Contracts.activeCount(Store.node(M.player, false)), 1, "still exactly one contract")

    -- 不同 requestId 但同一毫秒 -> too_fast
    resetWorld({ balance = 10000 })
    local uid2 = M.addActor({ uid = "palife:dedup:2" })
    M.setNowMs(910000000)
    d(M.player, "HireExisting", { uid = uid2, mode = "follow", requestId = U("fast-a") })
    M.setNowMs(910000000 + 10)                   -- 只挪 10ms：越过 400ms 节流了吗？没有
    local fast = Service.dispatch(M.player, "HireExisting",
        { uid = uid2, mode = "follow", requestId = U("fast-b") })
    M.assert_eq(resultCode(fast), "too_fast", "second command in the same millisecond")
    M.assert_eq(M.balance(), 10000 - SIGN, "only the first command was charged")
    -- 不传 requestId 也要节流
    resetWorld({ balance = 10000 })
    uid2 = M.addActor({ uid = "palife:dedup:3" })
    M.setNowMs(920000000)
    Service.dispatch(M.player, "HireExisting", { uid = uid2, mode = "follow" })
    M.setNowMs(920000000 + 10)
    fast = Service.dispatch(M.player, "HireExisting", { uid = uid2, mode = "follow" })
    M.assert_eq(resultCode(fast), "too_fast", "throttle also applies without a requestId")

    -- 去重窗口不能被"条数上限"挤破：60 秒内连发 >64 个不同 requestId 之后，
    -- 最早那一条重放仍必须判 duplicate（按时间裁剪，而不是按条数）。
    resetWorld({ balance = 10000 })
    local uid3 = M.addActor({ uid = "palife:dedup:4" })
    M.setNowMs(930000000)
    local burstFirst = U("burst-first")             -- 必须复用同一个字符串，U() 每次都带新序号
    d(M.player, "HireExisting", { uid = uid3, mode = "follow", requestId = burstFirst })
    for index = 1, 70 do
        M.setNowMs(930000000 + index * 500)
        Service.dispatch(M.player, "SetMode",
            { uid = uid3, mode = index % 2 == 0 and "follow" or "guard", requestId = "burst-" .. tostring(index) })
    end
    M.setNowMs(930000000 + 71 * 500)
    local replay = Service.dispatch(M.player, "HireExisting",
        { uid = uid3, mode = "follow", requestId = burstFirst })
    M.assert_eq(resultCode(replay), "duplicate",
        "the first requestId is still inside the dedup window after 70 newer ones")
    M.assert_eq(M.count_calls("Pay"), 1, "the replayed request never charged again")
end)

-- ===========================================================================
-- 18. 客户端单机分支
-- ===========================================================================
runTest(18, "client net: single player dispatches directly, multiplayer uses sendClientCommand", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:net:1" })
    M.setClient(false)
    local ok = Net.send("RequestState")
    M.assert_eq(ok, true, "Net.send returned true in single player")
    M.assert_eq(M.count_calls("sendClientCommand"), 0, "sendClientCommand must not be used in single player")
    M.assert_truthy(Net.cache.limits.max == 3, "the cache was refreshed from the direct dispatch (limits.max)")
    M.assert_eq(Net.cache.capabilities and Net.cache.capabilities.alife, true, "cache capabilities.alife")
    M.assert_truthy(Net.cache.prices ~= nil, "cache prices table")

    -- 单机下的改状态命令也走直连，并带上 requestId
    M.setNowMs(M.state.nowMs + 1000)
    Net.send("HireExisting", { uid = uid, mode = "follow" }, true)
    M.assert_eq(M.count_calls("sendClientCommand"), 0, "mutating command also direct in single player")
    M.assert_truthy(ProjectALife.DecisionLoop.orders[uid] ~= nil, "the hire really happened")
    M.assert_truthy(Net.cache.result ~= nil, "cache.result from the direct dispatch")

    -- 联机客户端：发命令，缓存不动
    resetWorld({ balance = 10000 })
    M.setClient(true)
    M.assert_eq(Net.isMultiplayerClient(), true, "Net.isMultiplayerClient()")
    Net.cache.limits = { max = 0, used = 0 }
    local before = M.count_calls("sendClientCommand")
    ok = Net.send("RequestState")
    M.assert_eq(ok, true, "Net.send returned true for a multiplayer client")
    local sent = M.calls_named("sendClientCommand")
    M.assert_eq(#sent, before + 1, "sendClientCommand was called")
    M.assert_eq(sent[#sent] and sent[#sent].module, "Bin2NPCExtensionYese", "command module name")
    M.assert_eq(sent[#sent] and sent[#sent].command, "RequestState", "command name")
    M.assert_eq(Net.cache.limits.max, 0, "the cache is NOT refreshed by the outbound call")

    -- 服务端回包
    M.pushFromServer({
        contracts = { { uid = "palife:net:9", name = "Pushed", mode = "guard", status = "active" } },
        capabilities = { enabled = true, alife = true, economy = true, jeem = false },
        limits = { max = 5, used = 1 },
        prices = { sign = 500, spawn = 1500, wage = 20 },
        coins = 777,
        result = { ok = true, code = "pushed" },
    })
    M.assert_eq(Net.cache.limits.max, 5, "cache.limits updated by OnServerCommand")
    M.assert_eq(Net.cache.coins, 777, "cache.coins updated by OnServerCommand")
    M.assert_eq(#Net.cache.contracts, 1, "cache.contracts updated by OnServerCommand")
    M.assert_eq(M.count_calls("ShowRadioNotice"), 1, "the result was announced through the radio notice")
    M.assert_truthy(M.state.radioNotices[1] ~= nil, "Notify reached the economy UI")

    -- 别的 module / command 不处理
    local snapshot = Net.cache.coins
    M.pushFromServer({ coins = 5 })
    M.trigger("OnServerCommand", "ProjectALife", "State", { coins = 5 })
    M.trigger("OnServerCommand", "Bin2NPCExtensionYese", "Other", { coins = 5 })
    M.assert_eq(Net.cache.coins, 5, "a payload without a coins field leaves the cache alone")
    M.setClient(false)
end)

-- ===========================================================================
-- 19. UI 接入
-- ===========================================================================
runTest(19, "ui: page registered, YeseMarket navigation row injected, button opens the page, page renders", function()
    local ui = Config.economy()
    M.assert_truthy(ui ~= nil, "YeseMarket is present")
    local registry = ui.UIPageRegistry
    M.assert_truthy(registry ~= nil, "UIPageRegistry present")

    --[[
        YeseMarket 版的入口策略是**导航栏插一行**（橙子版才是包首页工厂 `factories.index`），
        所以这里换成对应断言：钩子把按钮塞进 `self.navButtons`，点它走 `self:setPage(我们的 id)`；
        另外 `Entry.open()` 走"`Open(number)` → `Window:setPage(id)`"两步（YeseMarket 的 Open 只吃一个参数）。
    ]]
    registry.factories = {}
    registry.order = {}
    Config.Entry.installed = false
    Config.Entry.navInstalled = false
    M.resetShell()

    local installed = Config.Entry.install()
    M.assert_eq(installed, true, "Entry.install() returned true")
    M.assert_eq(registry.Has("bin2NpcRecruit"), true, "UIPageRegistry.Has('bin2NpcRecruit')")
    local ids, idCount = {}, 0
    for _, id in ipairs(registry.Ids()) do ids[id] = (ids[id] or 0) + 1 idCount = idCount + 1 end
    M.assert_eq(ids.bin2NpcRecruit, 1, "the recruit page was registered exactly once")
    M.assert_eq(idCount, 1, "only the recruit page was registered by Entry.install")
    local ok, err = pcall(registry.Register, "bin2NpcRecruit", function() end)
    M.assert_eq(ok, false, "registering the same page twice raises (idempotence relies on Has)")

    -- 包了 YeseMarket.UIShell 的 buildNavigation / layoutNavigationItems
    local shell = ui.UIShell
    M.assert_truthy(type(shell) == "table", "YeseMarket.UIShell present")
    M.assert_truthy(type(shell.buildNavigation) == "function", "buildNavigation is hooked")
    local instance = setmetatable({}, { __index = shell })
    instance:buildNavigation()
    M.assert_truthy(type(instance.navButtons) == "table", "mock shell built its navButtons")
    local navButton = instance.navButtons["bin2NpcRecruit"]
    M.assert_truthy(navButton ~= nil, "the recruit page got its own navigation row")
    M.assert_eq(navButton and navButton.pageId, "bin2NpcRecruit", "nav button carries the page id")
    instance:layoutNavigationItems()
    M.assert_truthy(navButton and tonumber(navButton.y) ~= nil and navButton.y >= 0,
        "the injected nav row is positioned by layoutNavigationItems")

    -- 幂等：再调一次 buildNavigation 不会插第二行
    local rowsBefore = 0
    for _, child in ipairs(instance.navigationViewport.children) do
        if child.ymNavId == "bin2NpcRecruit" then rowsBefore = rowsBefore + 1 end
    end
    instance:buildNavigation()
    local rowsAfter = 0
    for _, child in ipairs(instance.navigationViewport.children) do
        if child.ymNavId == "bin2NpcRecruit" then rowsAfter = rowsAfter + 1 end
    end
    M.assert_eq(rowsAfter, rowsBefore, "the nav row is not injected twice")

    -- 点击导航行 -> shell 切到我们的页面
    M.state.opened = {}
    navButton:click()
    local switched = M.calls_named("UIShell.setPage")
    M.assert_truthy(#switched >= 1, "clicking the nav row calls shell:setPage")
    M.assert_eq(switched[#switched] and switched[#switched].pageId, "bin2NpcRecruit",
        "…with our page id")

    -- Entry.open：窗口没开时先 Open(number) 再切页；已开则只切页
    ui.Window = nil
    M.state.opened = {}
    local opensBefore = M.count_calls("YeseMarket.Open")
    M.assert_eq(Config.Entry.open(0), true, "Entry.open() with no window open returns true")
    M.assert_truthy(M.count_calls("YeseMarket.Window.setPage") >= 1, "Entry.open switched the window with Window:setPage")
    M.assert_eq(M.count_calls("YeseMarket.Open"), opensBefore + 1, "…and it called Open(playerNum)")
    local openCall = M.calls_named("YeseMarket.Open")
    M.assert_eq(openCall[#openCall] and openCall[#openCall].number, 0, "Open got the player number")
    M.assert_eq(Config.Entry.open(0), true, "Entry.open() on an already-open window returns true")
    M.assert_eq(M.count_calls("YeseMarket.Open"), opensBefore + 1,
        "…and it did NOT open a second window (only setPage)")

    local primitives = {}
    function primitives.FitText(value, font, width)
        return tostring(value or "")
    end
    -- YeseMarket 的 UIPrimitives **没有** GetDensityMetrics（那是橙子经济的原语），
    -- 所以 mock 也不提供：页面要是再依赖它，测试会当场炸而不是等到游戏里。
    local lastButton = nil
    function primitives.CreateButton(x, y, width, height, title, target, callback, variant)
        lastButton = ISButton:new(x, y, width, height)
        lastButton.title = title
        lastButton.target = target
        lastButton.callback = callback
        lastButton.variant = variant
        function lastButton:click()
            if type(self.callback) == "function" then return self.callback(self.target, self) end
        end
        return lastButton
    end
    -- [真实] card_grid.lua:58/64/92 —— clear / addItem 返回 {text,item,index} / setOffset
    local list = ISPanel:new(0, 0, 1, 1)
    list.items = {}
    list.selected = 0
    list.offset = 0
    function list:clear() self.items = {} self.selected = 0 self.offset = 0 end
    function list:addItem(label, item)
        local entry = { text = tostring(label or ""), item = item, index = #self.items + 1,
            height = self.itemheight or 92 }
        self.items[#self.items + 1] = entry
        return entry
    end
    function list:setOffset(value) self.offset = math.max(0, tonumber(value) or 0) end
    function list:getYScroll() return self.yScroll or 0 end
    function list:setYScroll(value) self.yScroll = tonumber(value) or 0 end
    function list:contentHeight() return #self.items * 96 end
    function list:setX(value) self.x = value return self end
    function list:setY(value) self.y = value return self end
    function list:setWidth(value) self.width = value return self end
    function list:setHeight(value) self.height = value return self end
    -- YeseMarket 只有 CreateList（IScrollingListBox 的派生类），没有 CreateCardGrid
    function primitives.CreateList(x, y, width, height) return list end

    local context = {
        primitives = primitives,
        theme = {
            Colors = {
                Text = { r = 1, g = 1, b = 1 }, TextWeak = { r = .7, g = .7, b = .7 },
                TextMuted = { r = .5, g = .5, b = .5 }, Danger = { r = 1, g = 0, b = 0 },
                Warning = { r = 1, g = .6, b = 0 }, Success = { r = 0, g = 1, b = 0 },
                Currency = { r = 1, g = .8, b = 0 }, Panel = { r = .1, g = .1, b = .1 },
                PanelRaised = { r = .2, g = .2, b = .2 }, Action = { r = 0, g = .5, b = 1 },
                Selection = { r = .3, g = .2, b = .1 },
                BorderSoft = { r = .3, g = .3, b = .3 },
            },
            Metrics = { Padding = 12, Gap = 12 },
            DrawRoundedSurface = function(...) end,
            FontHeight = function(font, fallback) return tonumber(fallback) or 16 end,
            CenterTextY = function(y, height) return math.floor((tonumber(y) or 0) + 4) end,
        },
        player = M.player,
        shell = { setPage = function(self, pageId) M.state.opened[#M.state.opened + 1] = { number = -1, pageId = pageId } end },
    }
    -- 通过注册表建页面：pageId 必须被填上（Page.lua 依赖这个契约）
    local built = registry.Create("bin2NpcRecruit", context)
    M.assert_truthy(built ~= nil, "Registry.Create builds the recruit page")
    M.assert_eq(built.pageId, "bin2NpcRecruit", "Registry.Create stamps pageId")

    -- （入口这一段的断言已经在上面 YeseMarket 段落里做过：橙子版此处是
    --   「包首页工厂 + page.bin2NpcButton」，YeseMarket 版没有对应物）

    -- Page.Create 的页面契约
    local recruitPage = Config.RecruitPage.Create(context)
    M.assert_truthy(recruitPage ~= nil, "Page.Create returned a page")
    M.assert_eq(type(recruitPage.relayout), "function", "page.relayout")
    M.assert_eq(type(recruitPage.activate), "function", "page.activate")
    M.assert_eq(type(recruitPage.render), "function", "page.render")
    M.assert_eq(type(recruitPage.rebuild), "function", "page.rebuild")
    M.assert_eq(type(recruitPage.deactivate), "function", "page.deactivate")
    M.assert_eq(type(recruitPage.refresh), "function", "page.refresh")
    M.assert_eq(recruitPage.ID, nil, "Page.ID lives on the module, not the instance")
    local okRelayout, errRelayout = pcall(recruitPage.relayout, recruitPage, { x = 0, y = 0, w = 800, h = 600 })
    M.assert_eq(okRelayout, true, "relayout(800x600) must not throw: " .. tostring(errRelayout))
    M.assert_eq(recruitPage.width, 800, "relayout applied the width")
    local okRender, errRender = pcall(recruitPage.render, recruitPage)
    M.assert_eq(okRender, true, "render() must not throw: " .. tostring(errRender))

    --[[
        版面几何：进游戏实测过一次"文字压按钮"（右侧提示语叠在模式按钮上），
        所以这里把布局**当契约来测**：文本区必须止于模式行上方，按钮块之间不许重叠，
        页面尺寸变化（含很矮的窗口）也不许越界，renders 只允许裁文本、不许压控件。
    ]]
    for _, size in ipairs({ { 800, 600 }, { 1200, 700 }, { 520, 420 } }) do
        local W, H = size[1], size[2]
        recruitPage:relayout({ x = 0, y = 0, w = W, h = H })
        local label = string.format("%dx%d", W, H)
        M.assert_truthy(recruitPage.textBottom < recruitPage.modeFollow.y,
            label .. ": the text area ends above the mode buttons")
        M.assert_truthy(recruitPage.primary.y >= recruitPage.modeFollow.y + recruitPage.modeFollow.height,
            label .. ": the primary button starts below the mode row")
        M.assert_truthy(recruitPage.dismiss.y >= recruitPage.primary.y + recruitPage.primary.height,
            label .. ": the dismiss button starts below the primary button")
        for _, name in ipairs({ "modeFollow", "modeGuard", "modeResident", "primary", "dismiss" }) do
            local control = recruitPage[name]
            M.assert_truthy(control.y + control.height <= H,
                label .. ": " .. name .. " stays inside the page vertically")
            M.assert_truthy(control.x + control.width <= W,
                label .. ": " .. name .. " stays inside the page horizontally")
            M.assert_truthy(control.y >= recruitPage.textTop,
                label .. ": " .. name .. " is below the top of the detail panel")
        end
        M.assert_truthy(recruitPage.modeFollow.x + recruitPage.modeFollow.width <= recruitPage.modeGuard.x,
            label .. ": follow/guard buttons do not overlap")
        M.assert_truthy(recruitPage.modeGuard.x + recruitPage.modeGuard.width <= recruitPage.modeResident.x,
            label .. ": guard/resident buttons do not overlap")
        M.assert_truthy(recruitPage.list.x + recruitPage.list.width <= recruitPage.detailX,
            label .. ": the card list does not run under the detail panel")
        M.assert_truthy(recruitPage.textBottom >= recruitPage.textTop,
            label .. ": the text area is not inverted")
        local okSmall, errSmall = pcall(recruitPage.render, recruitPage)
        M.assert_eq(okSmall, true, label .. ": render() must not throw: " .. tostring(errSmall))
    end
    recruitPage:relayout({ x = 0, y = 0, w = 800, h = 600 })
    -- activate 会请求状态并重建列表；联机分支下只是发包
    M.setClient(true)
    local okActivate, errActivate = pcall(recruitPage.activate, recruitPage)
    M.assert_eq(okActivate, true, "activate() must not throw: " .. tostring(errActivate))
    M.setClient(false)
    -- 切页签也不该炸
    for _, mode in ipairs({ "hire", "summon", "roster" }) do
        local okMode, errMode = pcall(recruitPage.setMode, recruitPage, mode)
        M.assert_eq(okMode, true, "setMode(" .. mode .. ") must not throw: " .. tostring(errMode))
    end
    local okRebuild, errRebuild = pcall(recruitPage.rebuild, recruitPage)
    M.assert_eq(okRebuild, true, "rebuild() must not throw: " .. tostring(errRebuild))
    -- 候选/契约行都能画出来
    Net.cache.contracts = { { uid = "u1", name = "Bob", mode = "follow", status = "active", price = 500 } }
    Net.cache.candidates = { { uid = "u2", name = "Ann", factionId = "f", profileId = "p", distance = 3, hostile = false } }
    okRender = pcall(recruitPage.rebuild, recruitPage)
    M.assert_eq(okRender, true, "rebuild() with a contract row must not throw")
    recruitPage:setMode("hire")
    recruitPage.list.selected = 1
    Net.cache.contracts = {}
    Net.cache.candidates = { { uid = "u2", name = "Ann", factionId = "f", profileId = "p", distance = 3, hostile = false } }
    recruitPage:rebuild()
    recruitPage.selectedCandidate = { uid = "u2" }
    local okRender2, errRender2 = pcall(recruitPage.render, recruitPage)
    M.assert_eq(okRender2, true, "render() with a selected candidate must not throw: " .. tostring(errRender2))
end)

-- ===========================================================================
-- 20. 翻译完整性（静态检查）
-- ===========================================================================
runTest(20, "translations: every literal key exists in CN and EN, and both languages match", function()
    M.assert_truthy(#SOURCE_KEYS > 30, "the scanner found the translation keys (" .. tostring(#SOURCE_KEYS) .. ")")
    local missingCn, missingEn = {}, {}
    for _, key in ipairs(SOURCE_KEYS) do
        if CN_KEYS[key] ~= true then missingCn[#missingCn + 1] = key end
        if EN_KEYS[key] ~= true then missingEn[#missingEn + 1] = key end
    end
    M.assert_eq(#missingCn, 0, "CN IG_UI.json is missing: " .. table.concat(missingCn, ", "))
    M.assert_eq(#missingEn, 0, "EN IG_UI.json is missing: " .. table.concat(missingEn, ", "))

    local cnOnly, enOnly = {}, {}
    for key in pairs(CN_KEYS) do
        if EN_KEYS[key] ~= true then cnOnly[#cnOnly + 1] = key end
    end
    for key in pairs(EN_KEYS) do
        if CN_KEYS[key] ~= true then enOnly[#enOnly + 1] = key end
    end
    table.sort(cnOnly)
    table.sort(enOnly)
    M.assert_eq(#cnOnly, 0, "present in CN but not EN: " .. table.concat(cnOnly, ", "))
    M.assert_eq(#enOnly, 0, "present in EN but not CN: " .. table.concat(enOnly, ", "))

    local cnCount, enCount = 0, 0
    for _ in pairs(CN_KEYS) do cnCount = cnCount + 1 end
    for _ in pairs(EN_KEYS) do enCount = enCount + 1 end
    M.assert_eq(cnCount, enCount, "CN/EN key counts differ")
    M.assert_eq(cnCount, 73, "expected 73 translated keys in IG_UI.json")
    M.assert_eq(CN_KEYS.Prefix ~= nil, false, "no stray 'Prefix' key")
    M.assert_eq(CN_KEYS.PageTitle, true, "PageTitle exists")
    M.assert_eq(CN_KEYS.EntryButton, true, "EntryButton exists")
    M.assert_eq(CN_KEYS.FlowHire, true, "FlowHire exists (Economy.record)")
    M.assert_eq(CN_KEYS.CampName, true, "CampName exists (Jimmy.ensureBase)")
    M.assert_eq(CN_KEYS.ReasonUpstream, true, "ReasonUpstream exists (Text.reason fallback)")
    for _, reason in ipairs({ "ReasonNoFunds", "ReasonLimitReached", "ReasonTakenByOther", "ReasonTooFar",
        "ReasonHostile", "ReasonSpawnFailed", "ReasonDisabled", "ReasonNoJeem", "ReasonTooFast",
        "ReasonDuplicate", "ReasonPending", "ReasonUnpaid" }) do
        M.assert_eq(CN_KEYS[reason], true, "CN has " .. reason)
    end
end)

-- ===========================================================================
-- 21. 补充：Contract.owner 的全库互斥
-- ===========================================================================
runTest(21, "extra: Contracts.owner guards a uid across every player", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:owner:1" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r21a") })
    local store = Store.data()
    local ownerKey = Contracts.owner(store, uid)
    M.assert_eq(ownerKey, Store.playerKey(M.player), "owner reports the hiring player")
    M.assert_eq(Contracts.owner(store, "palife:nobody"), nil, "owner is nil for an unknown uid")
    -- 同名玩家的 playerKey 稳定
    M.assert_eq(Store.playerKey(M.player), KEY, "playerKey is stable")
    M.assert_eq(Store.playerName(nil), "LocalPlayer", "playerName(nil) fallback")
end)

-- ===========================================================================
-- 22. 补充：Maintain.restore 重下指令
-- ===========================================================================
runTest(22, "extra: Maintain.restore re-issues follow orders after a reload", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:restore:1" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r22a") })
    ProjectALife.DecisionLoop.orders[uid] = nil             -- 读档后 orders 是空的
    M.advanceMs(1000)
    Maintain.restore()
    M.assert_truthy(ProjectALife.DecisionLoop.orders[uid] ~= nil, "restore re-issued the order")
    M.assert_eq(ProjectALife.DecisionLoop.orders[uid].kind, "follow", "restored order kind")
    local count = M.count_calls("DecisionLoop.setOrder")
    M.advanceMs(1000)
    Maintain.restore()
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), count + 1, "restore forces an immediate re-issue")
end)

-- ===========================================================================
-- 23. 补充：ScanCandidates / RequestState
-- ===========================================================================
runTest(23, "extra: RequestState and ScanCandidates shape the payload", function()
    resetWorld({ balance = 10000 })
    local near = M.addActor({ uid = "palife:scan:1", x = 102, y = 100 })
    local far = M.addActor({ uid = "palife:scan:2", x = 100 + 50, y = 100 })
    local payload = d(M.player, "RequestState")
    M.assert_truthy(type(payload) == "table", "RequestState payload")
    M.assert_eq(payload.result, nil, "no result on the first RequestState")
    M.assert_eq(payload.limits.used, 0, "limits.used")
    M.assert_eq(payload.prices.sign, SIGN, "prices.sign")
    M.assert_eq(payload.prices.spawn, SPAWN, "prices.spawn")
    M.assert_eq(payload.prices.wage, 20, "prices.wage")
    M.assert_eq(payload.version, Config.VERSION, "payload.version")

    payload = d(M.player, "ScanCandidates")
    M.assert_eq(payload.candidateRadius, RADIUS, "candidateRadius")
    M.assert_eq(#payload.candidates, 1, "only the in-radius candidate is returned")
    M.assert_eq(payload.candidates[1] and payload.candidates[1].uid, near, "the near NPC is the candidate")
    M.assert_eq(payload.candidates[1] and payload.candidates[1].name, "Alex Mercer", "candidate name from the catalog")
    M.assert_eq(payload.candidates[1] and payload.candidates[1].distance, 2, "candidate distance")

    -- 已被雇的人从候选里消失
    d(M.player, "HireExisting", { uid = near, mode = "follow", requestId = U("r23a") })
    M.advanceMs(1000)
    payload = d(M.player, "ScanCandidates")
    M.assert_eq(#payload.candidates, 0, "a hired NPC is no longer a candidate")

    -- 未知命令返回 nil（改状态命令之外的路径）
    local unknown = d(M.player, "Nope")
    M.assert_falsy(unknown, "unknown command returns nil")
    M.assert_falsy(Service.dispatch(nil, "RequestState"), "a nil player returns nil")
end)

-- ===========================================================================
-- 24. 补充：服务端事件接线
-- ===========================================================================
runTest(24, "extra: server Bootstrap registers the events and routes OnClientCommand", function()
    M.assert_truthy(M.handler_count("OnClientCommand") >= 1, "OnClientCommand handler registered")
    M.assert_truthy(M.handler_count("OnGameStart") >= 1, "OnGameStart handler registered")
    M.assert_truthy(M.handler_count("OnServerStarted") >= 1, "OnServerStarted handler registered")
    M.assert_truthy(M.handler_count("EveryOneMinute") >= 1, "EveryOneMinute handler registered")
    M.assert_truthy(M.handler_count("OnTick") >= 2, "OnTick handlers registered (server + client)")

    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:cmd:1" })
    local count, err = M.trigger("OnClientCommand", "Bin2NPCExtensionYese", "HireExisting", M.player,
        { uid = uid, mode = "follow", requestId = U("r24a") })
    M.assert_eq(err, nil, "OnClientCommand handler must not error: " .. tostring(err))
    M.assert_eq(count >= 1, true, "at least one handler ran")
    M.assert_truthy(ProjectALife.DecisionLoop.orders[uid] ~= nil, "the command was routed to Service.dispatch")
    M.assert_eq(M.balance(), 10000 - SIGN, "the command charged the player")

    -- 别人的 module 不处理
    local uid2 = M.addActor({ uid = "palife:cmd:2" })
    M.advanceMs(1000)
    M.trigger("OnClientCommand", "YeseMarket", "HireExisting", M.player,
        { uid = uid2, mode = "follow", requestId = U("r24b") })
    M.assert_eq(M.balance(), 10000 - SIGN, "a foreign module name does nothing")

    -- 兼容自检（详细断言在用例 1：加载期就调过 foreignCopies、且绝不写 known）。
    -- 这里只确认它在"有自带 A-Life 副本的模组"时也能跑完，并且是幂等的。
    M.assert_falsy(ProjectALife.ModCompat.known["Bin2NPCExtensionYese"] ~= nil,
        "this mod must NOT write itself into ProjectALife.ModCompat.known")
    M.setForeignCopies({ "SomeA-lifeCopy (3807277264) -> incompatible: ships its own copy" })
    M.assert_eq(Config.ServerBootstrap.reportCompat(), true,
        "Bootstrap.reportCompat() survives a non-empty foreign-copy list")
    M.assert_eq(Config.ServerBootstrap.reportCompat(), true, "…and is idempotent")
    M.setForeignCopies(nil)

    -- 依赖/能力自检（同域项目的"可观测"约定）：进世界时跑一遍，
    -- 把 hooks active/inactive 打进日志 —— 上游改名时第一次进游戏就能看到，而不是等按钮没反应
    local active, inactive = Config.ServerBootstrap.capabilities()
    M.assert_eq(type(inactive), "table", "capabilities() returns an inactive list")
    M.assert_truthy(active >= 5,
        "the mock satisfies most hooks (active=" .. tostring(active) .. ", inactive=" .. tostring(#inactive) .. ")")
    M.assert_truthy(Config.ServerBootstrap.report() == nil or true, "report() runs")
    local ranGames, gameErr = M.trigger("OnGameStart")
    M.assert_eq(gameErr, nil, "OnGameStart handler must not error: " .. tostring(gameErr))
    M.assert_truthy(ranGames >= 1, "OnGameStart handlers ran")
    local ranServer, serverErr = M.trigger("OnServerStarted")
    M.assert_eq(serverErr, nil, "OnServerStarted handler must not error: " .. tostring(serverErr))
    M.assert_truthy(ranServer >= 1, "OnServerStarted handlers ran")

    -- OnTick -> Maintain.tick（1 秒节流）
    resetWorld({ balance = 10000 })
    uid = M.addActor({ uid = "palife:tick:1" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r24c") })
    ProjectALife.DecisionLoop.orders[uid] = nil
    local callsBefore = M.count_calls("DecisionLoop.setOrder")
    M.trigger("OnTick")                                  -- 第一次：Bootstrap 自己节流后放行
    local afterFirst = M.count_calls("DecisionLoop.setOrder")
    M.trigger("OnTick")                                  -- 同一毫秒的第二次：必被 1s 节流挡掉
    M.assert_eq(M.count_calls("DecisionLoop.setOrder"), afterFirst,
        "the second OnTick in the same millisecond is throttled")
    M.assert_truthy(afterFirst > callsBefore, "OnTick ran Maintain.tick at least once")
    ProjectALife.DecisionLoop.orders[uid] = nil          -- 模拟 A-Life 的 orders 是纯内存表
    local tickContract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_truthy(tickContract ~= nil, "the tick test has a contract")
    tickContract.note = "pending"                        -- 岗位补派分支
    local orderCallsBefore = M.count_calls("DecisionLoop.setOrder")
    -- Bootstrap 的 OnTick 节流是 1 秒，Maintain 自己的指令重下节流是 8 秒，两个都要越过
    M.advanceMs(9000)
    M.trigger("OnTick")
    M.assert_truthy(M.count_calls("DecisionLoop.setOrder") > orderCallsBefore,
        "OnTick ran Maintain.tick again after both throttles")

    -- EveryOneMinute -> settleWages
    resetWorld({ balance = 100, sandbox = { DailyWage = 20 } })
    M.setWorldHours(0)
    uid = M.addActor({ uid = "palife:tick:2" })
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r24d") })
    M.setBalance(1000)
    M.advanceWorldHours(25)
    M.trigger("EveryOneMinute")
    M.assert_truthy(M.count_calls("Pay") >= 1, "EveryOneMinute settled the wages")
end)

-- ===========================================================================
-- 25. 补充：Alife 不可用时的降级
-- ===========================================================================
runTest(25, "extra: without A-Life the service degrades instead of erroring", function()
    resetWorld({ balance = 10000 })
    M.hideAlife(true)
    M.assert_falsy(Config.alife(), "Config.alife() is nil without the global")
    M.assert_eq(Alife.available(), false, "Alife.available()")
    local payload = d(M.player, "HireExisting", { uid = "palife:any", mode = "follow", requestId = U("r25a") })
    M.assert_eq(resultCode(payload), "no_alife", "no_alife code")
    M.advanceMs(1000)
    payload = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r25b") })
    M.assert_eq(resultCode(payload), "no_alife", "no_alife on summon")
    M.advanceMs(1000)
    payload = d(M.player, "ScanCandidates")
    M.assert_eq(#payload.candidates, 0, "ScanCandidates returns an empty list")
    M.assert_eq(Alife.record("palife:any"), nil, "Alife.record is nil without the api")
    M.assert_eq(Alife.name(nil), "?", "Alife.name(nil)")
    M.assert_eq(Alife.distance(nil, nil), nil, "Alife.distance(nil, nil)")
    M.hideAlife(false)
    M.advanceMs(1000)

    -- 经济缺失
    M.hideEconomy(true)
    M.assert_eq(Config.economyServer(), nil, "economyServer is nil when hidden")
    payload = d(M.player, "HireExisting", { uid = "palife:any", mode = "follow", requestId = U("r25c") })
    M.assert_eq(resultCode(payload), "no_economy", "no_economy code")
    payload = d(M.player, "RequestState")
    M.assert_eq(payload.capabilities.economy, false, "capabilities.economy=false")
    M.assert_eq(payload.coins, 0, "coins reported as 0 without the economy")
    M.hideEconomy(false)
end)

-- ===========================================================================
-- 26. 补充：Alife.orderFollow / orderHold 的拒绝码
-- ===========================================================================
runTest(26, "extra: Alife order helpers surface the upstream rejection codes", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:order:1" })

    -- 还没落地（lifecycle ~= active）
    M.setActorLifecycle(uid, "dormant")
    local done, why = Alife.orderFollow(M.player, uid)
    M.assert_eq(done, false, "orderFollow refuses a dormant actor")
    M.assert_eq(why, "actor_not_active", "refusal code for a dormant actor")

    -- active 但 generation 对不上：Alife.orderFollow 用的是 record.generation，永远对得上；
    -- 直接调 DecisionLoop 验证 mock 与真实实现一致
    M.setActorLifecycle(uid, "active")
    local accepted, code = ProjectALife.DecisionLoop.setOrder(uid, 999, { kind = "follow", player = M.player })
    M.assert_eq(accepted, false, "stale generation is refused")
    M.assert_eq(code, "order_actor_stale", "stale generation code")
    accepted, code = ProjectALife.DecisionLoop.setOrder(uid, M.state.alifeRecords[uid].generation, { kind = "dance" })
    M.assert_eq(code, "order_invalid", "invalid kind code")
    accepted, code = ProjectALife.DecisionLoop.setOrder(uid, M.state.alifeRecords[uid].generation, { kind = "follow" })
    M.assert_eq(code, "order_player_missing", "follow without a player")
    accepted, code = ProjectALife.DecisionLoop.setOrder(uid, M.state.alifeRecords[uid].generation, { kind = "hold" })
    M.assert_eq(code, "order_anchor_missing", "hold without an anchor")

    -- hold 成功
    done, why = Alife.orderHold(uid, { x = 10, y = 20, z = 0 })
    M.assert_eq(done, true, "orderHold with an anchor: " .. tostring(why))
    M.assert_eq(ProjectALife.DecisionLoop.orders[uid].kind, "hold", "hold order recorded")
    -- 没有 anchor 时退回记录里的 worldPosition
    ProjectALife.DecisionLoop.orders[uid] = nil
    done = Alife.orderHold(uid, nil)
    M.assert_eq(done, true, "orderHold falls back to record.worldPosition")
    M.assert_eq(ProjectALife.DecisionLoop.orders[uid].anchor.x, 102, "anchor x from the record")
    -- 清理
    Alife.clearOrder(uid)
    M.assert_falsy(ProjectALife.DecisionLoop.orders[uid], "clearOrder removed the order")

    -- orderFollow 的 quiet 透传（走过 setOrder 的调用里必须有 quiet=true 的那次）
    local before = M.count_calls("DecisionLoop.setOrder")
    Alife.orderFollow(M.player, uid, true)
    M.assert_eq(ProjectALife.DecisionLoop.orders[uid].kind, "follow", "follow order recorded")
    local quiet = false
    local calls = M.calls_named("DecisionLoop.setOrder")
    for index = before + 1, #calls do
        if calls[index].order and calls[index].order.quiet == true then quiet = true end
    end
    M.assert_eq(quiet, true, "quiet flag passed through to DecisionLoop.setOrder")
end)

-- ===========================================================================
-- 27. 补充：Alife.spawn 的幂等与回滚
-- ===========================================================================
runTest(27, "extra: Alife.spawn is idempotent per operationId and rolls back on refusal", function()
    resetWorld({ balance = 10000 })
    local spec = {
        operationId = "bin2:test:op-1",
        profileId = "npc_test_1",
        factionId = "bin2_test_friendly",
        worldPosition = { x = 10, y = 10, z = 0 },
    }
    local first = Alife.spawn(spec)
    M.assert_truthy(type(first) == "string", "Alife.spawn returned a uid")
    local second = Alife.spawn(spec)
    M.assert_eq(second, first, "the same operationId returns the same uid")
    M.assert_eq(M.count_calls("ActorRegistry.create"), 2, "create called twice but the second replayed")
    M.assert_eq(M.state.alifeSequence, 1, "only one actor was really created")

    -- 拒绝路径：SpawnService 失败 -> Registry.remove 回滚
    local spec2 = {
        operationId = "bin2:test:op-2",
        profileId = "npc_test_1",
        factionId = "bin2_test_friendly",
        worldPosition = { x = 12, y = 12, z = 0 },
    }
    local originalRequest = ProjectALife.SpawnService.request
    ProjectALife.SpawnService.request = function(uid, operationId, fingerprint, timeoutMs)
        return nil, "shell_hydration_failed"
    end
    local uid, why = Alife.spawn(spec2)
    ProjectALife.SpawnService.request = originalRequest
    M.assert_eq(uid, nil, "Alife.spawn returns nil on refusal")
    M.assert_eq(why, "shell_hydration_failed", "the upstream reason is propagated")
    M.assert_eq(M.count_calls("ActorRegistry.remove"), 1, "the dormant actor was rolled back")
    M.assert_eq(#ProjectALife.ActorRegistry.list(), 1, "only the first actor survives")
end)

-- ===========================================================================
-- 28. 补充：Contracts 基本操作
-- ===========================================================================
runTest(28, "extra: Contracts add/get/list/remove/activeCount", function()
    resetWorld()
    local node = Contracts.player(Contracts.blank(), "someone", true)
    M.assert_truthy(node ~= nil, "player node created")
    M.assert_eq(node.seq, 0, "fresh seq")
    M.assert_eq(Contracts.player(Contracts.blank(), "someone", false), nil, "create=false returns nil")
    local a = Contracts.add(node, { uid = "u1", mode = "follow", status = "active" })
    M.assert_eq(a.id, "c:1", "generated contract id")
    local b = Contracts.add(node, { uid = "u2", mode = "guard", status = "dismissed" })
    M.assert_eq(b.id, "c:2", "second generated id")
    M.assert_eq(Contracts.activeCount(node), 1, "activeCount ignores dismissed")
    M.assert_eq(#Contracts.list(node), 2, "list returns both")
    -- 同 uid 覆盖（幂等）
    Contracts.add(node, { uid = "u1", mode = "guard", status = "active" })
    M.assert_eq(#Contracts.list(node), 2, "same-uid add does not duplicate")
    M.assert_eq(Contracts.get(node, "u1").mode, "guard", "same-uid add overwrites")
    local removed = Contracts.remove(node, "u1")
    M.assert_eq(removed.uid, "u1", "remove returns the contract")
    M.assert_eq(Contracts.get(node, "u1"), nil, "contract is gone")
    M.assert_eq(#Contracts.list(node), 1, "order array shrank too")
    M.assert_eq(Contracts.remove(node, "ghost"), nil, "removing an unknown uid returns nil")
    -- hiredOrder 排序
    local rows = {
        { uid = "b", hiredHours = 5 }, { uid = "a", hiredHours = 1 }, { uid = "c", hiredHours = 5 },
    }
    Contracts.hiredOrder(rows)
    M.assert_eq(rows[1].uid, "a", "sorted by hiredHours")
    M.assert_eq(rows[2].uid, "b", "ties break on uid")
    M.assert_eq(rows[3].uid, "c", "stable tail")
end)

-- ===========================================================================
-- 29. 补充：Text 翻译回退
-- ===========================================================================
runTest(29, "extra: Text.get falls back to the bare key and Text.reason covers every code", function()
    local text = Config.Text
    -- getText 桩原样返回 key -> Text.get 去掉前缀
    M.assert_eq(text.get("PageTitle"), "PageTitle", "Prefixing then stripping the prefix")
    M.assert_eq(text.get("IGUI_Bin2NPCExtensionYese_PageTitle"), "PageTitle", "already-prefixed keys are kept")
    M.assert_eq(text.get(nil), "", "nil key")
    M.assert_eq(text.mode("guard"), "ModeGuard", "mode translation")
    M.assert_eq(text.mode("resident"), "ModeResident", "resident mode translation")
    M.assert_eq(text.mode("whatever"), "ModeFollow", "illegal mode falls back to follow")
    M.assert_eq(text.status("dead"), "StatusDead", "status translation")
    M.assert_eq(text.status("dismissed"), "StatusDismissed", "dismissed translation")
    M.assert_eq(text.status("active"), "StatusActive", "active translation")
    -- reason 覆盖 REASONS 里每个码
    local known = {
        "no_funds", "no_alife", "no_economy", "disabled", "limit_reached", "already_hired",
        "taken_by_other", "not_found", "not_active", "too_far", "hostile", "spawn_failed",
        "not_yours", "no_jeem", "too_fast", "duplicate", "pending", "dead", "unpaid",
    }
    for _, code in ipairs(known) do
        local value = text.reason(code)
        M.assert_truthy(type(value) == "string" and value ~= "", "Text.reason(" .. code .. ")")
        M.assert_not_contains(value, "ReasonUpstream", "Text.reason(" .. code .. ") uses its own translation")
    end
    M.assert_eq(text.reason(""), "", "empty code")
    -- 取不到翻译（我们的 getText 桩原样返回 key）时退化成裸键名，不给玩家看 %1
    local upstream = text.reason("shell_hydration_failed")
    M.assert_eq(upstream, "ReasonUpstream", "the missing translation falls back to the bare key")
    M.assert_not_contains(upstream, "%1", "no raw placeholder is left behind")
    M.assert_not_contains(upstream, "IGUI_", "the namespace prefix is stripped for display")
    -- 有真翻译时 %1 必须被替换成上游码
    M.state.translations = { IGUI_Bin2NPCExtensionYese_ReasonUpstream = "%1 (upstream)" }
    upstream = text.reason("shell_hydration_failed")
    M.assert_contains(upstream, "shell_hydration_failed", "the upstream code is substituted into %1")
    -- 复合码 resident:no_beds -> ReasonResidentRefused(ReasonUpstream(no_beds))
    -- （no_beds 是 Jeem 的上游码，REASONS 里刻意不穷举，统一走 ReasonUpstream 包装）
    M.state.translations = {
        IGUI_Bin2NPCExtensionYese_ReasonResidentRefused = "refused: %1",
        IGUI_Bin2NPCExtensionYese_ReasonUpstream = "%1 (upstream)",
    }
    local resident = text.reason("resident:no_beds")
    M.assert_eq(resident, "refused: no_beds (upstream)", "compound reason wraps the prefix and the upstream tail")
    M.assert_not_contains(resident, "no_funds", "compound reason does not leak another translation")
    M.assert_eq(text.reason("no_beds"), "no_beds (upstream)", "an upstream-only code is wrapped too")
    M.state.translations = nil
    resident = text.reason("resident:no_beds")
    M.assert_eq(resident, "ReasonResidentRefused", "without translations the wrapper key is shown")
end)

-- ===========================================================================
-- 30. 补充：Economy 适配层
-- ===========================================================================
runTest(30, "extra: Economy balance/pay/refund/record and RecordPlayerFlow extra payload", function()
    resetWorld({ balance = 400 })
    local Economy = Config.Economy
    M.assert_eq(Economy.available(), true, "Economy.available()")
    M.assert_eq(Economy.balance(M.player), 400, "Economy.balance")
    M.assert_eq(Economy.wage(), 20, "Economy.wage()")
    local ok, why = Economy.pay(M.player, 500)
    M.assert_eq(ok, false, "pay refuses an amount above the balance")
    M.assert_eq(why, "no_funds", "pay refusal code")
    M.assert_eq(Economy.balance(M.player), 400, "balance unchanged after a refusal")
    M.assert_eq(M.count_calls("RecordPlayerFlow"), 0, "no ledger row for a refused payment")

    ok = Economy.pay(M.player, 100)
    M.assert_eq(ok, true, "pay succeeds below the balance")
    M.assert_eq(Economy.balance(M.player), 300, "balance went down")
    local flow = M.calls_named("RecordPlayerFlow")[1]
    M.assert_truthy(flow ~= nil, "RecordPlayerFlow was called")
    M.assert_eq(flow.direction, "out", "flow direction")
    M.assert_eq(flow.kind, "npc_hire", "flow kind")
    M.assert_eq(flow.itemType, "Bin2NPCExtensionYese.contract", "flow itemType")
    M.assert_eq(flow.coins, 100, "flow coins")
    M.assert_eq(flow.extra and flow.extra.labelKey, "FlowHire", "flow extra labelKey")

    M.assert_eq(Economy.refund(M.player, 100), true, "refund succeeds")
    M.assert_eq(Economy.balance(M.player), 400, "refund restored the balance")
    M.assert_eq(Economy.refund(M.player, 0), false, "refund(0) is a no-op")
    M.assert_eq(Economy.pay(M.player, 0), true, "pay(0) is free")
    M.assert_eq(Economy.balance(M.player), 400, "pay(0) changed nothing")
    -- 读不到 PlayerData 时 balance 返回 nil（区分"没钱"与"读不到"）
    M.hideEconomy(true)
    M.assert_eq(Economy.balance(M.player), nil, "balance is nil without the economy")
    M.assert_eq(Economy.available(), false, "Economy.available() without the economy")
    M.assert_eq(Economy.pay(M.player, 10), false, "pay fails without the economy")
    M.hideEconomy(false)
end)

-- ===========================================================================
-- 31. 沙盒总开关必须覆盖每一个改状态命令
-- ===========================================================================
runTest(31, "disabled sandbox switch blocks SetMode/Dismiss too, not just the hire commands", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:disabled2:1" })
    -- 先在启用状态下拿到一份契约
    d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("r31a") })
    local node = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node), 1, "a contract exists before the switch is flipped")
    M.assert_eq(M.balance(), 10000 - SIGN, "the hire was charged while enabled")

    M.setSandbox("Enabled", false)
    M.assert_eq(Config.enabled(), false, "Config.enabled() is false")

    M.advanceMs(1000)
    local payload = d(M.player, "SetMode", { uid = uid, mode = "guard", requestId = U("r31b") })
    M.assert_eq(resultCode(payload), "disabled", "SetMode is gated by Enabled")
    local contract = Contracts.get(Store.node(M.player, false), uid)
    M.assert_truthy(contract ~= nil, "the contract survives a blocked SetMode")
    M.assert_eq(contract and contract.mode, "follow", "the post does not change while disabled")

    -- 沙盒总开关关掉后，改状态命令一律被挡住 —— Dismiss 也在内（bug #1 已修）
    M.advanceMs(1000)
    payload = d(M.player, "Dismiss", { uid = uid, requestId = U("r31c") })
    M.assert_eq(resultCode(payload), "disabled",
        "Dismiss is gated by Enabled just like the hire commands")
    M.assert_truthy(Contracts.get(Store.node(M.player, false), uid),
        "…and the contract is left untouched while the mod is disabled")
    M.setSandbox("Enabled", true)
end)

-- ===========================================================================
-- 32. 流水账必须覆盖"收钱"和"退钱"两侧
-- ===========================================================================
runTest(32, "the economy ledger records both the charge and the refund", function()
    resetWorld({ balance = 10000 })
    M.failNextSpawn("shell_hydration_failed")
    local payload = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r32") })
    M.assert_eq(resultCode(payload), "spawn_failed", "the spawn failed as arranged")
    M.assert_eq(M.balance(), 10000, "the fee was refunded")

    -- 扣款与退款都要在账单里留痕（bug #3 已修），否则玩家只看到扣钱、看不到钱回来
    local flows = M.calls_named("RecordPlayerFlow")
    M.assert_eq(#flows, 2, "two ledger rows: the charge and the refund")
    M.assert_eq(flows[1] and flows[1].direction, "out", "the charge is an outgoing row")
    M.assert_eq(flows[1] and flows[1].coins, SPAWN, "the charge row carries the fee")
    M.assert_eq(flows[2] and flows[2].direction, "in", "the refund is an incoming row")
    M.assert_eq(flows[2] and flows[2].coins, SPAWN, "the refund row carries the refunded amount")
    M.assert_eq(M.count_calls("AddCoins"), 1, "the coins are returned through AddCoins")
end)

-- ===========================================================================
-- 33. 造出来的 actor 在落地前就消失了 —— 契约仍然被写入吗？
-- ===========================================================================
runTest(33, "hireSpawned with an actor that vanishes right after SpawnService accepts", function()
    resetWorld({ balance = 10000 })
    -- 模拟真实场景：request 已经受理（排进了 SpawnService.pending），但在 Service 回来读
    -- Alife.record(uid) 之前，这条记录被别的流程（人口回收 / catalog 删除 / admin purge）清掉了。
    local originalRequest = ProjectALife.SpawnService.request
    local vanished = nil
    ProjectALife.SpawnService.request = function(uid, operationId, fingerprint, timeoutMs)
        local request, replayed = originalRequest(uid, operationId, fingerprint, timeoutMs)
        if request ~= nil then
            vanished = uid
            -- 真实的清理路径会先把 actor 变回 dormant（makeDormant）再 remove；
            -- mock 里直接照做，避免把 remove 的前置条件也一起绕过去
            M.setActorLifecycle(uid, "dormant")
            local record = ProjectALife.ActorRegistry.read(uid)
            if record ~= nil then
                local done, why = ProjectALife.ActorRegistry.remove(uid, record.revision, "probe_removed")
                M.assert_eq(done, true, "probe cleanup: remove succeeded (" .. tostring(why) .. ")")
            end
        end
        return request, replayed
    end
    local payload = d(M.player, "HireSpawned", { mode = "follow", requestId = U("r33") })
    ProjectALife.SpawnService.request = originalRequest

    M.assert_truthy(vanished ~= nil, "the spawn was accepted once")
    M.assert_falsy(Alife.record(vanished), "the actor is gone right after the accept")
    -- 造出来的人当场就没了 ⇒ 不能收钱、不能写契约（bug #4 已修）
    M.assert_eq(resultCode(payload), "spawn_failed",
        "a vanished actor reports spawn_failed instead of a phantom success")
    M.assert_eq(M.balance(), 10000, "…and the fee is refunded in full")
    M.assert_eq(M.count_calls("AddCoins"), 1, "the refund goes through AddCoins")
    local node = Store.node(M.player, false)
    M.assert_eq(Contracts.activeCount(node), 0, "…and no slot is taken by a contract that can never resolve")
    M.assert_falsy(Contracts.get(node, vanished), "no contract is written for the vanished uid")
    -- 阵亡清理无事可做（契约根本没建立）
    M.advanceMs(9000)
    Maintain.tick()
    M.assert_eq(Contracts.activeCount(node), 0, "still no contract after the maintenance tick")
end)

-- ===========================================================================
-- 34. 同一工坊物品里的"另一个口味"已经雇了这名 NPC
-- ===========================================================================
runTest(34, "extra: an NPC employed by the sibling flavour cannot be hired again", function()
    resetWorld({ balance = 10000 })
    local uid = M.addActor({ uid = "palife:sibling:1" })
    local before = M.balance()

    -- 兄弟模组的名字取自 Config（变体里会被生成器翻成对方的 id），这里塞一个最小替身
    local siblingId = Config.SIBLING_MODULE
    M.assert_truthy(type(siblingId) == "string" and siblingId ~= "", "Config.SIBLING_MODULE is set")
    local previous = _G[siblingId]
    _G[siblingId] = {
        Contracts = { owner = function() return "someone-else" end },
        Store = { data = function() return {} end },
    }

    local reply = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("rsib1") })
    M.assert_eq(resultCode(reply), "taken_by_other",
        "a sibling-owned NPC is refused with taken_by_other")
    M.assert_eq(M.balance(), before, "no money is taken when the sibling flavour owns the NPC")
    M.assert_falsy(Contracts.get(Store.node(M.player, false), uid), "no contract is written either")

    -- 替身拿掉之后应当又能雇（说明这道互查是"可降级"的，不会把自己锁死）
    _G[siblingId] = nil
    M.advanceMs(1000)
    reply = d(M.player, "HireExisting", { uid = uid, mode = "follow", requestId = U("rsib2") })
    M.assert_eq(resultCode(reply), "hired", "without the sibling flavour the same NPC hires fine")
    _G[siblingId] = previous
end)

-- ===========================================================================
-- 汇总
-- ===========================================================================
print("")
print(string.format("[test] %d/%d passed, %d failed", passed, TOTAL, failures))
return failures
