-- Utility functions for NeatControllerSupport

-- Debug: print all fields of JoypadData and controller
function debugJoypadData(dirData)
    if not dirData then return end
    print("[NCS-Joypad] === JoypadData debug ===")
    for k, v in pairs(dirData) do
        print("[NCS-Joypad] " .. tostring(k) .. " = " .. tostring(v))
    end
    print("[NCS-Joypad] =======================")

    -- Also check controller fields
    if dirData.controller then
        print("[NCS-Joypad] === JoypadControllerData debug ===")
        for k, v in pairs(dirData.controller) do
            print("[NCS-Joypad] controller." .. tostring(k) .. " = " .. tostring(v))
        end
        print("[NCS-Joypad] =======================")
    end
end

-- Extract direction from JoypadData object
function getJoypadDirection(dirData)
    if not dirData then
        print("[NCS-Joypad] dirData is nil")
        return nil
    end

    local ctrl = dirData.controller
    if not ctrl then
        print("[NCS-Joypad] ctrl is nil")
        return nil
    end

    -- Check controller buttons directly (boolean values)
    print("[NCS-Joypad] ctrl.down=" .. tostring(ctrl.down) .. " ctrl.up=" .. tostring(ctrl.up))
    print("[NCS-Joypad] ctrl.left=" .. tostring(ctrl.left) .. " ctrl.right=" .. tostring(ctrl.right))
    print("[NCS-Joypad] Joypad values: DOWN=" .. tostring(Joypad.DOWN) .. " UP=" .. tostring(Joypad.UP))

    -- Check D-pad buttons via controller (direct boolean check)
    if ctrl.down then return "DOWN" end
    if ctrl.up then return "UP" end
    if ctrl.left then return "LEFT" end
    if ctrl.right then return "RIGHT" end

    -- Check D-pad (alternative field names)
    if ctrl.dpd or ctrl.dpdown then return "DOWN" end
    if ctrl.dpu or ctrl.dpup then return "UP" end
    if ctrl.dpl or ctrl.dpleft then return "LEFT" end
    if ctrl.dpr or ctrl.dpright then return "RIGHT" end

    -- Check axis values (left stick)
    if ctrl.lstickx and ctrl.lsticky then
        local threshold = 0.5
        if ctrl.lsticky > threshold then return "DOWN" end
        if ctrl.lsticky < -threshold then return "UP" end
        if ctrl.lstickx > threshold then return "RIGHT" end
        if ctrl.lstickx < -threshold then return "LEFT" end
    end

    print("[NCS-Joypad] No direction found")
    return nil
end

-- Check if joypad is connected for player
function isJoypadActive(playerNum)
    return JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]
end

-- Safe wrapper for setJoypadFocus
function safeSetJoypadFocus(playerNum, target)
    if not target then return false end
    if not isJoypadActive(playerNum) then return false end

    local success, err = pcall(setJoypadFocus, playerNum, target)
    return success
end

return {
    getJoypadDirection = getJoypadDirection,
    debugJoypadData = debugJoypadData,
    isJoypadActive = isJoypadActive,
    safeSetJoypadFocus = safeSetJoypadFocus
}
