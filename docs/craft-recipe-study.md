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

> ⚠️ 容器类 flag 的实测差异(见 13.2):对装了液体的容器,**只有 `IsEmpty` / `IsFull` 生效**,
> `NotEmpty` 是空操作 —— "锅里必须先装满液体" 这类需求不能靠 `NotEmpty` 表达。

### 3.5 液体输入

```lua
-fluid 1.0 [Petrol],
-fluid <升数> [<FluidID>],
-fluid 0.5 categories[Water] mode:mixture,   -- 按类别 + 匹配模式(B42 常用写法)
```

- 用 `-fluid` 前缀(不是 `item`)
- 数量单位是升(可以为小数)
- `mode:` 取值 `exact` / `primary` / `mixture` / `anything`(枚举来源见 13.3)
- 液体**不必**装在同一条 `inputs` 里列出的容器中(见 13.1)

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

**B42 新式** — `bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt`(v1.6.2 现状):
```lua
module Bin2Recipe
{
    craftRecipe Bin2DisassembleCrudeWoodenTongs
    {
        time = 5,
        timedAction = Making,
        Tags = InHandCraft;CanBeDoneFromFloor,
        category = Cooking,
        inputs
        {
            item 1 [Base.CrudeWoodenTongs],
        }
        outputs
        {
            item 2 Base.ShortBat,
            item 1 Base.RippedSheets,
        }
    }
}
```

**演进对照:**

| 维度 | 42.15.0 (B41) | 42.19.0 (B42) |
|------|--------------|---------------|
| RecipeID | `DisassembleCrudeWoodenTongs` | `Bin2DisassembleCrudeWoodenTongs` (加 mod 前缀) |
| 字段语法 | `属性:值` | `属性 = 值` |
| 原料写法 | `CrudeWoodenTongs,` 简写 | `item 1 [Base.CrudeWoodenTongs]` 显式 |
| 产出写法 | `Result:WoodenStick=2,` | `outputs { item 2 Base.ShortBat, }` |
| 工作台条件 | (无) | `Tags = InHandCraft;CanBeDoneFromFloor` |
| Time 字段 | `Time:5.0` | `time = 5`(v1.6.1 起已补,此前缺失会落到默认值) |
| category | (无) | `category = Cooking` |

> 说明:这段 B42 代码在 v1.6.1 之前缺 `time`、且引用了不存在的物品 ID(`Base.WoodenStick`/`Base.Rag`),
> 现在已修好;要复核任何一条配方到底被引擎解析成什么,用 `bin2_b42/tools/recipe_probe`(见 13 节)。

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

## 13. 引擎实测补充(用游戏自带解析器核实)

> 来源:本机安装的 `Project Zomboid.app/Contents/Java/projectzomboid.jar`(B42 42.19.0)反编译 +
> 仓库工具 `bin2_b42/tools/recipe_probe`(headless 跑 `ScriptManager.Load()`,逐行打印引擎的解析结果)。
> 下面每条都是**引擎自己解析出来的**,不是 Wiki 转述;类名/方法名即证据。

### 13.1 `-fluid` 的水**不一定**来自 inputs 里那只锅

`zombie/scripting/entity/components/crafting/InputScript.isFluidMatch(FluidContainer)` 说明流体需求是
拿"上下文里能拿到的 FluidContainer"去匹配的(`CraftRecipeManager.consumeInputFluid(InputScript, List<Resource>, …)`),
不是绑在某个 item 输入上。原版可作反证:

```lua
-- recipes_cooking.txt / MakeGravy:碗必须是空的,却要 1 升水
item 1 [Base.Bowl;Base.ClayBowl] mode:keep flags[IsEmpty],
-fluid 1.0 categories[Water] mode:mixture,
```

碗 `flags[IsEmpty]`(必须无液体)与 `-fluid 1.0`(必须消耗 1 升)同时成立 ⇒ 水只能来自**附近别的容器**
(背包里的水瓶、雨水桶……)。实践含义:

- 想要求"锅里得有卤水",光靠 `-fluid` 不行,还得配 Lua 校验;
- 反过来,`-fluid` 是**防刷**的关键:没有 `-fluid` 行的"蒸发法"等于凭空产盐。

### 13.2 `flags[NotEmpty]` 对装液体的容器是空操作

