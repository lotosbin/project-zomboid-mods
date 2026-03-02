# Project Zomboid Cell 和 Building API 文档

> 基于官方 Wiki 和代码分析

---

## 核心 API 概览

```lua
-- 获取 Cell
getCell()                    -- 返回当前世界的 IsoCell
getWorld():getCell()         -- 同样获取 Cell

-- 获取/创建 GridSquare
cell:getGridSquare(x, y, z)  -- 获取指定坐标的 GridSquare
cell:getOrCreateGridSquare(x, y, z)  -- 获取或创建

-- 获取相邻 Cell
cell:getNeighbor(x, y, z)    -- 获取相邻 Cell
```

---

## Cell API

### 基础方法

| 方法 | 说明 |
|------|------|
| `getCell()` | 获取当前世界的 Cell |
| `getGridSquare(x, y, z)` | 获取 GridSquare (坐标可以是任意值，会自动计算) |
| `getOrCreateGridSquare(x, y, z)` | 获取或创建 GridSquare |
| `getNeighbor(x, y, z)` | 获取相邻 Cell |
| `getWorld()` | 获取所属 World |
| `getMinX()`, `getMaxX()` | 获取 Cell X 范围 |
| `getMinY()`, `getMaxY()` | 获取 Cell Y 范围 |

### 示例

```lua
-- 获取当前世界的 Cell
local cell = getCell()
local world = getWorld()

-- 获取 GridSquare
local square = cell:getGridSquare(100, 200, 0)

-- 检查坐标是否有效
if square then
    print("找到 GridSquare: " .. square:getX() .. ", " .. square:getY())
end

-- 移动到相邻 Cell
local neighborCell = cell:getNeighbor(1, 0, 0)  -- 东边
```

---

## GridSquare API

### 基础属性

| 方法 | 说明 |
|------|------|
| `getX()`, `getY()`, `getZ()` | 获取坐标 |
| `getWorldX()`, `getWorldY()` | 获取世界坐标 |
| `getFloor()` | 获取地面对象 |
| `getStaticMovingObject()` | 获取静态移动对象 |
| `getRoom()` | 获取房间 |
| `getBuilding()` | 获取建筑 |

### 对象管理

| 方法 | 说明 |
|------|------|
| `getObjects()` | 获取所有对象 (IsoObject[]) |
| `getWorldObjects()` | 获取世界对象列表 |
| `addWorldObject(obj)` | 添加世界对象 |
| `transmitRemoveItemFromSquare(obj)` | 移除对象 |

### 示例

```lua
local cell = getCell()
local sq = cell:getGridSquare(100, 200, 0)

if sq then
    -- 获取坐标
    local x = sq:getX()
    local y = sq:getY()
    local z = sq:getZ()

    -- 获取地面
    local floor = sq:getFloor()

    -- 获取所有对象
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        print("对象: " .. obj:getType())
    end

    -- 获取房间
    local room = sq:getRoom()

    -- 获取建筑
    local building = sq:getBuilding()
end
```

---

## Building API

### 基础方法

| 方法 | 说明 |
|------|------|
| `getDef()` | 获取 BuildingDef |
| `getName()` | 获取建筑名称 |
| `getRoom()` | 获取主房间 |
| `getRooms()` | 获取所有房间 |
| `getWindows()` | 获取窗户列表 |
| `getExits()` | 获取出口列表 |
| `AddRoom(room)` | 添加房间 |
| `CalculateWindows()` | 计算窗户 |
| `CalculateExits()` | 计算出口 |

### BuildingDef

| 方法 | 说明 |
|------|------|
| `getName()` | 获取定义名称 |
| `getID()` | 获取建筑 ID |
| `getStyle()` | 获取建筑风格 |

### 示例

```lua
local cell = getCell()
local sq = cell:getGridSquare(100, 200, 0)

if sq then
    local building = sq:getBuilding()
    if building then
        local def = building:getDef()
        print("建筑名称: " .. building:getName())
        print("建筑定义: " .. def:getName())

        -- 获取所有房间
        local rooms = building:getRooms()
        for i = 0, rooms:size() - 1 do
            local room = rooms:get(i)
            print("房间: " .. room:getName())
        end
    end
end
```

---

## IsoObject API

### 基础方法

| 方法 | 说明 |
|------|------|
| `getSquare()` | 所在 GridSquare |
| `getSprite()` | 获取精灵 |
| `getType()` | 获取类型 |
| `getModData()` | 获取模组数据 |
| `getObjectIndex()` | 获取对象索引 |
| `isVisible()` | 是否可见 |
| `isCollide()` | 是否碰撞 |

