-- CompanionDogsAlpaca: 气候应激（服务端）
--
-- 这是本 addon 唯一"改数值"的地方：通过 base 公开的 CD.onUpkeepStress 钩子，把环境温度折算成
-- 每轮 upkeep 的应激增量。羊驼是高原动物，夏天比狗难受、冬天比狗好过。
--
-- 两条硬性纪律（都来自 base 源码实证）：
--   1) base 的这个钩子是**裸调用**（BreedAPI.lua:14-20，全 base 没有任何 pcall/xpcall），
--      addon 的 handler 抛异常会打断整轮 upkeep，所以这里自己包 pcall；
--   2) 应激值由 upkeep 每轮重算并覆写，只能用返回值相加，不能从外部写存档。
local CD = CompanionDogs
if not (CD and CD.onUpkeepStress and (CD.API_VERSION or 0) >= 3) then return end
if not (CompanionDogsAlpaca and CompanionDogsAlpaca.BREED_KEYS) then return end

local ALPACAS = CompanionDogsAlpaca.BREED_KEYS

CD.onUpkeepStress[#CD.onUpkeepStress + 1] = function(animal)
    if not animal or not ALPACAS[CD.getBreed(animal)] then return 0 end
    local ok, delta = pcall(function()
        local heat = (CD.alpacaHeatRatio and CD.alpacaHeatRatio(animal) or 0) * CD.ALPACA_HEAT_STRESS_MAX
        local cold = (CD.alpacaColdRatio and CD.alpacaColdRatio(animal) or 0) * CD.ALPACA_COLD_STRESS_MAX
        return heat + cold
    end)
    if not ok or type(delta) ~= "number" then
        CD.log("CompanionDogsAlpaca: falha ao calcular estresse climatico; ignorando neste ciclo")
        return 0
    end
    return delta
end
