-- CompanionDogsBlockyAlpaca: 动物定义（成长阶段 / 毛色 / 三个性别年龄类型 / 头像相机）
--
-- 与写实羊驼（CompanionDogsAlpaca/AlpacaDefinitions.lua）是**同一物种的两套造型**：
-- 物种键仍是 "alpaca"、阶段表与品种表都挂在同一个物种下，只是新增三个动物类型
-- <typePrefix>bky 与它们自己的网格 BlockyAlpaca_Body。
--
-- 三条硬规则（都来自官方手册与 base 代码，写实羊驼那份踩过）：
--   1) animset 必须保持 "raccoon"：fork 出去的 animset 名字不会加载状态机，动物会原地冻结；
--   2) 不要声明 mate：引擎的原生交配会绕过 mod 的繁殖系统（base 在 OnGameBoot 会清掉它）；
--   3) AnimalDefinitions 必须在本文件的顶层（shared 阶段）就建好。
if not (CompanionDogs and (CompanionDogs.applyCompanionModel or CompanionDogs.applyDogModel)
        and (CompanionDogs.COMPANION_SOUNDS or CompanionDogs.DOG_SOUNDS)) then
    return
end

local CD = CompanionDogs

-- 新名优先、旧名兜底：万一 Steam 先更新了 addon 后更新 base，用新名做 guard 会让三个类型全部消失。
local applyModel = CD.applyCompanionModel or CD.applyDogModel
local applyBehaviour = CD.applyCompanionBehaviour or CD.applyDogBehaviour
local applyAvatar = CD.applyCompanionAvatar or CD.applyDogAvatar
local baseSounds = CD.COMPANION_SOUNDS or CD.DOG_SOUNDS
local blockyGenes = (CD.defineGenome and CD.defineGenome("alpaca")) or AnimalDefinitions.genome["dog"].genes

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.genome = AnimalDefinitions.genome or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

-- ---------------------------------------------------------------- 成长阶段
-- 追加到物种 "alpaca" 的阶段表（写实羊驼已经建好这张表与表名）。
AnimalDefinitions.stages["alpaca"] = AnimalDefinitions.stages["alpaca"] or { stages = {} }
local stages = AnimalDefinitions.stages["alpaca"].stages
stages["bkypup"] = { ageToGrow = 3 * 30, nextStage = "bkyfemale", nextStageMale = "bkymale" }
stages["bkyfemale"] = { ageToGrow = 3 * 30 }
stages["bkymale"] = { ageToGrow = 3 * 30 }

-- ---------------------------------------------------------------- 毛色（引擎品种）
-- 追加到物种 "alpaca" 的品种表：引擎按 <type>.<engineBreed> 取 texture，
-- 与写实羊驼同表可以让"同物种不同造型"共用同一套查找路径（这也是写实羊驼已经验证过的路径）。
AnimalDefinitions.breeds["alpaca"] = AnimalDefinitions.breeds["alpaca"] or { breeds = {} }
local breeds = AnimalDefinitions.breeds["alpaca"].breeds

-- 这份表与 CompanionDogsBlockyAlpaca_Breed.lua 是同一事实的两处写法（加载顺序不确定，不能互依赖）。
local COATS = {
    { engine = "blocky_cream", texture = "BlockyAlpaca" },
    { engine = "blocky_brown", texture = "BlockyAlpaca_Brown" },
    { engine = "blocky_gray",  texture = "BlockyAlpaca_Gray" },
    { engine = "blocky_spot",  texture = "BlockyAlpaca_Spot" },
}

for _, coat in ipairs(COATS) do
    local b = {}
    b.name = coat.engine
    b.texture = coat.texture
    b.textureMale = coat.texture
    b.rottenTexture = "Raccoon_Rotting"
    -- 背包图标复用本 addon 自己的偶蹄图标（贴图名全局解析，所以拷了一份并改名，避免和写实羊驼重名）
    b.invIconMale = "CDBlockyHoof_64"
    b.invIconFemale = "CDBlockyHoof_64"
    b.invIconBaby = "CDBlockyHoof_64"
    b.invIconMaleDead = "CDBlockyHoofDead_64"
    b.invIconFemaleDead = "CDBlockyHoofDead_64"
    b.invIconBabyDead = "CDBlockyHoofDead_64"
    b.invIconMaleSkel = "Item_Skeleton_Raccoon"
    b.invIconFemaleSkel = "Item_Skeleton_Raccoon"
    b.invIconBabySkel = "Item_Skeleton_Raccoon"
    breeds[coat.engine] = b
