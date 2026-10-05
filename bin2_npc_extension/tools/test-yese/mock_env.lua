-- ===========================================================================
-- mock_env.lua —— Bin2NPCExtensionYese 离线测试环境
-- ===========================================================================
--
-- 三件事：
--   1. 引擎全局桩（SandboxVars / ModData / Events / getText / 时间 / ISPanel …），
--      全部是**可控的**：时间能推进、SandboxVars 能设能整个缺失、Events 能手动触发。
--   2. 三个依赖的 mock：Project A-Life、ProjectALifeJimmy（Jeem）、YeseMarket。
--      标注 [真实] 的部分照抄上游源码的校验顺序与返回值；标注 [简化] 的部分只保证
--      "形状与返回值契约"对，内部实现省略。真实路径见每个 mock 顶部的注释。
--   3. 断言框架（MOCK.expect / MOCK.assert_eq …）与调用记录。
--
-- 被 run.js dofile 一次，**在任何被测文件之前**。
--
-- 关键约定：
--   * MOCK.state 是唯一可变状态。所有 mock 函数在**调用时**读 MOCK.state 的字段，
--     所以 MOCK.reset() 换一张新 state 表之后，已经加载的模组代码依然指向新状态。
--   * 被测模组通过全局名（SandboxVars / Events / ProjectALife / …）取依赖，所以
--     测试开关也走全局名（MOCK.hideJeem() / MOCK.hideAlife()），不换表引用。
-- ===========================================================================

-- ---------------------------------------------------------------- 断言框架
MOCK = MOCK or {}
local M = MOCK

M.TOTAL_TESTS = 0
M.passed = 0
M.failures = 0

local currentTest = nil

local function render(value)
    if type(value) == "string" then return '"' .. value .. '"' end
    if type(value) == "table" then
        local parts = {}
        local n = 0
        for k, v in pairs(value) do
            n = n + 1
            if n > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    return tostring(value)
end

