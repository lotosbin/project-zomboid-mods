--[[
    Bin2NPCExtension :: Alife（server，A-Life 适配层）

    这一层是**唯一**碰 ProjectALife 的地方，全部用"存在性探测 + pcall + 缺失即降级"的写法。
    没有一处 monkey patch：只读公开表、只调公开/半公开函数。
    稳定性评级与证据见 docs/research/jeem-recruit-api.md §2/§9。
]]

require "Bin2NPCExtension/Config"

local Config = Bin2NPCExtension

local Alife = {}
Config.Alife = Alife

local function api() return Config.alife() end

function Alife.available()
    return api() ~= nil
end

local function registry()
    local alife = api()
    return alife and alife.ActorRegistry or nil
end

local function watchdog()
    local alife = api()
    return alife and alife.Watchdog or nil
end

local function shellAdapter()
    local alife = api()
    return alife and alife.ShellAdapter or nil
end

-- 读一条 actor 记录（深拷贝；调用方拿到的改动不会影响 A-Life）
function Alife.record(uid)
    local reg = registry()
    if reg == nil or type(reg.read) ~= "function" or type(uid) ~= "string" then return nil end
    local ok, record = pcall(reg.read, uid)
    if not ok or type(record) ~= "table" then return nil end
    return record
end

-- 取某个 actor 当前绑定的 shell（IsoZombie），没有活动实体时返回 nil
function Alife.shell(uid)
    local wd = watchdog()
    if wd == nil or type(wd.bindings) ~= "table" then return nil end
    local binding = wd.bindings[uid]
    if type(binding) ~= "table" or binding.shell == nil then return nil end
    if type(wd.matches) == "function" then
        local ok, matches = pcall(wd.matches, binding)
        if not ok or matches ~= true then return nil end
    end
    return binding.shell
end

-- shell 上的 A-Life 身份（给"玩家选中了哪个 NPC"这类反查用）
function Alife.shellUid(shell)
    if shell == nil then return nil end
    local adapter = shellAdapter()
    if adapter ~= nil and type(adapter.shellIdentity) == "function" then
        local ok, uid = pcall(adapter.shellIdentity, shell)
        if ok and type(uid) == "string" and uid ~= "" then return uid end
    end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID
    end
    return nil
end

-- 坐标：shell 优先，其次记录里的 worldPosition，最后（对玩家）用对象自身的方法
function Alife.position(target)
    if target == nil then return nil end
    local adapter = shellAdapter()
    if adapter ~= nil and type(adapter.shellPosition) == "function" then
        local ok, position = pcall(adapter.shellPosition, target)
        if ok and type(position) == "table" and tonumber(position.x) ~= nil then return position end
    end
    local ok, x, y, z = pcall(function()
        return target:getX(), target:getY(), target:getZ()
    end)
    if ok and tonumber(x) ~= nil then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) or 0 }
    end
    return nil
end

-- actor 的位置：shell 优先（在跑的实体），否则退回存档里的 worldPosition
function Alife.actorPosition(uid, record)
    local shell = Alife.shell(uid)
    if shell ~= nil then
        local live = Alife.position(shell)
        if live ~= nil then return live end
    end
    record = record or Alife.record(uid)
    local stored = record and record.worldPosition or nil
    if type(stored) == "table" and tonumber(stored.x) ~= nil then
        return { x = tonumber(stored.x), y = tonumber(stored.y), z = tonumber(stored.z) or 0 }
    end
    return nil
end

function Alife.distance(first, second)
    if first == nil or second == nil then return nil end
    local dx = (tonumber(first.x) or 0) - (tonumber(second.x) or 0)
    local dy = (tonumber(first.y) or 0) - (tonumber(second.y) or 0)
    local dz = (tonumber(first.z) or 0) - (tonumber(second.z) or 0)
    if dz ~= 0 then return math.sqrt(dx * dx + dy * dy + dz * dz) end
    return math.sqrt(dx * dx + dy * dy)
end

--[[
    显示名。

    三层回退：Jeem 的 nameOf（最懂 A-Life 的 memory 字段） → Catalog 档案名 → profileId。
    Jeem 不在时我们只读 Catalog，绝不去复制 A-Life 的 memory 私有键。
]]
function Alife.name(record)
    if type(record) ~= "table" then return "?" end
    local jeem = Config.jeem()
    if jeem ~= nil and type(jeem.nameOf) == "function" then
        local ok, name = pcall(jeem.nameOf, record, nil)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local alife = api()
    local catalog = alife and alife.Catalog or nil
    if catalog ~= nil and type(catalog.npc) == "function" and type(record.profileId) == "string" then
        local ok, npc = pcall(catalog.npc, record.profileId)
        if ok and type(npc) == "table" then
            local general = npc.general
            if type(general) == "table" and type(general.name) == "string" and general.name ~= "" then
                return general.name
            end
        end
    end
    return tostring(record.profileId or record.uid or "?")
