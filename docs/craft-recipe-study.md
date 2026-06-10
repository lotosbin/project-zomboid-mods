# PZ Wiki CraftRecipe 学习笔记

> 来源:
> - 主页面: <https://pzwiki.net/wiki/CraftRecipe> (B42 unstable,oldid=1263201,2025-10-30)
> - B41 对照: <https://pzwiki.net/wiki/Recipe_(scripts)> (oldid=874781,2025-03-02)
>
> B42 配方系统与 B41 完全不同,以下以 B42 为主线,B41 作为字段对照参考。

---

## 1. 配方文件位置 / 结构

### 1.1 顶层结构

```lua
module yourModule /* 或 Base */
{
    craftRecipe <RecipeID>
    {
        -- 参数
    }
}
```

- 配方写在 `.txt` 脚本文件中,一般放在 `media/scripts/recipes/` 目录
- `<RecipeID>` 是唯一标识,**不能有空格**;它对应翻译文件中的 `Recipe_<RecipeID>`
- 翻译文件结构(B42.15+):
  - `media/lua/shared/Translate/EN/Recipe.json`
  - 内容: `{ "Recipe_MyRecipe": "My Recipe Name" }`

### 1.2 文件命名参考

| 用途 | 常见文件 |
|------|----------|
| 木工 | `recipes_carpentry.txt` |
| 光源 | `recipes_lightsources.txt` |
| 骨头/雕刻 | `recipes_bone.txt` |

---

## 2. B42 craftRecipe 完整字段表

| 参数 | 必填 | 说明 |
|------|------|------|
| `Tags` | **是** | 制作条件标签,**至少需要一个工作台标签** (如 `AnySurfaceCraft`) |
| `inputs` | **是** | 制作所需原料 |
| `outputs` | 否 | 制作产出物 |
| `time` / `Time` | 否 | 制作耗时,默认 50 |
| `timedAction` | 否 | 制作时的动画、声音、卡路里消耗、热量生成 |
| `category` | 否 | 在制作菜单中的分类 |
| `ToolTip` | 否 | 制作菜单中的描述 |
| `Icon` | 否 | 制作菜单中显示的图标 |
| `itemMapper` | 否 | 输入→输出物品映射 |
| `OnCreate` | 否 | 制作完成时调用的 Lua 函数 |
| `OnTest` | 否 | 制作前校验 Lua 函数 |
| `xpAward` | 否 | 制作给予的经验,格式 `技能:经验` |
| `SkillRequired` | 否 | 制作所需技能等级,格式 `技能:等级` |
| `needToBeLearn` | 否 | true 时需要先学会配方 |
| `AutoLearnAll` | 否 | 必须学会所有列出的技能(达到等级)才能学会该配方 |
| `AutoLearnAny` | 否 | 列出技能之一达到等级即可学会配方 |
| `MetaRecipe` | 否 | 链接到另一个配方(学会 Meta 等于学会主配方) |
| `AllowBatchCraft` | 否 | 允许批量制作 |
| `Fluids` | 否 | 配方使用液体 |
| `overlayMapper` | 否 | 输入→输出叠加物映射(尚未文档化) |

### 2.1 可用技能 (vanilla)

技能定义在 `PerkFactory.Perks` 类中,使用 `技能名:等级` 格式:

| 技能 ID | 中文 |
|---------|------|
| `Blacksmith` | 锻造 |
| `Butchering` | 屠宰 |
| `Carving` | 雕刻 |
| `Cooking` | 烹饪 |
| `Electricity` | 电工 |
| `FlintKnapping` | 打制石器 |
| `Glassmaking` | 玻璃制造 |
| `Maintenance` | 维护 |
| `Masonry` | 砌筑 |
| `MetalWelding` | 金属焊接 |
| `Pottery` | 陶器 |
| `Tailoring` | 裁缝 |
| `WoodWork` | 木工 |

> 模组也可以自定义技能(由其他 mod 或本 mod 注入 PerkFactory)。

---

## 3. inputs 块(原料)语法

B42 风格示例 (来自 `recipes_carpentry.txt` `SawLogs`):

