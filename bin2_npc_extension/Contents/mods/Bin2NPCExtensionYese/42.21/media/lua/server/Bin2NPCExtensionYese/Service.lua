--[[
    Bin2NPCExtensionYese :: Service（server，命令处理 = 唯一改状态的地方）

    客户端 → 服务端：
        module = "Bin2NPCExtensionYese"（我们自己的 mod id，不能借用 A-Life / Jeem 的）
        command ∈ { RequestState, ScanCandidates, HireExisting, HireSpawned, SetMode, Dismiss }

    服务端 → 客户端：
        sendServerCommand(player, "Bin2NPCExtensionYese", "State", payload)
    单机下 sendServerCommand 是空操作，所以 dispatch 同时**返回** payload，
    客户端 Net 层在单机下直接拿返回值（Jeem 的 Menu.send 也是这个套路）。
]]

require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Contracts"
require "Bin2NPCExtensionYese/Text"
require "Bin2NPCExtensionYese/Store"
require "Bin2NPCExtensionYese/Alife"
require "Bin2NPCExtensionYese/Jimmy"
require "Bin2NPCExtensionYese/Economy"

local Config = Bin2NPCExtensionYese
local Contracts = Config.Contracts
local Store = Config.Store
local Alife = Config.Alife
local Jimmy = Config.Jimmy
local Economy = Config.Economy

local Service = {}
Config.Service = Service

-- 最近一次操作的结果，客户端读它来弹提示
local lastResult = {}

--[[
    组装给客户端的完整状态。全部是基本类型，可以直接被 sendServerCommand 序列化。
]]
function Service.state(player, extra)
    local alifeReady = Alife.available()
    local jeemReady = Jimmy.available()
    local economyReady = Economy.available()
    local store = Store.data()
    local key = Store.playerKey(player)
    local node = Contracts.player(store, key, false)

    local rows = {}
    for _, contract in ipairs(Contracts.list(node)) do
        local record = alifeReady and Alife.record(contract.uid) or nil
        local lifecycle = record and tostring(record.lifecycle) or "missing"
        local status = contract.status
        if status == "active" and lifecycle == "dead" then status = "dead" end
        local distance = nil
        if record ~= nil then
            local position = Alife.actorPosition(contract.uid, record)
            distance = Alife.distance(Alife.position(player), position)
        end
        rows[#rows + 1] = {
            uid = contract.uid,
            id = tostring(contract.id or ""),
            name = tostring(contract.name or contract.uid),
            mode = Config.normalizeMode(contract.mode),
            status = status,
            source = tostring(contract.source or "hired"),
            factionId = tostring(contract.factionId or ""),
            profileId = tostring(contract.profileId or ""),
            price = tonumber(contract.price) or 0,
            hiredHours = tonumber(contract.hiredHours) or 0,
            unpaid = contract.unpaidSince ~= nil,
            baseId = contract.baseId and tostring(contract.baseId) or nil,
            distance = distance and (math.floor(distance * 10 + 0.5) / 10) or nil,
            note = contract.note and tostring(contract.note) or nil,
        }
    end

    local result = lastResult[key]
    lastResult[key] = nil

    local payload = {
        schema = Config.SCHEMA,
        version = Config.VERSION,
        coins = economyReady and (Economy.balance(player) or 0) or 0,
        limits = {
            max = Config.maxContracts(),
            used = Contracts.activeCount(node),
        },
        prices = {
            sign = Config.signPrice(),
            spawn = Config.spawnPrice(),
            wage = Economy.wage(),
        },
        capabilities = {
            economy = economyReady,
            alife = alifeReady,
            jeem = jeemReady,
            enabled = Config.enabled(),
        },
        contracts = rows,
        result = result,
    }
    if type(extra) == "table" then
        for name, value in pairs(extra) do payload[name] = value end
    end
    return payload
end

