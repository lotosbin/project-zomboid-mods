--[[
    ALifeStartWithNPC :: Grant（仅服务端加载）
    职责：在新角色就绪后，为其生成 1..N 名友好 NPC。

    两段式设计（每段都用经过实测的公开/半公开入口）：
      第一段 · 造人（必须，两条路线共用）
          ProjectALife.ActorRegistry.create(spec)   -- ALifeActorRegistry.lua:374
          ProjectALife.SpawnService.request(...)    -- ALifeSpawnService.lua:136（内部同步 createShell）
        关键：
          * operationId 自带幂等：同 operationId + 同 fingerprint 返回已有记录，绝不会重复造人。
          * memory.spawnStance = "friendly" 是 Relations.baselineStance 的第一优先级来源
            （ALifeRelations.lua:30-39），命中即友好，与阵营关系表无关。
          * 实体出生点 = spec.worldPosition（createZombieShell 精确使用它，ALifeShellAdapter.lua:46）。

      第二段 · 行为（二选一）
          Mode 1（默认）跟随：ProjectALife.DecisionLoop.setOrder(uid, generation,
              { kind = "follow", player = player, source = "player" })   -- ALifeDecisionLoop.lua:1242
              —— 这是 A-Life 原生跟随，不要自建行为模块（orders 模块 priority=10 会抢跑）。
          Mode 2 Jeem 居民：ProjectALifeJimmy.Residents.recruit(player, uid, baseId, true)
              —— Jeem 内部会完成「建阵营副本 + 冻结外观 + 重写 factionId/profileId + retag memory」。
                 居民语义是"守基地"，与跟随互斥，因此成功转居民后不再下 follow 命令。

    失败处理：任何一步失败都只降级、不抛错；造人失败则整个流程放弃并保留重试机会。
]]

require "ALifeStartWithNPC/Config"
require "ALifeStartWithNPC/Pick"

local Config = ALifeStartWithNPC
local Pick = require "ALifeStartWithNPC/Pick"

local Grant = {
    pending = {},        -- uid -> { uid, generation, mode, tries, player }
    pendingCount = 0,    -- 显式计数：Kahlua 没有表遍历用的 next()，用它代替"表是否为空"判断
    running = false,
    -- 注意：这里**故意不放**任何"按玩家对象缓存"的已完成/尝试计数。
    -- 联机里玩家重生可能复用同一个 IsoPlayer 对象，按对象缓存会挡住重新发放；
    -- 所有 per-角色的状态一律存进玩家 modData（见 Config.KEY_*）。
}

-- Kahlua 的限制：没有 next()（Jeem 的 Core.lua:231 专门记录过这个坑："Kahlua has no next()"）。
-- 因此这里既不做 next() 调用，也不靠遍历判空，而是直接维护一个计数。
local function pendingAdd(uid, item)
    if Grant.pending[uid] == nil then Grant.pendingCount = Grant.pendingCount + 1 end
    Grant.pending[uid] = item
end

local function pendingRemove(uid)
    if Grant.pending[uid] ~= nil then
        Grant.pending[uid] = nil
        Grant.pendingCount = Grant.pendingCount - 1
    end
end

-- 简易访问器：表可能不存在（缺依赖时）
local function actors() return ProjectALife and ProjectALife.ActorRegistry end
local function spawner() return ProjectALife and ProjectALife.SpawnService end
local function decisions() return ProjectALife and ProjectALife.DecisionLoop end
local function runtime() return ProjectALife and ProjectALife.Runtime end
local function jimmy() return ProjectALifeJimmy end

local function nowMs()
    local ok, value = pcall(getTimestampMs)
    if ok and value ~= nil then return value end
    -- 不假设 Kahlua 一定暴露 os.time：包一层 pcall，取不到就退化为 0（只影响日志时间戳与超时估算）
    local okTime, seconds = pcall(function() return (os and os.time) and os.time() or nil end)
    if okTime and type(seconds) == "number" then return math.floor(seconds * 1000) end
    return 0
end

-- 玩家坐标（优先用 A-Life 自己的 PlayerLocator，失败再退回 player 方法）
function Grant.playerPosition(player)
    local locator = ProjectALife and ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.position) == "function" then
        local ok, position = pcall(locator.position, player)
        if ok and type(position) == "table" and position.x ~= nil then return position end
    end
    local ok, x, y, z = pcall(function()
        return player:getX(), player:getY(), player:getZ()
    end)
    if not ok or x == nil then return nil end
    return { x = x, y = y, z = z or 0 }