```lua
inputs
{
    item 1 [Base.Log] flags[Prop2],
    item 1 tags[Saw] mode:keep flags[MayDegradeLight;Prop1],
}
```

### 3.1 通用形式

```
item <数量> [<筛选条件>] mode:<模式> flags[<flag1>;<flag2>...] mappers[<mapperName>]
-fluid <升数> [<FluidID>],
```

### 3.2 筛选条件形式

- `[Base.Log]` — 具体物品 fullType
- `[Base.ItemA;Base.ItemB]` — 任选其一(`;` 分隔)
- `[*]` — 任意物品
- `tags[Saw]` — 拥有 `Saw` 标签的物品
- `tags[DrillWood;DrillMetal;DrillWoodPoor]` — 拥有任一标签

### 3.3 mode 取值

| 取值 | 含义 |
|------|------|
| `mode:keep` | 制作后保留物品(不会消耗) |
| `mode:destroy` | 制作后销毁物品 |
| (缺省) | 制作后消耗(默认) |

### 3.4 常见 flags

| Flag | 含义 |
|------|------|
| `Prop1` | 占用主手(右) — 对应 B41 的 `Prop1` |
| `Prop2` | 占用副手(左) — 对应 B41 的 `Prop2` |
| `MayDegradeLight` | 工具会轻微降级 |
| `MayDegradeHeavy` | 工具会重度降级 |
| `NotFull` | 仅匹配未装满/未满状态的容器(液体) |
| `AllowFavorite` | 允许使用被收藏的物品 |
| `InheritFavorite` | 继承收藏状态到产出 |
| `ItemCount` | 计数可部分消耗(液体桶) |
| `AllowDestroyedItem` | 允许使用已损坏物品(参见 3.5) |

### 3.5 液体输入

```lua
-fluid 1.0 [Petrol],
-fluid <升数> [<FluidID>],
```

- 用 `-fluid` 前缀(不是 `item`)
- 数量单位是升(可以为小数)

### 3.6 进阶:B41 兼容字段(若用 B41 语法)

B41 还在使用旧 `recipe` 系统,字段对照:

| B41 字段 | B42 等价/变化 |
|----------|---------------|
| `Time:230.0` | `Time = 230` (无冒号) |
| `Result:Nails=20` | `outputs { item 20 Base.Nails }` |
| `NailsBox` (无 = 数量) | `item 1 [Base.NailsBox]` |
| `keep Saw` | `mode:keep` |
| `destroy RippedSheets` | `mode:destroy` |
| `Prop1:Screwdriver` | `flags[Prop1]` |
| `AnimNode:RipSheets` | `timedAction = RipSheets` |
| `[Recipe.GetItemTypes.FishingLine]=2` | 模组 Lua 函数返回候选 items |
| `Heat:-0.22` | (B42 暂未文档化) |
| `StopOnWalk / StopOnRun` | (B42 暂未文档化) |
| `IsHidden:true` | (B42 暂未文档化) |

---

## 4. outputs 块(产出)语法

```lua
outputs
{
    item <数量> <fullType> [其他参数],
}
```

### 4.1 简单产出

```lua
outputs
{
    item 3 Base.Plank,         -- 产出 3 个 Base.Plank
    item 1 Base.Whistle_Bone,  -- 产出 1 个骨哨
}
```

### 4.2 通过 itemMapper 映射产出

当输入/输出需要按类型变化(如不同种皮革)时:

```lua
outputs
{
    item 1 mapper:LampMapper,  -- 根据 mapper 决定具体产出物
}

itemMapper LampMapper
{
    Base.Lantern_Hurricane       = Base.Lantern_Hurricane,
    Base.Lantern_Hurricane_Copper = Base.Lantern_Hurricane_Copper,
    Base.Lantern_Hurricane_Forged = Base.Lantern_Hurricane_Forged,
    Base.Lantern_Hurricane_Gold   = Base.Lantern_Hurricane_Gold,
    Base.Lantern_Hurricane_Silver = Base.Lantern_Hurricane_Silver,
    default = Base.Lantern_Hurricane,
}
```

