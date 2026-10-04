-- ===========================================================================
-- mock_base.lua —— Companion Dogs base API 的忠实 mock（离线测试用）
-- ===========================================================================
--
-- 目的：在没有游戏的情况下，把 addon 依赖的 base 契约复刻成一个可断言的 Lua 环境。
--
-- 忠实度来源（都是直接照抄 base 源码，路径见下）：
--   $CD/shared/CompanionDogs/skills/BreedAPI.lua   -> registerBreed / onUpkeepStress
--   $CD/shared/CompanionDogs/skills/Species.lua    -> registerSpecies
--   $CD/shared/CompanionDogs/config/Needs.lua      -> registerVoices / SOUND_* / MOODLE_NEGLECT_MAX
--   $CD/shared/CompanionDogs/config/Base.lua       -> TYPES
--   $CD/shared/CompanionDogs/skills/Skills.lua     -> SKILLS / BREEDS / BREED_BY_ENGINE
--   $CD/shared/Definitions/animal/DogDefinitions.lua -> applyDog* / defineGenome / DOG_SOUNDS
--   $CD/shared/Definitions/animal/CompanionDogs_Parts.lua -> defineDogParts
--   $CD/client/CompanionDogs_Moodles.lua           -> DogMoodles 的形状
--   $CD/core/{Status,Mood}.lua, config/{Diet,SpawnRegistry,Sandbox}.lua
--   $CD = ~/Library/Application Support/Steam/steamapps/workshop/content/108600/3740052292
--         /mods/CompanionDogs/42/media/lua
--
-- 约定：
--   * 所有"被调用过"的公开 API 都往 MOCK.calls 里按**调用顺序**追加一条记录，
--     测试据此断言 registerVoices 早于第一次 registerBreed。
--   * CD.log 不直接打印，只收进 MOCK.logs，测试最后统一 dump 并做禁忌词检查。
--   * 校验类函数（registerBreed / registerSpecies / registerVoices）的**行为**照抄 base，
--     包括拒绝时返回 nil 并 CD.log。其余函数是"记录调用 + 返回合理值"。

-- ---------------------------------------------------------------- 记录表
MOCK = {
    -- CD.log 的输出（顺序）
    logs = {},
    -- 全部被记录到的调用，按顺序：{ name = ..., ... }
    calls = {},
    -- registerBreed 的逐次调用：{ key=, status="ok"|"refused"|"duplicate", arg=, missing= }
    registerBreedCalls = {},
    -- 通过校验并写入 CD.BREEDS 的 key 集合
    breedAccepted = {},
    -- defineDogParts/defineCompanionParts 的逐次调用
    definePartsCalls = {},
    -- registerStraySpawns 收到的 spawn 表（累加）
    straySpawnDefs = {},
    -- defineGenome 的逐次调用
    genomeCalls = {},
    -- applyDogModel / applyDogBehaviour / applyDogAvatar 的逐次调用
    modelCalls = {},
    behaviourCalls = {},
    avatarCalls = {},
    -- relieveMood 的逐次调用
    relieveMoodCalls = {},
    -- 计数器（断言"重建了索引""清了缓存"这类副作用真的发生过）
    rebuildBreedOrderCount = 0,
    rebuildEngineIndexCount = 0,
    clearDietCacheCount = 0,
    -- addon 加载前的基线，加载后测试断言"恰好追加 1 条"
    moodleCountBefore = 0,
    upkeepCountBefore = 0,
    -- 测试可以拨动的开关（模拟"不忠/生病"这些 base 状态）
    disloyal = false,
    sick = false,
    -- 气候桩开关：temp 是摄氏温度，nilManager 模拟 getClimateManager() 返回 nil，
    -- throwOnRead 模拟引擎在取温度时抛异常（用来验证 addon 自己的 pcall）。
    climate = { temp = 20, nilManager = false, throwOnRead = false },
}

