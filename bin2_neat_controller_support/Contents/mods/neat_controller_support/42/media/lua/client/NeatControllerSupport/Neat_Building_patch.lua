-- NeatControllerSupport: Neat_Building Patch
-- Handle joypad navigation for Neat_Building components

local NeatBuildingPatch = {}

-- Joypad button configuration
NeatBuildingPatch.closeButton = Joypad.BButton
NeatBuildingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatBuildingPatch.R1Button = Joypad.RBumper or Joypad.R1Button

-- Get categoryPanel from window
local function getCategoryPanel(window)
    if not window then
        print("[NCS-Building] getCategoryPanel: window is nil")
        return nil
    end
    if window.categoryPanel then
        return window.categoryPanel
    end
    return nil
end

-- Get all categories from categoryPanel
local function getAllCategories(panel)
    if not panel then return nil end
    local categories = { "" }
    if panel.categories then
        for _, item in ipairs(panel.categories) do
            table.insert(categories, item.categoryValue)
        end
    end
    return categories
end

-- Cycle category
local function cycleCategory(panel, direction)
    if not panel or not panel.selectedCategory then return false end

    local allCategories = getAllCategories(panel)
    if not allCategories or #allCategories == 0 then return false end

    -- Find current category index
    local currentIndex = 1
    local currentCat = panel.selectedCategory
    for i, cat in ipairs(allCategories) do
        if cat == currentCat then
            currentIndex = i
            break
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
    print("[NCS-Building] Cycle category: " .. tostring(currentCat) .. " -> " .. tostring(newCategory))

    panel:onCategoryChanged(newCategory)
    return true
end

-- Add joypad support to building panel window
function NeatBuildingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatBuildingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown

    function windowClass:onJoypadDown(button)
        print("[NCS-Building] === onJoypadDown ===")
        print("[NCS-Building] button: " .. tostring(button))

        -- Handle L1: previous category
        if button == _patch.L1Button then
            print("[NCS-Building] L1 pressed - prev category")
            local catPanel = getCategoryPanel(self)
            if catPanel then
                print("[NCS-Building] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "prev")
                print("[NCS-Building] cycleCategory result: " .. tostring(result))
                return true
            end
        end

        -- Handle R1: next category
        if button == _patch.R1Button then
            print("[NCS-Building] R1 pressed - next category")
            local catPanel = getCategoryPanel(self)
            if catPanel then
                print("[NCS-Building] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "next")
                print("[NCS-Building] cycleCategory result: " .. tostring(result))
                return true
            end
        end

        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == _patch.closeButton then
            print("[NCS-Building] close button pressed")
            self.close(self)
            return true
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end
        return false
    end
end

-- Register all Neat_Building patches at once
function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then
        self:addJoypad(NB_BuildingPanel)
    end
end

return NeatBuildingPatch
