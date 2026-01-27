-- NeatCraftingControllerSupport: Main Entry Point
-- Loads all component patches

local NeatCraftingControllerSupport = {}
NeatCraftingControllerSupport.Crafting = require "NeatCraftingControllerSupport/Neat_Crafting/Neat_Crafting_patch"

-- Register all patches on game boot
Events.OnGameBoot.Add(function()
    print("[NCS] OnGameBoot: applying patches")
    NeatCraftingControllerSupport.Crafting:registerAll()
    print("[NCS] Patches applied")
end)

return NeatCraftingControllerSupport
