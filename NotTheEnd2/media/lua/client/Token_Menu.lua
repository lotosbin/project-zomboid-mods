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
    if item then
        -- Check if it is one of our containers
        if item:getType() == "DeathToken" then
            -- local addXP = _context:addOption("Consume Death Token", clickedItems, nil);
            local addXP = _context:addOption("Consume Death Token", clickedItems, UIAddXP.ADDXP2, player, item);
            -- xpSub = _context:getNew(_context);
            -- _context:addSubMenu(addXP, xpSub);
            -- xpSub:addOption("Add Combat XP", clickedItems, UIAddXP.replaceHairV2, player, item, name);
        end
        usedItem = item;
    end

    -- Adds context menu entries for multiple items.
    if stack then
        for i = #stack.items, #stack.items do
            -- print("this is a stack");
            local item = stack.items[i];
            if instanceof(item, "InventoryItem") then
                usedItem = item;
                if item:getType() == "DeathToken" and player:getInventory():contains(usedItem) then
                    local addXP = _context:addOption("Consume Death Token", clickedItems, UIAddXP.ADDXP2, player, item);
                    -- local addRandXP = _context:addOption("Add Random XP", clickedItems, UIAddXP.randXP2, player, item);
                end
                if item:getCategory() == "Weapon" then
                    -- local addEnd = _context:addOption("End it all", clickedItems, UIAddXP.endIt, player, item);
                end
            end
        end
    end
end

function UIAddXP.endIt() --function for suicide, disabled for mod
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Neck):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Groin):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.ForeArm_L):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.ForeArm_R):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_L):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_R):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.UpperArm_L):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.UpperArm_R):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.UpperLeg_L):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.UpperLeg_R):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Torso_Upper):generateDeepWound();
    getPlayer():getBodyDamage():getBodyPart(BodyPartType.Torso_Lower):generateDeepWound();
    getPlayer():PlayAnimUnlooped("Attack_Shove"); -- need to figure this out
end

function UIAddXP.randXP2() --function to add a bunch of XP for debugging, disabled for mod
    -- getPlayer():getXp():AddXP(Perks.Sneak, 200);
    for i = 0, Perks.getMaxIndex() - 1 do
        local perk = PerkFactory.getPerk(Perks.fromIndex(i));
        -- print("perk", perk);
        -- local perk2 = PerkFactory.getPerk(Perks.FromString(i+1));
        -- local perk2 = PerkFactory.getPerk(Perks.FromString(perk));
        if perk and perk:getParent() ~= Perks.None then
            getPlayer():getXp():AddXPNoMultiplier(Perks.fromIndex(i), (math.floor(25 * 4 / SandboxVars.XpMultiplier)));
            -- print("1Perk: " .. tostring(perk) .. " / XP Added: " .. math.floor(25*4/SandboxVars.XpMultiplier));
            -- getPlayer():getXp():AddXP(Perks.fromIndex(i), (math.floor(25/SandboxVars.XpMultiplier)));
            -- print("2Perk: " .. tostring(i) .. " / XP Added: " .. math.floor(25/SandboxVars.XpMultiplier));

            local newPerk = {};
            newPerk.perk = Perks.fromIndex(i);
            newPerk.name = perk:getName() .. " (" .. PerkFactory.getPerkName(perk:getParent()) .. ")";
            newPerk.level = player:getPerkLevel(Perks.fromIndex(i));
            newPerk.xpToLevel = perk:getXpForLevel(newPerk.level + 1);
            newPerk.xp = player:getXp():getXP(newPerk.perk) - ISSkillProgressBar.getPreviousXpLvl(perk, newPerk.level);
            -- print(newPerk.perk, newPerk.name, newPerk.level, newPerk.xpToLevel, newPerk.xp);
            local perk2 = PerkFactory.getPerk(Perks.FromString(newPerk.name));
            local multCan = player:getXp():getMultiplier(perk2);


            local pXP = newPerk.xp;
            local pLevel = newPerk.level;
            local tLevel = newPerk.xpToLevel

            -- if pXP >= tLevel then
            -- getPlayer():setPerkLevelDebug(newPerk.perk, (pLevel + 1));
            -- end
            for i = 1, 10 do
                if pXP >= perk:getXpForLevel(pLevel + 1) and pLevel < 10 then
                    getPlayer():setPerkLevelDebug(newPerk.perk, (pLevel));
                    pLevel = pLevel + 1;
                    -- getPlayer():setPerkLevelDebug(newPerk.perk, (pLevel));
                    -- print("pXP", pXP, "tLevel", tLevel);
                    tLevel = perk:getXpForLevel(newPerk.level + 1);
                    pXP = player:getXp():getXP(newPerk.perk) - ISSkillProgressBar.getPreviousXpLvl(perk, newPerk.level);
                end
                -- print(i);
                -- print("plevel", pLevel);
                -- print("tlevel", tLevel);
            end
            -- print(newPerk.perk, newPerk.name, newPerk.level, newPerk.xpToLevel, newPerk.xp);
        end
    end
