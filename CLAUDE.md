# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 仓库概述

这是一个 Project Zomboid 模组开发工作坊，包含多个独立的模组和模组包。该仓库作为各种基于 Lua 的模组的集中位置，专为游戏 Build 42 版本设计（主要是 42.12/42.13 版本）。

## 目录结构

**主要模组集合：**
- **bin2/**: 当前 B41 版本的独立模组和模组包集合
- **bin2_b42/**: 旧版 B42 版本兼容包
- **learn/**: 开发/学习区域，包含 UI 框架和制作系统模组
- **eat_whole_stack-main/**: 用于一次性食用整堆食物的独立 QoL 模组

**模组结构模式：**
每个模组遵循标准的 Zomboid 模组结构：
```
<mod_name>/
├── Contents/
│   └── mods/
│       └── <mod_id>/
│           ├── mod.info (必需的元数据)
│           ├── poster.png (模组预览)
│           ├── media/
│           │   ├── lua/ (客户端/服务器/共享脚本)
│           │   └── ui/ (纹理, 资源)
│           └── workshop.txt (Steam Workshop 元数据)
```

## 关键开发概念

**模组依赖：**
- 模组在 mod.info 中使用 `require=` 声明依赖
- 框架模组如 `NeatUI_Framework` 提供基础功能
- 模组包使用 `require=` 将多个模组打包在一起

**版本管理：**
- 每个模组指定 `versionMin=` 以确保兼容性
- 主要专注于 Build 42（42.12/42.13）
- 需要时为不同游戏版本使用单独的目录

**Lua 脚本模式：**
- 客户端：UI、玩家交互、视觉效果
- 服务器端：游戏逻辑、数据管理
- 共享：通用工具、翻译系统
- 翻译文件位于 `media/lua/shared/Translate/<LANG>/`

## 常见开发任务

**添加新模组：**
1. 在适当的集合下创建标准目录结构
2. 创建包含所需元数据的 `mod.info`
3. 将 Lua 脚本添加到 `media/lua/`，遵循客户端/服务器/共享的分离
4. 在 `workshop.txt` 中添加 Steam Workshop 元数据
5. 包含预览图像（poster.png、preview.png）

**本地化支持：**
在 `media/lua/shared/Translate/<LANG>/<FILENAME>_<LANG>.txt` 中添加翻译文件
支持的语言包括：CN、EN、DE、ES、FR、HU、IT、JP、KO、NL、PL、PT、PTBR、RU、TH、TR、UA、CH、DA

**测试模组：**
在 Project Zomboid 游戏环境中通过主菜单启用模组进行测试。无需构建过程 - Lua 脚本在运行时直接加载。

## 仓库管理

**清理脚本：** 运行 `./clean.sh` 删除开发工件（.DS_Store、.vscode 目录）

**Git 工作流：**
- 主分支包含稳定的模组
- 各个模组可以单独维护
- 模组包引用特定版本/依赖

## Steam Workshop 集成

每个模组/模组包包含 `workshop.txt`，其中包含：
- Workshop ID
- 版本号
- 标题和描述
- 用于可发现性的标签
- 公开可见性设置

## 框架依赖

**NeatUI_Framework：** 为制作/建造模组提供基础 UI 组件和工具
- 9-patch 渲染系统
- 滚动视图和虚拟列表
- UI 原语（按钮、面板、进度条）
- 文本渲染工具

**翻译系统：** 集中在共享 Lua 文件中，为所有模组提供多语言支持。