end

-- ---------------------------------------------------------------- 三个类型
-- 尺寸语义：minSize = 0 天大时的模型缩放，maxSize = 长成且养得好时的缩放，单位是米。
-- 方块网格的**静止高度是 0.5589 单位**（make_blocky_alpaca.py 会打印；写实羊驼是 0.4523），
-- 所以这里把写实那套尺寸按 0.4523/0.5589 = 0.809 等比缩小，
-- 让方块羊驼和写实羊驼在世界上一样高（同物种不该因为造型不同而变大变小）：
--   成年 2.10~2.71 ⇒ 头顶 1.17~1.51 m、肩高约 0.88~1.13 m。
local SIZE_PUP_MIN, SIZE_PUP_MAX = 1.21, 2.10
local SIZE_F_MIN, SIZE_F_MAX = 2.10, 2.55
local SIZE_M_MIN, SIZE_M_MAX = 2.18, 2.71

local pup = {}
applyModel(pup, "BlockyAlpaca_Body")
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
pup.genes = blockyGenes
AnimalDefinitions.animals["bkypup"] = pup

local female = {}
applyModel(female, "BlockyAlpaca_Body")
applyBehaviour(female)
female.group = "alpaca"
female.female = true
-- 故意不写 mate（同写实羊驼：引擎原生交配会绕过 mod 的繁殖与沙盒开关）
female.babyType = "bkypup"
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
female.genes = blockyGenes
AnimalDefinitions.animals["bkyfemale"] = female

local male = {}
applyModel(male, "BlockyAlpaca_Body")
applyBehaviour(male)
male.group = "alpaca"
male.male = true
male.babyType = "bkypup"
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
male.genes = blockyGenes
AnimalDefinitions.animals["bkymale"] = male

-- ---------------------------------------------------------------- 叫声
-- sounds 挂在 breeds[<组>].breeds[<engineBreed>] 上，对该型三个类型一起生效。
-- 音名沿用写实羊驼注册的那套（本 addon 硬依赖它，不重复注册声音、也不带音频文件）。
local blockySounds = {}
for k, v in pairs(baseSounds) do blockySounds[k] = v end
blockySounds.pain = { name = "CDAlpacaWhine", slot = "voice", priority = 50 }
blockySounds.death = { name = "CDAlpacaDeath", slot = "voice", priority = 100 }
blockySounds.pick_up = { name = "CDAlpacaPickup", slot = "voice", priority = 1 }
blockySounds.put_down = blockySounds.pick_up
for _, coat in ipairs(COATS) do
    breeds[coat.engine].sounds = blockySounds
end

-- ---------------------------------------------------------------- 头像相机
-- 体型比 = (方块网格 0.5589 单位 x 成年 size 2.10) / (金毛 0.3492 单位 x 1.50) ≈ 2.24
-- （与写实羊驼相同的比值：因为尺寸就是按"世界高度一致"反推的）。
local SIZE_RATIO = 2.24
AnimalAvatarDefinition = AnimalAvatarDefinition or {}
for _, atype in ipairs({ "bkypup", "bkyfemale", "bkymale" }) do
    AnimalAvatarDefinition[atype] = {}
    applyAvatar(AnimalAvatarDefinition[atype])
end
for _, atype in ipairs({ "bkypup", "bkyfemale", "bkymale" }) do
    local t = AnimalAvatarDefinition[atype]
    t.zoom = 10 / SIZE_RATIO
    t.trailerZoom = 8.5 / SIZE_RATIO
    t.xoffset = t.xoffset * SIZE_RATIO
    t.yoffset = t.yoffset * SIZE_RATIO
    t.trailerXoffset = t.trailerXoffset * SIZE_RATIO
    t.trailerYoffset = t.trailerYoffset * SIZE_RATIO
end
