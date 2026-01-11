# NeatControllerSupport B42 开发总结

> Project Zomboid 手柄控制模组开发笔记

## 背景

`NeatControllerSupport` 是一个为 Neat Crafting 和 Neat Building 模组添加手柄控制支持的扩展模组。本次开发主要解决 B42 版本中的兼容性问题。

## 问题描述

在 B42 版本中，建造模式出现以下错误：

```
Object tried to call nil in placeBuilding
Object tried to call nil in rotateBuilding
Object tried to call nil in moveBuilding
```

## 根本原因

经过详细调查和 API 研究，发现：

**B42 中 ISBuildIsoEntity 是纯 Java 类，没有暴露 Lua API**

这意味着以下功能无法通过 Lua 实现：
- 放置建筑 (`placeBuilding`)
- 旋转建筑 (`rotateBuilding`)
- 移动建筑 (`moveBuilding`)

## API 研究过程

### 1. 代码调试

在 `Neat_Building_patch.lua` 中添加了调试函数 `debugBuildEntity`：

```lua
local function debugBuildEntity(entity)
    if not entity then return end
    print("=== ISBuildIsoEntity API ===")

    -- 列出所有 Lua 方法
    local methods = {}
    for k, v in pairs(entity) do
        if type(v) == "function" then table.insert(methods, k) end
    end
    print("Lua methods: " .. #methods)
    -- 结果：Lua methods: 0
end
```

### 2. PZwiki 搜索确认

- `ISBuildIsoEntity` - 无页面
- `ISBuildMenu` - 无页面
- `Category:Lua_objects` - 只有 9 个 Lua 对象，无建造相关

### 3. 官方文档说明

根据 PZwiki [Lua (API)](https://pzwiki.net/wiki/Lua_(API)) 文档：

> "Not all the Java classes and methods are exposed to the Lua API. In the JavaDocs, there is no indication of which classes are exposed but for the classes that are exposed, it shows only the methods that are exposed."

## 解决方案

### 代码简化

移除了无法工作的函数，简化了手柄控制逻辑：

```lua
-- 建造模式控制
local function placeBuilding(self)
    print("[NCS-Build] placeBuilding: B42 API not available for Lua")
    print("[NCS-Build] 请使用鼠标放置建筑，或按 B 取消")
    return false
end
```

### 可用功能

| 按键 | 功能 | 状态 |
|------|------|------|
| 方向键 | 配方列表导航 | ✅ 可工作 |
| A | 开始建造 | ✅ 可工作 |
| B | 关闭界面/取消建造 | ✅ 可工作 |
| X | 切换排序方式 | ✅ 可工作 |
| Y | 切换列表/网格视图 | ✅ 可工作 |
| L1/R1 | 循环切换分类 | ✅ 可工作 |

## 后续解决方案

要实现完整的手柄建造控制，需要：

1. **Neat_Building 模组更新**：在 Java 端添加手柄支持
2. **等待官方更新**：PZ 在后续 B42 版本中暴露相关 Lua API

## 版本更新

- **版本 1.3**
  - 修复 nil 错误
  - 移除无法实现的功能
  - 添加 B42 API 限制说明
  - 更新模组描述

## 参考资料

- [Lua (API) - PZwiki](https://pzwiki.net/wiki/Lua_(API))
- [Category:Lua objects - PZwiki](https://pzwiki.net/wiki/Category:Lua_objects)
- [Project Zomboid Modding Guide - GitHub](https://github.com/AuthenticPeach/Zomboid-Modding-Guide)

---

*最后更新：2026-01-11*
