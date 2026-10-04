-- CompanionDogsAlpaca: 品种注册（addon 契约的入口）
--
-- 这里调用 CD.registerSpecies / CD.registerVoices / CD.registerBreed，是"扩展 CompanionDogs"的
-- 唯一正式入口。要点（来自官方手册 + base 源码实证）：
--   * require=CompanionDogs 保证 base 的全部 Lua 先跑；文件顶部还要按"用到什么就 guard 什么"再挡一层。
--   * registerVoices 必须在 registerBreed **之前**：registerBreed 只检查 CD.SOUND_CATEGORY 并打日志，
--     不阻断注册，声音会静默地不跟玩家的音量/静音走。
--   * 循环音（吃/喝）必须自己补 CD.SOUND_LOOPED，registerVoices 不管这个。
--   * engineBreed 是事实必填：base 里缺省回落 CD.BREED（= "brown"，金毛的皮），漏写会贴错皮。
local CD = CompanionDogs
-- 本模组是"新物种"，物种注册（API 6）是硬要求：base 更旧就没有 CD.registerSpecies，
-- 一只会跟狗杂交的羊驼比"完全不出现"更糟，所以这里直接早退而不是降级运行。
-- 版本下限同时写在 mod.info 的 description 与工坊描述里（versionMin 只管游戏版本，
-- mod.info 没有"依赖哪个 base 版本"的字段）。
if not (CD and CD.registerBreed and CD.registerSpecies and (CD.API_VERSION or 0) >= 6) then return end

-- ---------------------------------------------------------------- 物种
-- 新物种要注册三个翻译键：nounKey 是填进 "%1" 的裸名词（小写），youngKey 是幼体称谓，
-- labelKey 是档案卡 "Species" 那一行的显示名（可选，缺省回落 nounKey）。
CD.registerSpecies({
    key = "alpaca",
    nounKey = "IGUI_PD_SpeciesNoun_alpaca",
    youngKey = "IGUI_PD_Young_alpaca",
    labelKey = "IGUI_PD_SpeciesDisplay_alpaca",
})

-- ---------------------------------------------------------------- 声音
-- 全部是本地合成的（tools/alpaca/make_sounds.py），没有采样任何外部素材。
-- 第三个参数是"可听范围（tile）"，必须与 sounds_cdalpaca.txt 里每个 clip 的 distanceMax 对齐：
-- 服务端据此只把声音包发给范围内的玩家。
CD.registerVoices({
    CDAlpacaAlarm = "bark",          -- 报警哞叫：哨兵警报、战斗、应激自叫
    CDAlpacaAlarmAmbient = "ambient",-- 远处流浪羊驼的报警声（纯环境音，不吸引僵尸）
    CDAlpacaHum = "bark",            -- 满足/联络的哼鸣
    CDAlpacaSpit = "bark",           -- 警告吐口水
    CDAlpacaWhine = "bark",          -- 疼痛/生病
    CDAlpacaDeath = "bark",          -- 死亡长鸣
    CDAlpacaPickup = "bark",         -- 被抱起/放下
    CDAlpacaChew = "fx",             -- 咀嚼（循环）
    CDAlpacaDrink = "fx",            -- 饮水（循环）
}, { "CDAlpacaWhine", "CDAlpacaDeath", "CDAlpacaPickup" }, {
    CDAlpacaAlarm = 28, CDAlpacaAlarmAmbient = 28, CDAlpacaWhine = 15, CDAlpacaDeath = 25,
    CDAlpacaHum = 12, CDAlpacaSpit = 10, CDAlpacaPickup = 8, CDAlpacaChew = 10, CDAlpacaDrink = 10,
})

-- 循环音登记：不写这两行，动物走出听觉范围后声道不会被停（会一直响到离开世界）。
if CD.SOUND_LOOPED then
    CD.SOUND_LOOPED.CDAlpacaChew = true
    CD.SOUND_LOOPED.CDAlpacaDrink = true
else
    CD.log("CompanionDogsAlpaca: base sem CD.SOUND_LOOPED; o som de mastigar/beber nao sera parado " ..
           "por distancia.")
end

-- ---------------------------------------------------------------- 气候
-- 羊驼是高原动物：耐寒、怕热。这两个函数放在 **shared** 里而不是 server 里 ——
-- 客户端 moodle 要用同一个判据（base 的 Pug 也是这么放）。
CD.ALPACA_HEAT_ENTER = 24.0      -- 从这度开始热应激
CD.ALPACA_HEAT_FULL = 34.0       -- 到这度满值
CD.ALPACA_HEAT_STRESS_MAX = 0.22 -- 每轮 upkeep 最多加这么多应激
CD.ALPACA_COLD_ENTER = 4.0       -- 低于这度开始冷应激（厚毛让它比狗耐寒得多）
CD.ALPACA_COLD_FULL = -8.0       -- 到这度满值
CD.ALPACA_COLD_STRESS_MAX = 0.10 -- 冷应激上限：有毛，但没棚也难受