`InputFlag` 全量枚举(`zombie/entity/components/crafting/InputFlag`):`HandcraftOnly / AutomationOnly /
IsFull / NotFull / ItemIsUses / ItemIsFluid / ItemIsEnergy / IsEmpty / NotEmpty / Prop1 / Prop2 / ToolLeft /
ToolRight / IsDamaged / IsUndamaged / IsWholeFoodItem / IsEmptyContainer / IsUncookedFoodItem /
IsCookedFoodItem / IsNotDull / IsHeadPart / IsSharpenable / DontPutBack / InheritColor / InheritCondition /
InheritEquipped / InheritSharpness / InheritHeadCondition / MayDegrade / MayDegradeLight / MayDegradeVeryLight /
MayDegradeHeavy / SharpnessCheck / InheritUses / InheritUsesAndEmpty / InheritFood / InheritFoodAge /
InheritCooked / InheritModelVariation / InheritWeight / InheritName / InheritFreezingTime / DontInheritCondition /
AllowFrozenItem / AllowRottenItem / NoBrokenItems / AllowDestroyedItem / IsWorn / IsNotWorn / InheritAmmunition /
CopyClothing / AllowFavorite / InheritFavorite / FakeOutput / DontReplace / CanBeDoneFromFloor / ItemCount /
IsExclusive / RecordInput / DontRecordInput / ResearchInput / IsBlunt / HasOneUse / HasNoUses / IsSealed /
IsNotSealed / Unseal / EquipSecondary / SetActivated`。

但 `InputScript.doesItemPassIsOrNotEmptyAndFullTests(InventoryItem)` 里,**FluidContainer 分支只判定
`IsFull` 与 `IsEmpty`**,`NotEmpty` 只在 `DrainableComboItem`(手电/打火机等"使用次数"物品)与
`Radio`/`WeaponPart` 分支里判定。结论:

| 写法 | 对"锅/桶/瓶"这类液体容器 |
|------|--------------------------|
| `flags[NotEmpty]` | **不生效**(永远通过) |
| `flags[IsEmpty]` | 生效:必须**没有**液体 |
| `flags[IsFull]` | 生效:必须装满 |

所以老的 `item 1 [Base.Saucepan] mode:keep flags[Prop1;NotEmpty;ItemCount]` 里"需要装满液体的锅"
只是注释/更新日志里的一厢情愿,引擎没这么判。

### 13.3 mode 与流体模式枚举值

- `zombie/entity/components/crafting/ItemApplyMode`:`Normal` / `Keep` / `Destroy` ⇒ `mode:keep`、`mode:destroy`
- `zombie/entity/components/crafting/FluidMatchMode`:`Exact` / `Primary` / `Mixture` / `Anything`
  ⇒ `-fluid 0.5 categories[Water] mode:mixture` 中的 `mode:mixture` = 容器里可以是含水的混合液
- `-fluid` 的筛选既可以写 `[Water;TaintedWater]`(`FluidKey`),也可以写 `categories[Water]`
  (`FluidCategory`);原版 `media/scripts/generated/fluids.txt` 里 `Water` 与 `TaintedWater` **同属
  `Water` 类别**,所以 `categories[Water]` 水/污染的水都吃(`CarbonatedWater` 也在内)

### 13.4 解析结果里看不到流体行,不代表流体没生效

`CraftRecipe.getInputs()` 只返回 item 输入,流体行在 private 字段 `ioLines`(`ArrayList<IOScript>`)里 ——
校验脚本时用 `getInputs()` 会误判"`-fluid` 被吃掉了",要看 `ioLines`(探针已用反射读它)。

### 13.5 原版可当"卤水锅"的锅具(以及没有通用 tag)

`media/scripts/generated/items/*.txt` 实测(有 `component FluidContainer` 且 `IsCookable = true`):

| 物品 | 游戏内中文名 | 容量 | 标签 |
|------|------|------|------|
| `Base.Saucepan` | 平底煮锅 | 0.6 L | `base:cookable;base:hasmetal;…` |
| `Base.SaucepanCopper` | 铜平底煮锅 | 0.6 L | `base:cookable;base:hasmetal;…` |
| `Base.Pot` | 蒸煮锅 | 1.5 L | `base:cookable;base:hasmetal;…` |
| `Base.PotForged` | 粗制蒸煮锅 | 1.5 L | `base:cookable;base:hasmetal;…` |
| `Base.Kettle` | 水壶 | 1.5 L | `base:cookable;base:hasmetal;…` |
| `Base.Kettle_Copper` | 铜制水壶 | 1.5 L | `base:cookable;base:hasmetal;…` |
| `Base.Bucket` 等金属桶 | 金属桶 | 10 L | `base:bucket;base:cookable;…` |

