--[[
    Bin2NPCExtension :: Maintain（server，周期维护）

    四件事，全部是"周期性核对"，不依赖任何一次性回调：
      1. **岗位补派**：刚造出来的 NPC 要等 lifecycle=="active" 才能下命令，
         spawn 期间契约的 note 是 "pending"，这里续跑 Service.applyMode。
      2. **指令重下**：A-Life 的 DecisionLoop.orders 是纯内存表，读档即失效；
         跟随/守卫契约必须像 Jeem 的 Friendlies.sync 那样周期重下（quiet 模式，不刷动画）。
      3. **阵亡清理**：record 消失或 lifecycle=="dead" → 契约标记 dead，释放名额。
      4. **日薪结算**：每个满 24 世界小时扣一次工资；欠薪超过宽限期就解约走人。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Contracts"
require "Bin2NPCExtension/Store"
require "Bin2NPCExtension/Alife"
require "Bin2NPCExtension/Jimmy"
require "Bin2NPCExtension/Economy"
require "Bin2NPCExtension/Service"

local Config = Bin2NPCExtension
local Contracts = Config.Contracts
local Store = Config.Store
local Alife = Config.Alife
local Jimmy = Config.Jimmy
local Economy = Config.Economy
local Service = Config.Service

local Maintain = {}
Config.Maintain = Maintain

local ORDER_REFRESH_MS = 8000          -- 同一份跟随/守卫指令的重下间隔
local lastOrderAt = {}                 -- uid -> ms

local function onlinePlayers()
    local players = {}
    local count = 1
    local ok, value = pcall(function()
        return getNumActivePlayers and getNumActivePlayers() or 1
    end)
    if ok and tonumber(value) ~= nil then count = math.max(1, math.floor(tonumber(value))) end
    for index = 0, count - 1 do
        local okPlayer, player = pcall(getSpecificPlayer, index)
        if okPlayer and player ~= nil then
            local dead = false
            pcall(function() dead = player:isDead() == true end)
            if not dead then players[#players + 1] = player end
        end
    end
    return players
end

Config.onlinePlayers = onlinePlayers

--[[
    每 tick 调用（Bootstrap 自己做节流，这里按 ~1 秒粒度跑）。
]]
function Maintain.tick()
    if not Config.enabled() then return end
    if not Alife.available() then return end
    local now = Config.nowMs()

    for _, player in ipairs(onlinePlayers()) do
        local node = Store.node(player, false)
        if node ~= nil then
            local dirty = false
            for _, contract in ipairs(Contracts.list(node)) do
                if contract.status == "active" then
                    local record = Alife.record(contract.uid)
                    if record == nil or record.lifecycle == "dead" then
                        contract.status = "dead"
                        contract.deadHours = Config.worldHours()
                        contract.note = "dead"
                        dirty = true
                        Config.log("contract " .. tostring(contract.uid) .. " is gone (dead)")
                    elseif record.lifecycle == "active" then
                        local mode = Config.normalizeMode(contract.mode)
                        if contract.note == "pending" or mode == Config.MODE_FOLLOW
                                or mode == Config.MODE_GUARD then
                            local due = now - (lastOrderAt[contract.uid] or 0) >= ORDER_REFRESH_MS
                            if due then
                                lastOrderAt[contract.uid] = now
                                -- quiet=true：这是"重下"，不是"下令" —— 不重放动画与 ORDER_ACK
                                local applied, why = Service.applyMode(player, contract, mode, true)
                                -- applyMode 会写 note，成功的重下不该改变已有说明
                                if not applied and why ~= "pending" then
                                    Config.log("order refresh failed for " .. tostring(contract.uid)
                                        .. ": " .. tostring(why))
                                end
                                dirty = true
                            end
                        end
                    end
                end
            end
            if dirty then
                Store.transmit()
                Service.push(player, Service.state(player))
            end
        end
    end
end

--[[
    日薪结算（每分钟调用一次；真正扣钱只在跨过 24 世界小时时发生）。
]]
function Maintain.settleWages()
    if not Config.enabled() then return end
    local wage = Economy.wage()
    if wage <= 0 then return end
    if not Economy.available() then return end

    local hours = Config.worldHours()
    local grace = Config.unpaidGraceDays() * 24

    for _, player in ipairs(onlinePlayers()) do
        local node = Store.node(player, false)
        if node ~= nil then
            local dirty = false
            for _, contract in ipairs(Contracts.list(node)) do
                if contract.status == "active" then
                    local paid = tonumber(contract.wagePaidHours) or hours
                    local elapsed = hours - paid
                    if elapsed >= 24 then
                        local days = math.floor(elapsed / 24)
                        local amount = wage * days
                        local ok = Economy.pay(player, amount)
                        if ok then
                            contract.wagePaidHours = paid + days * 24
                            contract.unpaidSince = nil
                            dirty = true
                            Config.log(string.format("wage %s paid for %s (%d day(s))",
                                tostring(amount), tostring(contract.uid), days))
                        else
                            if contract.unpaidSince == nil then
                                contract.unpaidSince = hours
                                dirty = true
                            end
                            Config.log("wage unpaid for " .. tostring(contract.uid))
                        end
                    end
                    if contract.unpaidSince ~= nil and grace >= 0
                            and (hours - contract.unpaidSince) >= grace then
                        -- 欠薪太久：解约走人（居民要退出 Jeem 的居民系统）
                        if Config.normalizeMode(contract.mode) == Config.MODE_RESIDENT
                                and Jimmy.available() then
                            pcall(Jimmy.leaveOne, player, contract.uid)
                        end
                        Alife.clearOrder(contract.uid)
                        contract.status = "dismissed"
                        contract.note = "unpaid"
                        Config.always("contract " .. tostring(contract.uid) .. " ended: unpaid wage")
                        dirty = true
                    end
                end
            end
            if dirty then
                Store.transmit()
                Service.push(player, Service.state(player))
            end
        end
    end
end

--[[
    进档恢复：A-Life 的 orders 不持久化，所以每次进世界都要把跟随/守卫指令重新下一次。
    由 Bootstrap 挂在 OnGameStart / OnServerStarted 上（两者都挂，覆盖单机与专用服）。
]]
function Maintain.restore()
    if not Config.enabled() then return end
    if not Alife.available() then return end
    for _, player in ipairs(onlinePlayers()) do
        local node = Store.node(player, false)
        if node ~= nil then
            for _, contract in ipairs(Contracts.list(node)) do
                if contract.status == "active" then
                    local mode = Config.normalizeMode(contract.mode)
                    if mode == Config.MODE_FOLLOW or mode == Config.MODE_GUARD then
                        lastOrderAt[contract.uid] = 0        -- 强制立刻重下
                    end
                end
            end
        end
    end
    Config.log("restored orders for active contracts")
    Maintain.tick()
end

return Maintain
