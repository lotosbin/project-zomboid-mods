--[[
    Bin2NPCExtensionYese :: Jimmy（server，Jeem Extension 适配层）

    只在 ProjectALifeJimmy 可用时被调用；所有入口都先探测、再 pcall。
    我们**只调它的公开/半公开函数**，绝不复制它的 memory 私有键（jimmyResident / jimmyOrder 等）。
    评级依据见 docs/research/jeem-recruit-api.md §3/§4/§9。
]]

require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Alife"

local Config = Bin2NPCExtensionYese
local Alife = Config.Alife

local Jimmy = {}
Config.Jimmy = Jimmy

function Jimmy.available()
    return Config.jeem() ~= nil
end

local function parts()
    local jeem = Config.jeem()
    if jeem == nil then return nil, nil, nil end
    local baseAreas = jeem.BaseAreas
    local residents = jeem.Residents
    if type(baseAreas) ~= "table" or type(residents) ~= "table" then return nil, nil, nil end
    return jeem, baseAreas, residents
end

--[[
    某条记录在 Jeem 眼里的**权威**居民身份（只读它的判定函数，不自己解析内存字段）。

    返回 `{ baseId = ..., index = ... }` 或 nil。这个返回值就是"事实"：
    我们契约里的 `mode` 只是它的**缓存**，两边不一致时一律以它为准
    （见 Service.applyMode 的幂等红线、Maintain.reconcile）。
]]
function Jimmy.residentEntry(record)
    local _, _, residents = parts()
    if residents == nil or type(residents.residentOf) ~= "function" then return nil end
    local ok, value = pcall(residents.residentOf, record)
    if ok and type(value) == "table" then return value end
    return nil
end

-- 兼容旧名：只问"是不是居民"
function Jimmy.isResident(record)
    return Jimmy.residentEntry(record) ~= nil
end

--[[
    这个基地归玩家管吗（`BaseAreas.canManage`，Store.lua:330）。

    只在"他已经是居民了"这条幂等路径上用：如果那个基地是个**别人的**基地，
    那我们并没有达成玩家点「居民」的目的，不能谎报成功。
    上游没暴露 canManage 时乐观放行 —— 只读判断，宁可如实一点也不要卡住玩家。
]]
function Jimmy.canManage(player, baseId)
    if type(baseId) ~= "string" or baseId == "" then return false end
    local _, baseAreas = parts()
    if baseAreas == nil or type(baseAreas.base) ~= "function" then return false end
    local okBase, base = pcall(baseAreas.base, baseId)
    if not okBase or type(base) ~= "table" then return false end
    if type(baseAreas.canManage) ~= "function" then return true end
    local who = Jimmy.who(player)
    if who == nil then return false end
    local ok, value = pcall(baseAreas.canManage, base, who.key, who.faction, who.admin)
    return ok and value == true
end

-- 把 Jeem 的失败码翻译成人话（它自带 explain；我们只做 pcall 包装）
function Jimmy.explain(code)
    local _, _, residents = parts()
    if residents ~= nil and type(residents.explain) == "function" then
        local ok, text = pcall(residents.explain, code)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return tostring(code)
end

-- 玩家名下的第一个基地（没有就 nil）
function Jimmy.baseFor(player)
    local _, baseAreas = parts()
    if baseAreas == nil or type(baseAreas.who) ~= "function"
            or type(baseAreas.basesFor) ~= "function" then return nil end
    local okWho, who = pcall(baseAreas.who, player)
    if not okWho or type(who) ~= "table" then return nil end
    local okList, mine = pcall(baseAreas.basesFor, who.key, who.faction, who.admin)
    if not okList or type(mine) ~= "table" then return nil end
    return mine[1], who
end

