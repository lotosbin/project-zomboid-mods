-- NeatControllerSupport: Neat_Building 补丁
-- 处理 Neat_Building 组件的手柄导航

local NeatBuildingPatch = {}

-- 手柄按钮配置
NeatBuildingPatch.closeButton = Joypad.BButton
NeatBuildingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatBuildingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatBuildingPatch.YButton = Joypad.YButton
NeatBuildingPatch.XButton = Joypad.XButton

-- 从窗口获取 categoryPanel
local function getCategoryPanel(window)
    if not window then
        print("[NCS-Building] getCategoryPanel: window 为空")
        return nil
    end
    if window.categoryPanel then
        return window.categoryPanel
    end
    return nil
end

-- 从 categoryPanel 获取所有分类
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

    -- 查找当前分类索引
    local currentIndex = 1
    local currentCat = panel.selectedCategory
    for i, cat in ipairs(allCategories) do
        if cat == currentCat then
            currentIndex = i
            break
        end
    end

    -- 计算新索引
    local newIndex
    if direction == "prev" then
        newIndex = currentIndex - 1
        if newIndex < 1 then newIndex = #allCategories end
    else
        newIndex = currentIndex + 1
        if newIndex > #allCategories then newIndex = 1 end
    end

    local newCategory = allCategories[newIndex]
    print("[NCS-Building] 切换分类: " .. tostring(currentCat) .. " -> " .. tostring(newCategory))

    panel:onCategoryChanged(newCategory)
    return true
end

-- 使用手柄放置建筑
local function placeBuilding(self)
    if self.buildEntity then
        self.buildEntity:onMouseClick(0, 0)
        return true
    end
    return false
end

-- 使用手柄取消建造模式
local function cancelBuilding(self)
    if self.buildEntity then
        getCell():setDrag(nil, self.player:getPlayerNum())
        self.buildEntity = nil
        return true
    end
    return false
end

-- 使用手柄旋转建筑
local function rotateBuilding(self)
    if self.buildEntity then
        self.buildEntity:rotate()
        return true
    end
    return false
end

-- 使用手柄移动建筑
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

-- 设置建造模式的手柄焦点
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

