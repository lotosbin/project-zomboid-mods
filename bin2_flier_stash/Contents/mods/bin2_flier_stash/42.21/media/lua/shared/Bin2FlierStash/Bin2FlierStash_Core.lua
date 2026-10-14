--[[
    bin2 传单寻宝 —— 共有逻辑（单机与联机服务端都用这份）
    流程：点亮传单 → arm(mediaID) → 玩家走进那片区域 → spawnAround(player) → markDone

    只用原版 API：PrintMediaDefinitions（点亮坐标表）、addZombiesInOutfitArea（刷尸群，返回僵尸列表）、
    ModData（存档内状态）、HaloTextHelper（提示）。ID 与签名都经 javap / 原版 Lua 核对。
]]

Bin2FlierStash = Bin2FlierStash or {}

-- 全局存档 ModData：armed = 已点亮、等着玩家过去的地点；done = 已经开过的地点
function Bin2FlierStash.getData()
    local md = ModData.getOrCreate(Bin2FlierStash.MOD_DATA_KEY)
    md.armed = md.armed or {}
    md.done = md.done or {}
    return md
end

-- 状态是服务端权威（单机由本机持有）：只在联机时同步给客户端
local function syncData()
    if isClient() and ModData and ModData.transmit then
        pcall(function() ModData.transmit(Bin2FlierStash.MOD_DATA_KEY) end)
    end
end

function Bin2FlierStash.isDone(mediaID)
    return Bin2FlierStash.getData().done[mediaID] == true
end

-- 点亮一张传单：登记待触发地点。已开过 / 已登记 / 表里没这个 mediaID ⇒ false
function Bin2FlierStash.arm(mediaID)
    if type(mediaID) ~= "string" or mediaID == "" then return false end
    if not Bin2FlierStash.getRects(mediaID) then return false end
    local md = Bin2FlierStash.getData()
    if md.done[mediaID] or md.armed[mediaID] then return false end
    md.armed[mediaID] = true
    syncData()
    print("[Bin2FlierStash] armed location " .. mediaID)
    return true
end

function Bin2FlierStash.markDone(mediaID)
    local md = Bin2FlierStash.getData()
    md.armed[mediaID] = nil
    md.done[mediaID] = true
    syncData()
end

-- 给一只僵尸塞 1~2 件战利品
local function injectLoot(zombie)
    if not zombie then return end
    local inv = zombie:getInventory()
    if not inv then return end
    local n = math.floor(ZombRand(Bin2FlierStash.REWARD_ITEMS_MIN, Bin2FlierStash.REWARD_ITEMS_MAX + 1))
    for _ = 1, n do
        local item, amount = Bin2FlierStash.rollLoot()
        if item then
            local ok = pcall(function() inv:AddItems(item, amount) end)
            if not ok then
                for _ = 1, amount do pcall(function() inv:AddItem(item) end) end
            end
        end
    end
end

-- 刷一小片丧尸，返回引擎给的僵尸列表（ArrayList<IsoZombie>，失败返回 nil）
local function spawnZombies(x1, y1, x2, y2, z, count)
    count = math.floor(count)
    if count <= 0 then return nil end
    local ok, list = pcall(addZombiesInOutfitArea, x1, y1, x2, y2, z, count, nil, nil)
    if not ok then
        print("[Bin2FlierStash] addZombiesInOutfitArea failed: " .. tostring(list))
        return nil
    end
    return list
end

-- 玩家到达：在四个象限（离玩家 6~16 格，避免贴脸刷）铺尸群，另刷几只带战利品的
function Bin2FlierStash.spawnAround(player)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local z = math.floor(player:getZ())
    local want = math.floor(ZombRand(Bin2FlierStash.HORDE_MIN, Bin2FlierStash.HORDE_MAX + 1))
    local quads = {
        { px - 16, py - 16, px - 6, py - 6 },
        { px + 6,  py - 16, px + 16, py - 6 },
        { px - 16, py + 6,  px - 6, py + 16 },
        { px + 6,  py + 6,  px + 16, py + 16 },
    }
    local per = math.floor(want / #quads)
    local spawned = 0
    for _, q in ipairs(quads) do
        if spawnZombies(q[1], q[2], q[3], q[4], z, per) then spawned = spawned + per end
    end
    -- 奖励丧尸单独刷，这样拿得到僵尸对象去塞战利品
    local q = quads[math.min(#quads, math.floor(ZombRand(1, #quads + 1)))]
    local ok, rewards = pcall(addZombiesInOutfitArea, q[1], q[2], q[3], q[4], z,
        Bin2FlierStash.REWARD_ZOMBIES, nil, nil)
    if ok and rewards then
        local size = 0
        if rewards.size then size = rewards:size() end
        for i = 0, size - 1 do injectLoot(rewards:get(i)) end
    else
        print("[Bin2FlierStash] reward spawn failed: " .. tostring(rewards))
    end
    print(string.format("[Bin2FlierStash] spawned %d zombies around %d,%d (z=%d)", spawned, px, py, z))
    return spawned
end

-- 每次玩家更新调用（调用方限流）：看有没有"已点亮且人已到"的地点
function Bin2FlierStash.updateArrival(player)
    if not player or player:isDead() then return end
    local md = Bin2FlierStash.getData()
    -- 先收键再改表：pairs 迭代中删键是未定义行为
    local pending = {}
    for mediaID in pairs(md.armed) do pending[#pending + 1] = mediaID end
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    for _, mediaID in ipairs(pending) do
        local rects = Bin2FlierStash.getRects(mediaID)
        if not rects then
            Bin2FlierStash.markDone(mediaID)   -- 表里没有（自定义地图/上游改过）⇒ 作废，别卡着
        elseif Bin2FlierStash.isInside(rects, px, py, Bin2FlierStash.ARRIVE_RADIUS) then
            Bin2FlierStash.spawnAround(player)
            Bin2FlierStash.markDone(mediaID)
            Bin2FlierStash.notifyArrived(player)
        end
    end
end

-- 提示（服务端没有 HaloTextHelper，包一层）
function Bin2FlierStash.notifyArrived(player)
    if HaloTextHelper and HaloTextHelper.addGoodText then
        HaloTextHelper.addGoodText(player, getText("UI_Bin2FlierStash_Arrived"))
    end
end

function Bin2FlierStash.notifyArmed(player)
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(player, getText("UI_Bin2FlierStash_Armed"))
    end
end
