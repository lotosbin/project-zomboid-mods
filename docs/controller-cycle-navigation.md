# 手柄循环导航功能说明

## 🎮 概述

NC_CategoryList_Panel 现在支持在分类(category)和槽位(slot)之间的循环导航，提供无缝的手柄操作体验。

## 🔄 循环导航逻辑

### 水平循环 (LB/RB 按钮)
```
分类1 → 分类2 → 分类3 → ... → 分类1
   ↓         ↓         ↓         ↓
  Slot1    Slot1    Slot1     Slot1
  Slot2    Slot2    Slot2     Slot2
   ...       ...       ...       ...
```

### 导航行为

#### **按 LB (上一个)**
- **当前在分类上**: 移动到上一个分类
  - 如果已经是第一个分类 → 移动到当前分类的最后一个slot
- **当前在slot上**: 移动到上一个slot
  - 如果已经是第一个slot → 移动到上一个分类

#### **按 RB (下一个)**
- **当前在分类上**: 移动到下一个分类
- **当前在slot上**: 移动到下一个slot
  - 如果已经是最后一个slot → 移动到下一个分类

#### **按 ↑ (上方向键)**
- 在slot之间向上移动
- 如果在第一个slot → 移动到最后一个slot

#### **按 ↓ (下方向键)**
- 在slot之间向下移动
- 如果在最后一个slot → 移动到第一个slot

#### **按 A (确认)**
- **在分类上**: 选择该分类
- **在slot上**: 激活该slot的功能

## 🎯 焦点管理

### 焦点类型检测
```lua
function getCurrentFocusType()
    -- 返回: "category", "slot", "other", "none"
end
```

### 智能焦点切换
- **分类切换**: 自动将焦点设置到新选中的分类项
- **Slot导航**: 在当前分类的slot之间循环
- **边界处理**: 在边界处智能切换到分类

## 🛠️ 实现细节

### 核心方法

#### `selectNextInCycle()`
主要的下一个选择逻辑，处理分类和slot之间的循环

#### `selectPreviousInCycle()`
主要的上一个选择逻辑，处理分类和slot之间的循环

#### `isCategoryItem(element)`
检查元素是否为分类项

#### `isSlot(element)`
检查元素是否为slot

#### `getCurrentSlotIndex()`
获取当前焦点slot的索引

#### `getSlotCount()`
获取当前分类下的slot总数

### 焦点设置
```lua
-- 聚焦到分类
setJoypadFocus(playerNum, categoryItem)

-- 聚焦到slot
setJoypadFocus(playerNum, slotItem)
```

## 🎨 用户体验

### 流畅的导航
- **无缝循环**: 在分类和slot之间无缝切换
- **智能边界**: 在边界处自动切换到合适的元素
- **直观操作**: LB/RB负责主要循环，方向键负责微调

### 状态保持
- **分类状态**: 切换分类时保持选择状态
- **焦点记忆**: 记住用户在分类内的导航位置
- **视觉反馈**: 清晰的焦点指示

## 🔧 扩展功能

### 可用性检查
```lua
function isCategoryAvailable(categoryValue)
    -- 检查分类是否可用
end
```

### 显示名称获取
```lua
function getCategoryDisplayName(categoryValue)
    -- 获取分类的显示名称
end
```

### 可用分类循环
```lua
function selectNextAvailableCategory()
    -- 跳转到下一个可用分类
end
```

## 🎮 操作指南

| 按钮操作 | 功能描述 | 行为逻辑 |
|---------|---------|---------|
| **LB** | 上一个分类 | 保持原有categoryPanel的分类切换逻辑 |
| **RB** | 下一个分类 | 保持原有categoryPanel的分类切换逻辑 |
| **LT** | 上一个循环 | 在slot之间循环向上选择 |
| **RT** | 下一个循环 | 在slot之间循环向下选择 |
| **↑** | 上一个slot | 在当前分类内向上移动 |
| **↓** | 下一个slot | 在当前分类内向下移动 |
| **A** | 确认选择 | 激活当前焦点元素（分类或slot） |

## 🔄 循环导航逻辑

### 分类导航 (保持原有逻辑)
- **LB/RB**: 完全保持categoryPanel原有的分类切换逻辑
- 不影响现有的分类选择和切换行为

### Slot循环导航 (新增功能)
```
Slot1 ← Slot2 ← Slot3 ← ... ← Slot1
  ↓        ↓        ↓         ↓
Slot1 → Slot2 → Slot3 → ... → Slot1
```

### 导航行为

#### **按 LT (上一个循环)**
- **当前在slot上**: 移动到上一个slot
- **当前不在slot上**: 移动到最后一个slot

#### **按 RT (下一个循环)**
- **当前在slot上**: 移动到下一个slot
- **当前不在slot上**: 移动到第一个slot

#### **按 ↑/↓ (垂直导航)**
- **专门用于slot导航**: 在slot之间上下移动
- **不影响categoryPanel**: 不干扰分类面板的逻辑

## 🚀 性能优化

- **索引缓存**: 缓存当前索引避免重复计算
- **智能检测**: 只在必要时进行元素类型检测
- **延迟加载**: 按需计算slot信息

这个循环导航系统为用户提供了直观、高效的手柄操作体验，让分类和slot的导航变得自然流畅。