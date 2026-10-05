--[[
    Bin2NPCExtension :: Service（server，命令处理 = 唯一改状态的地方）

    客户端 → 服务端：
        module = "Bin2NPCExtension"（我们自己的 mod id，不能借用 A-Life / Jeem 的）
        command ∈ { RequestState, ScanCandidates, HireExisting, HireSpawned, SetMode, Dismiss }

    服务端 → 客户端：
        sendServerCommand(player, "Bin2NPCExtension", "State", payload)
    单机下 sendServerCommand 是空操作，所以 dispatch 同时**返回** payload，
    客户端 Net 层在单机下直接拿返回值（Jeem 的 Menu.send 也是这个套路）。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Contracts"
require "Bin2NPCExtension/Text"
require "Bin2NPCExtension/Store"
require "Bin2NPCExtension/Alife"
require "Bin2NPCExtension/Jimmy"
require "Bin2NPCExtension/Economy"

local Config = Bin2NPCExtension
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
    结果的单调序号。

    为什么需要：同一份 payload 可能被投递两次 —— 主机（自己开服）下 `Net.send` 直接拿
    `Service.dispatch` 的返回值应用一次，服务端 `Service.push` 的 `sendServerCommand`
    又会把同一条 `State` 送到本地客户端。payload 里的 `result` 是同一张表，
    于是玩家看到两遍（本轮线上"招募操作已完成。"刷了 5 条）。
    客户端只认"序号变了才提示"，任何投递路径重复都不会再刷屏。
]]
local resultSeq = 0

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
    resultSeq = resultSeq + 1
    lastResult[Store.playerKey(player)] = { ok = false, code = tostring(code or "failed"), seq = resultSeq }
    return code
end

function Service.ok(player, code)
    resultSeq = resultSeq + 1
    lastResult[Store.playerKey(player)] = { ok = true, code = tostring(code or "ok"), seq = resultSeq }
    return code
end

-- 契约里记一条"最近发生了什么"，玩家在 UI 上能看到降级原因
local function note(contract, value)
    contract.note = value ~= nil and tostring(value) or nil
end