-- 把状态推给指定玩家（单机下是空操作，靠 dispatch 的返回值）
function Service.push(player, payload)
    if type(sendServerCommand) ~= "function" then return payload end
    pcall(sendServerCommand, player, Config.MODULE, "State", payload)
    return payload
end

function Service.fail(player, code)
    lastResult[Store.playerKey(player)] = { ok = false, code = tostring(code or "failed") }
    return code
end

function Service.ok(player, code)
    lastResult[Store.playerKey(player)] = { ok = true, code = tostring(code or "ok") }
    return code
end

-- 契约里记一条"最近发生了什么"，玩家在 UI 上能看到降级原因
local function note(contract, value)
    contract.note = value ~= nil and tostring(value) or nil
end

-- 玩家与 NPC 的距离（服务端权威；Jeem 自己不校验距离，我们补上）
local function withinReach(player, uid, radius)
    local record = Alife.record(uid)
    if record == nil then return false, "not_found" end
    local position = Alife.actorPosition(uid, record)
    local origin = Alife.position(player)
    local distance = Alife.distance(origin, position)
    if distance == nil then return false, "not_found" end
    if distance > (tonumber(radius) or Config.recruitRadius()) then return false, "too_far" end
    return true
end

--[[
    把契约落到 NPC 身上（岗位指派）。

    失败一律**降级**而不是撤销契约：钱已经收了，人也造出来了，
    最差也要给玩家一个"跟随"的雇员，并在契约上写明降级原因。

    quiet=true 用于 Maintain 的周期重下：不重放 follow/stop 动画与 ORDER_ACK 语音，
    否则每 8 秒都会"啊"一声。
]]
function Service.applyMode(player, contract, mode, quiet)
    local wanted = Config.normalizeMode(mode)
    contract.mode = wanted

    local uid = contract.uid
    local record = Alife.record(uid)
    if record == nil then
        note(contract, "not_found")
        return false, "not_found"
    end
    if record.lifecycle ~= "active" then
        -- 还没落地（spawn 中）：交给 Maintain 的 tick 继续推进
        note(contract, "pending")
        return false, "pending"
    end

    -- 防人口回收：雇佣期间不许 A-Life 把这个人回收掉
    Alife.protect(uid)

    local degraded = nil

    if wanted == Config.MODE_RESIDENT then
        if Jimmy.available() then
            local count, why, joined, baseId = Jimmy.recruit(player, uid)
            if count ~= nil then
                contract.baseId = baseId
                note(contract, nil)
                return true, "resident"
            end
            Config.log("resident conversion refused (" .. tostring(why) .. "), falling back to follow")
            degraded = "resident:" .. tostring(why)
        else
            degraded = "no_jeem"
        end
        wanted = Config.MODE_FOLLOW
        contract.mode = wanted
    end

    if wanted == Config.MODE_GUARD then
        local anchor = Alife.position(player) or record.worldPosition
        contract.anchor = anchor
        local done, why = Alife.orderHold(uid, anchor, quiet)
        if done then
            note(contract, degraded)
            return true, degraded and "degraded" or "guard"
        end
        degraded = (degraded ~= nil and (degraded .. "/") or "") .. "guard:" .. tostring(why)
        wanted = Config.MODE_FOLLOW                          -- hold 被拒也退回跟随
        contract.mode = wanted
    end

    local done, why = Alife.orderFollow(player, uid, quiet)
    if done then
        note(contract, degraded)
        return true, degraded and "degraded" or "follow"
    end
    note(contract, degraded ~= nil and (degraded .. "/follow:" .. tostring(why)) or ("follow:" .. tostring(why)))
    return false, tostring(why)
end