local function record(name, entry)
    entry = entry or {}
    entry.name = name
    MOCK.calls[#MOCK.calls + 1] = entry
    return entry
end
MOCK.record = record

-- ---------------------------------------------------------------- 引擎桩
-- SandboxVars：addon 的沙盒倍率（media/sandbox-options.txt 的 AlpacaSpawnMultiplier）
SandboxVars = {
    CompanionAlpaca = { AlpacaSpawnMultiplier = 1.0 },
}

-- CharacterStat：Moodle 的 apply 会写 CharacterStat.STRESS
CharacterStat = { STRESS = 1, UNHAPPINESS = 2, BOREDOM = 3, PANIC = 4, FATIGUE = 5, ENDURANCE = 6 }

-- IsoDirections：base 的 applyDogAvatar 会写 SE/SW
IsoDirections = { N = 1, NE = 2, E = 3, SE = 4, S = 5, SW = 6, W = 7, NW = 8 }

-- 原版引擎的全局表（base 与 addon 都会在外层 `or {}` 兜底，这里给初始值，跟游戏里一致）
AnimalDefinitions = AnimalDefinitions or {}
AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalPartsDefinitions = AnimalPartsDefinitions or { animals = {} }

--- 翻译桩：base 的 *_noun 系列会用它，addon 本身不直接调。
function getText(key) return key end

--- 气候桩：addon 的 CD.alpacaAirTemp 走 getClimateManager()。
function getClimateManager()
    local cfg = MOCK.climate
    if cfg.nilManager then return nil end
    local cm = {}
    function cm:getAirTemperatureForCharacter(char, indoor)
        if cfg.throwOnRead then error("mock: climate read failed", 0) end
        return cfg.temp
    end
    function cm:getTemperature()
        if cfg.throwOnRead then error("mock: climate read failed", 0) end
        return cfg.temp
    end
    return cm
end

-- ---------------------------------------------------------------- CD
CompanionDogs = {}
local CD = CompanionDogs

CD.API_VERSION = 11
CD.DEFAULT_SPECIES = "dog"
CD.DEFAULT_BREED = "caramelo"
CD.BREED = "brown" -- engine 缺省回落

---@param msg string
function CD.log(msg)
    MOCK.logs[#MOCK.logs + 1] = tostring(msg)
end

-- ---------------------------------------------------------------- 声音表（照抄 Needs.lua）
CD.BARK_SOUND = "CDDogBark"
CD.GROWL_SOUND = "CDDogGrowl"
CD.PET_SOUND = "CDDogPet"
CD.WILD_BARK_SOUND = "CDDogBarkAmbient"
CD.IDLE_VOICE_SOUND = "CDDogIdle"

CD.SOUND_CATEGORY = {
    CDDogBark = "bark", CDDogGrowl = "bark",
    CDDogIdle = "bark", CDDogWhine = "bark", CDDogDeath = "bark", CDDogPickup = "bark",
    ZombieBite = "fx", CDDogEat = "fx", CDDogDrink = "fx", CDDogPet = "fx",
    CDDogBarkAmbient = "ambient",
}
CD.SOUND_CATEGORIES = { "bark", "fx", "ambient" }

CD.SOUND_NONBANK = {
    CDDogBark = true, CDDogBarkAmbient = true, CDDogGrowl = true, CDDogWhine = true, CDDogIdle = true,
    CDDogPickup = true, CDDogPet = true, CDDogDeath = true, CDDogEat = true, CDDogDrink = true,
}
CD.SOUND_LOOPED = { CDDogEat = true, CDDogDrink = true }

CD.SOUND_RANGE = {
    CDDogBark = 30, CDDogBarkAmbient = 30, CDDogDeath = 25, CDDogWhine = 15, CDDogGrowl = 12,
    CDDogPet = 12, CDDogIdle = 10, CDDogEat = 10, CDDogDrink = 10, CDDogPickup = 8,
    ZombieBite = 20, ChickenCoopWoodClose = 15, ChickenCoopWoodOpen = 15,
}
CD.SOUND_RANGE_BY_CAT = { bark = 30, fx = 12, ambient = 30 }
CD.SOUND_RANGE_DEFAULT = 30
CD.SOUND_RANGE_MARGIN = 8

CD.ENGINE_VOICES = { "CDDogWhine", "CDDogDeath", "CDDogPickup" }

CD.VOICE_DEFAULT = {
    bark     = CD.BARK_SOUND,
    growl    = CD.GROWL_SOUND,
    idle     = CD.IDLE_VOICE_SOUND,
    wildbark = CD.WILD_BARK_SOUND,
    pet      = CD.PET_SOUND,
    whine    = "CDDogWhine",
    eat      = "CDDogEat",
    drink    = "CDDogDrink",
}

--- 照抄 base Needs.lua:76 的行为：没有任何校验，只写四张表。
---@param map table<string, string> sound name -> volume category
---@param engineVoices string[]|nil engine sounds the player's mute also silences
---@param ranges table<string, number>|nil sound name -> audible range in tiles
function CD.registerVoices(map, engineVoices, ranges)
    local call = record("registerVoices", { map = map, engineVoices = engineVoices, ranges = ranges })
    if type(map) ~= "table" then
        call.status = "refused"
        call.reason = "map is not a table"
        return
    end
    for name, cat in pairs(map) do
        CD.SOUND_CATEGORY[name] = cat
        CD.SOUND_NONBANK[name] = true
    end
    if type(ranges) == "table" then
        for name, r in pairs(ranges) do
            CD.SOUND_RANGE[name] = r
        end
    end
    if type(engineVoices) == "table" then
        for i = 1, #engineVoices do
            CD.ENGINE_VOICES[#CD.ENGINE_VOICES + 1] = engineVoices[i]
        end
    end
    call.status = "ok"
end

-- ---------------------------------------------------------------- 物种（照抄 Species.lua:16）
CD.SPECIES = {
    dog = { key = "dog", nounKey = "IGUI_PD_DogNoun", youngKey = "IGUI_PD_Puppy",
            labelKey = "IGUI_PD_SpeciesDisplay_dog" },
}

---@param def table { key, nounKey, youngKey, labelKey? }
---@return table|nil def the registered entry; nil when refused
function CD.registerSpecies(def)
    local call = record("registerSpecies", { arg = def })
    if type(def) ~= "table" or not def.key then
        call.status = "refused"
        CD.log("registerSpecies: recusado, argumento nao e tabela ou nao tem 'key'")
        return nil
    end
    if CD.SPECIES[def.key] then
        call.status = "duplicate"
        CD.log("registerSpecies: a chave de especie '" .. tostring(def.key) ..
               "' JA existe; o registro novo foi ignorado (dois addons disputando a mesma chave?)")
        return CD.SPECIES[def.key]
    end
    for _, field in ipairs({ "nounKey", "youngKey" }) do
        if type(def[field]) ~= "string" then
            call.status = "refused"
            call.missing = field
            CD.log("registerSpecies: especie '" .. tostring(def.key) .. "' recusada, falta o campo '" ..
                   field .. "' (API_VERSION " .. tostring(CD.API_VERSION) .. ")")
            return nil
        end
    end
    CD.SPECIES[def.key] = def
    call.status = "ok"
    return def
end

-- ---------------------------------------------------------------- 技能 / 品种基础表
CD.SKILLS = { "scent", "combat", "obedience", "hunt", "herding" }
CD.HUNT_PREY_RANK = { tiny = 1, small = 2, large = 3 }

CD.TYPES = {
    dogpup = true, dogfemale = true, dogmale = true,
    gspup = true, gsfemale = true, gsmale = true,
    retrieverpup = true, retrieverfemale = true, retrievermale = true,
    huskypup = true, huskyfemale = true, huskymale = true,
    bcpup = true, bcfemale = true, bcmale = true,
}

-- 只保留 base 自己那 5 个品种（Skills.lua:13）：key / engineBreed / typePrefix 是真的，
-- 其余字段对 addon 的注册流程没有影响，但要让 rebuildEngineIndex 与重复检查有东西可查。
local BASE_REQUIRED = {
    xpMult = { scent = 1, combat = 1, obedience = 1, hunt = 1, herding = 1 },
    combatPower = 0.2, lethalityCurve = { min = 0.4, max = 1.5 },
    geneRange = { strength = { 0, 0.15 }, aggressiveness = { 0, 0.15 },
                  resistance = { 0, 0.15 }, stress = { 0, 0.15 } },
    skills = { hunt = true }, canKill = false, canKnockdown = true,
}
local function baseBreed(key, engineBreed, typePrefix)
    local d = {}
    for k, v in pairs(BASE_REQUIRED) do d[k] = v end
    d.key = key
    d.engineBreed = engineBreed
    d.typePrefix = typePrefix
    d.species = "dog"
    d.nameKey = "IGUI_PD_Breed_" .. key
    d.puppySize = 1.0
    d.spawns = {}
    d.diet = { replace = true }
    return d
end

CD.BREEDS = {
    caramelo = baseBreed("caramelo", "brown", "dog"),
    germanshepherd = baseBreed("germanshepherd", "germanshepherd", "gs"),
    retriever = baseBreed("retriever", "golden", "retriever"),
    husky = baseBreed("husky", "husky", "husky"),
    bordercollie = baseBreed("bordercollie", "bordercollie", "bc"),
}

CD.DIET_FIELDS = {
    bad = "set", badParts = "parts",
    protein = "set", proteinParts = "parts",
    nonProtein = "set",
    trough = "set", troughItems = "set",
}
CD.DIET_CACHE = {}

function CD.clearDietCache()
    MOCK.clearDietCacheCount = MOCK.clearDietCacheCount + 1
    CD.DIET_CACHE = {}
end

function CD.rebuildBreedOrder()
    MOCK.rebuildBreedOrderCount = MOCK.rebuildBreedOrderCount + 1
    local order = {}
    for bk in pairs(CD.BREEDS) do order[#order + 1] = bk end
    table.sort(order)
    CD.BREED_ORDER = order
end

CD.BREED_BY_ENGINE = {}
function CD.rebuildEngineIndex()
    MOCK.rebuildEngineIndexCount = MOCK.rebuildEngineIndexCount + 1
    local idx = {}
    for key, def in pairs(CD.BREEDS) do
        if def.engineBreed then idx[def.engineBreed] = key end
    end
    CD.BREED_BY_ENGINE = idx
end
CD.rebuildEngineIndex()
CD.rebuildBreedOrder()

CD.StraySpawnDefs = {}
---@param list table[] each entry { id, class, chance = fun(): number, breed?, suffix?, gate?, indoor? }
function CD.registerStraySpawns(list)
    local call = record("registerStraySpawns", { list = list })
    if type(list) ~= "table" then
        call.status = "refused"
        return
    end
    for _, sdef in ipairs(list) do
        if sdef.id and sdef.class and type(sdef.chance) == "function" then
            CD.StraySpawnDefs[#CD.StraySpawnDefs + 1] = sdef
            MOCK.straySpawnDefs[#MOCK.straySpawnDefs + 1] = sdef
        end
    end
    call.status = "ok"
end

-- base 自己也注册了一条（caramelo|house），让"追加 14 条"这种断言有意义
CD.registerStraySpawns({ { id = "caramelo", class = "house", chance = function() return 3 end, indoor = 35 } })

-- ---------------------------------------------------------------- registerBreed
-- 照抄 BreedAPI.lua:36 的校验与副作用顺序。这里包含 addon 会走到的全部分支：
--   key 缺失 / key 重复 / 6 个必填字段 / huntMaxPrey / maleChance / sterileMale
--   voices / species / skills / diet / engineBreed 重复，最后写 BREEDS + TYPES + 索引 + spawn。
---@param def table
---@return table|nil def
function CD.registerBreed(def)
    local call = record("registerBreed", { arg = def })
    MOCK.registerBreedCalls[#MOCK.registerBreedCalls + 1] = call

    if type(def) ~= "table" or not def.key then
        call.status = "refused"
        CD.log("registerBreed: recusado, argumento nao e tabela ou nao tem 'key'")
        return nil
    end
    call.key = def.key

    if CD.BREEDS[def.key] then
        call.status = "duplicate"
        CD.log("registerBreed: a chave de raca '" .. tostring(def.key) ..
               "' JA existe; o registro novo foi ignorado (dois addons disputando a mesma chave?)")
        return CD.BREEDS[def.key]
    end

    for _, field in ipairs({ "typePrefix", "nameKey", "xpMult", "combatPower", "lethalityCurve", "geneRange" }) do
        if def[field] == nil then
            call.status = "refused"
            call.missing = field
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' recusada, falta o campo '" ..
                   field .. "' (API_VERSION " .. tostring(CD.API_VERSION) .. ")")
            return nil
        end
    end

    if def.huntMaxPrey ~= nil and CD.HUNT_PREY_RANK[def.huntMaxPrey] == nil then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou huntMaxPrey='" ..
               tostring(def.huntMaxPrey) .. "', que nao e tiny/small/large; caindo em 'large' (sem teto)")
        def.huntMaxPrey = nil
    end

    if def.maleChance ~= nil then
        if type(def.maleChance) ~= "number" or def.maleChance < 0 or def.maleChance > 1 then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou maleChance='" ..
                   tostring(def.maleChance) .. "', que nao e um numero de 0 a 1 (0.25 e 25%, nao 25); " ..
                   "caindo no meio a meio")
            def.maleChance = nil
        end
    end

    if def.sterileMale ~= nil and type(def.sterileMale) ~= "boolean" then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou sterileMale que nao e " ..
               "booleano; o macho dela continua cruzando")
        def.sterileMale = nil
    end

    if type(def.voices) == "table" and type(CD.VOICE_DEFAULT) == "table" then
        local valid = {}
        for k in pairs(CD.VOICE_DEFAULT) do valid[k] = true end
        for k, v in pairs(def.voices) do
            if not valid[k] then
                local validNames = {}
                for kk in pairs(valid) do validNames[#validNames + 1] = kk end
                table.sort(validNames)
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou voices['" .. tostring(k) ..
                       "'], que nao e uma voz do mod; sera ignorado (as validas sao " ..
                       table.concat(validNames, ", ") .. ")")
            elseif CD.SOUND_CATEGORY and CD.SOUND_CATEGORY[v] == nil then
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' usa o som '" .. tostring(v) ..
                       "' em voices." .. tostring(k) .. " sem te-lo passado por CD.registerVoices; ele vai " ..
                       "tocar por fora do volume e do mute do jogador")
            end
        end
    end

    if def.species ~= nil then
        if type(def.species) ~= "string" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou species que nao e texto; " ..
                   "sera ignorado e a raca conta como cao (o formato e species = \"cat\")")
            def.species = nil
        elseif CD.SPECIES and CD.SPECIES[def.species] == nil then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou species='" ..
                   tostring(def.species) .. "', que ninguem registrou com CD.registerSpecies; ela nao cruza " ..
                   "com outra especie, mas a UI vai chama-la de cao")
        end
    end

    if type(def.skills) == "table" then
        local known = {}
        for _, s in ipairs(CD.SKILLS) do known[s] = true end
        for k in pairs(def.skills) do
            if not known[k] then
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou skills['" .. tostring(k) ..
                       "'], que nao e uma skill do mod; sera ignorado (as validas sao " ..
                       table.concat(CD.SKILLS, ", ") .. ")")
            end
        end
        if def.skills.scent == false and def.alertModeLocked == true then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou skills.scent=false JUNTO com " ..
                   "alertModeLocked=true, que se contradizem; sem Faro nao ha sentinela pra travar, entao o " ..
                   "alertModeLocked nao tem efeito")
        end
    end

    if def.diet ~= nil then
        if type(def.diet) ~= "table" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou diet que nao e tabela; " ..
                   "o formato e { bad = { <FoodType> = true } } e este foi ignorado")
            def.diet = nil
        else
            for field, kind in pairs(CD.DIET_FIELDS) do
                local sub = def.diet[field]
                if sub ~= nil then
                    if type(sub) ~= "table" then
                        CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                               " nao e uma tabela; o formato e { <chave> = true|false } e este campo foi ignorado")
                        def.diet[field] = nil
                    else
                        local rename = {}
                        for k, v in pairs(sub) do
                            if type(k) ~= "string" then
                                CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                                       " tem uma chave que nao e texto; ela foi ignorada")
                                sub[k] = nil
                            elseif type(v) ~= "boolean" then
                                CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                                       "['" .. k .. "'] nao e true nem false; a chave foi ignorada")
                                sub[k] = nil
                            elseif kind == "parts" and string.lower(k) ~= k then
                                rename[#rename + 1] = k
                            end
                        end
                        for i = 1, #rename do
                            local k = rename[i]
                            sub[string.lower(k)] = sub[k]
                            sub[k] = nil
                        end
                    end
                end
            end
        end
    end

    if def.engineBreed and CD.BREED_BY_ENGINE and CD.BREED_BY_ENGINE[def.engineBreed] then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou engineBreed='" ..
               tostring(def.engineBreed) .. "', que a raca '" .. tostring(CD.BREED_BY_ENGINE[def.engineBreed]) ..
               "' ja usa; com o ModData ausente as duas vao resolver para a mesma")
    end

    CD.BREEDS[def.key] = def
    CD.clearDietCache()
    CD.TYPES[def.typePrefix .. "pup"] = true
    CD.TYPES[def.typePrefix .. "female"] = true
    CD.TYPES[def.typePrefix .. "male"] = true
    CD.rebuildBreedOrder()
    CD.rebuildEngineIndex()
    if def.spawns and CD.registerStraySpawns then
        CD.registerStraySpawns(def.spawns)
    end

    call.status = "ok"
    call.def = def
    MOCK.breedAccepted[def.key] = true
    return def