local function fail(message)
    currentTest.problems[#currentTest.problems + 1] = message
end

M.expect = function(condition, message)
    if condition ~= true then fail(tostring(message)) end
end

M.assert_eq = function(got, want, label)
    if got ~= want then
        fail(string.format("%s: got %s, want %s", tostring(label), render(got), render(want)))
    end
end

M.assert_near = function(got, want, label, epsilon)
    epsilon = epsilon or 1e-9
    if type(got) ~= "number" or math.abs(got - want) > epsilon then
        fail(string.format("%s: got %s, want %s (+-%s)", tostring(label), tostring(got), tostring(want),
            tostring(epsilon)))
    end
end

M.assert_truthy = function(value, label)
    if value == nil or value == false then
        fail(string.format("%s: expected a truthy value, got %s", tostring(label), render(value)))
    end
end

M.assert_falsy = function(value, label)
    if value ~= nil and value ~= false then
        fail(string.format("%s: expected nil/false, got %s", tostring(label), render(value)))
    end
end

-- 字符串包含（用于断言 note 里含 "resident:no_beds" 这类复合码）
M.assert_contains = function(haystack, needle, label)
    if type(haystack) ~= "string" or string.find(haystack, needle, 1, true) == nil then
        fail(string.format("%s: %s does not contain %s", tostring(label), render(haystack), render(needle)))
    end
end

M.assert_not_contains = function(haystack, needle, label)
    if type(haystack) == "string" and string.find(haystack, needle, 1, true) ~= nil then
        fail(string.format("%s: %s unexpectedly contains %s", tostring(label), render(haystack), render(needle)))
    end
end

M.next_test = function(total, name)
    M.TOTAL_TESTS = total
    currentTest = { name = name, problems = {}, logs = {} }
    -- 被测代码的 Config.always / warn / error 会 print，捕获下来在失败时一起打印
    M.currentLogs = currentTest.logs
    return currentTest
end

M.finish_test = function(index)
    local test = currentTest
    if #test.problems == 0 then
        M.passed = M.passed + 1
        print(string.format("[test] %d/%d %s ... OK", index, M.TOTAL_TESTS, test.name))
        return true
    end
    M.failures = M.failures + 1
    print(string.format("[test] %d/%d %s ... FAIL", index, M.TOTAL_TESTS, test.name))
    for _, problem in ipairs(test.problems) do
        print("       -> " .. problem)
    end
    for _, line in ipairs(test.logs) do
        print("       [mod] " .. line)
    end
    return false
end

-- ---------------------------------------------------------------- 调用记录
local function record(name, fields)
    local entry = fields or {}
    entry.name = name
    entry.atMs = MOCK and MOCK.state and MOCK.state.nowMs or 0
    local list = MOCK.state.calls
    list[#list + 1] = entry
    return entry
end

M.calls_named = function(name)
    local out = {}
    for _, entry in ipairs(M.state.calls) do
        if entry.name == name then out[#out + 1] = entry end
    end
    return out
end

M.count_calls = function(name)
    return #M.calls_named(name)
end

-- ---------------------------------------------------------------- 依赖探测开关
-- 被测代码用 rawget(_G, "ProjectALife") 之类做存在性探测，所以"缺失依赖"必须真的把全局去掉。
-- 这三个开关模拟"依赖不在"。恢复时一律指回 mock 的规范表，
-- 而不是"当初存下来的引用" —— 否则 reset() 换过全局之后会恢复成一张空表。
M.hideJeem = function(hidden)
    if hidden then
        ProjectALifeJimmy = nil
    else
        ProjectALifeJimmy = M.jeem
    end
end

M.hideAlife = function(hidden)
    if hidden then
        ProjectALife = nil
    else
        ProjectALife = M.alife
    end
end

M.hideEconomy = function(hidden)
    if hidden then
        YeseMarketServer = nil
    else
        YeseMarketServer = M.economyServer
    end
end

-- ===========================================================================
-- 1. 引擎全局桩
-- ===========================================================================

M.CONFIG_TABLE = "Bin2NPCExtensionYese"

--- 默认沙盒选项（与 media/sandbox-options.txt 一致）
local function defaultSandbox()
    return {
        Enabled = true,
        MaxContracts = 3,
        SignPrice = 500,
        SpawnPrice = 1500,
        RecruitRadius = 6,
        AllowHostile = false,
        MakeAllied = true,
        SpawnDistance = 2,
        WageEnabled = true,
        DailyWage = 20,
        UnpaidGraceDays = 1,
        DefaultMode = 1,
        CreateCamp = true,
        DebugLog = false,
    }
end

local function defaultState()
    return {
        nowMs = 1000000,
        worldHours = 0,
        balance = 10000,
        client = false,
        server = false,
        sandboxPresent = true,
        sandboxTablePresent = true,
        sandbox = defaultSandbox(),
        ---- A-Life 状态
        alifeRecords = {},
        alifeOrder = {},
        alifeOperations = {},
        alifeSequence = 0,
        alifeBindings = {},
        decideOrders = {},
        decideStates = {},
        foreignCopies = nil,
        spawnPending = {},
        spawnSettled = {},
        ---- Jeem 状态
        jeemEnabled = true,
        jeemFeatures = {},
        bases = {},
        baseSequence = 0,
        residentsByBase = {},
        pendingRecruitFailures = {},
        recruitCalls = {},
        standing = {},
        ---- 经济状态
        economy = {},
        ---- 记录
        players = nil,
        calls = {},
        events = {},
        modData = {},
        opened = {},
        radioNotices = {},
    }
end

M.state = defaultState()

--- 只重置指定字段（默认全量重置），换新表但保留 mock 函数引用（它们读 M.state）
M.reset = function(options)
    options = options or {}
    local previousNow = M.state.nowMs
    local fresh = defaultState()
    -- 时间永远单调前进：被测代码里 Bootstrap 的 OnTick 节流、Service 的防连点
    -- 都是模块级 local，时钟回退会让它们算出负数间隔（节流失效 / 永远 too_fast）
    fresh.nowMs = math.max(previousNow, fresh.nowMs)
    if options.keepEconomy == true then
        fresh.economy = M.state.economy
        fresh.balance = M.state.balance
    end
    if options.keepSandbox == true then
        fresh.sandbox = M.state.sandbox
        fresh.sandboxPresent = M.state.sandboxPresent
        fresh.sandboxTablePresent = M.state.sandboxTablePresent
    end
    fresh.players = M.state.players or { M.player }
    M.state = fresh
    M.currentLogs = nil
    ProjectALifeJimmy = M.jeem
    ProjectALife = M.alife
    YeseMarketServer = M.economyServer
    M.hideJeem(false)
    M.hideAlife(false)
    M.hideEconomy(false)
    return M.state
end

-- ---------------------------------------------------------------- 时间
getTimestampMs = function() return M.state.nowMs end
M.advanceMs = function(delta) M.state.nowMs = M.state.nowMs + (delta or 0) return M.state.nowMs end
M.setNowMs = function(value) M.state.nowMs = value return M.state.nowMs end

function getGameTime()
    return {
        getWorldAgeHours = function() return M.state.worldHours end,
        getMonth = function() return math.floor(M.state.worldHours / (24 * 30)) end,
    }
end
M.setWorldHours = function(value) M.state.worldHours = value return value end
M.advanceWorldHours = function(delta) M.state.worldHours = M.state.worldHours + delta return M.state.worldHours end

-- ---------------------------------------------------------------- 沙盒
--- 与 PZ 一致：SandboxVars.<Table>.<Option>；表或全局整体缺失时被测代码必须退默认值
SandboxVars = {}
M.setSandbox = function(key, value)
    M.state.sandbox[key] = value
    M.syncSandbox()
end
--- 整个 SandboxVars 全局消失（专用服/客户端早期）
M.setSandboxMissing = function(missing)
    M.state.sandboxPresent = not missing
    M.syncSandbox()
end
--- SandboxVars 在，但我们那张表不在
M.setSandboxTableMissing = function(missing)
    M.state.sandboxTablePresent = not missing
    M.syncSandbox()
end
function M.syncSandbox()
    if M.state.sandboxPresent then
        SandboxVars = {}
        if M.state.sandboxTablePresent then
            SandboxVars[M.CONFIG_TABLE] = M.state.sandbox
        end
    else
        SandboxVars = nil
    end
end

-- ---------------------------------------------------------------- ModData
ModData = {}
function ModData.getOrCreate(key)
    local data = M.state.modData[key]
    if type(data) ~= "table" then
        data = {}
        M.state.modData[key] = data
    end
    return data
end
function ModData.transmit(key)
    record("ModData.transmit", { key = key })
    return true
end
--- 清掉存档（让下一次 getOrCreate 建新的）
M.clearModData = function() M.state.modData = {} end
--- 直接读我们的存档表（等价于游戏里 ModData[Config.TAG]）
M.store = function() return M.state.modData[M.CONFIG_TABLE] end

-- ---------------------------------------------------------------- Events
local function newEvent()
    local event = { handlers = {} }
    function event.Add(handler)
        event.handlers[#event.handlers + 1] = handler
    end
    function event.Remove(handler)
        for index, existing in ipairs(event.handlers) do
            if existing == handler then table.remove(event.handlers, index) return end
        end
    end
    function event.RemoveAll()
        -- 游戏里的真实签名带参数；测试只用无参形式
        event.handlers = {}
    end
    return event
end

Events = {}
for _, name in ipairs({
    "OnTick", "EveryOneMinute", "EveryTenMinutes", "OnGameStart", "OnServerStarted",
    "OnClientCommand", "OnServerCommand", "OnKeyPressed", "OnKeyStartPressed",
    "OnPlayerDeath", "OnZombieDead", "OnLoad", "OnInitGlobalModData",
}) do
    Events[name] = newEvent()
end

--- 手动触发一次事件；返回 handler 数量与第一个错误
M.trigger = function(name, ...)
    local event = Events[name]
    if event == nil then return 0, "no such event: " .. tostring(name) end
    local errors = {}
    local count = 0
    for _, handler in ipairs(event.handlers) do
        count = count + 1
        local ok, err = pcall(handler, ...)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    return count, errors[1]
end

M.handler_count = function(name)
    return Events[name] ~= nil and #Events[name].handlers or 0
end

-- ---------------------------------------------------------------- 玩家
local function makePlayer(username, x, y)
    local player = {
        __username = username,
        __display = username,
        __x = x or 100,
        __y = y or 100,
        __z = 0,
    }
    function player:getUsername() return self.__username end
    function player:getDisplayName() return self.__display end
    function player:getX() return self.__x end
    function player:getY() return self.__y end
    function player:getZ() return self.__z end
    function player:setPosition(nx, ny, nz) self.__x, self.__y, self.__z = nx, ny, nz end
    function player:getPlayerNum() return 0 end
    function player:isDead() return false end
    function player:getModData() return {} end
    function player:setHaloNote(...) record("player.setHaloNote", { args = { ... } }) end
    return player
end

M.player = makePlayer("TestPlayer", 100, 100)
M.player2 = makePlayer("OtherPlayer", 300, 300)
M.state.players = { M.player }

function getSpecificPlayer(index)
    local list = M.state.players or {}
    return list[(tonumber(index) or 0) + 1]
end
function getNumActivePlayers()
    return #(M.state.players or {})
end
function getPlayer()
    return M.state.players[1]
end
function isClient() return M.state.client == true end
function isServer() return M.state.server == true end
M.setClient = function(value) M.state.client = value == true end
M.setServer = function(value) M.state.server = value == true end

M.rangeOf = function(player, x, y, z)
    player:setPosition(x, y, z or 0)
end

-- ---------------------------------------------------------------- 网络
function sendClientCommand(player, module, command, args)
    record("sendClientCommand", { player = player, module = module, command = command, args = args })
    return true
end
function sendServerCommand(player, module, command, args)
    record("sendServerCommand", { player = player, module = module, command = command, args = args })
    return true
end
--- 模拟服务端把状态推给客户端（客户端 Net 的 OnServerCommand 分支）
M.pushFromServer = function(payload)
    return M.trigger("OnServerCommand", "Bin2NPCExtensionYese", "State", payload)
end

-- ---------------------------------------------------------------- 杂项引擎桩
--[[
    翻译桩。

    真实引擎在**取不到翻译时原样返回 key**（这是我们测试里 Text.get 回退分支的关键），
    取到翻译时会把 %1/%2 换成参数。这里同时复刻这两点：先看 MOCK.state.translations
    （测试可以往里塞真翻译），没有就返回 key，并按参数替换占位符。
]]
function getText(key, ...)
    local name = tostring(key)
    -- 取不到翻译时，游戏会把 key 原样交给 UI（Text.get 再剥掉我们的前缀）。
    -- 这里也照着做：返回"去掉命名空间前缀的键名"，而不是把 IGUI_xxx 显示给玩家。
    local fallback = string.gsub(name, "^IGUI_Bin2NPCExtensionYese_", "")
    local template = M.state.translations and M.state.translations[name] or fallback
    if select("#", ...) > 0 then
        local args = { ... }
        for index, value in ipairs(args) do
            template = string.gsub(template, "%%" .. tostring(index), tostring(value))
        end
    end
    return template
end

function ZombRand(a, b)
    local state = M.state
    state.zombRandCounter = (state.zombRandCounter or 0) + 1
    local n = state.zombRandCounter
    if a == nil then return n % 1000 end
    if b == nil then return n % math.max(1, math.floor(a)) end
    local low, high = math.floor(a), math.floor(b)
    return low + (n % math.max(1, high - low + 1))
end

function getCell()
    return {
        getGridSquare = function(self, x, y, z) return { x = x, y = y, z = z } end,
    }
end

Keyboard = { KEY_N = 46, KEY_M = 47 }
UIFont = { Small = 0, Medium = 1, Large = 2, NewSmall = 3 }
getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
--[[
    测试开关：把 CN 的**真实**文案接到 getText 桩上。

    默认不接（键名回退是很多用例的断言基础）；需要断言"玩家在面板上看到的那句话"时打开，
    例如"拒绝原因必须是中文而不是上游码"。
]]
M.useCnTranslations = function()
    M.state.translations = Bin2NPCExtensionYese.__cnText or {}
    return M.state.translations
end

getTextManager = function()
    return {
        MeasureStringX = function(self, font, text) return #tostring(text) * 7 end,
        getFontHeight = function(self, font) return 16 end,
    }
end
isCtrlKeyDown = function() return true end
isAltKeyDown = function() return true end

-- ---------------------------------------------------------------- UI 桩
local function basePanel(x, y, width, height)
    local panel = {
        x = x or 0, y = y or 0, width = width or 1, height = height or 1,
        children = {}, visible = true, enabled = true,
    }
    function panel:initialise() return self end
    function panel:instantiate() return self end
    function panel:addChild(child) self.children[#self.children + 1] = child return child end
    function panel:removeChild(child)
        for index, existing in ipairs(self.children) do
            if existing == child then table.remove(self.children, index) break end
        end
    end
    function panel:getX() return self.x end
    function panel:getY() return self.y end
    function panel:getWidth() return self.width end
    function panel:getHeight() return self.height end
    function panel:setX(value) self.x = value return self end
    function panel:setY(value) self.y = value return self end
    function panel:setWidth(value) self.width = value return self end
    function panel:setHeight(value) self.height = value return self end
    function panel:setVisible(value) self.visible = value == true return self end
    function panel:isVisible() return self.visible end
    function panel:setEnable(value) self.enabled = value == true return self end
    function panel:isEnabled() return self.enabled end
    function panel:setTitle(value) self.title = value return self end
    function panel:getTitle() return self.title end
    function panel:drawText(...) return self end
    function panel:drawRect(...) return self end
    function panel:drawTexture(...) return self end
    function panel:bringToTop() return self end
    function panel:setPage(pageId) self.pageId = pageId return self end
    function panel:clampToScreen() return self end
    return panel
end

ISPanel = {}
function ISPanel:new(x, y, width, height)
    local panel = basePanel(x, y, width, height)
    panel.__index = ISPanel
    return setmetatable(panel, { __index = ISPanel })
end
function ISPanel:derive(name)
    -- 引擎里 ISPanel:derive 返回一个子类构造器；测试只需要"能调、返回表"
    local derived = setmetatable({}, { __index = self })
    derived.__index = derived
    derived.Type = name
    function derived:new(x, y, width, height)
        local instance = basePanel(x, y, width, height)
        return setmetatable(instance, { __index = derived })
    end
    return derived
end

ISUIElement = ISPanel
ISButton = ISPanel:derive("ISButton")
ISScrollingListBox = ISPanel:derive("ISScrollingListBox")

function instanceof(value, class)
    if type(value) ~= "table" then return false end
    local meta = getmetatable(value)
    local index = meta and meta.__index or nil
    while type(index) == "table" do
        if index == class then return true end
        local meta2 = getmetatable(index)
        index = meta2 and meta2.__index or nil
    end
    return false
end

-- ===========================================================================
-- 2. 依赖 mock
-- ===========================================================================

-- ---------------------------------------------------------------- Orange mod 页面注册表
-- [真实] 照抄 YeseMarket/42/media/lua/client/ui/page_registry.lua（工作坊 3735641567）。
-- Page.lua 里 require "ui/page_registry"，在游戏里就是加载这个文件；这里用同名的
-- package.preload 条目把它暴露给 require（见 run.js）。
local function installPageRegistry()
    YeseMarket = YeseMarket or {}
    local Registry = YeseMarket.UIPageRegistry or {}
    Registry.factories = Registry.factories or {}
    Registry.order = Registry.order or {}
    YeseMarket.UIPageRegistry = Registry
    YeseMarket.UIPageRegistryLoaded = true

    local function pageKey(value)
        if value == nil then return nil end
        local key = tostring(value)
        return key ~= "" and key or nil
    end

    local function registrationError(message, key)
        if key then error(message .. ": " .. key, 3) end
        error(message, 3)
    end

    function Registry.Register(pageId, factory)
        local key = pageKey(pageId)
        if not key then registrationError("Orange Trading page id is required") end
        if type(factory) ~= "function" then registrationError("Orange Trading page factory is invalid", key) end
        if Registry.factories[key] then registrationError("Orange Trading page is already registered", key) end
        Registry.factories[key] = factory
        Registry.order[#Registry.order + 1] = key
    end

    function Registry.Create(pageId, context)
        local key = pageKey(pageId)
        local build = key and Registry.factories[key]
        if not build then
            return nil, "Orange Trading page is unavailable: " .. tostring(key or pageId)
        end
        local page = build(context)
        if page == nil then
            return nil, "Orange Trading page could not be created: " .. tostring(key)
        end
        page.pageId = key
        return page
    end

    function Registry.Has(pageId)
        local key = pageKey(pageId)
        return key ~= nil and type(Registry.factories[key]) == "function"
    end

    function Registry.Ids()
        local snapshot = {}
        for index = 1, #Registry.order do snapshot[index] = Registry.order[index] end
        return snapshot
    end

    return Registry
end

-- ---------------------------------------------------------------- YeseMarket
--- [真实] 客户端：FormatCoins / IsSinglePlayer / ShowRadioNotice（形状）
--- [简化] ShowRadioNotice 只记录调用；真实实现还会写 HaloTextHelper
M.economyClient = {}
M.economyServer = {}
M.installEconomy = function()
    YeseMarket = YeseMarket or {}
    YeseMarketServer = YeseMarketServer or {}
    M.economyServer = YeseMarketServer      -- 规范表引用固定，reset 才能一致地恢复
    YeseMarket.UIPageRegistry = installPageRegistry()

    -- ---- 客户端侧
    -- [真实] client_api.lua:62 FormatCoins -> string.format("%.2f", NormalizeCoins(value))
    function YeseMarket.FormatCoins(value)
        local number = tonumber(value) or 0
        return string.format("%.2f", math.floor(number * 100 + 0.5) / 100)
    end
    -- [真实] single_player_bridge.lua:17 -> not (isClient and isClient() == true)
    function YeseMarket.IsSinglePlayer()
        return isClient() ~= true
    end
    -- [简化] 只记录
    function YeseMarket.ShowRadioNotice(player, message, color)
        M.state.radioNotices[#M.state.radioNotices + 1] = { player = player, message = message, color = color }
        record("ShowRadioNotice", { player = player, message = message, color = color })
        return true
    end
    -- [真实] event_handlers.lua:710 -> 打开/复用窗口，切到 targetPage
    function YeseMarket.Open(number, targetPage)
        M.state.opened[#M.state.opened + 1] = { number = number, pageId = targetPage }
        record("YeseMarket.Open", { number = number, pageId = targetPage })
        return nil
    end

    -- ---- 服务端侧
    -- [真实] runtime_core.lua:510 Pay：CeilCoins 之后真正扣钱，余额不足返回 false
    local function coins(value)
        local number = tonumber(value) or 0
        if number ~= number or number == math.huge or number == -math.huge then number = 0 end
        return math.floor(number * 100 + 0.5) / 100
    end
    function YeseMarketServer.PlayerData(player)
        local key = player == nil and "?" or tostring(player:getUsername())
        local data = M.state.economy[key]
        if type(data) ~= "table" then
            data = { coins = M.state.balance, flows = {} }
            M.state.economy[key] = data
        end
        return data
    end
    function YeseMarketServer.AddCoins(player, amount)
        local data = YeseMarketServer.PlayerData(player)
        data.coins = coins(data.coins + (tonumber(amount) or 0))
        record("AddCoins", { player = player, amount = tonumber(amount) or 0, after = data.coins })
        return data.coins
    end
    function YeseMarketServer.Pay(player, amount)
        local charge = math.ceil((tonumber(amount) or 0) * 100 - 0.0000001) / 100
        if type(player) ~= "table" or charge <= 0 then return false end
        local data = YeseMarketServer.PlayerData(player)
        if data.coins < charge then
            record("Pay", { player = player, amount = charge, ok = false, refused = true })
            return false
        end
        data.coins = coins(data.coins - charge)
        record("Pay", { player = player, amount = charge, ok = true, after = data.coins })
        return true
    end
    function YeseMarketServer.RecordPlayerFlow(player, direction, kind, itemType, amount, coinsPaid, extra)
        record("RecordPlayerFlow", {
            player = player, direction = direction, kind = kind, itemType = itemType,
            amount = amount, coins = coinsPaid, extra = extra,
        })
        return true
    end
    YeseMarketServer.EconomyLoaded = true

    -- ===== YeseMarket 版专有：Open(playerNum) + Window:setPage(id) + UIShell 导航钩子 =====
    -- 这三件事与橙子版的差异见 docs/research/yese-integration-hooks.md：
    --   * Open(playerNum) 只吃一个参数、不返回窗口（client/event_handlers.lua:299）
    --   * 切页要自己 YeseMarket.Window:setPage(id)（client/ui/shell.lua:726；未进 NAVIGATION 的 id 默认放行）
    --   * 导航由 shell.lua:32 的 local NAVIGATION 构建，第三方加不进去 ——
    --     但壳把按钮与度量放在实例字段上，所以我们包 buildNavigation / layoutNavigationItems 插一行
    YeseMarket.UIPrimitives = YeseMarket.UIPrimitives or {}
    if type(YeseMarket.UIPrimitives.CreateButton) ~= "function" then
        function YeseMarket.UIPrimitives.CreateButton(x, y, width, height, title, target, callback, variant)
            local button = ISButton:new(x, y, width, height)
            button.title, button.target = title, target
            button.callback, button.variant = callback, variant
            function button:click()
                if type(self.callback) == "function" then return self.callback(self.target, self) end
            end
            return button
        end
    end

    -- 重建一个干净的假壳（每个用例开头调一次，避免上一轮的包装残留）
    function M.resetShell()
        YeseMarket.Window = nil
        local Shell = {}
        function Shell:buildNavigation()
            local viewport = { width = 220, height = 400, children = {} }
            function viewport:addChild(child) self.children[#self.children + 1] = child end
            function viewport:setScrollHeight(value) self.scrollHeight = value end
            function viewport:setYScroll(value) self.yScroll = value end
            function viewport:getYScroll() return 0 end
            self.navigationViewport = viewport
            self.navButtons = {}
            self.navigationButtonHeight = 30
            self.navigationGap = 5
            self.navigationContentHeight = 0
            return true
        end
        function Shell:layoutNavigationItems() self.layoutCalls = (self.layoutCalls or 0) + 1 end
        function Shell:setPage(pageId)
            record("UIShell.setPage", { pageId = tostring(pageId or "") })
            self.activePageId = tostring(pageId or "")
            return true
        end
        YeseMarket.UIShell = Shell
        return Shell
    end
    M.resetShell()

    function YeseMarket.Open(playerNum)
        record("YeseMarket.Open", { number = tonumber(playerNum) or 0 })
        local window = {}
        function window:getIsVisible() return self.visible == true end
        function window:setPage(pageId)
            record("YeseMarket.Window.setPage", { pageId = tostring(pageId or "") })
            self.activePageId = tostring(pageId or "")
            M.state.opened[#M.state.opened + 1] = { number = tonumber(playerNum) or 0,
                pageId = tostring(pageId or "") }
            return true
        end
        function window:bringToTop() return self end
        function window:clampToScreen() return self end
        window.visible = true
        YeseMarket.Window = window
        return window
    end
end

M.setBalance = function(value)
    local data = YeseMarketServer.PlayerData(M.player)
    data.coins = value
    -- 其它玩家也一起设，方便 taken_by_other 场景
    M.state.balance = value
    for _, data2 in pairs(M.state.economy) do data2.coins = value end
    return value
end
M.balance = function(player)
    return YeseMarketServer.PlayerData(player or M.player).coins
end

-- ---------------------------------------------------------------- Project A-Life
--- 真实实现：workshop 3803984183
---   .../ProjectALifeNPCs/42.20/media/lua/server/ProjectALife/Core/ALifeActorRegistry.lua
---   .../Core/ALifeWatchdog.lua            （bindings 形状 / matches）
---   .../World/ALifeSpawnService.lua       （request / retire 的返回与校验）
---   .../Decisions/ALifeDecisionLoop.lua   （setOrder / forget / orders / states）
---   .../Shells/ALifeShellAdapter.lua      （shellPosition）
---   .../Decisions/ALifeRelations.lua      （baselineStance）
---   .../shared/ProjectALife/Records/ALifeCatalog.lua
M.installAlife = function()
    ProjectALife = ProjectALife or {}
    local A = ProjectALife

    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, entry in pairs(value) do result[copy(key)] = copy(entry) end
        return result
    end
    A.__copy = copy

    local function finite(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end
    local function validPosition(position)
        return type(position) == "table" and finite(position.x)
            and finite(position.y) and finite(position.z)
    end
    local LIFECYCLES = { dormant = true, spawning = true, active = true, dead = true }
    local function validRecord(record)
        return type(record) == "table" and type(record.uid) == "string"
            and #record.uid > 0 and #record.uid <= 64
            and type(record.revision) == "number" and record.revision >= 1
            and record.revision == math.floor(record.revision)
            and type(record.generation) == "number" and record.generation >= 0
            and record.generation == math.floor(record.generation)
            and LIFECYCLES[record.lifecycle] == true
            and type(record.profileId) == "string" and #record.profileId > 0
            and type(record.factionId) == "string" and #record.factionId > 0
            and validPosition(record.worldPosition)
    end

    -- ---- ActorRegistry -------------------------------------------------
    local registry = A.ActorRegistry or {}
    A.ActorRegistry = registry

    local function newUid()
        M.state.alifeSequence = M.state.alifeSequence + 1
        return "palife:" .. tostring(M.state.nowMs) .. ":" .. tostring(M.state.alifeSequence)
    end

    function registry.read(uid)
        local record = M.state.alifeRecords[uid]
        return record and copy(record) or nil
    end

    -- [真实] create：operationId+fingerprint 幂等；lifecycle 初始 dormant / generation 0 / revision 1
    function registry.create(specification)
        record("ActorRegistry.create", { spec = specification })
        if MOCK.__spawnFailure ~= nil then
            -- 测试开关：下一次造人直接失败（只消费一次）
            local pending = MOCK.__spawnFailure
            MOCK.__spawnFailure = nil
            return nil, pending.reason
        end
        if type(specification) ~= "table" or type(specification.operationId) ~= "string"
                or #specification.operationId < 1 or #specification.operationId > 128
                or type(specification.fingerprint) ~= "string" or #specification.fingerprint < 1
                or type(specification.profileId) ~= "string" or #specification.profileId < 1
                or type(specification.factionId) ~= "string" or #specification.factionId < 1
                or not validPosition(specification.worldPosition) then
            return nil, "actor_specification_invalid"
        end
        local prior = M.state.alifeOperations[specification.operationId]
        if prior then
            if prior.fingerprint ~= specification.fingerprint then
                return nil, "operation_conflict"
            end
            return copy(M.state.alifeRecords[prior.uid]), true
        end
        local uid = specification.uid or newUid()
        if type(uid) ~= "string" or #uid < 1 or #uid > 64 or M.state.alifeRecords[uid] then
            return nil, "uid_invalid"
        end
        local recordValue = {
            uid = uid,
            revision = 1,
            generation = 0,
            lifecycle = "dormant",
            profileId = specification.profileId,
            factionId = specification.factionId,
            worldPosition = copy(specification.worldPosition),
            activity = specification.activity or "idle",
            intent = specification.intent or "hold",
            memory = copy(specification.memory or {}),
        }
        if recordValue.memory.loadoutDay == nil then
            recordValue.memory.loadoutDay = math.max(0, math.floor(M.state.worldHours / 24))
        end
        if not validRecord(recordValue) then return nil, "actor_record_invalid" end
        M.state.alifeRecords[uid] = recordValue
        M.state.alifeOrder[#M.state.alifeOrder + 1] = uid
        M.state.alifeOperations[specification.operationId] = {
            fingerprint = specification.fingerprint, uid = uid,
        }
        return copy(recordValue), false
    end

    -- [真实] update：成功返回深拷贝表，失败返回 nil, why
    function registry.update(uid, expectedRevision, mutation)
        local current = M.state.alifeRecords[uid]
        if not current then return nil, "actor_not_found" end
        if current.revision ~= expectedRevision then return nil, "actor_revision_conflict" end
        if type(mutation) ~= "function" then return nil, "actor_mutation_invalid" end
        local candidate = copy(current)
        local ok, mutationError = pcall(mutation, candidate)
        if not ok then return nil, "actor_mutation_failed:" .. tostring(mutationError) end
        candidate.revision = current.revision + 1
        if not validRecord(candidate) then return nil, "actor_record_invalid" end
        M.state.alifeRecords[uid] = candidate
        record("ActorRegistry.update", { uid = uid, revision = candidate.revision, lifecycle = candidate.lifecycle })
        return copy(candidate)
    end

    -- [真实] remove：只有 dormant / dead 能被删
    function registry.remove(uid, expectedRevision, reason)
        local current = M.state.alifeRecords[uid]
        if current == nil then return false, "actor_not_found" end
        if current.revision ~= expectedRevision then return false, "actor_revision_conflict" end
        if current.lifecycle ~= "dormant" and current.lifecycle ~= "dead" then
            return false, "actor_remove_requires_inactive"
        end
        M.state.alifeRecords[uid] = nil
        for index, candidate in ipairs(M.state.alifeOrder) do
            if candidate == uid then table.remove(M.state.alifeOrder, index) break end
        end
        for operationId, operation in pairs(M.state.alifeOperations) do
            if operation.uid == uid then M.state.alifeOperations[operationId] = nil end
        end
        record("ActorRegistry.remove", { uid = uid, reason = reason })
        return true
    end

    function registry.list()
        local out = {}
        for _, uid in ipairs(M.state.alifeOrder) do
            if M.state.alifeRecords[uid] then out[#out + 1] = copy(M.state.alifeRecords[uid]) end
        end
        return out
    end

    function registry.each(callback)
        local visited = 0
        for _, uid in ipairs(M.state.alifeOrder) do
            local recordValue = M.state.alifeRecords[uid]
            if recordValue ~= nil then
                visited = visited + 1
                if callback(recordValue) == true then break end
            end
        end
        return visited
    end

    -- 游戏里由 SpawnService 调；测试用它把 actor 推到 active
    function registry.activate(uid, expectedRevision, generation, position)
        return registry.update(uid, expectedRevision, function(candidate)
            if candidate.lifecycle ~= "spawning" or candidate.generation ~= generation then
                error("spawn_generation_changed")
            end
            if position ~= nil then candidate.worldPosition = copy(position) end
            candidate.lifecycle = "active"
        end)
    end

    function registry.beginSpawn(uid, expectedRevision)
        return registry.update(uid, expectedRevision, function(candidate)
            if candidate.lifecycle ~= "dormant" then error("actor_not_dormant") end
            candidate.generation = candidate.generation + 1
            candidate.lifecycle = "spawning"
        end)
    end

    function registry.markDead(uid, expectedRevision, generation, position)
        return registry.update(uid, expectedRevision, function(candidate)
            if candidate.generation ~= generation then error("actor_generation_changed") end
            if position ~= nil then candidate.worldPosition = copy(position) end
            candidate.lifecycle = "dead"
            candidate.activity = "dead"
            candidate.intent = "none"
        end)
    end

    M.alifeRegistry = registry

    -- ---- Watchdog ------------------------------------------------------
    local watchdog = A.Watchdog or {}
    A.Watchdog = watchdog
    watchdog.bindings = watchdog.bindings or {}
    function watchdog.matches(binding)
        if type(binding) ~= "table" or type(binding.shell) ~= "table" then return false end
        local uid = binding.shell.__uid
        return uid ~= nil and binding.uid == uid
    end

    -- ---- SpawnService --------------------------------------------------
    local spawn = A.SpawnService or {}
    A.SpawnService = spawn

    -- [真实] request：已 pending/settled 的 operationId 幂等；lifecycle ~= dormant 时 actor_not_dormant
    function spawn.request(uid, operationId, fingerprint, timeoutMs)
        record("SpawnService.request", {
            uid = uid, operationId = operationId, fingerprint = fingerprint, timeoutMs = timeoutMs,
        })
        if type(operationId) ~= "string" or #operationId < 1
                or type(fingerprint) ~= "string" or #fingerprint < 1 then
            return nil, "spawn_request_invalid"
        end
        local existing = M.state.spawnPending[operationId] or M.state.spawnSettled[operationId]
        if existing then
            if existing.uid ~= uid or existing.fingerprint ~= fingerprint then
                return nil, "spawn_operation_conflict"
            end
            return existing, true
        end
        local actor = registry.read(uid)
        if not actor then return nil, "actor_not_found" end
        if actor.lifecycle ~= "dormant" then return nil, "actor_not_dormant" end
        local spawning, spawnError = registry.beginSpawn(actor.uid, actor.revision)
        if not spawning then return nil, spawnError end
        local shell = { __uid = uid, __generation = spawning.generation, x = actor.worldPosition.x, y = actor.worldPosition.y, z = actor.worldPosition.z }
        function shell:getX() return self.x end
        function shell:getY() return self.y end
        function shell:getZ() return self.z end
        function shell:getModData() return { ProjectALifeUID = self.__uid, ProjectALifeGeneration = self.__generation } end
        function shell:isDead() return false end
        local request = {
            uid = uid,
            generation = spawning.generation,
            operationId = operationId,
            fingerprint = fingerprint,
            shell = shell,
            status = "spawning",
        }
        M.state.spawnPending[operationId] = request
        watchdog.bindings[uid] = {
            uid = uid, generation = spawning.generation, shell = shell,
            boundAtMs = M.state.nowMs, lastSeenAtMs = M.state.nowMs, misses = 0,
        }
        return request, false
    end

    function spawn.retire(uid, reason)
        record("SpawnService.retire", { uid = uid, reason = reason })
        local actor = registry.read(uid)
        if actor == nil then return true end
        -- [简化] 真实实现会 detach shell / 清 pending / 必要时 makeDormant 再 remove
        local binding = watchdog.bindings[uid]
        if binding ~= nil then binding.shell = nil end
        watchdog.bindings[uid] = nil
        if actor.lifecycle ~= "dormant" and actor.lifecycle ~= "dead" then
            local dormant = registry.update(uid, actor.revision, function(candidate)
                candidate.lifecycle = "dormant"
                candidate.activity = "idle"
                candidate.intent = "hold"
            end)
            if dormant == nil then return false end
            actor = dormant
        end
        return registry.remove(uid, actor.revision, reason)
    end


    -- ---- DecisionLoop --------------------------------------------------
    local decisions = A.DecisionLoop or {}
    A.DecisionLoop = decisions
    decisions.orders = decisions.orders or {}
    decisions.states = decisions.states or {}

    -- [真实] setOrder：记录不存在 / lifecycle ~= active / generation 不等 -> order_actor_stale
    --        kind 非法 -> order_invalid；follow 缺 player -> order_player_missing；
    --        非 follow 缺 anchor -> order_anchor_missing；成功 true 并写 orders[uid]
    function decisions.setOrder(uid, generation, order)
        record("DecisionLoop.setOrder", { uid = uid, generation = generation, order = order })
        local actor = registry.read(uid)
        if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= generation then
            return false, "order_actor_stale"
        end
        if type(order) ~= "table"
                or not ({ follow = true, hold = true, patrol = true })[order.kind] then
            return false, "order_invalid"
        end
        if order.kind == "follow" and order.player == nil then return false, "order_player_missing" end
        if order.kind ~= "follow" and type(order.anchor) ~= "table" then
            return false, "order_anchor_missing"
        end
        decisions.states[uid] = { kind = "idle", intent = "order_changed", cooldownUntilMs = 0 }
        decisions.orders[uid] = {
            kind = order.kind,
            player = order.player,
            anchor = order.anchor,
            generation = generation,
            untilMs = tonumber(order.untilMs),
            source = order.source == "leader" and "leader" or "player",
        }
        return true
    end

    function decisions.forget(uid, generation, reason)
        record("DecisionLoop.forget", { uid = uid, generation = generation, reason = reason })
        decisions.orders[uid] = nil
        decisions.states[uid] = { kind = "idle", intent = "order_released", cooldownUntilMs = 0 }
        return true
    end

    -- ---- ShellAdapter --------------------------------------------------
    A.ShellAdapter = A.ShellAdapter or {}
    -- [真实] ShellAdapter.lua:306 -> { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
    function A.ShellAdapter.shellPosition(shell)
        if type(shell) ~= "table" or shell.getX == nil then return nil end
        return { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
    end
    function A.ShellAdapter.shellIdentity(shell)
        if type(shell) ~= "table" or shell.getModData == nil then return nil, nil end
        local data = shell:getModData()
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
    end

    -- ---- Catalog -------------------------------------------------------
    -- [真实] 形状照抄 ALifeCatalog.build()：{ factions = byId, factionOrder, npcs = byId, npcOrder }
    local function makeCatalog()
        local factions = {
            {
                id = "bin2_test_friendly",
                general = { name = "Friendly Testers" },
                relations = { player = "friendly", zombie = "hostile" },
            },
            {
                id = "bin2_test_hostile",
                general = { name = "Hostile Testers" },
                relations = { player = "hostile" },
            },
        }
        local npcs = {
            { id = "npc_test_1", general = { name = "Alex Mercer", faction = "bin2_test_friendly" } },
            { id = "npc_test_2", general = { name = "Dana Mercer", faction = "bin2_test_hostile" } },
        }
        return {
            factions = factions,
            factionOrder = factions,
            npcs = npcs,
            npcOrder = npcs,
        }
    end
    A.Catalog = A.Catalog or {}
    A.Catalog.current = makeCatalog()
    function A.Catalog.reset()
        A.Catalog.current = makeCatalog()
    end
    function A.Catalog.faction(id)
        for _, faction in ipairs(A.Catalog.current.factionOrder) do
            if faction.id == id then return faction end
        end
        return nil
    end
    function A.Catalog.npc(id)
        for _, npc in ipairs(A.Catalog.current.npcOrder) do
            if npc.id == id then return npc end
        end
        return nil
    end

    -- ---- Relations -----------------------------------------------------
    A.Relations = A.Relations or {}
    -- [真实] Relations.baselineStance 优先取 memory.spawnStance，否则看 faction.relations.player
    A.Relations.overrides = A.Relations.overrides or {}
    function A.Relations.baselineStance(actor, player)
        -- 测试开关优先：setStance() 用来模拟"记录里的 spawnStance 被改过 / 阵营敌对"
        local override = type(actor) == "table" and actor.uid and A.Relations.overrides[actor.uid] or nil
        if override ~= nil then return override end
        -- [真实] Relations.lua:31 -> memory.spawnStance 优先级最高
        local memory = type(actor) == "table" and actor.memory or nil
        if type(memory) == "table" and memory.spawnStance ~= nil then return memory.spawnStance end
        local faction = type(actor) == "table" and A.Catalog.faction(actor.factionId) or nil
        if faction == nil then return nil end
        local relations = faction.relations
        if type(relations) == "table" and type(relations.player) == "string" then
            return string.lower(relations.player)
        end
        return "neutral"
    end
    --- 测试开关：设置 Compat.foreignCopies 的返回值（nil = 没有不兼容模组）
M.setForeignCopies = function(list)
    M.state.foreignCopies = list
end

-- 测试开关：把某个 uid 的基线态度钉死
    function A.Relations.setStance(uid, word)
        A.Relations.overrides[uid] = word
    end

    -- ---- ModCompat：本模组**只读** foreignCopies，绝不写 known ----------------
    -- 真实契约：Compat.report()（ALifeModCompat.lua:314-330）会遍历 known，
    -- 把启用中的条目按 entry.verdict 打印成 "[A-Life] compat: ... -> <verdict>: <note>"。
    -- 所以第三方往里写 = 借 A-Life 的口替自己背书；测试 24 专门盯这一点。
    A.ModCompat = A.ModCompat or {}
    A.ModCompat.known = A.ModCompat.known or {}
    A.ModCompat.activeSet = function()
        return { ProjectALifeNPCs = true, ProjectALifeJimmy = true,
            YeseMarket = true, Bin2NPCExtensionYese = true }
    end
    A.ModCompat.foreignCopies = function(active)
        record("foreignCopies", { active = active })
        return M.state.foreignCopies or {}
    end

    M.alife = A
end

--- 造一个 active 的 actor；返回 uid
M.addActor = function(options)
    options = options or {}
    local uid = options.uid or ("palife:test:" .. tostring(#M.state.alifeOrder + 1))
    local recordValue = {
        uid = uid,
        revision = 1,
        generation = options.generation or 1,
        lifecycle = options.lifecycle or "active",
        profileId = options.profileId or "npc_test_1",
        factionId = options.factionId or "bin2_test_friendly",
        worldPosition = {
            x = options.x or 102, y = options.y or 100, z = options.z or 0,
        },
        activity = "idle",
        intent = "hold",
        memory = options.memory or {
            persistent = true, admin = { persistent = true, bin2npc = true },
            spawnStance = "friendly", groupId = options.groupId or ("grp:" .. uid),
        },
    }
    M.state.alifeRecords[uid] = recordValue
    M.state.alifeOrder[#M.state.alifeOrder + 1] = uid
    local shell = {
        __uid = uid, __generation = recordValue.generation,
        x = recordValue.worldPosition.x, y = recordValue.worldPosition.y, z = recordValue.worldPosition.z,
    }
    function shell:getX() return self.x end
    function shell:getY() return self.y end
    function shell:getZ() return self.z end
    function shell:getModData() return { ProjectALifeUID = self.__uid, ProjectALifeGeneration = self.__generation } end
    function shell:isDead() return false end
    ProjectALife.Watchdog.bindings[uid] = {
        uid = uid, generation = recordValue.generation, shell = shell,
        boundAtMs = M.state.nowMs, lastSeenAtMs = M.state.nowMs, misses = 0,
    }
    return uid, shell
end

--- 让 actor 变成 active（模拟 SpawnService 落地）
M.activateActor = function(uid)
    local recordValue = M.state.alifeRecords[uid]
    if recordValue == nil then return nil, "actor_not_found" end
    recordValue.lifecycle = "active"
    recordValue.revision = recordValue.revision + 1
    return recordValue
end

M.setActorLifecycle = function(uid, lifecycle)
    local recordValue = M.state.alifeRecords[uid]
    if recordValue == nil then return nil end
    recordValue.lifecycle = lifecycle
    return recordValue
end

M.killActor = function(uid)
    local recordValue = M.state.alifeRecords[uid]
    if recordValue == nil then return nil end
    recordValue.lifecycle = "dead"
    return recordValue
end

--- 让 ActorRegistry.read 对某个 uid 返回 nil（模拟记录被清掉）
M.forgetActor = function(uid)
    M.state.alifeRecords[uid] = nil
end

M.moveActor = function(uid, x, y, z)
    local recordValue = M.state.alifeRecords[uid]
    if recordValue == nil then return nil end
    recordValue.worldPosition = { x = x, y = y, z = z or 0 }
    local binding = ProjectALife.Watchdog.bindings[uid]
    if binding ~= nil and type(binding.shell) == "table" then
        binding.shell.x, binding.shell.y, binding.shell.z = x, y, z or 0
    end
    return recordValue
end

-- ---------------------------------------------------------------- ProjectALifeJimmy（Jeem）
--- 真实实现：workshop 3806944055
---   .../ProjectALifeJimmy/42/media/lua/shared/ProjectALifeJimmy/Core.lua        （enabled / nameOf / opt）
---   .../shared/.../Features/Residents/Residents.lua                             （residentOf）
---   .../shared/.../Features/BaseAreas/Store.lua                                 （who / basesFor / createBase / transmit）
---   .../server/.../Features/Residents/Server.lua:560-650                        （recruit 的校验顺序）
---   .../server/.../Features/Residents/Server.lua:395-407                        （residents(baseId)）
---   .../server/.../Features/Residents/Server.lua:722-733                        （leaveOne）
---   .../server/.../Services/Standing.lua:178                                    （addGroup）
M.installJeem = function()
    ProjectALifeJimmy = ProjectALifeJimmy or {}
    local J = ProjectALifeJimmy

    -- [真实] Core.lua:1094 -> features[id].upstreamActive / option / default
    function J.enabled(id)
        local def = J.features[id]
        if def == nil then return false end
        if def.upstreamActive then return false end
        if M.state.jeemEnabled ~= true then return false end
        return def.default ~= false
    end

    -- [真实] Core.lua:203 nameOf：memory.name -> Catalog.npc(profileId).general.name -> fallback
    function J.nameOf(record, fallback)
        local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or {}
        if memory.name or memory.displayName then
            return tostring(memory.name or memory.displayName)
        end
        local catalog = ProjectALife and ProjectALife.Catalog
        if type(record) == "table" and catalog and type(catalog.npc) == "function" then
            local ok, profile = pcall(catalog.npc, record.profileId)
            local name = ok and type(profile) == "table" and type(profile.general) == "table"
                and profile.general.name or nil
            if name and name ~= "" then return tostring(name) end
        end
        return fallback
    end

    function J.opt(name, default)
        if name == "Base_MaxResidents" then return M.state.jeemMaxResidents or 12 end
        return default
    end

    function J.worldHours() return M.state.worldHours end
    function J.nowMs() return M.state.nowMs end
    function J.log() return true end

    J.features = {
        residents = { option = "Residents_Enabled", default = true },
        traders = { option = "Traders_Enabled", default = true },
        outposts = { option = "Outposts_Enabled", default = true },
    }
    J.featureOrder = { "residents", "traders", "outposts" }

    -- ---- BaseAreas -----------------------------------------------------
    local baseAreas = J.BaseAreas or {}
    J.BaseAreas = baseAreas

    -- [真实] Store.lua:761 -> { key = playerKey, faction = factionName, admin = bool }
    function baseAreas.who(player)
        local key = player ~= nil and ("jimmy:" .. tostring(player:getUsername())) or "local"
        return { key = key, faction = nil, admin = player ~= nil and player.__admin == true }
    end

    function baseAreas.base(id)
        return M.state.bases[id]
    end

    function baseAreas.list()
        local out = {}
        for _, base in pairs(M.state.bases) do out[#out + 1] = base end
        return out
    end

    -- [真实] Store.lua:338 -> 按可管理性筛选，按 name 排序
    function baseAreas.basesFor(key, faction, admin)
        local out = {}
        for _, base in pairs(M.state.bases) do
            local mine = admin == true
                or (key ~= nil and (base.createdBy == key or (base.ownerKind == "player" and base.owner == key)))
                or (base.ownerKind == "faction" and faction ~= nil and base.owner == faction)
            if mine then out[#out + 1] = base end
        end
        table.sort(out, function(a, b)
            return a.name < b.name or (a.name == b.name and a.id < b.id)
        end)
        return out
    end

    -- [真实] Store.lua:389 -> 返回 base, area 或 nil, reason；[简化] 不做矩形重叠检查
    function baseAreas.createBase(args, who)
        record("BaseAreas.createBase", { args = args, who = who })
        who = type(who) == "table" and who or {}
        M.state.baseSequence = M.state.baseSequence + 1
        local base = {
            id = "base:" .. tostring(M.state.baseSequence),
            name = tostring(args and args.name or "Camp"),
            createdBy = who.key or "?",
            ownerKind = who.faction and "faction" or "player",
            owner = who.faction or who.key or "?",
            bedsOverride = tonumber(args and args.bedsOverride) or 0,
            posts = {},
        }
        M.state.bases[base.id] = base
        M.state.residentsByBase[base.id] = M.state.residentsByBase[base.id] or {}
        return base, { id = "area:1", baseId = base.id }
    end

    -- [真实] Store.lua:330 -> 管理员 / 非联机 / 创建者 / 阵营所有 都可以管理
    function baseAreas.canManage(base, key, factionName, admin)
        if type(base) ~= "table" then return false end
        if admin == true or M.state.isMultiplayer ~= true then return true end
        if key ~= nil and (base.createdBy == key or (base.ownerKind == "player" and base.owner == key)) then
            return true
        end
        return base.ownerKind == "faction" and factionName ~= nil and base.owner == factionName
    end

    function baseAreas.transmit()
        record("BaseAreas.transmit", {})
        return true
    end

    -- 测试开关：预先给玩家一个基地
    function J.giveBase(beds)
        local who = baseAreas.who(M.player)
        local base = {
            id = "base:given", name = "Player Base", createdBy = who.key,
            ownerKind = "player", owner = who.key,
            bedsOverride = tonumber(beds) or 4, posts = {},
        }
        M.state.bases[base.id] = base
        M.state.residentsByBase[base.id] = M.state.residentsByBase[base.id] or {}
        return base
    end

    -- ---- StandingService -----------------------------------------------
    --[[
        [真实] 逐条对齐 ProjectALifeJimmy/Services/Standing.lua：
          ladder / thresholds / clamp / data().players[key]
          steps(points)  -> 过了几个阈值（正负对称）
          points / groupPoints / defaultLabel / labelFor / toNext
          add(key, factionId, delta, info)  -> 阵营点数（带 clamp），并按 info.groupId 顺带顶小队点数
          addGroup(key, groupId, factionId, delta) -> 只顶小队点数

        这里必须**忠实**，否则"垫声望"这类改动在离线测试里永远看不见（真实案例：mock 原来把
        同盟判定写成 points >= 0，且漏了 labelFor 那条路，于是"雇了人却当不了队友"的 bug 测试全绿）。
    ]]
    local LADDER = { "hostile", "careful", "neutral", "friendly", "allied" }
    local THRESHOLDS = { 25, 75, 150, 250 }
    local clamp = 400
    J.StandingService = J.StandingService or {}
    local S = J.StandingService
    S.clamp = clamp
    S.ladder = S.ladder or LADDER
    S.thresholds = S.thresholds or THRESHOLDS
    S.baseline = S.baseline or {}     -- 测试可改：factionId -> 该阵营对你的默认标签

    local function ladderIndex(name)
        for i, value in ipairs(LADDER) do if value == name then return i end end
        return 1
    end

    function S.defaultLabel(factionId)
        return S.baseline[factionId] or "hostile"      -- A-Life 默认多为敌对
    end

    function S.steps(points)
        points = tonumber(points) or 0
        local n = 0
        for _, threshold in ipairs(THRESHOLDS) do
            if math.abs(points) >= threshold then n = n + 1 end
        end
        return points < 0 and -n or n
    end

    function S.playerState(key)
        local state = M.state.standing[key]
        if type(state) ~= "table" then
            state = { factions = {}, groups = {} }
            M.state.standing[key] = state
        end
        state.factions = type(state.factions) == "table" and state.factions or {}
        state.groups = type(state.groups) == "table" and state.groups or {}
        return state
    end

    function S.points(key, factionId)
        return tonumber(S.playerState(key).factions[factionId]) or nil
    end

    function S.poolBonus() return 0 end          -- 单人测试里没有同阵营队友

    function S.labelFor(key, factionId, extraPoints)
        local base = ladderIndex(S.defaultLabel(factionId))
        local steps = S.steps((S.points(key, factionId) or 0) + (tonumber(extraPoints) or 0))
        return LADDER[math.max(1, math.min(#LADDER, base + steps))]
    end

    function S.groupPoints(key, groupId)
        local state = M.state.standing[key]
        local group = type(state) == "table" and type(state.groups) == "table" and state.groups[groupId] or nil
        return type(group) == "table" and (tonumber(group.points) or 0) or 0
    end

    -- [真实] Standing.lua:151 -> add(key, factionId, delta, info)，返回 before/after 标签
    function S.add(key, factionId, delta, info)
        record("StandingService.add", {
            key = key, factionId = factionId, delta = delta,
            groupId = type(info) == "table" and info.groupId or nil,
            kind = type(info) == "table" and info.kind or nil,
        })
        if key == nil or factionId == nil or tonumber(delta) == nil then return nil end
        info = type(info) == "table" and info or {}
        local state = S.playerState(key)
        local before = S.labelFor(key, factionId)
        local points = (tonumber(state.factions[factionId]) or 0) + delta
        state.factions[factionId] = math.max(-clamp, math.min(clamp, points))
        if info.groupId ~= nil then
            local group = type(state.groups[info.groupId]) == "table" and state.groups[info.groupId]
                or { factionId = factionId, points = 0 }
            group.points = math.max(-clamp, math.min(clamp,
                (tonumber(group.points) or 0) + (tonumber(info.groupPoints) or delta)))
            group.factionId = factionId
            state.groups[info.groupId] = group
        end
        return before, S.labelFor(key, factionId)
    end

    -- [真实] Standing.lua:178 -> addGroup(key, groupId, factionId, delta)
    function S.addGroup(key, groupId, factionId, delta)
        record("StandingService.addGroup", {
            key = key, groupId = groupId, factionId = factionId, delta = delta,
        })
        if key == nil or groupId == nil or tonumber(delta) == nil then return end
        local state = S.playerState(key)
        local group = type(state.groups[groupId]) == "table" and state.groups[groupId]
            or { factionId = factionId, points = 0 }
        group.points = math.max(-clamp, math.min(clamp, (tonumber(group.points) or 0) + delta))
        group.factionId = factionId
        state.groups[groupId] = group
    end

    -- [真实] Features/Residents/Server.lua:490 -> R.isAlly（两条路：阵营标签 或 小队点数）
    S.isAlly = function(key, record)
        if key == nil or type(record) ~= "table" then return false end
        if record.factionId ~= nil and S.labelFor(key, record.factionId) == "allied" then return true end
        local groupId = type(record.memory) == "table" and record.memory.groupId or nil
        local R = J.Residents
        local threshold = R ~= nil and tonumber(R.allyGroupPoints) or 50
        return groupId ~= nil and S.groupPoints(key, groupId) >= threshold
    end

    -- ---- Residents -----------------------------------------------------
    local residents = J.Residents or {}
    J.Residents = residents
    residents.pending = {}
    residents.refusals = {
        off = "IGUI_ALJ_Residents_Off",
        no_base = "IGUI_ALJ_Residents_NoBase",
        not_yours = "IGUI_ALJ_Residents_NotYours",
        unavailable = "IGUI_ALJ_Residents_Unavailable",
        busy = "IGUI_ALJ_Residents_Busy",
        resident = "IGUI_ALJ_Residents_Resident",
        garrison = "IGUI_ALJ_Residents_Garrison",
        trader = "IGUI_ALJ_Residents_Trader",
        not_allied = "IGUI_ALJ_Residents_NotAllied",
        beds_unknown = "IGUI_ALJ_Residents_BedsUnknown",
        no_beds = "IGUI_ALJ_Residents_NoBeds",
        full_cap = "IGUI_ALJ_Residents_FullCap",
        full = "IGUI_ALJ_Residents_Full",
        moving = "IGUI_ALJ_Residents_Moving",
        not_resident = "IGUI_ALJ_Residents_NotResident",
    }

    -- [真实] Features/Residents/Server.lua:22 -> R.allyGroupPoints（挂在 Residents 上，不是 StandingService）
    residents.allyGroupPoints = 50

    -- [真实] Residents.lua:120 -> memory.jimmyResident（必须同时带 baseId）
    function residents.residentOf(record)
        local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
        if memory == nil then return nil end
        local resident = memory.jimmyResident
        if type(resident) ~= "table" then return nil end
        if type(resident.baseId) ~= "string" then return nil end
        return resident
    end

    -- [真实] Server.lua:395 -> 该基地的居民记录数组，按 index 排序
    function residents.residents(baseId)
        local out = {}
        local registry = ProjectALife and ProjectALife.ActorRegistry
        if registry == nil then return out end
        for _, record in ipairs(registry.list()) do
            local resident = residents.residentOf(record)
            if resident and resident.baseId == baseId and record.lifecycle ~= "dead" then
                out[#out + 1] = record
            end
        end
        table.sort(out, function(a, b)
            return (tonumber(residents.residentOf(a).index) or 0)
                < (tonumber(residents.residentOf(b).index) or 0)
        end)
        return out
    end

    -- [真实] R.isAlly：阵营标签 allied 或 小队点数 >= 50（原来这里写成 points >= 0，几乎永远为真）
    local function isAllied(key, record)
        return J.StandingService.isAlly(key, record) == true
    end

    local function crewOf(record)
        local registry = ProjectALife and ProjectALife.ActorRegistry
        local memory = type(record.memory) == "table" and record.memory or {}
        local crew = { record }
        if memory.groupId == nil or registry == nil then return crew end
        local rest = {}
        for _, other in ipairs(registry.list()) do
            local otherMemory = type(other.memory) == "table" and other.memory or {}
            if other.uid ~= record.uid and other.lifecycle ~= "dead"
                    and otherMemory.groupId == memory.groupId then
                rest[#rest + 1] = other
            end
        end
        table.sort(rest, function(a, b) return tostring(a.uid) < tostring(b.uid) end)
        for _, other in ipairs(rest) do crew[#crew + 1] = other end
        return crew
    end

    -- [真实] Server.lua:560-650 的校验顺序与拒绝码
    --    off -> no_base -> not_yours -> unavailable -> busy(记录缺失或已死) -> resident
    --    -> garrison -> trader -> not_allied -> busy(交战中) -> beds_unknown
    --    -> no_beds / full_cap / full -> moving
    --   force 只在 who.admin == true 时生效（skip allied + combat）
    function residents.recruit(player, uid, baseId, force)
        M.state.recruitCalls[#M.state.recruitCalls + 1] = {
            player = player, uid = uid, baseId = baseId, force = force,
        }
        record("Residents.recruit", { player = player, uid = uid, baseId = baseId, force = force })

        if not J.enabled("residents") then return nil, "off" end
        local who = baseAreas.who(player)
        local base = baseAreas.base(baseId)
        if base == nil then return nil, "no_base" end
        local registry = ProjectALife and ProjectALife.ActorRegistry
        if registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then
            return nil, "unavailable"
        end
        local record = registry.read(uid)
        if record == nil or record.lifecycle == "dead" then return nil, "busy" end
        local memory = type(record.memory) == "table" and record.memory or {}
        if residents.residentOf(record) then return nil, "resident" end
        if memory.outpostId ~= nil then return nil, "garrison" end
        if memory.jimmyTrader ~= nil then return nil, "trader" end
        force = force == true and who.admin == true
        if not force and not isAllied(who.key, record) then return nil, "not_allied" end
        local talk = ProjectALife and ProjectALife.Talk
        if not force and talk and type(talk.inCombat) == "function" and talk.inCombat(record) then
            return nil, "busy"
        end

        -- 测试注入的拒绝（放在真实校验之后、落地之前，等价于床位/上限检查失败）
        local injected = M.state.pendingRecruitFailures[uid]
        if injected ~= nil then
            -- 故意**不消费**：Jimmy.recruit 内部会先来一次、失败后再来一次 force=true，
            -- 要让两次都被拒就得让注入持续到测试显式复位
            return nil, injected
        end

        local crew = crewOf(record)
        local list = M.state.residentsByBase[base.id]
        if type(list) ~= "table" then list = {} M.state.residentsByBase[base.id] = list end
        local have = #list
        local capacity = tonumber(base.bedsOverride) or 0
        if #crew > capacity - have then
            local cap = tonumber(J.opt("Base_MaxResidents", 12)) or 12
            if have == 0 and capacity == 0 and cap > 0 then return nil, "no_beds" end
            return nil, (#crew > cap - have) and "full_cap" or "full"
        end
        if base.moving == true then return nil, "moving" end

        for index, member in ipairs(crew) do
            local target = M.state.alifeRecords[member.uid]
            if target ~= nil then
                target.memory = type(target.memory) == "table" and target.memory or {}
                local resident = type(target.memory.jimmyResident) == "table" and target.memory.jimmyResident or {}
                resident.baseId = base.id
                resident.index = have + index
                resident.since = M.state.worldHours
                resident.recruitedBy = who.key
                resident.fromFaction = member.factionId
                target.memory.jimmyResident = resident
                target.revision = target.revision + 1
                list[#list + 1] = member.uid
            end
        end
        base.garrisonCount = #list
        return #crew
    end

    -- [真实] Server.lua:722 -> 成功返回 true；不是居民 -> nil, "not_resident"
    function residents.leaveOne(player, uid)
        record("Residents.leaveOne", { player = player, uid = uid })
        local registry = ProjectALife and ProjectALife.ActorRegistry
        local record = registry and registry.read(uid)
        local resident = residents.residentOf(record)
        if resident == nil then return nil, "not_resident" end
        local base = M.state.bases[resident.baseId]
        if base == nil then return nil, "not_resident" end
        local who = baseAreas.who(player)
        local mine = who.admin == true or base.createdBy == who.key
            or (base.ownerKind == "player" and base.owner == who.key)
        if not mine then return nil, "not_yours" end
        local target = M.state.alifeRecords[uid]
        if target ~= nil then
            target.memory = type(target.memory) == "table" and target.memory or {}
            target.memory.jimmyResident = nil
            target.memory.groupId = "solo:jimmy:" .. tostring(uid)
            target.revision = target.revision + 1
        end
        local list = M.state.residentsByBase[base.id] or {}
        for index, value in ipairs(list) do
            if value == uid then table.remove(list, index) break end
        end
        return true
    end

    -- [真实] Server.lua:527 -> 拒绝码翻成人话；未知码原样返回
    function residents.explain(why)
        local key = residents.refusals[why]
        return key and ("[jeem]" .. key) or tostring(why)
    end

    -- 测试开关：下一次对 uid 的 recruit 直接返回该拒绝码
    function J.refuseNextRecruit(uid, code)
        M.state.pendingRecruitFailures[uid] = code
    end

    M.jeem = J
end

--- 直接把某个 base 的床位改掉（模拟"床位被占"）
M.setBaseBeds = function(baseId, beds)
    local base = M.state.bases[baseId]
    if base == nil then return nil end
    base.bedsOverride = beds
    return base
end

-- ===========================================================================
-- 3. 初始化
-- ===========================================================================

M.installEconomy()
M.installAlife()
M.installJeem()
M.syncSandbox()

-- 加载被测文件之前的全局快照；「只多出预期全局」这条断言用它做差集
M.captureGlobals = function()
    local snapshot = {}
    for key in pairs(_G) do snapshot[key] = true end
    M.globalsBefore = snapshot
    return snapshot
end

M.newGlobals = function()
    local out = {}
    for key in pairs(_G) do
        if M.globalsBefore[key] ~= true then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

--[[
    以下 helper 刻意挂在 MOCK 上而不是三个依赖的表上：
    M.reset() 会重建依赖表，挂在依赖表上的 helper 会变成"上一代对象上的函数"，
    测试再去 index 就会踩到 nil。
]]

--- 让下一次 ActorRegistry.create 直接失败（模拟 A-Life 造人失败）
M.failNextSpawn = function(reason)
    M.__spawnFailure = { reason = reason or "shell_hydration_failed" }
end

--- 给玩家预置一个可管理的基地（Jeem 居民化的前置条件）
M.giveBase = function(beds)
    local who = YeseMarket ~= nil and nil or nil
    who = { key = "jimmy:" .. tostring(M.player:getUsername()), faction = nil, admin = M.player.__admin == true }
    local base = {
        id = "base:given", name = "Player Base", createdBy = who.key,
        ownerKind = "player", owner = who.key,
        bedsOverride = tonumber(beds) or 4, posts = {},
    }
    M.state.bases[base.id] = base
    M.state.residentsByBase[base.id] = M.state.residentsByBase[base.id] or {}
    return base
end

--- 让下一次对 uid 的 Residents.recruit 直接返回该拒绝码
M.refuseNextRecruit = function(uid, code)
    M.state.pendingRecruitFailures[uid] = code
end

-- require 计数器（run.js 的自定义 searcher 会写这里）
M.requireCounts = {}

return M
