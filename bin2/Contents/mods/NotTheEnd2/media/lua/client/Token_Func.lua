local function initToken3()
	local player = getPlayer();
	-- print("player" , player);
	-- print("player number:" , player:getPlayerNum());
	-- print("Number active:" , getNumActivePlayers());
	for i=1,getNumActivePlayers() do
        local pdata = getPlayerData(i-1)
		-- print("pdata" , pdata);
	end
	for i=0, getNumActivePlayers() -1 do
		-- print("player number" , i)
		local player = getSpecificPlayer(i);
		
		-- print("player index:" , player:getPlayerIndex());
		local pMod = player:getModData(); -- ModData is a table of information stored on each new character, also weapons

		if pMod.initTable == nil then
			-- print("init table nil");
			pMod.initTable = {};
			
			for i, k in pairs(Perks) do
				local perk = Perks.FromString(i);
				-- local perk2 = Perks.fromIndex(i);
				local randXP = ZombRand(1500);
				if PerkFactory.getPerk(Perks.FromString(i)) ~= nil then
					local initXP = player:getXp():getXP(Perks.FromString(i));
					table.insert(pMod.initTable, initXP);
					-- print("Initial XP stored", perk, initXP);
				end
			end
			pMod.lightningLevel = 0; -- lightning Alpha level
			pMod.lightningFlashes = 0; -- number of strikes
						
			pMod.hasToken = false;
			pMod.tokensConsumedThisLife = 0;
			pMod.tokensConsumed = 0;
			-- print(BCdump(pMod.initTable));
			print("INIT TOKEN COMPLETE PLAYER" , i);
		end
	end
end

local function createToken()
	local pMod = getPlayer():getModData();
	local player = getPlayer();
	-- print("player" , player);
	-- print("player number:" , player:getPlayerNum());
	-- print("player index:" , player:getPlayerIndex());
	if pMod.hasToken == false then -- .hasToken prevents the addition of multiple tokensConsumed
		-- print(BCdump(getPlayer():getXp():getXP()));
		
		-- local deathToken = getPlayer():getInventory():AddItem('Token.DeathToken'); -- storing a new item in a variable allows us to easily access it
		local deathToken = player:getSquare():AddWorldInventoryItem('Token.DeathToken', 0,0,0);		
		
		deathToken:setName(getPlayer():getDescriptor():getForename() .. "'s Death Token"); -- haven't tested what happens if same name
		
		deathToken:getModData().kRecipes = {}; -- add blank table to put known recipes
		deathToken:getModData().perkTab = {};
		local r = getPlayer():getKnownRecipes(); -- variable with stored known recipes
		
		for i = 0, r:size()-1 do -- for loop that runs once for every known recipe
			local recipe = r:get(i); -- as loop iterates over recipe, store this recipe in var 'recipe'
			print("Recipe added: " .. recipe);
			table.insert(deathToken:getModData().kRecipes, recipe); -- insert variable 'recipe' into previously created table 'kRecipes'
		end
		
		local curIndex = 1;
		for i, k in pairs(Perks) do
			local perk = Perks.FromString(i);
			local perk2 = tostring(perk);
			local curXP = player:getXp():getXP(perk);
			if PerkFactory.getPerk(perk) ~= nil then
			-- print(perk, curXP);
				
				local negXP = player:getModData().initTable[curIndex];
				local negXP2 = (curXP - negXP);
				
				table.insert(deathToken:getModData().perkTab, negXP2) ;
				
				-- print("Current xp minus initial xp:", perk, player:getXp():getXP(Perks.FromString(i)), negXP, negXP2);
				-- print("Current xp minus initial xp:", perk, curXP, negXP, negXP2); --same as above
				curIndex = curIndex + 1;
			end
		end
		
		deathToken:getModData().tokenNumber = getPlayer():getModData().tokensConsumed + 1;
		
		deathToken:setDescription("Token number " .. tostring(deathToken:getModData().tokenNumber));
		
		-- player:getSquare():AddWorldInventoryItem(deathToken, 0,0,0);
		
		-- getPlayer():Say("Imma Die");
		getPlayer():getModData().hasToken = true; -- prevents creation of multiple tokens
	end
end

local function killPopup() -- stops build 41 popup from displaying on main menu
	MainScreen.instance.animPopup:setVisible(false);
end

local function addRespawn() -- not right, disabled in hooks
	ISPostDeathUI.instance[self.playerIndex].buttonRespawn:setVisible(self.waitOver and allPlayersDead);
end

-- Events.OnMainMenuEnter.Add(killPopup);
Events.OnPlayerDeath.Add(createToken);
Events.OnCreatePlayer.Add(initToken3);