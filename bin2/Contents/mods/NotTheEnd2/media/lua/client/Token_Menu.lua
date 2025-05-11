UIAddXP = {};
function UIAddXP.createMenu(_player, _context, _items)
    local player = getSpecificPlayer(_player);
    local clickedItems = _items;

    -- Will store the clicked stuff.
    local item;
    local stack;

    -- stop function if player has selected multiple item stacks
    if #clickedItems > 1 then
        return;
    end

    -- Iterate through all clicked items
    for i, entry in ipairs(clickedItems) do
        -- test if we have a single item
        if instanceof(entry, "InventoryItem") then
            item = entry; -- store in local variable
            break;
        elseif type(entry) == "table" then
            stack = entry;
            break;
        end
    end

    -- Adds context menu entry for single item.
    local deathTokenName = player:getDescriptor():getForename() .. "'s Death Token"
    if item then
        if item:getType() == "DeathToken" then
            local addXP = _context:addOption("Consume Death Token", clickedItems, UIAddXP.ADDXP2, _player, item);
        end
    end

    -- Adds context menu entries for multiple items.
    if stack then
        for i = #stack.items, #stack.items do
            -- print("this is a stack");
            local item = stack.items[i];
            if instanceof(item, "InventoryItem") then
                if item:getType() == "DeathToken" and player:getInventory():contains(item) then
                    local addXP = _context:addOption("Consume Death Token", clickedItems, UIAddXP.ADDXP2, _player, item);
                end
            end
        end
    end
end


function UIAddXP.ADDXP2(clickedItems,_player,item)
    local player = getSpecificPlayer(_player);
    local mod = item:getModData();
    local pMod = player:getModData();
    local addXp = player:getXp();
    local curPerkTab = 1;
    local xpMod = 0;

    pMod.tokensConsumedThisLife = pMod.tokensConsumedThisLife + 1;
    pMod.tokensConsumed = mod.tokenNumber + pMod.tokensConsumedThisLife;
    -- print("tokens consumed",pMod.tokensConsumed);

    if pMod.tokensConsumed < 5 then
        if pMod.tokensConsumed <= 1 then
            xpMod = 0;
        else
            xpMod = (pMod.tokensConsumed - 1);
        end
    else
        xpMod = 5; -- max XP loss is 25% after 5 tokens consumed
    end

    -- print("xpMod" , xpMod);

    for i, k in pairs(Perks) do
        local perk = Perks.FromString(i);
        if PerkFactory.getPerk(perk) ~= nil then
            local rXP = item:getModData().perkTab[curPerkTab]; --mess due to debugging
            local ranXP = (ZombRand(xpMod * 5) / 100);
            local nXP = (ranXP * rXP);
            local mXP = (rXP - nXP);
            local newMult = player:getXp():getMultiplier(perk); --disable multiplier
            if newMult <= 0 then
                newMult = 1;
            end
            if tostring(i) == "Sprinting" then
                player:getXp():AddXP(perk, rXP / SandboxVars.XpMultiplier);
            elseif tostring(i) == "Fitness" or tostring(i) == "Strength" then
                player:getXp():AddXP(perk, rXP);
            else
                player:getXp():AddXPNoMultiplier(perk, rXP * 4 / SandboxVars.XpMultiplier);
            end
            curPerkTab = curPerkTab + 1;
        end
    end

    for i = 0, Perks.getMaxIndex() - 1 do --bullshit to auto level in non-IWBUMS branches
        local perk = PerkFactory.getPerk(Perks.fromIndex(i));
        if perk and perk:getParent() ~= Perks.None then
            local newPerk = {};
            newPerk.perk = Perks.fromIndex(i);
            newPerk.name = perk:getName() .. " (" .. PerkFactory.getPerkName(perk:getParent()) .. ")";
            newPerk.level = player:getPerkLevel(Perks.fromIndex(i));
            newPerk.xpToLevel = perk:getXpForLevel(newPerk.level + 1);
            newPerk.xp = player:getXp():getXP(newPerk.perk) - ISSkillProgressBar.getPreviousXpLvl(perk, newPerk.level);
            local perk2 = PerkFactory.getPerk(Perks.FromString(newPerk.name));
            local multCan = player:getXp():getMultiplier(perk2);

            local pXP = newPerk.xp;
            local pLevel = newPerk.level;
            local tLevel = newPerk.xpToLevel

            for i = 1, 10 do
                if pXP >= perk:getXpForLevel(pLevel + 1) and pLevel < 10 then
                    player:setPerkLevelDebug(newPerk.perk, (pLevel));
                    pLevel = pLevel + 1;
                    tLevel = perk:getXpForLevel(newPerk.level + 1);
                    pXP = player:getXp():getXP(newPerk.perk) - ISSkillProgressBar.getPreviousXpLvl(perk, newPerk.level);
                end
            end
        end
    end

    local function tablen(tab) --gives number of items in a table
        local count = 0;
        for _ in pairs(tab) do
            count = count + 1;
        end
        return count;
    end

    print("Recipes known " .. tablen(mod.kRecipes));

    if mod.kRecipes ~= nil then
        local r = mod.kRecipes;

        for i, k in pairs(r) do
            local d = ZombRand((15 - pMod.tokensConsumed));
            print("Percent chance to forget " .. (1 / d * 100));
            print("Diceroll = " .. d);
            local recipe = k;
            if player:getKnownRecipes():contains(recipe) then
                print("Recipe " .. recipe .. " already known");
            else
                player:getKnownRecipes():add(recipe); --removed chance to forget recipe below
            end
        end
    end

    pMod.lightningFlashes = ZombRand(3) + 1;
    pMod.lightningLevel = 1;

    player:getInventory():Remove(item);
end

Events.OnPreFillInventoryObjectContextMenu.Add(UIAddXP.createMenu);
