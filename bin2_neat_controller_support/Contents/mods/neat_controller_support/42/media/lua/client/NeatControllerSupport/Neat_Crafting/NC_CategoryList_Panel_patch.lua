-- NeatControllerSupport: NC_CategoryList_Panel Patch
-- Handle joypad navigation for category list

local NC_CategoryList_Panel_Patch = {}

-- Get all categories from categoryListPanel
local function getAllCategories(panel)
    print("[NCS-Category] getAllCategories called")
    if not panel then
        print("[NCS-Category] panel is nil")
        return nil
    end
    print("[NCS-Category] panel OK")
    print("[NCS-Category] panel.selectedCategory: " .. tostring(panel.selectedCategory))
    print("[NCS-Category] panel.categories: " .. tostring(panel.categories))

    local categories = { "", "*" } -- ALL and Favourites

    if panel.categories then
        print("[NCS-Category] categories count: " .. tostring(#panel.categories))
        for i, item in ipairs(panel.categories) do
            print("[NCS-Category]   [" .. i .. "] categoryValue: " .. tostring(item.categoryValue))
            table.insert(categories, item.categoryValue)
        end
    else
        print("[NCS-Category] panel.categories is nil")
    end

    print("[NCS-Category] total categories: " .. tostring(#categories))
    return categories
end

-- Cycle to previous/next category
local function cycleCategory(panel, direction)
    print("[NCS-Category] === cycleCategory ===")
    print("[NCS-Category] panel: " .. tostring(panel))
    print("[NCS-Category] direction: " .. tostring(direction))

    if not panel then
        print("[NCS-Category] panel is nil, returning false")
        return false
    end

    if not panel.selectedCategory then
        print("[NCS-Category] selectedCategory is nil, returning false")
        return false
    end

    local allCategories = getAllCategories(panel)
    if not allCategories or #allCategories == 0 then
        print("[NCS-Category] no categories found, returning false")
        return false
    end

    -- Find current category index
    local currentIndex = 1
    local currentCat = panel.selectedCategory
    print("[NCS-Category] currentCat: " .. tostring(currentCat))

    if currentCat == "*" then
        currentIndex = 2
    else
        for i, cat in ipairs(allCategories) do
            print("[NCS-Category] checking [" .. i .. "]: " .. tostring(cat))
            if cat == currentCat then
                currentIndex = i
                print("[NCS-Category] found at index: " .. tostring(i))
                break
            end
        end
    end

    print("[NCS-Category] currentIndex: " .. tostring(currentIndex))

    -- Calculate new index
    local newIndex
    if direction == "prev" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = #allCategories end -- wrap to last
        print("[NCS-Category] prev: " .. tostring(currentIndex) .. " -> " .. tostring(newIndex))
    else
        newIndex = currentIndex + 1
        if newIndex > #allCategories then newIndex = 1 end -- wrap to first
        print("[NCS-Category] next: " .. tostring(currentIndex) .. " -> " .. tostring(newIndex))
    end

    local newCategory = allCategories[newIndex]
    print("[NCS-Category] Cycle: " .. tostring(currentCat) .. " -> " .. tostring(newCategory))

    print("[NCS-Category] calling onCategoryChanged...")
    panel:onCategoryChanged(newCategory)
    print("[NCS-Category] onCategoryChanged done")

    return true
end

function NC_CategoryList_Panel_Patch:apply(panel)
    if not panel then
        print("[NCS-Category] panel is nil")
        return
    end

    -- Track selected category index for navigation
    if not panel.joypadCategoryIndex then
        panel.joypadCategoryIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function panel:onJoypadDown(button)
        -- Handle category cycling via L1/R1 from parent handler
        -- This panel doesn't directly handle shoulder buttons
        if originalOnJoypadDown then
            return originalOnJoypadDown(self, button)
        end
        return false
    end

    function panel:onJoypadDirDown(dir)
        -- Forward to recipeListPanel (category panel doesn't handle direction navigation)
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

-- Expose helpers for parent window
NC_CategoryList_Panel_Patch.cycleCategory = cycleCategory
NC_CategoryList_Panel_Patch.getAllCategories = getAllCategories

return NC_CategoryList_Panel_Patch
