--[[
    ALifeStartWithNPC :: Request（仅客户端加载）

    联机时由客户端在角色创建后向服务端请求一次发放。
    module 名使用我们自己的 mod id —— 这是 A-Life 侧明文规定的红线：
    "ProjectALife" 是对方 Debug 服务的白名单领地，第三方不得复用。

    纯单机（isClient()=false）不发请求，由服务端文件直接处理。
]]

require "ALifeStartWithNPC/Config"
local Config = ALifeStartWithNPC

local requested = {}

local function onCreatePlayer(playerIndex, player)
    if not isClient() then return end               -- 纯单机走服务端直连路径
    if requested[playerIndex] then return end
    if player == nil or player:isDead() then return end
    requested[playerIndex] = true

    -- 延后一 tick 再发：让玩家对象完全初始化（与 CD_StartWithDog 的做法一致）
    local tick
    tick = function()
        pcall(function() Events.OnTick.Remove(tick) end)
        if player == nil or player:isDead() then return end
        Config.log("requesting grant from server")
        sendClientCommand(player, Config.MODULE, "requestGrant", {})
    end
    Events.OnTick.Add(tick)
end

if Events ~= nil and Events.OnCreatePlayer ~= nil then
    Events.OnCreatePlayer.Add(onCreatePlayer)
end

return { requested = requested }
