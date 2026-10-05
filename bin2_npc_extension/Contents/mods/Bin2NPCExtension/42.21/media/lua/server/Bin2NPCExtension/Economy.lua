--[[
    Bin2NPCExtension :: Economy（server，橙子社区经济适配层）

    钱的唯一通道：OrangeTradingModServer.Pay / AddCoins。
    客户端传来的价格一律不采信 —— 服务端用沙盒选项重算。

    这些函数都是橙子经济 server/runtime_core.lua 里导出的全局函数（见
    docs/research/economy-integration-hooks.md），我们只读不写它的存档形状。
]]

require "Bin2NPCExtension/Config"

local Config = Bin2NPCExtension

local Economy = {}
Config.Economy = Economy

function Economy.available()
    return Config.economyServer() ~= nil and type(Config.economyServer().Pay) == "function"
end

-- 玩家余额（读不到返回 nil，让调用方区分"没钱"与"读不到"）
function Economy.balance(player)
    local server = Config.economyServer()
    if server == nil or player == nil then return nil end
    local ok, data = pcall(server.PlayerData, player)
    if not ok or type(data) ~= "table" then return nil end
    return tonumber(data.coins) or 0
end

--[[
    扣款。橙子经济的 Pay 是服务端权威的（会重新校验余额并 Transmit 给客户端），
    返回 true/false；我们不用它的返回值做"原子回滚"，而是在调用方决定要不要退钱。
]]
function Economy.pay(player, amount)
    local server = Config.economyServer()
    local price = tonumber(amount) or 0
    if server == nil then return false, "no_economy" end
    if price <= 0 then return true end
    if type(server.Pay) ~= "function" then return false, "no_economy" end
    local ok, paid = pcall(server.Pay, player, price)
    if not ok then return false, "pay_failed" end
    if paid ~= true then return false, "no_funds" end
    Economy.flow(player, "out", "npc_hire", "FlowHire", price)
    return true
end

--[[
    退款（造人失败 / 收编失败时把已扣的钱还回去）。

    必须与扣款一样写流水：否则玩家的账单里只有"支出"，看不到这笔钱回来了，
    对账时会以为钱丢了。
]]
function Economy.refund(player, amount)
    local server = Config.economyServer()
    local price = tonumber(amount) or 0
    if server == nil or price <= 0 or type(server.AddCoins) ~= "function" then return false end
    local ok = pcall(server.AddCoins, player, price)
    if ok then
        Economy.flow(player, "in", "npc_hire_refund", "FlowRefund", price)
        Config.warn("refunded " .. tostring(price) .. " to " .. tostring(Config.Store.playerName(player)))
    end
    return ok
end

--[[
    记一笔流水，让雇人的收支出现在玩家账单里（可选能力，对方没有这个函数就算了）。
    direction："out" = 支出，"in" = 收入。
]]
function Economy.flow(player, direction, kind, labelKey, amount)
    local server = Config.economyServer()
    if server == nil or type(server.RecordPlayerFlow) ~= "function" then return false end
    local price = tonumber(amount) or 0
    if price <= 0 then return false end
    local key = type(labelKey) == "string" and labelKey or "FlowHire"
    local extra = { labelKey = key, label = Config.Text.get(key), peer = "NPC" }
    local ok = pcall(server.RecordPlayerFlow, player, direction == "in" and "in" or "out", kind,
        "Bin2NPCExtension.contract", 1, price, extra)
    return ok
end

-- 兼容旧调用名（测试与未来的调用点）
function Economy.record(player, amount, labelKey)
    return Economy.flow(player, "out", "npc_hire", labelKey or "FlowHire", amount)
end

-- 每名雇员的日薪
function Economy.wage()
    if not Config.wageEnabled() then return 0 end
    return Config.dailyWage()
end

return Economy
