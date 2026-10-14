--[[
    bin2 传单寻宝 —— 服务端（联机）
    客户端只上报"点亮了哪张传单"，判定与刷怪都在这里做：
      · mediaID 必须在原版 PrintMediaDefinitions 表里
      · 同一地点每个存档只开一次
      · 玩家进到那片区域时再刷（在服务端刷，走服务端权威）
    ⚠ 已知边界：刷怪用的 addZombiesInOutfitArea 原版只在客户端用过（DebugUIs/Tutorial），
      服务端是否可用**未实测**；失败时只打印日志、不刷，不报错。
]]

Bin2FlierStash = Bin2FlierStash or {}

local MIN_INTERVAL_MS = 2000     -- 同一玩家的上报限流
local lastArmed = {}             -- [username] = 时间戳

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "Bin2FlierStash" or command ~= "arm" then return end
    if not player or not args or type(args.mediaID) ~= "string" then return end

    local now = getTimestampMs()
    local who = player:getUsername()
    if lastArmed[who] and now - lastArmed[who] < MIN_INTERVAL_MS then return end
    lastArmed[who] = now

    -- 只接受原版表里认得的地点（自定义地图里不存在的 mediaID 直接丢）
    if not Bin2FlierStash.getRects(args.mediaID) then return end
    if Bin2FlierStash.isDone(args.mediaID) then return end

    if Bin2FlierStash.arm(args.mediaID) then
        print("[Bin2FlierStash] server armed " .. args.mediaID .. " by " .. tostring(who))
        Bin2FlierStash.notifyArmed(player)                       -- 单机/本机服务端场景
        sendServerCommand(player, "Bin2FlierStash", "armed", {})  -- 联机：让客户端弹提示
    end
    -- TODO(联机阶段)：校验这名玩家确实持有/读过这张传单（需要先在真实服务器上确认
    -- 传单物品的 printMedia 是否同步到服务端，因此不在这里写过不了验证的检查）。
end)

-- 服务端侧同样跑"人到了没有"（每秒一次）——只在专职服务端跑，单机由客户端文件负责
local lastCheck = 0
Events.OnPlayerUpdate.Add(function(player)
    if not isServer() then return end
    local now = getTimestampMs()
    if now - lastCheck < Bin2FlierStash.CHECK_INTERVAL_MS then return end
    lastCheck = now
    pcall(Bin2FlierStash.updateArrival, player)
end)
