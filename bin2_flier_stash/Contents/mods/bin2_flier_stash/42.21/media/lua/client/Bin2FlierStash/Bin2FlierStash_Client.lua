--[[
    bin2 传单寻宝 —— 客户端
    1) 包一层原版的"点亮地图"两个入口（自动点亮 + 传单窗口底部按钮），点亮时登记地点
    2) 单机：每次玩家更新检查"人到了没有"；联机：把点亮事件发给服务端，由服务端判定与刷怪
    不替换任何原版文件，只做前后置包装；上游改了结构就静默不挂钩（打印一行说明）。
]]

Bin2FlierStash = Bin2FlierStash or {}

-- 点亮一张传单（两个入口都汇到这里）
local function onRevealed(reader, mediaID)
    if not reader or not mediaID then return end
    if isClient() then
        -- 联机：服务端权威，只上报
        sendClientCommand(reader, "Bin2FlierStash", "arm", { mediaID = mediaID })
    else
        if Bin2FlierStash.arm(mediaID) then
            Bin2FlierStash.notifyArmed(reader)
        end
    end
end

-- 入口一：原版 ISReadABook:revealPrintMediaLocationsOnMap（设置里开了"自动点亮"时走这条）
local function hookReadABook()
    if not ISReadABook or not ISReadABook.revealPrintMediaLocationsOnMap then return false end
    if ISReadABook.__bin2FlierStashHooked then return true end
    local orig = ISReadABook.revealPrintMediaLocationsOnMap
    ISReadABook.revealPrintMediaLocationsOnMap = function(self, mediaID)
        local ret = orig(self, mediaID)
        pcall(onRevealed, self and self.character, mediaID)
        return ret
    end
    ISReadABook.__bin2FlierStashHooked = true
    return true
end

-- 入口二：传单窗口底部的"点亮地图"按钮（PrintMediaDefinitions.MiscDetails 驱动，最多 5 个）
local function hookPrintMediaUI()
    if not PZAPI or not PZAPI.UI or not PZAPI.UI.PrintMedia or not PZAPI.UI.PrintMedia.init then
        return false
    end
    if PZAPI.UI.PrintMedia.__bin2FlierStashHooked then return true end
    local origInit = PZAPI.UI.PrintMedia.init
    PZAPI.UI.PrintMedia.init = function(self)
        local ret = origInit(self)
        pcall(function()
            local mediaID = self.media_id
            if not mediaID then return end
            local bottom = self.children and self.children.bottomButtons
            local buttons = bottom and bottom.children
            if not buttons then return end
            for i = 1, 5 do
                local btn = buttons["revealOnMap" .. i]
                if btn and btn.onLeftClick then
                    local origClick = btn.onLeftClick
                    btn.onLeftClick = function(_self, ...)
                        local r = origClick(_self, ...)
                        pcall(onRevealed, getPlayer(), mediaID)
                        return r
                    end
                end
            end
        end)
        return ret
    end
    PZAPI.UI.PrintMedia.__bin2FlierStashHooked = true
    return true
end

local function installHooks()
    local a = hookReadABook()
    local b = hookPrintMediaUI()
    if not a and not b then
        print("[Bin2FlierStash] hooks not installed (upstream UI/timed action shape changed?) - mod idle")
    else
        print(string.format("[Bin2FlierStash] hooks installed (readABook=%s printMediaUI=%s)",
            tostring(a), tostring(b)))
    end
end

installHooks()
Events.OnGameStart.Add(installHooks)   -- 万一加载顺序不同，进游戏再挂一次

-- 单机：自己检查"人到了没有"（联机交给服务端）。每秒一次，别每帧算。
local lastCheck = 0
Events.OnPlayerUpdate.Add(function(player)
    if isClient() then return end
    local now = getTimestampMs()
    if now - lastCheck < Bin2FlierStash.CHECK_INTERVAL_MS then return end
    lastCheck = now
    pcall(Bin2FlierStash.updateArrival, player)
end)