---@param char IsoAnimal|IsoPlayer|nil
---@return number|nil air temperature in celsius
function CD.alpacaAirTemp(char)
    -- 自己包 pcall：base 的 moodle 求值循环与本模组的气候钩子**都没有** pcall
    -- （整个 base 的 Lua 里一个都没有），这里抛异常会连带打断 moodle 的整轮求值。
    local ok, t = pcall(function()
        local cm = getClimateManager()
        if not cm then return nil end
        if char then
            -- IsoAnimal extends IsoPlayer（javap 实证），所以这个签名对动物同样合法；
            -- 第二参数与 vanilla 的用法一致（媒体/lua/shared/Fishing/Bobber.lua:83）。
            return cm:getAirTemperatureForCharacter(char, false)
        end
        return cm:getTemperature()
    end)
    if not ok or type(t) ~= "number" then return nil end
    return t
end

---@param char IsoAnimal|nil
---@return number 0..1 heat stress ratio
function CD.alpacaHeatRatio(char)
    local t = CD.alpacaAirTemp(char)
    if type(t) ~= "number" then return 0 end
    local r = (t - CD.ALPACA_HEAT_ENTER) / (CD.ALPACA_HEAT_FULL - CD.ALPACA_HEAT_ENTER)
    if r < 0 then return 0 elseif r > 1 then return 1 end
    return r
end

---@param char IsoAnimal|nil
---@return number 0..1 cold stress ratio
function CD.alpacaColdRatio(char)
    local t = CD.alpacaAirTemp(char)
    if type(t) ~= "number" then return 0 end
    local span = CD.ALPACA_COLD_ENTER - CD.ALPACA_COLD_FULL
    if span <= 0 then return 0 end
    local r = (CD.ALPACA_COLD_ENTER - t) / span
    if r < 0 then return 0 elseif r > 1 then return 1 end
    return r
end

-- ---------------------------------------------------------------- 生成
-- 羊驼是家畜：主要出现在农场建筑（base 的 farm class 允许在城镇外投骰），
-- 少数出现在宠物医院/宠物店。chance 是**百分比**（base 里 `ZombRand(0,100) >= chance` 即失败），
-- 且这里除以毛色数量 —— 加毛色只增加"花色"，不会把世界里的羊驼总量翻倍（CD: Cats 用的同一套算法）。
--
-- 数值标定（base 自己的常量，`config/Diagnostics.lua` + `config/Care.lua:55`）：
--   民宅流浪狗 3%/栋、农场边牧 15%/栋、警局德牧 POLICE_SHEPHERD_CHANCE、猫合计约 10%/栋。
-- 羊驼总量取农场 6%/栋（比农场狗稀少，但比"一辈子见不到"常见），宠物医院/店 3%/栋。
CD.ALPACA_FARM_CHANCE = 6.0       -- farm 建筑出现羊驼的百分比（每毛色摊薄前）
CD.ALPACA_PETVET_CHANCE = 3.0     -- petvet 建筑出现羊驼的百分比（每毛色摊薄前）

---@return number multiplier >= 0 from the mod's own sandbox option
local function alpacaSpawnMultiplier()
    local sv = SandboxVars and SandboxVars.CompanionAlpaca
    local m = sv and sv.AlpacaSpawnMultiplier
    if type(m) ~= "number" then return 1.0 end
    if m < 0 then return 0 end
    return m
end

