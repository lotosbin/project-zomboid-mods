-- =============================================================================
-- COORDINATE VIEWER
-- by RoboMat & Turbotutone
-- 
-- Created: 07.08.13 - 21:31
--
-- Not my most elegant code, but it works :D
-- =============================================================================

local function initToken()
	local player = getPlayer();
	local pMod = player:getModData();
	if pMod.initSprinting == nil then
		pMod.initSprinting = player:getXp():getXP(Perks.Sprinting);
	-- pMod.initSneak = player:getXp():getXP(Perks.Sneak);
	-- pMod.initNimble = player:getXp():getXP(Perks.Nimble);
	-- pMod.initLightfoot = player:getXp():getXP(Perks.Lightfoot);
	end
	print("fuck");
	print(pMod.initSprinting);
end

local version = "0.7.2";
local author = "RoboMat & Turbotutone & Mist";
local modName = "Coordinate Viewer(Mist)";

local FONT_SMALL = UIFont.Small;
local T_MANAGER = getTextManager();

local SCREEN_X = 20;
local SCREEN_Y = 300;

local flag = true;
local floor = math.floor;
local print = print;

local mouseX = 0;
local mouseY = 0;

-- ------------------------------------------------
-- Functions
-- ------------------------------------------------
---
-- Prints out the mod info on startup and initializes a new
-- trait.
local function initInfo()
	print("Mod Loaded: " .. modName .. " by " .. author .. " (v" .. version .. ")");
end

---
-- Checks if the P key is pressed to activate / deactivate the
-- debug menu.
-- @param _key - The key which was pressed by the player.
--
local function checkKey(_key)
	local key = _key;
	if key == 25 then
		-- flag = not flag; -- reverse flag
		-- ISAdminPanelUI:setVisible();
	end
end

---
-- Round up if decimal is higher than 0.5 and down if it is smaller.
-- @param _num
--
local function round(_num)
	local number = _num;
	return number <= 0 and floor(number) or floor(number + 0.5);
end