> 写用户可见文案时**必须**照抄这里的"游戏内中文名"(来源:`media/lua/shared/Translate/CN/ItemName.json`)。
> 我自己起过名 —— 把 `Base.Pot` 写成"炖锅"、`Base.Kettle_Copper` 写成"铜水壶",玩家在游戏里根本搜不到
> 这两个词,是小红书运营按 `manifest.json` 的 `cn` 字段核对时才发现的。

`Base.RoastingPan` / `Base.BakingPan` / `Base.BakingTray` / `Base.MuffinTray` 带 `base:cookable` 但
**没有 FluidContainer**,装不了水。且**没有**"锅具"专用 tag:`base:cookable` 在原版命中 115 个物品
(威士忌瓶、汽水罐、香水都在内),所以"更通用的锅具"只能用显式 fullType 列表,不能用 `tags[base:cookable]`。

### 13.6 本次落地

`bin2_extension` 的 `Bin2MakeSalt` 按 13.1~13.5 改成(见 `bin2_b42/Contents/mods/bin2_extension/42.19.0/`)：

```lua
item 1 [Base.Saucepan;Base.SaucepanCopper;Base.Pot;Base.PotForged;Base.Kettle;Base.Kettle_Copper] mode:keep flags[ItemCount],
-fluid 0.5 categories[Water] mode:mixture,
item 1 [Base.Charcoal;Base.CharcoalCrafted;Base.Coke],
outputs { item 1 Base.Salt, }   /* 锅具 keep,不再重复产出 */
```

探针输出:`keep=true itemCount=true` + `IN [Fluid] fluid 0.5 categories[Water] mode:mixture (fluidMode=Mixture amount=0.5)`
+ 6 个锅具 fullType 全部解析成功。

---

## 14. 原版配方缺口扫描(969 条 craftRecipe 的结论)

第 13 节是"单条配方怎么被引擎解释",这一节是"整个原版配方体系缺了什么"。
结论来自 `bin2_b42/tools/recipe_gap/scan_recipe_gaps.py`,数据全部取自游戏自带脚本,
没有任何猜测成分,命令见 14.7。

### 14.1 判据:什么叫"缺配方"

最容易走偏的是"没有配方的物品"这个说法。Build 42.21 原版脚本解析出 **5079 个物品**,
其中绝大多数本来就不该有配方(衣服、书籍、罐头、车辆零件……)。真正可判定、可复现的缺口是:

> **被某条 craftRecipe 当作材料消耗,却没有任何机制能产出它。**

两侧的判定细节:

| 侧 | 算什么 | 不算什么 |
|---|---|---|
| 消耗侧 | `inputs` 里 `item N [...]` 提到的物品 | `mode:keep` / `flags[Prop1\|Prop2\|ToolLeft\|ToolRight]` 的工具位(锤子、金属加工凿、金属加工钳/夹钳这类只是被拿在手里) |
| 产出侧 | craftRecipe 的 `outputs` 直接产出;`itemMapper` 的**键**(`输出 = 触发它的输入`);`evolvedrecipe` 的 `ResultItem`;拆家具 `ISMoveableDefinitions` 的 `addScrapItem`;采集表 `Foraging/**` | 只是"能拿到"的容器/箱子内容物(战利品,不是产出) |

按这个判据,42.21 的分布是:

| 分类 | 数量 | 含义 |
|---|---|---|
| 被当材料消耗 | 1800 | 出现在材料位 |
| 被当工具使用 | 1101 | 只出现在 Prop/Tool 位 |
| 有配方产出 | 1622 | outputs / mapper 键 / evolvedrecipe 命中 |
| 世界来源 | 1817 | 拆家具或采集能拿到 |
| 有可产出替代品 | 772 | 同 tag 家族里有别的成员造得出来(如 `base:thread` 家族) |
| **真缺口(只能搜刮)** | **379** | 上面几条都不沾 |
| 有世界来源的材料 | 315 | 无配方可行,但拆家具/采集能拿(不算堵死) |
| 有替代品的材料 | 139 | 无配方可行,但同族有替代品 |
| 做得出没人用 | 370 | 有产出、无消耗(成品居多,**不是**缺口) |

