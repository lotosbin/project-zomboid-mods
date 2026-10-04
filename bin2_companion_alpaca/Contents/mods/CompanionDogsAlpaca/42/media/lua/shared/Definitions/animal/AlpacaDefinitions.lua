-- CompanionDogsAlpaca: 动物定义（成长阶段 / 毛色 / 三个性别年龄类型 / 头像相机）
--
-- 契约见 CompanionDogs 官方 addon 手册第 7 节：引擎把网格绑在**动物类型**上而不是品种上，
-- 所以新物种必须有自己的一套 <typePrefix>pup / <typePrefix>female / <typePrefix>male。
-- 本文件的三条硬规则（都来自手册与 base 代码）：
--   1) animset 必须保持 "raccoon"：fork 出去的 animset 名字不会加载状态机，动物会原地冻结；
--   2) 不要声明 mate：引擎的原生交配会绕过 mod 的繁殖系统，base 在 OnGameBoot 会清掉它；
--   3) AnimalDefinitions 必须在本文件的顶层（shared 阶段）就建好，否则 OnGameBoot 清 mate 时看不到。
if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end

local CD = CompanionDogs

-- 物种中性名（API 7）与旧名兼容取值。guard 故意用**旧名**：万一 Steam 先更新了 addon、
-- 后更新 base，用新名做 guard 会让本文件提前 return，三个类型全部消失，引擎会把整格动物数据删掉。
local applyModel = CD.applyCompanionModel or CD.applyDogModel
local applyBehaviour = CD.applyCompanionBehaviour or CD.applyDogBehaviour
local applyAvatar = CD.applyCompanionAvatar or CD.applyDogAvatar
local baseSounds = CD.COMPANION_SOUNDS or CD.DOG_SOUNDS
local alpacaGenes = (CD.defineGenome and CD.defineGenome("alpaca")) or AnimalDefinitions.genome["dog"].genes

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.genome = AnimalDefinitions.genome or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

-- ---------------------------------------------------------------- 成长阶段
AnimalDefinitions.stages["alpaca"] = { stages = {} }
local stages = AnimalDefinitions.stages["alpaca"].stages
stages["alpacapup"] = { ageToGrow = 3 * 30, nextStage = "alpacafemale", nextStageMale = "alpacamale" }
stages["alpacafemale"] = { ageToGrow = 3 * 30 }
stages["alpacamale"] = { ageToGrow = 3 * 30 }

-- ---------------------------------------------------------------- 毛色（引擎品种）
AnimalDefinitions.breeds["alpaca"] = { breeds = {} }
local breeds = AnimalDefinitions.breeds["alpaca"].breeds

-- engineBreed 决定贴图：media/textures/Body/<texture>.png，全家族共用 typePrefix "alpaca"（网格）。
-- engineBreed 必须每色唯一：base 用它反查品种（CD.BREED_BY_ENGINE），重名会让两只不同的羊驼
-- 在 ModData 缺失时被认成同一个品种。
--
-- 注意：这份毛色表与 CompanionDogsAlpaca_Breed.lua 里的品种表是**同一个事实的两处写法** ——
-- 同目录两份文件谁先加载取决于引擎对路径排序，不能互相依赖（CD: Cats 也是这么处理的）。
-- 客户端 moodle 文件里有一致性检查，对不上会在日志里报出来。
local COATS = {
    { engine = "alpaca",        texture = "Alpaca" },
    { engine = "alpaca_fawn",   texture = "Alpaca_Fawn" },
    { engine = "alpaca_brown",  texture = "Alpaca_Brown" },
    { engine = "alpaca_black",  texture = "Alpaca_Black" },
    { engine = "alpaca_grey",   texture = "Alpaca_Grey" },
    { engine = "alpaca_rose",   texture = "Alpaca_RoseGrey" },
    { engine = "alpaca_suri",   texture = "Alpaca_Suri" },
}

for _, coat in ipairs(COATS) do
    local b = {}
    b.name = coat.engine
    b.texture = coat.texture
    b.textureMale = coat.texture
    b.rottenTexture = "Raccoon_Rotting"
    -- 偶蹄图标是本地生成的（tools/alpaca/make_icons.py），不是 base 的狗爪
    b.invIconMale = "CDAlpacaHoof_64"
    b.invIconFemale = "CDAlpacaHoof_64"
    b.invIconBaby = "CDAlpacaHoof_64"
    b.invIconMaleDead = "CDAlpacaHoofDead_64"
    b.invIconFemaleDead = "CDAlpacaHoofDead_64"
    b.invIconBabyDead = "CDAlpacaHoofDead_64"
    b.invIconMaleSkel = "Item_Skeleton_Raccoon"
    b.invIconFemaleSkel = "Item_Skeleton_Raccoon"
    b.invIconBabySkel = "Item_Skeleton_Raccoon"
    breeds[coat.engine] = b
end

-- ---------------------------------------------------------------- 三个类型
-- 尺寸语义（原版 CowDefinitions.lua 的注释 + base 的用法）：
--   minSize = 0 天大时的模型缩放，maxSize = 走完 stage.ageToGrow 且吃好喝好时的模型缩放，
--   单位就是米（金毛 1.5~2.15 对应 0.52~0.75 m 肩高，模型量出来 0.3492 单位高）。
--   本模型（CC0 羊驼网格传递到本骨架后）的静止高度是 **0.4523 单位**（validate_glb.py 会打印），
--   所以成年 size≈2.6~3.35 ⇒ 头顶 1.18~1.51 m、肩高约 0.88~1.13 m，与真羊驼一致。
local SIZE_PUP_MIN, SIZE_PUP_MAX = 1.50, 2.60
local SIZE_F_MIN, SIZE_F_MAX = 2.60, 3.15
local SIZE_M_MIN, SIZE_M_MAX = 2.70, 3.35

