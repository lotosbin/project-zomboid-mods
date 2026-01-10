-- NeatControllerSupport: Neat_Crafting 补丁
-- 处理 Neat_Crafting 组件的手柄导航

local NeatCraftingPatch = {}
local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 手柄按钮配置
NeatCraftingPatch.closeButton = Joypad.BButton
NeatCraftingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatCraftingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatCraftingPatch.AButton = Joypad.AButton
NeatCraftingPatch.YButton = Joypad.YButton
NeatCraftingPatch.XButton = Joypad.XButton

-- 导入组件补丁
local NC_RecipeList_Panel_Patch = require "NeatControllerSupport/NC_RecipeList_Panel_patch"

-- 右摇杆上次检测时间（用于防抖）
local lastRStickTime = 0
local R_STICK_COOLDOWN = 100 -- 毫秒

-- 从 JoypadData 对象提取方向
local function getJoypadDirection(dirData)
    return JoypadUtil.getJoypadDirection(dirData)
end

-- 从窗口获取 recipeListPanel
local function getRecipeListPanel(window)
    if not window then return nil end
    if window.HandCraftPanel and window.HandCraftPanel.recipeListPanel then
        return window.HandCraftPanel.recipeListPanel
    end
    return nil
end

-- 从窗口获取 categoryListPanel
local function getCategoryListPanel(window)
    if not window then
        print("[NCS-Crafting] getCategoryListPanel: window 为空")
        return nil
    end
    if window.HandCraftPanel and window.HandCraftPanel.categoryPanel then
        return window.HandCraftPanel.categoryPanel
    end
    return nil
end

-- 获取分类列表面板中的所有分类
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

    -- 查找当前分类索引
    local currentIndex = 1
    local currentCat = panel.selectedCategory
    if currentCat == "*" then
        currentIndex = 2
    else
        for i, cat in ipairs(allCategories) do
            if cat == currentCat then
                currentIndex = i
                break
            end
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
    print("[NCS-Crafting] 切换分类: " .. tostring(currentCat) .. " -> " .. tostring(newCategory))

    panel:onCategoryChanged(newCategory)
    return true
end

-- 处理右摇杆控制合成数量
local function handleRStickForCraftQuantity(playerNum)
    if not JoypadState or not JoypadState.players or not JoypadState.players[playerNum + 1] then
        return false
    end

    local currentTime = getCalendarTime()
    if currentTime - lastRStickTime < R_STICK_COOLDOWN then
        return false
    end

    local joyState = JoypadState.players[playerNum + 1]
    if not joyState then return false end

    -- 获取右摇杆值 (axis 2 = 水平, axis 3 = 垂直)
    local rStickX = joyState.rstickx or 0
    local rStickY = joyState.rsticky or 0

    -- 阈值
    local threshold = 0.5

    if math.abs(rStickX) < threshold and math.abs(rStickY) < threshold then
        return false
    end

    -- 查找 craftActionPanel
    local craftPanel = nil
    if NC_HandcraftWindow and NC_HandcraftWindow.instance then
        local win = NC_HandcraftWindow.instance
        if win.HandCraftPanel and win.HandCraftPanel.craftActionPanel then
            craftPanel = win.HandCraftPanel.craftActionPanel
        end
    end

    if not craftPanel then return false end

    -- 检查是否正在制作中
    if craftPanel.logic and craftPanel.logic:isCraftActionInProgress() then
        return false
    end

    -- 检查是否允许批量制作
    if not craftPanel.allowBatchCraft then
        return false
    end

    -- 获取当前数量和最大数量
    local currentValue = tonumber(craftPanel.quantityInput:getText()) or 1
    local maxCount = craftPanel.logic:getPossibleCraftCount(true)
    maxCount = math.max(1, maxCount)

    local changed = false

    -- 右摇杆水平：左减右加
    if math.abs(rStickX) >= threshold then
        if rStickX < 0 then
            -- 左
            local newValue = math.max(1, currentValue - 1)
            if newValue ~= currentValue then
                craftPanel.quantityInput:setText(tostring(newValue))
                craftPanel.currentCraftQuantity = newValue
                print("[NCS-Crafting] 右摇杆左: " .. currentValue .. " -> " .. newValue)
                changed = true
            end
        else
            -- 右
            local newValue = math.min(maxCount, currentValue + 1)
            if newValue ~= currentValue then
                craftPanel.quantityInput:setText(tostring(newValue))
                craftPanel.currentCraftQuantity = newValue
                print("[NCS-Crafting] 右摇杆右: " .. currentValue .. " -> " .. newValue)
                changed = true
            end
        end
    end

    -- 右摇杆垂直：上 max，下 min
    if math.abs(rStickY) >= threshold then
        if rStickY < 0 then
            -- 上
            if currentValue ~= maxCount then
                craftPanel.quantityInput:setText(tostring(maxCount))
                craftPanel.currentCraftQuantity = maxCount
                print("[NCS-Crafting] 右摇杆上: " .. currentValue .. " -> " .. maxCount)
                changed = true
            end
        else
            -- 下
            if currentValue ~= 1 then
                craftPanel.quantityInput:setText("1")
                craftPanel.currentCraftQuantity = 1
                print("[NCS-Crafting] 右摇杆下: " .. currentValue .. " -> 1")
                changed = true
            end
        end
    end

    if changed then
        lastRStickTime = currentTime
        getSoundManager():playUISound("UIActivateButton")
        return true
    end

    return false
