-- Project Zomboid 手柄支持开发模板
-- 基于最佳实践和安全机制的完整模板

-- ============================================
-- 配置部分
-- ============================================
local ControllerSupport = {
    MOD_ID = "your_controller_support",
    MOD_NAME = "Your Controller Support",
    VERSION = "1.0.0",

    -- 目标窗口配置
    targetWindows = {
        "YourWindow1",
        "YourWindow2"
    },

    -- 手柄按钮映射
    buttonMappings = {
        [JoypadState.A] = "confirm",
        [JoypadState.B] = "cancel",
        [JoypadState.X] = "action",
        [JoypadState.Y] = "search",
        [JoypadState.LB] = "page_left",
        [JoypadState.RB] = "page_right",
        [JoypadState.LT] = "category_prev",
        [JoypadState.RT] = "category_next",
        [JoypadState.Left] = "nav_left",
        [JoypadState.Right] = "nav_right",
        [JoypadState.Up] = "nav_up",
        [JoypadState.Down] = "nav_down"
    },

    -- 状态管理
    state = {
        isActive = false,
        currentPlayer = 0,
        focusedWindows = {},
        debugMode = false
    }
}

-- ============================================
-- 工具函数
-- ============================================
local function debugLog(message)
    if ControllerSupport.state.debugMode or getDebug() then
        print("[" .. ControllerSupport.MOD_ID .. "] " .. message)
    end
end

-- ============================================
-- 安全检查模块
-- ============================================
local Safety = {}

function Safety.isValidWindow(window)
    if not window then
        debugLog("窗口对象为 nil")
        return false
    end

    -- 检查窗口是否仍然有效
    if window.javaObject and window.javaObject:isDestroyed() then
        debugLog("窗口对象已被销毁")
        return false
    end

    -- 检查必要的方法
    local requiredMethods = {"getClassName"}
    for _, method in ipairs(requiredMethods) do
        if not window[method] or type(window[method]) ~= "function" then
            debugLog("窗口缺少必要方法: " .. method)
            return false
        end
    end

    if not window.playerNum then
        debugLog("窗口缺少 playerNum 属性")
        return false
    end

    return true
end

function Safety.safeCall(func, ...)
    if not func or type(func) ~= "function" then
        debugLog("无效的函数调用")
        return nil
    end

    local success, result = pcall(func, ...)
    if not success then
        debugLog("函数调用失败: " .. tostring(result))
        return nil
    end
    return result
end

function Safety.safeSetJoypadFocus(playerNum, target)
    if not target then
        debugLog("焦点目标为空")
        return false
    end

    if not JoypadState.players[playerNum+1] then
        debugLog("玩家 " .. playerNum .. " 没有连接手柄")
        return false
    end

    local success, err = pcall(setJoypadFocus, playerNum, target)
    if success then
        debugLog("成功设置焦点")
        return true
    else
        debugLog("设置焦点失败: " .. tostring(err))
        return false
    end
end

-- ============================================
-- 按钮处理模块
-- ============================================
local ButtonHandler = {}

function ButtonHandler.handleButton(window, button)
    if not Safety.isValidWindow(window) then
        return false
    end

    local action = ControllerSupport.buttonMappings[button]
    if not action then
        debugLog("未映射的按钮: " .. tostring(button))
        return false
    end

    debugLog("处理按钮动作: " .. action)
    return ButtonHandler.executeAction(window, action)
end

function ButtonHandler.executeAction(window, action)
    if action == "cancel" then
        return ButtonHandler.handleCancel(window)
    elseif action == "search" then
        return ButtonHandler.handleSearch(window)
    elseif action == "confirm" then
        return ButtonHandler.handleConfirm(window)
    elseif action:match("nav_") then
        return ButtonHandler.handleNavigation(window, action)
    end

    return false
end

function ButtonHandler.handleCancel(window)
    debugLog("处理取消操作")
    if window.close and type(window.close) == "function" then
        local success = Safety.safeCall(window.close, window)
        return success ~= nil
    end
    return false
end

function ButtonHandler.handleSearch(window)
    debugLog("处理搜索操作")
    if window.header and window.header.searchComponent then
        return Safety.safeSetJoypadFocus(window.playerNum, window.header.searchComponent)
    end
    return false
end

function ButtonHandler.handleConfirm(window)
    debugLog("处理确认操作")
    -- 这里实现确认逻辑，取决于具体的窗口类型
    return false
end

function ButtonHandler.handleNavigation(window, action)
    debugLog("处理导航: " .. action)
    -- 这里实现导航逻辑
    return false
end

-- ============================================
-- 窗口补丁模块
-- ============================================
local WindowPatcher = {}

