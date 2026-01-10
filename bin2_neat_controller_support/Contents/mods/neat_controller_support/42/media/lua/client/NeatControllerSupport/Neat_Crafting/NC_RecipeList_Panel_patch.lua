-- NeatControllerSupport: NC_RecipeList_Panel Patch
-- Handle joypad navigation for recipe list

local NC_Utils = require "NeatControllerSupport/NC_Utils"
local getJoypadDirection = NC_Utils.getJoypadDirection

local NC_RecipeList_Panel_Patch = {}

-- Joypad button configuration
NC_RecipeList_Panel_Patch.AButton = Joypad.AButton
NC_RecipeList_Panel_Patch.BButton = Joypad.BButton
NC_RecipeList_Panel_Patch.DOWN = Joypad.DOWN
NC_RecipeList_Panel_Patch.UP = Joypad.UP
NC_RecipeList_Panel_Patch.RIGHT = Joypad.RIGHT
NC_RecipeList_Panel_Patch.LEFT = Joypad.LEFT

function NC_RecipeList_Panel_Patch:apply(panel)
    if not panel then
        print("[NCS-RecipeList] panel is nil")
        return
    end

    local _patch = NC_RecipeList_Panel_Patch
    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    -- Track selected recipe index for navigation
    if not panel.joypadSelectedIndex then
        panel.joypadSelectedIndex = 1
    end

    function panel:onJoypadDown(button)
        -- print("[NCS-RecipeList] onJoypadDown: " .. tostring(button))
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == _patch.AButton then
            self:selectRecipeWithJoypad()
            return true
        elseif button == _patch.BButton then
            if self.HandCraftPanel and self.HandCraftPanel.close then
                self.HandCraftPanel:close()
            end
            return true
        end
        return false
    end

    function panel:onJoypadDirDown(dir)
        print("[NCS-RecipeList] onJoypadDirDown called")
        print("[NCS-RecipeList] dir type: " .. type(dir))
        print("[NCS-RecipeList] dir: " .. tostring(dir))
        print("[NCS-RecipeList] originalOnJoypadDirDown: " .. tostring(originalOnJoypadDirDown))

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            print("[NCS-RecipeList] original result: " .. tostring(result))
            if result then return result end
        end

        -- Extract actual direction from JoypadData
        print("[NCS-RecipeList] calling getJoypadDirection...")
        local direction = getJoypadDirection(dir)
        print("[NCS-RecipeList] direction: " .. tostring(direction) .. " type: " .. type(direction))

        if not direction then
            print("[NCS-RecipeList] no direction, returning false")
            return false
        end

        print("[NCS-RecipeList] direction found: " .. tostring(direction))

        -- Safety check
        if not self.logic or not self.filteredRecipes then
            print("[NCS-RecipeList] safety check failed")
            return false
        end

        local style = self.logic:getSelectedRecipeStyle() or "list"
        local dataCount = #self.filteredRecipes
        print("[NCS-RecipeList] style=" .. style .. " count=" .. dataCount)

        if dataCount == 0 then
            print("[NCS-RecipeList] empty list, returning false")
            return false
        end

        if style == "grid" then
            return self:handleGridNavigation(direction, dataCount)
        else
            return self:handleListNavigation(direction, dataCount)
        end
    end

    function panel:handleListNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex

        if dir == _patch.DOWN then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
        elseif dir == _patch.UP then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
        end

        if prevIndex ~= self.joypadSelectedIndex then
            self:scrollToItem(self.joypadSelectedIndex)
            return true
        end
        return false
    end

    function panel:handleGridNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        local cols = self.gridColumnCount or 4

        if dir == _patch.DOWN then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
        elseif dir == _patch.UP then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
        elseif dir == _patch.RIGHT then
            if self.joypadSelectedIndex % cols ~= 0 then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            end
        elseif dir == _patch.LEFT then
            if self.joypadSelectedIndex > 1 then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
            end
        end

        if prevIndex ~= self.joypadSelectedIndex then
            self:scrollToItem(self.joypadSelectedIndex)
            return true
        end
        return false
    end

    function panel:scrollToItem(index)
        if not index or index < 1 or not self.currentScrollView then return end

        local style = "list"
        if self.logic and self.logic.getSelectedRecipeStyle then
            style = self.logic:getSelectedRecipeStyle() or "list"
        end

        local itemHeight, itemSpacing

        if style == "grid" then
            itemHeight = self.gridItemSize or 50
            itemSpacing = self.gridItemSize + (self.gridPadding or 5)
        else
            itemHeight = self.itemHeight or 50
            itemSpacing = self.itemHeight + (self.padding or 5)
        end

        local padding = self.padding or 5
        local targetScroll = padding + (index - 1) * itemSpacing - (self.currentScrollView.height / 2) + (itemHeight / 2)

        self.currentScrollView:setYScroll(math.max(0, targetScroll))
    end

    function panel:selectRecipeWithJoypad()
        local index = self.joypadSelectedIndex
        if not self.filteredRecipes or not index then return end
        local recipe = self.filteredRecipes[index]

        if not recipe or not self.logic then return end
        if not self.logic.getRecipe or not self.logic.setRecipe then return end

        self.logic:setRecipe(recipe)
        if self.currentScrollView then
            self.currentScrollView:refreshItems()
        end
    end
end

return NC_RecipeList_Panel_Patch