-- ---------------------------------------------------------------- 品种
-- 一套共用数值（PROFILE）+ 每个毛色只换 key/engineBreed/名字键/生成后缀。
-- 设计取向（与狗、猫拉开差异）：
--   * 驮兽：bagMult 2.2（狗是 1），背包能装得比狗多一倍多；
--   * 报警器：sentinelMult 1.5、barkNoiseMult 1.2 —— 它很少打架，但很早就叫；
--   * 不狩猎：hunt = false（羊驼不吃肉，也不去追猎物）；
--   * 牧群特化：herding 2.0（这是它的本职工作），scent 1.2，combat 0.8，obedience 0.9；
--   * 脾气：能踢倒僵尸但打不死（canKill = false / canKnockdown = true），受惊阈值低（0.60）。
local PROFILE = {
    typePrefix = "alpaca",
    species = "alpaca",
    descKey = "IGUI_PD_BreedDesc_alpaca",
    limpAnim = true,               -- 派生模型带全套 Rac_* 剪辑，含两条瘸腿行走
    litter = { 1, 1 },             -- 羊驼一胎一崽
    puppySize = 1.85,              -- 绝对视觉尺寸；不给的话幼崽会被强制到 base 默认的 0.6（像小狗）
                                   -- 新网格静止高 0.4523 单位，1.85 ⇒ 幼驼约 0.84 m（成年的 ~60%）
    xpMult = { scent = 1.2, combat = 0.8, obedience = 0.9, hunt = 1.0, herding = 2.0 },
    combatPower = 0.35,
    lethalityCurve = { min = 0.45, max = 1.25 },
    canKill = false,
    canKnockdown = true,
    combatStressMult = 1.15,
    panicThreshold = 0.60,
    bagMult = 2.2,
    sentinelMult = 1.5,
    barkNoiseMult = 1.2,
    loyaltyDecayMult = 0.8,
    skills = { hunt = false },
    canBreed = true,
    huntMaxPrey = "tiny",
    voices = { bark = "CDAlpacaAlarm", growl = "CDAlpacaSpit", idle = "CDAlpacaHum",
               wildbark = "CDAlpacaAlarmAmbient", pet = "CDAlpacaHum", whine = "CDAlpacaWhine",
               eat = "CDAlpacaChew", drink = "CDAlpacaDrink" },
    -- 严格草食：以 replace 从空表开始，只列羊驼真正认的东西。
    -- protein 是"还肉债"的那张表（Weak moodle 盯的就是它），对羊驼来说干草/蔬菜/豆类算数。
    -- 洋葱、蒜、葡萄、牛油果、巧克力、咖啡这些对羊驼同样有毒，所以照抄 base 的毒性名单。
    diet = {
        replace = true,
        bad = { Candy = true, Sugar = true, Coffee = true, Tea = true, Cocoa = true,
                Chocolate = true, HotPepper = true },
        badParts = { onion = true, garlic = true, leek = true, chive = true, shallot = true,
                     scallion = true, grape = true, raisin = true, chocolate = true, cocoa = true,
                     coffee = true, acorn = true, macadamia = true, avocado = true, dough = true },
        protein = { Vegetable = true, Vegetables = true, Greens = true, Bean = true, Seed = true,
                    Nut = true, Mushroom = true, Fruits = true, Berry = true, Citrus = true,
                    Hay = true, Grass = true, AnimalFeed = true },
        proteinParts = { hay = true, grass = true, silage = true, alfalfa = true, clover = true,
                         vegetable = true, bean = true, seed = true, mushroom = true, fruit = true,
                         berry = true },
        trough = { Hay = true, Grass = true, AnimalFeed = true, Vegetables = true, Fruits = true,
                   Greens = true },
        troughItems = {},
    },
    geneRange = {
        strength       = { 0.05, 0.25 },
        aggressiveness = { 0.00, 0.15 },
        resistance     = { 0.10, 0.30 },
        stress         = { 0.35, 0.65 },
    },
}

-- 品种键（人类可读，存档里存的就是它）与引擎品种（决定贴图）是两套名字；
-- 生成后缀 |a? 属于持久化键，一旦发布**绝不能改名**（改名 = 每个存档的每栋建筑重新投骰）。
-- 已占用后缀（base 与已发布 addon）：空、g、h、hv、bc、gh、hh、bh、rw、r、db、dm、dh、lb、lk、
-- pg、pv、ml、mm、mh、ct*/cv*/cs*。本项目用 ap*/av*（alpaca）。
local COATS = {
    { key = "alpaca",         engine = "alpaca",       farm = "|ap",  petvet = "|av"  },
    { key = "alpacafawn",     engine = "alpaca_fawn",  farm = "|apf", petvet = "|avf" },
    { key = "alpacabrown",    engine = "alpaca_brown", farm = "|apb", petvet = "|avb" },
    { key = "alpacablack",    engine = "alpaca_black", farm = "|apk", petvet = "|avk" },
    { key = "alpacagrey",     engine = "alpaca_grey",  farm = "|apg", petvet = "|avg" },
    { key = "alpacarosegrey", engine = "alpaca_rose",  farm = "|apr", petvet = "|avr" },
    { key = "alpacasuri",     engine = "alpaca_suri",  farm = "|aps", petvet = "|avs" },
}

-- 摊薄用的毛色数从表里数出来，避免"加一个毛色忘了改常数"（CD: Cats 也是这么做的）
CD.ALPACA_COAT_COUNT = #COATS

CompanionDogsAlpaca = CompanionDogsAlpaca or {}
CompanionDogsAlpaca.BREED_KEYS = {}     -- 品种键集合（moodle / 气候钩子用它判"是不是羊驼"）
CompanionDogsAlpaca.ENGINE_BREEDS = {}  -- 引擎品种集合（与 AlpacaDefinitions.lua 的表做一致性检查）

for _, coat in ipairs(COATS) do
    CompanionDogsAlpaca.BREED_KEYS[coat.key] = true
    CompanionDogsAlpaca.ENGINE_BREEDS[coat.engine] = true

    local def = {}
    for k, v in pairs(PROFILE) do def[k] = v end
    def.key = coat.key
    def.engineBreed = coat.engine
    def.nameKey = "IGUI_PD_Breed_" .. coat.key
    def.spawns = {
        -- indoor 是"生在室内"的百分比：羊驼是放牧动物，多数应该站在院子里而不是谷仓里
        { id = coat.key .. "farm", class = "farm", suffix = coat.farm, breed = coat.key, indoor = 25,
          chance = function()
              return (CD.ALPACA_FARM_CHANCE / CD.ALPACA_COAT_COUNT) * alpacaSpawnMultiplier()
          end },
        { id = coat.key .. "petvet", class = "petvet", suffix = coat.petvet, breed = coat.key, indoor = 80,
          chance = function()
              return (CD.ALPACA_PETVET_CHANCE / CD.ALPACA_COAT_COUNT) * alpacaSpawnMultiplier()
          end },
    }
    CD.registerBreed(def)
end
