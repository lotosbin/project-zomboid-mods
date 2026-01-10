-- Utility functions for NeatControllerSupport

-- Debug: dump object structure (limited depth to avoid infinite recursion)
local function dumpObject(obj, prefix, depth, maxDepth)
    if not obj then
        print(prefix .. "nil")
        return
    end
    if depth > maxDepth then
        print(prefix .. "... (max depth reached)")
        return
    end

    local objType = type(obj)
    if objType == "userdata" or objType == "table" then
        -- Check if already visited (prevent infinite recursion)
        if depth > 0 then
            local seen = {}
            local function checkSeen(o, p)
                if type(o) == "table" then
                    if seen[o] then
                        print(p .. "... (circular reference)")
                        return true
                    end
                    seen[o] = true
                end
                return false
            end
            if checkSeen(obj, prefix) then return end
        end

        local count = 0
        local firstFew = {}
        if objType == "table" then
            for k, v in pairs(obj) do
                count = count + 1
                if count <= 5 then
                    local keyStr = type(k) == "number" and "[" .. k .. "]" or tostring(k)
                    if type(v) == "userdata" or type(v) == "table" then
                        table.insert(firstFew, keyStr .. "={" .. tostring(v) .. "}")
                    else
                        table.insert(firstFew, keyStr .. "=" .. tostring(v))
                    end
                end
            end
        end
        local info = tostring(obj)
        if obj.getClassName and obj:getClassName then
            info = obj:getClassName()
        end
        if count > 5 then
            print(prefix .. info .. " { " .. table.concat(firstFew, ", ") .. ", ... +" .. (count - 5) .. " more }")
        else
            print(prefix .. info .. " { " .. table.concat(firstFew, ", ") .. " }")
        end
    else
        print(prefix .. tostring(obj) .. " (" .. objType .. ")")
    end
end

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

-- 从 JoypadData 对象提取方向
function getJoypadDirection(dirData)
    if not dirData then
        print("[NCS-Joypad] dirData 为空")
        return nil
    end

    local ctrl = dirData.controller
    if not ctrl then
        print("[NCS-Joypad] ctrl 为空")
        return nil
    end

    -- 打印所有控制器字段用于调试
    print("[NCS-Joypad] === 控制器状态 ===")
    print("[NCS-Joypad] ctrl.down=" .. tostring(ctrl.down) .. " ctrl.up=" .. tostring(ctrl.up))
    print("[NCS-Joypad] ctrl.left=" .. tostring(ctrl.left) .. " ctrl.right=" .. tostring(ctrl.right))
    print("[NCS-Joypad] ctrl.dpu=" .. tostring(ctrl.dpu) .. " ctrl.dpd=" .. tostring(ctrl.dpd))
    print("[NCS-Joypad] ctrl.dpl=" .. tostring(ctrl.dpl) .. " ctrl.dpr=" .. tostring(ctrl.dpr))
    if ctrl.lstickx then print("[NCS-Joypad] ctrl.lstickx=" .. tostring(ctrl.lstickx)) end
    if ctrl.lsticky then print("[NCS-Joypad] ctrl.lsticky=" .. tostring(ctrl.lsticky)) end
    print("[NCS-Joypad] ===================")

    -- 直接检查 controller 的布尔字段 (Zomboid B42 使用这种格式)
    if ctrl.down == true or ctrl.down == 1 then
        print("[NCS-Joypad] 检测到 DOWN")
        return "DOWN"
    end
    if ctrl.up == true or ctrl.up == 1 then
        print("[NCS-Joypad] 检测到 UP")
        return "UP"
    end
    if ctrl.left == true or ctrl.left == 1 then
        print("[NCS-Joypad] 检测到 LEFT")
        return "LEFT"
    end
    if ctrl.right == true or ctrl.right == 1 then
        print("[NCS-Joypad] 检测到 RIGHT")
        return "RIGHT"
    end

    -- 检查 D-pad 替代字段名
    if ctrl.dpd or ctrl.dpdown then
        print("[NCS-Joypad] 检测到 dpdown")
        return "DOWN"
    end
    if ctrl.dpu or ctrl.dpup then
        print("[NCS-Joypad] 检测到 dpup")
        return "UP"
    end
    if ctrl.dpl or ctrl.dpleft then
        print("[NCS-Joypad] 检测到 dpleft")
        return "LEFT"
    end
    if ctrl.dpr or ctrl.dpright then
        print("[NCS-Joypad] 检测到 dpright")
        return "RIGHT"
    end

    -- 检查左摇杆轴值
    if ctrl.lstickx and ctrl.lsticky then
        local threshold = 0.5
        print("[NCS-Joypad] lstickx=" .. tostring(ctrl.lstickx) .. " lsticky=" .. tostring(ctrl.lsticky) .. " threshold=" .. tostring(threshold))
        if ctrl.lsticky > threshold then
            print("[NCS-Joypad] 检测到 lsticky DOWN")
            return "DOWN"
        end
        if ctrl.lsticky < -threshold then
            print("[NCS-Joypad] 检测到 lsticky UP")
            return "UP"
        end
        if ctrl.lstickx > threshold then
            print("[NCS-Joypad] 检测到 lstickx RIGHT")
            return "RIGHT"
        end
        if ctrl.lstickx < -threshold then
            print("[NCS-Joypad] 检测到 lstickx LEFT")
            return "LEFT"
        end
    end

    -- 检查 axis0/axis1 (备用轴名)
    if ctrl.axis0 and ctrl.axis1 then
        local threshold = 0.5
        if ctrl.axis1 > threshold then return "DOWN" end
        if ctrl.axis1 < -threshold then return "UP" end
        if ctrl.axis0 > threshold then return "RIGHT" end
        if ctrl.axis0 < -threshold then return "LEFT" end
    end

    print("[NCS-Joypad] 未检测到方向")
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

