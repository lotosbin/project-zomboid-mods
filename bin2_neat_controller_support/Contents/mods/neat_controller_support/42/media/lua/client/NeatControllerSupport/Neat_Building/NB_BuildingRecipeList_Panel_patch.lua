-- NeatControllerSupport: NB_BuildingRecipeList_Panel Patch
-- 手柄导航建造配方列表

local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 按钮配置
local AButton = JoypadUtil.AButton
local BButton = JoypadUtil.BButton

-- 直接扩展 NB_BuildingRecipeList_Panel
function NB_BuildingRecipeList_Panel:onJoypadDown(button)
    local originalOnJoypadDown = self._originalOnJoypadDown
    if originalOnJoypadDown then
        local result = originalOnJoypadDown(self, button)
        if result then return true end
    end

    -- A 键建造
    if button == AButton then
        self:executeBuild()
        return true
    elseif button == BButton then
        if self.BuildingPanel and self.BuildingPanel.close then
            self.BuildingPanel:close()
        end
        return true
    end

    return false
end

function NB_BuildingRecipeList_Panel:onJoypadDirDown(dir)
    -- 与鼠标选择同步
    self:syncJoypadIndexFromSelection()

    local originalOnJoypadDirDown = self._originalOnJoypadDirDown
    if originalOnJoypadDirDown then
        local result = originalOnJoypadDirDown(self, dir)
        if result then return result end
    end

    local direction = JoypadUtil.getJoypadDirection(dir)
    if not direction or not self.logic or not self.filteredRecipes then return false end

    local dataCount = #self.filteredRecipes
    if dataCount == 0 then return false end

    -- 确保索引有效
    if not self.joypadSelectedIndex or self.joypadSelectedIndex < 1 then
        self.joypadSelectedIndex = 1
    elseif self.joypadSelectedIndex > dataCount then
        self.joypadSelectedIndex = dataCount
    end

    local prevIndex = self.joypadSelectedIndex
    local style = self.logic:getSelectedRecipeStyle() or "list"

    if style == "grid" then
        return self:handleGridNavigation(direction, dataCount)
    else
        return self:handleListNavigation(direction, dataCount)
    end
end

-- 列表导航
function NB_BuildingRecipeList_Panel:handleListNavigation(dir, dataCount)
    local prevIndex = self.joypadSelectedIndex
    if dir == "down" or dir == "right" then
        self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
    elseif dir == "up" or dir == "left" then
        self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
    end

    if prevIndex ~= self.joypadSelectedIndex then
        self:selectCurrentItem()
        self:updateJoypadSelection()
        return true
    end
    return false
end

-- 网格导航
function NB_BuildingRecipeList_Panel:handleGridNavigation(dir, dataCount)
    local prevIndex = self.joypadSelectedIndex
    local cols = self.gridColumnCount or 4
    if self.scrollView and self.scrollView.cols then
        cols = self.scrollView.cols
    end

    if dir == "down" then
        self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
    elseif dir == "up" then
        self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
    elseif dir == "right" then
        local currentCol = self.joypadSelectedIndex % cols
        if currentCol == 0 then currentCol = cols end
        if currentCol < cols then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
        end
    elseif dir == "left" then
        local currentCol = self.joypadSelectedIndex % cols
        if currentCol == 0 then currentCol = cols end
        if currentCol > 1 then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
        end
    end

    if prevIndex ~= self.joypadSelectedIndex then
        self:selectCurrentItem()
        self:updateJoypadSelection()
        return true
    end
    return false
end

function NB_BuildingRecipeList_Panel:selectCurrentItem()
    if self.filteredRecipes and self.BuildingPanel and self.BuildingPanel.logic then
        local recipe = self.filteredRecipes[self.joypadSelectedIndex]
        if recipe then
            self.BuildingPanel.logic:setRecipe(recipe)
            getSoundManager():playUISound("UIActivateButton")
            return true
        end
    end
    return false
end

function NB_BuildingRecipeList_Panel:executeBuild()
    if not self.filteredRecipes or not self.joypadSelectedIndex then return false end

    local recipe = self.filteredRecipes[self.joypadSelectedIndex]
    if not recipe then return false end

    local buildingPanel = self.BuildingPanel
    if not buildingPanel then return false end

    if buildingPanel.logic:getRecipe() ~= recipe then
        buildingPanel.logic:setRecipe(recipe)
    end
    buildingPanel:startBuild()
    getSoundManager():playUISound("UIActivateButton")
    return true
end

function NB_BuildingRecipeList_Panel:updateJoypadSelection()
    if not self.scrollView then return end
    local scrollView = self.scrollView
    if scrollView.scrollToIndex then scrollView:scrollToIndex(self.joypadSelectedIndex) end
    scrollView:refreshItems()
end

function NB_BuildingRecipeList_Panel:syncJoypadIndexFromSelection()
    if not self.filteredRecipes or not self.BuildingPanel or not self.BuildingPanel.logic then return false end

    local currentRecipe = self.BuildingPanel.logic:getRecipe()
    if not currentRecipe then return false end

    for i, recipe in ipairs(self.filteredRecipes) do
        if recipe == currentRecipe then
            if self.joypadSelectedIndex ~= i then
                self.joypadSelectedIndex = i
                self:updateJoypadSelection()
            end
            return true
        end
    end
    return false
end
