-- NeatControllerSupport: Neat_Crafting 补丁
-- 处理 Neat_Crafting 组件的手柄导航

local NeatCraftingPatch = {}

-- 手柄按钮配置
NeatCraftingPatch.closeButton = Joypad.BButton
NeatCraftingPatch.L1Button = Joypad.LBumper or Joypad.L1Button
NeatCraftingPatch.R1Button = Joypad.RBumper or Joypad.R1Button
NeatCraftingPatch.AButton = Joypad.AButton
NeatCraftingPatch.YButton = Joypad.YButton

-- 导入组件补丁
local NC_RecipeList_Panel_Patch = require "NeatControllerSupport/NC_RecipeList_Panel_patch"

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
                panel.logic:setSelectedRecipeStyle(newStyle)
                panel:createChildren()
                panel:updateJoypadSelection()
                print("[NCS-Crafting] 切换视图: " .. currentStyle .. " -> " .. newStyle)
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
            -- 添加手柄选中状态字段并渲染
            local scrollView = self.currentScrollView
            if scrollView then
                -- 保存面板引用用于回调
                local panel = self
                local originalOnUpdateItem = scrollView.onUpdateItem
                scrollView:setOnUpdateItem(function(itemObject, recipe)
                    -- 调用原始更新
                    if originalOnUpdateItem then
                        originalOnUpdateItem(itemObject, recipe)
                    end
                    -- 通过直接字段设置手柄选中状态
                    local itemIndex = itemObject.indexInData
                    itemObject.joypadSelected = (itemIndex == panel.joypadSelectedIndex)
                end)

                -- 添加 prerender 来渲染选中高亮
                local originalPrerender = scrollView.prerender
                scrollView.prerender = function(self)
                    if originalPrerender then originalPrerender(self) end
                    -- 为可见项绘制选中高亮
                    if self.itemPool then
                        for _, item in ipairs(self.itemPool) do
                            if item and item.joypadSelected then
                                -- 绘制选中矩形边框
                                item:drawBorder(0.3, 0.3, 0.8, 1) -- 蓝色高亮
                            end
                        end
                    end
                end
            end
        end
    end

    -- 重写 createGridScrollView 添加手柄选中支持
    if originalCreateGridScrollView then
        function NC_RecipeList_Panel:createGridScrollView()
            originalCreateGridScrollView(self)
            -- 添加手柄选中状态字段
            local scrollView = self.currentScrollView
            if scrollView then
                -- 保存面板引用用于回调
                local panel = self
                local originalOnUpdateItem = scrollView.onUpdateItem
                scrollView:setOnUpdateItem(function(itemObject, recipe)
                    -- 调用原始更新
                    if originalOnUpdateItem then
                        originalOnUpdateItem(itemObject, recipe)
                    end
                    -- 通过直接字段设置手柄选中状态
                    local itemIndex = itemObject.indexInData
                    itemObject.joypadSelected = (itemIndex == panel.joypadSelectedIndex)
                end)
            end
        end
    end

    function NC_RecipeList_Panel:onJoypadDown(button)
        if originalOnJoypadDown then
            local result = originalOnJoypadDown(self, button)
            if result then return true end
        end

        if button == Joypad.AButton then
            self:selectRecipeWithJoypad()
            return true
        elseif button == Joypad.BButton then
            if self.HandCraftPanel and self.HandCraftPanel.close then
                self.HandCraftPanel:close()
            end
            return true
        end
        return false
    end

    function NC_RecipeList_Panel:onJoypadDirDown(dir)
        if originalOnJoypadDirDown then
            local result = originalOnJoypadDirDown(self, dir)
            if result then return result end
        end

        local direction = getJoypadDirection(dir)
        print("[NCS-RecipeList] 方向: " .. tostring(direction))
        if not direction then return false end

        if not self.logic or not self.filteredRecipes then return false end

        local style = self.logic:getSelectedRecipeStyle() or "list"
        local dataCount = #self.filteredRecipes
        if dataCount == 0 then return false end

        if style == "grid" then
            return self:handleGridNavigation(direction, dataCount)
        else
            return self:handleListNavigation(direction, dataCount)
        end
    end

    -- 列表视图导航处理
    function NC_RecipeList_Panel:handleListNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex

        if dir == "DOWN" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
        elseif dir == "UP" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
        end

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-RecipeList] 索引改变: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- 网格视图导航处理
    function NC_RecipeList_Panel:handleGridNavigation(dir, dataCount)
        local prevIndex = self.joypadSelectedIndex
        local cols = self.gridColumnCount or 4

        if dir == "DOWN" then
            self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + cols, dataCount)
        elseif dir == "UP" then
            self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - cols, 1)
        elseif dir == "RIGHT" then
            if self.joypadSelectedIndex % cols ~= 0 then
                self.joypadSelectedIndex = math.min(self.joypadSelectedIndex + 1, dataCount)
            end
        elseif dir == "LEFT" then
            if self.joypadSelectedIndex > 1 then
                self.joypadSelectedIndex = math.max(self.joypadSelectedIndex - 1, 1)
            end
        end

        if prevIndex ~= self.joypadSelectedIndex then
            print("[NCS-RecipeList] 网格索引改变: " .. prevIndex .. " -> " .. self.joypadSelectedIndex)
            self:updateJoypadSelection()
            return true
        end
        return false
    end

    -- 更新手柄选中可视化并滚动到选中项
    function NC_RecipeList_Panel:updateJoypadSelection()
        if not self.currentScrollView then return end

        local scrollView = self.currentScrollView
        local selectedIdx = self.joypadSelectedIndex

        -- 更新所有可见项的选中状态并强制重绘
        if scrollView.itemPool then
            for _, item in ipairs(scrollView.itemPool) do
                if item then
                    local isSelected = (item.indexInData == selectedIdx)
                    item.joypadSelected = isSelected
                    -- 强制重绘该项
                    if item.setDirty then
                        item:setDirty(true)
                    end
                end
            end
        end

        -- 强制整个 scrollView 刷新
        if scrollView.setDirty then
            scrollView:setDirty(true)
        end

        -- 刷新列表
        scrollView:refreshItems()

        -- 滚动到选中索引
        if scrollView.scrollToIndex then
            scrollView:scrollToIndex(selectedIdx)
        end

        -- 同时更新 logic 中选中的食谱
        if self.filteredRecipes and selectedIdx then
            local selectedRecipe = self.filteredRecipes[selectedIdx]
            if selectedRecipe and self.logic and self.logic.setSelectedRecipe then
                self.logic:setSelectedRecipe(selectedRecipe)
            end
        end
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