--[[
    同一个物品里的"另一个口味"是否已经雇了这名 NPC（只读对方的存档表，拿不到就当没有）。

    两个模组各有一份 ModData，但**同一个 NPC 只能属于一个人**；没有这道互查，
    玩家可以在这个界面雇一次、在另一个界面再雇一次，两边名册同时认领同一个 actor，
    后续指令会互相顶掉（DecisionLoop.orders 一人一槽）。
]]
local function takenBySibling(uid)
    local siblingId = Config.SIBLING_MODULE
    if type(siblingId) ~= "string" or siblingId == "" then return false end
    local sibling = rawget(_G, siblingId)
    if type(sibling) ~= "table" then return false end
    local contracts, store = sibling.Contracts, sibling.Store
    if type(contracts) ~= "table" or type(store) ~= "table" then return false end
    if type(contracts.owner) ~= "function" or type(store.data) ~= "function" then return false end
    local ok, data = pcall(store.data)
    if not ok or type(data) ~= "table" then return false end
    local okOwner, ownerKey = pcall(contracts.owner, data, uid)
    if not okOwner then return false end
    return ownerKey ~= nil
end

-- 收编一个已经在场的 NPC
function Service.hireExisting(player, uid, mode)
    if not Config.enabled() then return Service.fail(player, "disabled") end
    if type(uid) ~= "string" or uid == "" then return Service.fail(player, "not_found") end
    if not Alife.available() then return Service.fail(player, "no_alife") end
    if not Economy.available() then return Service.fail(player, "no_economy") end

    local key = Store.playerKey(player)
    local node = Store.node(player, true)
    if Contracts.activeCount(node) >= Config.maxContracts() then return Service.fail(player, "limit_reached") end

    local existing = Contracts.get(node, uid)
    if existing ~= nil and existing.status == "active" then return Service.fail(player, "already_hired") end

    local ownerKey = Contracts.owner(Store.data(), uid)
    if ownerKey ~= nil and ownerKey ~= key then return Service.fail(player, "taken_by_other") end
    if takenBySibling(uid) then return Service.fail(player, "taken_by_other") end

    local record = Alife.record(uid)
    if record == nil then return Service.fail(player, "not_found") end
    if record.lifecycle ~= "active" then return Service.fail(player, "not_active") end
    local inReach, reachWhy = withinReach(player, uid, Config.recruitRadius())
    if not inReach then return Service.fail(player, reachWhy) end
    if Alife.isHostile(record, player) and not Config.allowHostile() then
        return Service.fail(player, "hostile")
    end

    local price = Config.signPrice()
    local paid, payWhy = Economy.pay(player, price)
    if not paid then return Service.fail(player, payWhy or "no_funds") end

    local contract = {
        uid = uid,
        name = Alife.name(record),
        factionId = tostring(record.factionId or ""),
        profileId = tostring(record.profileId or ""),
        mode = Config.normalizeMode(mode or Config.defaultMode()),
        source = "hired",
        status = "active",
        price = price,
        hiredHours = Config.worldHours(),
        wagePaidHours = Config.worldHours(),
    }
    Contracts.add(node, contract)
    local applied, appliedWhy = Service.applyMode(player, contract, contract.mode)
    Store.transmit()
    Service.ok(player, applied and "hired" or ("hired_degraded:" .. tostring(appliedWhy)))
    Config.log(string.format("%s hired %s (%s) for %s", tostring(key), tostring(uid),
        tostring(contract.mode), tostring(price)))
    return Service.push(player, Service.state(player))
end

