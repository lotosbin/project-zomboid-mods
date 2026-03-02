# Neat_Building 文档

## 概述

Neat_Building 是一个改进原版建造 UI 的模组，提供更清晰、更高效的建造体验。

## 结构

```
Neat_Building/
├── 42/
│   └── media/
│       └── lua/
│           ├── client/                           # 客户端
│           │   └── Neat_Building/
│           │       ├── Base/
│           │       │   ├── NB_OverrideISEntity.lua     # 覆盖 ISEntity
│           │       │   ├── NB_BuildingHeader.Deprecated
│           │       │   └── NB_BuildingWindow.Deprecated
│           │       ├── Cell/
│           │       │   └── NB_CellRecipeList.lua       # 配方列表单元
│           │       ├── Patch/
│           │       │   └── DisableContextMenuWhenDrag.lua
│           │       │
│           │       ├── BuildingRecipeGroups.lua         # 建筑配方分组
│           │       ├── NB_BuildingCategoryPanel.lua     # 分类面板
│           │       ├── NB_BuildingCategorySlot.lua     # 分类槽
│           │       ├── NB_BuildingInfoPanel.lua        # 信息面板
│           │       ├── NB_BuildingInfoDetailPanel.lua   # 详细信息面板
│           │       ├── NB_BuildingInput_Panel.lua      # 输入面板
│           │       ├── NB_BuildingInput_Slot.lua       # 输入槽
│           │       ├── NB_BuildingPanel.lua            # 主建筑面板
│           │       ├── NB_BuildingRecipeList_Box.lua   # 配方列表盒
│           │       ├── NB_BuildingRecipeList_Grid.lua  # 配方网格
│           │       ├── NB_BuildingRecipeList_Panel.lua # 配方面板
│           │       ├── NB_FilterBar.lua                # 过滤栏
│           │       └── NB_LevelRecipePanel.lua         # 等级配方面板
│           │
│           ├── server/                             # 服务器端
│           │   ├── BuildRecipeCode/
│           │   │   └── NB_BuildRecipeCode.lua     # 建造配方代码
│           │   └── BuildingObjects/
│           │       └── ISBuildEntityExtended.lua   # 扩展建筑实体
│           │
│           └── shared/                             # 共享
│               └── Translate/                      # 翻译文件
│                   ├── CN/   # 中文
│                   ├── EN/   # 英文
│                   └── ...   # 其他语言
│
└── common/                                       # 公共资源
```

## 核心功能

### UI 组件

1. **NB_BuildingPanel** - 主建筑面板，替代原版建造菜单
2. **NB_BuildingCategoryPanel** - 分类面板，显示建筑类别
3. **NB_BuildingRecipeList_Panel** - 配方列表面板
4. **NB_BuildingInput_Panel** - 材料输入面板
5. **NB_BuildingInfoPanel** - 建筑信息显示
6. **NB_FilterBar** - 搜索过滤栏

### 核心类

- **NB_BuildRecipeCode** - 处理建造配方的核心逻辑
- **ISBuildEntityExtended** - 扩展的建筑实体类
- **BuildingRecipeGroups** - 建筑配方分组管理

## 与 BuildingCraft 的关系

Neat_Building 提供了改进的 UI 层，而 BuildingCraft 提供了扩展的建筑功能。两者可以配合使用：
- BuildingCraft: 扩展的建筑类型（更多家具、装饰等）
- Neat_Building: 改进的建造界面体验

## 键盘/手柄控制

**注意**: Neat_Building 是一个 UI 改进模组，**不直接处理**建造位置和方向的控制。这些功能由以下模块处理：

### 建造位置控制

由 **BuildingCraft** 的 `DoTileBuilding` 函数处理：
- 鼠标移动自动跟踪建造位置
- 手柄通过 `DoTileBuildingJoyPad` 函数处理

### 方向控制

由 **BuildingCraft** 的 `ISBuildingObjectNew.lua` 处理：

1. **自动旋转模式** - 自动尝试 4 个方向，找第一个可建造的方向
2. **手动旋转模式** - 使用旋转按钮切换
3. **键盘 R 键** - 在建造时按 R 键旋转（见 BuildingCraft 翻译文件）

### ISBuildEntityExtended 功能

虽然不处理输入控制，但 Neat_Building 提供了 `renderEntityEdges` 函数来渲染建筑边框：

```lua
-- 根据方向渲染边缘
local function renderEntityEdges(self, x, y, z, square, directions)
    -- directions.north / directions.west / directions.south / directions.east
end
```

该函数用于显示建筑占地的边缘提示，帮助玩家确认建造位置。
