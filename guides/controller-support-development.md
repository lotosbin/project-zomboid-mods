# Project Zomboid 模组手柄支持开发流程指南

## 🎮 概述

本指南基于 `neat_controller_support` 补丁模组的开发和修复经验，提供完整的 Project Zomboid 模组手柄支持开发流程。

## 📋 开发流程概览

```
1. 需求分析 → 2. 架构设计 → 3. 基础实现 → 4. 测试验证 → 5. 优化完善 → 6. 发布维护
```

## 🎯 第一步：需求分析

### 1.1 确定支持范围
```lua
-- 需要支持的窗口类型
local targetWindows = {
    "NC_CraftingWindow",     -- 制作窗口
    "NC_BuildingWindow",     -- 建筑窗口
    "NC_InventoryWindow",    -- 背包窗口
    "RecipeListWindow"       -- 配方列表窗口
}

-- 需要支持的手柄操作
local controllerActions = {
    navigation = true,       -- 导航操作
    selection = true,        -- 选择操作
    search = true,          -- 搜索功能
    close = true,           -- 关闭窗口
    context = true          -- 上下文菜单
}
```

### 1.2 兼容性分析
- **目标游戏版本**: B42.13+
- **依赖模组**: Neat_Crafting, Neat_Building
- **手柄类型**: Xbox, PlayStation, 通用手柄

## 🏗️ 第二步：架构设计

### 2.1 补丁模式设计
```lua
-- 非侵入式补丁架构
local ControllerPatch = {
    -- 原始函数保存
    originalFunctions = {},

    -- 补丁目标
    patchTargets = {},

    -- 手柄映射
    buttonMappings = {},

    -- 状态管理
    state = {
        isActive = false,
        currentPlayer = 0,
        focusedWindow = nil
    }
}
```

### 2.2 安全机制设计
```lua
-- 多层安全检查
local SafetyChecks = {
    -- 对象有效性检查
    isValidObject = function(obj) end,

    -- 时序安全检查
    isSafeTiming = function() end,

    -- 权限检查
    hasPermission = function(action) end,

    -- 错误恢复
    recoverFromError = function(error) end
}
```

## 💻 第三步：基础实现

### 3.1 创建模组结构
```
mod_controller_support/
├── Contents/
│   └── mods/
│       └── mod_controller_support/
│           ├── mod.info
│           ├── poster.png
│           └── media/
│               └── lua/
│                   └── client/
│                       └── ControllerSupport/
│                           ├── Core.lua              -- 核心逻辑
│                           ├── Safety.lua            -- 安全检查
│                           ├── ButtonHandler.lua     -- 按钮处理
│                           ├── FocusManager.lua      -- 焦点管理
│                           └── WindowPatches.lua     -- 窗口补丁
```

### 3.2 核心模块实现

#### Core.lua - 核心初始化
```lua
-- 核心初始化模块
local Core = {}

function Core.initialize()
    -- 1. 安全检查
    if not Core.checkEnvironment() then
        return false
    end

    -- 2. 加载依赖
    Core.loadDependencies()

    -- 3. 注册补丁
    Core.registerPatches()

    -- 4. 初始化手柄系统
    Core.initializeControllerSystem()

    return true
end

function Core.checkEnvironment()
    -- 检查游戏版本
    -- 检查依赖模组
    -- 检查手柄支持
    return true
end

Events.OnGameBoot.Add(Core.initialize)
```

#### Safety.lua - 安全检查
```lua
-- 安全检查模块（基于修复经验）
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
    local requiredMethods = {"getClassName", "isVisible", "setJoypadFocus"}
    for _, method in ipairs(requiredMethods) do
        if not window[method] or type(window[method]) ~= "function" then
            debugLog("窗口缺少必要方法: " .. method)
            return false
        end
    end

    return true
end

function Safety.safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        debugLog("函数调用失败: " .. tostring(result))
        return nil
    end
    return result
end

return Safety
```

#### ButtonHandler.lua - 按钮处理
```lua
-- 手柄按钮处理模块
local ButtonHandler = {}
local Safety = require "Safety"

-- 标准按钮映射
ButtonHandler.buttonMappings = {
    [JoypadState.A] = "confirm",
    [JoypadState.B] = "cancel",
    [JoypadState.X] = "action",
    [JoypadState.Y] = "search",
    [JoypadState.LB] = "page_left",
    [JoypadState.RB] = "page_right",
    [JoypadState.LT] = "category_prev",
    [JoypadState.RT] = "category_next"
}

function ButtonHandler.handleButton(window, button)
    if not Safety.isValidWindow(window) then
        return false
    end

    local action = ButtonHandler.buttonMappings[button]
    if not action then
        return false
    end

    -- 根据窗口类型和按钮动作执行相应操作
    return ButtonHandler.executeAction(window, action)
end

function ButtonHandler.executeAction(window, action)
    if action == "cancel" then
        return ButtonHandler.handleCancel(window)
    elseif action == "search" then
        return ButtonHandler.handleSearch(window)
    elseif action == "confirm" then
        return ButtonHandler.handleConfirm(window)
    end

    return false
end

function ButtonHandler.handleCancel(window)
    if window.close and type(window.close) == "function" then
        return Safety.safeCall(window.close, window)
    end
    return false
end

return ButtonHandler
```

### 3.3 窗口补丁实现