-- 中介派遣：花钱让 A-Life 现造一个
function Service.hireSpawned(player, mode)
    if not Config.enabled() then return Service.fail(player, "disabled") end
    if not Alife.available() then return Service.fail(player, "no_alife") end
    if not Economy.available() then return Service.fail(player, "no_economy") end

    local key = Store.playerKey(player)
    local node = Store.node(player, true)
    local used = Contracts.activeCount(node)
    if used >= Config.maxContracts() then return Service.fail(player, "limit_reached") end

    local factionId, profileId, pickWhy = Alife.pickFactionProfile()
    if factionId == nil then
        Config.warn("cannot pick a faction/profile: " .. tostring(pickWhy))
        return Service.fail(player, "no_alife")
    end

    local spot, spotWhy = Alife.freeSquareNear(player, Config.spawnDistance(), used + 1)
    if spot == nil then return Service.fail(player, spotWhy or "spawn_failed") end

    -- 扣款放在造人之前：Pay 会重新校验余额，失败时我们还什么都没造，回滚成本最低
    local price = Config.spawnPrice()
    local paid, payWhy = Economy.pay(player, price)
    if not paid then return Service.fail(player, payWhy or "no_funds") end

    local operationId = string.format("%s:%s:%d:%d", Config.MODULE, key,
        math.floor(Config.nowMs()), ZombRand(100000))

    local uid, spawnWhy = Alife.spawn({
        operationId = operationId,
        factionId = factionId,
        profileId = profileId,
        worldPosition = spot,
    })
    if uid == nil then
        Economy.refund(player, price)
        Config.warn("spawn failed: " .. tostring(spawnWhy))
        return Service.fail(player, "spawn_failed")
    end

    -- SpawnService 受理之后记录仍可能被回收（人口裁剪 / 目录删除 / 管理员清理）。
    -- 契约是"人还在"的凭据，人没了就必须退款，不能让玩家花钱买一个空 uid。
    local record = Alife.record(uid)
    if record == nil then
        Alife.retire(uid, "bin2npc_vanished")
        Economy.refund(player, price)
        Config.warn("spawned actor " .. tostring(uid) .. " vanished right after the request; refunded")
        return Service.fail(player, "spawn_failed")
    end

    local contract = {
        uid = uid,
        name = Alife.name(record),
        factionId = factionId,
        profileId = profileId,
        mode = Config.normalizeMode(mode or Config.defaultMode()),
        source = "spawned",
        status = "active",
        price = price,
        hiredHours = Config.worldHours(),
        wagePaidHours = Config.worldHours(),
    }
    Contracts.add(node, contract)
    note(contract, "pending")                                -- 等实体激活后再指派岗位
    Store.transmit()
    Service.ok(player, "summoned")
    Config.log(string.format("%s summoned %s (%s) for %s", tostring(key), tostring(uid),
        tostring(contract.mode), tostring(price)))
    return Service.push(player, Service.state(player))
end

-- 换岗位（跟随 / 守卫 / 居民）
function Service.setMode(player, uid, mode)
    if not Config.enabled() then return Service.fail(player, "disabled") end
    local node = Store.node(player, true)
    local contract = Contracts.get(node, uid)
    if contract == nil or contract.status ~= "active" then return Service.fail(player, "not_found") end

    -- 居民要退出居民系统才能改回跟随/守卫
    local current = Config.normalizeMode(contract.mode)
    local wanted = Config.normalizeMode(mode)
    if current == Config.MODE_RESIDENT and wanted ~= Config.MODE_RESIDENT then
        if Jimmy.available() then
            local done, why = Jimmy.leaveOne(player, uid)
            if done ~= true then Config.log("leaveOne refused (" .. tostring(why) .. "), continuing") end
        end
    end

    contract.baseId = wanted == Config.MODE_RESIDENT and contract.baseId or nil
    local applied, appliedWhy = Service.applyMode(player, contract, wanted)
    Store.transmit()
    Service.ok(player, applied and "mode" or ("mode_degraded:" .. tostring(appliedWhy)))
    return Service.push(player, Service.state(player))
end

-- 解雇（清岗位 + 从名册删除；签约金不退，工资结算到当天）
function Service.dismiss(player, uid)
    if not Config.enabled() then return Service.fail(player, "disabled") end
    local node = Store.node(player, true)
    local contract = Contracts.get(node, uid)
    if contract == nil then return Service.fail(player, "not_found") end

    if Config.normalizeMode(contract.mode) == Config.MODE_RESIDENT and Jimmy.available() then
        local done, why = Jimmy.leaveOne(player, uid)
        if done ~= true then Config.log("leaveOne refused on dismiss (" .. tostring(why) .. ")") end
    end
    Alife.clearOrder(uid)
    Contracts.remove(node, uid)
    Store.transmit()
    Service.ok(player, "dismissed")
    Config.log(Store.playerKey(player) .. " dismissed " .. tostring(uid))
    return Service.push(player, Service.state(player))
