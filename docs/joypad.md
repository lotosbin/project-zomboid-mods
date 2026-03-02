# Project Zomboid 手柄 API 文档

> Project Zomboid B42 手柄开发指南

---

## 继承关系

```
ISUIElement
  └── ISPanel
        └── ISWindow
              └── ISCollapsableWindowJoypad  (支持手柄的可折叠窗口)

ISUIElement
  └── ISPanel
        └── ISCollapsableWindow (普通窗口)
              └── ISCollapsableWindowJoypad

ISUIElement
  └── ISPanel
        └── ISPanelJoypad  (支持手柄的面板)
```

---

## 官方 API (来自 Project Zomboid 官方 Wiki)

### JoypadButtons - 按钮常量

| 常量 | 说明 |
|------|------|
| `Joypad.AButton` | A 按钮 |
| `Joypad.BButton` | B 按钮 |
| `Joypad.XButton` | X 按钮 |
| `Joypad.YButton` | Y 按钮 |
| `Joypad.LBumper` | 左肩键 (L1) |
| `Joypad.RBumper` | 右肩键 (R1) |
| `Joypad.LT` | 左扳机 (L2) |
| `Joypad.RT` | 右扳机 (R2) |
| `Joypad.DPadUp` | 方向键上 |
| `Joypad.DPadDown` | 方向键下 |
| `Joypad.DPadLeft` | 方向键左 |
| `Joypad.DPadRight` | 方向键右 |
| `Joypad.BackButton` | 返回键 |
| `Joypad.StartButton` | 开始键 |

### JoypadState - 手柄状态

```lua
-- 检查玩家是否使用手柄
if JoypadState.players[playerNum + 1] then
    -- 手柄已连接
end
```

### Triggers - 扳机

```lua
-- 扳机返回值范围: 0.0 到 1.0
-- LT = 左扳机 (瞄准/精确操作)
-- RT = 右扳机 (射击/主要动作)
```

### Sticks - 摇杆

```lua
-- 摇杆返回值范围: -1.0 到 1.0
-- lStickX = 左摇杆 X轴 (左负右正)
-- lStickY = 左摇杆 Y轴 (上负下正)
-- rStickX = 右摇杆 X轴
-- rStickY = 右摇杆 Y轴

-- 典型死区阈值
local DEADZONE = 0.2  -- 20%
```

### 焦点管理

```lua
-- 设置手柄焦点
setJoypadFocus(playerNum, control)

-- 获取当前焦点
getJoypadFocus(playerNum)
```

---

## ISCollapsableWindowJoypad 使用方法

### 1. 基本使用

```lua
-- 1. 继承类
MyWindow = ISCollapsableWindowJoypad:derive("MyWindow")

-- 2. 创建实例
function MyWindow:new(x, y, width, height, player)
    local o = {}
    o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.player = player
    o.playerNum = player:getPlayerNum()
    return o
end

-- 3. 初始化
function MyWindow:initialise()
    ISCollapsableWindowJoypad.initialise(self)
end

-- 4. 创建子组件
function MyWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    -- 添加你的 UI 组件
end

-- 5. 渲染
function MyWindow:render()
    ISCollapsableWindowJoypad.render(self)
    -- 自定义渲染
end

-- 6. 打开窗口
function MyWindow:open()
    self:initialise()
    self:addToUIManager()
    -- 设置手柄焦点
    if JoypadState.players[self.playerNum + 1] then
        setJoypadFocus(self.playerNum, self)
    end
end
```

---

## ISPanelJoypad 使用方法

```lua
-- 用于面板类
MyPanel = ISPanelJoypad:derive("MyPanel")

function MyPanel:new(x, y, width, height)
    local o = ISPanelJoypad.new(self, x, y, width, height)
    return o
end

function MyPanel:initialise()
    ISPanelJoypad.initialise(self)
end
```

---

## 手柄事件处理

### 必须实现的手柄回调函数

