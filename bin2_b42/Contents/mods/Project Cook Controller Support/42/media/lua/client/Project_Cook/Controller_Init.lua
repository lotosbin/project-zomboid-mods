-- ------------------------------------------------------ --
-- Project Cook Controller Support
-- 手柄控制器支持 - 初始化脚本
-- ------------------------------------------------------ --

local PJCK_Instance = nil

-- 按钮常量
local AButton = Joypad.AButton
local BButton = Joypad.BButton
local XButton = Joypad.XButton

-- ------------------------------------------------------ --
-- PJCK_Window 扩展
-- ------------------------------------------------------ --

-- 保存原始 onOpen
local original_PJCK_Window_onOpen = PJCK_Window.onOpen

function PJCK_Window:onOpen(player)
    PJCK_Instance = self

    -- 调用原始 onOpen
    if original_PJCK_Window_onOpen then
        original_PJCK_Window_onOpen(self, player)
    end

    -- 设置手柄焦点
    if player then
        local playerNum = 0
        if player.getPlayerNum then
            playerNum = player:getPlayerNum()
        end
        setJoypadFocus(playerNum, self)
    end

    -- 初始化 EvoPanel 状态
    if self.EvoPanel then
        if not self.EvoPanel.pjck_controllerIndex then self.EvoPanel.pjck_controllerIndex = 1 end
        if not self.EvoPanel.pjck_controllerColumn then self.EvoPanel.pjck_controllerColumn = 1 end
    end
end

-- ------------------------------------------------------ --
-- PJCK_Window 手柄按键处理
-- ------------------------------------------------------ --

local original_PJCK_Window_onJoypadDown = PJCK_Window.onJoypadDown

function PJCK_Window:onJoypadDown(button, playerNum)
    -- 调用原始处理
    if original_PJCK_Window_onJoypadDown then
        local result = original_PJCK_Window_onJoypadDown(self, button, playerNum)
        if result == true then return true end
    end

    if not self.EvoPanel then return false end

    local panel = self.EvoPanel
    if not panel.pjck_controllerIndex then panel.pjck_controllerIndex = 1 end
    if not panel.pjck_controllerColumn then panel.pjck_controllerColumn = 1 end

    -- B 键关闭
    if button == BButton then
        self:onCloseClick()
        return true
    end

    -- A 键选择
    if button == AButton then
        panel:pjck_selectCurrent()
        return true
    end

    -- X 键切换筛选
    if button == XButton then
        if panel.pjck_controllerColumn == 2 then
            panel:toggleShowPossible("Ingredient")
        elseif panel.pjck_controllerColumn == 3 then
            panel:toggleShowPossible("Seasoning")
        end
        if panel.onUpdateContainers then
            panel:onUpdateContainers()
        end
        return true
    end

    return false
end

function PJCK_Window:pjck_onJoypadDirUp()
    if self.EvoPanel then
        return self.EvoPanel:pjck_handleDirection("up")
    end
    return false
end

function PJCK_Window:pjck_onJoypadDirDown()
    if self.EvoPanel then
        return self.EvoPanel:pjck_handleDirection("down")
    end
    return false
end

function PJCK_Window:pjck_onJoypadDirLeft()
    if self.EvoPanel then
        return self.EvoPanel:pjck_handleDirection("left")
    end
    return false
end

function PJCK_Window:pjck_onJoypadDirRight()
    if self.EvoPanel then
        return self.EvoPanel:pjck_handleDirection("right")
    end
    return false
end

-- ------------------------------------------------------ --
-- PJCK_EvoPanel 扩展
-- ------------------------------------------------------ --

function PJCK_EvoPanel:pjck_renderFocus()
    local list = self:pjck_getCurrentList()
    if not list or not list.items or not self.pjck_controllerIndex or self.pjck_controllerIndex > #list.items or self.pjck_controllerIndex < 1 then
        return
    end

    local listX, listY = list:getScreenRect()
    local itemHeight = list.itemHeight or 30
    local listWidth = list.width or 200

    local x = listX
    local y = listY + (self.pjck_controllerIndex - 1) * itemHeight
    local width = listWidth
    local height = itemHeight

    -- 绘制焦点边框 (蓝色)
    self:drawRectBorder(x - 2, y - 2, width + 4, height + 4, 1, 0.3, 0.6, 1.0)
end

function PJCK_EvoPanel:pjck_getCurrentList()
    if self.pjck_controllerColumn == 1 then
        return self.baseItemPanel and self.baseItemPanel.itemList
    elseif self.pjck_controllerColumn == 2 then
        return self.ingredientsPanel and self.ingredientsPanel.itemList
    elseif self.pjck_controllerColumn == 3 then
        return self.seasoningsPanel and self.seasoningsPanel.itemList
    end
    return nil
end

function PJCK_EvoPanel:pjck_getMaxIndex()
    local list = self:pjck_getCurrentList()
    if list and list.items then
        return #list.items
    end
    return 1
end

function PJCK_EvoPanel:pjck_selectCurrent()
    local list = self:pjck_getCurrentList()
    if list and list.items and self.pjck_controllerIndex <= #list.items then
        local item = list.items[self.pjck_controllerIndex]
        if item and item.onClick then
            item:onClick()
        end
    end
end

function PJCK_EvoPanel:pjck_handleDirection(direction)
    if not self.pjck_controllerIndex then self.pjck_controllerIndex = 1 end
    if not self.pjck_controllerColumn then self.pjck_controllerColumn = 1 end

    local maxIdx = self:pjck_getMaxIndex()

    if direction == "up" then
        if self.pjck_controllerIndex > 1 then
            self.pjck_controllerIndex = self.pjck_controllerIndex - 1
            return true
        end
    elseif direction == "down" then
        if self.pjck_controllerIndex < maxIdx then
            self.pjck_controllerIndex = self.pjck_controllerIndex + 1
            return true
        end
    elseif direction == "left" then
        if self.pjck_controllerColumn > 1 then
            self.pjck_controllerColumn = self.pjck_controllerColumn - 1
            self.pjck_controllerIndex = 1
            return true
        end
    elseif direction == "right" then
        if self.pjck_controllerColumn < 3 then
            self.pjck_controllerColumn = self.pjck_controllerColumn + 1
            self.pjck_controllerIndex = 1
            return true
        end
    end
    return false
end

-- ------------------------------------------------------ --
-- Prerender 扩展 - 绘制焦点
-- ------------------------------------------------------ --

local original_PJCK_EvoPanel_prerender = PJCK_EvoPanel.prerender
function PJCK_EvoPanel:prerender(...)
    if original_PJCK_EvoPanel_prerender then
        original_PJCK_EvoPanel_prerender(self, ...)
    end
    self:pjck_renderFocus()
end

-- ------------------------------------------------------ --
-- 初始化
-- ------------------------------------------------------ --

Events.OnGameStart.Add(function()
    print("[Project Cook Controller Support] 已加载")
end)