end

function UIAddXP.ADDXP2(player,item)
    local mod = usedItem:getModData();
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
            local rXP = usedItem:getModData().perkTab[curPerkTab]; --mess due to debugging
            local ranXP = (ZombRand(xpMod * 5) / 100);
            local nXP = (ranXP * rXP);
            local mXP = (rXP - nXP);
            local newMult = player:getXp():getMultiplier(perk); --disable multiplier
            if newMult <= 0 then
                newMult = 1;
            end
            -- if tostring(i) == "Sprinting" or tostring(i) == "Fitness" or tostring(i) == "Strength" then
            if tostring(i) == "Sprinting" then
                -- getPlayer():getXp():AddXP(perk, (mXP/newMult)); -- original
                player:getXp():AddXP(perk, rXP / SandboxVars.XpMultiplier);
                -- getPlayer():getXp():AddXPNoMultiplier(perk, rXP/SandboxVars.XpMultiplier); --fucking strength and fitness have natural 125% boost
                -- print("Sprinting/Fitness/Strength");
            elseif tostring(i) == "Fitness" or tostring(i) == "Strength" then
                player:getXp():AddXP(perk, rXP);
            else
                -- getPlayer():getXp():AddXP(perk, (mXP*4/newMult)); -- original
                -- getPlayer():getXp():AddXPNoMultiplier(perk, (mXP*4/newMult)); -- test
                -- getPlayer():getXp():AddXPNoMultiplier(perk, (rXP/SandboxVars.XpMultiplier)); --test 2, no XP degredation
                player:getXp():AddXPNoMultiplier(perk, rXP * 4 / SandboxVars.XpMultiplier); --test 3, no XP degredation
                -- print("Perk is " .. tostring(i) .. ". With XP added: " .. rXP*4/SandboxVars.XpMultiplier)
            end
            curPerkTab = curPerkTab + 1;
        end
    end

    for i = 0, Perks.getMaxIndex() - 1 do --bullshit to auto level in non-IWBUMS branches
        local perk = PerkFactory.getPerk(Perks.fromIndex(i));
        if perk and perk:getParent() ~= Perks.None then
            -- getPlayer():getXp():AddXP(Perks.fromIndex(i), (4500));
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
                -- if d >= 1 then --highest of 10% chance to forget recipe
                -- getPlayer():getKnownRecipes():add(recipe);
                -- print("Recipe added " .. recipe);
                -- print(i, k);
                -- else
                -- print("Recipe lost " .. recipe);
                -- end
            end
        end
    end

    pMod.lightningFlashes = ZombRand(3) + 1;
    pMod.lightningLevel = 1;

    player:getInventory():Remove(usedItem);
end

Events.OnPreFillInventoryObjectContextMenu.Add(UIAddXP.createMenu);