| 函数 | 参数 | 用途 |
|------|------|------|
| `onJoypadDown(button)` | button 按键代码 | 按下手柄按钮时触发 |
| `onJoypadDirUp()` | - | 方向键上 |
| `onJoypadDirDown()` | - | 方向键下 |
| `onJoypadDirLeft()` | - | 方向键左 |
| `onJoypadDirRight()` | - | 方向键右 |
| `onJoypadTick(joypadData)` | joypadData 摇杆数据 | 摇杆移动时每帧触发 |

### 手柄按钮代码 (B42)

```lua
-- 标准按钮
Joypad.AButton   -- A 键 (确认) - 绿色
Joypad.BButton   -- B 键 (返回/取消) - 红色
Joypad.XButton   -- X 键 - 蓝色
Joypad.YButton   -- Y 键 - 黄色

-- 肩键
Joypad.LBumper   -- LB / L1 - 左肩键
Joypad.RBumper   -- RB / R1 - 右肩键
Joypad.LT        -- 左扳机 (L2) - 瞄准/精确操作
Joypad.RT        -- 右扳机 (R2) - 射击/主要动作

-- 方向键 (数字代码)
DPadUp = 10     -- 方向键上
DPadDown = 11   -- 方向键下
DPadLeft = 12   -- 方向键左
DPadRight = 13  -- 方向键右

-- 系统按钮
Joypad.StartButton  -- 开始键 - 暂停/菜单
Joypad.SelectButton -- 选择键 (Back/Select)
```

### 摇杆数据 (joypadData)

```lua
function MyWindow:onJoypadTick(joypadData)
    -- 左摇杆 (通常用于移动)
    local lx = joypadData.lStickX  -- -1 到 1 (左负右正)
    local ly = joypadData.lStickY  -- -1 到 1 (上负下正)

    -- 右摇杆 (通常用于视角/旋转)
    local rx = joypadData.rStickX
    local ry = joypadData.rStickY

    -- 扳机 (模拟值 0 到 1)
    local lt = joypadData.LT  -- 左扳机
    local rt = joypadData.RT  -- 右扳机

    -- 按钮数组 (按下为 true)
    local buttons = joypadData.buttons
    -- buttons[1] = A, buttons[2] = B, ...
end
```

### JoypadState 全局状态

```lua
-- 检查手柄是否连接
if JoypadState.players[playerNum + 1] then
    -- 手柄已连接
end

-- 访问当前手柄状态
local controller = JoypadState.players[playerNum + 1]
if controller then
    local lx = controller.lStickX
    local ly = controller.lStickY
    local rx = controller.rStickX
    local ry = controller.rStickY
    local lt = controller.LT
    local rt = controller.RT
end
```

---

## 摇杆死区处理

摇杆存在物理漂移，需要设置死区来忽略微小输入：

```lua
local DEADZONE = 0.2  -- 20% (官方推荐)

local function isInDeadzone(value)
    return math.abs(value) < DEADZONE
end

function MyWindow:onJoypadTick(joypadData)
    local lx = joypadData.lStickX
    local ly = joypadData.lStickY

    -- 忽略死区内的输入
    if not isInDeadzone(lx) or not isInDeadzone(ly) then
        -- 处理摇杆输入
    end
end
```

---

## 核心 API

### 焦点管理

```lua
-- 设置手柄焦点
setJoypadFocus(playerNum, control)

-- 获取当前焦点
getJoypadFocus(playerNum)

-- 检查手柄是否连接
JoypadState.players[playerNum + 1]
```

### 按钮按下检测

```lua
-- 检测按钮是否按下 (需要持续检测)
isJoypadPressed(playerNum, button)

-- 示例
if isJoypadPressed(playerNum, Joypad.AButton) then
    -- A 键被按住
end
```

### 继承的标准方法

```lua
-- 生命周期
:initialise()           -- 初始化
:createChildren()       -- 创建子组件
:render()              -- 渲染
:update()              -- 每帧更新
:close()               -- 关闭

-- 位置和大小
:getX() :setX(x)
:getY() :setY(y)
:getWidth() :setWidth(w)
:getHeight() :setHeight(h)

-- 可见性
:isVisible()
:setVisible(bool)
:addToUIManager()
:removeFromUIManager()
```