end

-- 找玩家身边一个真的已加载的方块（A-Life 的 square_unloaded 判定同源）
local function freeSquareNear(position, distance, index)
    local cell = getCell()
    if cell == nil then return nil end
    -- 以玩家为中心绕一圈找空位：不同 NPC 用不同角度，避免叠在一起
    local angle = (index - 1) * (math.pi / 3)
    local offsets = {
        { math.cos(angle) * distance, math.sin(angle) * distance },
        { distance, 0 }, { -distance, 0 }, { 0, distance }, { 0, -distance },
    }
    for _, offset in ipairs(offsets) do
        local x = math.floor(position.x + offset[1]) + 0.5
        local y = math.floor(position.y + offset[2]) + 0.5
        local z = math.floor(position.z or 0)
        local ok, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), z) end)
        if ok and square ~= nil then return x, y, z end
    end
    return nil
end

-- 世界是否已就绪：A-Life runtime 启动 + 玩家有方块
function Grant.worldReady(player)
    local rt = runtime()
    if rt == nil or rt.started ~= true then return false, "runtime_not_started" end
    if player == nil or player:isDead() then return false, "player_gone" end
    local square = player:getCurrentSquare()
    if square == nil then return false, "player_square_unloaded" end
    return true
end

--[[
    造一名友好 NPC。返回 actor 记录或 nil, why。
    幂等：同一 opId 重复调用返回同一条记录（A-Life 的 operations 表），所以重进存档不会翻倍。
]]
function Grant.spawnOne(player, index, factionId, profileId, opId)
    local Registry, Spawn = actors(), spawner()
    if Registry == nil or type(Registry.create) ~= "function" then return nil, "actor_registry_unavailable" end
    if Spawn == nil or type(Spawn.request) ~= "function" then return nil, "spawn_service_unavailable" end

    local position = Grant.playerPosition(player)
    if position == nil then return nil, "no_player_position" end
    local x, y, z = freeSquareNear(position, Config.distance(), index)
    if x == nil then return nil, "no_loaded_square_near_player" end

    local fingerprint = Config.MODULE .. ":v1"
    local memory = {
        spawnStance = "friendly",          -- Relations.baselineStance 的第一优先级来源
        persistent = true,                 -- Population.expendable(...) 为 false（ALifePopulation.lua:132）
        admin = { persistent = true },     -- 唯一能挡住 SpawnService.dehydrate 的标记
                                           -- （adminPersistent 读 memory.admin.persistent，ALifeSpawnService.lua:32-36, 308）
        home = { x = x, y = y, z = z },
        groupId = "starter:" .. tostring(opId),
    }

    local actor, createError = Registry.create({
        operationId = opId .. ":create",
        fingerprint = fingerprint,
        profileId = profileId,
        factionId = factionId,
        worldPosition = { x = x, y = y, z = z },
        activity = "idle",
        intent = "hold",
        memory = memory,
    })
    if actor == nil then return nil, tostring(createError) end

    local request, requestError = Spawn.request(actor.uid, opId .. ":spawn", fingerprint .. ":spawn", 2500)
    if request == nil then
        -- 回滚：只有还处于 dormant 才能 remove（Registry.remove 的前置条件）
        local current = Registry.read(actor.uid)
        if current ~= nil and current.lifecycle == "dormant" then
            pcall(Registry.remove, current.uid, current.revision, "start_with_npc_rejected")
        end
        return nil, tostring(requestError)
    end

    -- createZombieShell 硬编码朝南；这里顺手摆正（失败无所谓）
    if request.shell ~= nil and IsoDirections ~= nil then
        pcall(function() request.shell:setDir(IsoDirections.S) end)
    end

    Config.log(string.format("spawned %s at %d,%d (faction=%s profile=%s)", tostring(actor.uid),
        math.floor(x), math.floor(y), tostring(factionId), tostring(profileId)))
    return actor
end