- 左侧 = 匹配到的输入物,右侧 = 产出的物
- `default` 是兜底
- `overlayMapper` 是额外叠加物(类比 `itemMapper`,但只输出叠加内容)

### 4.3 B41 时代的 result 字段(供对照)

| B41 字段 | 说明 |
|----------|------|
| `Result:Nails=20` | 产出 20 个 Nails |
| `Result:Hat_TinFoilHat` | 产出 1 个 |
| `Result:Base.Hat_TinFoilHat` | 加 mod 前缀 |
| `RemoveResultItem:true` | 不返回结果(给 NPC 等) |
| `CanBeDoneFromFloor:true` | 可从地面直接制作,不需先拿入包 |

### 4.4 B42 关键 result 替代字段

B42 用 `outputs` 块替换 B41 `Result:`,但 B41 行为对应:

| B42 字段 | 替代 B41 |
|----------|----------|
| `Tags = InHandCraft;CanBeDoneFromFloor` | `CanBeDoneFromFloor:true` |
| `flags[AllowDestroyedItem]` | `AllowDestroyedItem:true` |
| `outputs {}` | `Result:xxx=y` |
| `itemMapper` / `overlayMapper` | (新增机制) |

> 说明:Wiki 仍把 `CanBeDoneFromFloor`、`AllowDestroyedItem` 列为 B41 字段。
> B42 用 `Tags = ...;CanBeDoneFromFloor` 和 `flags[AllowDestroyedItem]` 实现同样效果。

---

## 5. Tags(制作条件)详解

B42 的 `Tags` 字段是字符串列表,使用 `;` 分隔,至少需要一个工作台类标签。

### 5.1 常见 Tags

| Tag | 用途 |
|-----|------|
| `AnySurfaceCraft` | 任意工作台可制作(最常用) |
| `InHandCraft` | 在手持工具时直接制作(不需要工作台) |
| `CanBeDoneFromFloor` | 允许不收进背包直接从地面取物品 |
| `CanBeDoneInDark` | 黑暗中可制作 |
| `Survivalist` | 生存向(影响分类) |

### 5.2 至少需要一个制作台标签

Wiki 强调:为了让制作被识别,**至少需要一个 crafting bench tag**(如 `AnySurfaceCraft`)。

---

## 6. 完整代码示例

### 6.1 简单示例:SawLogs(木工锯木)

来源:`ProjectZomboid\media\scripts\recipes\recipes_carpentry.txt`

```lua
craftRecipe SawLogs
{
    timedAction = SawLogs,
    Time = 230,
    Tags = InHandCraft;CanBeDoneFromFloor,
    category = Carpentry,
    xpAward = Woodwork:5,
    inputs
    {
        item 1 [Base.Log] flags[Prop2],
        item 1 tags[Saw] mode:keep flags[MayDegradeLight;Prop1],
    }
    outputs
    {
        item 3 Base.Plank,
    }
}
```

### 6.2 复合示例:加注煤油灯 (含 mapper + fluid)

来源:`recipes_lightsources.txt`

```lua
craftRecipe RefillHurricaneLantern
{
    timedAction = Making,
    Time = 50,
    OnCreate = Recipe.OnCreate.RefillHurricaneLantern,
    /* OnTest = Recipe.OnTest.RefillHurricaneLantern, */
    Tags = InHandCraft;CanBeDoneInDark,
    category = Miscellaneous,
    inputs
    {
        item 1 [Base.Lantern_Hurricane;Base.Lantern_Hurricane_Copper;Base.Lantern_Hurricane_Forged;Base.Lantern_Hurricane_Gold;Base.Lantern_Hurricane_Silver] mode:destroy flags[NotFull;AllowFavorite;InheritFavorite;ItemCount] mappers[LampMapper],
        item 1 [*],
        -fluid 1.0 [Petrol],
    }
    outputs
    {
        item 1 mapper:LampMapper,
    }
    itemMapper LampMapper
    {
        Base.Lantern_Hurricane       = Base.Lantern_Hurricane,
        Base.Lantern_Hurricane_Copper = Base.Lantern_Hurricane_Copper,
        Base.Lantern_Hurricane_Forged = Base.Lantern_Hurricane_Forged,
        Base.Lantern_Hurricane_Gold   = Base.Lantern_Hurricane_Gold,
        Base.Lantern_Hurricane_Silver = Base.Lantern_Hurricane_Silver,
        default = Base.Lantern_Hurricane,
    }
}
```

