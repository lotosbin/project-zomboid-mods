--[[
    ALifeStartWithNPC :: Bootstrap（仅服务端加载）

    触发路径（与社区成熟模组 CD_StartWithDog 同构，因为它已被验证可行）：
      * 纯单机（isClient()=false 且 isServer()=false）：OnCreatePlayer 直接开跑。
      * 联机（含主机与专用服）：客户端发 requestGrant → 这里的 OnClientCommand 开跑。
        （专用服上 OnCreatePlayer 也会触发，但同一分支会 return，避免重复。）
      * EveryOneMinute 兜底重试，最多 Config.RETRY_MAX 次。

    为什么不能在这里直接造人：
      OnCreatePlayer/OnGameStart 时 A-Life 的 Runtime 往往还没 started，
      SpawnService.request 会返回 runtime_not_started。所以一律交给 Grant.run 里的条件判断，
      由 Grant 自己决定"这次能不能干"，不能干就返回 false 等下一 tick。
]]

require "ALifeStartWithNPC/Config"
local Config = ALifeStartWithNPC
local Grant = require "ALifeStartWithNPC/Grant"

local Bootstrap = {}
local pollFn = nil
local pollStartedAtMs = 0
local retries = 0

local function nowMs()
    local ok, value = pcall(getTimestampMs)
    if ok and value ~= nil then return value end
    local okTime, seconds = pcall(function() return (os and os.time) and os.time() or nil end)
    if okTime and type(seconds) == "number" then return math.floor(seconds * 1000) end
    return 0
end

local function stopPoll()
    if pollFn ~= nil then
        pcall(function() Events.OnTick.Remove(pollFn) end)
        pollFn = nil
    end
end

-- 尝试发放一次；返回 true 表示"已完成，不用再试"
local function attempt(player)
    if player == nil then return true end
    local ok, done, why = pcall(Grant.run, player)
    if not ok then
        Config.error("grant crashed: " .. tostring(done))
        return true                          -- 崩溃不重试，避免刷屏
    end
    if done == true then return true end
    if why ~= nil and why ~= "runtime_not_started" and why ~= "player_square_unloaded" then
        Config.log("grant deferred: " .. tostring(why))
    end
    return false
end

-- 开始轮询，直到世界就绪（或超时）
function Bootstrap.start(player)
    if player == nil or player:isDead() then return end
    if pollFn ~= nil then return end
    pollStartedAtMs = nowMs()
    pollFn = function()
        if player:isDead() then stopPoll() return end
        if attempt(player) then stopPoll() return end
        if nowMs() - pollStartedAtMs > Config.READY_TIMEOUT_MS then
            stopPoll()
            Config.warn("world was not ready within " .. tostring(math.floor(Config.READY_TIMEOUT_MS / 1000))
                .. "s; will retry once a minute")
        end
    end
    Events.OnTick.Add(pollFn)
end

-- 联机：客户端请求
local function onClientCommand(module, command, player, args)
    if module ~= Config.MODULE then return end
    if command ~= "requestGrant" then return end
    if player == nil or player:isDead() then return end
    Config.log("grant requested by " .. tostring(player) .. " (client)")
    Bootstrap.start(player)
end

-- 纯单机：直接处理
local function onCreatePlayer(playerIndex, player)
    if isClient() or isServer() then return end
    Config.log("OnCreatePlayer (singleplayer) -> scheduling grant")
    Bootstrap.start(player)
end

-- 兜底：每分钟再看一次（服务器慢、模组加载顺序异常等情况）
local function onEveryMinute()
    if retries >= Config.RETRY_MAX then return end
    local n = getNumActivePlayers and getNumActivePlayers() or 1
    for i = 0, n - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil and not player:isDead() then
            local granted = false
            pcall(function()
                local md = player:getModData()
                granted = type(md) == "table" and md[Config.KEY_GRANTED] == true
            end)
            if not granted then
                retries = retries + 1
                Bootstrap.start(player)
                return                          -- 一次只处理一个，别在同一个 tick 里堆
            end
        end
    end
end

if Events ~= nil then
    if Events.OnClientCommand ~= nil then Events.OnClientCommand.Add(onClientCommand) end
    if Events.OnCreatePlayer ~= nil then Events.OnCreatePlayer.Add(onCreatePlayer) end
    if Events.EveryOneMinute ~= nil then Events.EveryOneMinute.Add(onEveryMinute) end
    -- 开局做一次兼容性自检（复用 A-Life 自己的检测器），把"自带 A-Life Lua 副本"的模组点名报出来
    local function compatCheck()
        local ok, err = pcall(Grant.reportForeignCopies)
        if not ok then Config.log("compat check failed: " .. tostring(err)) end
    end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(compatCheck) end
    if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(compatCheck) end

    -- 每 tick 推进"等实体激活 → 下 follow 命令 / 转居民"的队列
    if Events.OnTick ~= nil then
        Events.OnTick.Add(function()
            local ok, err = pcall(Grant.tick)
            if not ok then Config.error("tick failed: " .. tostring(err)) end
        end)
    end
end

Config.log("Bootstrap loaded (v" .. tostring(Config.VERSION) .. ")", true)

return Bootstrap