> 这组数字在 2026-10-13 修正过一次:早先的 1909 / 1218 / 1614 / 389 / 317 把 `flags[...]`、
> `mappers[...]` 里的枚举名当成了物品 ID(同时漏掉了写成 `Base.X flags[...]` 的真物品),
> 根因与修法见 14.10。**表里这组是修正后的值**;`Base.NutsBolts` 33 条、圆锯片 11 条这类
> 逐个物品的结论没有变(那批物品恰好都没踩到方括号/小数那几种写法)。

"做得出没人用"和"完全没配方"这两类都被明确排除:前者是设计(做出来就是拿来用的),
后者是搜刮设计。

### 14.2 本次补的 6 项(按被消耗条数排序)

| 物品 | 消耗它的配方数 | 产出途径 | 世界来源 | 处理 |
|---|---|---|---|---|
| `Base.NutsBolts` 螺母与螺栓 | **33** | 无 | 拆家具(Fridge / MetalPlates / MetalPlatesAndBars / SmallMetalPlates) | ✅ 新增 |
| `Base.CircularSawblade` 圆锯片 | **11** | 无 | 无(真缺口榜首) | ✅ 新增 |
| `Base.Screws` 螺丝 | **10** | 只有 `OpenBox100`(开箱,属战利品) | 拆家具 5 处 + 采集 Trash | ✅ 新增 |
| `Base.Glue` 胶水 | **9** | 无 | 采集(Trash.lua) | ✅ 新增 |
| `Base.HacksawBlade` 手锯条 | **3** | 无 | 无 | ✅ 新增 |
| `Base.SmallSawblade` 小手锯条 | **3** | 无 | 无 | ❌ 与手锯条功能重复,不做 |

也就是说:原版有 33 条配方要螺母螺栓、11 条要圆锯片,而这些物品**一条制作路径都没有**,
只能靠拆家具或搜刮。这是本次新增的真正理由,和"某物品没配方"完全不是一回事。

### 14.3 被排除的假阳性(确认过,不是缺口)

- `Base.Charcoal` 木炭:`MakeCoke` 产 `Base.Coke`,土窑产 `Base.CharcoalCrafted`,配方同时接受三者。
- 线/线团家族:`SpinThreadFromFlax` / `SpinThreadFromWool` 可造,且 `base:thread` 家族 6 个成员可互换。
- `Base.Button` 纽扣:`producibleSiblings` 命中 `Base.BoneBead_Large`(可造),可替代。
- 坩埚类:`FireCeramicCrucible` 等有完整制作链。
- `Base.SheetMetal` / `Base.SmallSheetMetal`:由 `evolvedrecipe` 产出(第 14.5 节的工具识别到了)。
- 鱼/电子/带状态物品(`CandleLit`、`GardeningSprayEmpty`、`MetalPipe_Broken` 等):缺的不是配方,是状态链。
- 火柴/打火机:原版刻意的搜刮物品,配方体系里当"火源"用,补制作会破坏前期节奏。
- 武器刀刃(`Base.KillerBlades`、`*_NoTang`):锻造链已有,补配方会破坏 Blacksmith 平衡。

### 14.4 安全约束:不许造出材料泵

补配方时必须逐条检查"能不能用这条配方把材料变多",否则就是刷物品后门。这次的三条依据:

1. **螺母螺栓不可回炉**:`Base.NutsBolts` 的 tags 只有 `base:hasmetal`,没有 `base:smeltable*`,
   所以"1 金属块 → 6 螺母螺栓 → 回炉"这条路不存在。
2. **圆锯片与回炉持平**:`ExtractSteelFromLargeItem` = 1 个 `base:smeltablesteellarge` 物品 + 9 木炭 + 坩埚 + 夹钳 → **4 SteelChunk**;
   `Forge_Steel_Sheet` = 1 SteelBlock(4 chunks 合成) + 木炭 → 1 `Base.SheetMetal`。
   于是 1 金属板 ≈ 4 钢块,而"2 木炭 + 1 金属板 → 1 圆锯片"恰好是材料中性 ——
   既补上了 11 条配方缺的料,又不构成"1 块钢刷出无限锯片"。
   反面例子(明确否决):曾经想把圆锯片改成"1 金属块直接锻打",那才是材料泵。
