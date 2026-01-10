-- NeatControllerSupport: Neat_Building 补丁
-- 处理 Neat_Building 组件的手柄导航

local NeatBuildingPatch = {}

-- 手柄按钮配置
NeatBuildingPatch.closeButton = Joypad.BButton
NeatBuildingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatBuildingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatBuildingPatch.YButton = Joypad.YButton

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
                self.recipeListPanel.logic:setSelectedRecipeStyle(newStyle)
                self.recipeListPanel:createChildren()
                print("[NCS-Building] 切换视图: " .. currentStyle .. " -> " .. newStyle)
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

        -- 处理建造模式: 使用方向键移动
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

-- 注册所有 Neat_Building 补丁
function NeatBuildingPatch:registerAll()
    if NB_BuildingPanel then
        self:addJoypad(NB_BuildingPanel)
    end
end

return NeatBuildingPatch
