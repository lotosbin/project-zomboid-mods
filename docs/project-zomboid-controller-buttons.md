# Project Zomboid 手柄按钮完整定义参考

## 📋 概述

基于 CleanUI 模组和官方代码分析，整理 Project Zomboid 中所有可用的手柄按钮定义。

## 🎮 按钮常量定义

### 基础按钮
```lua
-- 标准游戏手柄按钮
Joypad.AButton      -- A按钮 (绿色) - 确认/选择/交互
Joypad.BButton      -- B按钮 (红色) - 取消/关闭/返回
Joypad.XButton      -- X按钮 (蓝色) - 动作/拾取/重载
Joypad.YButton      -- Y按钮 (黄色) - 菜单/库存/地图

-- 肩键和扳机
Joypad.LBumper      -- 左肩键 (LB) - 上一个/翻页
Joypad.RBumper      -- 右肩键 (RB) - 下一个/翻页
Joypad.LTrigger     -- 左扳机 (LT) - 瞄准/精确操作
Joypad.RTrigger     -- 右扳机 (RT) - 射击/主要动作

-- 方向键
Joypad.DPadLeft     -- 方向键左
Joypad.DPadRight    -- 方向键右
Joypad.DPadUp       -- 方向键上
Joypad.DPadDown     -- 方向键下

-- 系统按钮
Joypad.StartButton  -- 开始键 - 暂停/菜单
Joypad.SelectButton -- 选择键 (Back/Select) - 辅助功能
```

### 摇杆输入
```lua
-- 摇杆状态 (通过 JoypadState 访问)
JoypadState.leftStickX    -- 左摇杆 X轴 (-1.0 到 1.0)
JoypadState.leftStickY    -- 左摇杆 Y轴 (-1.0 到 1.0)
JoypadState.rightStickX   -- 右摇杆 X轴 (-1.0 到 1.0)
JoypadState.rightStickY   -- 右摇杆 Y轴 (-1.0 到 1.0)
```

## 🔧 使用示例

### 基础按钮处理
```lua
function MyWindow:onJoypadDown(button)
    if button == Joypad.AButton then
        -- 确认操作
        self:confirmAction()
    elseif button == Joypad.BButton then
        -- 取消/关闭窗口
        self:close()
    elseif button == Joypad.YButton then
        -- 打开搜索
        self:openSearch()
    elseif button == Joypad.LBumper then
        -- 上一个分类
        self:selectPreviousCategory()
    elseif button == Joypad.RBumper then
        -- 下一个分类
        self:selectNextCategory()
    end
end
```

### 按钮状态检查
```lua
-- 检查按钮是否被按下
function checkButtonPressed(playerNum, button)
    return JoypadState.players[playerNum+1] and isJoypadPressed(playerNum, button)
end

-- 获取摇杆输入
function getStickInput(playerNum)
    local player = JoypadState.players[playerNum+1]
    if player then
        return {
            leftX = player.leftStickX,
            leftY = player.leftStickY,
            rightX = player.rightStickX,
            rightY = player.rightStickY
        }
    end
    return nil
end
```

## 🎯 常用按钮映射建议

### UI 窗口标准映射
| 按钮 | 功能 | 说明 |
|------|------|------|
| **A** | 确认/选择 | 选择列表项、确认对话框 |
| **B** | 取消/关闭 | 关闭窗口、取消操作 |
| **X** | 动作/交互 | 与物品交互、执行动作 |
| **Y** | 搜索/菜单 | 打开搜索框、显示菜单 |
| **LB** | 上一个/左翻 | 切换分类、翻页上一页 |
| **RB** | 下一个/右翻 | 切换分类、翻页下一页 |
| **方向键** | 导航 | 上下左右移动光标 |

### 游戏内操作映射
| 按钮 | 功能 | 说明 |
|------|------|------|
| **A** | 交互/拾取 | 开门、拾取物品、使用物品 |
| **B** | 取消/后退 | 停止当前动作、关闭界面 |
| **X** | 重装/攻击 | 重装武器、轻攻击 |
| **Y** | 库存 | 打开背包界面 |
| **LT** | 瞄准 | 精确瞄准模式 |
| **RT** | 重攻击/射击 | 重攻击、开火 |
| **方向键** | 移动/导航 | 角色移动、菜单导航 |

## 🛠️ 实用工具函数

