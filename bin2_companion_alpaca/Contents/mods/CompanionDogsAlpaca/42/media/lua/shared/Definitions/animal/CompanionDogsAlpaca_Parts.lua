-- CompanionDogsAlpaca: 剥皮/屠宰表
--
-- AnimalPartsDefinitions 的键是 **引擎动物类型 .. 引擎品种名**（ButcheringUtil.lua:15
-- `modData["AnimalType"] .. modData["AnimalBreed"]`），也就是 <typePrefix><male|female|pup><engineBreed>。
-- 不注册的后果不是"没肉"，而是原版剥皮直接 nil 索引崩溃（`if def.feather then` 撞上 def = nil），
-- 所以每个 engineBreed 都要调一次 —— 剥皮键里带着毛色。
if CompanionDogs and CompanionDogs.defineDogParts then
    local defineParts = CompanionDogs.defineCompanionParts or CompanionDogs.defineDogParts

    -- 羊驼的肉量按体型给：引擎会把数量与每块肉的饥饿值再乘一遍 carcass:getAnimalSize()（约 2.3~3.05），
    -- 所以单块 HungerChange 必须比自己想喂饱的数小，否则一只羊驼能顶一星期口粮。
    local alpacaMeat = { item = "Base.CompanionDogsAlpacaMeat", minNb = 3, maxNb = 6,
                         pupMinNb = 1, pupMaxNb = 2 }

    local coats = AnimalDefinitions and AnimalDefinitions.breeds
        and AnimalDefinitions.breeds["alpaca"] and AnimalDefinitions.breeds["alpaca"].breeds
    if coats then
        for name in pairs(coats) do
            defineParts("alpaca", name, alpacaMeat)
        end
    else
        -- 兜底表：与 Breed/Definitions 里的毛色保持一致（加载顺序不确定，不能互相依赖）
        for _, name in ipairs({ "alpaca", "alpaca_fawn", "alpaca_brown", "alpaca_black",
                                "alpaca_grey", "alpaca_rose", "alpaca_suri" }) do
            defineParts("alpaca", name, alpacaMeat)
        end
    end
end
