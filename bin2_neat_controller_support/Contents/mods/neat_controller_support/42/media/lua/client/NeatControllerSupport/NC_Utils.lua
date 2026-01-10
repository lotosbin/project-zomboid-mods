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

    print("[NCS-Joypad] dirData type: " .. type(dirData))
    print("[NCS-Joypad] dirData.controller: " .. tostring(dirData.controller))

    local ctrl = dirData.controller
    if not ctrl then
        print("[NCS-Joypad] ctrl is nil, checking dirData fields...")
        for k, v in pairs(dirData) do
            print("[NCS-Joypad]   " .. tostring(k) .. " = " .. tostring(v))
        end
        return nil
    end

    print("[NCS-Joypad] ctrl fields: dpd=" .. tostring(ctrl.dpd) .. " dpdown=" .. tostring(ctrl.dpdown) ..
          " down=" .. tostring(ctrl.down) .. " dpu=" .. tostring(ctrl.dpu) .. " lsticky=" .. tostring(ctrl.lsticky))

    -- Check D-pad buttons via controller
    if ctrl.dpd or ctrl.dpdown or ctrl.down then return Joypad.DOWN end
    if ctrl.dpu or ctrl.dpup or ctrl.up then return Joypad.UP end
    if ctrl.dpr or ctrl.dpright or ctrl.right then return Joypad.RIGHT end
    if ctrl.dpl or ctrl.dpleft or ctrl.left then return Joypad.LEFT end

    -- Check axis values (left stick)
    if ctrl.lstickx and ctrl.lsticky then
        local threshold = 0.5
        print("[NCS-Joypad] lstickx=" .. tostring(ctrl.lstickx) .. " lsticky=" .. tostring(ctrl.lsticky))
        if ctrl.lsticky > threshold then return Joypad.DOWN end
        if ctrl.lsticky < -threshold then return Joypad.UP end
        if ctrl.lstickx > threshold then return Joypad.RIGHT end
        if ctrl.lstickx < -threshold then return Joypad.LEFT end
    end

    print("[NCS-Joypad] No direction found, returning nil")
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