### 按钮检查工具
```lua
local ControllerUtils = {}

-- 检查玩家是否连接手柄
function ControllerUtils.isControllerConnected(playerNum)
    return JoypadState.players[playerNum+1] ~= nil
end

-- 获取当前按下的按钮
function ControllerUtils.getPressedButtons(playerNum)
    local pressed = {}
    local buttons = {
        Joypad.AButton, Joypad.BButton, Joypad.XButton, Joypad.YButton,
        Joypad.LBumper, Joypad.RBumper, Joypad.LTrigger, Joypad.RTrigger,
        Joypad.DPadLeft, Joypad.DPadRight, Joypad.DPadUp, Joypad.DPadDown
    }

    for _, button in ipairs(buttons) do
        if isJoypadPressed(playerNum, button) then
            table.insert(pressed, button)
        end
    end

    return pressed
end

-- 安全的按钮处理
function ControllerUtils.safeButtonHandler(window, button, handlers)
    if not window or not button then return false end

    local handler = handlers[button]
    if handler and type(handler) == "function" then
        local success, result = pcall(handler, window)
        return success and result
    end

    return false
end
```

### 按钮映射配置
```lua
-- 可配置的按钮映射
local ButtonMapping = {
    -- 窗口操作
    window = {
        confirm = Joypad.AButton,
        cancel = Joypad.BButton,
        search = Joypad.YButton,
        context = Joypad.XButton
    },

    -- 导航操作
    navigation = {
        next = Joypad.RBumper,
        previous = Joypad.LBumper,
        up = Joypad.DPadUp,
        down = Joypad.DPadDown,
        left = Joypad.DPadLeft,
        right = Joypad.DPadRight
    },

    -- 游戏操作
    game = {
        interact = Joypad.AButton,
        attack = Joypad.RTrigger,
        aim = Joypad.LTrigger,
        reload = Joypad.XButton,
        inventory = Joypad.YButton
    }
}

-- 动态按钮处理
function handleButtonByCategory(category, button)
    local mapping = ButtonMapping[category]
    if not mapping then return false end

    for action, mappedButton in pairs(mapping) do
        if button == mappedButton then
            return handleAction(action)
        end
    end

    return false
end
```

## 🔍 调试和测试

### 调试工具
```lua
-- 调试手柄输入
function debugJoypadInput(playerNum)
    if not JoypadState.players[playerNum+1] then
        print("玩家 " .. playerNum .. " 未连接手柄")
        return
    end

    print("=== 手柄调试信息 ===")
    print("玩家: " .. playerNum)

    -- 检查所有按钮
    local buttons = {
        {name = "A", id = Joypad.AButton},
        {name = "B", id = Joypad.BButton},
        {name = "X", id = Joypad.XButton},
        {name = "Y", id = Joypad.YButton},
        {name = "LB", id = Joypad.LBumper},
        {name = "RB", id = Joypad.RBumper}
    }

    for _, btn in ipairs(buttons) do
        if isJoypadPressed(playerNum, btn.id) then
            print("按下: " .. btn.name)
        end
    end

    -- 显示摇杆状态
    local stick = getStickInput(playerNum)
    if stick then
        print("左摇杆: X=" .. string.format("%.2f", stick.leftX) .. ", Y=" .. string.format("%.2f", stick.leftY))
        print("右摇杆: X=" .. string.format("%.2f", stick.rightX) .. ", Y=" .. string.format("%.2f", stick.rightY))
    end
end

-- 在按钮处理中添加调试
function MyWindow:onJoypadDown(button)
    if getDebug() then
        print("手柄按钮按下: " .. tostring(button) .. " 窗口: " .. self:getClassName())
    end

    -- 原有处理逻辑...
end
```

## ⚠️ 注意事项

### 兼容性
- 不同手柄制造商可能有不同的按钮布局
- 某些手柄可能缺少特定按钮（如 Select 按钮）
- 建议提供键鼠备用操作方式

### 性能考虑
- 避免在 `onJoypadDown` 中进行重计算
- 使用 `isJoypadPressed` 进行连续按键检测
- 合理使用事件监听器，避免内存泄漏

### 最佳实践
- 始终检查手柄连接状态
- 提供视觉反馈（按钮高亮、焦点指示）
- 遵循平台常见的手柄操作习惯
- 为不同的操作类型提供一致的按钮映射

---

这份参考文档基于 CleanUI 模组的实际使用经验和官方代码分析，提供了完整、准确的手柄按钮定义和使用指南。