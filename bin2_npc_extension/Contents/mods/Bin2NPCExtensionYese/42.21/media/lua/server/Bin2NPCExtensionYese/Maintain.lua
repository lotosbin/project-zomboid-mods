--[[
    Bin2NPCExtensionYese :: Maintain（server，周期维护）

    五件事，全部是"周期性核对"，不依赖任何一次性回调：
      1. **岗位对账**：契约里的 `mode` 只是 Jeem 那份权威状态（`memory.jimmyResident`）的缓存，
         两边分叉时以事实为准双向自愈（见 reconcile）。
      2. **岗位补派**：刚造出来的 NPC 要等 lifecycle=="active" 才能下命令，
         spawn 期间契约的 note 是 "pending"，这里续跑 Service.applyMode。
      3. **指令重下**：A-Life 的 DecisionLoop.orders 是纯内存表，读档即失效；
         跟随/守卫契约必须像 Jeem 的 Friendlies.sync 那样周期重下（quiet 模式，不刷动画）。
      4. **阵亡清理**：record 消失或 lifecycle=="dead" → 契约标记 dead，释放名额。
      5. **日薪结算**：每个满 24 世界小时扣一次工资；欠薪超过宽限期就解约走人。
]]

require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Contracts"
require "Bin2NPCExtensionYese/Store"
require "Bin2NPCExtensionYese/Alife"
require "Bin2NPCExtensionYese/Jimmy"
require "Bin2NPCExtensionYese/Economy"
require "Bin2NPCExtensionYese/Service"

local Config = Bin2NPCExtensionYese
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
local RECONCILE_MS = 30000             -- 契约岗位与 Jeem 权威状态的对账间隔
local lastReconcileAt = {}             -- uid -> ms

--[[
    把契约上的 `mode` 拉回 Jeem 的**事实**（`memory.jimmyResident`）。双向自愈：

      * 事实是居民、契约写着跟随 —— 同小队一起被收编、Jeem 自己的右键「邀请入住」、
        或者在别的界面操作过，都会造成这种分叉。分叉的表象就是玩家最困惑的那一个：
        "人明明已经是队友了，面板还写跟随，再点居民还被拒（resident = 他已经是居民了）"。
      * 契约写着居民、事实已经不是 —— 在 Jeem 的管理台把他送走了，或者居民系统把他清了。

    返回 true 表示契约被改过（调用方据此标脏并推送状态）。
]]
local function reconcile(contract, now)
    if Jimmy.available() ~= true then return false end
    if now - (lastReconcileAt[contract.uid] or 0) < RECONCILE_MS then return false end
    lastReconcileAt[contract.uid] = now

    local record = Alife.record(contract.uid)
    if record == nil or record.lifecycle ~= "active" then return false end

    local entry = Jimmy.residentEntry(record)
    local mode = Config.normalizeMode(contract.mode)
    if entry ~= nil and mode ~= Config.MODE_RESIDENT then
        contract.mode = Config.MODE_RESIDENT
        contract.baseId = entry.baseId
        contract.note = nil
        Config.always("reconcile: " .. tostring(contract.uid) .. " is a Jeem resident (base "
            .. tostring(entry.baseId) .. ") but this contract said " .. tostring(mode)
            .. "; corrected to resident")
        return true
    end
    if entry == nil and mode == Config.MODE_RESIDENT then
        contract.mode = Config.MODE_FOLLOW
        contract.baseId = nil
        contract.note = "left_residence"
        Config.always("reconcile: " .. tostring(contract.uid)
            .. " is no longer a Jeem resident; the contract fell back to follow")
        return true
    end
    return false
end

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
                        -- 先对账（会把 mode 改回事实），再按对账后的岗位决定要不要重下指令
                        if reconcile(contract, now) then dirty = true end
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
                    lastReconcileAt[contract.uid] = 0        -- 进世界第一件事：与 Jeem 对一次账
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
