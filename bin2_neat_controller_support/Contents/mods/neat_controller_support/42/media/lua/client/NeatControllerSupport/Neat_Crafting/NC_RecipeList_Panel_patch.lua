-- NeatControllerSupport: NC_RecipeList_Panel Patch
-- 手柄导航配方列表

local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

local NC_RecipeList_Panel_Patch = {}

-- 按钮配置
NC_RecipeList_Panel_Patch.AButton = JoypadUtil.AButton
NC_RecipeList_Panel_Patch.BButton = JoypadUtil.BButton
NC_RecipeList_Panel_Patch.XButton = JoypadUtil.XButton

function NC_RecipeList_Panel_Patch:apply(panel)
    if not panel then return end

    local _patch = NC_RecipeList_Panel_Patch
    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    -- 初始化选中索引
    if not panel.joypadSelectedIndex then
        panel.joypadSelectedIndex = 1
    end

    function panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        -- A 键制作
        if button == _patch.AButton then
            local craftPanel = self.HandCraftPanel and self.HandCraftPanel.craftActionPanel
            if craftPanel and craftPanel.onCraftButtonClick then
                craftPanel:onCraftButtonClick()
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        -- B 键关闭
        if button == _patch.BButton then
            if self.HandCraftPanel and self.HandCraftPanel.close then
                self.HandCraftPanel:close()
            end
            return true
        end

        -- X 键切换筛选
        if button == _patch.XButton then
            local filterBar = self.HandCraftPanel and self.HandCraftPanel.filterBar
            if filterBar then
                filterBar.showOnlyCanMake = not filterBar.showOnlyCanMake
                self.HandCraftPanel:onFilterChanged()
                self.joypadSelectedIndex = 1
                self:createChildren()
                if self.currentScrollView then
                    self.currentScrollView:refreshItems()
                    self.currentScrollView:setYScroll(0)
                end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        return false
    end

    -- R-stick 控制制作数量
    function panel:onJoypadAxisMoved(axis, value)
        if axis ~= 2 and axis ~= 3 then return false end

        local craftPanel = self.HandCraftPanel and self.HandCraftPanel.craftActionPanel
        if not craftPanel or not craftPanel.allowBatchCraft then return false end
        if craftPanel.logic:isCraftActionInProgress() then return false end

        local currentValue = tonumber(craftPanel.quantityInput:getText()) or 1
        local maxCount = math.max(1, craftPanel.logic:getPossibleCraftCount(true))
        local threshold = 0.5
        local changed = false

        if axis == 2 and math.abs(value) >= threshold then
            local newValue = value < 0 and math.max(1, currentValue - 1) or math.min(maxCount, currentValue + 1)
            if newValue ~= currentValue then
                craftPanel.quantityInput:setText(tostring(newValue))
                craftPanel.currentCraftQuantity = newValue
                changed = true
            end
        elseif axis == 3 and math.abs(value) >= threshold then
            local newValue = value < 0 and maxCount or 1
            if newValue ~= currentValue then
                craftPanel.quantityInput:setText(tostring(newValue))
                craftPanel.currentCraftQuantity = newValue
                changed = true
            end
        end

        if changed then getSoundManager():playUISound("UIActivateButton") end
        return changed
    end

    function panel:onJoypadDirDown(dir)
        -- 与鼠标选择同步
        self:syncJoypadIndexFromSelection()

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local direction = JoypadUtil.getJoypadDirection(dir)
        if not direction or not self.logic or not self.filteredRecipes then return false end

        local dataCount = #self.filteredRecipes
        if dataCount == 0 then return false end

        local style = self.logic:getSelectedRecipeStyle() or "list"

        if style == "grid" then
            return self:handleGridNavigation(direction, dataCount)
        else
            return self:handleListNavigation(direction, dataCount)
        end
    end

    -- 列表导航
    function panel:handleListNavigation(dir, dataCount)
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
    function panel:handleGridNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        local cols = self.gridColumnCount or 4
        if self.currentScrollView and self.currentScrollView.cols then
            cols = self.currentScrollView.cols
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

    function panel:selectCurrentItem()
        if self.filteredRecipes and self.HandCraftPanel and self.HandCraftPanel.logic then
            local recipe = self.filteredRecipes[self.joypadSelectedIndex]
            if recipe then
                self.HandCraftPanel.logic:setRecipe(recipe)
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end
        return false
    end

    function panel:updateJoypadSelection()
        if not self.currentScrollView then return end
        local scrollView = self.currentScrollView
        if scrollView.scrollToIndex then scrollView:scrollToIndex(self.joypadSelectedIndex) end
        scrollView:refreshItems()
    end

    function panel:syncJoypadIndexFromSelection()
        if not self.filteredRecipes or not self.HandCraftPanel or not self.HandCraftPanel.logic then return false end

        local currentRecipe = self.HandCraftPanel.logic:getRecipe()
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
end

return NC_RecipeList_Panel_Patch