### 位置和旋转

| 方法 | 说明 |
|------|------|
| `getX()`, `getY()`, `getZ()` | 获取坐标 |
| `getRotation()` | 获取旋转 (0-3) |
| `setRotation(rot)` | 设置旋转 |
| `getScale()` | 获取缩放 |
| `setScale(scale)` | 设置缩放 |

### 对象操作

| 方法 | 说明 |
|------|------|
| `removeFromWorld()` | 从世界移除 |
| `addToWorld()` | 添加到世界 |
| `transmitModData()` | 同步模组数据 |
| `setHighlighted(highlight)` | 设置高亮 |

### 示例

```lua
local cell = getCell()
local sq = cell:getGridSquare(100, 200, 0)

if sq then
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)

        -- 获取基本信息
        local square = obj:getSquare()
        local sprite = obj:getSprite()
        local objType = obj:getType()

        print("类型: " .. objType)
        print("坐标: " .. obj:getX() .. ", " .. obj:getY() .. ", " .. obj:getZ())

        -- 获取旋转
        local rotation = obj:getRotation()
        print("旋转: " .. rotation)

        -- 模组数据
        local modData = obj:getModData()
    end
end
```

---

## 世界和坐标系统

### 坐标层级

```
World (世界)
  └── Cell (单元格) - 300x300 方块
        └── GridSquare (网格方块) - 1x1
              └── IsoObject (游戏对象)
```

### 坐标转换

```lua
-- 屏幕坐标转世界坐标
local wx, wy = ISCoordConversion.ToWorld(screenX, screenY, z)

-- 世界坐标转网格坐标
local gridX = math.floor(wx)
local gridY = math.floor(wy)

-- 示例
local mouseX = getMouseXScaled()
local mouseY = getMouseYScaled()
local playerZ = getPlayer():getZ()
local wx, wy = ISCoordConversion.ToWorld(mouseX, mouseY, playerZ)
local sq = getCell():getGridSquare(math.floor(wx), math.floor(wy), playerZ)
```

---

## 建造相关操作

### 放置建筑

```lua
-- 获取建造位置
local cell = getCell()
local sq = cell:getGridSquare(x, y, z)

-- 创建建筑对象 (需要模组特定实现)
local building = ISBuildingObject:new(sprite, x, y, z)
building:setRotation(rotation)
building:addToWorld()
```

### 移动建筑

```lua
-- 移动建筑到新位置
local function moveObjectToSquare(obj, targetSquare)
    if not obj or not targetSquare then return false end

    -- 从旧位置移除
    obj:removeFromWorld()

    -- 设置新位置 (某些对象需要)
    obj:setSquare(targetSquare)

    -- 添加到新位置
    obj:addToWorld()

    return true
end
```

### 旋转建筑

```lua
-- 旋转建筑
local function rotateObject(obj)
    if not obj then return end

    local currentRot = obj:getRotation()
    local newRot = (currentRot + 1) % 4  -- 0-3 循环
    obj:setRotation(newRot)

    -- 同步到服务器
    obj:transmitModData()
end
```

---

## 完整示例：查找相邻 Cell

```lua
-- 获取当前 Cell 边界上的建筑并移动到相邻 Cell
local function moveToNeighborCell(object, direction)
    local cell = getCell()
    local sq = object:getSquare()
    if not sq then return false end

    local x = sq:getX()
    local y = sq:getY()
    local z = sq:getZ()

    local cellSize = 300  -- Cell 大小

    -- 计算相邻坐标
    local newX, newY
    if direction == "east" then
        newX = x + cellSize
        newY = y
    elseif direction == "west" then
        newX = x - cellSize
        newY = y
    elseif direction == "south" then
        newX = x
        newY = y + cellSize
    elseif direction == "north" then
        newX = x
        newY = y - cellSize
    end

    -- 获取新位置的 GridSquare
    local newSq = cell:getGridSquare(newX, newY, z)
    if not newSq then
        print("目标位置无效")
        return false
    end

    -- 移动对象
    object:removeFromWorld()
    object:setSquare(newSq)
    object:addToWorld()

    return true
end
```

---

## ISBuildIsoEntity API

> 建造实体 - 用于放置建筑物