--[[
    把"玩家 <-> 该 NPC 的阵营"的声望直接拉到同盟（allied）。

    为什么需要这么绕：
      * A-Life 的 stance 词汇里 allied 会被归一化成 friendly（ALifeRelations.lua:22），
        且 memory.spawnStance 只接受 friendly/neutral/careful/hostile —— 所以
        "同盟"这件事在 A-Life 侧的表达就是 friendly（它的上限），不能写 "allied"（会被白名单拒绝，
        反而退回按阵营关系计算，可能变成敌对）。
      * Jeem 才有真正的「同盟」档位：Services/Standing.lua:14 的阶梯
        { hostile, careful, neutral, friendly, allied }，thresholds = { 25, 75, 150, 250 }。
        把点数拉到 S.clamp（400）会跨过全部四个阈值 ⇒ 任何默认档位都会到 allied。
      * 而且 Jeem 的 Standing 特性（Features/Standing/Standing.lua:123 F.apply）会把该标签写回
        A-Life 的声望存档（foreign faction 写 status=label，own faction 写 status="allied"），
        所以这一下同时把 A-Life 侧的关系也顶到 friendly。
      * 副作用（已在沙盒 tooltip 里写明）：Jeem 的声望是按阵营记录的，所以变成同盟的是整个阵营。
]]
function Grant.makeAllied(player, actor)
    if not Config.makeAllied() then return false, "disabled" end
    local J = jimmy()
    if J == nil then return false, "jimmy_unavailable" end
    local S = J.StandingService
    if type(S) ~= "table" or type(S.set) ~= "function" or type(S.labelFor) ~= "function" then
        return false, "standing_service_missing"
    end
    local factionId = type(actor) == "table" and actor.factionId or nil
    if type(factionId) ~= "string" or factionId == "" then return false, "no_faction" end
    -- 与 Jeem 自己的兜底写法保持一致（Marks.lua:329 / BaseAreas.who:761 都是这个三元）：
    -- SP 下 A-Life 的 Reputation.playerKey 返回 "sp:<n>"，MP 下是用户名
    local key
    if type(J.playerKey) == "function" then
        local okKey, value = pcall(J.playerKey, player)
        if okKey and type(value) == "string" and value ~= "" then key = value end
    end
    if key == nil and type(J.username) == "function" then
        local okName, value = pcall(J.username, player)
        if okName and type(value) == "string" and value ~= "" then key = value end
    end
    if key == nil then key = "local" end

    local F = J.Standing
    local top = tonumber(S.clamp) or 400

    -- 1) 首选官方路径：F.debugSet 会按档位换算点数，并**先清掉 A-Life 声望里那条记录**
    --    （关键：若那条是 cause = "provoked"，F.apply 会拒绝覆盖它，同盟就设不上）
    if type(F) == "table" and type(F.debugSet) == "function" then
        local okSet, labelOrWhy = pcall(F.debugSet, player, factionId, "allied")
        if okSet and labelOrWhy == "allied" then
            Grant.stampGroupStanding(J, S, key, actor, factionId, top)
            return true, "allied"
        end
        -- 常见拒绝：联机里这名玩家不是服务器管理员（debugSet 要求 admin）。
        -- 官方路径被拒时走下面的等价退路（我们不需要 admin 权限）。
        Config.log("Standing.debugSet refused (" .. tostring(labelOrWhy) .. "); using equivalent fallback")
    end

    -- 2) 退路：复刻 debugSet 的三步（按档位算点数 → 清掉 A-Life 声望条目 → F.apply 写回）
    local defaultIndex = type(S.index) == "table" and S.index[S.defaultLabel and S.defaultLabel(factionId)] or nil
    local targetIndex = type(S.index) == "table" and S.index["allied"] or nil
    local points
    if targetIndex ~= nil and defaultIndex ~= nil then
        local steps = targetIndex - defaultIndex
        local thresholds = S.thresholds or {}
        points = steps == 0 and 0 or (steps > 0 and thresholds[steps] or -thresholds[-steps])
    end
    if points == nil then points = top end                       -- 换算不出来就退回置顶
    local poolBonus = (type(S.poolBonus) == "function") and (tonumber(S.poolBonus(key, factionId)) or 0) or 0
    S.set(key, factionId, points - poolBonus)

    -- 清掉 A-Life 声望里那条（等价于 Jeem 自己的 reputationStore() 里做的事）
    local Reputation = ProjectALife and ProjectALife.Reputation
    if Reputation ~= nil and Reputation.TAG ~= nil and ModData ~= nil then
        local okStore, store = pcall(ModData.getOrCreate, Reputation.TAG)
        if okStore and type(store) == "table" and type(store.players) == "table"
                and type(store.players[key]) == "table" then
            store.players[key][factionId] = nil
            if Reputation.dirty ~= nil then Reputation.dirty = true end
        end
    end
    if type(F) == "table" and type(F.apply) == "function" then
        pcall(F.apply, key, factionId)
    end

    -- 3) 组声望：让 R.isAlly 的"组点数 >= allyGroupPoints(50)"这条路也成立
    Grant.stampGroupStanding(J, S, key, actor, factionId, top)

    local okLabel, label = pcall(S.labelFor, key, factionId)
    label = okLabel and label or "?"
    return label == "allied", label