### 6.3 学习 + 制作:骨哨

来源:`recipes_bone.txt`

```lua
craftRecipe CarveWhistle
{
    time = 200,
    tags = AnySurfaceCraft;Survivalist,
    category = Carving,
    xpAward = Carving:60,
    SkillRequired = Carving:6,
    needTobeLearn = true,   -- 需先学会配方
    AutoLearnAny = Carving:8, -- 雕刻等级达到 8 自动学会
    timedAction = SharpenStake,
    inputs
    {
        item 1 tags[DrillWood;DrillMetal;DrillWoodPoor] mode:keep flags[MayDegradeLight],
        item 1 tags[SharpKnife] mode:keep flags[MayDegradeLight],
        item 1 [Base.SmallAnimalBone] flags[Prop2;AllowDestroyedItem],
    }
    outputs
    {
        item 1 Base.Whistle_Bone,
    }
}
```

---

## 7. Lua 钩子函数

### 7.1 OnCreate

制作完成时调用,签名参考 B41 风格:

```lua
function Recipe.OnCreate.YourRecipe(items, result, player, selectedItem)
    -- items    : 使用的原料(列表)
    -- result   : 产出物品
    -- player   : 玩家对象
    -- selectedItem : 选中物品(可空)
    player:getInventory():AddItem("Base.ElectronicsScrap")
end
```

### 7.2 OnTest

校验资源是否满足条件,返回 `true` / `false`:

```lua
function Recipe.OnTest.IsNotWorn(item)
    if instanceof(item, "Clothing") then
        return not item:isWorn()
    end
    return true
end
```

### 7.3 OnCanPerform (B41 风格,B42 沿用)

开始制作前的额外条件检查:

```lua
function Recipe.OnCanPerform.HockeyMaskSmashBottle(recipe, playerObj)
    local wornItem = playerObj:getWornItem("MaskEyes")
    return (wornItem ~= nil) and (wornItem:getType() == "Hat_HockeyMask")
end
```

### 7.4 OnGiveXP (B41 风格)

```lua
function Recipe.OnGiveXP.SawLogs(recipe, ingredients, result, player)
    if player:getPerkLevel(Perks.Woodwork) <= 3 then
        player:getXp():AddXP(Perks.Woodwork, 3)
    else
        player:getXp():AddXP(Perks.Woodwork, 1)
    end
end
```

### 7.5 模块化函数 (B41 风格)

```lua
-- 必须在文件顶部继承 Base 的 Recipe
local Recipe = Recipe

function Recipe.OnCreate.YourRecipe(items, result, player, selectedItem)
    -- ...
end
```

也可以写动态 items 返回:

```lua
function Recipe.GetItemTypes.FishingLine(scriptItems)
    scriptItems:addAll(getScriptManager():getItemsTag("FishingLine"))
end
```

### 7.6 修改现有配方 (B42 局限)

Wiki 明确指出:**B42 的 craftRecipe 在 Lua 端可修改的内容比 B41 少很多**。

#### 方法一:同 RecipeID 重定义(只能加 itemMapper / overlayMapper)

```lua
craftRecipe DrySmallLeather
{
    itemMapper DryLeatherSmall
    {
        Base.RaccoonLeather_Spiffo_Fur_Tan = Base.RaccoonLeather_Spiffo_Fur_Tan_Wet,
    }
    overlayMapper
    {
        Base.RaccoonLeather_Spiffo_Fur_Tan_Wet = DeerLeather,
    }
}
```

> 注意:此方法只能加 `itemMapper` / `overlayMapper` 条目,不会覆盖原 recipe。

#### 方法二:通过 ScriptManager Lua API 动态改

