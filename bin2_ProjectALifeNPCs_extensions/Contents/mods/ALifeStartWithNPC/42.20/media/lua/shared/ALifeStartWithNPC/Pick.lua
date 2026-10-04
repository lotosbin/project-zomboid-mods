--[[
    ALifeStartWithNPC :: Pick
    从 A-Life 的 Catalog 里挑一个"对玩家友好"的阵营 + 档案。

    为什么需要挑：ActorRegistry.create 要求 factionId / profileId 都真实存在于 Catalog，
    否则返回 actor_specification_invalid（ALifeActorRegistry.lua:374-383）。

    友方性由 Grant.lua 写 memory.spawnStance = "friendly" 保证
    （Relations.baselineStance 第一行就读它，命中即返回 friendly, 不走阵营关系表）；
    这里挑阵营只是为了让外观/装备/名字像回事。
]]

ALifeStartWithNPC = ALifeStartWithNPC or {}
local Config = ALifeStartWithNPC
local Pick = {}

local function catalog()
    return ProjectALife and ProjectALife.Catalog
end

local function current()
    local cat = catalog()
    local ok, loaded = pcall(function() return cat and cat.current end)
    if ok and type(loaded) == "table" then return loaded end
    return nil
end

-- 该阵营对玩家的立场（faction.relations.player），兼容几种可能的落点
local function playerStance(faction)
    if type(faction) ~= "table" then return nil end
    local relations = faction.relations
    if type(relations) == "table" and type(relations.player) == "string" then
        return string.lower(relations.player)
    end
    if type(faction.stance) == "table" and type(faction.stance.player) == "string" then
        return string.lower(faction.stance.player)
    end
    return nil
end

-- 从属于 factionId 的档案里随机取一个（避免一次发多个时所有人一模一样）
local function randomProfileOf(factionId)
    local loaded = current()
    if loaded == nil then return nil end
    local order = loaded.npcOrder
    if type(order) ~= "table" then return nil end
    local pool = {}
    for _, npc in ipairs(order) do
        local id = type(npc) == "table" and npc.id or nil
        local general = type(npc) == "table" and npc.general or nil
        if id ~= nil and type(general) == "table" and general.faction == factionId then
            pool[#pool + 1] = id
        end
    end
    if #pool == 0 then return nil end
    local index = 1
    if #pool > 1 and type(ZombRand) == "function" then index = ZombRand(#pool) + 1 end
    if index < 1 or index > #pool then index = 1 end
    return pool[index]
end

-- 是否是一个"像人"的可用档案（有名字即可）
local function usableProfile(npc)
    if type(npc) ~= "table" then return false end
    local general = npc.general
    return type(general) == "table" and general.faction ~= nil
end

--[[
    挑选顺序：
      1. 选项里显式指定的 factionId / profileId（校验存在性，错了就报错并返回 nil）
      2. Catalog 里 stance.player 为 friendly / neutral 的阵营
      3. 任意有档案的阵营（保底，不让功能因为数据而异）
    返回 factionId, profileId, why
]]
function Pick.choose()
    local cat = catalog()
    if type(cat) ~= "table" or type(cat.faction) ~= "function" or type(cat.npc) ~= "function" then
        return nil, nil, "catalog_unavailable"
    end

    local wantFaction = Config.factionId()
    local wantProfile = Config.profileId()

    -- 1) 显式指定
    if wantFaction ~= nil then
        local faction = cat.faction(wantFaction)
        if faction == nil then
            return nil, nil, "faction_not_found:" .. tostring(wantFaction)
        end
        if wantProfile ~= nil then
            local npc = cat.npc(wantProfile)
            if npc == nil or not usableProfile(npc) then
                return nil, nil, "profile_not_found:" .. tostring(wantProfile)
            end
            local general = npc.general
            if general.faction ~= nil and general.faction ~= wantFaction then
                return nil, nil, "profile_faction_mismatch:" .. tostring(wantProfile)
            end
            return wantFaction, wantProfile, "explicit"
        end
        local id = randomProfileOf(wantFaction)
        if id == nil then return nil, nil, "faction_has_no_profiles:" .. tostring(wantFaction) end
        return wantFaction, id, "explicit_faction"
    end

    local loaded = current()
    if loaded == nil or type(loaded.factionOrder) ~= "table" then
        return nil, nil, "catalog_not_loaded"
    end

    -- 2) 优先友好/中立阵营
    local fallback
    for _, faction in ipairs(loaded.factionOrder) do
        local id = type(faction) == "table" and faction.id or nil
        if id ~= nil then
            local profileId = randomProfileOf(id)
            if profileId ~= nil then
                local stance = playerStance(faction)
                if stance == "friendly" or stance == "neutral" then
                    return id, profileId, "friendly:" .. tostring(stance)
                end
                if fallback == nil then fallback = { id, profileId } end
            end
        end
    end

    -- 3) 保底
    if fallback ~= nil then return fallback[1], fallback[2], "fallback" end
    return nil, nil, "no_usable_faction"
end

return Pick