3. **螺丝产量低于回炉门槛**:`SmeltSmallerSteelItem` 要 **10** 个小件才出 1 钢块,
   而 `Bin2MakeScrews` 一次出 6 个,不够回炉,不构成循环。

### 14.5 一个引擎事实:craftRecipe 里没有"需要火源"这种字段

`javap -p zombie.scripting.entity.components.crafting.CraftRecipe` 显示,配方里唯一的"外部条件"
槽位就是 `prop1 / prop2 / toolLeft / toolRight` 加上 `inputs` —— **没有** heat / fire / near 之类字段。
"要在灶上做"这件事由烹饪系统(物品的 cook 状态、灶台实体)负责,不在 craftRecipe 里。
所以锅具类配方(制盐、熬胶)不可能写成"必须放在火上",只能写成"锅 + 水 + 热源材料(木炭)"。
熬胶配方里没有木炭,是因为骨头熬胶的火候在 240 秒的 `timedAction = Making` 里体现,
而不是靠额外消耗一个木炭 —— 这条取舍是刻意的,写在这里以免后人以为是漏写。

### 14.6 本次落地的 5 条配方

见 `bin2_b42/Contents/mods/bin2_extension/42.19.0/media/scripts/recipes/bin2_Recipes.txt`:

```lua
/* 熬胶: 骨头 + 水 (原版只有搜刮/采集, 却有 9 条配方需要胶水) */
Bin2MakeGlue        : 2 骨头 + 1 锅具 + 1 升水            → 2 胶水     (Cooking:2)
/* 打造螺母与螺栓: 原版只能拆家具得到, 却有 33 条配方需要 (螺栓不可回炉) */
Bin2MakeNutsBolts   : 1 木炭 + 1 金属料 + 锤子 + 金属加工钳或夹钳 → 6 螺母螺栓 (MetalWelding:1)
Bin2MakeScrews      : 1 木炭 + 1 金属料 + 锤子 + 金属加工钳或夹钳 → 6 螺丝     (MetalWelding:1)
Bin2MakeCircularSawblade : 2 木炭 + 1 金属板 + 锤子 + 金属加工凿 + 金属加工钳或夹钳 → 1 圆锯片 (MetalWelding:2)
Bin2MakeHacksawBlade     : 1 木炭 + 1 小金属板 + 锤子 + 金属加工凿          → 2 手锯条 (MetalWelding:2)
```

工具/锅具一律 `mode:keep`(制作后原样保留);`category` 用原版真实存在的技能名
(MetalWelding / Cooking —— 原版**没有** "Metalworking" 技能,Metalworking 只是分类名)。

### 14.7 复现
```bash
# 缺口扫描(可加 --json gaps.json / --top 80 / --lang CN)
python3 bin2_b42/tools/recipe_gap/scan_recipe_gaps.py --top 40

# 用游戏自带解析器离线校验配方脚本(必须 ALL RECIPES PARSED 且退出码 0)
./bin2_b42/tools/recipe_probe/run.sh

# 仓库级校验(物品 ID 真实性 + 翻译 JSON)
python3 -m mod_dependency_analyzer.validate_recipes --root ./bin2_b42
```

坑:探针会提示"3 个 fullType 查不到",那是 `Bin2MakeEpoxy` 引用的 `LabItems.*`(来自另一个 mod)——
探针不加载 mod,跨 mod 引用被判为未知属正常;原版物品里出现未知 fullType 才是拼写错误。

### 14.8 顺带挖到:物品图标藏在贴图包里(PZPK 格式)

写更新公告要画"配方消耗什么、产出什么",需要物品图标。**B42 的物品图标没有独立 png 文件**:
`media/textures/` 下只有世界模型贴图(如 `WorldItems/Glue.png`,64x128,那是丢在地上的样子),
真正的物品栏图标打包在 `media/texturepacks/UI.pack`(1.2 MB,老包)与 `UI2.pack`(54 MB)里。
实测出来的格式(两个包都成立):