```lua
Events.OnGameStart.Add(function()
    local recipe = ScriptManager.instance:getCraftRecipe("SliceHead")
    if recipe then
        local outputs = recipe:getOutputs()
        for i = 0, outputs:size() - 1 do
            local out = outputs:get(i)
            local mapper = out:getOutputMapper()
            if mapper then
                local list = ArrayList.new()
                list:add("HorseMod.Horse_Head")
                mapper:addOutputEntree("HorseMod.Horse_Skull", list)
                mapper:OnPostWorldDictionaryInit(recipe:getName())
            end
        end
    end
end)
```

---

## 8. Module 系统 / `needToBeLearn` / 自动学会

Wiki 的 craftRecipe 用 `module yourModule { ... }` 包裹,但**模块本身不直接控制配方可见性**,它控制的是配方命名空间(也用作物品源)。

### 8.1 needToBeLearn

```lua
needTobeLearn = true,    -- 拼写注意:Tobe 大小写 wiki 既有 needToBeLearn 又有 needTobeLearn,需以实际游戏为准
```

设为 `true` 时,玩家必须先学会配方才能在制作菜单中看到/制作。常见学习途径:

- 杂志(Magazines)
- 职业/技能奖励(Professions/Perks)
- Lua 代码动态注入(参见 8.3)

### 8.2 AutoLearnAll / AutoLearnAny

```lua
AutoLearnAll = Carving:5;Woodwork:3,   -- 两个技能都达到等级时自动学会
AutoLearnAny = Woodwork:5;MetalWelding:3, -- 其中之一达到等级时自动学会
```

格式:多个技能用 `;` 分隔,`技能:等级`。

### 8.3 MetaRecipe

链接到另一个配方 — 学会 Meta 即学会主配方:

```lua
MetaRecipe = SomeBaseRecipe,
```

### 8.4 模块机制

B41/B42 中物品来源的 `module` 字段也使用 module 名称作为命名空间。在制作中 module 主要影响:

- 配方的归属
- 在制作菜单中按模块筛选
- 翻译文件中可能的命名空间前缀(取决于游戏实现)

> Wiki 没有把 Module 作为独立页面,module 系统的具体 API 主要散落在 `Item`、`Recipe` 等脚本页面中。

---

## 9. 特殊属性快速对照表

| 行为 | B41 字段 | B42 等价 |
|------|----------|----------|
| 允许已损坏物品作原料 | `AllowDestroyedItem:true` | `flags[AllowDestroyedItem]` |
| 允许冰冻物品 | `AllowFrozenItem:true` | (B42 暂未文档化) |
| 允许腐烂物品 | `AllowRottenItem:true` | (B42 暂未文档化) |
| 不返还产出物 | `RemoveResultItem:true` | (B42 暂未文档化) |
| 地面直接制作 | `CanBeDoneFromFloor:true` | `Tags = ...;CanBeDoneFromFloor` |
| 必须学习 | `NeedToBeLearn:true` | `needToBeLearn = true` / `needTobeLearn = true` |
| 必须附近有某物 | `NearItem:Workbench` | (B42 暂未文档化) |
| 隐藏配方 | `IsHidden:true` | (B42 暂未文档化) |
| 走路时不可做 | `StopOnWalk:true` | (B42 暂未文档化) |
| 跑步时不可做 | `StopOnRun:true` | (B42 暂未文档化) |
| 温度要求 | `Heat:-0.22` | (B42 暂未文档化) |
| 覆盖原配方 | `Override:true` | (B42 不支持) |
| 移除原配方 | `Obsolete:true` | (B42 不支持) |

---

## 10. 关键经验要点

1. **B42 与 B41 字段语法完全不同**:
   - B41 用 `属性:值` (冒号)
   - B42 用 `属性 = 值` (等号) + 嵌套块(`inputs {}` `outputs {}`)