-- 为建筑面板窗口添加手柄支持
function NeatBuildingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatBuildingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown
    local originalCreateBuildIsoEntity = windowClass.createBuildIsoEntity

    -- 重写 createBuildIsoEntity 以设置手柄焦点
    if originalCreateBuildIsoEntity then
        function windowClass:createBuildIsoEntity(dontSetDrag)
            originalCreateBuildIsoEntity(self, dontSetDrag)
            -- 进入建造模式时设置手柄焦点
            if self.buildEntity then
                setJoypadFocusForBuild(self, self.player:getPlayerNum())
            else
                -- 退出建造模式时清除焦点
                setJoypadFocusForBuild(self, -1)
            end
        end
    end

    function windowClass:onJoypadDown(button)
        print("[NCS-Building] === onJoypadDown ===")
        print("[NCS-Building] 按钮: " .. tostring(button))
        print("[NCS-Building] buildEntity: " .. tostring(self.buildEntity))

        -- 处理建造模式: A 放置, B 取消, X 旋转
        if self.buildEntity then
            -- A 按钮: 放置建筑
            if button == Joypad.AButton then
                print("[NCS-Building] A 按下 - 放置建筑")
                if placeBuilding(self) then return true end
            end
            -- B 按钮: 取消建造
            if button == Joypad.BButton then
                print("[NCS-Building] B 按下 - 取消建造")
                if cancelBuilding(self) then return true end
            end
            -- X 按钮: 旋转建筑
            if button == Joypad.XButton then
                print("[NCS-Building] X 按下 - 旋转建筑")
                if rotateBuilding(self) then return true end
            end
        end

        -- L1 键: 上一个分类
        if button == _patch.L1Button then
            print("[NCS-Building] L1 按下 - 上一个分类")
            local catPanel = getCategoryPanel(self)
            if catPanel then
                print("[NCS-Building] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "prev")
                print("[NCS-Building] cycleCategory 结果: " .. tostring(result))
                return true
            end
        end

        -- R1 键: 下一个分类
        if button == _patch.R1Button then
            print("[NCS-Building] R1 按下 - 下一个分类")
            local catPanel = getCategoryPanel(self)
            if catPanel then
                print("[NCS-Building] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "next")
                print("[NCS-Building] cycleCategory 结果: " .. tostring(result))
                return true
            end
        end

        -- Y 键: 切换列表/网格视图
        if button == _patch.YButton then
            if self.recipeListPanel and self.recipeListPanel.logic then
                local currentStyle = self.recipeListPanel.logic:getSelectedRecipeStyle() or "list"
                local newStyle = (currentStyle == "list") and "grid" or "list"

                print("[NCS-Building] 切换视图: " .. currentStyle .. " -> " .. newStyle)

                -- 设置新的视图样式
                self.recipeListPanel.logic:setSelectedRecipeStyle(newStyle)

                -- 重置选中状态
                self.recipeListPanel.joypadSelectedIndex = 1

                -- 全面刷新 UI
                self.recipeListPanel:createChildren()

                -- 刷新滚动视图
                if self.recipeListPanel.currentScrollView then
                    self.recipeListPanel.currentScrollView:refreshItems()
                end

                -- 播放声音
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        -- X 键: 循环切换排序方法
        if button == _patch.XButton then
            if self.recipeListPanel and self.recipeListPanel.logic then
                local sortModes = { "RecipeName", "LastUsed", "MostUsed" }
                local currentMode = self.recipeListPanel.logic:getRecipeSortMode() or "RecipeName"
                local currentIndex = 1
                for i, mode in ipairs(sortModes) do
                    if mode == currentMode then
                        currentIndex = i
                        break
                    end
                end
                local newIndex = currentIndex % #sortModes + 1
                local newMode = sortModes[newIndex]

                print("[NCS-Building] 切换排序: " .. currentMode .. " -> " .. newMode)

                -- 设置新的排序模式
                self.recipeListPanel.logic:setRecipeSortMode(newMode)
                self.recipeListPanel.logic:sortRecipeList()

                -- 重置选中状态
                self.recipeListPanel.joypadSelectedIndex = 1

                -- 全面刷新 UI
                self.recipeListPanel:createChildren()

                -- 刷新滚动视图
                if self.recipeListPanel.currentScrollView then
                    self.recipeListPanel.currentScrollView:refreshItems()
                end

                -- 滚动到顶部
                if self.recipeListPanel.currentScrollView and self.recipeListPanel.currentScrollView.setYScroll then
                    self.recipeListPanel.currentScrollView:setYScroll(0)
                end

                -- 播放声音
                getSoundManager():playUISound("UIActivateButton")

                return true
            end
        end

        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == _patch.closeButton then
            print("[NCS-Building] 关闭按钮按下")
            self.close(self)
            return true
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        print("[NCS-Building] onJoypadDirDown: " .. tostring(dir))

        -- 从 JoypadData 对象提取方向
        local direction = getJoypadDirection(dir)
        print("[NCS-Building] direction=" .. tostring(direction))

        -- 处理建造模式: 使用方向键移动
        if self.buildEntity and direction then
            -- 转换大写为小写
            local moveDir = string.lower(direction)
            print("[NCS-Building] 建造模式移动建筑: " .. moveDir)
            if moveBuilding(self, moveDir) then
                print("[NCS-Building] 移动成功")
                return true
            else
                print("[NCS-Building] 移动失败")
            end
        end

        -- 转发到 recipeListPanel 处理配方导航
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

-- 注册所有 Neat_Building 补丁
function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then
        self:addJoypad(NB_BuildingPanel)
    end
    -- 添加 recipeListPanel 的手柄支持
    self:addRecipeListJoypad()
end

-- 为 recipeListPanel 添加手柄支持
function NeatBuildingPatch:addRecipeListJoypad()
    local panel = NB_RecipeList_Panel
    if not panel then return end

    if not panel.joypadSelectedIndex then
        panel.joypadSelectedIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function NB_RecipeList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == Joypad.AButton then
            -- A 键：执行建造（和双击效果相同）
            self:executeBuild()
            return true
        elseif button == Joypad.BButton then
            if self.BuildingPanel and self.BuildingPanel.close then
                self.BuildingPanel:close()
            end
            return true
        end
        return false
    end

    function NB_RecipeList_Panel:onJoypadDirDown(dir)
        print("[NCS-Building-List] onJoypadDirDown dir=" .. tostring(dir))

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local direction = getJoypadDirection(dir)
        print("[NCS-Building-List] 方向=" .. tostring(direction))

        if not direction then return false end
        if not self.logic or not self.filteredRecipes then return false end

        local dataCount = #self.filteredRecipes
        print("[NCS-Building-List] dataCount=" .. tostring(dataCount) .. " joypadSelectedIndex=" .. tostring(self.joypadSelectedIndex))

        if dataCount == 0 then return false end

        -- 确保索引在有效范围内
        if not self.joypadSelectedIndex or self.joypadSelectedIndex < 1 then
            self.joypadSelectedIndex = 1
        elseif self.joypadSelectedIndex > dataCount then
            self.joypadSelectedIndex = dataCount
        end

        local prevIndex = self.joypadSelectedIndex
        local style = self.logic:getSelectedRecipeStyle() or "list"

        if style == "grid" then
            local cols = self.gridColumnCount or 4
            if self.currentScrollView and self.currentScrollView.cols then
                cols = self.currentScrollView.cols
            end

            if direction == "DOWN" then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
            elseif direction == "UP" then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
            elseif direction == "RIGHT" then
                local currentCol = self.joypadSelectedIndex % cols
                if currentCol == 0 then currentCol = cols end
                if currentCol < cols then
                    self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
                end
            elseif direction == "LEFT" then
                local currentCol = self.joypadSelectedIndex % cols
                if currentCol == 0 then currentCol = cols end
                if currentCol > 1 then
                    self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
                end
            end
        else
            -- 列表模式
            if direction == "DOWN" then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            elseif direction == "UP" then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
            end
        end

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-Building-List] 索引改变: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            self:selectCurrentItem()
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- 选择当前项并触发选择逻辑
    function NB_RecipeList_Panel:selectCurrentItem()
        print("[NCS-Building-List] selectCurrentItem joypadSelectedIndex=" .. tostring(self.joypadSelectedIndex))

        -- 直接从 filteredRecipes 获取配方并设置
        if self.filteredRecipes and self.BuildingPanel and self.BuildingPanel.logic then
            local recipe = self.filteredRecipes[self.joypadSelectedIndex]
            if recipe then
                print("[NCS-Building-List] 设置 recipe: " .. tostring(recipe:getTranslationName()))
                self.BuildingPanel.logic:setRecipe(recipe)
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end
        return false
    end

    -- 执行建造（和双击效果相同）
    function NB_RecipeList_Panel:executeBuild()
        print("[NCS-Building-List] executeBuild joypadSelectedIndex=" .. tostring(self.joypadSelectedIndex))

        if not self.filteredRecipes then
            print("[NCS-Building-List] filteredRecipes 为空")
            return false
        end

        local recipe = self.filteredRecipes[self.joypadSelectedIndex]
        if not recipe then
            print("[NCS-Building-List] 未找到配方")
            return false
        end

        print("[NCS-Building-List] 执行建造: " .. tostring(recipe:getTranslationName()))

        -- 获取 BuildingPanel
        local buildingPanel = self.BuildingPanel
        if not buildingPanel then
            print("[NCS-Building-List] BuildingPanel 为空")
            return false
        end

        -- 设置配方
        if buildingPanel.logic:getRecipe() ~= recipe then
            buildingPanel.logic:setRecipe(recipe)
        end

        -- 开始建造（和双击效果相同）
        buildingPanel:startBuild()

        getSoundManager():playUISound("UIActivateButton")
        return true
    end

    -- 更新手柄选中可视化并滚动到选中项
    function NB_RecipeList_Panel:updateJoypadSelection()
        if not self.currentScrollView then return end

        local scrollView = self.currentScrollView

        if scrollView.scrollToIndex then
            scrollView:scrollToIndex(self.joypadSelectedIndex)
        end

        scrollView:refreshItems()
    end
end

return NeatBuildingPatch
