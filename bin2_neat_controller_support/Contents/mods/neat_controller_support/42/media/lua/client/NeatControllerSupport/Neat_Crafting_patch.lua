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

-- 导入面板补丁
local NC_RecipeList_Panel_Patch = require "NeatControllerSupport/Neat_Crafting/NC_RecipeList_Panel_patch"

local function getRecipeListPanel(window)
    if not window then return nil end
    return window.HandCraftPanel and window.HandCraftPanel.recipeListPanel
end

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
            local panel = getRecipeListPanel(self)
            if panel then panel:onJoypadDown(button) end
            return true
        end

        -- 切换视图
        if button == _patch.ToggleViewButton then
            local panel = getRecipeListPanel(self)
            if panel and panel.logic then
                local newStyle = panel.logic:getSelectedRecipeStyle() == "list" and "grid" or "list"
                panel.logic:setSelectedRecipeStyle(newStyle)
                panel.joypadSelectedIndex = 1
                panel:createChildren()
                if panel.currentScrollView then panel.currentScrollView:refreshItems() end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local panel = getRecipeListPanel(self)
        if panel and panel.onJoypadDirDown then
            return panel:onJoypadDirDown(dir)
        end
        return false
    end
end

function NeatCraftingPatch:addRecipeListJoypad()
    local panel = NC_RecipeList_Panel
    if not panel then return end

    -- 使用独立的补丁文件
    NC_RecipeList_Panel_Patch:apply(panel)
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
        local recipePanel = self.HandCraftPanel and self.HandCraftPanel.recipeListPanel
        if recipePanel and recipePanel.onJoypadDirDown then
            return recipePanel:onJoypadDirDown(dir)
        end
        if originalOnJoypadDirDown then return originalOnJoypadDirDown(self, dir) end
        return false
    end
end

function NeatCraftingPatch:registerAll()
    if NC_HandcraftWindow then self:addJoypad(NC_HandcraftWindow) end
    self:addRecipeListJoypad()
    self:addCategoryListJoypad()
end

return NeatCraftingPatch
