-- Joypad Utility Functions
-- 手柄工具函数

local JoypadUtil = {}

-- 从 JoypadData 对象提取方向
function JoypadUtil.getJoypadDirection(dirData)
    -- 处理数字参数 (0=up, 1=down, 2=left, 3=right) - B42 标准
    if type(dirData) == "number" then
        if dirData == 0 then return "up" end
        if dirData == 1 then return "down" end
        if dirData == 2 then return "left" end
        if dirData == 3 then return "right" end
        return nil
    end

    -- 处理 JoypadData 对象
    if not dirData or not dirData.controller then return nil end

    local ctrl = dirData.controller

    -- 首先检查布尔字段（按键刚按下时有效）
    if ctrl.down == true or ctrl.down == 1 then return "down" end
    if ctrl.up == true or ctrl.up == 1 then return "up" end
    if ctrl.left == true or ctrl.left == 1 then return "left" end
    if ctrl.right == true or ctrl.right == 1 then return "right" end

    -- 检查 D-pad 字段
    if ctrl.dpd == true or ctrl.dpd == 1 or ctrl.dpdown then return "down" end
    if ctrl.dpu == true or ctrl.dpu == 1 or ctrl.dpup then return "up" end
    if ctrl.dpl == true or ctrl.dpl == 1 or ctrl.dpleft then return "left" end
    if ctrl.dpr == true or ctrl.dpr == 1 or ctrl.dpright then return "right" end

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

-- 手柄按钮常量封装
JoypadUtil.AButton = Joypad.AButton
JoypadUtil.BButton = Joypad.BButton
JoypadUtil.XButton = Joypad.XButton
JoypadUtil.YButton = Joypad.YButton
JoypadUtil.LBumper = Joypad.LBumper or Joypad.L1Button
JoypadUtil.RBumper = Joypad.RBumper or Joypad.R1Button
JoypadUtil.DOWN = Joypad.DOWN
JoypadUtil.UP = Joypad.UP
JoypadUtil.LEFT = Joypad.LEFT
JoypadUtil.RIGHT = Joypad.RIGHT

return JoypadUtil
