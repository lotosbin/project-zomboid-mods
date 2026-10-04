-- CompanionDogsBlockyAlpaca: 方块羊驼（voxel 造型）的品种注册
--
-- 设计取向：**不新开物种**，而是复用 CompanionDogsAlpaca 注册的 "alpaca" 物种 ——
-- 方块羊驼和写实羊驼在玩法上是同一种动物（同样的驮载/牧群/草食/怕热数值），
-- 只是网格换成脚本生成的方块造型、贴图换成方块毛色。这样：
--   * 它们可以和写实羊驼同群、同栏、同一个 moodle/气候规则；
--   * 不需要重复注册物种（物种键全局唯一，重复注册会被 base 拒绝并打日志）。
--
-- 契约要点（与写实羊驼那份一致，都来自 base 源码与官方手册）：
--   * registerSpecies 由 CompanionDogsAlpaca 负责，这里只 registerBreed；
--   * engineBreed 是事实必填（base 缺省回落 CD.BREED = 金毛皮），每个毛色必须唯一；
--   * typePrefix 决定三个动物类型 <prefix>pup/female/male，必须在 Definitions 里都有条目；
--   * 生成后缀 |b?* 是持久化键，一旦发布不能再改。
local CD = CompanionDogs
local Alpaca = CompanionDogsAlpaca

-- 依赖检查分两层：base 的 API 版本，以及"物种提供者"是否在（本 addon 的 require 写在 mod.info，
-- 但 Steam 更新顺序不可控，所以再挡一层，缺了就直接安静退出而不是半注册）。
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 6) then return end
if not (Alpaca and Alpaca.BREED_KEYS and CD.SPECIES and CD.SPECIES["alpaca"]) then
    CD.log("CompanionDogsBlockyAlpaca: CompanionDogsAlpaca ausente (especie alpaca); " ..
           "nenhuma raca registrada.")
    return
end

-- ---------------------------------------------------------------- 生成
-- 与写实羊驼共用同一个沙盒倍率（SandboxVars.CompanionAlpaca.AlpacaSpawnMultiplier）。
-- 那个选项的访问函数在写实羊驼的 Breed.lua 里是 local，拿不到，所以这里自己读一遍。
-- 好处：玩家调一个选项就能同时影响两种造型，不需要新加翻译键。
local function spawnMultiplier()
    local sv = SandboxVars and SandboxVars.CompanionAlpaca
    local m = sv and sv.AlpacaSpawnMultiplier
    if type(m) ~= "number" then return 1.0 end
    if m < 0 then return 0 end
    return m
end

CD.BLOCKY_FARM_CHANCE = 4.0      -- farm 建筑出现方块羊驼的百分比（摊薄前）
CD.BLOCKY_PETVET_CHANCE = 2.0    -- petvet 建筑出现方块羊驼的百分比（摊薄前）

-- ---------------------------------------------------------------- 毛色表
-- 毛色数从表里数出来，避免"加了毛色忘了改常数"。
-- 后缀占用情况：|bk* / |bv* 未被 base 与任何已发布 addon 使用（已占用：空、g、h、hv、bc、gh、hh、
-- bh、rw、r、db、dm、dh、lb、lk、pg、pv、ml、mm、mh、ct*、cv*、cs*、ap*、av*）。
local COATS = {
    { key = "blockycream", engine = "blocky_cream", farm = "|bk", petvet = "|bv" },
    { key = "blockybrown", engine = "blocky_brown", farm = "|bkb", petvet = "|bvb" },
    { key = "blockygray",  engine = "blocky_gray",  farm = "|bkg", petvet = "|bvg" },
    { key = "blockyspot",  engine = "blocky_spot",  farm = "|bks", petvet = "|bvs" },
}

CD.BLOCKY_COAT_COUNT = #COATS

CompanionDogsBlockyAlpaca = CompanionDogsBlockyAlpaca or {}
CompanionDogsBlockyAlpaca.BREED_KEYS = {}
CompanionDogsBlockyAlpaca.ENGINE_BREEDS = {}

-- 把方块品种登记进写实羊驼的集合：它的"羊毛暖意" moodle 与"怕热/耐寒"应激钩子都是按
-- CompanionDogsAlpaca.BREED_KEYS 过滤的，登记之后方块羊驼自动享受同一套规则
-- （它们本来就是同一种动物，分开处理反而会让玩家觉得"方块的不怕热"是 bug）。
for _, coat in ipairs(COATS) do
    CompanionDogsBlockyAlpaca.BREED_KEYS[coat.key] = true
    CompanionDogsBlockyAlpaca.ENGINE_BREEDS[coat.engine] = true
    Alpaca.BREED_KEYS[coat.key] = true
    Alpaca.ENGINE_BREEDS[coat.engine] = true
end

-- ---------------------------------------------------------------- 数值档案
-- 与写实羊驼完全一致：同物种就该同数值。抄一份而不是引用写实羊驼的表，
-- 是因为 base 的 registerBreed 会往传进去的表里回填字段，共用一张表会被后注册的覆盖。
local PROFILE = {
    typePrefix = "bky",
    species = "alpaca",
    descKey = "IGUI_PD_BreedDesc_blockycream",
    limpAnim = true,
    litter = { 1, 1 },
    puppySize = 1.50,              -- 绝对视觉尺寸；方块网格静止高 0.5589 单位（写实是 0.4523）
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
    -- 叫声直接复用写实羊驼注册过的音名（CompanionDogsAlpaca 是硬依赖，那套音一定在）。
    voices = { bark = "CDAlpacaAlarm", growl = "CDAlpacaSpit", idle = "CDAlpacaHum",
               wildbark = "CDAlpacaAlarmAmbient", pet = "CDAlpacaHum", whine = "CDAlpacaWhine",
               eat = "CDAlpacaChew", drink = "CDAlpacaDrink" },
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

-- ---------------------------------------------------------------- 注册
for _, coat in ipairs(COATS) do
    local def = {}
    for k, v in pairs(PROFILE) do def[k] = v end
    def.key = coat.key
    def.engineBreed = coat.engine
    def.nameKey = "IGUI_PD_Breed_" .. coat.key
    def.spawns = {
        { id = coat.key .. "farm", class = "farm", suffix = coat.farm, breed = coat.key, indoor = 25,
          chance = function()
              return (CD.BLOCKY_FARM_CHANCE / CD.BLOCKY_COAT_COUNT) * spawnMultiplier()
          end },
        { id = coat.key .. "petvet", class = "petvet", suffix = coat.petvet, breed = coat.key,
          indoor = 80,
          chance = function()
              return (CD.BLOCKY_PETVET_CHANCE / CD.BLOCKY_COAT_COUNT) * spawnMultiplier()
          end },
    }
    CD.registerBreed(def)
end
