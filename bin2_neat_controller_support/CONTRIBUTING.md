# NeatControllerSupport 开发文档

## B42 手柄 API 变化

### 方向键处理 (关键变化)

**B41 旧方式：**
```lua
function onJoypadDirDown(dir)
    -- dir 是 JoypadData 对象，包含 controller.down/up/left/right 字段
    local direction = getJoypadDirection(dir)
end
```

**B42 新方式（推荐）：**
```lua
-- 使用独立函数处理每个方向
function onJoypadDirUp()
    -- 处理上键
end

function onJoypadDirDown(joypadData)
    -- 处理下键
end

function onJoypadDirLeft()
    -- 处理左键
end

function onJoypadDirRight()
    -- 处理右键
end
```

### D-pad 键值映射

| 按键 | onJoypadDown 值 | 对应方向函数 |
|------|----------------|-------------|
| D-pad 下 | 11 | onJoypadDirDown |
| D-pad 上 | 10 | onJoypadDirUp |
| D-pad 左 | 12 | onJoypadDirLeft |
| D-pad 右 | 13 | onJoypadDirRight |

### JoypadData 结构

B42 中 `onJoypadDirDown` 传入的 JoypadData 对象结构：
```lua
{
    controller = {
        down = true/false,  -- 下键
        up = true/false,    -- 上键
        left = true/false,  -- 左键
        right = true/false, -- 右键
    }
}
```

## 最佳实践

### 1. 回调函数必须返回布尔值
```lua
-- 错误：可能返回 nil
function onJoypadDown(button)
    if button == AButton then doSomething() end
end

-- 正确：始终返回 true/false
function onJoypadDown(button)
    if button == AButton then return true end
    return false
end
```

### 2. 使用 `== true` 比较返回值
```lua
-- 错误：如果 original 返回 nil，也会返回 nil
if originalOnJoypadDown then return originalOnJoypadDown(self, button) end

-- 正确：明确检查 boolean
if result == true then return true end
return false
```

### 3. 所有代码路径必须有返回值
```lua
local function doSomething()
    if cond then return true end
    -- 必须有，否则返回 nil
    return false
end
```

## 代码结构

```
NeatControllerSupport/
├── JoypadUtil.lua              # 手柄工具函数
├── Neat_Crafting/
│   ├── Neat_Crafting_patch.lua # 制作窗口手柄支持
│   └── NC_RecipeList_Panel_patch.lua  # 配方列表面板
└── Neat_Building/
    ├── Neat_Building_patch.lua     # 建造窗口手柄支持
    └── NB_BuildingRecipeList_Panel_patch.lua # 建造配方面板
```

## 测试方法

1. 打开游戏控制台 (F1)
2. 启用模组
3. 打开制作/建造界面
4. 使用手柄方向键测试导航
5. 查看 Output Log 中的 `[NCS-]` 日志