### 来源
- [官方 Lua API (pzwiki)](https://pzwiki.net/wiki/Lua_(API)#ISBuildIsoEntity)
- [B42 非官方 JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/_build/entity/ISBuildIsoEntity.html)

### 继承关系

```
IsoObject
  └── IsoBuildGC
        └── ISBuildIsoEntity
```

### 基础方法

| 方法 | 说明 |
|------|------|
| `getSquare()` | 获取所在 GridSquare |
| `getIsoObject()` | 获取关联的 IsoObject |
| `getIsValid()` | 检查是否有效 |
| `getIsRoad()` | 是否道路 |
| `getNorth()` | 检查是否朝北 (true=北, false=南) |
| `getType()` | 获取建筑类型 |
| `getSprite()` | 获取精灵对象 |
| `isPlayerNearby()` | 玩家是否在附近 |

### 坐标相关

| 方法 | 说明 |
|------|------|
| `getX()`, `getY()`, `getZ()` | 获取坐标 |
| `getW()`, `getH()` | 获取宽度和高度 |

### 属性相关

| 方法 | 说明 |
|------|------|
| `getType()`, `setType(type)` | 获取/设置类型 |
| `getSprite()`, `setSprite(sprite)` | 获取/设置精灵 |
| `getColor()`, `getAlpha()` | 获取颜色和透明度 |
| `isCollide()`, `setCollide(bool)` | 碰撞相关 |
| `isVisible()` | 是否可见 |
| `isThumpable()` | 是否可敲击 |
| `isSpecialTile()` | 是否特殊瓦片 |
| `isRenderFloor()` | 是否渲染地板 |
| `isRenderDepth()` | 是否渲染深度 |

### 建造相关

| 方法 | 说明 |
|------|------|
| `getCurrentBuildIndex()` | 获取当前建造索引 |
| `getProperties()` | 获取属性 |
| `getModData()` | 获取模组数据 |

### 示例

```lua
-- 在建造界面中获取 buildEntity
function onBuildMode(self)
    if self.buildEntity then
        -- 获取位置
        local square = self.buildEntity:getSquare()
        if square then
            print("建造位置: " .. square:getX() .. ", " .. square:getY())
        end

        -- 检查朝向
        local isNorth = self.buildEntity:getNorth()
        print("朝北: " .. tostring(isNorth))

        -- 获取类型
        local buildType = self.buildEntity:getType()
        print("建造类型: " .. buildType)

        -- 检查有效性
        local isValid = self.buildEntity:getIsValid()
        print("有效: " .. tostring(isValid))

        -- 是否道路
        local isRoad = self.buildEntity:getIsRoad()
        print("道路: " .. tostring(isRoad))

        -- 玩家是否在附近
        local nearby = self.buildEntity:isPlayerNearby()
        print("玩家在附近: " .. tostring(nearby))

        -- 坐标
        local x = self.buildEntity:getX()
        local y = self.buildEntity:getY()
        local z = self.buildEntity:getZ()
        print("坐标: " .. x .. ", " .. y .. ", " .. z)
    end
end
```

### B42 限制说明

**重要**: 在 B42 版本中，`ISBuildIsoEntity` 是纯 Java 类，部分方法可能没有暴露给 Lua：

- ✅ 可用: `getSquare()`, `getIsoObject()`, `getIsValid()`, `getIsRoad()`, `getNorth()`, `getType()`, `getSprite()`, `isPlayerNearby()`, `getX()`, `getY()`, `getZ()`
- ⚠️ 可能受限: `setSprite()`, `setType()` 等 setter 方法
- ❌ 可能不可用: 直接修改位置的方法如 `setSquare()`, `moveTo()` 等

如果需要旋转或移动建筑，可以尝试：

```lua
-- 旋转建筑 (如果可用)
local function rotateBuilding(buildEntity)
    if not buildEntity then return false end

    -- 方法1: 尝试切换朝向
    local currentNorth = buildEntity:getNorth()
    buildEntity:setNorth(not currentNorth)

    -- 方法2: 尝试通过 IsoObject 旋转
    local isoObj = buildEntity:getIsoObject()
    if isoObj then
        local rot = isoObj:getRotation()
        isoObj:setRotation((rot + 1) % 4)
    end

    return true
end

-- 移动建筑 (如果可用)
local function moveBuilding(buildEntity, targetSquare)
    if not buildEntity or not targetSquare then return false end

    -- 注意: setSquare 可能未暴露给 Lua
    local isoObj = buildEntity:getIsoObject()
    if isoObj and isoObj.setSquare then
        isoObj:setSquare(targetSquare)
        return true
    end

    return false
end
```

---

## 参考资料

- [pzwiki.net - Lua API](https://pzwiki.net/wiki/Lua_(API))
- [projectzomboid.com - Lua API](https://projectzomboid.com/modding/wiki/Lua_API)
- Neat_Building 模组源码
- BuildingCraft 模组源码
