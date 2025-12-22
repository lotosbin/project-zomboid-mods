require "ISUI/ISInventoryPage"

local NeatControllerSupport = {}
NeatControllerSupport.MOD_ID = "Neat_Controller_Support"
NeatControllerSupport.MOD_Name = "Neat Controller Support"

-- 调试日志函数
local function debugLog(message)
    if getDebug() then
        print("[NeatControllerSupport] " .. message)
    end
end

-- 统一的手柄处理函数
local function addUniversalJoypadSupport(windowClass)
    if not windowClass then 
        debugLog("窗口类为空，无法添加手柄支持")
        return 
    end
    
    debugLog("正在为窗口类添加统一手柄支持: " .. tostring(windowClass))
    
    -- 添加统一的手柄按钮处理
    local original_onJoypadDown = windowClass.onJoypadDown
    function windowClass:onJoypadDown(button)
        debugLog("手柄按钮按下: " .. tostring(button) .. " 窗口类型: " .. tostring(self:getClassName()))
        
        -- 调用原始处理
        if original_onJoypadDown then
            local result = original_onJoypadDown(self, button)
            if result then 
                debugLog("原始手柄处理已处理按钮: " .. tostring(button))
                return result 
            end
        end
        
        -- 统一的B按钮处理（关闭窗口）
        if button == JoypadState.B then
            debugLog("B按钮按下，准备关闭窗口")
            if self.close then
                self:close()
                debugLog("窗口已关闭")
                return true
            end
        end
        
        -- 统一的Y按钮处理（搜索焦点）
        if button == JoypadState.Y and self.header and self.header.searchComponent then
            debugLog("Y按钮按下，设置焦点到搜索框")
            setJoypadFocus(self.playerNum, self.header.searchComponent)
            return true
        end
        
        debugLog("未处理的手柄按钮: " .. tostring(button))
        return false
    end
    
    -- 统一的键盘处理
    local original_onKeyRelease = windowClass.onKeyRelease
    function windowClass:onKeyRelease(key)
        if original_onKeyRelease then
            local result = original_onKeyRelease(self, key)
            if result then return result end
        end
        
        if key == Keyboard.KEY_ESCAPE or getCore():isKey("Crafting UI", key) then
            if self.close then
                self:close()
                return true
            end
        end
        return false
    end
    
    -- 统一的按键消费判断
    local original_isKeyConsumed = windowClass.isKeyConsumed
    function windowClass:isKeyConsumed(key)
        if original_isKeyConsumed then
            local result = original_isKeyConsumed(self, key)
            if result then return result end
        end
        
        return key == Keyboard.KEY_ESCAPE or getCore():isKey("Crafting UI", key)
    end
end

-- 自动为窗口添加手柄支持的函数
local function autoAddJoypadSupport(window)
    if not window then 
        debugLog("窗口为空，无法添加手柄支持")
        return 
    end
    
    debugLog("开始为窗口添加自动手柄支持: " .. tostring(window:getClassName()) .. " 玩家: " .. tostring(window.playerNum))
    
    -- 自动设置手柄焦点
    if JoypadState.players[window.playerNum+1] then
        debugLog("检测到手柄连接，开始设置焦点")
        -- 优先设置焦点到搜索框
        if window.header and window.header.searchComponent then
            debugLog("设置焦点到搜索框")
            setJoypadFocus(window.playerNum, window.header.searchComponent)
        else
            debugLog("设置焦点到窗口")
            setJoypadFocus(window.playerNum, window)
        end
    else
        debugLog("未检测到手柄连接")
    end
    
    -- 触发窗口创建完成事件
    debugLog("触发窗口创建完成事件")
    triggerEvent("OnNC_WindowCreated", window)
end

Events.OnGameBoot.Add(function()
    debugLog("游戏启动，开始初始化手柄支持")
    
    -- 为所有相关窗口类添加统一的手柄支持
    if NC_EntityWindow then
        addUniversalJoypadSupport(NC_EntityWindow)
        debugLog("已为NC_EntityWindow添加手柄支持")
    else
        debugLog("NC_EntityWindow未找到")
    end
    
    if NC_HandcraftWindow then
        addUniversalJoypadSupport(NC_HandcraftWindow)
        debugLog("已为NC_HandcraftWindow添加手柄支持")
    else
        debugLog("NC_HandcraftWindow未找到")
    end
    
    -- 修补窗口创建函数，自动添加手柄支持
    local original_createWindow = createWindow
    createWindow = function(_player, _windowInstance, _isoObject)
        debugLog("创建窗口: " .. tostring(_windowInstance:getClassName()) .. " 玩家: " .. tostring(_player:getPlayerNum()))
        
        -- 调用原始函数
        original_createWindow(_player, _windowInstance, _isoObject)
        
        -- 自动添加手柄支持
        autoAddJoypadSupport(_windowInstance)
    end
    
    -- 修补手工艺窗口打开函数
    local original_OpenHandcraftWindow = ISEntityUI.OpenHandcraftWindow
    function ISEntityUI.OpenHandcraftWindow(_player, _isoObject, _queryOverride, _ignoreFindSurface, recipeData, itemString)
        debugLog("打开手工艺窗口，玩家: " .. tostring(_player:getPlayerNum()))
        
        -- 调用原始函数
        original_OpenHandcraftWindow(_player, _isoObject, _queryOverride, _ignoreFindSurface, recipeData, itemString)
        
        -- 延迟添加手柄支持，确保窗口完全初始化
        Events.OnTick.Add(function()
            local playerNum = _player:getPlayerNum()
            if ISEntityUI.players[playerNum] and ISEntityUI.players[playerNum].windows and ISEntityUI.players[playerNum].windows.HandcraftWindow then
                local windowInstance = ISEntityUI.players[playerNum].windows.HandcraftWindow.instance
                if windowInstance and windowInstance:isVisible() then
                    debugLog("手工艺窗口已可见，添加手柄支持")
                    autoAddJoypadSupport(windowInstance)
                    return true -- 移除此事件监听器
                end
            end
            return false
        end)
    end
end)
