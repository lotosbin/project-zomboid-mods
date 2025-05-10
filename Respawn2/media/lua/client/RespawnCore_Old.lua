-- --**************************
-- -- Respawn
-- --**************************
-- --* Coded by: LichKingNZ
-- --* Date Created: 09/01/2022
-- --**************************

-- local option = RespawnOption.Options

-- local RespawnObj = {}
-- local playerData = {}

-- RespawnObj.death = function(player)
--     local id = player:getSteamID()
--     -- print("Player: " .. id .. " is dead")
--     local xp = player:getXp()
--     playerData[id] = {}

--     for i = 0, PerkFactory.PerkList:size() -1 do
--         local perk = PerkFactory.PerkList:get(i)
--         playerData[id][i] = (xp:getXP(perk) * option.xpRate) 
--         -- print(playerData[id][i])
--     end
    
--     Events.OnCreatePlayer.Add(RespawnObj.checkForRespawn)
-- end

-- RespawnObj.checkForRespawn = function(index, player)
--     local function Respawn(player)
--         local id = player:getSteamID()
--         if playerData[id] == nil then
--             return
--         end
    
--         -- print("Respawning player: " .. id)
--         local xp = player:getXp()
        
--         for i = 0, PerkFactory.PerkList:size() -1 do
--             local perk = PerkFactory.PerkList:get(i)
--             xp:AddXP(perk, playerData[id][i], true, true, false, false)
--             -- print(">>>>>>>>>>>>>>>>>ading xp: " .. perk:getName() .. " - " .. playerData[id][i])
--         end
    
--         playerData[id] = {}
--         Events.OnPlayerUpdate.Remove(Respawn)
--     end
--     Events.OnPlayerUpdate.Add(Respawn)
--     Events.OnCreatePlayer.Remove(RespawnObj.checkForRespawn)
-- end



-- function levelUpPerkByIndex(i)
--     print(Perks.fromIndex(i))
--     -- getPlayer():LevelPerk(Perks.fromIndex(i), false)
--     getPlayer():getXp():AddXP(Perks.fromIndex(i), 10000, true, true, false, false)
--     -- getPlayer():getXp():AddXPNoMultiplier(Perks.fromIndex(i), 10000)
-- end

-- local function showXp()
--     local xp = getPlayer():getXp()
--     print(xp:getXP(Perks.Aiming))
-- end

-- local function suicideDebug(key) 
--     if key == 72 then
--         getPlayer():Kill(getPlayer())
--     elseif key == 71 then
--         levelUpPerkByIndex(14)
--         levelUpPerkByIndex(34)
--         levelUpPerkByIndex(33)
--     elseif key == 75 then
--         showXp()
--     end
-- end

-- -- print(getPlayer():getSteamID())
-- -- xp = getPlayer():getXp()
-- -- print(xp:getXP(Perks.Aiming))

-- Events.OnPlayerDeath.Add(RespawnObj.death)
-- Events.OnKeyPressed.Add(suicideDebug)