end

--[[
    兼容性自检：复用 A-Life 自己的检测器（ProjectALife.Compat.foreignCopies），
    把"自带 A-Life Lua 副本"的模组点名打到日志里。

    为什么值得做：A-Life 的 ALifeModCompat 明确写了这类模组的后果 ——
    "it replaces or runs beside A-Life's file and breaks on updates"、
    "old copy ... NPCs throw errors and stutter until that mod's A-Life Lua files are removed"。
    实测（2026-10-04 多人日志）就是如此：某个把 A-Life 旧版整包重传的"汉化"模组
    导致每次 NPC 水合都抛 "no such location"，而 A-Life 自己 12 次、本模组 28 次中招。
]]
function Grant.reportForeignCopies()
    if Grant.compatReported then return end
    local Compat = ProjectALife and ProjectALife.Compat
    if type(Compat) ~= "table" or type(Compat.foreignCopies) ~= "function" then return end
    Grant.compatReported = true

    local active = nil
    if type(Compat.activeSet) == "function" then
        local okSet, set = pcall(Compat.activeSet)
        if okSet and type(set) == "table" then active = set end
    end
    if active == nil and type(getActivatedMods) == "function" then
        local okMods, mods = pcall(getActivatedMods)
        if okMods and mods ~= nil then
            local set = {}
            pcall(function()
                for i = 0, mods:size() - 1 do set[mods:get(i)] = true end
            end)
            active = set
        end
    end

    local ok, lines = pcall(Compat.foreignCopies, active)
    if not ok or type(lines) ~= "table" or #lines == 0 then return end
    Config.warn("A-Life reports " .. tostring(#lines) .. " incompatible mod(s) in this stack.")
    Config.warn("They ship their own copy of A-Life's Lua; expect 'no such location' / animation errors "
        .. "and NPCs that stutter or fail to spawn.")
    for _, line in ipairs(lines) do Config.warn("  " .. tostring(line)) end
    Config.warn("Fix: disable or unsubscribe those mods. A translation must ship only Translate files.")
end

--[[
    死亡时清掉"本角色已发放"的 per-角色 标记（仅在开启 GrantOnRespawn 时）。

    为什么必须清 KEY_TOKEN：ActorRegistry.create 的幂等键是 operationId，
    而 operationId 里含本角色的令牌。若令牌不变，重生后调用会**返回那条旧（已死）记录**，
    接着 SpawnService.request 会以 actor_not_dormant 失败 —— 表现就是"重生不再发放"。
    清掉令牌 ⇒ 新 operationId ⇒ 真的生成一名新 NPC。

    另外：联机里玩家重生可能复用同一个 IsoPlayer 对象，所以这些状态一律存 modData 而不是按对象缓存。
]]
function Grant.onDeath(player)
    if player == nil then return end
    if not Config.grantOnRespawn() then return end
    local ok, err = pcall(function()
        local md = player:getModData()
        if type(md) ~= "table" then return end
        md[Config.KEY_GRANTED] = nil
        md[Config.KEY_TOKEN] = nil
        md[Config.KEY_ATTEMPTS] = nil
        md[Config.KEY_LAST_ATTEMPT_MS] = nil
    end)
    if ok then
        Config.log("death: cleared this character's grant markers (GrantOnRespawn is on) "
            .. "-> the next character will be granted again")
    else
        Config.warn("death hook failed: " .. tostring(err))
    end
end

-- 该 NPC 所在小队的组声望也给足（R.isAlly 的另一条判据）
function Grant.stampGroupStanding(J, S, key, actor, factionId, points)
    local groupId = nil
    if type(actor) == "table" and type(actor.memory) == "table" then groupId = actor.memory.groupId end
    if groupId == nil or type(S.addGroup) ~= "function" then return false end
    pcall(S.addGroup, key, groupId, factionId, tonumber(points) or 400)
    return true
end

-- 等实体被 A-Life 激活后，下一条原生 follow 命令
local function orderFollow(player, uid)
    local Registry, Decisions = actors(), decisions()
    if Registry == nil or Decisions == nil or type(Decisions.setOrder) ~= "function" then
        return false, "decision_loop_unavailable"
    end
    local record = Registry.read(uid)
    if record == nil or record.lifecycle ~= "active" then return false, "actor_not_active" end
    local ok, accepted = pcall(Decisions.setOrder, uid, record.generation, {
        kind = "follow", player = player, source = "player",
    })
    if not ok then return false, tostring(accepted) end
    if accepted == false then return false, "order_refused" end
    Config.log("follow order accepted for " .. tostring(uid))
    return true
end

-- Jeem 居民化：拿到/建立一个基地，然后 recruit（force=true 在 SP 恒可用，见 J.isAdminPlayer）
local function makeResident(player, uid, count)
    local J = jimmy()
    if J == nil or type(J.BaseAreas) ~= "table" or type(J.Residents) ~= "table" then
        return false, "jimmy_unavailable"
    end
    if type(J.enabled) == "function" and J.enabled("residents") ~= true then
        return false, "jimmy_residents_disabled"
    end
    local B, R = J.BaseAreas, J.Residents
    if type(B.who) ~= "function" or type(B.basesFor) ~= "function" or type(R.recruit) ~= "function" then
        return false, "jimmy_api_missing"
    end

    local who = B.who(player)
    local mine = B.basesFor(who.key, who.faction, who.admin)
    local base = type(mine) == "table" and mine[1] or nil

    if base == nil then
        if not Config.createCamp() then return false, "no_base" end
        local position = Grant.playerPosition(player)
        if position == nil then return false, "no_player_position" end
        local radius = 8
        local created, why = B.createBase({
            x1 = math.floor(position.x) - radius, y1 = math.floor(position.y) - radius,
            x2 = math.floor(position.x) + radius, y2 = math.floor(position.y) + radius,
            name = "Start Camp", role = "grounds",
        }, who)
        if created == nil then return false, "create_base_failed:" .. tostring(why) end
        base = created
        Config.log("created start camp base " .. tostring(base.id))
    end

    -- 绕过床位统计：R.capacity 直接读 base.bedsOverride（Server.lua:1104-1108, 1254-1260）
    local want = (tonumber(count) or 1) + 2
    if (tonumber(base.bedsOverride) or 0) < want then base.bedsOverride = want end
    pcall(B.transmit)

    -- 先走"正规"路径（需要 isAlly：由 Grant.makeAllied 把声望顶到同盟来满足），
    -- 这样联机里**不是管理员**的玩家也能收编；再退回 force（force 只在 who.admin 时生效）。
    local recruited, why = R.recruit(player, uid, base.id, false)
    if recruited == nil then
        local firstWhy = tostring(why)
        recruited, why = R.recruit(player, uid, base.id, true)
        if recruited == nil then
            return false, firstWhy .. "/" .. tostring(why)
        end
        Config.log("resident conversion needed force (first refusal: " .. firstWhy .. ")")
    end
    Config.log(string.format("recruited %s into base %s (%d heads)", tostring(uid), tostring(base.id),
        tonumber(recruited) or 0))
    return true
end

-- 每 tick 处理"等激活 → 下命令/转居民"
function Grant.tick()
    if Grant.pendingCount <= 0 then return end
    local Registry = actors()
    if Registry == nil then return end
    for uid, item in pairs(Grant.pending) do
        if item.tries > 600 then            -- ~10 秒（60fps）；再等下去也没意义
            Config.warn("gave up on " .. tostring(uid) .. " (never became active)")
            pendingRemove(uid)
        else
            item.tries = item.tries + 1
            local record = Registry.read(uid)
            if record == nil or record.lifecycle == "dead" then
                pendingRemove(uid)
            elseif record.lifecycle == "active" then
                if item.mode == 2 then
                    local ok, why = makeResident(item.player, uid, item.count)
                    if not ok then
                        Config.log("resident conversion unavailable (" .. tostring(why) .. "), falling back to follow")
                        orderFollow(item.player, uid)
                    end
                else
                    local ok, why = orderFollow(item.player, uid)
                    if not ok then Config.log("follow order not accepted (" .. tostring(why) .. ")") end
                end
                pendingRemove(uid)
            end
        end
    end
end

--[[
    主流程。返回 true = 已发放；false = 这次没成（可稍后重试）。
]]
function Grant.run(player)
    if player == nil then return false end
    if not Config.enabled() then return false end

    local md = nil
    local ok = pcall(function() md = player:getModData() end)
    if not ok or type(md) ~= "table" then return false end

    if md[Config.KEY_GRANTED] == true then
        -- 让 T2（读档不重复发放）在看日志时一眼可验
        Config.log("this character was already granted earlier; skipping (no duplicate NPC)")
        return true
    end

    -- “每存档只给第一个角色”模式：优先用 A-Life 的存档级值（新档天然为空、读档保留），
    -- 拿不到就退回我们自己的 ModData。
    if not Config.grantOnRespawn() then
        local saved
        local savedOk = pcall(function()
            local Registry = actors()
            if Registry ~= nil and type(Registry.getWorldValue) == "function" then
                if Registry.getWorldValue(Config.SAVE_TAG) == true then saved = true return end
            end
            local store = ModData and ModData.getOrCreate(Config.SAVE_TAG)
            if type(store) == "table" and store.everGranted == true then saved = true end
        end)
        if savedOk and saved == true then
            Config.log("save-level flag already set and GrantOnRespawn is off; skipping")
            md[Config.KEY_GRANTED] = true
            return true
        end
    end

    local ready, why = Grant.worldReady(player)
    if not ready then return false, why end

    -- 本角色的一次性令牌：保证 operationId 唯一，同时让 A-Life 的幂等兜住重复调用
    local token = md[Config.KEY_TOKEN]
    if type(token) ~= "string" then
        token = tostring(nowMs()) .. "-" .. tostring(ZombRand(1000000))
        md[Config.KEY_TOKEN] = token
    end
    local key = "local"
    local J = jimmy()
    if J ~= nil and type(J.playerKey) == "function" then
        local keyOk, value = pcall(J.playerKey, player)
        if keyOk and type(value) == "string" and value ~= "" then key = value end
    end

    -- 生成节流：A-Life 的 hydrate 失败通常是"数据没就绪"或"存在旧版 A-Life 副本"，
    -- 每帧重试既没用又会把日志刷爆（上一版 MP 日志里出现过连续的 create/remove 噪声）。
    local attempts = tonumber(md[Config.KEY_ATTEMPTS]) or 0
    local lastAttemptMs = tonumber(md[Config.KEY_LAST_ATTEMPT_MS]) or 0
    local nowAttempt = nowMs()
    if attempts >= Config.MAX_SPAWN_ATTEMPTS then
        return false, "spawn_attempts_exhausted"
    end
    if nowAttempt - lastAttemptMs < Config.SPAWN_RETRY_MS then
        return false, "spawn_throttled"
    end
    md[Config.KEY_ATTEMPTS] = attempts + 1
    md[Config.KEY_LAST_ATTEMPT_MS] = nowAttempt

    local count = Config.count()
    local mode = Config.mode()
    local spawned = 0

    for index = 1, count do
        local factionId, profileId, pickWhy = Pick.choose()
        if factionId == nil then
            Config.error("cannot pick a faction/profile: " .. tostring(pickWhy))
            break
        end
        Config.log(string.format("grant #%d: faction=%s profile=%s (%s)", index, factionId, profileId,
            tostring(pickWhy)))
        local opId = string.format("%s:%s:%s:%d", Config.MODULE, key, token, index)
        local actor, spawnError = Grant.spawnOne(player, index, factionId, profileId, opId)
        if actor == nil then
            Config.error("spawn failed: " .. tostring(spawnError)
                .. " (attempt " .. tostring(md[Config.KEY_ATTEMPTS] or 0) .. "/"
                .. tostring(Config.MAX_SPAWN_ATTEMPTS) .. ")")
            if tostring(spawnError):find("hydration", 1, true) ~= nil then
                Grant.reportForeignCopies()
            end
        else
            spawned = spawned + 1
            -- 生成瞬间就把"玩家 <-> 该 NPC 阵营"的声望拉到同盟（见 Grant.makeAllied 的注释）
            local allied, label = Grant.makeAllied(player, actor)
            if allied then
                Config.log("standing with " .. tostring(actor.factionId) .. " is now ALLIED")
            else
                Config.log("ally step skipped/failed: " .. tostring(label))
            end
            pendingAdd(actor.uid, { uid = actor.uid, player = player, mode = mode,
                count = count, tries = 0 })
        end
    end

    if spawned == 0 then return false, "nothing_spawned" end

    md[Config.KEY_GRANTED] = true
    if not Config.grantOnRespawn() then
        pcall(function()
            local Registry = actors()
            if Registry ~= nil and type(Registry.setWorldValue) == "function" then
                Registry.setWorldValue(Config.SAVE_TAG, true)
            end
            local store = ModData and ModData.getOrCreate(Config.SAVE_TAG)
            if type(store) == "table" then store.everGranted = true end
        end)
    end
    Config.log(string.format("grant complete: %d/%d npcs (mode=%s)", spawned, count, tostring(mode)), true)
    return true
end

return Grant