---

## 与普通 ISCollapsableWindow 的区别

| 特性 | ISCollapsableWindow | ISCollapsableWindowJoypad |
|------|---------------------|---------------------------|
| 手柄支持 | ❌ 无 | ✅ 有 |
| 方向键导航 | ❌ 无 | ✅ 有 |
| 摇杆处理 | ❌ 无 | ✅ 有 |
| 自动焦点管理 | ❌ 无 | ✅ 有 |

---

## 实用工具函数 (JoypadUtil)

来自 NeatControllerSupport 的工具函数：

```lua
local JoypadUtil = require "NeatControllerSupport/JoypadUtil"

-- 从 JoypadData 对象提取方向
function JoypadUtil.getJoypadDirection(dirData)
    -- 处理数字参数 (0=up, 1=down, 2=left, 3=right)
    if type(dirData) == "number" then
        local dirMap = { [0]="up", [1]="down", [2]="left", [3]="right" }
        return dirMap[dirData]
    end

    -- 处理 JoypadData 对象
    if not dirData then return nil end

    local ctrl = dirData
    if dirData.controller then ctrl = dirData.controller end

    if ctrl.down == true or ctrl.down == 1 then return "down" end
    if ctrl.up == true or ctrl.up == 1 then return "up" end
    if ctrl.left == true or ctrl.left == 1 then return "left" end
    if ctrl.right == true or ctrl.right == 1 then return "right" end

    return nil
end

-- 检查手柄是否连接
function JoypadUtil.isJoypadActive(playerNum)
    return JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]
end

-- 安全设置手柄焦点
function JoypadUtil.safeSetJoypadFocus(playerNum, target)
    if not target then return false end
    if not JoypadUtil.isJoypadActive(playerNum) then return false end
    local success, err = pcall(setJoypadFocus, playerNum, target)
    return success
end

-- 手柄按钮常量
JoypadUtil.AButton = Joypad.AButton
JoypadUtil.BButton = Joypad.BButton
JoypadUtil.XButton = Joypad.XButton
JoypadUtil.YButton = Joypad.YButton
JoypadUtil.LBumper = Joypad.LBumper or Joypad.L1Button
JoypadUtil.RBumper = Joypad.RBumper or Joypad.R1Button
```

---

## 常用按钮映射建议

### UI 窗口标准映射

| 按钮 | 功能 | 说明 |
|------|------|------|
| **A** | 确认/选择 | 选择列表项、确认对话框 |
| **B** | 取消/关闭 | 关闭窗口、取消操作 |
| **X** | 动作/交互 | 与物品交互、执行动作 |
| **Y** | 搜索/菜单 | 打开搜索框、显示菜单 |
| **LB** | 上一个/左翻 | 切换分类、翻页上一页 |
| **RB** | 下一个/右翻 | 切换分类、翻页下一页 |
| **LT** | 精细操作 | 精确模式、预览 |
| **RT** | 快速操作 | 快速确认 |
| **方向键** | 导航 | 上下左右移动光标 |

---

## 示例：完整的建造界面