-- Debug: dump scroll view structure for UI debugging
function debugScrollView(scrollView, label)
    print("[NCS-Debug] === ScrollView: " .. tostring(label) .. " ===")
    if not scrollView then
        print("[NCS-Debug] scrollView is nil")
        return
    end

    dumpObject(scrollView, "[NCS-Debug] scrollView: ", 0, 2)

    -- Check key methods
    print("[NCS-Debug] --- Methods ---")
    print("[NCS-Debug] scrollToIndex: " .. tostring(scrollView.scrollToIndex))
    print("[NCS-Debug] refreshItems: " .. tostring(scrollView.refreshItems))
    print("[NCS-Debug] setYScroll: " .. tostring(scrollView.setYScroll))
    print("[NCS-Debug] getYScroll: " .. tostring(scrollView.getYScroll))
    print("[NCS-Debug] setXScroll: " .. tostring(scrollView.setXScroll))
    print("[NCS-Debug] itemPool: " .. tostring(scrollView.itemPool))
    if scrollView.itemPool then
        print("[NCS-Debug] itemPool count: " .. #scrollView.itemPool)
    end

    -- Check Joypad support
    print("[NCS-Debug] joypadIndex: " .. tostring(scrollView.joypadIndex))
    print("[NCS-Debug] joypadSelected: " .. tostring(scrollView.joypadSelected))
    print("[NCS-Debug] =======================")
end

-- Debug: dump recipe list panel structure
function debugRecipeListPanel(panel, label)
    print("[NCS-Debug] === RecipeListPanel: " .. tostring(label) .. " ===")
    if not panel then
        print("[NCS-Debug] panel is nil")
        return
    end

    dumpObject(panel, "[NCS-Debug] panel: ", 0, 2)

    -- Check key fields
    print("[NCS-Debug] --- Key Fields ---")
    print("[NCS-Debug] logic: " .. tostring(panel.logic))
    print("[NCS-Debug] filteredRecipes: " .. tostring(panel.filteredRecipes))
    if panel.filteredRecipes then
        print("[NCS-Debug] filteredRecipes count: " .. #panel.filteredRecipes)
    end
    print("[NCS-Debug] currentScrollView: " .. tostring(panel.currentScrollView))
    print("[NCS-Debug] joypadSelectedIndex: " .. tostring(panel.joypadSelectedIndex))
    print("[NCS-Debug] gridColumnCount: " .. tostring(panel.gridColumnCount))
    print("[NCS-Debug] =======================")
end

return {
    getJoypadDirection = getJoypadDirection,
    debugJoypadData = debugJoypadData,
    isJoypadActive = isJoypadActive,
    safeSetJoypadFocus = safeSetJoypadFocus,
    debugScrollView = debugScrollView,
    debugRecipeListPanel = debugRecipeListPanel,
    dumpObject = dumpObject
}
