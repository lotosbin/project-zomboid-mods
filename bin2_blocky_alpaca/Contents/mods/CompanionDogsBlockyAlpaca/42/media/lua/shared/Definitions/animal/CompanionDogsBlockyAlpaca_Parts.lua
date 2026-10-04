-- CompanionDogsBlockyAlpaca: 剥皮/屠宰表
--
-- 键是 <typePrefix><male|female|pup><engineBreed>（ButcheringUtil 里 modData 拼出来的），
-- 不注册的后果不是"没肉"，而是原版剥皮直接 nil 索引崩溃（def.feather 撞上 def = nil），
-- 所以 4 个 engineBreed 每个都要调一次。
--
-- 肉沿用写实羊驼的物品（Base.CompanionDogsAlpacaMeat）：方块羊驼是同一种动物的另一种造型，
-- 出不一样的肉才奇怪；写实羊驼是硬依赖，那个 item 一定已经定义好。
if CompanionDogs and (CompanionDogs.defineCompanionParts or CompanionDogs.defineDogParts) then
    local defineParts = CompanionDogs.defineCompanionParts or CompanionDogs.defineDogParts

    local alpacaMeat = { item = "Base.CompanionDogsAlpacaMeat", minNb = 3, maxNb = 6,
                         pupMinNb = 1, pupMaxNb = 2 }

    -- 兜底表：与 Breed/Definitions 里的毛色保持一致（加载顺序不确定，不能互相依赖）
    for _, name in ipairs({ "blocky_cream", "blocky_brown", "blocky_gray", "blocky_spot" }) do
        defineParts("bky", name, alpacaMeat)
    end
end