local pup = {}
applyModel(pup, "Alpaca_Body")
applyBehaviour(pup)
pup.group = "alpaca"                    -- 必须在 applyBehaviour 之后覆写：它一律写 "dog"
pup.shadoww = 0.34
pup.shadowfm = 0.52
pup.shadowbm = 0.52
pup.minSize = SIZE_PUP_MIN
pup.maxSize = SIZE_PUP_MAX
pup.wanderMul = 500
pup.hungerMultiplier = 0.002
pup.thirstMultiplier = 0.004
pup.hungerBoost = 25
pup.thirstBoost = 30
pup.baseEncumbrance = 12
pup.trailerBaseSize = 30
pup.minEnclosureSize = 60
pup.needMom = false
pup.eatFromMother = true
pup.litterEatTogether = true
pup.minWeight = 8
pup.maxWeight = 15
pup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
pup.breeds = breeds
pup.stages = stages
pup.genes = alpacaGenes
AnimalDefinitions.animals["alpacapup"] = pup

local female = {}
applyModel(female, "Alpaca_Body")
applyBehaviour(female)
female.group = "alpaca"
female.female = true
-- 故意不写 mate：引擎的原生交配会绕过 mod 的繁殖与沙盒开关（base 在 OnGameBoot 里清，别再加回来）
female.babyType = "alpacapup"
female.shadoww = 0.45
female.shadowfm = 0.70
female.shadowbm = 0.70
female.minSize = SIZE_F_MIN
female.maxSize = SIZE_F_MAX
female.wanderMul = 600
female.hungerMultiplier = 0.011
female.thirstMultiplier = 0.020
female.hungerBoost = 22
female.thirstBoost = 28
female.baseEncumbrance = 45          -- 驮兽：狗的 baseEncumbrance 是 20
female.trailerBaseSize = 90
female.minEnclosureSize = 60
female.minAge = 3 * 30
female.maxAgeGeriatric = 20 * 30
female.minAgeForBaby = 3 * 30
female.timeBeforeNextPregnancy = 7
female.pregnantPeriod = 35
female.minWeight = 55
female.maxWeight = 75
female.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
female.breeds = breeds
female.stages = stages
female.genes = alpacaGenes
AnimalDefinitions.animals["alpacafemale"] = female

local male = {}
applyModel(male, "Alpaca_Body")
applyBehaviour(male)
male.group = "alpaca"
male.male = true
male.babyType = "alpacapup"
male.dontAttackOtherMale = true
male.shadoww = 0.45
male.shadowfm = 0.70
male.shadowbm = 0.70
male.minSize = SIZE_M_MIN
male.maxSize = SIZE_M_MAX
male.wanderMul = 600
male.hungerMultiplier = 0.011
male.thirstMultiplier = 0.020
male.hungerBoost = 22
male.thirstBoost = 28
male.baseEncumbrance = 55
male.trailerBaseSize = 100
male.minEnclosureSize = 60
male.minAge = 3 * 30
male.maxAgeGeriatric = 20 * 30
male.minAgeForBaby = 3 * 30
male.minWeight = 65
male.maxWeight = 90
male.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
male.breeds = breeds
male.stages = stages
male.genes = alpacaGenes
AnimalDefinitions.animals["alpacamale"] = male

-- ---------------------------------------------------------------- 叫声
-- sounds 挂在 breeds[<组>].breeds[<engineBreed>] 上，对该组三个类型一起生效。
local alpacaSounds = {}
for k, v in pairs(baseSounds) do alpacaSounds[k] = v end
alpacaSounds.pain = { name = "CDAlpacaWhine", slot = "voice", priority = 50 }
alpacaSounds.death = { name = "CDAlpacaDeath", slot = "voice", priority = 100 }
alpacaSounds.pick_up = { name = "CDAlpacaPickup", slot = "voice", priority = 1 }
alpacaSounds.put_down = alpacaSounds.pick_up
for _, coat in ipairs(COATS) do
    breeds[coat.engine].sounds = alpacaSounds
end

-- ---------------------------------------------------------------- 头像相机
-- 手册第 7 节：zoom 是放大倍数，越小体型的动物要越大的数字；offset 按体型比例乘。
-- 体型比 = (本模型 0.4523 单位 x 成年 size 2.60) / (金毛 0.3492 单位 x 1.50) ≈ 2.24。
local SIZE_RATIO = 2.24
AnimalAvatarDefinition = AnimalAvatarDefinition or {}
for _, atype in ipairs({ "alpacapup", "alpacafemale", "alpacamale" }) do
    AnimalAvatarDefinition[atype] = {}
    applyAvatar(AnimalAvatarDefinition[atype])
end
for _, atype in ipairs({ "alpacapup", "alpacafemale", "alpacamale" }) do
    local t = AnimalAvatarDefinition[atype]
    t.zoom = 10 / SIZE_RATIO
    t.trailerZoom = 8.5 / SIZE_RATIO
    t.xoffset = t.xoffset * SIZE_RATIO
    t.yoffset = t.yoffset * SIZE_RATIO
    t.trailerXoffset = t.trailerXoffset * SIZE_RATIO
    t.trailerYoffset = t.trailerYoffset * SIZE_RATIO
end
