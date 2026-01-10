-- Joypad Utility Functions
-- 手柄工具函数

local JoypadUtil = {}

-- 从 JoypadData 对象提取方向
function JoypadUtil.getJoypadDirection(dirData)
    if not dirData or not dirData.controller then return nil end

    local ctrl = dirData.controller

    -- 直接检查 controller 的布尔字段 (Zomboid B42 使用这种格式)
    if ctrl.down == true or ctrl.down == 1 then
        return "down"
    end
    if ctrl.up == true or ctrl.up == 1 then
        return "up"
    end
    if ctrl.left == true or ctrl.left == 1 then
        return "left"
    end
    if ctrl.right == true or ctrl.right == 1 then
        return "right"
    end

    -- 检查 D-pad 字段 (Zomboid 使用 dpu/dpd/dpl/dpr)
    if ctrl.dpd == true or ctrl.dpd == 1 or ctrl.dpdown then
        return "down"
    end
    if ctrl.dpu == true or ctrl.dpu == 1 or ctrl.dpup then
        return "up"
    end
    if ctrl.dpl == true or ctrl.dpl == 1 or ctrl.dpleft then
        return "left"
    end
    if ctrl.dpr == true or ctrl.dpr == 1 or ctrl.dpright then
        return "right"
    end

    -- 检查左摇杆轴值
    if ctrl.lstickx and ctrl.lsticky then
        local threshold = 0.5
        if ctrl.lsticky > threshold then return "down" end
        if ctrl.lsticky < -threshold then return "up" end
        if ctrl.lstickx > threshold then return "right" end
        if ctrl.lstickx < -threshold then return "left" end
    end

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

return JoypadUtil
