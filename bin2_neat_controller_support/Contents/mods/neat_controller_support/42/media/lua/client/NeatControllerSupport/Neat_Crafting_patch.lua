-- NeatControllerSupport: Neat_Crafting Patch
-- Handle joypad navigation for Neat_Crafting components

local NeatCraftingPatch = {}

-- Joypad button configuration
NeatCraftingPatch.closeButton = Joypad.BButton
NeatCraftingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatCraftingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatCraftingPatch.AButton = Joypad.AButton
NeatCraftingPatch.YButton = Joypad.YButton

-- Import component patches
local NC_RecipeList_Panel_Patch = require "NeatControllerSupport/NC_RecipeList_Panel_patch"

-- Get recipeListPanel from window
local function getRecipeListPanel(window)
    if not window then return nil end
    if window.HandCraftPanel and window.HandCraftPanel.recipeListPanel then
        return window.HandCraftPanel.recipeListPanel
    end
    return nil
end

-- Get categoryListPanel from window
local function getCategoryListPanel(window)
    if not window then
        print("[NCS-Crafting] getCategoryListPanel: window is nil")
        return nil
    end
    if window.HandCraftPanel and window.HandCraftPanel.categoryPanel then
        return window.HandCraftPanel.categoryPanel
    end
    return nil
end

-- Get all categories from categoryListPanel (inlined to avoid module dependency)
local function getAllCategories(panel)
    if not panel then return nil end
    local categories = { "", "*" }
    if panel.categories then
        for _, item in ipairs(panel.categories) do
            table.insert(categories, item.categoryValue)
        end
    end
    return categories
end

-- Cycle category - inline implementation
local function cycleCategory(panel, direction)
    if not panel or not panel.selectedCategory then return false end

    local allCategories = getAllCategories(panel)
    if not allCategories or #allCategories == 0 then return false end

    -- Find current category index
    local currentIndex = 1
    local currentCat = panel.selectedCategory
    if currentCat == "*" then
        currentIndex = 2
    else
        for i, cat in ipairs(allCategories) do
            if cat == currentCat then
                currentIndex = i
                break
            end
        end
    end

    -- Calculate new index
    local newIndex
    if direction == "prev" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = #allCategories end
    else
        newIndex = currentIndex + 1
        if newIndex > #allCategories then newIndex = 1 end
    end

    local newCategory = allCategories[newIndex]
    print("[NCS-Crafting] Cycle category: " .. tostring(currentCat) .. " -> " .. tostring(newCategory))

    panel:onCategoryChanged(newCategory)
    return true
end