function WindowPatcher.patchWindowClass(windowClass)
    if not windowClass then
        debugLog("窗口类为空，无法打补丁")
        return false
    end

    debugLog("为窗口类添加手柄支持: " .. tostring(windowClass))

    -- 保存原始手柄处理函数
    local original_onJoypadDown = windowClass.onJoypadDown

    -- 添加新的手柄处理函数
    function windowClass:onJoypadDown(button)
        -- 安全检查
        if not Safety.isValidWindow(self) then
            debugLog("手柄处理时窗口无效，忽略")
            return false
        end

        debugLog("手柄按钮按下: " .. tostring(button) .. " 窗口类型: " .. tostring(self:getClassName()))

        -- 尝试调用原始处理函数
        if original_onJoypadDown then
            local success, result = Safety.safeCall(original_onJoypadDown, self, button)
            if success and result then
                debugLog("原始手柄处理已处理按钮: " .. tostring(button))
                return result
            elseif not success then
                debugLog("原始手柄处理出错，使用我们的处理")
            end
        end

        -- 使用我们的按钮处理
        return ButtonHandler.handleButton(self, button)
    end

    -- 保存原始键盘处理函数
    local original_onKeyRelease = windowClass.onKeyRelease

    -- 添加新的键盘处理函数
    function windowClass:onKeyRelease(key)
        if not Safety.isValidWindow(self) then
            return false
        end

        if original_onKeyRelease then
            local success, result = Safety.safeCall(original_onKeyRelease, self, key)
            if success and result then
                return result
            elseif not success then
                debugLog("原始键盘处理出错: " .. tostring(result))
            end
        end

        -- ESC 键关闭窗口
        if key == Keyboard.KEY_ESCAPE or getCore():isKey("Crafting UI", key) then
            return ButtonHandler.handleCancel(self)
        end

        return false
    end

    return true
end

-- ============================================
-- 焦点管理模块
-- ============================================
local FocusManager = {}

function FocusManager.autoSetFocus(window)
    if not Safety.isValidWindow(window) then
        debugLog("窗口无效，无法设置焦点")
        return
    end

    debugLog("开始自动设置焦点: " .. tostring(window:getClassName()))

    -- 优先级焦点设置
    if window.header and window.header.searchComponent then
        debugLog("尝试设置焦点到搜索框")
        if not Safety.safeSetJoypadFocus(window.playerNum, window.header.searchComponent) then
            debugLog("搜索框焦点设置失败，设置到窗口")
            Safety.safeSetJoypadFocus(window.playerNum, window)
        end
    else
        debugLog("设置焦点到窗口")
        Safety.safeSetJoypadFocus(window.playerNum, window)
    end

    -- 记录焦点窗口
    ControllerSupport.state.focusedWindows[window.playerNum] = window
end

-- ============================================
-- 初始化模块
-- ============================================
local function initializeControllerSupport()
    debugLog("开始初始化手柄支持系统")

    -- 检查依赖
    if not ControllerSupport.checkDependencies() then
        debugLog("依赖检查失败，停止初始化")
        return
    end

    -- 应用窗口补丁
    ControllerSupport.applyWindowPatches()

    -- 设置钩子
    ControllerSupport.setupHooks()

    ControllerSupport.state.isActive = true
    debugLog("手柄支持系统初始化完成")
end

function ControllerSupport.checkDependencies()
    -- 检查必要的全局变量和函数
    local requiredGlobals = {
        "JoypadState", "setJoypadFocus", "Keyboard", "getCore", "Events"
    }

    for _, globalName in ipairs(requiredGlobals) do
        if not _G[globalName] then
            debugLog("缺少必需的全局变量: " .. globalName)
            return false
        end
    end

    return true
end

function ControllerSupport.applyWindowPatches()
    for _, windowName in ipairs(ControllerSupport.targetWindows) do
        local windowClass = _G[windowName]
        if windowClass then
            local success = WindowPatcher.patchWindowClass(windowClass)
            if success then
                debugLog("成功为 " .. windowName .. " 添加手柄支持")
            else
                debugLog("为 " .. windowName .. " 添加手柄支持失败")
            end
        else
            debugLog("未找到窗口类: " .. windowName)
        end
    end
end

function ControllerSupport.setupHooks()
    -- 这里可以设置额外的钩子和事件监听器
    debugLog("设置钩子和事件监听器")
end

-- ============================================
-- 主初始化
-- ============================================
Events.OnGameBoot.Add(function()
    debugLog("游戏启动，准备初始化手柄支持")

    -- 延迟初始化，确保所有模组都已加载
    Events.OnTick.Add(function()
        initializeControllerSupport()
        return true -- 移除这个监听器
    end)
end)

-- ============================================
-- 导出接口（用于其他模组调用）
-- ============================================
ControllerSupport.Safety = Safety
ControllerSupport.ButtonHandler = ButtonHandler
ControllerSupport.WindowPatcher = WindowPatcher
ControllerSupport.FocusManager = FocusManager

-- 全局导出
_G[ControllerSupport.MOD_ID] = ControllerSupport

debugLog(ControllerSupport.MOD_NAME .. " 模板已加载")