```lua
BuildingUI = ISCollapsableWindowJoypad:derive("BuildingUI")

-- 配置
local DEADZONE = 0.2  -- 官方推荐死区
local GRID_SIZE = 50
local GRID_DELAY = 150

function BuildingUI:new(x, y, width, height, player)
    local o = {}
    o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.title = "建造"
    -- 状态记录
    o.lastMoveTime = 0
    o.lastRotateTime = 0
    return o
end

function BuildingUI:initialise()
    ISCollapsableWindowJoypad.initialise(self)
end

function BuildingUI:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)

    -- 创建面板
    self.panel = ISPanel:new(0, self:titleBarHeight(), self.width, self.height - self:titleBarHeight())
    self.panel:initialise()
    self:addChild(self.panel)
end

-- 手柄按钮处理
function BuildingUI:onJoypadDown(button)
    if button == Joypad.AButton then
        -- 确认选择
        self:confirmSelection()
        return true
    elseif button == Joypad.BButton then
        -- 关闭
        self:close()
        return true
    elseif button == Joypad.XButton then
        -- 切换排序
        self:toggleSort()
        return true
    elseif button == Joypad.YButton then
        -- 切换视图
        self:toggleView()
        return true
    elseif button == Joypad.LBumper then
        -- 上一个分类
        self:prevCategory()
        return true
    elseif button == Joypad.RBumper then
        -- 下一个分类
        self:nextCategory()
        return true
    end
    return false
end

-- 方向键处理
function BuildingUI:onJoypadDirUp()
    self:selectPrevious()
    return true
end

function BuildingUI:onJoypadDirDown()
    self:selectNext()
    return true
end

function BuildingUI:onJoypadDirLeft()
    self:pageUp()
    return true
end

function BuildingUI:onJoypadDirRight()
    self:pageDown()
    return true
end

-- 摇杆处理：区块移动
function BuildingUI:onJoypadTick(joypadData)
    local currentTime = getTimestampMs()

    -- 左摇杆：窗口区块移动
    local lx = joypadData.lStickX
    local ly = joypadData.lStickY

    if (math.abs(lx) > DEADZONE or math.abs(ly) > DEADZONE)
        and currentTime - self.lastMoveTime > GRID_DELAY then

        local moveX = 0
        local moveY = 0

        if ly < -DEADZONE then moveY = -GRID_SIZE
        elseif ly > DEADZONE then moveY = GRID_SIZE end

        if lx < -DEADZONE then moveX = -GRID_SIZE
        elseif lx > DEADZONE then moveX = GRID_SIZE end

        -- 对角线修正
        if moveX ~= 0 and moveY ~= 0 then
            moveX = moveX * 0.707
            moveY = moveY * 0.707
        end

        -- 边界检查
        local newX = math.max(0, math.min(self:getX() + moveX,
            getCore():getScreenWidth() - self:getWidth()))
        local newY = math.max(0, math.min(self:getY() + moveY,
            getCore():getScreenHeight() - self:getHeight()))

        self:setX(newX)
        self:setY(newY)
        self.lastMoveTime = currentTime
    end

    -- 右摇杆：旋转
    local rx = joypadData.rStickX

    if math.abs(rx) > DEADZONE and currentTime - self.lastRotateTime > GRID_DELAY then
        local angle = rx > 0 and 90 or -90
        self:rotate(angle)
        self.lastRotateTime = currentTime
    end
end
```

---

## 调试工具

```lua
-- 调试手柄输入
function debugJoypadInput(playerNum)
    if not JoypadState.players[playerNum+1] then
        print("玩家 " .. playerNum .. " 未连接手柄")
        return
    end

    print("=== 手柄调试信息 ===")
    print("玩家: " .. playerNum)

    -- 摇杆状态
    local stick = JoypadState.players[playerNum+1]
    print("左摇杆: X=" .. string.format("%.2f", stick.lStickX) .. ", Y=" .. string.format("%.2f", stick.lStickY))
    print("右摇杆: X=" .. string.format("%.2f", stick.rStickX) .. ", Y=" .. string.format("%.2f", stick.rStickY))
    print("LT=" .. string.format("%.2f", stick.LT) .. ", RT=" .. string.format("%.2f", stick.RT))
end
```

---

## 注意事项

### 兼容性
- 不同手柄制造商可能有不同的按钮布局
- 某些手柄可能缺少特定按钮（如 Select 按钮）
- 建议提供键鼠备用操作方式

### 性能考虑
- 避免在 `onJoypadDown` 中进行重计算
- 使用冷却时间防止摇杆输入过快
- 合理使用事件监听器，避免内存泄漏

### 最佳实践
- 始终检查手柄连接状态
- 提供视觉反馈（按钮高亮、焦点指示）
- 遵循平台常见的手柄操作习惯
- 使用死区处理摇杆漂移（官方推荐 0.2）

---

## 参考资料

- [Project Zomboid Official Wiki - Lua API](https://projectzomboid.com/modding/wiki/Lua_API)
- BuildingCraft 模组源码
- NeatControllerSupport 模组源码