end

-- NPC 对玩家的基线态度（"hostile" 表示上来就打你）
function Alife.stance(record, player)
    local alife = api()
    local relations = alife and alife.Relations or nil
    if relations == nil or type(relations.baselineStance) ~= "function" then return nil end
    local ok, word = pcall(relations.baselineStance, record, player)
    if ok and type(word) == "string" then return word end
    return nil
end

function Alife.isHostile(record, player)
    return Alife.stance(record, player) == "hostile"
end

--[[
    附近可招募的 NPC。

    遍历 Watchdog.bindings（只有"真的有实体在场"的 actor 才会在里面），
    逐一过滤：生命周期、距离、已被占用、已是 Jeem 居民/驻军/商人。
    返回的是**纯数据**，可以直接丢给客户端渲染。
]]
function Alife.candidates(player, radius, isTaken)
    local rows = {}
    local wd = watchdog()
    local reg = registry()
    if wd == nil or type(wd.bindings) ~= "table" or reg == nil then return rows end
    local origin = Alife.position(player)
    if origin == nil then return rows end
    local limit = math.max(1, tonumber(radius) or 6)

    for uid, binding in pairs(wd.bindings) do
        local record = Alife.record(uid)
        local shell = Alife.shell(uid)
        if record ~= nil and shell ~= nil and record.lifecycle == "active" then
            local memory = type(record.memory) == "table" and record.memory or {}
            local skip = memory.outpostId ~= nil          -- 前哨驻军：Jeem/前哨导演在管
                or memory.jimmyResident ~= nil            -- 已经是 Jeem 居民
                or memory.jimmyTrader ~= nil              -- 来访商人
                or (type(isTaken) == "function" and isTaken(uid) == true)
            if not skip then
                local position = Alife.position(shell)
                local distance = Alife.distance(origin, position)
                if distance ~= nil and distance <= limit then
                    local hostile = Alife.isHostile(record, player)
                    if not hostile or Config.allowHostile() then
                        rows[#rows + 1] = {
                            uid = uid,
                            name = Alife.name(record),
                            factionId = tostring(record.factionId or ""),
                            profileId = tostring(record.profileId or ""),
                            distance = math.floor(distance * 10 + 0.5) / 10,
                            hostile = hostile,
                        }
                    end
                end
            end
        end
    end

    table.sort(rows, function(left, right)
        local a, b = tonumber(left.distance) or 0, tonumber(right.distance) or 0
        if a ~= b then return a < b end
        return tostring(left.uid) < tostring(right.uid)
    end)
    return rows
end