```
magic "PZPK"                      4 字节;UI.pack 这类老包直接以记录开头
记录 = uint32 名称长度 + 名称 + 8 个 uint32
       x, y, w, h        雪碧图里的裁剪矩形(图标是裁掉透明边之后的)
       offX, offY        画回原尺寸画布时的偏移
       origW, origH      原始画布(物品图标通常 32x32)
页码 = 该记录之后最近的那个 PNG —— 每张雪碧图前面紧跟着它自己的名称表
       (PNG 数据是内嵌在 .pack 里的,不是旁边的独立文件)
```

关键坑:① 图标名**不等于物品 ID**,要读物品脚本的 `Icon = X`,再找 sprite `Item_X`
(例:`Base.HacksawBlade` 的 `Icon = Sawblade` → sprite `Item_Sawblade`;
`Base.AnimalBone` 的 `Icon = Bone` → `Item_Bone`);② 名称表按页分散在包里,
`UI2.pack` 里 `Item_NutsBolts` 在第 3 张雪碧图上、`Item_Bone` 在第 1 张上,
所以"先解析整张表再查"很慢(逐字节扫 54 MB),按名字用 `bytes.find` 定向查找快一个数量级;
③ 大小标签不一致的图标是同一物品的不同档(`Item_MetalSheetSmall` 与 `Item_MetalSheet_Small` 都在)。

工具:`bin2_b42/tools/pz_atlas/extract_item_icons.py`(用法与依赖见该目录 README)。
用它给 `bin2_Recipes.txt` 里出现的全部物品导过 45 个图标,总览图在
`docs/xhs/游戏图标素材/图标总览.png`。

### 14.9 临时 grep 才会踩的坑:包含判断会假阳性

复核结论时最容易脱口而出的一句是"我在 outputs 里 grep 到了它,所以它有产出"。**别这么判**。

反例(实测):`Base.CircularSawblade` 与 `Base.CircularSawblade_Half` 是**两个物品**,后者以前者为前缀。
`recipes_metalWelding.txt:120` 的 `CutCircularSawblade` 与 `:164` 的 `SawCircularSawblade` 都是
`inputs { item 1 [Base.CircularSawblade] }` + `outputs { item 2 Base.CircularSawblade_Half }` ——
它们**消耗**圆锯片、产出半片。可一句 `grep Base.CircularSawblade` 会把 outputs 里的
`Base.CircularSawblade_Half` 也算成命中,于是得出"圆锯片有产出"的错误结论(而且方向正好相反:
把真缺口判成不缺口)。

规矩:**匹配物品 ID 必须精确**(正则 `ID(?=[\s,;\]\n]|$)`),不要用 `in` / 子串包含。
`scan_recipe_gaps.py` 是按物品 ID 建索引后比较的,不受这个影响;会踩的是"顺手 grep 复核一遍"的人,
所以写在这里。

### 14.10 扫描器自己踩的坑:方括号不止一种、数量可能是小数

14.1 的数字在 2026-10-13 修正过一次(消耗 1909 → 1800、真缺口 389 → 379)。
起因是运营复核一篇笔记时发现"她自己数出 7 条配方消耗盐,而扫描器说 6 条"——
**是扫描器错了,不是她错**。两个解析 bug,都在 `inputs`/`outputs` 的行匹配上:

1. **数量写成小数就整行丢掉**。`ITEMREF_RE` 原来是 `item\s+(\d+)\s+`,而原版有 3 行写成
   `item 1.0` / `item 2.0` / `item 5.0`,于是 `MakeJar`(`recipes_jarring.txt:49-50`,
   消耗 2.0 醋 + 1.0 `[Base.Salt;Base.SeasoningSalt]` + 1 个 `[*]`)整行没被看见 →
   `Base.Salt` 少算 1 条(算成 6,实际 7)、`Base.SeasoningSalt` 同样少 1 条(算成 5,实际 6)。
   修法:数量正则改成 `\d+(?:\.\d+)?`,读出来是浮点,整数就还原成 int。
