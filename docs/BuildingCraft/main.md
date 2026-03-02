## 组件结构

```
BuildingCraft/
├── 42.0/
│   └── media/
│       ├── lua/
│       │   ├── client/                    # 客户端
│       │   │   ├── BuildingCraftMenu.lua   # 建筑菜单
│       │   │   ├── BuildingCraftUI.lua    # 建筑 UI
│       │   │   ├── BuildingCraftTileList.lua
│       │   │   ├── BuildingCraftTab.lua
│       │   │   └── ISBuildingCraftAction.lua
│       │   │
│       │   ├── server/                    # 服务器端
│       │   │   ├── BuildingData/          # 建筑数据定义
│       │   │   │   ├── Building_Data.lua           # 主数据（材料、配方）
│       │   │   │   ├── Building_Data_Wall.lua      # 墙壁
│       │   │   │   ├── Building_Data_Floor.lua     # 地板
│       │   │   │   ├── Building_Data_Door.lua      # 门
│       │   │   │   ├── Building_Data_Window.lua    # 窗户
│       │   │   │   ├── Building_Data_Roof.lua       # 屋顶
│       │   │   │   ├── Building_Data_Stair.lua     # 楼梯
│       │   │   │   ├── Building_Data_Fence.lua     # 栅栏
│       │   │   │   ├── Building_Data_Furniture.lua # 家具
│       │   │   │   ├── Building_Data_Container.lua # 容器
│       │   │   │   ├── Building_Data_InclinedWall.lua
│       │   │   │   └── Building_Data_BuildDecoration.lua
│       │   │   │
│       │   │   └── BuildingObjects/       # 建筑对象实现
│       │   │       ├── ISBuildWall.lua
│       │   │       ├── ISBuildFloor.lua
│       │   │       ├── ISBuildDoor.lua
│       │   │       ├── ISBuildWindow.lua
│       │   │       ├── ISBuildRoof.lua
│       │   │       ├── ISBuildStairs.lua
│       │   │       ├── ISBuildFence.lua
│       │   │       ├── ISBuildRamp.lua
│       │   │       ├── ISBuildGarageDoor.lua
│       │   │       ├── ISBuildDoubleDoor.lua
│       │   │       ├── ISBuildOneTileFurniture.lua
│       │   │       ├── ISBuildTwoTileFurniture.lua
│       │   │       ├── ISBuild2x2Furniture.lua
│       │   │       ├── ISBuild2x3Furniture.lua
│       │   │       ├── ISBuildThreeTileFurniture.lua
│       │   │       ├── ISBuildTelevision.lua
│       │   │       ├── ISBuildRadio.lua
│       │   │       ├── ISBuildGenerator.lua
│       │   │       ├── ISBuildFeedingTrough.lua
│       │   │       └── ISBuildUtilNew.lua
│       │   │
│       │   └── shared/                    # 共享
│       │       ├── BuildingCraftObject.lua # 建筑对象工具函数
│       │       ├── Building_Global.lua      # 全局配置
│       │       ├── FurnitureCapacityOverride.lua
│       │       ├── CustomLightProps.lua
│       │       ├── AddModTextureBase.lua
│       │       └── Translate/              # 翻译文件
│       │           ├── CN/                 # 中文
│       │           └── EN/                 # 英文
│       │
│       └── sandbox-options.txt             # 沙盒选项
│
└── common/                                # 公共资源
```

### 核心架构

1. **BuildingData** - 定义所有建筑类型的材料需求、建造配方、外观属性
2. **BuildingObjects** - 继承 ISBuildingObjectNew，实现具体建造逻辑
3. **客户端** - 提供建筑菜单、UI 交互、建造操作
4. **共享模块** - 提供方向设置、物品附加、建造属性配置等工具函数

---

## 移动和旋转机制

### 1. 方向控制

**手动/自动旋转模式** - 使用旋转按钮（TurnDirButton）切换：

```lua
-- BuildingCraftUI.lua:410
function BuildingCraftUI:onTurnDirButtonClick()
    local modData = self.character:getModData();
    if modData.IsAutoTurnDir == 1 then
        modData.IsAutoTurnDir = 0  -- 手动模式
    else
        modData.IsAutoTurnDir = 1  -- 自动模式
    end
end
```

**自动旋转逻辑** (`ISBuildingObjectNew.lua:77-93`)：

```lua
if modData.IsAutoTurnDir == 1 then
    -- 自动尝试4个方向，找第一个可建造的方向
    for ii = 1, 4 do
        draggingItem.nSprite = ii
        draggingItem:getSprite()
        canBeBuild = draggingItem:isValid(square, draggingItem.north)
        if canBeBuild then
            draggingItem.canBeBuild = true
            break
        end
    end
end
```

**手动设置方向** (`BuildingCraftObject.lua`)：

```lua
function BuildingCraftObject.SetDir(_obj, dir)
    _obj.nSprite = dir
    if dir == 1 then _obj.west = true
    elseif dir == 2 then _obj.north = true
    elseif dir == 3 then _obj.east = true
    elseif dir == 4 then _obj.south = true
    end
end
```

### 2. 移动（建造位置）

移动是通过**鼠标位置**自动跟踪的。

**UI 获取鼠标坐标** (`BuildingCraftUI.lua`)：

```lua
function BuildingCraftUI:getCoordsByMouse()
    local x = getMouseXScaled()
    local y = getMouseYScaled()
    local z = getPlayer():getZ()
    local wx, wy = ISCoordConversion.ToWorld(x, y, z)
    return math.floor(wx), math.floor(wy), z
end
```

**建造位置计算** (`ISBuildingObjectNew.lua`)：

```lua
local x1 = math.min(self.startPos.x, self.endPos.x)
local x2 = math.max(self.startPos.x, self.endPos.x)
local y1 = math.min(self.startPos.y, self.endPos.y)
local y2 = math.max(self.startPos.y, self.endPos.y)
```

### 3. 方向值含义

| nSprite | 方向 | 属性 |
|---------|------|------|
| 1 | 西 (West) | `west = true` |
| 2 | 北 (North) | `north = true` |
| 3 | 东 (East) | `east = true` |
| 4 | 南 (South) | `south = true` |

### 4. 键盘控制

- `KEY_LEFT` / `KEY_RIGHT` - 切换分类面板
- `KEY_UP` / `KEY_DOWN` - 选择建筑类型
- `KEY_ESCAPE` - 关闭建筑菜单

### 5. 手柄控制

手柄控制通过 `DoTileBuildingJoyPad` 函数实现：

```lua
-- ISBuildingObjectNew.lua:114
function DoTileBuildingJoyPad(draggingItem, isRender, x, y, z)
    -- 首次按下时记录初始位置
    if draggingItem.xJoypad == -1 then
        draggingItem.xJoypad = x;
        draggingItem.yJoypad = y;
    end
    draggingItem.zJoypad = z;
    -- 使用记录的 JoyPad 位置进行建造
    local square = getCell():getGridSquare(draggingItem.xJoypad, draggingItem.yJoypad, draggingItem.zJoypad);
    DoTileBuilding(draggingItem, isRender, draggingItem.xJoypad, draggingItem.yJoypad, draggingItem.zJoypad, square);
end
```

**手柄按钮提示** (代码中注释)：
- LB/RB 按钮 - 切换方向

### 6. UI 按钮

- **TurnDirButton** (旋转按钮) - 切换手动/自动旋转模式
- **GearButton** - 设置 UI 透明度
- **PipetteButton** - 吸管工具，快速搜索已有 Tile