end

-- 注册到全局更新
local function registerRStickHandler()
    if Events == nil then return end
    Events.OnPlayerMove.Add(function() end) -- 占位，确保 Events 存在
end

-- 为窗口添加手柄支持
function NeatCraftingPatch:addJoypad(windowClass)
    if not windowClass then return end

    local _patch = NeatCraftingPatch
    local originalOnJoypadDown = windowClass.onJoypadDown
    local originalOnJoypadDirDown = windowClass.onJoypadDirDown

    function windowClass:onJoypadDown(button)
        print("[NCS-Crafting] === onJoypadDown ===")
        print("[NCS-Crafting] 按钮: " .. tostring(button))

        -- L1 键：上一个分类
        if button == _patch.L1Button then
            print("[NCS-Crafting] L1 按下 - 上一个分类")
            local catPanel = getCategoryListPanel(self)
            if catPanel then
                print("[NCS-Crafting] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "prev")
                print("[NCS-Crafting] cycleCategory 结果: " .. tostring(result))
                return true
            end
        end

        -- R1 键：下一个分类
        if button == _patch.R1Button then
            print("[NCS-Crafting] R1 按下 - 下一个分类")
            local catPanel = getCategoryListPanel(self)
            if catPanel then
                print("[NCS-Crafting] catPanel: " .. tostring(catPanel))
                local result = cycleCategory(catPanel, "next")
                print("[NCS-Crafting] cycleCategory 结果: " .. tostring(result))
                return true
            end
        end

        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == _patch.closeButton then
            self.close(self)
            return true
        end

        -- A 键：转发到 recipeListPanel
        if button == _patch.AButton then
            local panel = getRecipeListPanel(self)
            if panel and panel.onJoypadDown then
                panel:onJoypadDown(button)
                return true
            end
        end

        -- Y 键：切换列表/网格视图
        if button == _patch.YButton then
            local panel = getRecipeListPanel(self)
            if panel and panel.logic then
                local currentStyle = panel.logic:getSelectedRecipeStyle() or "list"
                local newStyle = (currentStyle == "list") and "grid" or "list"

                print("[NCS-Crafting] 切换视图: " .. currentStyle .. " -> " .. newStyle)

                -- 设置新的视图样式
                panel.logic:setSelectedRecipeStyle(newStyle)

                -- 重置选中状态
                panel.joypadSelectedIndex = 1

                -- 全面刷新 UI
                panel:createChildren()

                -- 刷新滚动视图
                if panel.currentScrollView then
                    panel.currentScrollView:refreshItems()
                end

                -- 播放声音
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        return false
    end

    function windowClass:onJoypadDirDown(dir)
        print("[NCS-Crafting] onJoypadDirDown: " .. tostring(dir))
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            print("[NCS-Crafting] originalOnJoypadDirDown 结果: " .. tostring(result))
            if result then return result end
        end
        -- 转发到 recipeListPanel
        local panel = getRecipeListPanel(self)
        print("[NCS-Crafting] recipeListPanel: " .. tostring(panel))
        print("[NCS-Crafting] panel.onJoypadDirDown: " .. tostring(panel and panel.onJoypadDirDown))
        if panel and panel.onJoypadDirDown then
            local forwardResult = panel:onJoypadDirDown(dir)
            print("[NCS-Crafting] 转发结果: " .. tostring(forwardResult))
            return forwardResult
        end
        return false
    end
end

-- 应用食谱列表面板补丁
function NeatCraftingPatch:addRecipeListJoypad()
    local panel = NC_RecipeList_Panel
    if not panel then return end

    if not panel.joypadSelectedIndex then
        panel.joypadSelectedIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown
    local originalCreateListScrollView = panel.createListScrollView
    local originalCreateGridScrollView = panel.createGridScrollView

    -- 重写 createListScrollView 添加手柄选中支持
    if originalCreateListScrollView then
        function NC_RecipeList_Panel:createListScrollView()
            originalCreateListScrollView(self)
        end
    end

    -- 重写 createGridScrollView 添加手柄选中支持
    if originalCreateGridScrollView then
        function NC_RecipeList_Panel:createGridScrollView()
            originalCreateGridScrollView(self)
        end
    end

    function NC_RecipeList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == Joypad.AButton then
            -- A 键：执行合成（调用 craftActionPanel 的 onCraftButtonClick）
            if self.HandCraftPanel and self.HandCraftPanel.craftActionPanel then
                local craftPanel = self.HandCraftPanel.craftActionPanel
                if craftPanel.onCraftButtonClick then
                    craftPanel:onCraftButtonClick()
                    getSoundManager():playUISound("UIActivateButton")
                end
            end
            return true
        elseif button == Joypad.BButton then
            if self.HandCraftPanel and self.HandCraftPanel.close then
                self.HandCraftPanel:close()
            end
            return true
        elseif button == Joypad.XButton then
            -- X 键：切换只显示可制作
            if self.HandCraftPanel and self.HandCraftPanel.filterBar then
                local filterBar = self.HandCraftPanel.filterBar
                filterBar.showOnlyCanMake = not filterBar.showOnlyCanMake
                print("[NCS-Crafting] showOnlyCanMake=" .. tostring(filterBar.showOnlyCanMake))

                -- 触发过滤器变更事件
                self.HandCraftPanel:onFilterChanged()

                -- 重置选中状态
                self.joypadSelectedIndex = 1

                -- 全面刷新 UI
                self:createChildren()

                -- 刷新滚动视图
                if self.currentScrollView then
                    self.currentScrollView:refreshItems()
                end

                -- 滚动到顶部
                if self.currentScrollView and self.currentScrollView.setYScroll then
                    self.currentScrollView:setYScroll(0)
                end

                -- 播放声音
                getSoundManager():playUISound("UIActivateButton")
            end
            return true
        end
        return false
    end

    -- 右摇杆控制合成数量
    function NC_RecipeList_Panel:onJoypadAxisMoved(axis, value)
        -- axis 0 = 左摇杆水平, 1 = 左摇杆垂直, 2 = 右摇杆水平, 3 = 右摇杆垂直
        if axis ~= 2 and axis ~= 3 then return false end

        print("[NCS-Crafting] onJoypadAxisMoved axis=" .. tostring(axis) .. " value=" .. tostring(value))

        if not self.HandCraftPanel or not self.HandCraftPanel.craftActionPanel then
            return false
        end

        local craftPanel = self.HandCraftPanel.craftActionPanel

        -- 检查是否正在制作中
        if craftPanel.logic and craftPanel.logic:isCraftActionInProgress() then
            return false
        end

        -- 检查是否允许批量制作
        if not craftPanel.allowBatchCraft then
            return false
        end

        -- 获取当前数量和最大数量
        local currentValue = tonumber(craftPanel.quantityInput:getText()) or 1
        local maxCount = craftPanel.logic:getPossibleCraftCount(true)
        maxCount = math.max(1, maxCount)

        -- 阈值，避免微小移动触发
        local threshold = 0.5

        if axis == 2 then
            -- 右摇杆水平：左减右加
            if value < -threshold then
                -- 左
                local newValue = math.max(1, currentValue - 1)
                if newValue ~= currentValue then
                    craftPanel.quantityInput:setText(tostring(newValue))
                    craftPanel.currentCraftQuantity = newValue
                    print("[NCS-Crafting] 右摇杆左: " .. currentValue .. " -> " .. newValue)
                    getSoundManager():playUISound("UIActivateButton")
                end
                return true
            elseif value > threshold then
                -- 右
                local newValue = math.min(maxCount, currentValue + 1)
                if newValue ~= currentValue then
                    craftPanel.quantityInput:setText(tostring(newValue))
                    craftPanel.currentCraftQuantity = newValue
                    print("[NCS-Crafting] 右摇杆右: " .. currentValue .. " -> " .. newValue)
                    getSoundManager():playUISound("UIActivateButton")
                end
                return true
            end
        elseif axis == 3 then
            -- 右摇杆垂直：上 max，下 min
            if value < -threshold then
                -- 上（注意：在许多控制器中，摇杆向上是负值）
                if currentValue ~= maxCount then
                    craftPanel.quantityInput:setText(tostring(maxCount))
                    craftPanel.currentCraftQuantity = maxCount
                    print("[NCS-Crafting] 右摇杆上: " .. currentValue .. " -> " .. maxCount)
                    getSoundManager():playUISound("UIActivateButton")
                end
                return true
            elseif value > threshold then
                -- 下
                if currentValue ~= 1 then
                    craftPanel.quantityInput:setText("1")
                    craftPanel.currentCraftQuantity = 1
                    print("[NCS-Crafting] 右摇杆下: " .. currentValue .. " -> 1")
                    getSoundManager():playUISound("UIActivateButton")
                end
                return true
            end
        end

        return false
    end

    function NC_RecipeList_Panel:onJoypadDirDown(dir)
        print("[NCS-RecipeList] onJoypadDirDown dir=" .. tostring(dir))

        -- 使用调试函数打印详细信息
        if self.currentScrollView and self.currentScrollView.debug then
            debugScrollView(self.currentScrollView, "onJoypadDirDown")
        end

        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then
                print("[NCS-RecipeList] originalOnJoypadDirDown 处理了方向")
                return result
            end
        end

        -- 从 JoypadData 对象提取方向
        local direction = getJoypadDirection(dir)

        print("[NCS-RecipeList] 方向=" .. tostring(direction))

        if not direction then
            print("[NCS-RecipeList] 未检测到有效方向")
            return false
        end

        if not self.logic then
            print("[NCS-RecipeList] logic 为空")
            return false
        end

        if not self.filteredRecipes then
            print("[NCS-RecipeList] filteredRecipes 为空，尝试获取")
            self.filteredRecipes = self.logic:getFilteredRecipes() or {}
        end

        local dataCount = #self.filteredRecipes
        print("[NCS-RecipeList] filteredRecipes count=" .. tostring(dataCount))
        print("[NCS-RecipeList] joypadSelectedIndex=" .. tostring(self.joypadSelectedIndex))

        if dataCount == 0 then
            print("[NCS-RecipeList] 数据为空")
            return false
        end

        -- 确保索引在有效范围内
        if not self.joypadSelectedIndex or self.joypadSelectedIndex < 1 then
            self.joypadSelectedIndex = 1
        elseif self.joypadSelectedIndex > dataCount then
            self.joypadSelectedIndex = dataCount
        end

        local style = self.logic:getSelectedRecipeStyle() or "list"
        print("[NCS-RecipeList] style=" .. tostring(style) .. " dataCount=" .. tostring(dataCount))

        if style == "grid" then
            return self:handleGridNavigation(direction, dataCount)
        else
            return self:handleListNavigation(direction, dataCount)
        end
    end

    -- 列表视图导航处理
    function NC_RecipeList_Panel:handleListNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        print("[NCS-ListNav] prevIndex=" .. tostring(prevIndex) .. " dir=" .. tostring(dir) .. " dataCount=" .. tostring(dataCount))

        if dir == "down" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
        elseif dir == "up" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
        end

        print("[NCS-ListNav] newIndex=" .. tostring(self.joypadSelectedIndex))

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-ListNav] 索引改变: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            -- 通过点击选中项来处理（调用原始模组的 onMouseDown）
            self:selectCurrentItem()
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- 网格视图导航处理
    function NC_RecipeList_Panel:handleGridNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        -- 从 scrollView 获取 gridColumnCount
        local cols = self.gridColumnCount or 4
        if self.currentScrollView and self.currentScrollView.cols then
            cols = self.currentScrollView.cols
        end

        print("[NCS-GridNav] prevIndex=" .. tostring(prevIndex) .. " dir=" .. tostring(dir) .. " cols=" .. tostring(cols) .. " dataCount=" .. tostring(dataCount))

        if dir == "down" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
        elseif dir == "up" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
        elseif dir == "right" then
            local currentCol = self.joypadSelectedIndex % cols
            if currentCol == 0 then currentCol = cols end
            print("[NCS-GridNav] RIGHT currentCol=" .. tostring(currentCol))
            if currentCol < cols then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            end
        elseif dir == "left" then
            local currentCol = self.joypadSelectedIndex % cols
            if currentCol == 0 then currentCol = cols end
            print("[NCS-GridNav] LEFT currentCol=" .. tostring(currentCol))
            if currentCol > 1 then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
            end
        end

        print("[NCS-GridNav] newIndex=" .. tostring(self.joypadSelectedIndex))

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-GridNav] 索引改变: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            -- 通过点击选中项来处理（调用原始模组的 onMouseDown）
            self:selectCurrentItem()
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- 通过点击当前选中项来处理选择
    function NC_RecipeList_Panel:selectCurrentItem()
        print("[NCS-RecipeList] selectCurrentItem joypadSelectedIndex=" .. tostring(self.joypadSelectedIndex))

        -- 方法1: 直接从 filteredRecipes 获取配方并设置（最可靠的方式）
        if self.filteredRecipes and self.HandCraftPanel and self.HandCraftPanel.logic then
            local recipe = self.filteredRecipes[self.joypadSelectedIndex]
            if recipe then
                print("[NCS-RecipeList] 直接设置 recipe: " .. tostring(recipe:getTranslationName()))
                self.HandCraftPanel.logic:setRecipe(recipe)
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end

        -- 方法2: 在 itemPool 中找到当前选中索引的 item 并调用 onMouseDown
        if self.currentScrollView and self.currentScrollView.itemPool then
            for _, item in ipairs(self.currentScrollView.itemPool) do
                if item and item.indexInData == self.joypadSelectedIndex then
                    print("[NCS-RecipeList] 从 itemPool 找到选中项，调用 onMouseDown")
                    if item.onMouseDown then
                        item:onMouseDown()
                        return true
                    end
                end
            end
        end

        print("[NCS-RecipeList] selectCurrentItem 失败")
        return false
    end

    -- 更新手柄选中可视化并滚动到选中项
    function NC_RecipeList_Panel:updateJoypadSelection()
        if not self.currentScrollView then return end

        local scrollView = self.currentScrollView

        -- 滚动到选中索引
        if scrollView.scrollToIndex then
            scrollView:scrollToIndex(self.joypadSelectedIndex)
        end

        -- 刷新列表以更新高亮显示
        scrollView:refreshItems()
    end
end

-- 应用分类列表面板补丁
function NeatCraftingPatch:addCategoryListJoypad()
    local panel = NC_CategoryList_Panel
    if not panel then return end

    if not panel.joypadCategoryIndex then
        panel.joypadCategoryIndex = 1
    end

    local originalOnJoypadDown = panel.onJoypadDown
    local originalOnJoypadDirDown = panel.onJoypadDirDown

    function NC_CategoryList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            return originalOnJoypadDown(self, button)
        end
        return false
    end

    function NC_CategoryList_Panel:onJoypadDirDown(dir)
        -- 转发到 recipeListPanel
        if self.HandCraftPanel and self.HandCraftPanel.recipeListPanel then
            local recipePanel = self.HandCraftPanel.recipeListPanel
            if recipePanel and recipePanel.onJoypadDirDown then
                return recipePanel:onJoypadDirDown(dir)
            end
        end
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end
        return false
    end
end

-- 注册所有 Neat_Crafting 补丁
function NeatCraftingPatch:registerAll()
    if NC_HandcraftWindow then
        self:addJoypad(NC_HandcraftWindow)
    end
    self:addRecipeListJoypad()
    self:addCategoryListJoypad()
end

return NeatCraftingPatch
