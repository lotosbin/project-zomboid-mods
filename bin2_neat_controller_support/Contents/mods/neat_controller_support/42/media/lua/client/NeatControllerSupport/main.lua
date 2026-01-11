-- NeatControllerSupport: Main Entry Point
-- 手柄控制支持模组主入口

local NeatControllerSupport = {}

-- 初始化事件
local function initNeatControllerSupport()
    -- 注册 Neat_Crafting 手柄支持
    local NeatCraftingPatch = require "NeatControllerSupport/Neat_Crafting/Neat_Crafting_patch"
    if NeatCraftingPatch and NeatCraftingPatch.registerAll then
        NeatCraftingPatch:registerAll()
        print("[NCS] Neat_Crafting 手柄支持已加载")
    end

    -- 注册 Neat_Building 手柄支持
    local NeatBuildingPatch = require "NeatControllerSupport/Neat_Building/Neat_Building_patch"
    if NeatBuildingPatch and NeatBuildingPatch.registerAll then
        NeatBuildingPatch:registerAll()
        print("[NCS] Neat_Building 手柄支持已加载")
    end
end

-- 使用 Events.OnGameStart 等待游戏初始化完成后再注册
Events.OnGameStart.Add(initNeatControllerSupport)

return NeatControllerSupport