--[[
    从 Catalog 里挑一个"对玩家友好"的阵营 + 档案。

    沿用本仓库已验证过的策略（bin2_ProjectALifeNPCs_extensions 的 Pick.lua）：
    1) 沙盒显式指定（我们没有这两个选项，保留给未来）→ 跳过；
    2) Catalog 里 relations.player 为 friendly / neutral 的阵营；
    3) 任意有档案的阵营（保底）。
    友好性最终由 memory.spawnStance = "friendly" 保证，这里只是让外观/装备像回事。
]]
local function randomProfileOf(loaded, factionId)
    local order = loaded and loaded.npcOrder or nil
    if type(order) ~= "table" then return nil end
    local pool = {}
    for _, npc in ipairs(order) do
        local general = type(npc) == "table" and npc.general or nil
        if type(npc) == "table" and type(npc.id) == "string"
                and type(general) == "table" and general.faction == factionId then
            pool[#pool + 1] = npc.id
        end
    end
    if #pool == 0 then return nil end
    local index = 1
    if #pool > 1 and type(ZombRand) == "function" then index = ZombRand(#pool) + 1 end
    if index < 1 or index > #pool then index = 1 end
    return pool[index]
end

local function playerStanceOf(faction)
    if type(faction) ~= "table" then return nil end
    local relations = faction.relations
    if type(relations) == "table" and type(relations.player) == "string" then
        return string.lower(relations.player)
    end
    return nil
end

function Alife.pickFactionProfile()
    local alife = api()
    local catalog = alife and alife.Catalog or nil
    if catalog == nil or type(catalog.faction) ~= "function" or type(catalog.npc) ~= "function" then
        return nil, nil, "catalog_unavailable"
    end
    local ok, loaded = pcall(function() return catalog.current end)
    if not ok or type(loaded) ~= "table" or type(loaded.factionOrder) ~= "table" then
        return nil, nil, "catalog_not_loaded"
    end
    local fallback
    for _, faction in ipairs(loaded.factionOrder) do
        local id = type(faction) == "table" and faction.id or nil
        if type(id) == "string" then
            local profileId = randomProfileOf(loaded, id)
            if profileId ~= nil then
                local stance = playerStanceOf(faction)
                if stance == "friendly" or stance == "neutral" then
                    return id, profileId, "friendly:" .. tostring(stance)
                end
                if fallback == nil then fallback = { id, profileId } end
            end
        end
    end
    if fallback ~= nil then return fallback[1], fallback[2], "fallback" end
    return nil, nil, "no_usable_faction"
end

--[[
    给玩家身边找一个真的已加载的方块（A-Life 的 createZombieShell 直接用 worldPosition）。

    第一个候选按 index 分散角度，避免一次雇多人时叠在一起。
]]
function Alife.freeSquareNear(player, distance, index)
    local origin = Alife.position(player)
    if origin == nil then return nil, "no_player_position" end
    if type(getCell) ~= "function" then return nil, "no_cell" end
    local cell = getCell()
    if cell == nil then return nil, "no_cell" end
    local gap = math.max(1, tonumber(distance) or 2)
    local angle = ((tonumber(index) or 1) - 1) * (math.pi / 3)
    local offsets = {
        { math.cos(angle) * gap, math.sin(angle) * gap },
        { gap, 0 }, { -gap, 0 }, { 0, gap }, { 0, -gap },
    }
    for _, offset in ipairs(offsets) do
        local x = math.floor(origin.x + offset[1])
        local y = math.floor(origin.y + offset[2])
        local z = math.floor(origin.z or 0)
        local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
        if ok and square ~= nil then
            return { x = x + 0.5, y = y + 0.5, z = z }
        end
    end
    return nil, "no_loaded_square_near_player"
end

--[[
    造一名友好 NPC。返回 uid 或 nil, why。

    幂等：operationId 由调用方保证唯一（我们把它绑到契约 id 上），
    同一个 operationId + fingerprint 重复调用会返回同一条记录，绝不会翻倍。
]]
function Alife.spawn(spec)
    local alife = api()
    if alife == nil then return nil, "no_alife" end
    local reg, spawn = alife.ActorRegistry, alife.SpawnService
    if reg == nil or type(reg.create) ~= "function" then return nil, "actor_registry_unavailable" end
    if spawn == nil or type(spawn.request) ~= "function" then return nil, "spawn_service_unavailable" end

    local position = spec.worldPosition
    if type(position) ~= "table" or tonumber(position.x) == nil then return nil, "no_position" end
    local fingerprint = Config.MODULE .. ":v1"

    local memory = {
        spawnStance = "friendly",                        -- Relations.baselineStance 的第一优先级
        persistent = true,                               -- 免疫 Population 的 dormant_ttl 回收
        admin = { persistent = true, bin2npc = true },   -- 免疫 SpawnService.dehydrate
        moduleOverrides = { orders = "on" },             -- 保证 orders 模块开（跟随指令才有人听）
        home = { x = position.x, y = position.y, z = position.z },
        groupId = "bin2npc:" .. tostring(spec.operationId or ""),
    }

    local actor, createError = reg.create({
        operationId = spec.operationId .. ":create",
        fingerprint = fingerprint,
        profileId = spec.profileId,
        factionId = spec.factionId,
        worldPosition = { x = position.x, y = position.y, z = position.z },
        activity = "idle",
        intent = "hold",
        memory = memory,
    })
    if actor == nil then return nil, tostring(createError) end

    local request, requestError = spawn.request(actor.uid, spec.operationId .. ":spawn",
        fingerprint .. ":spawn", 2500)
    if request == nil then
        -- 回滚：只有还处于 dormant 才能 remove（Registry.remove 的前置条件）
        local current = Alife.record(actor.uid)
        if current ~= nil and current.lifecycle == "dormant" then
            pcall(reg.remove, current.uid, current.revision, "bin2npc_rejected")
        end
        return nil, tostring(requestError)
    end

    Config.log(string.format("spawned %s (faction=%s profile=%s)", tostring(actor.uid),
        tostring(spec.factionId), tostring(spec.profileId)))
    return actor.uid
end

-- 下一条原生跟随命令；只在 lifecycle=="active" 时才会被接受。
-- quiet=true 用于"周期性重下"：不重放 follow 动画与 ORDER_ACK 语音（会话里第一次才放）。
function Alife.orderFollow(player, uid, quiet)
    local alife = api()
    local decisions = alife and alife.DecisionLoop or nil
    if decisions == nil or type(decisions.setOrder) ~= "function" then return false, "decision_loop_unavailable" end
    local record = Alife.record(uid)
    if record == nil or record.lifecycle ~= "active" then return false, "actor_not_active" end
    local ok, accepted, why = pcall(decisions.setOrder, uid, record.generation, {
        kind = "follow", player = player, source = "player", quiet = quiet == true,
    })
    if not ok then return false, tostring(accepted) end
    if accepted ~= true then return false, tostring(why or "order_refused") end
    return true
end

-- 原地站岗（hold 需要一个 anchor）
function Alife.orderHold(uid, anchor, quiet)
    local alife = api()
    local decisions = alife and alife.DecisionLoop or nil
    if decisions == nil or type(decisions.setOrder) ~= "function" then return false, "decision_loop_unavailable" end
    local record = Alife.record(uid)
    if record == nil or record.lifecycle ~= "active" then return false, "actor_not_active" end
    local point = anchor or record.worldPosition
    if type(point) ~= "table" or tonumber(point.x) == nil then return false, "order_anchor_missing" end
    local ok, accepted, why = pcall(decisions.setOrder, uid, record.generation, {
        kind = "hold", anchor = { x = tonumber(point.x), y = tonumber(point.y), z = tonumber(point.z) or 0 },
        source = "player", quiet = quiet == true,
    })
    if not ok then return false, tostring(accepted) end
    if accepted ~= true then return false, tostring(why or "order_refused") end
    return true
end

-- 清掉我们下的命令（解雇/改岗位时用）
function Alife.clearOrder(uid)
    local alife = api()
    local decisions = alife and alife.DecisionLoop or nil
    if decisions == nil then return false end
    local record = Alife.record(uid)
    if record ~= nil and type(decisions.forget) == "function" then
        local ok = pcall(decisions.forget, uid, record.generation, "bin2npc_released")
        if ok then return true end
    end
    if type(decisions.orders) == "table" then
        decisions.orders[uid] = nil
        if type(decisions.states) == "table" then
            decisions.states[uid] = { kind = "idle", intent = "order_released", cooldownUntilMs = 0 }
        end
        return true
    end
    return false
end

--[[
    给被雇佣的 NPC 打"别回收我"的标记。

    必须同时写 memory.persistent 与 memory.admin.persistent —— 两者管的是不同函数
    （dormant TTL 回收 vs SpawnService.dehydrate）。见报告 §2.4。
]]
function Alife.protect(uid)
    local alife = api()
    local reg = alife and alife.ActorRegistry or nil
    if reg == nil or type(reg.update) ~= "function" then return false, "registry_unavailable" end
    local record = Alife.record(uid)
    if record == nil then return false, "not_found" end
    if record.memory ~= nil and record.memory.persistent == true
            and type(record.memory.admin) == "table" and record.memory.admin.persistent == true then
        return true                                    -- 已经打过，不做无用的 update（会顶掉 revision）
    end
    local ok, updated, why = pcall(reg.update, uid, record.revision, function(candidate)
        candidate.memory = type(candidate.memory) == "table" and candidate.memory or {}
        candidate.memory.persistent = true
        candidate.memory.admin = type(candidate.memory.admin) == "table" and candidate.memory.admin or {}
        candidate.memory.admin.persistent = true
        candidate.memory.admin.bin2npc = true
        candidate.memory.moduleOverrides = type(candidate.memory.moduleOverrides) == "table"
            and candidate.memory.moduleOverrides or {}
        candidate.memory.moduleOverrides.orders = "on"
    end)
    if not ok then return false, tostring(updated) end
    if updated == nil then return false, tostring(why) end
    return true
end

-- 让一个 actor 退场（失败时回滚已造出来的人）
function Alife.retire(uid, reason)
    local alife = api()
    local spawn = alife and alife.SpawnService or nil
    if spawn == nil then return false end
    if type(spawn.retire) == "function" then
        local ok = pcall(spawn.retire, uid, reason or "bin2npc_release")
        if ok then return true end
    end
    local reg = alife and alife.ActorRegistry or nil
    local record = Alife.record(uid)
    if reg ~= nil and record ~= nil and record.lifecycle == "dormant" then
        local ok = pcall(reg.remove, uid, record.revision, reason or "bin2npc_release")
        return ok
    end
    return false
end

return Alife
