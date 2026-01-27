-- NeatControllerSupport: Main Entry Point
-- Loads all component patches

local NeatControllerSupport = {}
NeatControllerSupport.Building = require "NeatControllerSupport/Neat_Building/Neat_Building_patch"

-- Register all patches on game boot
Events.OnGameBoot.Add(function()
    print("[NCS] OnGameBoot: applying patches")
    NeatControllerSupport.Building:registerAll()
    print("[NCS] Patches applied")
end)

return NeatControllerSupport