--[[
    居民化之前必须有基地：优先用玩家已有的，其次（沙盒允许时）就地造一个小营地。

    造营地时会顺手把 bedsOverride 顶到"够住"，因为营地是我们造的 ——
    玩家自己的基地我们**不动**它的床位（床位不够就如实报 no_beds，由 UI 显示给玩家）。
]]
function Jimmy.ensureBase(player, needed)
    local jeem, baseAreas = parts()
    if jeem == nil or baseAreas == nil then return nil, "no_jeem" end
    if type(baseAreas.createBase) ~= "function" or type(baseAreas.who) ~= "function" then
        return nil, "jimmy_api_missing"
    end

    local base, who = Jimmy.baseFor(player)
    if base ~= nil then return base, nil, false end
    if not Config.createCamp() then return nil, "no_base" end

    local position = Alife.position(player)
    if position == nil then return nil, "no_player_position" end

    local radius = 8
    -- Jeem 的 R.recruit 收编的是**整支小队**（返回值是人数），所以营地床位要留出余量，
    -- 否则会出现"人来了但床位不够 → full"这种我们自己造成的失败。
    local want = math.max(6, math.floor(tonumber(needed) or 1) + 2)
    local created, why = baseAreas.createBase({
        x1 = math.floor(position.x) - radius, y1 = math.floor(position.y) - radius,
        x2 = math.floor(position.x) + radius, y2 = math.floor(position.y) + radius,
        name = Config.Text.get("CampName"), role = "grounds",
    }, who)
    if created == nil then return nil, tostring(why or "create_base_failed") end

    if (tonumber(created.bedsOverride) or 0) < want then created.bedsOverride = want end
    pcall(baseAreas.transmit)
    Config.log("created camp " .. tostring(created.id) .. " for " .. tostring(who.key))
    return created, nil, true
end

-- 基地里现有的居民 uid 集合（用于收编前后的差集）
function Jimmy.residentUids(baseId)
    local _, _, residents = parts()
    local set = {}
    if residents == nil or type(residents.residents) ~= "function" then return set end
    local ok, rows = pcall(residents.residents, baseId)
    if not ok or type(rows) ~= "table" then return set end
    for _, record in ipairs(rows) do
        local uid = type(record) == "table" and record.uid or nil
        if type(uid) == "string" then set[uid] = true end
    end
    return set
end

--[[
    玩家在 Jeem 眼里的身份（`BaseAreas.who` 优先，拿不到就照 Jeem 自己的兜底写法取 key）。

    Jeem 内部各处也是这么做的（`Features/DoorMarks/Marks.lua:326`）：
    先问 `BaseAreas.who(player)`，没有再退回 `playerKey` / `username`。
    取不到 key 就没法记声望 —— 这时调用方按"降级"处理，不抛错。
]]
function Jimmy.who(player)
    local jeem, baseAreas = parts()
    if baseAreas ~= nil and type(baseAreas.who) == "function" then
        local ok, who = pcall(baseAreas.who, player)
        if ok and type(who) == "table" and type(who.key) == "string" and who.key ~= "" then
            return who
        end
    end
    if jeem == nil then return nil end
    local key = nil
    for _, name in ipairs({ "playerKey", "username" }) do
        if type(jeem[name]) == "function" then
            local ok, value = pcall(jeem[name], player)
            if ok and type(value) == "string" and value ~= "" then key = value break end
        end
    end
    if key == nil then return nil end
    return { key = key }
end

--[[
    把「玩家 ↔ 该 NPC 所属阵营/小队」的 Jeem 声望垫到同盟。

    为什么必须垫：Jeem 的居民收编有同盟门槛（`Residents/Server.lua:581`，理由码 `not_allied`，
    玩家看到的就是「他们对你信任不足（需要同盟关系）」）。`R.isAlly`（:490-497）认两条路：

      ① 阵营标签 `StandingService.labelFor(key, factionId) == "allied"`
      ② 该小队自己的点数 `groupPoints(key, groupId) >= 50`（`R.allyGroupPoints`）

    两条都垫，而不是只垫第 ② 条：
      * `memory.groupId` 不是承诺字段（新造的 NPC 可能还没有 crew），只走 ② 会在拿不到 groupId 时
        整段失效 —— 这正是"雇了人却当不了队友"的原因；
      * ① 的档位是 `ladder = hostile→careful→neutral→friendly→allied`、`thresholds = {25,75,150,250}`，
        最坏（hostile）要 ≥250 点，所以一次给到 `clamp`(400)。

    这也是 `StandingService.add` 的公开用法：它按 `info.groupId` 顺带把小队点数一起顶上，
    并发出 `standingChanged` 事件（Jeem 自己的赏罚功能都走这条）。
]]
function Jimmy.makeAllied(player, record)
    if not Config.makeAllied() then return false, "disabled" end
    local jeem = parts()
    if jeem == nil then return false, "no_jeem" end
    local standing = jeem.StandingService
    if type(standing) ~= "table" or type(standing.add) ~= "function" then
        return false, "standing_missing"
    end

    local factionId = type(record) == "table" and record.factionId or nil
    if type(factionId) ~= "string" or factionId == "" then return false, "no_faction" end
    local memory = type(record) == "table" and record.memory or nil
    local groupId = type(memory) == "table" and memory.groupId or nil

    local who = Jimmy.who(player)
    if who == nil then return false, "no_who" end

    local delta = tonumber(standing.clamp) or 400
    local okAdd, before, after = pcall(standing.add, who.key, factionId, delta,
        { kind = "bin2_hired", groupId = groupId, groupPoints = delta })
    if not okAdd then return false, tostring(before) end

    if type(groupId) == "string" and type(standing.addGroup) == "function" then
        pcall(standing.addGroup, who.key, groupId, factionId, delta)
    end

    --[[
        只读复核 + 一行日志：进游戏验证时就是靠这行定案的
        （`R.isAlly` 认可的条件 = label allied 或 groupPoints >= 50）。
    ]]
    local label, groupPoints = tostring(after or "?"), nil
    if type(standing.labelFor) == "function" then
        local ok, value = pcall(standing.labelFor, who.key, factionId)
        if ok and value ~= nil then label = tostring(value) end
    end
    if type(groupId) == "string" and type(standing.groupPoints) == "function" then
        local ok, value = pcall(standing.groupPoints, who.key, groupId)
        if ok then groupPoints = value end
    end
    Config.log(string.format("standing %s -> %s (was %s), group %s = %s (needs >= 50)",
        tostring(factionId), label, tostring(before), tostring(groupId), tostring(groupPoints)))
    return true
