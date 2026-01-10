-- NeatControllerSupport: Neat_Building Patch
-- Handle joypad navigation for Neat_Building components

local NeatBuildingPatch = {}

-- Joypad button configuration
NeatBuildingPatch.closeButton = Joypad.BButton
NeatBuildingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatBuildingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatBuildingPatch.YButton = Joypad.YButton

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

-- Place building with joypad
local function placeBuilding(self)
    if self.buildEntity then
        self.buildEntity:onMouseClick(0, 0)
        return true
    end
    return false
end

-- Cancel building mode with joypad
local function cancelBuilding(self)
    if self.buildEntity then
        getCell():setDrag(nil, self.player:getPlayerNum())
        self.buildEntity = nil
        return true
    end
    return false
end

-- Rotate building with joypad
local function rotateBuilding(self)
    if self.buildEntity then
        self.buildEntity:rotate()
        return true
    end
    return false
end

-- Move building with joypad
local function moveBuilding(self, direction)
    if not self.buildEntity then return false end

    local player = self.player
    if not player then return false end

    local playerObj = player
    if instanceof(player, "IsoPlayer") then
        playerObj = player
    end

    if not playerObj then return false end

    local moveDir = nil
    if direction == "left" then
        moveDir = IsoDirections.W
    elseif direction == "right" then
        moveDir = IsoDirections.E
    elseif direction == "up" then
        moveDir = IsoDirections.N
    elseif direction == "down" then
        moveDir = IsoDirections.S
    end

    if moveDir then
        local currentIso = playerObj:getCurrentSquare()
        if currentIso then
            local nextSquare = currentIso:getNeighbor(moveDir)
            if nextSquare and self.buildEntity:setIsoToBuildSquare(nextSquare) then
                return true
            end
        end
    end

    return false
end

-- Set joypad focus for building mode
local function setJoypadFocusForBuild(self, playerNum)
    if playerNum and playerNum >= 0 then
        setJoypadFocus(playerNum, self)
    else
        local player = self.player
        if player then
            setJoypadFocus(playerNum, nil)
        end
    end
end

-- Add joypad support to building panel window
function NeatBuildingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatBuildingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown
    local originalCreateBuildIsoEntity = windowClass.createBuildIsoEntity

    -- Patch createBuildIsoEntity to set joypad focus
    if originalCreateBuildIsoEntity then
        function windowClass:createBuildIsoEntity(dontSetDrag)
            originalCreateBuildIsoEntity(self, dontSetDrag)
            -- Set joypad focus when entering build mode
            if self.buildEntity then
                setJoypadFocusForBuild(self, self.player:getPlayerNum())
            else
                -- Clear focus when exiting build mode
                setJoypadFocusForBuild(self, -1)
            end
        end
    end

    function windowClass:onJoypadDown(button)
        print("[NCS-Building] === onJoypadDown ===")
        print("[NCS-Building] button: " .. tostring(button))
        print("[NCS-Building] buildEntity: " .. tostring(self.buildEntity))

        -- Handle building mode: A to place, B to cancel, X to rotate
        if self.buildEntity then
            -- A button: place building
            if button == Joypad.AButton then
                print("[NCS-Building] A pressed - place building")
                if placeBuilding(self) then return true end
            end
            -- B button: cancel building
            if button == Joypad.BButton then
                print("[NCS-Building] B pressed - cancel building")
                if cancelBuilding(self) then return true end
            end
            -- X button: rotate building
            if button == Joypad.XButton then
                print("[NCS-Building] X pressed - rotate building")
                if rotateBuilding(self) then return true end
            end
        end

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

        -- Y button: toggle list/grid view
        if button == _patch.YButton then
            if self.recipeListPanel and self.recipeListPanel.logic then
                local currentStyle = self.recipeListPanel.logic:getSelectedRecipeStyle() or "list"
                local newStyle = (currentStyle == "list") and "grid" or "list"
                self.recipeListPanel.logic:setSelectedRecipeStyle(newStyle)
                self.recipeListPanel:createChildren()
                print("[NCS-Building] Toggle view: " .. currentStyle .. " -> " .. newStyle)
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
        -- Handle building mode: move with directions
        if self.buildEntity then
            if dir == Joypad.DirLeft then
                if moveBuilding(self, "left") then return true end
            elseif dir == Joypad.DirRight then
                if moveBuilding(self, "right") then return true end
            elseif dir == Joypad.DirUp then
                if moveBuilding(self, "up") then return true end
            elseif dir == Joypad.DirDown then
                if moveBuilding(self, "down") then return true end
            end
        end

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
