-- NeatControllerSupport: Main Entry Point
-- Loads all component patches

local NeatControllerSupport = {}
NeatControllerSupport.Crafting = require "NeatControllerSupport/Neat_Crafting/Neat_Crafting_patch"

-- Register all patches on game boot
Events.OnGameBoot.Add(function()
    print("[NCS] OnGameBoot: applying patches")
    NeatControllerSupport.Crafting:registerAll()
    print("[NCS] Patches applied")
end)

return NeatControllerSupport