---
-- Creates a small overlay UI that shows debug info if the
-- P key is pressed.
local function showDebugger()
	local player = getSpecificPlayer(0);
		
	-- local xP1 = player:getXp();

	if player then
		-- print("Shit started");
		-- Absolute Coordinates.
		local absX = player:getX();
		local absY = player:getY();

		-- Relative Coordinates.
		local cellX = absX / 300;
		local cellY = absY / 300;
		local locX = absX % 300;
		local locY = absY % 300;

		-- Detect room.
		local room = player:getCurrentSquare():getRoom();
		local roomTxt;
		local pMod = player:getModData();
		if pMod.lightningFlashes ~= nil then
			lightF = pMod.lightningFlashes;
			lightL = pMod.lightningLevel;
			else
			lightF = "nothing";
			lightL = "nothing";
		end
		
		local pTab = pMod;
		-- local xp0 = pMod.initSprinting;
		-- local xpAA = player:getXp():getXP(Perks.Sprinting);
		local xp1 = player:getXp():getXP(Perks.Sprinting);
		local xp2 = player:getXp():getXP(Perks.Sneak);
		local xp3 = player:getXp():getXP(Perks.Nimble);
		local xp4 = player:getXp():getXP(Perks.Lightfoot);
		
		local xp5 = player:getXp():getXP(Perks.Aiming);
		local xp6 = player:getXp():getXP(Perks.Reloading);
		
		local xp7 = player:getXp():getXP(Perks.Axe);
		local xp8 = player:getXp():getXP(Perks.Blunt);
		local xp9 = player:getXp():getXP(Perks.SmallBlunt);
		local xp10 = player:getXp():getXP(Perks.LongBlade);
		local xp11 = player:getXp():getXP(Perks.SmallBlade);
		local xp12 = player:getXp():getXP(Perks.Spear);
		local xp13 = player:getXp():getXP(Perks.Maintenance);
		
		local xp14 = player:getXp():getXP(Perks.BladeGuard);
		local xp15 = player:getXp():getXP(Perks.BladeMaintenance);
		local xp16 = player:getXp():getXP(Perks.BluntGuard);
		local xp17 = player:getXp():getXP(Perks.BluntMaintenance);
		
		local xp18 = player:getXp():getXP(Perks.Woodwork);
		local xp19 = player:getXp():getXP(Perks.Cooking);
		local xp20 = player:getXp():getXP(Perks.Farming);
		local xp21 = player:getXp():getXP(Doctor);
		local xp22 = player:getXp():getXP(Perks.Electricity);
		local xp23 = player:getXp():getXP(Perks.MetalWelding);
		local xp24 = player:getXp():getXP(Perks.Mechanics);
		
		-- local xp25 = player:getXp():getXP(Fishing);
		local xp26 = player:getXp():getXP(Perks.Trapping);
		local xp27 = player:getXp():getXP(Perks.PlantScavenging);
		
		local xp28 = player:getXp():getXP(Perks.Melting);
		
		local xp29 = player:getXp():getXP(Perks.Fitness);
		local xp30 = player:getXp():getXP(Perks.Strength);
		
		local toksCL = pMod.tokensConsumedThisLife;
		local toksCT = pMod.tokensConsumed;
		
		if room then
			local roomName = player:getCurrentSquare():getRoom():getName();
			roomTxt = roomName;
		else
			roomTxt = "outside";
		end

		local strings = {
			"You are here:",
			"X: " .. round(absX),
			"Y: " .. round(absY),
			-- "Sprint init: " .. xp0,
			"Health 1 " .. getPlayer():getHealth(),
			"Health BD " .. getPlayer():getBodyDamage():getHealth(),
			"",
			"Current Room: " .. roomTxt,
			"",
			"Lightning level: " .. lightL,
			"Lightning flashes: " .. lightF,
			"",
			"Sprinting XP earned: " .. xp1,
			"Sneak XP earned: " .. xp2,
			"Nimble XP earned: " .. xp3,
			"Lightfoot XP earned: " .. xp4,
			"Aiming XP earned: " .. xp5,
			"Reloading XP earned: " .. xp6,
			"Axe XP earned: " .. xp7,
			"Blunt XP earned: " .. xp8,
			"SmallBlunt XP earned: " .. xp9,
			-- "LongBlade XP earned: " .. xp10,
			-- "SmallBlade XP earned: " .. xp11,
			-- "Spear XP earned: " .. xp12,
			"Maintenance XP earned: " .. xp13,
			-- "BladeGuard XP earned: " .. xp14,
			-- "BladeMaintenance XP earned: " .. xp15,
			-- "BluntGuard XP earned: " .. xp16,
			-- "BluntMaintenance XP earned: " .. xp17,
			-- "Woodwork XP earned: " .. xp18,
			-- "Cooking XP earned: " .. xp19,
			-- "Farming XP earned: " .. xp20,
			-- "Doctor XP earned: " .. xp21,
			-- "Electricity XP earned: " .. xp22,
			-- "MetalWelding XP earned: " .. xp23,
			-- "Mechanics XP earned: " .. xp24,
			-- "Fishing XP earned: " .. xp25,
			-- "Trapping XP earned: " .. xp26,
			-- "PlantScavenging XP earned: " .. xp27,
			-- "Melting XP earned: " .. xp27,
			-- "Fitness XP earned: " .. xp27,
			-- "Strength XP earned: " .. xp27,
			-- "Tokens consumed this life: " .. toksCL,
			-- "Tokens consumed total: " .. toksCT,
			"Sandbox Mutliplier: " .. SandboxVars.XpMultiplier,
		};

		local txt;
		for i = 1, #strings do
			txt = strings[i];
			-- if txt ~= nil then
			-- print(BCdump(txt));
			-- end
			if txt then
			T_MANAGER:DrawString(FONT_SMALL, SCREEN_X, SCREEN_Y + (i * 10), txt, 1, 1, 1, 1);
			else
			T_MANAGER:DrawString(FONT_SMALL, SCREEN_X, SCREEN_Y + (i * 10), "nil", 1, 1, 1, 1);
			end
		end
	end
end


---
-- @param x
-- @param y
--
local function readTile(_x, _y)
	mouseX, mouseY = ISCoordConversion.ToWorld(getMouseX(), getMouseY(), 0);
	mouseX = round(mouseX);
	mouseY = round(mouseY);

	local cell = getWorld():getCell();
	local sq = cell:getGridSquare(mouseX, mouseY, 0);
	
	if sq then
		local sqModData = sq:getModData();

		print("=====================================================");
		print("MODDATA SQUARE: ", mouseX, mouseY, "Params: ", _x, _y);
		for k, v in pairs(sqModData) do
			print(k, v);
		end
		local objs = sq:getObjects();
		local objs_size = objs:size();
		print("OBJECTS FOUND: ", objs_size - 1, "real", objs_size)
		if objs_size > 0 then
			for i = 0, objs_size - 1, 1 do
				print(" " .. tostring(i) .. "-", objs:get(i));
				if objs:get(i):getName() then
					print("  - ", objs:get(i):getName());
				else
					print("  - ", "unknown");
				end
			end
		end
		print("=====================================================");
	end
end


-- Events.OnKeyPressed.Add(checkKey);
-- Events.OnPostUIDraw.Add(showDebugger);

-- Events.OnGameBoot.Add(initInfo);
-- Events.OnCreatePlayer.Add(initToken);