2. **方括号有三种,不只是物品列表**。`tags[...]` / `flags[...]` / `mappers[...]` 也带方括号,
   `BRACKET_RE` 找"第一个方括号"就会拿到它们。两种错同时发生:
   - 把枚举名当物品:`item 1 tags[base:glass] flags[ItemCount]` → 解析出"物品 = ItemCount"(假阳性,
     JSON 里塞进 `ItemCount`/`Prop1`/`MayDegradeLight` 这类裸名);
   - **漏掉真物品**:`item 1 Base.HandScytheBlade flags[IsBlunt]` → 解析出"物品 = IsBlunt",
     真正的 `Base.HandScytheBlade` 反而没被算作被消耗(假阴性,危害更大)。
   修法:先 `(?:tags|flags|mappers)\[[^\]]*\]` 全部摘掉再找物品列表;`[*]` 是"任意物品"通配,
   要排除,不能当成物品 ID。

**教训**:脚本读的是"半结构化文本",正则宽松一点就会静默漏行 —— 不漏报错、只少算数。
所以每个新数字都要有一条**独立于脚本**的交叉验证(这次是运营按配方名手数的 7 条),
而且派生的用户可见数字(33/11/10/9/3)要单独复查是否受影响(这次不受影响,因为那 5 个物品
恰好都没踩到这两种写法)。判据侧的交叉验证命令见 14.7。

### 14.11 流体到底被扣多少:扣 amount,不是抽干整锅(字节码证据)

一个曾经只写在更新日志里、没有证据的句子:"制盐后锅内剩下的水还在"。2026-10-13 用字节码把它落实了 ——
**它是对的**,而且顺带解释了两件容易踩的事。

`zombie/entity/components/crafting/recipe/CraftRecipeManager.consumeInputFluidInternal(...)` 的逻辑
(反汇编 `projectzomboid.jar` 得到):

```
amount = InputScript.getAmount();                 // -fluid 0.5 → 0.5
if (cache != null) amount -= cache.fluidConsumed;  // 同一次制作里不重复扣
if (!script.isFluidMatch(container)) return false; // 类别/模式不符 → 输入不成立
float remove = min(amount, max(container.getAmount() - <已计部分>, 0));
if (remove < 1.0E-5f) return false;                // 容器里的量不够 → 这条输入不成立
container.removeFluid(remove, ...);                // 只扣这么多
```

三条可用的结论:

1. **只扣配方要求的量,不抽干整锅**。1.5 升的蒸煮锅里有 1 升水,做一次盐剩下 0.5 升;
   `mode:mixture` 只影响"匹配"(容器里可以是混合液),**不影响扣多少** —— 扣多少由 `amount` 决定。
2. **水不够就做不了**(`remove < 1e-5` 直接 `return false`)。0.6 升的平底煮锅装 0.5 升够用,
   只剩 0.4 升时这条配方不成立。**引擎只认"够不够",不关心 0.5 还是 0.6** —— 0.5 是我们选的数,
   唯一受约束的是上限:不能超过最小锅的 0.6 升,否则小锅做不了(这是设计取舍,不是引擎结论)。
3. `CacheData.fluidConsumed` 让一次制作里重复的扣除互相抵消,所以"同一条配方写两行 `-fluid`"
   不等于扣两次。

复核命令(本机 42.21 安装包):

```bash
JAR="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/projectzomboid.jar"
WD=$(mktemp -d); unzip -q "$JAR" 'zombie/entity/components/crafting/*' -d "$WD"
javap -p -c -cp "$WD" zombie.entity.components.crafting.recipe.CraftRecipeManager \
  | sed -n '/consumeInputFluidInternal/,/^$/p'      # 看 removeFluid 前后
```

### 14.12 用翻译文件当"配方考古"的线索:甜菜→糖 这条链原版没做完

14.1 的扫描只能证明"**今天**没有配方能产出它"。要证明"这是原版没做完,而不是设计如此",
有一条**独立于脚本**的旁证:**翻译文件里还留着配方的名字,而脚本里已经没有那条配方**。

实测(B42 42.21,`media/lua/shared/Translate/*/Recipes.json`;翻译覆盖并不整齐,按实测写):

| 配方键(只有译名,没有脚本) | 游戏内中文名 | 有译名的语言数 |
|---|---|---|
| `PulpSugarBeets` | 压榨甜菜 | 25 / 29 |
| `StrainCookedSugarBeetPulp` | 过滤煮熟的甜菜渣 | 25 / 29 |
| `CollectSugarBeetSugar` | 收集甜菜糖 | **29 / 29(全部语言)** |