end

--[[
    命令路由。返回 payload（单机下客户端直接拿它刷新 UI；联机下客户端等推送）。

    自带限速与去重：橙子经济的 action_request_guard 是白名单制（只护它自己的命令），
    第三方命令塞不进去，所以改状态的命令必须自己防连点与重放。
]]
local MUTATING = {
    HireExisting = true, HireSpawned = true, SetMode = true, Dismiss = true,
}
local THROTTLE_MS = 400        -- 同一个玩家两次改状态命令之间的最小间隔
local DEDUP_MS = 60000         -- 同一个 requestId 在 60 秒内只认一次
local lastCommandAt = {}
local seenRequests = {}
local seenOrder = {}

local function dedup(player, command, args)
    local key = Store.playerKey(player)
    local now = Config.nowMs()
    if now - (lastCommandAt[key] or 0) < THROTTLE_MS then return "too_fast" end
    local requestId = type(args.requestId) == "string" and args.requestId or ""
    if requestId ~= "" then
        -- 按**时间**而不是条数裁剪：只留 64 条的话，60 秒内连发 65 个不同 requestId
        -- 就能把最早的那条挤出去，之后重放它不再被判 duplicate（去重窗口失守）。
        -- 插入顺序即时间顺序，所以过期的一定是前缀。
        local kept = {}
        for index = 1, #seenOrder do
            local token = seenOrder[index]
            if now - (seenRequests[token] or 0) < DEDUP_MS then
                kept[#kept + 1] = token
            else
                seenRequests[token] = nil
            end
        end
        seenOrder = kept

        local token = key .. "|" .. tostring(command) .. "|" .. requestId
        local stamp = seenRequests[token]
        if stamp ~= nil and now - stamp < DEDUP_MS then return "duplicate" end
        if stamp == nil then seenOrder[#seenOrder + 1] = token end
        seenRequests[token] = now
        -- 兜底上限（理论上到不了：窗口内最多也就几十条命令/人）
        while #seenOrder > 256 do
            local oldest = table.remove(seenOrder, 1)
            seenRequests[oldest] = nil
        end
    end
    lastCommandAt[key] = now
    return nil
end

function Service.dispatch(player, command, args)
    local name = tostring(command or "")
    args = type(args) == "table" and args or {}
    if player == nil then return nil end

    if MUTATING[name] == true then
        local rejected = dedup(player, name, args)
        if rejected ~= nil then
            Service.fail(player, rejected)
            return Service.push(player, Service.state(player))
        end
    end

    if name == "RequestState" then
        return Service.push(player, Service.state(player))
    end
    if name == "ScanCandidates" then
        local radius = Config.recruitRadius()
        local store = Store.data()
        local rows = Alife.available() and Alife.candidates(player, radius, function(uid)
            return Contracts.owner(store, uid) ~= nil
        end) or {}
        return Service.push(player, Service.state(player, {
            candidates = rows,
            candidateRadius = radius,
        }))
    end
    if name == "HireExisting" then
        return Service.hireExisting(player, tostring(args.uid or ""), args.mode)
    end
    if name == "HireSpawned" then
        return Service.hireSpawned(player, args.mode)
    end
    if name == "SetMode" then
        return Service.setMode(player, tostring(args.uid or ""), args.mode)
    end
    if name == "Dismiss" then
        return Service.dismiss(player, tostring(args.uid or ""))
    end
    Config.warn("unknown command: " .. name)
    return nil
end

return Service
