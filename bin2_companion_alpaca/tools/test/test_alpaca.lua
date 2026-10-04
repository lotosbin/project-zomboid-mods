-- ===========================================================================
-- test_alpaca.lua —— CompanionDogsAlpaca 的注册契约断言（11 条）
-- ===========================================================================
--
-- 环境由 run.js + mock_base.lua 准备好：
--   * MOCK         —— mock 的调用记录 / 日志 / 开关（见 mock_base.lua 顶部）
--   * CompanionDogs（CD）—— 忠实 mock 的 base
--   * CompanionDogsAlpaca / AnimalDefinitions / AnimalAvatarDefinition / AnimalPartsDefinitions
--     —— 5 个被测文件跑完后的产物
--
-- 每条断言失败都会打印可读原因；最后 dump 全部 CD.log 并做禁忌词检查。
-- 返回失败条数（run.js 用它当退出码）。

local TOTAL = 11
local passedCount = 0
local failures = 0

-- 被测 addon 与 mock 都通过全局 CompanionDogs 取 base（跟游戏里一致）
local CD = CompanionDogs
local Alpaca = CompanionDogsAlpaca

-- ---------------------------------------------------------------- 断言框架
local function makeReport()
    local problems = {}
    local R = {}
    function R.add(msg) problems[#problems + 1] = tostring(msg) end
    function R.eq(got, want, label)
        if got ~= want then
            problems[#problems + 1] = string.format("%s: got %s, want %s", label, tostring(got), tostring(want))
        end
    end
    function R.isTrue(cond, label)
        if not cond then problems[#problems + 1] = label .. ": expected truthy, got falsy" end
    end
    -- 开区间 (lo, hi]，用于"百分比必须在 (0, 100] 里"
    function R.numIn(got, lo, hi, label)
        if type(got) ~= "number" or not (got > lo and got <= hi) then
            problems[#problems + 1] = string.format("%s: got %s, want a number in (%s, %s]",
                label, tostring(got), tostring(lo), tostring(hi))
        end
    end
    function R.near(got, want, label)
        if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
            problems[#problems + 1] = string.format("%s: got %s, want %s", label, tostring(got), tostring(want))
        end
    end
    function R.done()
        return #problems == 0, table.concat(problems, "\n       -> ")
    end
    return R
end

local function runTest(n, name, fn)
    local okk, passedFlag, reason = pcall(fn)
    if not okk then
        failures = failures + 1
        print(string.format("[test] %d/%d %s ... FAIL", n, TOTAL, name))
        print("       -> lua error: " .. tostring(passedFlag))
    elseif passedFlag then
        passedCount = passedCount + 1
        local suffix = (type(reason) == "string" and #reason > 0) and ("  (" .. reason .. ")") or ""
        print(string.format("[test] %d/%d %s ... OK%s", n, TOTAL, name, suffix))
    else
        failures = failures + 1
        print(string.format("[test] %d/%d %s ... FAIL", n, TOTAL, name))
        print("       -> " .. tostring(reason))
    end
end

-- ---------------------------------------------------------------- 通用工具
local function callsNamed(name)
    local out = {}
    for _, c in ipairs(MOCK.calls) do
        if c.name == name then out[#out + 1] = c end
    end
    return out
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function isIn(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

--- mock 的羊驼：饥饿/口渴都低、活着
local function newAnimal(breed, hunger, thirst, dead)
    local a = {}
    a.breed = breed
    a.hunger = hunger or 0.1
    a.thirst = thirst or 0.1
    a.dead = dead or false
    function a:isDead() return self.dead end
    function a:getHunger() return self.hunger end
    function a:getThirst() return self.thirst end
    return a
end

--- mock 的玩家：只要 getStats():remove 不炸就行
local function newPlayer()
    local stats = {}
    stats.removed = {}
    function stats:remove(stat, n) self.removed[#self.removed + 1] = { stat = stat, n = n } end
    function stats:add(stat, n) self.removed[#self.removed + 1] = { stat = stat, n = -n } end
    function stats:get(stat) return 0 end
    local p = {}
    function p:getStats() return stats end
    p.stats = stats
    return p
end

-- 契约里的常量（必须与 CompanionDogsAlpaca_Breed.lua 的 COATS 一致）
local KEYS = { "alpaca", "alpacafawn", "alpacabrown", "alpacablack", "alpacagrey",
               "alpacarosegrey", "alpacasuri" }
local ENGINE_BY_KEY = {
    alpaca = "alpaca", alpacafawn = "alpaca_fawn", alpacabrown = "alpaca_brown",
    alpacablack = "alpaca_black", alpacagrey = "alpaca_grey",
    alpacarosegrey = "alpaca_rose", alpacasuri = "alpaca_suri",
}
local ENGINE_BREEDS = { "alpaca", "alpaca_fawn", "alpaca_brown", "alpaca_black",
                        "alpaca_grey", "alpaca_rose", "alpaca_suri" }
local ENGINE_BREED_SET = { alpaca = true, alpaca_fawn = true, alpaca_brown = true, alpaca_black = true,
                           alpaca_grey = true, alpaca_rose = true, alpaca_suri = true }
-- base（含已发布 addon）已经占用的生成后缀；带 "|" 前缀的是持久化键的一部分。
-- 我们用的是 ap*/av*，任何一个撞上都意味着"每栋建筑重新投骰"或与别人抢同一格。
local BASE_SUFFIXES = { "", "g", "h", "hv", "bc", "gh", "hh", "bh", "rw", "r", "db", "dm", "dh",
                        "lb", "lk", "pg", "pv", "ml", "mm", "mh" }

print("== assertions ==")

-- ===========================================================================
-- 1) base 缺失时必须静默早退：不抛错、不建全局
-- ===========================================================================
runTest(1, "addon loads silently when base is absent (no error, no globals)", function()
    local r = makeReport()
    r.isTrue(type(host_nil_base_probe) == "function", "run.js host_nil_base_probe() is available")
    if type(host_nil_base_probe) ~= "function" then return r.done() end
    local probe = host_nil_base_probe()
    r.isTrue(probe.ok == true, "loading 5 files without base raised an error: " .. tostring(probe.error))
    r.eq(probe.created, "", "globals created while base was absent")
    return r.done()
end)

-- ===========================================================================
-- 2) CD.registerSpecies 恰好 1 次，三个翻译键正确
-- ===========================================================================
runTest(2, "CD.registerSpecies called once with the alpaca translation keys", function()
    local r = makeReport()
    local species = callsNamed("registerSpecies")
    r.eq(#species, 1, "registerSpecies call count")
    local call = species[1]
    if not call then return r.done() end
    local def = call.arg
    r.eq(call.status, "ok", "registerSpecies status")
    r.isTrue(type(def) == "table", "registerSpecies argument is a table")
    if type(def) ~= "table" then return r.done() end
    r.eq(def.key, "alpaca", "registerSpecies def.key")
    r.eq(def.nounKey, "IGUI_PD_SpeciesNoun_alpaca", "registerSpecies def.nounKey")
    r.eq(def.youngKey, "IGUI_PD_Young_alpaca", "registerSpecies def.youngKey")
    r.eq(def.labelKey, "IGUI_PD_SpeciesDisplay_alpaca", "registerSpecies def.labelKey")
    r.isTrue(CD.SPECIES["alpaca"] == def, "CD.SPECIES['alpaca'] points at the registered def")
    return r.done()
end)

-- ===========================================================================
-- 3) registerVoices 必须早于第一次 registerBreed，且四张声音表都被写了
-- ===========================================================================
runTest(3, "CD.registerVoices runs before the first CD.registerBreed", function()
    local r = makeReport()
    local voicesIdx, breedIdx
    for i, c in ipairs(MOCK.calls) do
        if c.name == "registerVoices" and not voicesIdx then voicesIdx = i end
        if c.name == "registerBreed" and not breedIdx then breedIdx = i end
    end
    r.isTrue(voicesIdx ~= nil, "registerVoices was never called")
    r.isTrue(breedIdx ~= nil, "registerBreed was never called")
    if voicesIdx and breedIdx then
        r.isTrue(voicesIdx < breedIdx,
            string.format("registerVoices (call #%d) must come BEFORE the first registerBreed (call #%d)",
                voicesIdx, breedIdx))
    end
    -- base 的 registerBreed 会在 SOUND_CATEGORY 里查不到声音时打这条日志：
    -- 有它就说明顺序还是错的（声音会绕开玩家音量与静音）。
    for i, line in ipairs(MOCK.logs) do
        if string.find(line, "CD.registerVoices", 1, true) then
            r.add(string.format("log line %d warns the voice was not registered in time: %s", i, line))
        end
    end
    -- registerVoices 的四张表（base Needs.lua:76 的行为）
    r.eq(CD.SOUND_CATEGORY.CDAlpacaChew, "fx", "SOUND_CATEGORY.CDAlpacaChew")
    r.eq(CD.SOUND_CATEGORY.CDAlpacaAlarm, "bark", "SOUND_CATEGORY.CDAlpacaAlarm")
    r.eq(CD.SOUND_CATEGORY.CDAlpacaAlarmAmbient, "ambient", "SOUND_CATEGORY.CDAlpacaAlarmAmbient")
    r.eq(CD.SOUND_NONBANK.CDAlpacaWhine, true, "SOUND_NONBANK.CDAlpacaWhine")
    r.eq(CD.SOUND_RANGE.CDAlpacaAlarm, 28, "SOUND_RANGE.CDAlpacaAlarm")
    r.eq(CD.SOUND_RANGE.CDAlpacaPickup, 8, "SOUND_RANGE.CDAlpacaPickup")
    r.eq(CD.SOUND_RANGE.CDAlpacaChew, 10, "SOUND_RANGE.CDAlpacaChew")
    r.isTrue(isIn(CD.ENGINE_VOICES, "CDAlpacaWhine"), "ENGINE_VOICES contains CDAlpacaWhine")
    r.isTrue(isIn(CD.ENGINE_VOICES, "CDAlpacaDeath"), "ENGINE_VOICES contains CDAlpacaDeath")
    r.isTrue(isIn(CD.ENGINE_VOICES, "CDAlpacaPickup"), "ENGINE_VOICES contains CDAlpacaPickup")
    return r.done()
end)

-- ===========================================================================
-- 4) 循环音必须自己登记（registerVoices 不管这个）
-- ===========================================================================
runTest(4, "CD.SOUND_LOOPED has the chewing/drinking loops", function()
    local r = makeReport()
    r.isTrue(type(CD.SOUND_LOOPED) == "table", "CD.SOUND_LOOPED exists")
    if type(CD.SOUND_LOOPED) ~= "table" then return r.done() end
    r.eq(CD.SOUND_LOOPED.CDAlpacaChew, true, "SOUND_LOOPED.CDAlpacaChew")
    r.eq(CD.SOUND_LOOPED.CDAlpacaDrink, true, "SOUND_LOOPED.CDAlpacaDrink")
    -- base 自己的循环音不能被我们覆盖掉
    r.eq(CD.SOUND_LOOPED.CDDogEat, true, "SOUND_LOOPED.CDDogEat (base) preserved")
    r.eq(CD.SOUND_LOOPED.CDDogDrink, true, "SOUND_LOOPED.CDDogDrink (base) preserved")
    return r.done()
end)

-- ===========================================================================
-- 5) registerBreed：恰好成功 7 次，字段与生成后缀全部对
-- ===========================================================================
runTest(5, "CD.registerBreed succeeds exactly 7x with the full field contract", function()
    local r = makeReport()
    local accepted = {}
    for _, c in ipairs(MOCK.registerBreedCalls) do
        if c.status == "ok" then accepted[#accepted + 1] = c.key end
    end
    r.eq(#accepted, 7, "successful registerBreed count")
    r.eq(table.concat(sortedKeys(MOCK.breedAccepted), ","), table.concat(sortedKeys(ENGINE_BY_KEY), ","),
        "accepted breed key set")

    local engineSeen = {}
    for _, key in ipairs(KEYS) do
        local def = CD.BREEDS[key]
        r.isTrue(type(def) == "table", "CD.BREEDS['" .. key .. "'] exists")
        if type(def) == "table" then
            r.eq(def.key, key, key .. ".key")
            r.eq(def.species, "alpaca", key .. ".species")
            r.eq(def.typePrefix, "alpaca", key .. ".typePrefix")
            r.eq(def.nameKey, "IGUI_PD_Breed_" .. key, key .. ".nameKey")
            r.eq(def.engineBreed, ENGINE_BY_KEY[key], key .. ".engineBreed")
            engineSeen[def.engineBreed] = (engineSeen[def.engineBreed] or 0) + 1
            r.eq(def.canKill, false, key .. ".canKill")
            r.eq(def.skills and def.skills.hunt, false, key .. ".skills.hunt")
            r.eq(def.diet and def.diet.replace, true, key .. ".diet.replace")
            r.isTrue(type(def.puppySize) == "number", key .. ".puppySize is a number")
            r.isTrue(type(def.xpMult) == "table", key .. ".xpMult is a table")
            r.isTrue(type(def.combatPower) == "number", key .. ".combatPower is a number")
            r.isTrue(type(def.lethalityCurve) == "table", key .. ".lethalityCurve is a table")

            local gr = def.geneRange
            r.isTrue(type(gr) == "table", key .. ".geneRange is a table")
            if type(gr) == "table" then
                for _, g in ipairs({ "strength", "aggressiveness", "resistance", "stress" }) do
                    r.isTrue(type(gr[g]) == "table" and #gr[g] == 2, key .. ".geneRange." .. g .. " is a 2-number range")
                end
            end

            local spawns = def.spawns
            r.isTrue(type(spawns) == "table" and #spawns == 2, key .. ".spawns has 2 steps")
            if type(spawns) == "table" and #spawns == 2 then
                r.isTrue(spawns[1].suffix ~= spawns[2].suffix, key .. ".spawns suffixes are distinct")
                for si, sp in ipairs(spawns) do
                    local label = string.format("%s.spawns[%d]", key, si)
                    r.eq(sp.breed, key, label .. ".breed")
                    r.isTrue(sp.class == "farm" or sp.class == "petvet", label .. ".class is farm|petvet")
                    r.isTrue(type(sp.indoor) == "number", label .. ".indoor is a number")
                    r.isTrue(type(sp.chance) == "function", label .. ".chance is a function")
                    r.isTrue(type(sp.suffix) == "string" and sp.suffix:sub(1, 1) == "|",
                        label .. ".suffix starts with '|'")
                    local body = type(sp.suffix) == "string" and sp.suffix:sub(2) or ""
                    r.isTrue(not isIn(BASE_SUFFIXES, body),
                        string.format("%s.suffix '%s' collides with a suffix already used by base", label, tostring(sp.suffix)))
                    r.isTrue(not (body:sub(1, 2) == "ct" or body:sub(1, 2) == "cv" or body:sub(1, 2) == "cs"),
                        string.format("%s.suffix '%s' collides with the cat addon ct*/cv*/cs*", label, tostring(sp.suffix)))
                end
            end
        end
    end

    local dupes = {}
    for engine, n in pairs(engineSeen) do
        if n > 1 then dupes[#dupes + 1] = engine .. "x" .. n end
    end
    table.sort(dupes)
    r.eq(#dupes, 0, "duplicated engineBreed(s): " .. table.concat(dupes, ","))
    r.eq(countKeys(engineSeen), 7, "distinct engineBreed count")

    r.eq(CD.TYPES.alpacapup, true, "CD.TYPES.alpacapup")
    r.eq(CD.TYPES.alpacafemale, true, "CD.TYPES.alpacafemale")
    r.eq(CD.TYPES.alpacamale, true, "CD.TYPES.alpacamale")
    return r.done()
end)

-- ===========================================================================
-- 6) spawn chance：落在 (0,100]，沙盒倍率 0 -> 0，2 -> 翻倍
-- ===========================================================================
runTest(6, "spawn chance() obeys the (0,100] range and the sandbox multiplier", function()
    local r = makeReport()
    local sv = SandboxVars and SandboxVars.CompanionAlpaca
    r.isTrue(type(sv) == "table", "SandboxVars.CompanionAlpaca exists (media/sandbox-options.txt)")
    if type(sv) ~= "table" then return r.done() end
    local original = sv.AlpacaSpawnMultiplier

    for _, key in ipairs(KEYS) do
        local def = CD.BREEDS[key]
        for si, sp in ipairs((def and def.spawns) or {}) do
            local label = string.format("%s.spawns[%d].chance()", key, si)
            sv.AlpacaSpawnMultiplier = 1.0
            local c1 = sp.chance()
            r.numIn(c1, 0, 100, label)

            sv.AlpacaSpawnMultiplier = 0
            r.eq(sp.chance(), 0, label .. " with multiplier 0")

            sv.AlpacaSpawnMultiplier = 2.0
            r.near(sp.chance(), c1 * 2, label .. " with multiplier 2")

            sv.AlpacaSpawnMultiplier = 0.5
            r.near(sp.chance(), c1 * 0.5, label .. " with multiplier 0.5")
        end
    end

    sv.AlpacaSpawnMultiplier = original
    return r.done()
end)

-- ===========================================================================
-- 7) AlpacaDefinitions：阶段 / 毛色 / 三个类型 / 头像 / 两份表的一致性
-- ===========================================================================
runTest(7, "AlpacaDefinitions builds stages, breeds, animals, avatars and matches Breed.lua", function()
    local r = makeReport()
    local AD = AnimalDefinitions
    r.isTrue(type(AD) == "table" and type(AD.stages) == "table" and type(AD.breeds) == "table"
        and type(AD.animals) == "table" and type(AD.genome) == "table",
        "AnimalDefinitions.genome/stages/breeds/animals all exist")
    if type(AD) ~= "table" or type(AD.animals) ~= "table" then return r.done() end

    -- 成长阶段
    local stageDef = AD.stages and AD.stages["alpaca"]
    local stages = stageDef and stageDef.stages
    r.isTrue(type(stages) == "table", "AnimalDefinitions.stages['alpaca'].stages exists")
    if type(stages) == "table" then
        r.eq(countKeys(stages), 3, "alpaca stage count")
        r.eq(stages.alpacapup and stages.alpacapup.nextStage, "alpacafemale", "alpacapup.nextStage")
        r.eq(stages.alpacapup and stages.alpacapup.nextStageMale, "alpacamale", "alpacapup.nextStageMale")
    end

    -- 毛色表
    local breedDef = AD.breeds and AD.breeds["alpaca"]
    local breedsTbl = breedDef and breedDef.breeds
    r.isTrue(type(breedsTbl) == "table", "AnimalDefinitions.breeds['alpaca'].breeds exists")
    if type(breedsTbl) == "table" then
        r.eq(table.concat(sortedKeys(breedsTbl), ","), table.concat(sortedKeys(ENGINE_BREED_SET), ","),
            "engine breed key set in Definitions")
        for _, engine in ipairs(ENGINE_BREEDS) do
            local b = breedsTbl[engine]
            r.isTrue(type(b) == "table", "breeds['" .. engine .. "'] exists")
            if type(b) == "table" then
                for _, field in ipairs({ "texture", "textureMale", "rottenTexture" }) do
                    r.isTrue(type(b[field]) == "string" and #b[field] > 0,
                        string.format("breeds['%s'].%s is a non-empty string", engine, field))
                end
            end
        end
    end

    -- 三个引擎动物类型
    local animals = {}
    for _, t in ipairs({ "alpacapup", "alpacafemale", "alpacamale" }) do
        local a = AD.animals[t]
        r.isTrue(type(a) == "table", "AnimalDefinitions.animals['" .. t .. "'] exists")
        if type(a) == "table" then
            animals[#animals + 1] = a
            r.eq(a.group, "alpaca", t .. ".group")
            r.eq(a.animset, "raccoon", t .. ".animset (forked animsets freeze the animal)")
            r.isTrue(a.breeds == breedsTbl, t .. ".breeds points at the shared breed table")
            r.isTrue(a.stages == stages, t .. ".stages points at the shared stage table")
            r.isTrue(type(a.genes) == "table", t .. ".genes exists")
            r.isTrue(a.mate == nil, t .. ".mate must not be declared")
        end
    end
    if #animals == 3 then
        r.isTrue(animals[1].breeds == animals[2].breeds and animals[2].breeds == animals[3].breeds,
            "all three types share one breeds table")
        r.isTrue(animals[1].stages == animals[2].stages and animals[2].stages == animals[3].stages,
            "all three types share one stages table")
        r.isTrue(animals[1].genes == animals[2].genes and animals[2].genes == animals[3].genes,
            "all three types share one genes table")
        r.isTrue(AD.genome["alpaca"] and animals[1].genes == AD.genome["alpaca"].genes,
            "genes come from CD.defineGenome('alpaca')")
    end

    -- 头像相机
    for _, t in ipairs({ "alpacapup", "alpacafemale", "alpacamale" }) do
        local av = AnimalAvatarDefinition and AnimalAvatarDefinition[t]
        r.isTrue(type(av) == "table", "AnimalAvatarDefinition['" .. t .. "'] exists")
        if type(av) == "table" then
            for _, field in ipairs({ "zoom", "trailerZoom", "xoffset", "yoffset", "trailerXoffset", "trailerYoffset" }) do
                r.isTrue(type(av[field]) == "number", t .. ".avatar." .. field .. " is a number")
            end
        end
    end

    -- 防漂移：Breed.lua 与 Definitions 两份毛色表必须是同一套 engineBreed
    local fromBreed = CompanionDogsAlpaca and CompanionDogsAlpaca.ENGINE_BREEDS
    local fromDefs = breedsTbl
    r.isTrue(type(fromBreed) == "table" and type(fromDefs) == "table",
        "both engineBreed tables exist (Breed.lua + AlpacaDefinitions.lua)")
    if type(fromBreed) == "table" and type(fromDefs) == "table" then
        r.eq(table.concat(sortedKeys(fromBreed), ","), table.concat(sortedKeys(fromDefs), ","),
            "engineBreed set drift between CompanionDogsAlpaca_Breed.lua and AlpacaDefinitions.lua")
    end
    return r.done()
end)

-- ===========================================================================
-- 8) defineCompanionParts：每个 engineBreed 一次，肉指向本模组的物品
-- ===========================================================================
runTest(8, "CD.defineCompanionParts called 7x with ('alpaca', engineBreed, meat)", function()
    local r = makeReport()
    -- base 在 API 7 把 defineDogParts 改名成 defineCompanionParts，两个名字指向同一个函数。
    -- 记录里的 name 是 "defineDogParts"（mock 就是这么定义的），这里先把别名关系钉住。
    r.isTrue(type(CD.defineCompanionParts) == "function", "CD.defineCompanionParts exists (API 7 name)")
    r.isTrue(CD.defineCompanionParts == CD.defineDogParts, "CD.defineCompanionParts aliases CD.defineDogParts")
    local ours = {}
    for _, c in ipairs(MOCK.definePartsCalls) do
        if c.typePrefix == "alpaca" then ours[#ours + 1] = c end
    end
    r.eq(#ours, 7, "defineCompanionParts('alpaca', ...) call count")

    local seen = {}
    for _, c in ipairs(ours) do
        r.isTrue(isIn(ENGINE_BREEDS, c.engineBreed),
            "unexpected engineBreed in defineCompanionParts: " .. tostring(c.engineBreed))
        seen[c.engineBreed] = (seen[c.engineBreed] or 0) + 1
        local meat = c.meat
        r.isTrue(type(meat) == "table", "meat argument for " .. tostring(c.engineBreed) .. " is a table")
        if type(meat) == "table" then
            r.eq(meat.item, "Base.CompanionDogsAlpacaMeat",
                "meat.item for " .. tostring(c.engineBreed))
            for _, f in ipairs({ "minNb", "maxNb", "pupMinNb", "pupMaxNb" }) do
                r.isTrue(type(meat[f]) == "number", "meat." .. f .. " is a number")
            end
        end
    end
    r.eq(countKeys(seen), 7, "distinct engineBreed count in defineCompanionParts")
    for _, engine in ipairs(ENGINE_BREEDS) do
        r.eq(seen[engine], 1, "defineCompanionParts call count for " .. engine)
    end

    -- mock 照抄 base 写了 <prefix>{male,female,pup}<engine> 三张表；剥皮键里带毛色
    local parts = AnimalPartsDefinitions and AnimalPartsDefinitions.animals
    for _, engine in ipairs(ENGINE_BREEDS) do
        for _, sex in ipairs({ "male", "female", "pup" }) do
            local k = "alpaca" .. sex .. engine
            r.isTrue(type(parts[k]) == "table", "AnimalPartsDefinitions.animals['" .. k .. "'] exists")
        end
    end
    return r.done()
end)

-- ===========================================================================
-- 9) CompanionMoodles：追加 1 条 + condition/apply 真的按契约工作
-- ===========================================================================
runTest(9, "CD.CompanionMoodles entry behaves per the moodle contract", function()
    local r = makeReport()
    local moods = CD.CompanionMoodles
    r.isTrue(type(moods) == "table", "CD.CompanionMoodles exists")
    r.isTrue(moods == CD.DogMoodles, "CD.CompanionMoodles aliases CD.DogMoodles")
    if type(moods) ~= "table" then return r.done() end
    r.eq(#moods, MOCK.moodleCountBefore + 1, "moodle count delta")

    local m = moods[#moods]
    r.isTrue(type(m) == "table", "the appended moodle is a table")
    if type(m) ~= "table" then return r.done() end
    r.eq(m.id, "alpacafleece", "moodle.id")
    r.eq(m.breed, "alpaca", "moodle.breed (base uses it to route the entry)")
    r.isTrue(type(m.nameKey) == "string" and #m.nameKey > 0, "moodle.nameKey")
    r.isTrue(type(m.descKey) == "string" and #m.descKey > 0, "moodle.descKey")
    r.isTrue(type(m.icon) == "string" and #m.icon > 0, "moodle.icon")
    r.isTrue(type(m.fg) == "string" and #m.fg > 0, "moodle.fg")
    r.isTrue(type(m.tintR) == "number", "moodle.tintR")
    r.isTrue(type(m.condition) == "function", "moodle.condition is a function")
    r.isTrue(type(m.apply) == "function", "moodle.apply is a function")
    if type(m.condition) ~= "function" or type(m.apply) ~= "function" then return r.done() end

    -- 输入夹具：气候 20C（无热应激）、不忠/生病都为 false
    MOCK.climate.temp = 20
    MOCK.climate.nilManager = false
    MOCK.climate.throwOnRead = false
    MOCK.disloyal = false
    MOCK.sick = false
    local player = newPlayer()
    local alpaca = newAnimal("alpaca", 0.1, 0.1, false)

    local v = m.condition(player, alpaca)
    r.isTrue(type(v) == "number" and v > 0, "cared-for alpaca should return > 0, got " .. tostring(v))

    r.eq(m.condition(player, newAnimal("caramelo", 0.1, 0.1, false)), 0, "non-alpaca breed must return 0")

    MOCK.disloyal = true
    r.eq(m.condition(player, alpaca), 0, "disloyal alpaca must return 0")
    MOCK.disloyal = false

    MOCK.sick = true
    r.eq(m.condition(player, alpaca), 0, "sick alpaca must return 0")
    MOCK.sick = false

    r.eq(m.condition(player, newAnimal("alpaca", 0.9, 0.1, false)), 0, "neglected (hungry) alpaca must return 0")
    r.eq(m.condition(player, newAnimal("alpaca", 0.1, 0.9, false)), 0, "neglected (thirsty) alpaca must return 0")
    r.eq(m.condition(player, newAnimal("alpaca", 0.1, 0.1, true)), 0, "dead alpaca must return 0")
    r.eq(m.condition(player, nil), 0, "nil animal must return 0")

    -- 热应激时厚毛是负担：CD.alpacaHeatRatio 为 0.5 时必须闭嘴
    local savedHeat = CD.alpacaHeatRatio
    CD.alpacaHeatRatio = function() return 0.5 end
    r.eq(m.condition(player, alpaca), 0, "heat-stressed alpaca must return 0")
    CD.alpacaHeatRatio = savedHeat

    -- apply 必须不炸，且恰好调用一次 CD.relieveMood
    local before = #MOCK.relieveMoodCalls
    local okk, err = pcall(m.apply, player, alpaca, 3)
    r.isTrue(okk, "moodle.apply raised: " .. tostring(err))
    r.eq(#MOCK.relieveMoodCalls - before, 1, "relieveMood call count during apply")
    local lastRelief = MOCK.relieveMoodCalls[#MOCK.relieveMoodCalls]
    if lastRelief then
        r.isTrue(type(lastRelief.n) == "number" and lastRelief.n > 0, "relieveMood amount must be > 0")
    end
    return r.done()
end)

-- ===========================================================================
-- 10) onUpkeepStress：追加 1 个 handler + 气候折算与 pcall 保护
-- ===========================================================================
runTest(10, "CD.onUpkeepStress handler maps temperature to stress and never throws", function()
    local r = makeReport()
    local hooks = CD.onUpkeepStress
    r.isTrue(type(hooks) == "table", "CD.onUpkeepStress exists")
    if type(hooks) ~= "table" then return r.done() end
    r.eq(#hooks, MOCK.upkeepCountBefore + 1, "onUpkeepStress count delta")
    local handler = hooks[#hooks]
    r.isTrue(type(handler) == "function", "the appended handler is a function")
    if type(handler) ~= "function" then return r.done() end

    MOCK.climate.nilManager = false
    MOCK.climate.throwOnRead = false
    local alpaca = newAnimal("alpaca", 0.1, 0.1, false)

    r.eq(handler(newAnimal("caramelo")), 0, "non-alpaca breed must return 0")
    r.eq(handler(nil), 0, "nil animal must return 0")

    local ceiling = (CD.ALPACA_HEAT_STRESS_MAX or 0) + (CD.ALPACA_COLD_STRESS_MAX or 0)
    r.isTrue(ceiling > 0, "ALPACA_*_STRESS_MAX constants exist")

    MOCK.climate.temp = 10
    r.eq(handler(alpaca), 0, "10C is inside the comfort band (must be 0)")

    MOCK.climate.temp = 34
    local hot = handler(alpaca)
    r.isTrue(type(hot) == "number" and hot > 0, "34C must add heat stress, got " .. tostring(hot))
    r.isTrue(type(hot) == "number" and hot <= ceiling,
        string.format("heat stress %s must stay <= ceiling %s", tostring(hot), tostring(ceiling)))

    MOCK.climate.temp = -20
    local cold = handler(alpaca)
    r.isTrue(type(cold) == "number" and cold > 0, "-20C must add cold stress, got " .. tostring(cold))
    r.isTrue(type(cold) == "number" and cold <= ceiling,
        string.format("cold stress %s must stay <= ceiling %s", tostring(cold), tostring(ceiling)))

    -- getClimateManager() 返回 nil -> 0，不得抛错
    MOCK.climate.nilManager = true
    local okNil, nilRes = pcall(handler, alpaca)
    r.isTrue(okNil, "handler threw when getClimateManager() returned nil: " .. tostring(nilRes))
    r.eq(nilRes, 0, "nil climate manager must yield 0")
    MOCK.climate.nilManager = false

    -- 引擎取温度抛异常 -> addon 自己 pcall 住，handler 返回 0 且不把异常抛出去
    MOCK.climate.throwOnRead = true
    local okThrow, throwRes = pcall(handler, alpaca)
    r.isTrue(okThrow, "handler propagated the engine exception (base calls hooks WITHOUT pcall): "
        .. tostring(throwRes))
    r.eq(throwRes, 0, "throwing climate read must yield 0")
    MOCK.climate.throwOnRead = false
    return r.done()
end)

-- ===========================================================================
-- 11) CD.log 收齐、最后打印；出现"运行期拒绝注册"的字样就是失败
-- ===========================================================================
runTest(11, "collected CD.log output is free of refusal/consistency warnings", function()
    local r = makeReport()
    print(string.format("[test] collected CD.log output (%d line(s)):", #MOCK.logs))
    if #MOCK.logs == 0 then
        print("       (none)")
    end
    for i, line in ipairs(MOCK.logs) do
        print(string.format("       [log %2d] %s", i, line))
    end
    local forbidden = { "recusada", "recusado", "aviso de consistencia" }
    for i, line in ipairs(MOCK.logs) do
        for _, f in ipairs(forbidden) do
            if string.find(line, f, 1, true) then
                r.add(string.format("log line %d contains forbidden '%s': %s", i, f, line))
            end
        end
    end
    return r.done()
end)

-- ---------------------------------------------------------------- 汇总
print(string.rep("-", 64))
print(string.format("[test] %d/%d passed, %d failed", passedCount, TOTAL, failures))
if failures == 0 then
    print("ALL PASS")
else
    print(string.format("%d FAILED", failures))
end
return failures
