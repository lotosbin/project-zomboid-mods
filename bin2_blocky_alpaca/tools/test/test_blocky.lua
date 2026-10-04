-- ===========================================================================
-- test_blocky.lua —— CompanionDogsBlockyAlpaca 的注册契约断言（9 条）
-- ===========================================================================
--
-- 环境由 run_blocky.js + 写实羊驼的 mock_base.lua 准备：
--   * MOCK 里记录着 base 的逐次注册调用（registerBreed / defineCompanionParts / applyModel ...）
--   * 前置加载了 CompanionDogsAlpaca（物种 "alpaca" 的提供者）
--   * 再加载方块羊驼的三个 shared 文件
--
-- 返回失败条数（run.js 用它当退出码）。

local TOTAL = 9
local passedCount = 0
local failures = 0

local CD = CompanionDogs
local Alpaca = CompanionDogsAlpaca
local Blocky = CompanionDogsBlockyAlpaca

local function makeReport()
    local problems = {}
    local R = {}
    function R.add(msg) problems[#problems + 1] = tostring(msg) end
    function R.eq(got, want, label)
        if got ~= want then
            problems[#problems + 1] = string.format("%s: got %s, want %s",
                label, tostring(got), tostring(want))
        end
    end
    function R.isTrue(cond, label)
        if not cond then problems[#problems + 1] = tostring(label) end
    end
    function R.done(label)
        if #problems == 0 then
            passedCount = passedCount + 1
            print(string.format("[test] %2d/%d %s ... OK", passedCount, TOTAL, label))
        else
            failures = failures + 1
            print(string.format("[test] %2d/%d %s ... FAIL", passedCount + failures, TOTAL, label))
            for _, p in ipairs(problems) do print("        - " .. p) end
        end
    end
    return R
end

-- ---------------------------------------------------------------- 断言 1
-- 依赖缺失时安静早退（在另一个干净的 state 里跑，由 run_blocky.js 提供）
do
    local R = makeReport()
    local probe = host_nil_deps_probe()
    R.isTrue(probe.ok, "load with no base/provider must not error: " .. tostring(probe.error))
    R.eq(probe.created, "", "no globals may be created without base/provider")
    R.done("deps missing -> silent early return, no globals")
end

-- ---------------------------------------------------------------- 断言 2
-- 前置条件：物种 "alpaca" 与写实品种已经就位（否则后面的断言没有意义）
do
    local R = makeReport()
    R.isTrue(CD.SPECIES ~= nil and CD.SPECIES["alpaca"] ~= nil, "alpaca species registered by the provider")
    R.isTrue(Alpaca ~= nil and Alpaca.BREED_KEYS ~= nil, "provider tables present")
    R.eq(#MOCK.registerBreedCalls, 11, "7 provider breeds + 4 blocky breeds")
    R.done("provider loaded first, 7 + 4 = 11 registerBreed calls")
end

-- ---------------------------------------------------------------- 断言 3
-- 方块品种的表与注册字段
do
    local R = makeReport()
    local want = {
        blockycream = "blocky_cream", blockybrown = "blocky_brown",
        blockygray = "blocky_gray", blockyspot = "blocky_spot",
    }
    local seen = {}
    for _, call in ipairs(MOCK.registerBreedCalls) do
        local d = call.arg
        if d and want[d.key] then
            seen[d.key] = true
            R.eq(d.engineBreed, want[d.key], "engineBreed of " .. tostring(d.key))
            R.eq(d.species, "alpaca", "species of " .. tostring(d.key))
            R.eq(d.typePrefix, "bky", "typePrefix of " .. tostring(d.key))
            R.eq(d.nameKey, "IGUI_PD_Breed_" .. d.key, "nameKey of " .. tostring(d.key))
            R.isTrue(call.status == "ok", "registerBreed status of " .. tostring(d.key) ..
                " (" .. tostring(call.status) .. ")")
            R.isTrue(type(d.voices) == "table" and d.voices.bark == "CDAlpacaAlarm",
                "voices reuse the provider's sound names")
            R.isTrue(d.diet ~= nil and d.diet.replace == true, "herbivore diet replaces the default")
            R.isTrue(#d.spawns == 2, "two spawn tables for " .. tostring(d.key))
            for _, s in ipairs(d.spawns) do
                local c = s.chance()
                R.isTrue(type(c) == "number" and c > 0 and c <= 100,
                    "spawn chance in (0,100] for " .. tostring(s.id) .. ": " .. tostring(c))
            end
        end
    end
    for k in pairs(want) do R.isTrue(seen[k], "breed registered: " .. k) end
    R.done("4 blocky breeds registered with the full contract")
end

-- ---------------------------------------------------------------- 断言 4
-- 三个动物类型 + bodyModel
do
    local R = makeReport()
    for _, t in ipairs({ "bkypup", "bkyfemale", "bkymale" }) do
        local a = AnimalDefinitions.animals[t]
        R.isTrue(a ~= nil, "animal type exists: " .. t)
        if a then
            R.eq(a.bodyModel, "BlockyAlpaca_Body", "bodyModel of " .. t)
            R.eq(a.group, "alpaca", "group of " .. t)
            R.isTrue(a.breeds ~= nil and a.breeds["blocky_cream"] ~= nil,
                "breed table reachable from " .. t)
            R.isTrue(a.breeds["blocky_cream"].texture == "BlockyAlpaca",
                "texture of blocky_cream")
            R.isTrue(a.stages ~= nil and a.stages["bkypup"] ~= nil, "stages reachable from " .. t)
            R.isTrue(a.genes ~= nil, "genes set on " .. t)
            R.isTrue(a.mate == nil, "mate must NOT be declared on " .. t)
        end
    end
    R.isTrue(AnimalDefinitions.animals["bkyfemale"].female == true, "bkyfemale is female")
    R.isTrue(AnimalDefinitions.animals["bkymale"].male == true, "bkymale is male")
    R.eq(AnimalDefinitions.animals["bkymale"].babyType, "bkypup", "male babyType")
    R.done("three bky* animal types with the blocky body model")
end

-- ---------------------------------------------------------------- 断言 5
-- 阶段表挂在物种 "alpaca" 下，且指向方块自己的类型
do
    local R = makeReport()
    local st = AnimalDefinitions.stages["alpaca"] and AnimalDefinitions.stages["alpaca"].stages
    R.isTrue(st ~= nil, "species stage table exists")
    if st then
        R.eq(st["bkypup"].nextStage, "bkyfemale", "bkypup.nextStage")
        R.eq(st["bkypup"].nextStageMale, "bkymale", "bkypup.nextStageMale")
        R.isTrue(type(st["bkyfemale"].ageToGrow) == "number", "bkyfemale.ageToGrow")
        -- 写实羊驼的四个阶段必须还在（同表追加，不能覆盖）
        R.isTrue(st["alpacapup"] ~= nil and st["alpacafemale"] ~= nil and st["alpacamale"] ~= nil,
            "provider stages preserved")
    end
    R.done("blocky stages appended to the alpaca species table")
end

-- ---------------------------------------------------------------- 断言 6
-- 4 个毛色都进了写实羊驼的品种组（引擎按 engineBreed 取 texture 的路径）
do
    local R = makeReport()
    local breeds = AnimalDefinitions.breeds["alpaca"] and AnimalDefinitions.breeds["alpaca"].breeds
    R.isTrue(breeds ~= nil, "alpaca breed group exists")
    if breeds then
        R.isTrue(breeds["alpaca"] ~= nil, "provider breed 'alpaca' preserved")
        R.isTrue(breeds["alpaca_suri"] ~= nil, "provider breed 'alpaca_suri' preserved")
        for _, e in ipairs({ "blocky_cream", "blocky_brown", "blocky_gray", "blocky_spot" }) do
            R.isTrue(breeds[e] ~= nil, "breed group has " .. e)
            if breeds[e] then
                R.isTrue(breeds[e].texture:find("BlockyAlpaca") == 1,
                    "texture name of " .. e .. " points at a blocky atlas")
                R.eq(breeds[e].invIconMale, "CDBlockyHoof_64", "inventory icon of " .. e)
                R.isTrue(breeds[e].sounds ~= nil and breeds[e].sounds.death.name == "CDAlpacaDeath",
                    "death sound of " .. e)
            end
        end
    end
    R.done("4 blocky engine breeds added to the shared breed group")
end

-- ---------------------------------------------------------------- 断言 7
-- 剥皮表：每个 <typePrefix><stage><engineBreed> 都要有（缺了原版剥皮会 nil 崩溃）
do
    local R = makeReport()
    for _, e in ipairs({ "blocky_cream", "blocky_brown", "blocky_gray", "blocky_spot" }) do
        for _, st in ipairs({ "male", "female", "pup" }) do
            local key = "bky" .. st .. e
            local d = AnimalPartsDefinitions.animals[key]
            R.isTrue(d ~= nil, "parts defined for " .. key)
            if d then
                R.isTrue(d.parts ~= nil and d.parts[1] ~= nil, "parts list for " .. key)
                R.eq(d.parts[1].item, "Base.CompanionDogsAlpacaMeat", "meat item for " .. key)
                R.isTrue(d.noSkeleton == true, "noSkeleton for " .. key)
            end
        end
    end
    R.done("butchering table covers all 12 bky* keys")
end

-- ---------------------------------------------------------------- 断言 8
-- 与写实羊驼的集成：品种键并进它的集合（moodle / 气候钩子靠这个筛选）
do
    local R = makeReport()
    for _, k in ipairs({ "blockycream", "blockybrown", "blockygray", "blockyspot" }) do
        R.isTrue(Alpaca.BREED_KEYS[k] == true, "provider BREED_KEYS has " .. k)
    end
    for _, e in ipairs({ "blocky_cream", "blocky_brown", "blocky_gray", "blocky_spot" }) do
        R.isTrue(Alpaca.ENGINE_BREEDS[e] == true, "provider ENGINE_BREEDS has " .. e)
    end
    R.isTrue(Blocky ~= nil and Blocky.BREED_KEYS.blockycream == true, "blocky own BREED_KEYS")
    -- 物种只由提供者注册一次（方块 addon 不该重复注册：物种键全局唯一）
    local speciesCalls = 0
    for _, c in ipairs(MOCK.calls) do
        if c.name == "registerSpecies" then speciesCalls = speciesCalls + 1 end
    end
    R.eq(speciesCalls, 1, "registerSpecies called exactly once (provider only)")
    R.done("blocky breeds join the provider's key sets (moodle/climate)")
end

-- ---------------------------------------------------------------- 断言 9
-- 头像相机 + 日志禁忌词
do
    local R = makeReport()
    for _, t in ipairs({ "bkypup", "bkyfemale", "bkymale" }) do
        local av = AnimalAvatarDefinition[t]
        R.isTrue(av ~= nil, "avatar definition for " .. t)
        if av then
            R.isTrue(type(av.zoom) == "number" and av.zoom > 0, "zoom for " .. t)
            R.isTrue(av.zoom < 10, "zoom must be scaled up for a bigger model: " .. t)
        end
    end
    local bad = { "recusad", "recusada", "aviso de consistencia", "refused", "missing" }
    local hits = {}
    for _, line in ipairs(MOCK.logs) do
        for _, w in ipairs(bad) do
            if tostring(line):find(w, 1, true) then hits[#hits + 1] = tostring(line) end
        end
    end
    R.eq(#hits, 0, "CD.log must not contain refusal/consistency warnings")
    R.done("avatar cameras scaled and CD.log is clean")
end

print(string.format("[test] %d/%d passed, %d failed", passedCount, TOTAL, failures))
return failures
