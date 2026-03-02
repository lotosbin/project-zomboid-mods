# 建造物品手柄支持方案

> 基于官方 JavaDocs 和代码分析

---

## 当前状况

### B42 限制

在 B42 版本中，**ISBuildIsoEntity 是纯 Java 类**，没有暴露足够的 Lua API 来实现以下功能：

| 功能 | 状态 | 说明 |
|------|------|------|
| 放置建筑 | ❌ 不可用 | `placeBuilding` API 未暴露 |
| 旋转建筑 | ❌ 不可用 | `rotate()` 方法未暴露 |
| 移动建筑 | ❌ 不可用 | `setSquare()` 方法未暴露 |
| 切换建筑 | ✅ 可用 | 通过 UI 列表选择 |

### 可用的 API

从 JavaDocs 分析，以下 API 可能可用：

```lua
-- 在 buildEntity 上可能可用的 getter
buildEntity:getSquare()      -- 获取位置
buildEntity:getNorth()       -- 获取朝向
buildEntity:getType()        -- 获取类型
buildEntity:getSprite()      -- 获取精灵
buildEntity:getIsValid()     -- 检查有效性

-- IsoObject 上的方法
isoObj:getRotation()         -- 获取旋转 (0-3)
isoObj:setRotation(rot)     -- 设置旋转
```

---

## 解决方案

### 方案 1: 通过按键模拟 (当前采用)

模拟游戏内置的 R/F 键来触发旋转：

```lua
-- 尝试模拟 R 键旋转
local function simulateRotateKey(clockwise)
    -- 模拟按下 R 键 (旋转) 或 F 键 (逆时针)
    local key = clockwise and Keyboard.KEY_R or Keyboard.KEY_F

    -- 方法: 发送按键事件到游戏
    if Keyboard.isKeyDown then
        -- 注意: 这可能不会触发建造系统的旋转
    end
end
```

**优点**: 简单，不需要额外代码
**缺点**: 不稳定，可能与其他模组冲突

---

### 方案 2: Java 扩展 (推荐)

创建 Java 类扩展 ISBuildIsoEntity：

```java
// Java 扩展示例
package mods.neatbuilding;

import iso._build.entity.ISBuildIsoEntity;

public class NEATBuildIsoEntity extends ISBuildIsoEntity {
    // 暴露旋转方法给 Lua
    public void rotate(boolean clockwise) {
        // 调用父类方法或实现自己的逻辑
        this.setNorth(!this.getNorth());
    }

    // 暴露移动方法
    public void moveTo(int x, int y, int z) {
        // 移动建筑到新位置
        IsoCell cell = this.getCell();
        IsoGridSquare newSquare = cell.getGridSquare(x, y, z);
        if (newSquare != null) {
            this.setSquare(newSquare);
        }
    }
}
```

然后在 Lua 中调用：

```lua
local function rotateBuildEntity(self, angle)
    if not self.buildEntity then return false end

    -- 通过 Java 扩展调用
    if self.buildEntity.rotate then
        self.buildEntity:rotate(angle > 0)
        return true
    end

    return false
end
```

**优点**: 完全控制，稳定可靠
**缺点**: 需要编写 Java 代码，需要重新编译模组

---

### 方案 3: 使用服务器命令

通过发送服务器命令来执行建造操作：

```lua
local function sendBuildCommand(command, args)
    -- 发送给服务器
    sendClientCommand("neatbuilding", command, args)
end

-- 服务器端处理 (需要 Java)
Events.OnClientCommand.Add(function(module, command, player, args)
    if module == "neatbuilding" then
        if command == "rotate" then
            -- 执行旋转
        elseif command == "place" then
            -- 执行放置
        elseif command == "move" then
            -- 执行移动
        end
    end
end)
```

**优点**: 适合多人游戏
**缺点**: 需要服务器端支持，单人游戏可能不工作

---

### 方案 4: 直接操作 IsoObject

通过 IsoObject 进行操作：

```lua
local function rotateViaIsoObject(buildEntity)
    if not buildEntity then return false end

    local isoObj = buildEntity:getIsoObject()
    if not isoObj then return false end

    -- 获取当前旋转
    local currentRot = isoObj:getRotation()
    -- 设置新旋转 (0-3, 每次 +1)
    local newRot = (currentRot + 1) % 4
    isoObj:setRotation(newRot)

    -- 同步
    isoObj:transmitModData()

    return true
end

local function moveViaIsoObject(buildEntity, targetSquare)
    if not buildEntity or not targetSquare then return false end

    local isoObj = buildEntity:getIsoObject()
    if not isoObj then return false end

    -- 尝试设置新位置
    -- 注意: setSquare 可能未暴露
    if isoObj.setSquare then
        isoObj:setSquare(targetSquare)
        isoObj:transmitModData()
        return true
    end

    return false
end
```

**优点**: 不需要额外文件
**缺点**: setSquare 可能未暴露给 Lua

---

## 推荐方案

### 短期: 方案 4 + 提示

1. 尝试通过 IsoObject 旋转
2. 如果失败，显示提示让用户使用鼠标 R/F 键

```lua
local function rotateBuildEntity(self, angle)
    if not self.buildEntity then return false end

    -- 尝试方法1: 通过 IsoObject
    local isoObj = self.buildEntity:getIsoObject()
    if isoObj then
        local rot = isoObj:getRotation()
        isoObj:setRotation((rot + 1) % 4)
        isoObj:transmitModData()
        return true
    end

    -- 尝试方法2: 直接在 buildEntity 上
    if self.buildEntity.rotate then
        self.buildEntity:rotate(angle > 0)
        return true
    end

    -- 都失败，提示用户
    getSoundManager():playUISound("UIActivateButton")
    print("[NCS-Build] 旋转: 请使用鼠标 R 键")

    return false
end
```

### 长期: 方案 2 (Java 扩展)

创建完整的 Java 扩展类来支持所有建造操作。

---

## 手柄控制设计

### 当前已实现

| 输入 | 功能 |
|------|------|
| 左摇杆 | 窗口区块移动 |
| 右摇杆 | 尝试旋转建筑 |
| L2/R2 | 精细旋转 |
| A 键 | 确认/开始建造 |
| B 键 | 取消/关闭 |
| X 键 | 切换排序 |
| Y 键 | 切换视图 |
| LB/RB | 切换分类 |
| 方向键 | 导航列表 |

### 建议的完整控制

```lua
-- 完整的手柄控制映射
function NB_BuildingPanel:onJoypadDown(button)
    if button == Joypad.AButton then
        -- 开始建造 / 确认
        self:startBuilding()
    elseif button == Joypad.BButton then
        -- 取消 / 关闭
        self:cancelBuilding()
        self:close()
    elseif button == Joypad.XButton then
        -- 切换排序
        self:toggleSort()
    elseif button == Joypad.YButton then
        -- 切换视图
        self:toggleView()
    elseif button == Joypad.LBumper then
        -- 上一个分类
        self:prevCategory()
    elseif button == Joypad.RBumper then
        -- 下一个分类
        self:nextCategory()
    end
end

function NB_BuildingPanel:onJoypadTick(joypadData)
    -- 左摇杆: 窗口移动
    self:handleWindowMovement(joypadData)

    -- 右摇杆: 旋转建筑
    self:handleBuildingRotation(joypadData)
end
```

---

## 参考资料

- [ISBuildIsoEntity JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/_build/entity/ISBuildIsoEntity.html)
- [ISBuildWorldEntity JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/ui/_is_build_world_entity.html)
- [ISPlaceBuild JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/_build/action/ISPlaceBuild.html)
- Neat_Building 模组源码
