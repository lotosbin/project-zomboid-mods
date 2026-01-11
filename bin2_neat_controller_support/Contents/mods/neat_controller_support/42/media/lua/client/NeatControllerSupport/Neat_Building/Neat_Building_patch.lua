-- NeatControllerSupport: Neat_Building Patch
-- 手柄导航建造界面

local NeatBuildingPatch = {}
local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 按钮配置
NeatBuildingPatch.CloseButton = JoypadUtil.BButton
NeatBuildingPatch.PrevCategoryButton = JoypadUtil.LBumper
NeatBuildingPatch.NextCategoryButton = JoypadUtil.RBumper
NeatBuildingPatch.ConfirmButton = JoypadUtil.AButton
NeatBuildingPatch.ToggleViewButton = JoypadUtil.YButton
NeatBuildingPatch.ToggleSortButton = JoypadUtil.XButton
NeatBuildingPatch.RotateButton = JoypadUtil.XButton

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
local function placeBuilding(self)
    if self.buildEntity then
        self.buildEntity:onMouseClick(0, 0)
        return true
    end
    return false
end

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

local function rotateBuilding(self)
    if self.buildEntity then
        self.buildEntity:rotate()
        return true
    end
    return false
end

local function moveBuilding(self, direction)
    if not self.buildEntity then return false end

    local player = self.player
    if not player then return false end

    local playerObj = instanceof(player, "IsoPlayer") and player or nil
    if not playerObj then return false end

    local moveDir = nil
    if direction == "left" then moveDir = IsoDirections.W
    elseif direction == "right" then moveDir = IsoDirections.E
    elseif direction == "up" then moveDir = IsoDirections.N
    elseif direction == "down" then moveDir = IsoDirections.S
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

function NeatBuildingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatBuildingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown
    local originalCreateBuildIsoEntity = windowClass.createBuildIsoEntity
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

    -- 进入/退出建造模式时设置焦点
    if originalCreateBuildIsoEntity then
        function windowClass:createBuildIsoEntity(dontSetDrag)
            originalCreateBuildIsoEntity(self, dontSetDrag)
            if self.buildEntity then
                setJoypadFocus(self.player:getPlayerNum(), self)
            end
        end
    end

    function windowClass:onJoypadDown(button)

        -- 建造模式控制
        if self.buildEntity then
            if button == _patch.ConfirmButton then
                if placeBuilding(self) then return true end
            elseif button == _patch.CloseButton then
                if cancelBuilding(self) then return true end
            elseif button == _patch.RotateButton then
                if rotateBuilding(self) then return true end
            end
        else
            -- 非建造模式
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

        if button == _patch.CloseButton then
            self.close(self)
            return true
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        local direction = getJoypadDirection(dir)
        if not direction then return false end

        -- 建造模式：方向键移动建筑
        if self.buildEntity then
            if moveBuilding(self, direction) then return true end
        end

        -- 转发到配方列表面板
        if self.recipeListPanel and self.recipeListPanel.onJoypadDirDown then
            local result = self.recipeListPanel:onJoypadDirDown(dir)
            if result then return true end
        end

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end
        return false
    end
end

function NeatBuildingPatch:addRecipeListJoypad()
    -- NB_BuildingRecipeList_Panel 已在 require 时扩展
end

function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then self:addJoypad(NB_BuildingPanel) end
    self:addRecipeListJoypad()
end

return NeatBuildingPatch
