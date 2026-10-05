--[[
    Bin2NPCExtension :: Net（client）

    我们自己的网络层，与橙子经济的 module 完全分离：
        * 联机客户端：sendClientCommand(player, "Bin2NPCExtension", cmd, args)
        * 单机 / 主机：直接调服务端 Service.dispatch（同一进程，server 文件在单机也会加载）
        * 回包：服务端 sendServerCommand(player, "Bin2NPCExtension", "State", payload)
          单机没有回包，直接吃 dispatch 的返回值。

    这也是 Jeem 的 Menu.send 用的同一套分发（见 docs/research/jeem-recruit-api.md §7）。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Text"

local Config = Bin2NPCExtension

--[[
    幂等 + 防"Reset Lua"重入。

    本文件可能在两条路径上各跑一次（引擎 LoadDirBase 自动加载 / 被其它文件 require），
    而它在文件体里注册了 Events.OnServerCommand —— 重复注册会让每条回包被处理两次。

    判据用 **Events 表的身份**而不是一个布尔量：同一张 Events 表 = 同一次 Lua 会话（跳过）；
    换了一张 Events 表 = 引擎重置过 Lua（必须重新注册，否则功能会静默失效）。
    这是本项目"通用工程约定 §4 防 Reset Lua 重入"的落地方式（见
    bin2_ProjectALifeNPCs_extensions/docs/roadmap.md 阶段 4）。
]]
if Config.NetEvents == Events and Config.Net ~= nil then return Config.Net end
Config.NetEvents = Events

local Net = {}
Config.Net = Net

-- 客户端缓存：服务端推来的最后一份状态（UI 每帧读它）
Net.cache = Net.cache or {
    contracts = {},
    result = nil,
    capabilities = {},
    limits = { max = 0, used = 0 },
    prices = { sign = 0, spawn = 0, wage = 0 },
    coins = 0,
    candidates = nil,
}

-- 自增序号：给改状态命令做幂等键（服务端用它去重，防连点/重放）
local sequence = 0

local function localPlayer()
    local ok, player = pcall(function()
        if type(getPlayer) == "function" then return getPlayer() end
        return nil
    end)
    if ok and player ~= nil then return player end
    local okSpecific, specific = pcall(getSpecificPlayer, 0)
    if okSpecific then return specific end
    return nil
end

Config.localPlayer = localPlayer

function Net.isMultiplayerClient()
    local ok, value = pcall(function() return isClient() end)
    return ok and value == true
end

--[[
    收下服务端/直连返回的状态。候选名单是"一次性"的：只有带 candidates 字段的 payload 才覆盖它，
    普通状态推送不会把玩家正在看的候选列表清空。
]]
function Net.apply(payload)
    if type(payload) ~= "table" then return Net.cache end
    local cache = Net.cache
    -- 版本号：UI 每帧比对它，变了才重建列表。
    -- 联机下状态是异步推来的，没有这个号就只能等玩家手动点刷新。
    cache.revision = (tonumber(cache.revision) or 0) + 1
    for _, key in ipairs({ "contracts", "capabilities", "limits", "prices" }) do
        if type(payload[key]) == "table" then cache[key] = payload[key] end
    end
    if tonumber(payload.coins) ~= nil then cache.coins = tonumber(payload.coins) end
    if payload.candidates ~= nil then cache.candidates = payload.candidates end
    if tonumber(payload.candidateRadius) ~= nil then cache.candidateRadius = tonumber(payload.candidateRadius) end
    if type(payload.result) == "table" then
        cache.result = payload.result
        Net.notify(payload.result)
    end
    return cache
end

-- 操作结果反馈：优先借用橙子经济的电台提示，退到 HaloNote
function Net.notify(result)
    local code = tostring(result.code or "")
    local ok = result.ok == true
    local message
    if ok then
        message = Config.Text.get("NoticeDone")
    else
        message = Config.Text.get("NoticeFailed", Config.Text.reason(code))
    end
    local player = localPlayer()
    if player == nil then return end
    local ui = Config.economy()
    if ui ~= nil and type(ui.ShowRadioNotice) == "function" then
        local okCall = pcall(ui.ShowRadioNotice, player, message, ok and "green" or "red")
        if okCall then return end
    end
    local okHalo = pcall(function()
        local r, g, b = 1, 0.4, 0.4
        if ok then r, g, b = 0.5, 1, 0.5 end
        player:setHaloNote(message, r * 255, g * 255, b * 255, 3000)
    end)
    if not okHalo then Config.log(message) end
end

--[[
    发一条命令。

    mutating=true 时会带 requestId（服务端去重）。
    返回 true 表示"已经发出/已处理"，不代表业务成功 —— 业务结果走 payload.result。
]]
function Net.send(command, args, mutating)
    local player = localPlayer()
    if player == nil then return false end
    local payloadArgs = type(args) == "table" and args or {}
    if mutating == true then
        sequence = sequence + 1
        payloadArgs.requestId = string.format("%d:%d", math.floor(Config.nowMs()), sequence)
    end

    if Net.isMultiplayerClient() then
        if type(sendClientCommand) ~= "function" then return false end
        sendClientCommand(player, Config.MODULE, tostring(command), payloadArgs)
        return true
    end

    -- 单机 / 主机：服务端代码在同一进程里，直接调
    local service = Config.Service
    if service == nil or type(service.dispatch) ~= "function" then return false end
    local ok, payload = pcall(service.dispatch, player, tostring(command), payloadArgs)
    if not ok then
        Config.warn("dispatch failed: " .. tostring(payload))
        return false
    end
    if type(payload) == "table" then Net.apply(payload) end
    return true
end

-- 联机下的回包
local function onServerCommand(module, command, args)
    if module ~= Config.MODULE then return end
    if tostring(command) ~= "State" then return end
    Net.apply(args)
end

if Events ~= nil and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(onServerCommand)
end

return Net