2. **`Tags` 必填且必须含工作台标签**:`AnySurfaceCraft` 最常用
3. **`mode:keep` / `mode:destroy`** 取代了 B41 的 `keep` / `destroy` 前缀
4. **`flags[]` 列表取代 B41 散落的 `AllowXxx` 字段**(部分字段)
5. **`itemMapper` / `overlayMapper`** 是 B42 新机制,允许按输入物类型动态选择产出物
6. **液体使用 `-fluid` 前缀**,单位为升
7. **Lua 钩子签名**(OnCreate/OnTest/OnCanPerform/OnGiveXP)在 B41/B42 之间基本保持兼容
8. **修改现有配方在 B42 受限**:只能加 `itemMapper` / `overlayMapper`,或通过 `ScriptManager:getCraftRecipe()` Lua API 操作
9. **学习配方**:`needToBeLearn = true` + `AutoLearnAll` / `AutoLearnAny` 组合,或 `MetaRecipe`
10. **翻译键**:`Recipe_<RecipeID>` 在 `media/lua/shared/Translate/<LANG>/Recipe.json` (B42.15+ JSON 格式)

---

## 11. 仓库内真实代码案例(bin2_extension 跨版本演进)

仓库内 `bin2_extension` 模组同时保留 B41 / B42 两版 Recipes.txt,可作为活的对照样本。

**B41 旧式** — `bin2_extension/42.15.0/media/scripts/Recipes.txt`:
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

**B42 新式** — `bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt`:
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

**演进对照:**

| 维度 | 42.15.0 (B41) | 42.19.0 (B42) |
|------|--------------|---------------|
| RecipeID | `DisassembleCrudeWoodenTongs` | `Bin2DisassembleCrudeWoodenTongs` (加 mod 前缀) |
| 字段语法 | `属性:值` | `属性 = 值` |
| 原料写法 | `CrudeWoodenTongs,` 简写 | `item 1 [CrudeWoodenTongs]` 显式 |
| 产出写法 | `Result:WoodenStick=2,` | `outputs { item 2 Base.WoodenStick, }` |
| 工作台条件 | (无) | `Tags = AnySurfaceCraft,` |
| 经验钩子 | `OnGiveXP:Recipe_GiveXP` | (B42 应补 `OnCreate = Recipe.OnCreate.XXX`) |
| Time 字段 | `Time:5.0` | (本文件省略,应补 `time = 5`) |
| category | (无) | `category = Cooking` |

> ⚠️ 注意:42.19.0 文件缺 `time` 与 `OnCreate`,实际游戏内可能会以默认 time=50 触发,经验不发放 — 建议补全。

---

## 12. 进阶:B42 Wiki 未明确文档化的字段

下列字段在 B41 Wiki 中存在,但 B42 Wiki 暂未明确文档化,需要源码验证(留作后续 TODO):

| 字段 | B41 用法 | B42 现状 |
|------|----------|----------|
| `Heat` | `Heat:-0.22` 温度要求 | B42 未文档化 |
| `StopOnWalk` | 走路时不可做 | B42 未文档化 |
| `StopOnRun` | 跑步时不可做 | B42 未文档化 |
| `IsHidden` | 隐藏配方 | B42 未文档化 |
| `RemoveResultItem` | 不返还产出 | B42 未文档化 |
| `NearItem` | 附近需有物 | B42 未文档化 |
| `AllowFrozenItem` | 允许冰冻物品 | B42 未文档化 |
| `AllowRottenItem` | 允许腐烂物品 | B42 未文档化 |
| `Override` | 覆盖原配方 | B42 不支持(需用 Lua API) |
| `Obsolete` | 移除原配方 | B42 不支持(需用 Lua API) |

> 实战建议:遇到这些需求时,先在 `media/scripts/recipes/*.txt` 跑一次加载测试,确认是否仍被 B42 引擎识别。

---

## 13. 参考链接(真实引用地址)

- PZWiki CraftRecipe (B42): <https://pzwiki.net/wiki/CraftRecipe> (oldid=1263201)
- PZWiki Recipe (B41): <https://pzwiki.net/wiki/Recipe_(scripts)> (oldid=874781)
- PZWiki Item: <https://pzwiki.net/wiki/Item>
- PZWiki EvolvedRecipe: <https://pzwiki.net/wiki/EvolvedRecipe>
- PZWiki Fluid: <https://pzwiki.net/wiki/Fluid>
- Wiki 导航目录: <https://pzwiki.net/wiki/Modding> (Scripts 章节)
- 抓取备份(用于 Cloudflare 拦截时): <https://web.archive.org/web/2025/https://pzwiki.net/wiki/CraftRecipe>