缺这两个键的语言是 `AR` / `NL` / `PT` / `UA` —— 说明译名层本身也是"没跟上"的遗留,
进一步支持"这几条配方是半途而废的"。**我第一版写成"28 种语言都有",是估的、不是数的**
(过程改进组长实测后指出,这里已按实测修正 —— 数字必须来自测量,不能来自印象)。

同一层的两个中间物品也只剩定义、没人引用:`Base.SugarBeetPulpPot`(甜菜渣锅)、
`Base.SugarBeetSyrupPot`(甜菜糖浆锅)——**没有任何 `inputs`/`outputs`/`itemMapper`/`evolvedrecipe` 提到它们**。

于是整条链的现状是:`base:sugar` 五个成员(`Sugar` 糖 / `SugarBrown` 红糖 / `SugarPacket` 小袋糖 /
`SugarCubes` 方糖 / `SugarBeetSugarPot` 蒸煮锅(甜菜糖))**没有一个能造出来**,而 7 条烘焙配方
(蛋糕面糊、各种饼干面团……)靠 `tags[base:sugar]` 取糖;方糖与"蒸煮锅(甜菜糖)"连拆家具/采集都查不到
(方糖在战利品表里出现)。也就是说 **甜菜→渣→糖浆→糖 这条链在 42.21 只剩名字**。

核对命令(注意:**配方名要精确匹配**,用包含判断会把 `Recipes.json` 里的别的键也命中):

```bash
G="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/media"
for n in CollectSugarBeetSugar PulpSugarBeets StrainCookedSugarBeetPulp; do
  grep -rl "$n" "$G/scripts" "$G/lua" | grep -v /Translate/    # 期望:无输出
  printf "%s 有译名的语言数 = %s\n" "$n" "$(grep -rl "\"$n\"" "$G"/lua/shared/Translate/*/Recipes.json | wc -l | tr -d ' ')"
done
ls -d "$G"/lua/shared/Translate/*/ | wc -l                          # 语言目录总数(29)
```

**方法上的意义**:翻译文件是**比脚本更慢变的一层**。脚本里"找不到"有两种可能——设计如此,或者
做了又删/没做完;而译名残留能把后者挑出来。以后遇到"某物品没有产出路径",除了扫脚本,
值得再查一遍它的**译名键**在不在(在 = 原版曾经有这条配方,补它属于"补完原版"而非"加私货")。
注意这只是**旁证**,不能单独下结论(译名也可能是废弃文案),要和 14.1 的扫描一起看。

---

## 15. 参考链接(真实引用地址)

- PZWiki CraftRecipe (B42): <https://pzwiki.net/wiki/CraftRecipe> (oldid=1263201)
- PZWiki Recipe (B41): <https://pzwiki.net/wiki/Recipe_(scripts)> (oldid=874781)
- PZWiki Item: <https://pzwiki.net/wiki/Item>
- PZWiki EvolvedRecipe: <https://pzwiki.net/wiki/EvolvedRecipe>
- PZWiki Fluid: <https://pzwiki.net/wiki/Fluid>
- Wiki 导航目录: <https://pzwiki.net/wiki/Modding> (Scripts 章节)
- 抓取备份(用于 Cloudflare 拦截时): <https://web.archive.org/web/2025/https://pzwiki.net/wiki/CraftRecipe>
- 引擎侧证据(本机 B42 42.19.0 安装包,随时可复核):
  - `projectzomboid.jar` → `zombie/scripting/entity/components/crafting/InputScript`(`doesItemPassIsOrNotEmptyAndFullTests`、`isFluidMatch`)
  - `projectzomboid.jar` → `zombie/entity/components/crafting/{InputFlag,ItemApplyMode,FluidMatchMode}`
  - `projectzomboid.jar` → `zombie/scripting/ScriptManager`(`Load`、`getCraftRecipe`)、`zombie/scripting/entity/components/crafting/CraftRecipe`(`ioLines`)
  - 原版脚本: `<游戏>/media/scripts/generated/{items/*.txt,fluids.txt,recipes/recipes_cooking.txt}`
  - 仓库工具: `bin2_b42/tools/recipe_probe`(headless 跑引擎解析器)、
    `bin2_b42/tools/recipe_gap`(全量配方缺口扫描,数据见第 14 节)
