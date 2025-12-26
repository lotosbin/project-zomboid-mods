# Workshop.txt 配置指南

本文档介绍 Project Zomboid 模组的 `workshop.txt` 文件格式和配置方法，用于 Steam Workshop 发布。

## 目录

- [文件概述](#文件概述)
- [字段说明](#字段说明)
- [完整示例](#完整示例)
- [最佳实践](#最佳实践)
- [官方资源](#官方资源)

---

## 文件概述

`workshop.txt` 是 Project Zomboid 模组用于 Steam Workshop 发布的元数据文件，位于模组根目录下。

**文件位置：**
```
Contents/mods/<Mod_ID>/workshop.txt
```

**文件格式：**
- 纯文本文件
- 使用 `键=值` 格式
- 每行一个配置项
- 不支持注释（以 `#` 开头的行会被忽略）

---

## 字段说明

### 必需字段

#### `version`
模组版本号，用于 Steam Workshop 的版本管理。

**格式：** 数字或字符串（如 `1`、`1.0.0`、`2025-12-26`）

**示例：**
```ini
version=1
```

#### `id`
Steam Workshop 模组 ID，在首次上传后由 Steam 自动生成。

**格式：** 数字

**示例：**
```ini
id=3628652563
```

**注意：** 首次上传前可以留空或使用占位符，上传后 Steam 会分配真实 ID。

#### `title`
模组在 Steam Workshop 上显示的标题。

**格式：** 字符串，支持多语言

**示例：**
```ini
title=bin2's B42 mods
```

#### `description`
模组描述，支持 Markdown 格式（部分功能）。

**格式：** 多行文本

**示例：**
```ini
description=bin2 的 Project Zomboid Build 42 模组包集合。
包含多个实用模组的中文化补丁和手柄支持功能，
为中文玩家提供更好的游戏体验。
```

**多行描述技巧：**
```ini
description=第一行描述
description=第二行描述
description=第三行描述
```

#### `tags`
模组标签，用于 Workshop 搜索和分类。

**格式：** 逗号分隔的标签列表

**示例：**
```ini
tags=Build 42,中文,手柄支持,UI
```

**常用标签：**
- `Build 41` / `Build 42` - 游戏版本
- `UI` - 界面相关
- `Gameplay` - 游戏玩法
- `Map` - 地图
- `Translation` - 翻译
- `Controller` - 手柄支持
- `QoL` - 生活质量改进

#### `visibility`
模组可见性设置。

**可选值：**
- `public` - 公开，所有人可见
- `friends` - 仅好友可见
- `private` - 私有，仅自己可见

**示例：**
```ini
visibility=public
```

---

### 可选字段

#### `changelog`
更新日志，记录模组的版本更新历史。

**格式：** 多行文本

**示例：**
```ini
changelog=版本 1.0.0 (2025-12-26)
- 初始发布
- 添加中文化补丁
- 添加手柄支持功能

版本 0.9.0 (2025-12-20)
- 测试版本
- 基础功能实现
```

#### `preview_image`
预览图片文件名（相对于模组根目录）。

**格式：** 文件名

**示例：**
```ini
preview_image=poster.png
```

**注意：** 如果未指定，Steam 会使用 `poster.png` 或 `preview.png`。

#### `author`
作者名称。

**格式：** 字符串

**示例：**
```ini
author=bin2
```

---

## 完整示例

### 基础模组示例

```ini
version=1
id=3628652563
title=Lingering Voices CN
description=将 Lingering Voices 模组的所有僵尸台词翻译为中文。
包括扑击、踉跄、假死、敲门和攻击时的台词，
让中文玩家获得更好的游戏体验。
tags=Build 42,Translation,中文,翻译
visibility=public
```

### 模组包示例

```ini
version=1
id=3628652563
title=bin2's B42 mods
description=bin2 的 Project Zomboid Build 42 模组包集合。
包含多个实用模组的中文化补丁和手柄支持功能，
为中文玩家提供更好的游戏体验。

包含模组：
- bin2_B42_13_1_Collection - bin2的B42.13.1合集
- Neat_Controller_Support - Neat Crafting & Building 手柄支持
- Lingering Voices CN - Lingering Voices 中文化补丁

tags=Build 42,中文,手柄支持,合集
visibility=public

changelog=版本 1.0.0 (2025-12-26)
- 初始发布
- 添加 Lingering Voices CN 中文化补丁
- 添加 Neat_Controller_Support 手柄支持
- 添加 bin2_B42_13_1 模组合集
```

### 带更新日志的示例

```ini
version=2
id=3628652563
title=My Awesome Mod
description=这是一个很棒的模组，提供了很多新功能。
tags=Build 42,Gameplay,QoL
visibility=public

changelog=版本 2.0.0 (2025-12-26)
- 添加新功能 A
- 修复 bug B
- 优化性能 C

版本 1.1.0 (2025-12-20)
- 添加新功能 D
- 改进用户体验

版本 1.0.0 (2025-12-15)
- 初始发布
```

---

## 最佳实践

### 1. 版本管理

- 使用语义化版本号（如 `1.0.0`、`1.2.3`）
- 主版本号：重大更新或不兼容的更改
- 次版本号：新功能，向后兼容
- 修订号：bug 修复和小改进

```ini
version=1.2.3
```

### 2. 描述撰写

- 清晰简洁地说明模组功能
- 列出主要特性和亮点
- 提供安装和使用说明
- 说明依赖关系

```ini
description=模组功能概述

主要特性：
- 特性 1
- 特性 2
- 特性 3

使用说明：
1. 启用模组
2. 开始游戏

依赖：需要原模组
```

### 3. 标签使用

- 使用 3-5 个相关标签
- 包含游戏版本标签（`Build 41` / `Build 42`）
- 使用英文标签以获得更好的搜索结果

```ini
tags=Build 42,Translation,UI,QoL
```

### 4. 更新日志

- 每次更新都添加 changelog 条目
- 按时间倒序排列（最新的在最前面）
- 使用清晰的版本号和日期

```ini
changelog=版本 2.0.0 (2025-12-26)
- 最新更新内容

版本 1.0.0 (2025-12-15)
- 初始发布
```

### 5. 预览图片

- 使用高质量的预览图片
- 图片尺寸建议：512x512 或更大
- 展示模组的主要功能和界面

```ini
preview_image=poster.png
```

### 6. 可见性设置

- 开发阶段使用 `private` 或 `friends`
- 测试完成后改为 `public`
- 确保在公开前充分测试

```ini
visibility=public
```

---

## 上传流程

### 使用游戏内工具上传

1. 打开 Project Zomboid 游戏
2. 进入主菜单
3. 选择 "Steam Workshop"
4. 选择 "Upload" 或 "Update"
5. 选择要上传的模组
6. 确认信息并上传

### 使用命令行工具（如果可用）

某些第三方工具支持命令行上传，具体方法请参考相关文档。

---

## 注意事项

1. **ID 管理**：首次上传后，Steam 会分配 ID，请将其保存到 workshop.txt
2. **版本同步**：每次更新时记得修改 version 字段
3. **描述限制**：Steam 对描述长度有限制，建议控制在合理范围内
4. **图片要求**：预览图片必须存在于模组目录中
5. **标签限制**：Steam 对标签数量和长度有限制

---

## 官方资源

### Project Zomboid 官方资源

- **官方网站**: https://projectzomboid.com/
- **Steam 商店页**: https://store.steampowered.com/app/108600/Project_Zomboid/
- **Steam Workshop**: https://steamcommunity.com/app/108600/workshop/

### 官方文档和社区

- **PZ Wiki - Modding**: https://pzwiki.net/w/index.php?title=Modding
- **The Indie Stone Forums**: https://theindiestone.com/forums/
  - Modding Section: https://theindiestone.com/forums/index.php?forums/modding.15/
  - Help Section: https://theindiestone.com/forums/index.php?forums/help.14/

### 开发资源

- **Lua 官方文档**: https://www.lua.org/manual/
- **Steam Workshop 文档**: https://steamcommunity.com/dev/documentation/

---

## 示例项目

完整的 workshop.txt 示例可参考：
- `bin2_b42/workshop.txt` - 模组包示例
- `bin2_b42/Contents/mods/Lingering Voices CN/42/workshop.txt` - 单个模组示例

---

## 常见问题

### Q: workshop.txt 是必需的吗？

**A:** 不是必需的，但强烈建议使用。它可以让 Steam Workshop 正确显示模组信息，便于用户发现和下载。

### Q: 如何获取 Workshop ID？

**A:** 首次上传模组到 Steam Workshop 后，Steam 会自动分配一个 ID。请将这个 ID 添加到 workshop.txt 的 `id` 字段中。

### Q: 可以使用中文标题和描述吗？

**A:** 可以，Steam Workshop 支持多语言。但建议同时提供英文标签以提高可发现性。

### Q: 更新模组时需要修改 workshop.txt 吗？

**A:** 建议每次更新时修改 `version` 字段，并更新 `changelog` 字段记录更新内容。

### Q: 如何删除已上传的模组？

**A:** 登录 Steam Workshop，找到你的模组，选择删除选项。注意：删除后 ID 将无法恢复。

---

## 总结

`workshop.txt` 是 Project Zomboid 模组发布到 Steam Workshop 的重要配置文件。正确配置该文件可以提高模组的可发现性和用户体验。

**关键要点：**
- 使用清晰的标题和描述
- 添加相关标签
- 维护版本号和更新日志
- 选择合适的可见性设置
- 参考官方资源和社区文档

通过遵循本指南，您可以有效地管理和发布您的 Project Zomboid 模组。