--[[
    岗位生效时的说明处理。

    成功**不擦掉**上一次的说明：降级原因（"居民化被拒（床位不够）"）必须留在面板上，
    否则 Maintain 每 8 秒一次的 quiet 重下会立刻把它抹掉，玩家永远看不到为什么。
    只有一次性的 `pending`（"正在就位"）在落位后要清掉 —— 它同时是补派的触发条件。
]]
local function settle(contract, degraded)
    if degraded ~= nil then
        note(contract, degraded)
    elseif contract.note == "pending" then
        note(contract, nil)
    end
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

    返回 `ok, code, degraded`：
      * ok       —— 岗位最终生效了（哪怕是被降级后的"跟随"）
      * code     —— "follow" / "guard" / "resident" / "degraded:<原因>" / "pending" …
      * degraded —— 降级原因（没降级就是 nil）；调用方把它拼进给玩家的结果码，
                    这样提示里能直接说清楚"为什么不是居民"

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
        if not Jimmy.available() then
            degraded = "no_jeem"
        else
            --[[
                幂等红线 —— 先读 Jeem 的**权威**居民状态，再决定要不要发起收编。

                为什么必须先读：客户端右下角「应用岗位」发的就是"当前岗位"
                （`mode = pendingMode or contract.mode`），所以"对已经是居民的人再点一次居民"
                是**必然会被走到**的路径。旧代码直接调 `R.recruit`，Jeem 对已经住进来的人
                返回 `nil, "resident"`（Server.lua:577），我们把它当失败处理、
                把契约降级成"跟随"并写上 `resident:resident` 的说明 ——
                玩家看到的就是「居民化被拒（resident（上游返回）），已降级为跟随」，
                而人一直好好地当着队友（本轮线上 bug）。
            ]]
            local entry = Jimmy.residentEntry(record)
            if entry ~= nil and Jimmy.canManage(player, entry.baseId) then
                contract.baseId = entry.baseId
                note(contract, nil)
                return true, "resident"
            end

            local count, why, joined, baseId = Jimmy.recruit(player, uid)
            if count ~= nil then
                contract.baseId = baseId
                note(contract, nil)
                -- R.recruit 收编的是整支小队：被一起带进来的成员也改过来
                Service.adoptJoined(player, joined, baseId)
                return true, "resident"
            end

            if tostring(why) == "resident" then
                -- 检查与调用之间他成了居民（同小队一起入住 / Jeem 自己的右键「邀请入住」）
                local fresh = Jimmy.residentEntry(Alife.record(uid))
                if fresh ~= nil and Jimmy.canManage(player, fresh.baseId) then
                    contract.baseId = fresh.baseId
                    note(contract, nil)
                    return true, "resident"
                end
                degraded = "resident:not_yours"        -- 是**别人**的居民：如实说不归你管
            else
                degraded = "resident:" .. tostring(why)
            end
            -- 降级路径必须留痕：沙盒 DebugLog 默认关着，这里用 always
            Config.always("resident conversion refused for " .. tostring(uid) .. ": "
                .. tostring(why) .. " (" .. Jimmy.explain(why) .. "), falling back to follow")
        end
        wanted = Config.MODE_FOLLOW
        contract.mode = wanted
    end

    if wanted == Config.MODE_GUARD then
        local anchor = Alife.position(player) or record.worldPosition
        contract.anchor = anchor
        local done, why = Alife.orderHold(uid, anchor, quiet)
        if done then
            settle(contract, degraded)
            return true, degraded and ("degraded:" .. degraded) or "guard", degraded
        end
        degraded = (degraded ~= nil and (degraded .. "/") or "") .. "guard:" .. tostring(why)
        wanted = Config.MODE_FOLLOW                          -- hold 被拒也退回跟随
        contract.mode = wanted
    end

    local done, why = Alife.orderFollow(player, uid, quiet)
    if done then
        settle(contract, degraded)
        return true, degraded and ("degraded:" .. degraded) or "follow", degraded
    end
    note(contract, degraded ~= nil and (degraded .. "/follow:" .. tostring(why)) or ("follow:" .. tostring(why)))
    return false, tostring(why)
end

--[[
    `R.recruit` 收编的是整支小队（A-Life 的 crew），所以一次「转居民」可能把
    我们已经雇下、也在这支小队里的**其他**契约一起带进基地。

    这些契约必须跟着改成"居民"：否则名册上那些行会一直写着"跟随"，
    玩家再点一次居民还会被 Jeem 以 `resident`（他已经是居民了）拒掉 —— 与主 bug 同一表象。
]]
function Service.adoptJoined(player, joined, baseId)
    if type(joined) ~= "table" or #joined == 0 then return 0 end
    local node = Store.node(player, false)
    if node == nil then return 0 end
    local set = {}
    for _, uid in ipairs(joined) do set[tostring(uid)] = true end
    local changed = 0
    for _, contract in ipairs(Contracts.list(node)) do
        if contract.status == "active" and set[tostring(contract.uid)] == true
                and Config.normalizeMode(contract.mode) ~= Config.MODE_RESIDENT then
            contract.mode = Config.MODE_RESIDENT
            contract.baseId = baseId
            note(contract, nil)
            changed = changed + 1
            Config.always("contract " .. tostring(contract.uid)
                .. " came in with the same crew invite; mode corrected to resident")
        end
    end
    return changed
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