-- Add joypad support to window
function NeatCraftingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatCraftingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown

    function windowClass:onJoypadDown(button)
        print("[NCS-Crafting] === onJoypadDown ===")
        print("[NCS-Crafting] button: " .. tostring(button))
        -- Handle L1: previous category
        if button == _patch.L1Button then
            print("[NCS-Crafting] L1 pressed - prev category")
            local catPanel = getCategoryListPanel(self)
            if catPanel then
                print("[NCS-Crafting] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "prev")
                print("[NCS-Crafting] cycleCategory result: " .. tostring(result))
                return true
            end
        end

        -- Handle R1: next category
        if button == _patch.R1Button then
            print("[NCS-Crafting] R1 pressed - next category")
            local catPanel = getCategoryListPanel(self)
            if catPanel then
                print("[NCS-Crafting] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "next")
                print("[NCS-Crafting] cycleCategory result: " .. tostring(result))
                return true
            end
        end

        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == _patch.closeButton then
            self.close(self)
            return true
        end

        -- Forward A button to recipeListPanel
        if button == _patch.AButton then
            local panel = getRecipeListPanel(self)
            if panel and panel.onJoypadDown then
                panel:onJoypadDown(button)
                return true
            end
        end

        -- Y button: toggle list/grid view
        if button == _patch.YButton then
            local panel = getRecipeListPanel(self)
            if panel and panel.logic then
                local currentStyle = panel.logic:getSelectedRecipeStyle() or "list"
                local newStyle = (currentStyle == "list") and "grid" or "list"
                panel.logic:setSelectedRecipeStyle(newStyle)
                panel:createChildren()
                panel:updateJoypadSelection()
                print("[NCS-Crafting] Toggle view: " .. currentStyle .. " -> " .. newStyle)
                return true
            end
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        print("[NCS-Crafting] onJoypadDirDown: " .. tostring(dir))
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            print("[NCS-Crafting] originalOnJoypadDirDown result: " .. tostring(result))
            if result then return result end
        end
        -- Forward to recipeListPanel
        local panel = getRecipeListPanel(self)
        print("[NCS-Crafting] recipeListPanel: " .. tostring(panel))
        print("[NCS-Crafting] panel.onJoypadDirDown: " .. tostring(panel and panel.onJoypadDirDown))
        if panel and panel.onJoypadDirDown then
            local forwardResult = panel:onJoypadDirDown(dir)
            print("[NCS-Crafting] forward result: " .. tostring(forwardResult))
            return forwardResult
        end
        return false
    end
end

-- Apply recipe list panel patch (inlined)
function NeatCraftingPatch:addRecipeListJoypad()
    local panel = NC_RecipeList_Panel
    if not panel then return end

    if not panel.joypadSelectedIndex then
        panel.joypadSelectedIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown
    local originalCreateListScrollView = panel.createListScrollView
    local originalCreateGridScrollView = panel.createGridScrollView

    -- Override createListScrollView to add joypad selection support
    if originalCreateListScrollView then
        function NC_RecipeList_Panel:createListScrollView()
            originalCreateListScrollView(self)
            -- Add setJoypadSelected to list items
            local scrollView = self.currentScrollView
            if scrollView and scrollView.setOnUpdateItem then
                local originalOnUpdateItem = scrollView.onUpdateItem
                scrollView:setOnUpdateItem(function(itemObject, recipe)
                    -- Call original update
                    if originalOnUpdateItem then
                        originalOnUpdateItem(itemObject, recipe)
                    end
                    -- Set joypad selected state
                    if itemObject and itemObject.setJoypadSelected then
                        local itemIndex = itemObject.indexInData
                        itemObject:setJoypadSelected(itemIndex == self.joypadSelectedIndex)
                    end
                end)
            end
        end
    end

    -- Override createGridScrollView to add joypad selection support
    if originalCreateGridScrollView then
        function NC_RecipeList_Panel:createGridScrollView()
            originalCreateGridScrollView(self)
            -- Add setJoypadSelected to grid items
            local scrollView = self.currentScrollView
            if scrollView and scrollView.setOnUpdateItem then
                local originalOnUpdateItem = scrollView.onUpdateItem
                scrollView:setOnUpdateItem(function(itemObject, recipe)
                    -- Call original update
                    if originalOnUpdateItem then
                        originalOnUpdateItem(itemObject, recipe)
                    end
                    -- Set joypad selected state
                    if itemObject and itemObject.setJoypadSelected then
                        local itemIndex = itemObject.indexInData
                        itemObject:setJoypadSelected(itemIndex == self.joypadSelectedIndex)
                    end
                end)
            end
        end
    end

    function NC_RecipeList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == Joypad.AButton then
            self:selectRecipeWithJoypad()
            return true
        elseif button == Joypad.BButton then
            if self.HandCraftPanel and self.HandCraftPanel.close then
                self.HandCraftPanel:close()
            end
            return true
        end
        return false
    end

    function NC_RecipeList_Panel:onJoypadDirDown(dir)
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local direction = getJoypadDirection(dir)
        print("[NCS-RecipeList] direction: " .. tostring(direction))
        if not direction then return false end

        if not self.logic or not self.filteredRecipes then return false end

        local style = self.logic:getSelectedRecipeStyle() or "list"
        local dataCount = #self.filteredRecipes
        if dataCount == 0 then return false end

        if style == "grid" then
            return self:handleGridNavigation(direction, dataCount)
        else
            return self:handleListNavigation(direction, dataCount)
        end
    end

    function NC_RecipeList_Panel:handleListNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex

        if dir == "DOWN" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
        elseif dir == "UP" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
        end

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-RecipeList] index changed: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    function NC_RecipeList_Panel:handleGridNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        local cols = self.gridColumnCount or 4

        if dir == "DOWN" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
        elseif dir == "UP" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
        elseif dir == "RIGHT" then
            if self.joypadSelectedIndex % cols ~= 0 then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            end
        elseif dir == "LEFT" then
            if self.joypadSelectedIndex > 1 then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
            end
        end

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-RecipeList] grid index changed: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- Update joypad selection visualization and scroll to selected item
    function NC_RecipeList_Panel:updateJoypadSelection()
        if not self.currentScrollView then return end

        local scrollView = self.currentScrollView
        local selectedIdx = self.joypadSelectedIndex

        -- Update selection state for all visible items
        if scrollView.itemPool then
            for _, item in ipairs(scrollView.itemPool) do
                if item then
                    -- Try to use setJoypadSelected if available
                    if item.setJoypadSelected then
                        local itemIndex = item.indexInData
                        item:setJoypadSelected(itemIndex == selectedIdx)
                    else
                        -- Alternative: try to directly set a selected field
                        item.joypadSelected = (item.indexInData == selectedIdx)
                    end
                end
            end
        end

        -- Refresh items to update selection state
        scrollView:refreshItems()

        -- Scroll to selected index if available
        if scrollView.scrollToIndex then
            scrollView:scrollToIndex(selectedIdx)
        end

        -- Also update the selected recipe in logic if needed
        if self.filteredRecipes and selectedIdx then
            local selectedRecipe = self.filteredRecipes[selectedIdx]
            if selectedRecipe and self.logic and self.logic.setSelectedRecipe then
                self.logic:setSelectedRecipe(selectedRecipe)
            end
        end
    end
end

-- Apply category list panel patch (inlined)
function NeatCraftingPatch:addCategoryListJoypad()
    local panel = NC_CategoryList_Panel
    if not panel then return end

    if not panel.joypadCategoryIndex then
        panel.joypadCategoryIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function NC_CategoryList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            return originalOnJoypadDown(self, button)
        end
        return false
    end

    function NC_CategoryList_Panel:onJoypadDirDown(dir)
        -- Forward to recipeListPanel
        if self.HandCraftPanel and self.HandCraftPanel.recipeListPanel then
            local recipePanel = self.HandCraftPanel.recipeListPanel
            if recipePanel and recipePanel.onJoypadDirDown then
                return recipePanel:onJoypadDirDown(dir)
            end
        end
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end
        return false
    end
end

-- Register all Neat_Crafting patches at once
function NeatCraftingPatch:registerAll()
    if NC_HandcraftWindow then
        self:addJoypad(NC_HandcraftWindow)
    end
    self:addRecipeListJoypad()
    self:addCategoryListJoypad()
end

return NeatCraftingPatch