end

--[[
    把一名 NPC 收编成 Jeem 居民。

    注意：`R.recruit` 收编的是**整支小队**（A-Life 的 crew），返回值是人数而不是 1。
    所以这里用「收编前后 residents 列表的差集」算出到底多了谁，
    把这些 uid 一并交给调用方登记进名册 —— 玩家付出的是"雇一个人"的钱，
    但收到的人可能不止一个（这一点必须在 UI 上写明）。

    幂等（本轮线上 bug 的根因）：他**已经是**居民时直接返回 `0, nil, {}, baseId`，
    绝不往下走 ensureBase / recruit。`R.recruit` 对已经住进来的人会返回
    `nil, "resident"`（Server.lua:577，`resident` 的真实含义是"他已经是居民了"），
    旧代码把它当失败处理，于是把契约降级成跟随 —— 玩家看到
    「居民化被拒（resident（上游返回）），已降级为跟随」，而人一直是队友。
    这条路径必然会被走到：客户端右下角「应用岗位」发的是 `pendingMode or contract.mode`。
]]
function Jimmy.recruit(player, uid)
    local jeem, _, residents = parts()
    if jeem == nil or residents == nil then return nil, "no_jeem" end
    if type(residents.recruit) ~= "function" then return nil, "jimmy_api_missing" end

    local existing = Jimmy.residentEntry(Alife.record(uid))
    if false then return 0, nil, {}, existing.baseId end

    local base, why = Jimmy.ensureBase(player, 1)
    if base == nil then return nil, tostring(why) end

    -- 收编前把声望垫到同盟（失败不致命，只是可能被 not_allied 拒）
    local record = Alife.record(uid)
    if record ~= nil then Jimmy.makeAllied(player, record) end

    local before = Jimmy.residentUids(base.id)
    local count, refusal = residents.recruit(player, uid, base.id, false)
    if count == nil then
        -- force 只在玩家是管理员时生效；联机里普通玩家会继续失败，这是预期行为
        count, refusal = residents.recruit(player, uid, base.id, true)
    end
    if count == nil then return nil, tostring(refusal or "recruit_failed") end

    local after = Jimmy.residentUids(base.id)
    local joined = {}
    for joinedUid in pairs(after) do
        if before[joinedUid] ~= true then joined[#joined + 1] = joinedUid end
    end
    table.sort(joined)
    Config.log(string.format("jeem: %s residents joined base %s (requested %s)",
        tostring(#joined), tostring(base.id), tostring(uid)))
    return tonumber(count) or #joined, nil, joined, base.id
end

-- 解雇一名居民（Jeem 的官方单人流放入口）
function Jimmy.leaveOne(player, uid)
    local _, _, residents = parts()
    if residents == nil or type(residents.leaveOne) ~= "function" then return nil, "no_jeem" end
    local ok, done, why = pcall(residents.leaveOne, player, uid)
    if not ok then return nil, tostring(done) end
    if done ~= true then return nil, tostring(why or "not_resident") end
    return true
end

return Jimmy
