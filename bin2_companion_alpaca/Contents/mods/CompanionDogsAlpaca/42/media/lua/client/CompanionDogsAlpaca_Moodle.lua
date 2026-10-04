-- CompanionDogsAlpaca: 羊驼的品种 moodle「羊毛暖意 / Fleece Warmth」
--
-- moodle 是**客户端**文件：往 CD.DogMoodles 追加一条表，base 负责画、跟踪、清理。
-- 契约（base 源码实证，手册第 10 节没写全的也在注释里标了）：
--   * condition(player, dog) 返回数字，> 0 即显示；dog 是**当前范围内的活动同伴**，可能是 nil；
--   * apply(player, dog, elapsedMin) 的 elapsedMin 是距上次求值的游戏分钟（夹在 0.5..10）；
--   * breed 字段不是过滤器，而是"这是品种专属 moodle"的开关：玩家关掉品种 moodle、或动物生病时，
--     带 breed 的 moodle 连 condition 都不会被调用 —— 过滤必须自己写在 condition 里；
--   * icon / fg 都要 6 个尺寸（32/48/64/80/96/128）：`media/textures/<名>_<尺寸>.png`；
--     fg 是叠在"被 tint 染过色的原版底框"上面的贴图，tint 只染底框。
local CD = CompanionDogs
if not (CD and (CD.CompanionMoodles or CD.DogMoodles) and (CD.API_VERSION or 0) >= 5) then return end
if not (CompanionDogsAlpaca and CompanionDogsAlpaca.BREED_KEYS) then return end

local MOODLES = CD.CompanionMoodles or CD.DogMoodles
local ALPACAS = CompanionDogsAlpaca.BREED_KEYS

-- 一致性检查：毛色表在本 addon 里有两处写法（Breed.lua 与 Definitions/animal/AlpacaDefinitions.lua），
-- 因为同名目录下两份文件谁先加载不确定、不能互相依赖。客户端在所有 shared 之后加载，
-- 是唯一能同时看到两边的地方 —— 对不上就在这里报出来，否则症状只是"某色羊驼没贴图"。
if CompanionDogsAlpaca.ENGINE_BREEDS and AnimalDefinitions and AnimalDefinitions.breeds
   and AnimalDefinitions.breeds["alpaca"] then
    local missing = {}
    for engine in pairs(CompanionDogsAlpaca.ENGINE_BREEDS) do
        if not AnimalDefinitions.breeds["alpaca"].breeds[engine] then
            missing[#missing + 1] = engine
        end
    end
    if #missing > 0 then
        table.sort(missing)
        CD.log("CompanionDogsAlpaca: aviso de consistencia: engineBreed sem definicao de animal: " ..
               table.concat(missing, ", "))
    end
end

local function alpacaIsCaredFor(alpaca)
    local h = alpaca:getHunger()
    local t = alpaca:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

CD.ALPACA_RELIEF_MULT = 0.75     -- 相对 base 的"开心"moodle 的缓解倍率
CD.ALPACA_CALM_STRESS_PER_MIN = 0.003

MOODLES[#MOODLES + 1] = {
    id = "alpacafleece",
    breed = "alpaca",
    nameKey = "IGUI_PD_Moodle_AlpacaFleece",
    descKey = "IGUI_PD_Moodle_AlpacaFleece_desc",
    icon = "CDAlpaca_Moodle_Fleece",
    fg = "CDAlpaca_MoodFleeceFG",
    tintR = 0.93, tintG = 0.82, tintB = 0.52,
    condition = function(player, alpaca)
        if not alpaca or alpaca:isDead() then return 0 end
        if not ALPACAS[CD.getBreed(alpaca)] then return 0 end
        if CD.isDisloyal(alpaca) then return 0 end
        if CD.isSick(alpaca) then return 0 end
        if not alpacaIsCaredFor(alpaca) then return 0 end
        -- 热应激时厚毛是负担，这条就不该再"暖"谁（Pug 的 Shadow moodle 用的是同样的互斥写法）
        if CD.alpacaHeatRatio and CD.alpacaHeatRatio(alpaca) > 0 then return 0 end
        return 1
    end,
    apply = function(player, alpaca, elapsedMin)
        CD.relieveMood(player, CD.moodleReliefPerMin() * CD.ALPACA_RELIEF_MULT * elapsedMin)
        local n = CD.ALPACA_CALM_STRESS_PER_MIN * elapsedMin
        if n <= 0 then return end
        local stats = player:getStats()
        if stats then
            stats:remove(CharacterStat.STRESS, n)
        end
    end,
}
