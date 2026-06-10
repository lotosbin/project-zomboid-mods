# 开发日志 2026-06-10

## 主题: CraftRecipe (B42) Wiki 系统学习

## 目标

深入学习 Project Zomboid Build 42 的 `craftRecipe` 系统,补充对模组制作系统的全面理解。

## 过程

### 1. 抓取策略

- 直接 `WebFetch` `https://pzwiki.net/wiki/CraftRecipe` → 失败 (Cloudflare 403)
- `curl` 直接抓取 → Cloudflare "Just a moment..." 拦截
- `web_search` → 无相关结果
- 改用 Wayback Machine `https://web.archive.org/web/2025/https://pzwiki.net/wiki/CraftRecipe` → 成功
- 备用页面:
  - B42 CraftRecipe: oldid=1263201 (2025-10-30)
  - B41 Recipe (scripts): oldid=874781 (2025-03-02) — 作为字段对照参考
  - 相关页面 Item / EvolvedRecipe / Fluid (部分存在)

### 2. 内容整理

详见 `docs/craft-recipe-study.md`,涵盖:

- 文件位置与命名规范
- B42 craftRecipe 完整字段表
- inputs 块语法(`item` / `-fluid` / `mode:` / `flags[]` / `mappers[]`)
- outputs 块语法 + itemMapper 机制
- Tags 详细列表
- 完整代码示例:SawLogs / RefillHurricaneLantern / CarveWhistle
- Lua 钩子函数(OnCreate / OnTest / OnCanPerform / OnGiveXP)
- 修改现有配方的两种方法
- Module / needToBeLearn / AutoLearnAll / AutoLearnAny 系统
- B41↔B42 字段对照表

## 关键知识点(中文)

### A. B42 与 B41 语法差异

| 维度 | B41 | B42 |
|------|-----|-----|
| 字段分隔 | `属性:值` (冒号) | `属性 = 值` (等号) |
| 原料 | 单行 source | `inputs { item 1 [...] }` 块 |
| 产出 | `Result:Nails=20` | `outputs { item 20 Base.Nails }` 块 |
| keep/destroy | 关键字前缀 | `mode:keep` / `mode:destroy` |
| 动画 | `AnimNode:RipSheets` | `timedAction = RipSheets` |

### B. 必填字段(踩坑重点)

- `Tags` **必填**,且至少需要一个工作台标签(如 `AnySurfaceCraft`、`InHandCraft`)
- `inputs` **必填**
- `outputs` 在 Wiki 中列为必填,但部分游戏源码中可省(默认无产出?待验证)

### C. inputs 完整语法

```
item <数量> [<fullType1>;<fullType2>...] tags[<tag1>;<tag2>] mode:<keep|destroy> flags[<flag1>;<flag2>] mappers[<mapperName>]
-fluid <升数> [<FluidID>]
```

- `[*]` 匹配任意物品
- `tags[...]` 匹配拥有任一标签的物品
- `mode:keep` 不消耗
- `flags[Prop1;Prop2]` 占用主/副手
- `mappers[...]` 绑定 mapper 用于动态输出

### D. itemMapper 机制

```lua
itemMapper MyMapper
{
    Base.InputItemA = Base.OutputItemA,
    Base.InputItemB = Base.OutputItemB,
    default = Base.DefaultOutput,
}
```

- 用于根据输入物类型决定输出
- 配合 `overlayMapper` 可叠加额外产出
- 是 B42 新机制,**B41 没有**

### E. Lua 钩子签名

```lua
function Recipe.OnCreate.Xxx(items, result, player, selectedItem) ... end
function Recipe.OnTest.Xxx(item) return true|false end
function Recipe.OnCanPerform.Xxx(recipe, playerObj) return true|false end
function Recipe.OnGiveXP.Xxx(recipe, ingredients, result, player) ... end
```

### F. 学习系统

```lua
needToBeLearn = true,
AutoLearnAll = Carving:5;Woodwork:3,   -- 都达到才自动学会
AutoLearnAny = Woodwork:5;MetalWelding:3, -- 其一达到即学会
MetaRecipe = SomeBaseRecipe,           -- 学会该配方即学会 SomeBaseRecipe
```

### G. 修改现有配方(B42 局限)

1. **方法一**:同 RecipeID 重定义,只能加 `itemMapper` / `overlayMapper` 条目
2. **方法二**:Lua API `ScriptManager.instance:getCraftRecipe()` + `output:getOutputMapper():addOutputEntree()`

