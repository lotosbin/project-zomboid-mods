--[[
    Bin2NPCExtension :: Jimmy（server，Jeem Extension 适配层）

    只在 ProjectALifeJimmy 可用时被调用；所有入口都先探测、再 pcall。
    我们**只调它的公开/半公开函数**，绝不复制它的 memory 私有键（jimmyResident / jimmyOrder 等）。
    评级依据见 docs/research/jeem-recruit-api.md §3/§4/§9。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Alife"

local Config = Bin2NPCExtension
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

-- 某条记录是不是 Jeem 居民（只读它的判定函数，不自己解析内存字段）
function Jimmy.isResident(record)
    local _, _, residents = parts()
    if residents == nil or type(residents.residentOf) ~= "function" then return false end
    local ok, value = pcall(residents.residentOf, record)
    return ok and value ~= nil
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

-- 把玩家与该 NPC 阵营/小队的声望垫到「同盟」，否则非管理员玩家收编会被 not_allied 拦住
function Jimmy.makeAllied(player, record)
    if not Config.makeAllied() then return false, "disabled" end
    local jeem, baseAreas = parts()
    if jeem == nil then return false, "no_jeem" end
    local standing = jeem.StandingService
    if type(standing) ~= "table" or type(standing.addGroup) ~= "function"
            or type(baseAreas.who) ~= "function" then return false, "standing_missing" end
    local memory = type(record) == "table" and record.memory or nil
    local groupId = type(memory) == "table" and memory.groupId or nil
    local factionId = type(record) == "table" and record.factionId or nil
    if type(groupId) ~= "string" or type(factionId) ~= "string" then return false, "no_group" end
    local okWho, who = pcall(baseAreas.who, player)
    if not okWho or type(who) ~= "table" then return false, "no_who" end
    local points = tonumber(standing.clamp) or 400
    local ok, result = pcall(standing.addGroup, who.key, groupId, factionId, points)
    if not ok then return false, tostring(result) end
    --[[
        只读复核：`R.isAlly` 认两条路 —— 阵营标签为 allied，或**组点数 ≥ 50**（`Residents.allyGroupPoints`）。
        我们走的是组点数那条，但 `addGroup` 的 clamp / poolShare 语义没有正式承诺，
        所以把结果打成一行日志 —— 进游戏验证 T15/M2（非管理员转居民）时就是靠这行定案的。
    ]]
    if type(standing.groupPoints) == "function" then
        local okPoints, value = pcall(standing.groupPoints, who.key, groupId)
        if okPoints then
            Config.log(string.format("standing group %s = %s (needs >= 50 for R.isAlly)",
                tostring(groupId), tostring(value)))
        end
    end
    return true
end

--[[
    把一名 NPC 收编成 Jeem 居民。

    注意：`R.recruit` 收编的是**整支小队**（A-Life 的 crew），返回值是人数而不是 1。
    所以这里用「收编前后 residents 列表的差集」算出到底多了谁，
    把这些 uid 一并交给调用方登记进名册 —— 玩家付出的是"雇一个人"的钱，
    但收到的人可能不止一个（这一点必须在 UI 上写明）。
]]
function Jimmy.recruit(player, uid)
    local jeem, _, residents = parts()
    if jeem == nil or residents == nil then return nil, "no_jeem" end
    if type(residents.recruit) ~= "function" then return nil, "jimmy_api_missing" end

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