end

-- base 的 onUpkeepStress 钩子（BreedAPI.lua:9-24）：**裸调用**，没有 pcall。
CD.onHuntDelivered = {}
CD.onUpkeepStress = {
    -- 种子里放一个 base 自己的 handler，让"恰好追加 1 个"是可断言的
    function(animal, needsStress) return 0 end,
}
function CD.upkeepStressDelta(animal, needsStress)
    local total = 0
    for i = 1, #CD.onUpkeepStress do
        local fn = CD.onUpkeepStress[i]
        if type(fn) == "function" then
            local delta = fn(animal, needsStress)
            if type(delta) == "number" then total = total + delta end
        end
    end
    return total
end

-- ---------------------------------------------------------------- 状态 / mood / moodle
---@param animal table
---@return string breedKey
function CD.getBreed(animal)
    if animal and animal.breed then return animal.breed end
    return CD.DEFAULT_BREED
end

function CD.isDisloyal(animal) return MOCK.disloyal == true end
function CD.isSick(animal) return MOCK.sick == true end

CD.MOODLE_NEGLECT_MAX = 0.75
CD.MOODLE_RELIEF_PER_MIN = 0.5

function CD.moodleReliefPerMin() return CD.MOODLE_RELIEF_PER_MIN end

---@param player table
---@param n number
function CD.relieveMood(player, n)
    local call = record("relieveMood", { player = player, n = n })
    call.status = "ok"
    MOCK.relieveMoodCalls[#MOCK.relieveMoodCalls + 1] = call
    if not player or not n or n <= 0 then return end
    local stats = player:getStats()
    if stats then
        stats:remove(CharacterStat.UNHAPPINESS, n)
        stats:remove(CharacterStat.BOREDOM, n)
    end
end

-- DogMoodles 的形状照抄 base CompanionDogs_Moodles.lua：先放两条 base 自己的。
CD.DogMoodles = {
    {
        id = "breedHappy", breed = "caramelo",
        nameKey = "IGUI_PD_Moodle_BreedHappy", descKey = "IGUI_PD_Moodle_BreedHappy_desc",
        icon = "CD_Moodle_BreedHappy", fg = "CD_MoodHappyFG",
        condition = function(player, dog) return 0 end,
        apply = function(player, dog, elapsedMin) end,
    },
    {
        id = "neglect", breed = "caramelo",
        nameKey = "IGUI_PD_Moodle_Neglect", descKey = "IGUI_PD_Moodle_Neglect_desc",
        icon = "CD_Moodle_Neglect", fg = "CD_MoodNeglectFG",
        tintR = 0.9, tintG = 0.3, tintB = 0.3,
        condition = function(player, dog) return 0 end,
        apply = function(player, dog, elapsedMin) end,
    },
}
CD.CompanionMoodles = CD.DogMoodles

-- ---------------------------------------------------------------- 定义表 API（照抄 DogDefinitions.lua）
CD.COMPANION_GENES = {
    "maxSize", "meatRatio", "maxWeight", "lifeExpectancy", "resistance", "strength",
    "hungerResistance", "thirstResistance", "aggressiveness", "ageToGrow", "fertility", "stress",
}

---@param key string
---@return table<string, string> genes
function CD.defineGenome(key)
    MOCK.genomeCalls[#MOCK.genomeCalls + 1] = key
    AnimalDefinitions.genome = AnimalDefinitions.genome or {}
    local g = AnimalDefinitions.genome[key]
    if not g then
        g = { genes = {} }
        for _, name in ipairs(CD.COMPANION_GENES) do g.genes[name] = name end
        AnimalDefinitions.genome[key] = g
    end
    return g.genes
end

local dog_sounds = {
    death = { name = "CDDogDeath", slot = "voice", priority = 100 },
    fallover = { name = "AnimalFoleyRaccoonBodyfall" },
    pain = { name = "CDDogWhine", slot = "voice", priority = 50 },
    pick_up = { name = "CDDogPickup", slot = "voice", priority = 1 },
    pick_up_corpse = { name = "PickUpAnimalDeadRaccoon" },
    put_down = { name = "CDDogPickup", slot = "voice", priority = 1 },
    put_down_corpse = { name = "PutDownAnimalDeadRaccoon" },
    runloop = { name = "AnimalFootstepsRaccoonRun", slot = "runloop" },
    walkBack = { name = "AnimalFootstepsRaccoonWalkBack" },
    walkFront = { name = "AnimalFootstepsRaccoonWalkFront" },
}
CD.DOG_SOUNDS = dog_sounds
CD.COMPANION_SOUNDS = dog_sounds

---@param a table
---@param bodyModel string|nil
function CD.applyDogModel(a, bodyModel)
    MOCK.modelCalls[#MOCK.modelCalls + 1] = { target = a, bodyModel = bodyModel }
    a.bodyModel = bodyModel or "Caramelo_Body"
    a.bodyModelSkel = "Raccoon_Skeleton"
    a.textureSkeleton = "RaccoonSkeleton"
    a.textureSkeletonBloody = "RaccoonSkeleton_Butchered"
    a.bodyModelSkelNoHead = "Raccoon_Skeleton_NoHead"
    a.animset = "raccoon"
    a.feedByHandAnim = "AnimalLureLow"
end

---@param a table
function CD.applyDogBehaviour(a)
    MOCK.behaviourCalls[#MOCK.behaviourCalls + 1] = { target = a }
    a.group = "dog"
    a.wild = false
    a.alwaysFleeHumans = false
    a.fleeHumansMod = 0
    a.canBeAlerted = false
    a.fleeZombies = false
    a.attackBack = false
    a.healthLossMultiplier = 0.004
    a.canBeDomesticated = true
    a.canBePet = true
    a.canBePicked = true
    a.canClimbStairs = true
    a.canClimbFences = false
    a.collidable = false
    a.idleTypeNbr = 2
    a.idleEmoteChance = 450
    a.sitRandomly = false
    a.turnDelta = 0.95
    a.animalSize = 0.25
    a.addTrackingXp = false
    a.corpseSize = 0
    a.dung = "Dung_Raccoon"
    a.canBeKilledWithoutWeapon = true
    a.eatTypeTrough = "AnimalFeed,Grass,Hay,Vegetables,Fruits"
    a.thirstHungerTrigger = 0.1
    a.distToEat = 1
end

---@param t table
function CD.applyDogAvatar(t)
    MOCK.avatarCalls[#MOCK.avatarCalls + 1] = { target = t }
    t.zoom = 10
    t.xoffset = -0.1
    t.yoffset = -0.2
    t.avatarWidth = 200
    t.avatarDir = IsoDirections.SE
    t.trailerDir = IsoDirections.SW
    t.trailerZoom = 8.5
    t.trailerXoffset = 0.2
    t.trailerYoffset = -0.3
end

CD.applyCompanionModel = CD.applyDogModel
CD.applyCompanionBehaviour = CD.applyDogBehaviour
CD.applyCompanionAvatar = CD.applyDogAvatar

CD.STRAY_NO_BLEEDOUT = 1000000

-- ---------------------------------------------------------------- 剥皮/屠宰表（照抄 CompanionDogs_Parts.lua）
local dogMeat = { item = "Base.CompanionDogsDogMeat", minNb = 2, maxNb = 4, pupMinNb = 1, pupMaxNb = 2 }

local function defineStage(key, parts, boneMin, boneMax)
    local d = AnimalPartsDefinitions.animals[key] or {}
    d.parts = d.parts or parts
    d.bones = d.bones or {}
    table.insert(d.bones, { item = "Base.SmallAnimalBone", minNb = boneMin, maxNb = boneMax })
    d.noSkeleton = true
    d.xpPerItem = 10
    AnimalPartsDefinitions.animals[key] = d
    return d
end

---@param typePrefix string prefix of the three animal types
---@param engineBreed string engine breed name
---@param meat table|nil
function CD.defineDogParts(typePrefix, engineBreed, meat)
    local call = record("defineDogParts", { typePrefix = typePrefix, engineBreed = engineBreed, meat = meat })
    MOCK.definePartsCalls[#MOCK.definePartsCalls + 1] = call
    if typePrefix == nil or engineBreed == nil then
        call.status = "refused"
        call.reason = "typePrefix or engineBreed is nil"
        return nil
    end
    meat = meat or dogMeat
    local adultParts = { { item = meat.item, minNb = meat.minNb, maxNb = meat.maxNb } }
    local pupParts = { { item = meat.item, minNb = meat.pupMinNb, maxNb = meat.pupMaxNb } }
    defineStage(typePrefix .. "male" .. engineBreed, adultParts, 1, 2)
    defineStage(typePrefix .. "female" .. engineBreed, adultParts, 1, 2)
    defineStage(typePrefix .. "pup" .. engineBreed, pupParts, 1, 1)
    call.status = "ok"
    return true
end
CD.defineCompanionParts = CD.defineDogParts

-- base 自己的 5 个品种也会调它（与 CompanionDogs_Parts.lua:31-35 一致）
CD.defineDogParts("dog", "brown")
CD.defineDogParts("gs", "germanshepherd")
CD.defineDogParts("retriever", "golden")
CD.defineDogParts("husky", "husky")
CD.defineDogParts("bc", "bordercollie")

-- ---------------------------------------------------------------- 基线
-- 这两个数在 addon 加载**之前**抓：测试据此断言"恰好追加 1 条"。
MOCK.moodleCountBefore = #CD.DogMoodles
MOCK.upkeepCountBefore = #CD.onUpkeepStress
-- base 初始化时空的：测试据此断言"恰好写了 7 个 engineBreed"
MOCK.definePartsBaseCount = #MOCK.definePartsCalls
