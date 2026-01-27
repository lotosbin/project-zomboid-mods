-- NeatControllerSupport: Neat_Building Patch
-- 手柄导航建造界面
--
-- B42 限制说明：
-- ISBuildIsoEntity 是纯 Java 类，没有暴露 Lua API
-- 以下功能无法通过 Lua 实现：
--   - 放置建筑 (placeBuilding)
--   - 旋转建筑 (rotateBuilding)
--   - 移动建筑 (moveBuilding)
-- 以下功能可用：
--   - 配方列表导航
--   - 分类切换 (LB/RB)
--   - 视图切换 (Y)
--   - 排序切换 (X)
--   - 开始建造/取消建造

local NeatBuildingPatch = {}
local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 按钮配置
NeatBuildingPatch.CloseButton = JoypadUtil.BButton
NeatBuildingPatch.PrevCategoryButton = JoypadUtil.LBumper
NeatBuildingPatch.NextCategoryButton = JoypadUtil.RBumper
NeatBuildingPatch.ConfirmButton = JoypadUtil.AButton
NeatBuildingPatch.ToggleViewButton = JoypadUtil.YButton
NeatBuildingPatch.ToggleSortButton = JoypadUtil.XButton
-- 注意：B42 中 X键用于切换排序，无法用于旋转建筑（API 未暴露）

-- D-pad 方向键 (B42 通过 onJoypadDown 传递: 10=上, 11=下, 12=左, 13=右)
NeatBuildingPatch.DPadUp = 10
NeatBuildingPatch.DPadDown = 11
NeatBuildingPatch.DPadLeft = 12
NeatBuildingPatch.DPadRight = 13

-- 导入面板补丁 (直接扩展 NB_BuildingRecipeList_Panel)
require "NeatControllerSupport/Neat_Building/NB_BuildingRecipeList_Panel_patch"

local function getCategoryPanel(window)
    if not window then return nil end
    return window.categoryPanel
end

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

-- 切换分类
local function cycleCategory(panel, direction)
    if not panel or not panel.selectedCategory then return false end

    local allCategories = getAllCategories(panel)
    if not allCategories or #allCategories == 0 then return false end

    local currentIndex = 1
    local currentCat = panel.selectedCategory
    for i, cat in ipairs(allCategories) do
        if cat == currentCat then currentIndex = i; break end
    end

    local newIndex = direction == "prev"
        and (currentIndex > 1 and currentIndex - 1 or #allCategories)
        or (currentIndex < #allCategories and currentIndex + 1 or 1)

    panel:onCategoryChanged(allCategories[newIndex])
    return true
end

-- 建造模式控制
local function startBuilding(self)
    if not self.logic then return false end
    local recipe = self.logic:getRecipe()
    if not recipe then return false end
    if self.startBuild then
        self:startBuild()
        getSoundManager():playUISound("UIActivateButton")
        return true
    end
    return false
end

local function cancelBuilding(self)
    if self.buildEntity then
        getCell():setDrag(nil, self.player:getPlayerNum())
        self.buildEntity = nil
        return true
    end
    return false
end

-- B42: 建造控制函数已被禁用，因为 ISBuildIsoEntity 没有暴露 Lua API
-- 放置、旋转、移动建筑的功能无法从 Lua 实现
local function placeBuilding(self)
    print("[NCS-Build] placeBuilding: B42 API not available for Lua")
    print("[NCS-Build] 请使用鼠标放置建筑，或按 B 取消")
    return false
end

local function rotateBuilding(self)
    print("[NCS-Build] rotateBuilding: B42 API not available for Lua")
    print("[NCS-Build] 旋转功能无法通过手柄控制")
    return false
end

local function moveBuilding(self, direction)
    print("[NCS-Build] moveBuilding: B42 API not available for Lua")
    print("[NCS-Build] 移动建筑功能无法通过手柄控制")
    return false
end

function NeatBuildingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatBuildingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
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
        -- 非建造模式：A键开始建造
        if not self.buildEntity then
            if button == _patch.ConfirmButton then
                if startBuilding(self) then return true end
            end
        end

        -- 分类切换
        if button == _patch.PrevCategoryButton then
            return cycleCategory(getCategoryPanel(self), "prev")
        end
        if button == _patch.NextCategoryButton then
            return cycleCategory(getCategoryPanel(self), "next")
        end

        -- 切换视图
        if button == _patch.ToggleViewButton then
            if self.recipeListPanel and self.recipeListPanel.logic then
                local currentStyle = self.recipeListPanel.logic:getSelectedRecipeStyle() or "list"
                local newStyle = currentStyle == "list" and "grid" or "list"
                self.recipeListPanel.logic:setSelectedRecipeStyle(newStyle)
                self.recipeListPanel.joypadSelectedIndex = 1
                self.recipeListPanel:createChildren()
                if self.recipeListPanel.currentScrollView then
                    self.recipeListPanel.currentScrollView:refreshItems()
                end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        -- 切换排序
        if button == _patch.ToggleSortButton then
            if self.recipeListPanel and self.recipeListPanel.logic then
                local sortModes = { "RecipeName", "LastUsed", "MostUsed" }
                local currentMode = self.recipeListPanel.logic:getRecipeSortMode() or "RecipeName"
                local currentIndex = 1
                for i, mode in ipairs(sortModes) do
                    if mode == currentMode then currentIndex = i; break end
                end
                local newMode = sortModes[currentIndex % #sortModes + 1]
                self.recipeListPanel.logic:setRecipeSortMode(newMode)
                self.recipeListPanel.logic:sortRecipeList()
                self.recipeListPanel.joypadSelectedIndex = 1
                self.recipeListPanel:createChildren()
                if self.recipeListPanel.currentScrollView then
                    self.recipeListPanel.currentScrollView:refreshItems()
                    self.recipeListPanel.currentScrollView:setYScroll(0)
                end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        -- B键关闭
        if button == _patch.CloseButton then
            self.close(self)
            return true
        end

        return false
    end

    -- 方向键处理 - 委托给面板处理列表导航
    function windowClass:onJoypadDirUp()
        local panel = self.recipeListPanel
        if panel and panel.handleJoypadDirection then
            return panel:handleJoypadDirection("up")
        end
        return false
    end

    function windowClass:onJoypadDirDown(joypadData)
        local panel = self.recipeListPanel
        if panel and panel.handleJoypadDirection then
            return panel:handleJoypadDirection("down")
        end
        return false
    end

    function windowClass:onJoypadDirLeft()
        local panel = self.recipeListPanel
        if panel and panel.handleJoypadDirection then
            return panel:handleJoypadDirection("left")
        end
        return false
    end

    function windowClass:onJoypadDirRight()
        local panel = self.recipeListPanel
        if panel and panel.handleJoypadDirection then
            return panel:handleJoypadDirection("right")
        end
        return false
    end
end

function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then self:addJoypad(NB_BuildingPanel) end
end

return NeatBuildingPatch
