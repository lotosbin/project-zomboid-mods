-- NeatControllerSupport: Neat_Crafting Patch
-- 手柄导航制作界面

local NeatCraftingPatch = {}
local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 按钮配置
NeatCraftingPatch.CloseButton = JoypadUtil.BButton
NeatCraftingPatch.PrevCategoryButton = JoypadUtil.LBumper
NeatCraftingPatch.NextCategoryButton = JoypadUtil.RBumper
NeatCraftingPatch.ConfirmButton = JoypadUtil.AButton
NeatCraftingPatch.ToggleViewButton = JoypadUtil.YButton

-- 导入面板补丁 (直接扩展 NC_RecipeList_Panel)
require "NeatControllerSupport/Neat_Crafting/NC_RecipeList_Panel_patch"

local function getCategoryListPanel(window)
    if not window then return nil end
    return window.HandCraftPanel and window.HandCraftPanel.categoryPanel
end

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

-- 切换分类
local function cycleCategory(panel, direction)
    if not panel or not panel.selectedCategory then return false end

    local allCategories = getAllCategories(panel)
    if not allCategories or #allCategories == 0 then return false end

    local currentIndex = 1
    local currentCat = panel.selectedCategory
    if currentCat == "*" then
        currentIndex = 2
    else
        for i, cat in ipairs(allCategories) do
            if cat == currentCat then currentIndex = i; break end
        end
    end

    local newIndex = direction == "prev"
        and (currentIndex > 1 and currentIndex - 1 or #allCategories)
        or (currentIndex < #allCategories and currentIndex + 1 or 1)

    panel:onCategoryChanged(allCategories[newIndex])
    return true
end

function NeatCraftingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatCraftingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown
    local originalOnOpen = windowClass.onOpen

    -- 窗口打开时设置手柄焦点
    if originalOnOpen then
        function windowClass:onOpen(...)
            originalOnOpen(self, ...)
            if self.player and self.player:getPlayerNum() then
                setJoypadFocus(self.player:getPlayerNum(), self)
            end
        end
    end

    function windowClass:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        -- 分类切换
        if button == _patch.PrevCategoryButton then
            return cycleCategory(getCategoryListPanel(self), "prev")
        end

        if button == _patch.NextCategoryButton then
            return cycleCategory(getCategoryListPanel(self), "next")
        end

        -- 关闭按钮
        if button == _patch.CloseButton then
            self.close(self)
            return true
        end

        -- 确认按钮
        if button == _patch.ConfirmButton then
            local recipePanel = self.HandCraftPanel and self.HandCraftPanel.recipeListPanel
            if recipePanel and recipePanel.onJoypadDown then
                recipePanel:onJoypadDown(button)
            end
            return true
        end

        -- 切换视图
        if button == _patch.ToggleViewButton then
            local recipePanel = self.HandCraftPanel and self.HandCraftPanel.recipeListPanel
            if recipePanel and recipePanel.logic then
                local newStyle = recipePanel.logic:getSelectedRecipeStyle() == "list" and "grid" or "list"
                recipePanel.logic:setSelectedRecipeStyle(newStyle)
                recipePanel.joypadSelectedIndex = 1
                recipePanel:createChildren()
                if recipePanel.currentScrollView then recipePanel.currentScrollView:refreshItems() end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result == true then return result end
        end

        local recipePanel = self.HandCraftPanel and self.HandCraftPanel.recipeListPanel
        if recipePanel and recipePanel.onJoypadDirDown then
            local result = recipePanel:onJoypadDirDown(dir)
            if result == true then return true end
        end
        return false
    end
end

function NeatCraftingPatch:addCategoryListJoypad()
    local panel = NC_CategoryList_Panel
    if not panel then return end
    if not panel.joypadCategoryIndex then panel.joypadCategoryIndex = 1 end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function NC_CategoryList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then return originalOnJoypadDown(self, button) end
        return false
    end

    function NC_CategoryList_Panel:onJoypadDirDown(dir)
        -- Forward to recipe list panel for navigation
        local recipePanel = self.HandCraftPanel and self.HandCraftPanel.recipeListPanel
        if recipePanel and recipePanel.onJoypadDirDown then
            local result = recipePanel:onJoypadDirDown(dir)
            if result == true then return true end
        end
        -- Fall through to original handler
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result == true then return result end
        end
        return false
    end
end

function NeatCraftingPatch:registerAll()
    if NC_HandcraftWindow then self:addJoypad(NC_HandcraftWindow) end
    self:addCategoryListJoypad()
end

return NeatCraftingPatch
