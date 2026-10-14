--[[
    bin2 传单寻宝 —— 配置与战利品表
    所有可调参数集中在这里；战利品只用原版物品（ID 都逐一核过存在）。
]]

Bin2FlierStash = Bin2FlierStash or {}

-- 全局 ModData 的键（整数索引的 ArrayList 由引擎管理；这里用字符串键，跨存档持久化）
Bin2FlierStash.MOD_DATA_KEY = "Bin2FlierStash"

-- 走到多近算"到达"（方块）。原版传单点亮的矩形可能很大，用一个半径兜住入口。
Bin2FlierStash.ARRIVE_RADIUS = 15

-- 尸群规模（到达时在身边刷）
Bin2FlierStash.HORDE_MIN = 6
Bin2FlierStash.HORDE_MAX = 12

-- 其中带战利品的只数（在区域中心附近单独刷，保证找得到）
Bin2FlierStash.REWARD_ZOMBIES = 3

-- 每只奖励丧尸带几件
Bin2FlierStash.REWARD_ITEMS_MIN = 1
Bin2FlierStash.REWARD_ITEMS_MAX = 2

-- 检查"是否到达"的间隔（毫秒），别每帧都算
Bin2FlierStash.CHECK_INTERVAL_MS = 1000

-- 同一个地点重复触发时的冷却（毫秒）——只为防止"没刷出来"被读成"再试一次"
Bin2FlierStash.RETRY_COOLDOWN_MS = 5000

-- 战利品表：weight 越大越常见。ID 已逐个核对存在于原版物品定义。
Bin2FlierStash.LOOT_TABLE = {
    { item = "Base.DuctTape",         amount = 2, weight = 26 },
    { item = "Base.Nails",            amount = 20, weight = 22 },
    { item = "Base.Screwdriver",      amount = 1, weight = 14 },
    { item = "Base.Hammer",           amount = 1, weight = 14 },
    { item = "Base.Saw",              amount = 1, weight = 12 },
    { item = "Base.Crowbar",          amount = 1, weight = 12 },
    { item = "Base.HuntingKnife",     amount = 1, weight = 10 },
    { item = "Base.WeldingRods",      amount = 4, weight = 10 },
    { item = "Base.BlowTorch",        amount = 1, weight = 8 },
    { item = "Base.FirstAidKit",      amount = 1, weight = 8 },
    { item = "Base.Whiskey",          amount = 1, weight = 8 },
    { item = "Base.Bullets38Box",     amount = 1, weight = 6 },
    { item = "Base.ShotgunShellsBox", amount = 1, weight = 5 },
    { item = "Base.Axe",              amount = 1, weight = 5 },
    { item = "Base.Sledgehammer",     amount = 1, weight = 4 },
    { item = "Base.HuntingRifle",     amount = 1, weight = 2 },
    { item = "Base.BookCarpentry5",   amount = 1, weight = 2 },
}

-- 按权重抽一件战利品（返回物品 ID 与数量）
function Bin2FlierStash.rollLoot()
    local total = 0
    for _, entry in ipairs(Bin2FlierStash.LOOT_TABLE) do
        total = total + entry.weight
    end
    if total <= 0 then return nil end
    local roll = ZombRand(total)
    local acc = 0
    for _, entry in ipairs(Bin2FlierStash.LOOT_TABLE) do
        acc = acc + entry.weight
        if roll < acc then
            return entry.item, entry.amount or 1
        end
    end
    local last = Bin2FlierStash.LOOT_TABLE[#Bin2FlierStash.LOOT_TABLE]
    return last.item, last.amount or 1
end

-- 取某个 mediaID 的点亮矩形（原版表：PrintMediaDefinitions.MiscDetails[mediaID].location1..5）
function Bin2FlierStash.getRects(mediaID)
    if not PrintMediaDefinitions or not PrintMediaDefinitions.MiscDetails then
        return nil
    end
    local details = PrintMediaDefinitions.MiscDetails[mediaID]
    if not details then return nil end
    local rects = {}
    for i = 1, 5 do
        local locationData = details["location" .. i]
        if locationData == nil then break end
        for _, sqData in ipairs(locationData) do
            rects[#rects + 1] = sqData
        end
    end
    if #rects == 0 then return nil end
    return rects
end

-- 点是否落在某组矩形内（含外扩半径）
function Bin2FlierStash.isInside(rects, x, y, radius)
    radius = radius or 0
    for _, r in ipairs(rects) do
        if x >= (r.x1 - radius) and x <= (r.x2 + radius) and y >= (r.y1 - radius) and y <= (r.y2 + radius) then
            return true
        end
    end
    return false
end