--[[
    签约那一刻就把「玩家 ↔ 该 NPC 阵营/小队」的 Jeem 声望垫到同盟（沙盒 `MakeAllied`，默认开）。

    为什么放在签约而不是"转居民"那一步：
      * Jeem 自己的右键菜单「邀请入住」和我们面板的「居民」模式检查的是**同一个**
        `R.isAlly`（`Residents/Server.lua:581`）—— 只在转居民时垫，等于让玩家先被拒一次，
        而且先用 follow 雇下的人之后永远转不成队友；
      * 沙盒选项 `MakeAllied` 的文档写的就是"签约后把声望垫到同盟档"。

    失败只记日志（拿不到 key / Jeem 没装 / 选项关掉），绝不影响雇佣本身。
]]
function Service.markAllied(player, record)
    if record == nil then return false end
    local ok, why = Jimmy.makeAllied(player, record)
    if ok ~= true and Config.verbose() then
        Config.log("alliance pad skipped: " .. tostring(why))
    end
    return ok == true
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

    --[[
        他已经是 Jeem 的居民了：收编他没有任何意义（他本来就是你的人），
        而且这正是不该收钱的情形 —— 付费之后玩家只会拿到一份写着"跟随"的契约，
        再点「居民」还会被 Jeem 以 `resident` 拒掉。
        候选名单本来就会跳过 `memory.jimmyResident`（Alife.candidates），
        这里是"按 uid 直接雇"（老客户端 / 别处传来的 uid）的第二道闸。
    ]]
    if Jimmy.available() and Jimmy.residentEntry(record) ~= nil then
        return Service.fail(player, "already_resident")
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
    Service.markAllied(player, record)
    local applied, appliedWhy, degraded = Service.applyMode(player, contract, contract.mode)
    Store.transmit()
    --[[
        降级要**说清楚**：把钱收下了却只给到"跟随"时，提示里必须带上原因，
        否则玩家只能看到一句"招募操作已完成"，然后自己去猜（本轮线上 bug 的表象之一）。
    ]]
    Service.ok(player, applied and (degraded ~= nil and ("hired_degraded:" .. degraded) or "hired")
        or ("hired_degraded:" .. tostring(appliedWhy)))
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
    Service.markAllied(player, record)
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

    --[[
        要不要退出居民系统，看的是**权威状态**（`memory.jimmyResident`）而不是我们缓存的
        `contract.mode`：缓存一旦落后于事实（同小队收编、Jeem 自己的右键邀请），
        按缓存判断就会漏掉「他其实还住在基地里」这一步，人于是永远卡在居民系统里。
    ]]
    local wanted = Config.normalizeMode(mode)
    local entry = Jimmy.available() and Jimmy.residentEntry(Alife.record(uid)) or nil
    if entry ~= nil and wanted ~= Config.MODE_RESIDENT then
        local done, why = Jimmy.leaveOne(player, uid)
        if done ~= true and tostring(why) == "busy" then
            -- 他正在战斗/执行任务：Jeem 的 free() 拒绝改记录。此时改岗位只会造成两边不一致
            return Service.fail(player, "leave_busy")
        end
        if done ~= true then
            Config.always("leaveOne refused for " .. tostring(uid) .. " (" .. tostring(why)
                .. "); he may still be a Jeem resident")
        end
    end

    contract.baseId = wanted == Config.MODE_RESIDENT and contract.baseId or nil
    local applied, appliedWhy, degraded = Service.applyMode(player, contract, wanted)
    Store.transmit()
    Service.ok(player, applied and (degraded ~= nil and ("mode_degraded:" .. degraded) or "mode")
        or ("mode_degraded:" .. tostring(appliedWhy)))
    return Service.push(player, Service.state(player))
end

-- 解雇（清岗位 + 从名册删除；签约金不退，工资结算到当天）
function Service.dismiss(player, uid)
    if not Config.enabled() then return Service.fail(player, "disabled") end
    local node = Store.node(player, true)
    local contract = Contracts.get(node, uid)
    if contract == nil then return Service.fail(player, "not_found") end

    --[[
        同样按**权威状态**判断要不要退居民系统：契约上写着"跟随"但他其实住在基地里时，
        直接删契约会留下一个"住在你基地、却不在你名册上"的人（旧代码只 log 不拦，查不出来）。
        Jeem 的 free() 在战斗中/任务中会拒绝改记录（`busy`）——那种情况必须如实
        告诉玩家"稍后再试"，而不是删掉契约假装已经解约。
    ]]
    local entry = Jimmy.available() and Jimmy.residentEntry(Alife.record(uid)) or nil
    if entry ~= nil then
        local done, why = Jimmy.leaveOne(player, uid)
        if done ~= true and tostring(why) == "busy" then
            return Service.fail(player, "leave_busy")
        end
        if done ~= true then
            Config.always("leaveOne refused on dismiss for " .. tostring(uid) .. " (" .. tostring(why)
                .. "); he may still be a Jeem resident")
        end
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
