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

local function getJoypadDirection(dirData)
    return JoypadUtil.getJoypadDirection(dirData)
end

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
    local panel = NB_BuildingRecipeList_Panel
    if not panel then return end

    if not panel.joypadSelectedIndex then panel.joypadSelectedIndex = 1 end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function NB_BuildingRecipeList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        -- A 键建造
        if button == JoypadUtil.AButton then
            self:executeBuild()
            return true
        elseif button == JoypadUtil.BButton then
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

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local direction = getJoypadDirection(dir)
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
            local cols = self.gridColumnCount or 4
            if self.scrollView and self.scrollView.cols then
                cols = self.scrollView.cols
            end

            if direction == "down" then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
            elseif direction == "up" then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
            elseif direction == "right" then
                local currentCol = self.joypadSelectedIndex % cols
                if currentCol == 0 then currentCol = cols end
                if currentCol < cols then
                    self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
                end
            elseif direction == "left" then
                local currentCol = self.joypadSelectedIndex % cols
                if currentCol == 0 then currentCol = cols end
                if currentCol > 1 then
                    self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
                end
            end
        else
            -- 列表模式：所有方向都是上下移动
            if direction == "down" or direction == "right" then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            elseif direction == "up" or direction == "left" then
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
end

function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then self:addJoypad(NB_BuildingPanel) end
    self:addRecipeListJoypad()
end

return NeatBuildingPatch