Wiki 明确说 B42 在 Lua 端可改的内容比 B41 少很多。

### H. 特殊属性对照

| 行为 | B41 | B42 |
|------|-----|-----|
| 允许损坏物品 | `AllowDestroyedItem:true` | `flags[AllowDestroyedItem]` |
| 地面制作 | `CanBeDoneFromFloor:true` | `Tags = ...;CanBeDoneFromFloor` |
| 必学 | `NeedToBeLearn:true` | `needToBeLearn = true` |
| 不返还产出 | `RemoveResultItem:true` | Wiki 未文档化(B42) |
| 附近需有物 | `NearItem:Workbench` | Wiki 未文档化(B42) |
| 覆盖/废弃 | `Override:true` / `Obsolete:true` | B42 不支持(需用 Lua API) |

### I. 翻译

- 配方显示名:`Recipe_<RecipeID>` 放在 `media/lua/shared/Translate/<LANG>/Recipe.json` (B42.15+ JSON 格式)
- 模块化翻译文件命名遵循项目其他部分规范

## 产出文件

- `docs/craft-recipe-study.md` — 完整学习笔记(约 380 行)
- `docs/rolling_log.md` — 已追加本次学习记录

## 经验沉淀

1. **抓取策略**:pzwiki.net 受 Cloudflare 防护,优先用 `web.archive.org/web/<年份>/<url>` 取存档
2. **UA 伪装**:`User-Agent: Mozilla/5.0 (Macintosh; ...)` 在 cloudflare 拦截下仍无效,需走 Wayback
3. **字段命名陷阱**:`needTobeLearn` (wiki 例子) 与 `needToBeLearn` (wiki 表格) 拼写不一,**实际游戏行为需以源码为准**
4. **B42 学习曲线**:B42 制作系统比 B41 严格(强制 Tags 必填、强制 mapper 与 input/output 分离),但表达力更清晰
5. **避免重复造轮子**:简单覆盖(Override)在 B42 已不可用,所有配方扩展都需通过 itemMapper 或 Lua API

## 仓库内真实代码案例(bin2_extension 跨版本演进)

仓库内 `bin2_extension` 模组同时包含 B41 与 B42 两种风格的 Recipes.txt,是非常好的对照样本。

**B41 旧式** (`42.15.0/media/scripts/Recipes.txt`):
```lua
module Bin2Recipe
{
    recipe DisassembleCrudeWoodenTongs
    {
        CrudeWoodenTongs,
        Result:WoodenStick=2,
        Result:Rag=1,
        Time:5.0,
        OnGiveXP:Recipe_GiveXP,
    }
}
```

**B42 新式** (`42.19.0/media/scripts/recipes/bin2_Recipes.txt`):
```lua
module Bin2Recipe
{
    craftRecipe Bin2DisassembleCrudeWoodenTongs
    {
        Tags = AnySurfaceCraft,
        category = Cooking,
        inputs
        {
            item 1 [CrudeWoodenTongs],
        }
        outputs
        {
            item 2 Base.WoodenStick,
            item 1 Base.Rag,
        }
    }
}
```

**演进要点:**
1. RecipeID 加 mod 前缀(`Bin2DisassembleCrudeWoodenTongs`)避免冲突
2. `Time:5.0` → (B42 改为 `time = 5` 等号语法,本文件省略)
3. `Result:X=Y` → `outputs { item Y Base.X }`
4. 原料 `CrudeWoodenTongs,` 简写 → `item 1 [CrudeWoodenTongs]` 显式
5. `OnGiveXP:Recipe_GiveXP` 简写 → B42 应改为 `OnCreate = Recipe.OnCreate.XXX`
6. 必须加 `Tags = AnySurfaceCraft,` 才能被识别为合法 recipe

## 下一步建议

- [ ] 验证本地 `bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt` 是否完全符合 B42.19 新语法(目前缺 `time` 字段与 `OnCreate` 钩子)
- [ ] 用 `itemMapper` 重构 `Bin2DisassembleCrudeWoodenTongs`,支持多种钳子输入映射到不同产出
- [ ] 在 Neat_Building / Neat_Crafting 中验证 B42 Tags 兼容性
- [ ] 关注 `overlayMapper` 的具体行为(目前 Wiki 标记 "This section may need more content")
- [ ] 跟进 B42 `MetaRecipe` 是否实际在游戏中生效
- [ ] 整理 `docs/recipes_b42_cheatsheet.md` 速查表
- [ ] 验证 `needTobeLearn` 正确拼写(查游戏源码)
