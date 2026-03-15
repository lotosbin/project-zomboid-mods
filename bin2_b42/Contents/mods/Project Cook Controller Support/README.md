# Project Cook Controller Support

> 为 Project Cook 添加手柄控制支持的 Patch Mod

## 简介

本 Mod 为 [Project Cook](https://steamcommunity.com/sharedfiles/filedetails/?id=3490188370) 添加完整的手柄控制器支持，让你可以使用游戏手柄操作合成界面。

## 前置要求

- **Project Cook** (必须安装) - Steam Workshop ID: 3490188370
- **NeatUI Framework** (由 Project Cook 依赖)
- **Project Zomboid B42** 版本


### 2. Steam Workshop 订阅

将本 Mod 发布到 Steam Workshop 后直接订阅即可。

## 使用说明

### 🎮 手柄控制按键

| 按键 | 功能 | 说明 |
|------|------|------|
| **方向键 ↑** | 向上导航 | 在配方列表中向上移动 |
| **方向键 ↓** | 向下导航 | 在配方列表中向下移动 |
| **方向键 ←** | 列切换 | 切换到前一列 (调料→食材→基础物品) |
| **方向键 →** | 列切换 | 切换到后一列 (基础物品→食材→调料) |
| **A 键** | 确认/执行 | 选择物品 / 开始合成 |
| **B 键** | 返回/关闭 | 关闭合成界面 / 返回上一级 |
| **X 键** | 筛选切换 | 切换"只显示可制作"选项 |
| **Y 键** | 视图切换 | 切换列表/网格视图 |
| **L1 键** | 分类切换 | 切换到上一个分类 |
| **R1 键** | 分类切换 | 切换到下一个分类 |
| **右摇杆** | 数量调整 | 上: 最大数量 / 下: 最小数量 / 左: -1 / 右: +1 |

### 界面布局

```
+------------------------------------------------------+
| [Icon] Project Cook                           [X]    |  <- 标题栏
+------------------------------------------------------+
|  基础物品列           |  食材列              | 调料列    |
|  [Selected]         |                     |          |
|  Item 1             |  Ingredient 1       | Spice 1  |
|  Item 2             |  Ingredient 2       | Spice 2  |
|  ...                |  ...                | ...      |
+------------------------------------------------------+
```

## 功能特性

- ✅ 完整的手柄导航支持
- ✅ 焦点视觉指示器 (蓝色边框)
- ✅ 配方列表滚动
- ✅ 多列快速切换
- ✅ 合成数量调整
- ✅ 分类筛选
- ✅ 视图模式切换
- ✅ 支持单人和多人游戏

## 文件结构

```
Project Cook Controller Support/
├── 42/
│   ├── mod.info              # Mod 信息配置
│   ├── poster.png            # Mod 封面图片
│   └── media/
│       └── lua/
│           └── client/
│               └── Project_Cook/
│                   ├── Controller_Init.lua           # 初始化脚本
│                   ├── PJCK_Window_Controller.lua    # 窗口控制器支持
│                   └── EvolvedRecipePanel/
│                       └── PJCK_EvoPanel_Controller.lua  # 面板控制器支持
└── README.md                 # 本说明文件
```

## 兼容性

| 游戏版本 | 兼容性 |
|----------|--------|
| B42.13.1+ | 完全支持 |
| B42.0-20  | 可能存在兼容问题 |
| B41.x     | 不支持 |

## 常见问题

**Q: 手柄没有反应怎么办？**
A: 确保在游戏设置中启用了手柄支持，并正确连接了手柄。

**Q: 焦点不在预期位置？**
A: 按下任意方向键激活控制器导航模式。

**Q: 多人游戏其他人可以使用手柄吗？**
A: 可以，每人使用自己的手柄独立控制。

## 更新日志

见 [CHANGELOG.txt](./CHANGELOG.txt)

## 致谢

- **Project Cook** 作者: Rocco
- **NeatUI Framework**
- Project Zomboid 社区

## 许可证

本 Mod 遵循与原 Mod 相同的许可证条款。

---

**作者**: bin^2
**版本**: 1.0.0
**发布日期**: 2026-01-14
