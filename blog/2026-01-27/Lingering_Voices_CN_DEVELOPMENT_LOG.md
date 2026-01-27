# Lingering Voices CN 开发日志

## 目标
将 Lingering Voices 模组的僵尸台词翻译为中文。

## 关键问题

### 1. Steam Workshop 覆盖文件不生效
- **原因**：Steam Workshop 机制下，覆盖同名文件不会替换原版
- **解决方案**：不覆盖原文件，创建 patch 文件修改变量

### 2. 变量作用域问题
- **问题**：原版使用 `local lungeList`、`local lungeLines` 等局部变量
- **解决**：patch 文件中覆盖全局变量 `lungeLines` 等（在原版中这些是全局的）

### 3. mod 加载时机
- **发现**：`Events.OnGameBoot` 在 mod 加载后触发，但原版变量已在加载时定义
- **解决**：直接执行 patch 函数 `patchLingeringVoicesCN()`，不等待 Events

### 4. getText() 翻译不生效
- **尝试1**：使用自定义 key（如 `LW_lunge_1`）
  - 结果：不生效
- **尝试2**：使用英文原文做 key（如 `Hide...`）
  - 结果：不生效
- **尝试3**：使用 `Sandbox_` 前缀
  - 结果：**生效！**

### 5. 中文显示问题
- **问题**：硬编码中文在游戏内显示为方块（字体不支持）
- **解决**：使用 `getText()` + `Sandbox_` 前缀翻译

## 最终方案

### 文件结构
```
Lingering Voices CN/42/
├── mod.info
└── media/
    └── lua/
        ├── server/
        │   └── LWtalking_patch.lua    # patch 文件
        └── shared/
            └── Translate/
                └── CN/
                    └── Sandbox_CN.txt  # 翻译文件
```

### mod.info
```ini
name=Lingering Voices CN
id=Lingering Voices CN
require=\Lingering Voices
```

### LWtalking_patch.lua
```lua
local function patchLingeringVoicesCN()
    lungeLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_lunge_1"),
        getText("Sandbox_LW_lunge_2"),
        -- ...
    })}
    -- staggerLines, fakeDeadLines, thumpingLines, attackLines 同理
end
patchLingeringVoicesCN()
```

### Sandbox_CN.txt
```lua
Sandbox_CN = {
    Sandbox_LW_lunge_1 = "躲起来...",
    Sandbox_LW_lunge_2 = "跑...",
    -- ...
}
```

## 经验总结

1. **Steam Workshop 覆盖机制**：同名文件不生效，需要 patch 方式
2. **PZ 翻译系统**：`getText()` 需要特定前缀（`Sandbox_` 可用）
3. **字体问题**：PZ 默认字体不支持中文，需通过翻译系统
4. **mod 加载顺序**：`require` 确保依赖模组先加载

## 待解决
- 测试游戏内中文显示是否正常
- 如仍显示方块，需配置中文字体