#### WindowPatches.lua
```lua
-- 窗口补丁模块
local WindowPatches = {}
local Safety = require "Safety"
local ButtonHandler = require "ButtonHandler"

function WindowPatches.patchWindow(windowClass)
    if not windowClass then
        return false
    end

    -- 保存原始函数
    local original_onJoypadDown = windowClass.onJoypadDown

    -- 添加手柄支持
    function windowClass:onJoypadDown(button)
        -- 安全检查
        if not Safety.isValidWindow(self) then
            return false
        end

        -- 尝试原始处理
        if original_onJoypadDown then
            local success, result = Safety.safeCall(original_onJoypadDown, self, button)
            if success and result then
                return result
            end
        end

        -- 使用我们的处理
        return ButtonHandler.handleButton(self, button)
    end

    return true
end

return WindowPatches
```

## 🧪 第四步：测试验证

### 4.1 单元测试
```lua
-- 测试模块
local TestSuite = {}

function TestSuite.testSafetyChecks()
    -- 测试空对象检查
    assert(not Safety.isValidWindow(nil), "空对象检查失败")

    -- 测试销毁对象检查
    local destroyedWindow = { javaObject = { isDestroyed = function() return true end } }
    assert(not Safety.isValidWindow(destroyedWindow), "销毁对象检查失败")

    print("✅ 安全检查测试通过")
end

function TestSuite.testButtonHandling()
    -- 测试按钮映射
    assert(ButtonHandler.buttonMappings[JoypadState.B] == "cancel", "按钮映射失败")

    print("✅ 按钮处理测试通过")
end

-- 在游戏启动时运行测试
Events.OnGameStart.Add(function()
    TestSuite.testSafetyChecks()
    TestSuite.testButtonHandling()
end)
```

### 4.2 集成测试
```lua
-- 集成测试
function IntegrationTest.testWindowIntegration()
    -- 创建测试窗口
    local testWindow = createTestWindow()

    -- 测试补丁应用
    local success = WindowPatches.patchWindow(testWindow)
    assert(success, "窗口补丁应用失败")

    -- 测试手柄输入
    local result = testWindow:onJoypadDown(JoypadState.B)
    assert(result, "手柄输入处理失败")

    print("✅ 集成测试通过")
end
```

## 🔧 第五步：优化完善

### 5.1 性能优化
```lua
-- 性能监控
local Performance = {}

function Performance.startMonitoring()
    Performance.startTime = os.time()
    Performance.frameCount = 0
end

function Performance.checkPerformance()
    Performance.frameCount = Performance.frameCount + 1

    if Performance.frameCount % 60 == 0 then -- 每秒检查一次
        local currentTime = os.time()
        local deltaTime = currentTime - Performance.startTime

        if deltaTime > 1 then -- 如果超过1秒
            debugLog("性能警告: 60帧用了 " .. deltaTime .. " 秒")
        end

        Performance.startTime = currentTime
    end
end
```

### 5.2 错误恢复
```lua
-- 错误恢复机制
local ErrorRecovery = {}

function ErrorRecovery.handleCriticalError(error)
    debugLog("严重错误: " .. tostring(error))

    -- 重置状态
    ErrorRecovery.resetState()

    -- 通知用户
    ErrorRecovery.notifyUser("手柄支持遇到错误，已重置")

    -- 尝试重新初始化
    ErrorRecovery.attemptReinitialize()
end

function ErrorRecovery.resetState()
    ControllerPatch.state.isActive = false
    ControllerPatch.state.currentPlayer = 0
    ControllerPatch.state.focusedWindow = nil
end
```

## 📦 第六步：发布维护

### 6.1 版本管理
```lua
-- 版本信息
local Version = {
    major = 1,
    minor = 1,
    patch = 0,
    build = "stable"
}

function Version.toString()
    return string.format("%d.%d.%d-%s", Version.major, Version.minor, Version.patch, Version.build)
end

function Version.checkCompatibility(gameVersion)
    -- 检查游戏版本兼容性
    local requiredVersion = "42.13"
    return gameVersion >= requiredVersion
end
```

### 6.2 更新日志
```markdown
# 更新日志

## [1.1.0] - 2024-01-XX

### 新增
- 增强的安全检查机制
- 性能监控功能
- 错误恢复机制

### 修复
- 修复空指针异常
- 修复焦点丢失问题
- 修复对象销毁导致的崩溃

### 改进
- 优化手柄响应速度
- 改进调试日志
- 增强兼容性检查
```

## 🎯 最佳实践总结

### 1. **安全第一**
- 所有外部调用都要包装在 `pcall()` 中
- 严格的对象有效性检查
- 完善的错误处理机制

### 2. **非侵入设计**
- 保存原始函数引用
- 不修改原有代码逻辑
- 支持与其他模组共存

### 3. **性能考虑**
- 避免无用的循环检查
- 使用超时机制防止无限等待
- 监控性能指标

### 4. **可维护性**
- 模块化设计
- 详细的调试日志
- 完整的测试覆盖

### 5. **用户体验**
- 智能焦点管理
- 直观的手柄映射
- 友好的错误提示

## 🚀 开发工具推荐

- **调试工具**: `getDebug()` 模式 + 详细日志
- **测试工具**: 单元测试 + 集成测试
- **性能工具**: 帧率监控 + 内存使用检查
- **版本控制**: Git + 分支管理

---

这个开发流程基于真实的 `neat_controller_support` 修复经验，提供了从需求分析到发布维护的完整指南，确保手柄支持模组的稳定性和可靠性。