# Project Zomboid 模组翻译开发指南

本文档介绍如何在不修改原模组的情况下，通过创建 patch 模组来翻译 Project Zomboid 模组的内容。

## 目录

- [基本概念](#基本概念)
- [翻译台词](#翻译台词)
- [翻译 UI 文本](#翻译-ui-文本)
- [翻译 Sandbox 设置](#翻译-sandbox-设置)
- [Patch 模组结构](#patch-模组结构)
- [最佳实践](#最佳实践)

---

## 基本概念

### 什么是 Patch 模组？

Patch 模组是一种特殊的模组，它不包含原始内容，而是通过覆盖原模组的数据来修改或扩展原模组的功能。

### 优势

- **不修改原模组**：保持原模组完整性，便于更新
- **易于维护**：翻译内容独立管理
- **模块化**：可以为同一原模组创建多个语言的 patch
- **兼容性好**：原模组更新时，patch 通常无需修改

---

## 翻译台词

### 原理

利用 Lua 的全局变量覆盖特性。由于 patch 模组在原模组之后加载，patch 文件中重新定义的变量会覆盖原模组中的值。

### 步骤

#### 1. 创建 patch 文件

在 patch 模组的 `media/lua/server/` 目录下创建 Lua 文件（如 `LWtalking_patch.lua`）。

#### 2. 覆盖台词列表

```lua
-- Patch 模组：翻译 Lingering Voices 的所有台词
-- 此文件必须在原模组之后加载

-- 扑击时的台词
lungeList = {
    "躲起来...",
    "跑...",
    "救救我们...",
    -- ... 更多中文台词
}
lungeLines = { zombieLine:new("%s", lungeList) }

-- 踉跄时的台词
staggerList = {
    "哈哈哈...",
    "不...！",
    -- ... 更多中文台词
}
staggerLines = { zombieLine:new("%s", staggerList) }
```

#### 3. 重新创建对象

如果原模组使用对象包装台词列表，需要重新创建对象：

```lua
-- 原模组可能这样定义
thumpingLines = { zombieLine:new("%s", thumpingList) }

-- Patch 中也需要重新创建
thumpingLines = { zombieLine:new("%s", thumpingList) }
```

### 注意事项

- **保持变量名一致**：必须使用原模组中相同的变量名
- **保持数据结构**：确保覆盖的数据结构与原模组一致
- **处理特殊格式**：如 `%s` 占位符，确保翻译后格式正确

---

## 翻译 UI 文本

### 翻译文件位置

UI 翻译文件通常位于：
```
media/lua/shared/Translate/<LANG>/<FILENAME>_<LANG>.txt
```

### 步骤

#### 1. 创建翻译文件

在 patch 模组中创建对应的翻译文件：

```
Contents/mods/<Mod_ID>/42/media/lua/shared/Translate/CN/UI_CN.txt
```

#### 2. 使用 Lua 表格式

```lua
UI_CN = {
    UI_Option_Screen_Resolution = "屏幕分辨率",
    UI_Option_Screen_Resolution_tooltip = "调整游戏窗口分辨率",

    UI_Inventory_Title = "背包",
    UI_Inventory_Close = "关闭",
}
```

### 自动加载机制

Project Zomboid 会自动加载所有模组的翻译文件，后加载的模组会覆盖之前的翻译。

---

## 翻译 Sandbox 设置

### 翻译文件位置

Sandbox 设置翻译文件：
```
media/lua/shared/Translate/<LANG>/Sandbox_<LANG>.txt
```

### 步骤

#### 1. 创建翻译文件

```lua
Sandbox_CN = {
    Sandbox_LingeringVoices = "徘徊的声音",

    Sandbox_LingeringVoices_RespondToSound = "僵尸被说话声吸引",
    Sandbox_LingeringVoices_RespondToSound_tooltip = "僵尸对僵尸说话的反应就像玩家大喊一样",

    Sandbox_LingeringVoices_CustomLines = "自定义台词",
    Sandbox_LingeringVoices_CustomLines_tooltip = "是否使用自定义台词文件",

    Sandbox_LingeringVoices_LowerLineLimit = "最小延迟",
    Sandbox_LingeringVoices_LowerLineLimit_tooltip = "僵尸说出下一句台词前需要经过的最小秒数。",

    Sandbox_LingeringVoices_UpperLineLimit = "最大延迟",
    Sandbox_LingeringVoices_UpperLineLimit_tooltip = "僵尸说出下一句台词前需要经过的最大秒数。",

    Sandbox_LingeringVoices_StaggerSpeakChance = "被击中时说话几率",
    Sandbox_LingeringVoices_StaggerSpeakChance_tooltip = "僵尸被击中时说话的几率（每1000次）。",
}
```

### 命名规则

- 变量名必须与原模组中定义的完全一致
- 通常格式为：`Sandbox_<ModID>_<SettingName>`
- Tooltip 变量名：`Sandbox_<ModID>_<SettingName>_tooltip`

---

## Patch 模组结构

### 标准目录结构

```
<Mod_ID>/
├── mod.info           # 模组元数据
├── poster.png         # 模组预览图
└── media/
    └── lua/
        ├── server/    # 服务器端脚本（台词覆盖等）
        └── shared/    # 共享脚本（翻译文件）
            └── Translate/
                └── CN/
                    ├── UI_CN.txt
                    └── Sandbox_CN.txt
```

### mod.info 配置

```ini
name=Lingering Voices CN
id=Lingering Voices CN
description=将 Lingering Voices 模组的所有僵尸台词翻译为中文。包括扑击、踉跄、假死、敲门和攻击时的台词，让中文玩家获得更好的游戏体验。
poster=poster.png
versionMin=42.13.1
require=\Lingering Voices
```

### 关键字段说明

- **name**：模组显示名称
- **id**：模组唯一标识符
- **description**：模组描述
- **poster**：预览图文件名
- **versionMin**：最低兼容游戏版本
- **require**：依赖的原模组（确保先加载原模组）

---

## 最佳实践

### 1. 模组命名规范

- 使用 `<原模组名> CN` 或 `<原模组名> Chinese` 格式
- 例如：`Lingering Voices CN`

### 2. 文件组织

- 将所有翻译相关文件放在 `media/lua/shared/Translate/CN/` 下
- 将台词覆盖脚本放在 `media/lua/server/` 下
- 使用清晰的文件名，如 `LWtalking_patch.lua`

### 3. 版本兼容性

- 在 mod.info 中指定正确的 `versionMin`
- 如果原模组有多个版本，为每个版本创建对应的 patch

### 4. 测试验证

- 在游戏中启用原模组和 patch 模组
- 验证所有翻译是否正确显示
- 检查台词是否在正确场景播放
- 确认 Sandbox 设置翻译是否生效

### 5. 更新维护

- 原模组更新时，检查是否有新增的台词或设置
- 及时添加新增内容的翻译
- 保持与原模组版本同步

### 6. 代码注释

```lua
-- Patch 模组：翻译 Lingering Voices 的所有台词
-- 此文件必须在原模组之后加载
-- 原模组版本：42.13.1
-- 翻译版本：1.0.0
-- 翻译者：Your Name
```

### 7. 错误处理

- 检查原模组是否已加载
- 验证变量是否存在再覆盖
- 提供回退机制

```lua
-- 检查原模组是否已加载
if zombieLine and zombieLine.new then
    thumpingLines = { zombieLine:new("%s", thumpingList) }
else
    print("[Lingering Voices CN] 警告：原模组未正确加载")
end
```

---

## 常见问题

### Q: 翻译没有生效？

**A:** 检查以下几点：
1. mod.info 中是否正确设置了 `require=\原模组名`
2. 文件路径是否正确
3. 变量名是否与原模组一致
4. 游戏版本是否满足 `versionMin` 要求

### Q: 如何翻译动态生成的文本？

**A:** 需要找到原模组中生成文本的函数，在 patch 中覆盖该函数：

```lua
-- 原模组函数
function getGreeting()
    return "Hello"
end

-- Patch 覆盖
function getGreeting()
    return "你好"
end
```

### Q: 支持哪些语言？

**A:** Project Zomboid 支持的语言包括：
CN（简体中文）、EN（英语）、DE（德语）、ES（西班牙语）、FR（法语）、HU（匈牙利语）、IT（意大利语）、JP（日语）、KO（韩语）、NL（荷兰语）、PL（波兰语）、PT（葡萄牙语）、PTBR（巴西葡萄牙语）、RU（俄语）、TH（泰语）、TR（土耳其语）、UA（乌克兰语）、CH（繁体中文）、DA（丹麦语）

---

## 示例项目

完整的翻译示例可参考：
- `bin2_b42/Contents/mods/Lingering Voices CN/` - 完整的台词翻译示例
- `bin2_b42/Contents/mods/Lingering Voices CN/42/media/lua/server/LWtalking_patch.lua` - 台词覆盖脚本
- `bin2_b42/Contents/mods/Lingering Voices CN/42/media/lua/shared/Translate/CN/Sandbox_CN.txt` - Sandbox 设置翻译

---

## 参考资源

- [Project Zomboid Modding Forums](https://theindiestone.com/forums/)
- [Project Zomboid Wiki - Modding](https://pzwiki.net/w/index.php?title=Modding)
- [Lua 官方文档](https://www.lua.org/manual/)