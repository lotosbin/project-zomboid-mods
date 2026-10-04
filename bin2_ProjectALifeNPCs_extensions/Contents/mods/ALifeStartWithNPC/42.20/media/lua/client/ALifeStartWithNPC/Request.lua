--[[
    ALifeStartWithNPC :: Request（仅客户端加载）

    联机时由客户端在角色创建后向服务端请求一次发放。
    module 名使用我们自己的 mod id —— 这是 A-Life 侧明文规定的红线：
    "ProjectALife" 是对方 Debug 服务的白名单领地，第三方不得复用。

    纯单机（isClient()=false）不发请求，由服务端文件直接处理。
]]

require "ALifeStartWithNPC/Config"
local Config = ALifeStartWithNPC

-- 注意：这里**故意不做"每个 playerIndex 只发一次"的守卫**。
-- 早期版本用 requested[playerIndex] 永久去重，结果玩家死亡重生后不再发请求，
-- 表现为"开了 GrantOnRespawn 也不重新发放"。服务端对重复请求是幂等的
-- （已发放会打印 already granted 并跳过；令牌已变则重新生成），所以每次角色创建都发一次最稳。
local sentCount = 0

local function onCreatePlayer(playerIndex, player)
    if not isClient() then return end               -- 纯单机走服务端直连路径
    if player == nil or player:isDead() then return end
    sentCount = sentCount + 1

    -- 延后一 tick 再发：让玩家对象完全初始化（与 CD_StartWithDog 的做法一致）
    local tick
    tick = function()
        pcall(function() Events.OnTick.Remove(tick) end)
        if player == nil or player:isDead() then return end
        Config.log("requesting grant from server (request #" .. tostring(sentCount) .. ")")
        sendClientCommand(player, Config.MODULE, "requestGrant", {})
    end
    Events.OnTick.Add(tick)
end

if Events ~= nil and Events.OnCreatePlayer ~= nil then
    Events.OnCreatePlayer.Add(onCreatePlayer)
end

return { sentCount = sentCount }
