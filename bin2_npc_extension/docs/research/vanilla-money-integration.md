# 纯原版钞票（`Base.Money`）经济接入报告 — 面向 `Bin2NPCExtensionVanilla`

> 目的：为公共层 `Bin2NPCExtensionCore.Economy` 找出**不依赖任何上游经济模组**、只用原版钞票物品
> （`Base.Money` / `Base.MoneyBundle`）实现 `available / balance / pay / refund` 的全部事实依据。
>
> **只读分析**：本报告未修改 `bin2_npc_extension` 下任何模组源码，只新增本文件。
>
> **环境事实**（`~/Zomboid/console.txt`）：
> `LOG  : General      f:0> version=42.21.0 4a0e9546ec demo=false` ⇒ 与模组目录 `42.21/` 一致。
> 游戏安装根（下称 `$G`）= `/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java`
>
> **路径约定**：
> - `lua/....lua:行号` 一律相对 `$G/media/lua/`；
> - `scripts/....txt:行号` 一律相对 `$G/media/scripts/`；
> - `ItemContainer.java:N` 之类指 `javap -p -c` 反汇编输出的**偏移/行号**，命令随文给出；
> - 反汇编工具：`~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap`
>   （jar 是 Java 25 / class 主版本 69，低版本 `javap` 会报 `class file has wrong version 69.0`）。

---

## 结论速览

| 我们需要的能力 | 纯原版落点 | 评级 | 证据小节 |
|---|---|---|---|
| `Base.Money` 面值 | **1 个 item 实例 = $1**；`Base.MoneyBundle` = $100 | 【稳定】由配方 1→100 保证 | §1 |
| 有没有 `getMoney()` / 计数属性 | **没有**。`Item.Count` 恒为 1、不参与序列化、`canStack` 已死 | 【稳定】= 用不了 | §1.3 |
| `balance(player)` | 遍历 `player:getInventory()` 递归计数 Money/Bundle；**必须额外查 worn 背包** | 【稳定】但 worn 必须自己补 | §2 §6 |
| `available()` | `getScriptManager():FindItem("Base.Money") ~= nil` | 【稳定】 | §5.4 |
| `pay(player, n)` | 服务端 `Remove` 整张钞票 + `RemoveAll` 兜底 + `sendRemoveItemsFromContainer` | 【稳定】有原版先例 | §3 |
| 部分扣除（一张大钞找零） | **不存在**（B42 无堆叠）；必须"拆分/拒绝"策略 | 【必须设计】 | §1.3 §3.4 |
| `refund(player, n)` | `inv:AddItem("Base.Money")` + `sendAddItemToContainer(inv, item)` | 【稳定】有原版先例 | §4 |
| 钱是不是角色属性 | **不是**。`IsoPlayer`/`IsoGameCharacter` 无任何 money 字段 | 【稳定】 | §5.2 |
| SP / 专用服 | 计数与删除在两边都成立；`send*` 在非服务器是**精确 no-op** | 【稳定】 | §6 |
| Kahlua 红线 | `pcall`/`ipairs`/`pairs` 可用，**无 `next`**；Java List 用 `:size()`/`:get(i-1)` 最稳 | 【稳定】 | §7 |

**最关键的一条**（会直接改变实现）：**背包类物品被穿戴（equip）后会从 `player:getInventory()` 里被移除**，
所以 `getCountTypeRecurse` / `getAllTypeRecurse` **不含**玩家背着/穿着的钱袋里的钱。见 §2.3、§6。

---

## 1. `Base.Money` / `Base.MoneyBundle` 的脚本定义与"一个实例值多少钱"

### 1.1 两个物品的完整定义

`scripts/generated/items/normal.txt:8636-8657`：

```
8636:    item Money
8637-    {
8638-        DisplayCategory = Junk,
8639-        ItemType = base:normal,
8640-        Weight = 0.01,
8641-        Icon = Money,
8642-        WorldStaticModel = Money,
8643-        Tags = base:isfirefuel;base:isfiretinder;base:fitswallet,
8644-        FireFuelRatio = 0.25,
8645:    }
8646-
8647:    item MoneyBundle
8648-    {
8649-        DisplayCategory = Junk,
8650-        ItemType = base:normal,
8651-        Weight = 0.5,
8652-        Icon = Money_Stack,
8653-        WorldStaticModel = MoneyBundle,
8654-        Tags = base:ignorezombiedensity;base:isfirefuel;base:isfiretinder,
8655-        FireFuelRatio = 0.25,
8656-        DoubleClickRecipe = UnbundleMoney,
8657:    }
```

**逐字段结论（没有 `Count`、没有 `Stackable`、没有任何 `Money` 数值属性）**：

| 字段 | 值 | 说明 |
|---|---|---|
| `Type` / `module.name` | `base:normal` ⇒ full type `Base.Money`、`Base.MoneyBundle` | `ItemType` 决定走 `normal.txt` 的物品基类 |
| `DisplayName` | **未定义** | 靠翻译键 `ItemName.json`：`lua/shared/Translate/CN/ItemName.json:1065` `"Base.Money": "钞票"`、`:2268` `"Base.MoneyBundle": "捆装钞票"` |
| `Icon` | `Money` / `Money_Stack` | 只是贴图名 |
| `Weight` | `0.01` / `0.5` | 单张发票 0.01lb、一捆 0.5lb（≠100×0.01，可作"捆更轻"的旁证） |
| `Stackable` | **未出现**，且引擎里 `CanStack()` 恒 false | 见 §1.3 |
| `Count` | **未出现** | 见 §1.3 |
| `Money` 相关 tag/属性 | 只有 `firefuel`/`firetinder`/`fitswallet`/`ignorezombiedensity` | **无任何面值语义** |

反证搜索（证明不存在"隐藏的钱数值"）：

```bash
$ cd "$G/media/scripts" && grep -rn "Money" --include=*.txt . | grep -v "generated/items/normal.txt\|generated/models_items.txt"
./generated/recipes/recipes_packing.txt:168:    craftRecipe UnbundleMoney
./generated/recipes/recipes_packing.txt:176:            item 1 [Base.MoneyBundle] flags[AllowFavorite;InheritFavorite],
./generated/recipes/recipes_packing.txt:180:            item 100 Base.Money,
./generated/recipes/recipes_packing.txt:802:   ... item 12 [...;100:Base.Money] ... Base.MoneyBundle = Base.Money,
./generated/items/container.txt:277:    item Bag_MoneyBag
./generated/items/container.txt:1776:    item Briefcase_Money
```

结论：**唯一给出"面值"的地方是配方，不是物品属性**。

### 1.2 面值 = 100:1，由 `UnbundleMoney` 配方单方面给出

`scripts/generated/recipes/recipes_packing.txt:168-182`：

```
168:    craftRecipe UnbundleMoney
169-    {
170-        timedAction = Making,
171-        time = 80,
172-        Tags = InHandCraft;Packing;CanBeDoneInDark,
173-        category = Packing,
174-        inputs
175-        {
176-            item 1 [Base.MoneyBundle] flags[AllowFavorite;InheritFavorite],
177-        }
178-        outputs
179-        {
180-            item 100 Base.Money,
181-        }
182-    }
```

`normal.txt:8656` 的 `DoubleClickRecipe = UnbundleMoney` 让玩家双击钞票捆即可拆开（耗时 80 单位）。
另一个方向（把 100 张钞票捆起来）走的是通用打包配方 `recipes_packing.txt:795-822`：

```
802:            item 12 [Base.RippedSheets;...;100:Base.Money] mode:destroy mappers[itemType] flags[IsFull;...;ItemCount;IsExclusive],
...
822:            Base.MoneyBundle = Base.Money,
```

⇒ **`1 × Base.MoneyBundle ≡ 100 × Base.Money`，`1 × Base.Money ≡ $1`**。

> **未证实点**：这个 100:1 是**配方约定**，不是引擎常量。若将来的原版更新改配方数字，
> 我们的 `BUNDLE_VALUE = 100` 就错了。
> **建议验证方法**：运行时把常量改成从配方读：
> `getScriptManager():getRecipe("UnbundleMoney")` → 取 outputs 里 `Base.Money` 的 count；
> 或最少在 `available()` 里断言 `getScriptManager():FindItem("Base.MoneyBundle") ~= nil`，
> 并在 `docs/` 里记下"B42.21 的 100 来自 recipes_packing.txt:180"。

### 1.3 "一个钞票物品实例到底代表多少钱" —— 没有 `getMoney()`，也没有有效 count

**(a) `InventoryItem.setCount/getCount` 存在，但只是纯字段读写，不联网、不落盘。**

```bash
$ JAVAP=~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap
$ $JAVAP -p /tmp/pzmoney/zombie/inventory/InventoryItem.class | grep -n "getCount\|setCount\|canStack"
61:  public boolean canStack;
396:  public int getCount();
397:  public void setCount(int);
```

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/InventoryItem.class
  public int getCount();
    Code:
         0: aload_0
         1: getfield      #690                // Field count:I
         4: ireturn

  public void setCount(int);
    Code:
         0: aload_0
         1: iload_1
         2: putfield      #690                // Field count:I
         5: return
```

⇒ `setCount` 就是 `putfield`。**没有 `sendItemStats` / `checkSyncItemFields` / `SendSyncItemFields` 调用**，
所以服务端改了 count 客户端不会知道（对比 §3.3）。

**(b) count 默认 1，且没有任何"按堆数量放置"的代码路径。**

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/InventoryItem.class | grep -n "putfield      #690"
1345:       226: putfield      #690                // Field count:I     ← 构造函数
1572:       226: putfield      #690                // Field count:I     ← 第二构造函数
8231:         2: putfield      #690                // Field count:I     ← setCount 本体
```

构造函数的上下文（同一个方法内）：

```
       200: invokestatic  #541                // Method zombie/core/Translator.getText:(...)...
       203: putfield      #677                // Field emptyString:Ljava/lang/String;
       217: ...
       224: aload_0
       225: iconst_1
       226: putfield      #690                // Field count:I
```

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/scripting/objects/Item.class | grep -n "Field count:I"
863:        37: putfield      #36                 // Field count:I    ← 脚本模板 Item 的 count = 1
```

```
       35: aload_0
       36: iconst_1
       37: putfield      #36                 // Field count:I
```

**(c) count 甚至不进存档。**

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/InventoryItem.class > /tmp/II.txt
# 在 save(ByteBuffer,boolean) 与 saveWithSize(...) 两个方法体内，对 #690(count) 的引用次数：
$ awk '/^  public void save\(java.nio.ByteBuffer, boolean\)/,/^  public [a-z]/' /tmp/II.txt | grep -c "690"
0
$ awk '/^  public void saveWithSize/,/^  public [a-z]/' /tmp/II.txt | grep -c "690"
0
```

对照：同一个类里 `getCount()`/`setCount()` 明确引用 `#690`（§1.3a），
⇒ `count` 既不参与网络（§1.3a）也不参与存档，**它不是一个持久的"堆叠数量"**。

**(d) `canStack` 是死字段：`CanStack()` / `CanStackNoTemp()` 都直接 `return false`。**

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/inventory/InventoryItem.class
  public boolean CanStack(zombie.inventory.InventoryItem);
    Code:
         0: iconst_0
         1: ireturn

  boolean CanStackNoTemp(zombie.inventory.InventoryItem);
    Code:
         0: iconst_0
         1: ireturn
```

`Item.canStack` 的默认值仍是 true（脚本关键字是 `CanStack`，不是 `Stackable`）：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/scripting/objects/Item.class | grep -n "canStack"
975:       246: putfield      #165                // Field canStack:Z     ← 构造里 iconst_1
7225:      5649: putfield      #165                // Field canStack:Z     ← 关键字 "CanStack" 的解析分支
```

**(e) 全引擎只有两个地方真的写 count，而且都是给管理员/调试视图做"伪堆叠"分组：**

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/inventory/ItemContainer.class | grep -n "InventoryItem.setCount\|InventoryItem.getCount"
9439:        35: invokevirtual #1601  // Method InventoryItem.setCount:(I)V
9466:        98: invokevirtual #1619  // Method InventoryItem.getCount:()I
9469:       103: invokevirtual #1601  // Method InventoryItem.setCount:(I)V
9589:        53: invokevirtual #1601  // Method InventoryItem.setCount:(I)V
9613:       114: invokevirtual #1619  // Method InventoryItem.getCount:()I
9616:       119: invokevirtual #1601  // Method InventoryItem.setCount:(I)V
```

`javap -p` 证明这两处属于 `getItems4Admin(...)` 与 `getAllItems(...)`：

```bash
$ $JAVAP -p /tmp/pzfull/zombie/inventory/ItemContainer.class | grep -n "getItems4Admin\|getAllItems"
  public java.util.LinkedHashMap<java.lang.String, zombie.inventory.InventoryItem> getItems4Admin();
  public java.util.LinkedHashMap<java.lang.String, zombie.inventory.InventoryItem> getAllItems(java.util.LinkedHashMap<...>, boolean);
```

其逻辑是：先把 count 强设 1，若同 fullType 已在 map 中，则把已有条目 `getCount()+1`。
**这是给管理面板显示"×N"的，不是真实物品堆。**

### 1.4 §1 结论

- **一个 `Base.Money` 实例 = $1；一个 `Base.MoneyBundle` 实例 = $100。**
- **没有** `getMoney()` / `getMoneyValue()` / `getValue()` 之类的方法（javap 方法表里不存在，见 §5.2 grep 无命中）。
- 取值方式：**数实例个数**（§2），不是读 count。
- 因此公共层**不能**假设"1 个 item 实例 + count 的堆叠语义"。B42 没有堆叠。

---

## 2. 统计玩家身上有多少钱

### 2.1 可用的 API（javap 方法表）

```bash
$ JAVAP=~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap
$ $JAVAP -p /tmp/pzmoney/zombie/inventory/ItemContainer.class | grep -E "getCountType|getCountRecurse|getAllTypeRecurse|getItemCount|getItemsFromType|getItemCountFromTypeRecurse|getSomeTypeRecurse|getContainers"
  public int getCount(java.util.function.Predicate<zombie.inventory.InventoryItem>);
  public int getCountRecurse(java.util.function.Predicate<zombie.inventory.InventoryItem>);
  public int getCountType(java.lang.String);
  public int getCountTypeRecurse(java.lang.String);
  public int getCountTypeEval(java.lang.String, se.krka.kahlua.vm.LuaClosure);
  public int getCountTypeEvalRecurse(java.lang.String, se.krka.kahlua.vm.LuaClosure);
  public int getCountTypeEvalArgRecurse(java.lang.String, se.krka.kahlua.vm.LuaClosure, java.lang.Object);
  public int getItemCount(java.lang.String);
  public int getItemCount(java.lang.String, boolean);
  public int getItemCountRecurse(java.lang.String);
  public int getItemCountFromTypeRecurse(java.lang.String);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getAllType(java.lang.String);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getAllTypeRecurse(java.lang.String);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getItemsFromType(java.lang.String);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getItemsFromType(java.lang.String, boolean);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getSomeTypeRecurse(java.lang.String, int);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getSomeType(java.lang.String, int);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getAllTypeEvalRecurse(java.lang.String, se.krka.kahlua.vm.LuaClosure);
```

**没有 `getContainers()`**（javap 方法表里不存在，别用）。

### 2.2 关键：这些 `get*Count*` 数的是**条目数**，不是 count 之和

`getCountRecurse` 的实现是"取列表 → 返回 `size()`"：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public int getCountRecurse(java.util.function.Predicate<zombie.inventory.InventoryItem>);
    Code:
        16: aload_0
        17: aload_1
        18: aload_2
        19: invokevirtual #795                // Method getAllRecurse:(Ljava/util/function/Predicate;Ljava/util/ArrayList;)Ljava/util/ArrayList;
        22: pop
        23: aload_2
        24: invokevirtual #649                // Method ItemContainer$InventoryItemList.size:()I
        27: istore_3
        ...
        41: iload_3
        42: ireturn
```

`getCountTypeRecurse` 只是它的类型化包装：

```
  public int getCountTypeRecurse(java.lang.String);
        18: invokevirtual #811   // ItemContainer$TypePredicate.init:(Ljava/lang/String;)...
        25: invokevirtual #971   // Method getCountRecurse:(Ljava/util/function/Predicate;)I
```

而 `getItemCountFromTypeRecurse` **每条命中只 +1**（更明确地证明不是求和）：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public int getItemCountFromTypeRecurse(java.lang.String);
    Code:
         0: iconst_0
         1: istore_2                      ← 计数器 = 0
        28: aload         4
        30: invokevirtual #415            // InventoryItem.getFullType:()Ljava/lang/String;
        33: aload_1
        34: invokevirtual #139            // String.equals:(Ljava/lang/Object;)Z
        37: ifeq          43
        40: iinc          2, 1            ← 命中一条就 +1（不是 +getCount()）
        43: aload         4
        45: instanceof    #264            // class zombie/inventory/types/InventoryContainer
        58: aload         5
        60: invokevirtual #646            // InventoryContainer.getInventory:()Lzombie/inventory/ItemContainer;
        63: aload_1
        64: invokevirtual #1489           // getItemCountFromTypeRecurse:(Ljava/lang/String;)I
        72: iadd
```

因为 B42 里 `InventoryItem.count ≡ 1`（§1.3），**条目数 == 钞票张数**，所以两种写法等价。

### 2.3 递归到底覆盖什么（`getAllRecurse` 反汇编）

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public java.util.ArrayList<...> getAllRecurse(java.util.function.Predicate<...>, java.util.ArrayList<...>);
    Code:
        19: iload         4
        21: aload_0
        22: getfield      #27                 // Field items:Ljava/util/ArrayList;      ← 只遍历本容器 items
        28: if_icmpge     105
        ...
        66: aload_1                              ← 谓词命中
        69: invokeinterface #932               // Predicate.test
        77: aload_2
        78: aload         5
        80: invokevirtual #403               // ArrayList.add        ← 收集命中
        84: aload         5
        86: instanceof    #264                // class zombie/inventory/types/InventoryContainer
        89: ifeq          99
        92: aload_3
        95: invokevirtual #648               // ItemContainer$InventoryItemList.add   ← 收集子容器
        ...
       108: iload         4
       117: aload_3
       118: iload         4
       120: invokevirtual #650               // InventoryItemList.get
       123: checkcast     #264                // InventoryContainer
       126: invokevirtual #646               // InventoryContainer.getInventory:()Lzombie/inventory/ItemContainer;
       135: invokevirtual #795               // getAllRecurse   ← 对子容器递归
```

**结论**：
- `Recurse` 版会进入 `InventoryContainer.getInventory()`，也就是**背包里的背包里的钱会被数到**（只要那个背包还在 `items` 列表里）。
- 但**穿戴中/拿在手上的容器不在 `items` 列表里**。见下面 (b)。

**(a) 原版自己就依赖 `Recurse` 来"看看玩家有没有这个东西"**（可用性先例）：

```
lua/client/ISUI/ISWorldObjectContextMenu.lua:1880:    local count = playerInv:getCountTypeRecurse(itemType)
lua/shared/Foraging/forageSystem.lua:1656:        sendAddItemToContainer(inv, item);     -- 说明 forage 也走容器路径
lua/server/BuildingObjects/ISBuildUtil.lua:201:            local items = playerInv:getAllTypeRecurse(itemFullType)
lua/shared/BuildingObjects/TimedActions/ISMultiStageBuild.lua:81:            local items = playerInv:getAllTypeRecurse(itemFullType)
lua/client/ContextMenuCode.lua:22:        local bottlesList = playerObj:getInventory():getAllTypeRecurse("WaterDispenserBottle");
```

CleanBandages 的完整先例（`lua/client/ISUI/ISWorldObjectContextMenu.lua:1875-1882`）：

```lua
function CleanBandages.getAvailableItems(items, playerObj, recipeName, itemType)
	local recipe = getScriptManager():getRecipe(recipeName)
	if not recipe then return nil end
	local playerInv = playerObj:getInventory()
	local count = playerInv:getCountTypeRecurse(itemType)
	if count == 0 then return end
	table.insert(items, { itemType = itemType, count = count, recipe = recipe })
end
```

**(b) 致命点：穿戴中的背包会被移出 `getInventory()`。**

`lua/shared/NPCs/SurvivorSwap.lua:54-78`（原版/官方 Lua，且以此注释闻名）：

```lua
SurvivorSwap.applyLoadout = function(playerObj, data)
    playerObj:clearWornItems()
    playerObj:setPrimaryHandItem(nil)
    playerObj:setSecondaryHandItem(nil)
    local inv = playerObj:getInventory()
    inv:clear()
    ...
    for _, value in pairs(data.worn or {}) do
        local item = inv:AddItem(value)            -- 先放进背包
        playerObj:setWornItem(item:getBodyLocation(), item)   -- 再穿上
    end
    for _, value in pairs(data.inventory or {}) do
        inv:AddItem(value)
    end
    ...
    inv:setDrawDirty(true) -- dont forget this when messing with inventory
```

为什么"再穿上"就查不到了：`setWornItem` 里有一段把旧穿戴物从 `getInventory()` **物理删除**：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/characters/IsoGameCharacter.class
  public void setWornItem(zombie.scripting.objects.ItemBodyLocation, zombie.inventory.InventoryItem, boolean);
    Code:
        43: aload_0
        46: getfield      #2511               // Field wornItems:Lzombie/characters/WornItems/WornItems;
        48: invokevirtual #3613               // WornItems.setItem:(ItemBodyLocation, InventoryItem)V
        ...
        90: aload_0
        91: instanceof    #81                 // class zombie/characters/IsoPlayer
        ...
       148: getstatic     #587                // Field GameServer.server:Z
       151: ifeq          163
       154: aload_0
       155: invokevirtual #3007               // Method getInventory:()Lzombie/inventory/ItemContainer;
       160: invokestatic  #3636               // Method GameServer.sendRemoveItemFromContainer:(ItemContainer,InventoryItem)V
       163: aload_0
       164: invokevirtual #3007               // Method getInventory:()Lzombie/inventory/ItemContainer;
       169: invokevirtual #3640               // Method ItemContainer.Remove:(Lzombie/inventory/InventoryItem;)V
```

另一条独立证据（把所有穿戴物塞进容器的是 `WornItems.addItemsToItemContainer`，只发生在"从 SurvivorDesc
初始化外观"那一次，之后穿戴物由 `WornItems` 单独持有、由 `bagsWorn` 列表单独跟踪）：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/characters/WornItems/WornItems.class
  public void addItemsToItemContainer(zombie.inventory.ItemContainer);
    Code:
        41: aload_3
        42: aload_3
        43: invokevirtual #157               // InventoryItem.getConditionMax:()I
        51: invokevirtual #160               // InventoryItem.setConditionNoSound:(I)V
        54: aload_1
        55: aload_3
        56: invokevirtual #164               // ItemContainer.AddItem:(Lzombie/inventory/InventoryItem;)...
```

```bash
$ $JAVAP -p /tmp/pzfull/zombie/characters/IsoGameCharacter.class | grep -n "bagsWorn"
132:  public final java.util.ArrayList<zombie.inventory.types.InventoryContainer> bagsWorn;
# 只有 updateSpeedModifiers()/渲染 与"初始化外观"两条路径碰它：
$ $JAVAP -p -c .../IsoGameCharacter.class | grep -n "getfield      #158"   # bagsWorn
26483:       209: getfield      #158
26487:       219: getfield      #158
27384:        16: getfield      #158     ← updateSpeedModifiers：forEach worn → 若是 InventoryContainer 就 add 进 bagsWorn
27430:       102: getfield      #158
```

> **明确说明未证实到什么程度**：
> 已证实的因果链是【`setWornItem` → `getInventory():Remove(item)`】（上面 offset 163-169），
> 所以**背在背上/穿在身上的容器不在 `getInventory()` 的 items 列表里**，
> `getCountTypeRecurse` 因此看不到它里面的钱。
> **未验证**：`IsoGameCharacter.getInventory()` 在别处是否还会把 `bagsWorn` 的内容塞回 items
> （搜索 `getfield #158 / bagsWorn` 只命中 4 处，全部是 `updateSpeedModifiers` 与初始化，
> 没有一处调用 `ItemContainer.AddItem` 把穿戴容器的内容装进主背包）。
> **建议验证方法**：进游戏控制台执行
> `local p=getPlayer(); local b=p:getInventory():AddItem("Base.MoneyBag"); p:setWornItem(ItemBodyLocation.BACK,b); local m=b:getInventory():AddItem("Base.Money"); print(p:getInventory():getCountTypeRecurse("Base.Money"))`
> 期望打印 `0`（即证实我们的结论）。

### 2.4 可直接抄的 Lua 片段（Kahlua 兼容）

风格对齐公共层现有文件（`Economy.lua` 用 `pcall` + `type()` 探测）。

```lua
--[[
    纯原版钞票计价。

    一个 Base.Money     实例 = 1 元   （scripts/generated/items/normal.txt:8636）
    一个 Base.MoneyBundle 实例 = 100 元（recipes_packing.txt:180: 1 MoneyBundle -> 100 Money）

    B42 没有堆叠（InventoryItem.CanStack() 恒 false），所以"张数"就是"实例个数"，
    用 getCountTypeRecurse 数条目即可；不要读 item:getCount()。
]]
local MONEY_TYPE   = "Base.Money"
local MONEY_BUNDLE = "Base.MoneyBundle"
local BUNDLE_VALUE = 100

local function containerValue(box)
    if box == nil then return 0 end
    local okA, bills = pcall(function() return box:getCountTypeRecurse(MONEY_TYPE) end)
    local okB, bundles = pcall(function() return box:getCountTypeRecurse(MONEY_BUNDLE) end)
    return (okA and bills or 0) + (okB and bundles or 0) * BUNDLE_VALUE
end

--[[
    玩家身上的现金总额。

    两段相加：
      1) player:getInventory() 递归 —— 覆盖身上所有口袋/背包里的背包；
      2) 穿戴中的容器（背包）—— setWornItem 会把容器从 getInventory() 里删掉
         （IsoGameCharacter.setWornItem offset 163-169），必须单独查。

    实测必须由调用方在服务端执行（见报告 §6）。
]]
function VanillaMoney.balance(player)
    if player == nil then return nil end
    local total = containerValue(player:getInventory())

    local ok, group = pcall(function() return BodyLocations.getGroup("Human") end)
    if ok and group ~= nil then
        local worn = player:getWornItems()
        for i = 0, group:size() - 1 do
            local loc = group:getLocationByIndex(i)
            if loc ~= nil then
                local okI, item = pcall(function() return worn:getItem(loc:getId()) end)
                if okI and item ~= nil then
                    local okC = pcall(function()
                        total = total + containerValue(item:getInventory())
                    end)
                end
            end
        end
    end
    return total
end
```

**逐行依据**：

| 写法 | 依据 |
|---|---|
| `box:getCountTypeRecurse(...)` | `ItemContainer.getCountTypeRecurse(String)I`（§2.1） |
| 不要用 `item:getCount()` | `InventoryItem.count` 恒 1 且不入档（§1.3） |
| `BodyLocations.getGroup("Human")` | `zombie.characters.WornItems.BodyLocations.getGroup(String)BodyLocationGroup`（javap 见 §6.3）；`lua/shared/NPCs/BodyLocations.lua:3` `local group = BodyLocations.getGroup("Human")` |
| `group:getLocationByIndex(i)` / `group:size()` | `BodyLocationGroup.getLocationByIndex(int)BodyLocation` / `size()I` |
| `loc:getId()` | `BodyLocation.getId()ItemBodyLocation`（**注意不叫 `getLocation()`**）。javap 全文：`$JAVAP -p /tmp/pzfull/zombie/characters/WornItems/BodyLocation.class` → 方法表只有 `isMultiItem/setMultiItem/isHideModel/isAltModel/isExclusive/isId/getId` |
| `worn:getItem(loc:getId())` | `WornItems.getItem(ItemBodyLocation)InventoryItem`；先例 `lua/shared/TimedActions/ISReadABook.lua:470` `self.character:getWornItems():getItem(ItemBodyLocation.EYES)` |
| `pcall` 包裹 | §7；公共层 `Economy.lua:39,54,71` 既有风格 |
| 用 `:size()` + `:get(i-1)` 而不是 `#`/`[1]` | §7.2（原版惯例，绝对安全） |

**如果你不想碰 worn 容器**，最小的正确写法是：

```lua
function VanillaMoney.balancePocketsOnly(player)
    return containerValue(player:getInventory())
end
```

并在 UI/日志里明确写"只计算随身口袋与未穿戴容器"——**不要**在文档里假装它等于"玩家全部现金"。

---

## 3. 扣钱（服务端权威）

### 3.1 删除原语：`ItemContainer.Remove(InventoryItem)` 是按引用删

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public void Remove(zombie.inventory.InventoryItem);
    Code:
         0: aload_0
         1: invokevirtual #1128              // getCharacter:()Lzombie/characters/IsoGameCharacter;
         4: ifnull        16
         7: aload_0
         8: invokevirtual #1128              // getCharacter:()...
        11: aload_1
        12: invokevirtual #1130              // IsoGameCharacter.removeFromHands:(InventoryItem)Z   ← 顺手脱手
        ...
        41: aload_3
        42: aload_1
        43: if_acmpne     182                 ← if_acmpne：引用比较！
        46: aload_1
        47: aload_0
        48: invokevirtual #1133              // InventoryItem.OnBeforeRemoveFromContainer:(ItemContainer)V
        51: aload_0
        52: getfield      #27                 // Field items:Ljava/util/ArrayList;
        55: iload_2
        56: invokevirtual #587                // ArrayList.remove:(I)Ljava/lang/Object;
        59: pop
        60: aload_1
        61: aconst_null
        62: putfield      #467                // Field InventoryItem.container:Lzombie/inventory/ItemContainer;
        65: aload_0
        66: iconst_1
        67: putfield      #40                 // Field drawDirty:Z     ← 主动置 drawDirty
        70: aload_0
        71: iconst_1
        72: putfield      #7                  // Field dirty:Z
        ...
       167: aload_0
       168: invokevirtual #351               // getParent:()Lzombie/iso/IsoObject;
       174: invokevirtual #499               // IsoObject.flagForHotSave:()V
```

⇒ `Remove` 只删**同一个 Java 对象**；并且会清 `item.container`、置 `drawDirty`/`dirty`、`flagForHotSave()`。
**它不负责联网**（§3.3）。

`RemoveAll` / `RemoveOneOf` 语义（javap 摘要）：

```
ItemContainer.java  RemoveAll(String, int)
   → 遍历 items，命中 type 或 fullType 的实例逐个放进返回列表，凑够 int 个就停
   → 返回 java.util.ArrayList<InventoryItem>（正好可以直接喂给 sendRemoveItemsFromContainer）
   → 注意：int 参数是"删几个实例"，不是"删多少张钞票金额"
   → 注意：不递归！
ItemContainer.java  RemoveOneOf(String, boolean) → 返回单个 InventoryItem
```

`RemoveAll(String)` 就是 `RemoveAll(type, items:size())`（全清）：

```
  public java.util.ArrayList<...> RemoveAll(java.lang.String);
         2: aload_0
         3: getfield      #27                 // Field items:...
         6: invokevirtual #106                // ArrayList.size:()I
         9: invokevirtual #1147               // Method RemoveAll:(Ljava/lang/String;I)...
```

类型匹配用的是**显式 equals**，同时比 `type` 与 `fullType`：

```
        56: getfield      #590                // InventoryItem.type:Ljava/lang/String;
        59: aload_1
        60: invokevirtual #139                // String.equals
        63: ifne          78
        66: aload         5
        68: getfield      #1150               // InventoryItem.fullType:Ljava/lang/String;
        71: aload_1
        72: invokevirtual #139                // String.equals
```

⇒ `RemoveAll("Base.Money", 3)` 与 `RemoveAll("Money", 3)` 都能命中，但**只在本容器**。

### 3.2 从多个 item 实例/多层容器里扣钱：自己写计划再执行

```lua
--[[
    从玩家身上扣掉 amount 元（面值单位的钞票）。

    返回 (true, plan) 表示已经真的扣完了；返回 (false, reason) 表示一分钱没动。

    设计原则：**先算清楚、确认够，再动手**。
    因为 Lua 中途 error 不会回滚，先扣一半再失败等于玩家丢钱。
]]
local function collectMoneyItems(box, out)
    if box == nil then return out end
    -- 大额优先：先花整捆，再花单张（减少拆除/腾格子的次数）
    local okB, bundles = pcall(function() return box:getItemsFromType(MONEY_BUNDLE) end)
    if okB and bundles ~= nil then
        for i = 0, bundles:size() - 1 do
            out[#out + 1] = { item = bundles:get(i), value = BUNDLE_VALUE }
        end
    end
    local okM, bills = pcall(function() return box:getItemsFromType(MONEY_TYPE) end)
    if okM and bills ~= nil then
        for i = 0, bills:size() - 1 do
            out[#out + 1] = { item = bills:get(i), value = 1 }
        end
    end
    -- 递归进子容器（背包里的背包里的钱）
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "InventoryContainer") then
            collectMoneyItems(it:getInventory(), out)
        end
    end
    return out
end
```

`getItemsFromType(String)` 的返回语义（javap）：

```
  public java.util.ArrayList<zombie.inventory.InventoryItem> getItemsFromType(java.lang.String);
  public java.util.ArrayList<zombie.inventory.InventoryItem> getItemsFromType(java.lang.String, boolean);
```

`lua/client/ISUI/ISInventoryPaneContextMenu.lua:1652,2157` 是它的原版用法：

```lua
    local fabricArray = player:getInventory():getItemsFromType(fabric:getType(), true);
    local otherDrainables = playerObj:getInventory():getItemsFromType(drainable:getType());
```

执行扣除：

```lua
--[[ 真正把计划里的钞票从容器里删掉，并在服务器上同步给客户端。
     touched 是 ArrayList<InventoryItem>，只装"容器是哪个"的信息留给发送阶段。 ]]
local function removePlanned(plan, need, touched)
    local removed = 0
    for i = 1, #plan do
        if removed >= need then break end
        local entry = plan[i]
        local value = entry.value
        if removed + value <= need then
            local item = entry.item
            local box = item:getContainer()
            -- 服务端才需要发包；客户端/单机下 sendRemoveItemsFromContainer 是 no-op（§6.2）
            if box ~= nil and isServer() then
                sendRemoveItemFromContainer(box, item)
            end
            if box ~= nil then box:Remove(item) end
            removed = removed + value
        end
    end
    return removed
end
```

> 为什么优先用 `box:Remove(item)` 而不是 `box:DoRemoveItem(item)`：
> 两者都是按引用删，但 `Remove` 额外走 `IsoGameCharacter.removeFromHands(item)`（offset 11-15），
> 对"手里正拿着钞票"的边界更安全。`DoRemoveItem` 只是 `ArrayList.remove(Object)` + 清 container：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public void DoRemoveItem(zombie.inventory.InventoryItem);
    Code:
        17: aload_1
        18: aload_0
        19: invokevirtual #1133              // InventoryItem.OnBeforeRemoveFromContainer:(ItemContainer)V
        22: aload_0
        23: getfield      #27                 // Field items:...
        26: aload_1
        27: invokevirtual #1145              // ArrayList.remove:(Ljava/lang/Object;)Z
        31: aload_1
        32: aconst_null
        33: putfield      #467                // Field container:Lzombie/inventory/ItemContainer;
```

### 3.3 找零（部分扣除）：B42 做不到，必须用策略代替

- `item:setCount()` 改的是那个不被同步、不入档的字段（§1.3a/c）；
- `SetCount` 在引擎里**只被管理员分组代码调用**（§1.3e）；
- 全游戏 Lua **零处**调用 `:setCount(`：

```bash
$ cd "$G/media/lua" && grep -rn ":setCount(" . | grep -v setCountdownSound
（无输出）
```

所以"给一张 $100 收 $30 找回 $70"**没有引擎原语**。可选的三种策略，按推荐度排序：

| 策略 | 做法 | 代价/风险 |
|---|---|---|
| **A. 必须精确（推荐给签约费）** | 用 `balance()` 校验 `总额 >= price`，然后**按面值组合逐张/逐捆删**，删多了（例如要 $60 但只有 $100 捆）就**先拆捆**：`Remove` 掉 1 个 `MoneyBundle`，`AddItems("Base.Money", 100)`，从中删掉 100-60=40 张...（实现上更简单：拆捆后重新跑一次选张逻辑） | 需要拆捆逻辑；拆捆产生 100 个新 item 实例，**大额时会有明显卡顿**（100 次 `AddItem`） |
| **B. 必须先拆捆（推荐，简单）** | 扣款前把玩家身上的 `MoneyBundle` 全部拆成 `Base.Money`（或按需拆），之后只剩面值 $1，`Remove` 数量 == 金额 | item 实例数暴增（$10000 = 10000 个实例），B42 背包格子/性能会痛苦；**不推荐**用于大额 |
| **C. 不找零（能接受就最省事）** | 要求玩家持有**面值恰好够**的组合；或声明"只收整钱，多付不退" | 用户体验差，但零风险、零新物品 |
| **D. 自建"零钱/代金券"物品** | 加一个 `Bin2NPCExtensionVanilla.Wallet` 之类的物品承载余额 | 已超出"纯原版"，但公共层的 `Economy` 接口不变，可以后加 |

**报告立场**：`pay()` 必须返回 `(false, "no_change")` 或自己完成拆捆，**不得静默少收或多收**。
原版对这个问题的态度见 §5.3：原版钱根本不参与交易，所以没有先例可抄。

### 3.4 多人联机：客户端如何得知

**(a) `ItemContainer` 上的同步设施**

```bash
$ $JAVAP -p /tmp/pzmoney/zombie/inventory/ItemContainer.class | grep -E "DrawDirty|sendContents|transmit"
  public boolean isDrawDirty();
  public void setDrawDirty(boolean);
```

**没有** `sendContentsToRemoteContainer`、`transmitItem` 这两个名字（javap 方法表里不存在；
`lua/` 全库 grep 也无命中）：

```bash
$ cd "$G/media/lua" && grep -rn "sendContentsToRemoteContainer\|transmitItem\b" . | head
（无输出）
```

**(b) 真正的同步 API 是 `zombie.network.GameServer` 的静态方法，且被暴露成 Lua 全局**

```bash
$ $JAVAP -p /tmp/pzfull/zombie/network/GameServer.class | grep -iE "sendReplaceItemInContainer|sendRemoveItem|sendAddItem"
  public static void sendReplaceItemInContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem, zombie.inventory.InventoryItem);
  public static void sendItemStats(zombie.inventory.InventoryItem);
  public static void sendSyncItemFields(zombie.inventory.InventoryItem);
```

```bash
$ $JAVAP -p /tmp/pzfull/zombie/Lua/LuaManager\$GlobalObject.class | grep -n "Container"
 244:  public static void sendItemsInContainer(zombie.iso.IsoObject, zombie.inventory.ItemContainer);
 760:  public static void sendAddItemToContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem);
 762:  public static void sendAddItemsToContainer(zombie.inventory.ItemContainer, java.util.ArrayList<zombie.inventory.InventoryItem>);
 764:  public static void sendReplaceItemInContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem, zombie.inventory.InventoryItem);
 765:  public static void sendRemoveItemFromContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem);
 766:  public static void sendRemoveItemsFromContainer(zombie.inventory.ItemContainer, java.util.ArrayList<zombie.inventory.InventoryItem>);
 767:  public static void replaceItemInContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem, zombie.inventory.InventoryItem);
```

**(c) 原版"服务端从玩家背包删物品并同步"的既有写法（这就是要抄的）**

`lua/server/ClientCommands.lua:210-218`（背包 空→满 的换袋命令，逐条对应我们扣钱需要的四步）：

```text
			local emptyBag = player:getInventory():getItemWithID(args.emptyBag)
			if emptyBag:hasTag(ItemTag.HOLD_DIRT) and (...) then
				local isPrimary = player:isPrimaryHandItem(emptyBag)
				local isSecondary = player:isSecondaryHandItem(emptyBag)
				player:removeFromHands(emptyBag);
				player:getInventory():Remove(emptyBag);
				sendRemoveItemFromContainer(player:getInventory(), emptyBag);
				local item = player:getInventory():AddItem(args.newBag);
				sendAddItemToContainer(player:getInventory(), item);
```

`lua/server/Camping/BuildingObjects/campingCampfire.lua:8-9`（按类型+数量删除并同步，**最贴近我们的需求**）：

```lua
    local items = self.character:getInventory():RemoveAll('Stone2', 3)
    sendRemoveItemsFromContainer(self.character:getInventory(), items);
```

调用点背景 `lua/server/Camping/BuildingObjects/campingCampfire.lua:1-10`：
文件位于 **`server/`**，本身只在服务端加载（第 1 行是 `require "BuildingObjects/ISBuildingObject"`，
没有也不需要 `if isClient() then return end`）。
**注意**：它对 `sendRemoveItemsFromContainer` **没有**加 `if isServer() then` 守卫，
依然安全，原因就是 §6.2 里 `INetworkPacket.send` 的 `GameServer.server` 早退。

另见 `lua/shared/Moveables/ISMoveableSpriteProps.lua:4435`（同一句式）：

```lua
            sendRemoveItemsFromContainer(_inventory, _inventory:RemoveAll(_itemType, _amount));
```

`lua/shared/BuildingObjects/TimedActions/ISShovelGround.lua:101-104`：

```lua
			self.character:getInventory():Remove(self.emptyBag);
			sendRemoveItemFromContainer(self.character:getInventory(), self.emptyBag);
			local item = self.character:getInventory():AddItem(self.newBag);
```

**(d) `setDrawDirty(true)` 是什么、不是什么**

- 它只是**本地 UI 标脏**（`ItemContainer.drawDirty` 字段 + `isDrawDirty()/setDrawDirty()`）。
- 原版把它当"我直接改过库存列表，通知 UI 重画"的约定，注释写在
  `lua/shared/NPCs/SurvivorSwap.lua:73`：`inv:setDrawDirty(true) -- dont forget this when messing with inventory`。
- 其它用例：`lua/shared/Camping/TimedActions/ISLightFromKindle.lua:100`、
  `lua/shared/Farming/TimedActions/ISPlowAction.lua:65`、`lua/shared/Entity/TimedActions/ISItemSlotAddAction.lua:59-60`。
- **它不是联网同步**；联网必须用 §3.4(b)/(c) 的 `send*`。

**(e) 如果只想改"数量"而不是删/加**

`sendReplaceItemInContainer(container, oldItem, newItem)` 是对应 `ReplaceInventoryItemInContainer` 包的 Lua 包装：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/network/GameServer.class
  public static void sendReplaceItemInContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem, zombie.inventory.InventoryItem);
    Code:
        17: getstatic     #2559               // Field PacketTypes$PacketType.ReplaceInventoryItemInContainer
        20: iconst_3
        21: anewarray     #6                  // class java/lang/Object
        24: dup
        25: iconst_0
        26: aload_0
        27: aastore
        28: dup
        29: iconst_1
        30: aload_1
        31: aastore
        32: dup
        33: iconst_2
        34: aload_2
        35: aastore
        36: invokestatic  #2501               // Method INetworkPacket.send:(IsoPlayer,PacketType,Object[])V
```

原版用法（客户端侧改完物品属性后通知服务端）：

```text
lua/server/ClientCommands.lua:1234:    sendReplaceItemInContainer(item:getContainer(), item, item)
lua/shared/TimedActions/ISCleanBandage.lua:44:	sendReplaceItemInContainer(self.character:getInventory(), self.item, item)
lua/shared/TimedActions/ISLitCandleExtinguish.lua:44:    sendReplaceItemInContainer(self.character:getInventory(), self.item, candle)
lua/shared/TimedActions/ISTransferWaterAction.lua:39:		sendReplaceItemInContainer(self.character:getInventory(), self.itemTo, newItem)
```

**但注意 `PlayerItem` 序列化里没有 count**（§1.3），所以 `sendReplaceItemInContainer` 只适合
"换一个 item 对象/改 modData"，**改 count 依然传不过去**。这就是 §3.3 说"setCount 不可用"的兜底证据。

小写那个 `replaceItemInContainer` **在联机里是 no-op**：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/Lua/LuaManager\$GlobalObject.class
  public static void replaceItemInContainer(zombie.inventory.ItemContainer, zombie.inventory.InventoryItem, zombie.inventory.InventoryItem);
    Code:
         0: getstatic     #349                // Field GameServer.server:Z
         3: ifne          33                    ← server 为 true 直接 return
         6: getstatic     #304                // Field GameClient.client:Z
         9: ifne          33                    ← client 为 true 也直接 return
        12: aload_0
        13: invokevirtual #6266               // ItemContainer.getParent:()Lzombie/iso/IsoObject;
        16: checkcast     #547                // class zombie/characters/IsoPlayer
        24: invokestatic  #6212               // ActionManager.getInstance:()...
        30: invokevirtual #6270               // ActionManager.replaceObjectInQueuedActions:(IsoPlayer,Object,Object)V
        33: return
```

即：**只在单机**把排队中的 timed action 里的旧 item 引用换成新的。原版成对调用它和
`sendReplaceItemInContainer`（`ISLitCandleExtinguish.lua:44-45`、`ISHurricaneLanternExtinguish.lua:44-45`）。

### 3.5 `pay()` 的推荐骨架

```lua
--[[ 返回 (true) 或 (false, reason)，reason ∈ {"no_item","no_funds","no_change","busy"} ]]
function VanillaMoney.pay(player, amount)
    local price = math.floor(tonumber(amount) or 0)
    if price <= 0 then return true end
    if player == nil then return false, "no_player" end
    if not isServer() and not isClient() then return false, "not_owner" end  -- §6

    local plan = collectMoneyItems(player:getInventory(), {})
    -- 需要先把 worn 容器也补进来（§2.4）；这里省略
    local total = 0
    for i = 1, #plan do total = total + plan[i].value end
    if total < price then return false, "no_funds" end

    -- 选一个"够且尽量不拆"的子集：整捆优先
    local taken, sum = {}, 0
    for i = 1, #plan do
        if sum >= price then break end
        taken[#taken + 1] = plan[i]
        sum = sum + plan[i].value
    end
    if sum > price then
        -- 需要找零：B42 无堆叠，直接删一张捆会多收，这里明确拒绝
        return false, "no_change"
    end

    local removed = 0
    for i = 1, #taken do
        local box = taken[i].item:getContainer()
        if box ~= nil then
            if isServer() then sendRemoveItemFromContainer(box, taken[i].item) end
            box:Remove(taken[i].item)
            removed = removed + taken[i].value
        end
    end
    if removed ~= price then
        -- 极端情况（并发改容器）：把已删的按原样补回去，保住"要么全扣、要么不扣"
        VanillaMoney.refund(player, removed)
        return false, "no_funds"
    end
    return true
end
```

> 上面 `removed ~= price` 的回滚只是**尽力而为**（`Remove` 掉的 item 对象已经脱容器，`AddItem`
> 会造**新对象**，ModData/损坏度会丢）。真正稳固的做法是"只允许精确组合"或"自建钱包物品"。

---

## 4. 退钱（退款）

### 4.1 `AddItem` 的重载与方法签名（javap）

```bash
$ $JAVAP -p /tmp/pzmoney/zombie/inventory/ItemContainer.class | grep -E "AddItem|AddItems|addItem"
  public zombie.inventory.InventoryItem AddItem(java.lang.String);
  public boolean AddItem(java.lang.String, float);
  public boolean AddItem(java.lang.String, float, boolean);
  public zombie.inventory.InventoryItem AddItem(zombie.inventory.InventoryItem);
  public zombie.inventory.InventoryItem addItem(zombie.inventory.InventoryItem);
  public java.util.ArrayList<zombie.inventory.InventoryItem> AddItems(java.lang.String, int);
  public java.util.ArrayList<zombie.inventory.InventoryItem> AddItems(zombie.inventory.InventoryItem, int);
  public java.util.ArrayList<zombie.inventory.InventoryItem> AddItems(java.util.ArrayList<zombie.inventory.InventoryItem>);
  public <T extends zombie.inventory.InventoryItem> T addItem(zombie.scripting.objects.ItemKey);
```

**返回值语义必须记牢**（这是最容易写错的地方）：

| 签名 | 返回 | 语义 |
|---|---|---|
| `AddItem(String)` | `InventoryItem`（失败 `null`） | 创建一个实例并塞进容器；**这就是退款要用的** |
| `AddItem(String, float)` | **`boolean`** | **第二个参数不是数量！** 只有 `Drainable` 会用它乘以 `maxUses` 当"剩余使用比例"，其余物品完全忽略它 |
| `AddItem(String, float, boolean)` | `boolean` | 同上 |
| `AddItems(String, int)` | `ArrayList<InventoryItem>` | 调 `int` 次 `AddItem(String)`，**每次一个独立实例** |

证明 A（`AddItem(String)` 创建实例、返回实例，并置 `drawDirty`）：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public zombie.inventory.InventoryItem AddItem(java.lang.String);
    Code:
         0: aload_0
         1: iconst_1
         2: putfield      #40                 // Field drawDirty:Z          ← 自动标脏
        27: getstatic     #508                // Field ScriptManager.instance:...
        31: invokevirtual #513               // ScriptManager.FindItem:(String)Item;   ← 未注册物品返回 null
        ...
        59: aload_1
        60: invokestatic  #529                // InventoryItemFactory.CreateItem:(String)InventoryItem;
        63: astore_3
        64: aload_3
        65: ifnonnull     70
        68: aconst_null
        69: areturn                            ← 创建失败返回 null
        70: aload_3
        71: aload_0
        72: putfield      #467                // InventoryItem.container = this
        75: aload_0
        76: getfield      #27                 // Field items:...
        80: invokevirtual #403               // ArrayList.add
        ...
```

证明 B（`AddItem(String, float)` 里 `iload_2` 只出现在 `Drainable` 分支，返回值是 `iconst_1`）：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public boolean AddItem(java.lang.String, float);
    Code:
        27: aload_1
        28: invokestatic  #529                // InventoryItemFactory.CreateItem:(String)...
        38: aload_3
        39: instanceof    #562                // class zombie/inventory/types/Drainable
        42: ifeq          57
        45: aload_3
        46: aload_3
        47: invokevirtual #564               // InventoryItem.getMaxUses:()I
        50: i2f
        51: fload_2                             ← 唯一的参数使用点
        52: fmul
        53: f2i
        54: invokevirtual #567               // InventoryItem.setCurrentUses:(I)V
        57: aload_3
        58: aload_0
        59: putfield      #467                // InventoryItem.container = this
        85: iconst_1
        86: ireturn
```

证明 C（`AddItems(String,int)` = 循环调 `AddItem(String)`）：

```bash
$ $JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class
  public java.util.ArrayList<zombie.inventory.InventoryItem> AddItems(java.lang.String, int);
    Code:
         8: iconst_0
         9: istore        4
        11: iload         4
        13: iload_2
        14: if_icmpge     42
        17: aload_0
        18: aload_1
        19: invokevirtual #401               // Method AddItem:(Ljava/lang/String;)Lzombie/inventory/InventoryItem;
        22: astore        5
        24: aload         5
        26: ifnull        36
        29: aload_3
        30: aload         5
        32: invokevirtual #403               // ArrayList.add
        36: iinc          4, 1
        39: goto          11
```

### 4.2 退款标准写法

```lua
--[[ 退款：按面值拆成 Money + MoneyBundle，减少实例数。
     M = 元，bundle = 100 元/个。 ]]
local function grantMoney(inv, amount)
    local left = math.floor(tonumber(amount) or 0)
    if left <= 0 then return 0 end
    local given = 0

    local bundles = math.floor(left / BUNDLE_VALUE)
    if bundles > 0 then
        local list = inv:AddItems(MONEY_BUNDLE, bundles)   -- ArrayList<InventoryItem>
        for i = 0, list:size() - 1 do
            if isServer() then sendAddItemToContainer(inv, list:get(i)) end
        end
        given = bundles * BUNDLE_VALUE
        left = left - given
    end

    for _ = 1, left do
        local item = inv:AddItem(MONEY_TYPE)               -- 返回 InventoryItem 或 nil
        if item == nil then break end
        if isServer() then sendAddItemToContainer(inv, item) end
        given = given + 1
    end
    return given
end
```

**原版先例（加物品 + 同步）**：

```text
lua/server/ClientCommands.lua:217-218:
				local item = player:getInventory():AddItem(args.newBag);
				sendAddItemToContainer(player:getInventory(), item);

lua/server/Fishing/BuildingObjects/FishingNet.lua:73-74:
    local item = player:getInventory():AddItem("Base.FishingNet");
    sendAddItemToContainer(player:getInventory(), item);

lua/server/ClientCommands.lua:681-682:
        sendAddItemToContainer(player:getInventory(), key);

lua/server/Traps/STrapGlobalObject.lua:321-322:
        sendAddItemToContainer(character:getInventory(), item);
```

### 4.3 退款是否还需要额外同步

- **需要**（联机时）：`AddItem` 自己**不会**发包。
  - 反证：`AddItem(String)` 的反汇编里只有 `drawDirty=1`、`items.add`、`Food` 特判、
    `flagForHotSave()`，**没有任何 `GameServer.send*` / `INetworkPacket.send` 调用**（上面 §4.1 证明 A 的完整方法体）。
  - 对照：`ItemContainer.Remove` 同理不联网（§3.1）。
- **单机不需要**：`sendAddItemToContainer` → `INetworkPacket.send(...)` → 第一步就 `if (!GameServer.server) return;`（§6.2）。
- **客户端（非房主）不能自己 `AddItem` 加钱**：那只是本地假物品。加钱只能由服务端做，或者
  客户端 `sendClientCommand(mod, "refund", args)` → 服务端执行。

---

## 5. `Base.Money` 在 B42 里的通行度

### 5.1 原版谁在发钱/收钱：**没有任何"收钱"的系统，只有战利品刷钱**

关键词与命中（全部命令可复现）：

```bash
# 1) 脚本层：除了物品定义/模型/打包配方，没有任何"钱的价值/交易"定义
$ cd "$G/media/scripts" && grep -rn "Money" --include=*.txt . \
    | grep -v "generated/items/normal.txt\|generated/models_items.txt\|recipes_packing"
generated/items/container.txt:277:    item Bag_MoneyBag
generated/items/container.txt:1776:    item Briefcase_Money
（仅此两条，都是容器）

# 2) Lua 层（排除翻译/StoryClutter）：
$ cd "$G/media/lua" && grep -rn "Money" . --include=*.lua | grep -v "Translate\|StoryClutter"
→ lua/server/Camping/camping_fuel.lua:37,110        Money = 5/60.0,       ← 烧钞票当燃料的燃料值表
→ lua/server/Vehicles/VehicleDistributions.lua:*    "Money", 20 / 10 / 100  ← 车里刷钱
→ lua/shared/Foraging/Categories/Trash.lua:67       Money = "Base.Money"   ← 翻垃圾能翻到
→ lua/server/Items/Distributions.lua:197-...        "Money", 100 / 50 ...  ← 建筑战利品刷钱
→ lua/server/Items/ProceduralDistributions.lua:*    "Money"/"MoneyBundle"  ← 同上
→ lua/client/... (无)
```

`lua/server/Camping/camping_fuel.lua:37` 只说"钞票是可燃物"：

```text
    Money = 5/60.0,
```

`lua/shared/Foraging/Categories/Trash.lua:67`：

```text
				Money              = "Base.Money",
```

**发钱地点（weighted loot，数字是权重不是数量）**，例如银行金库：

```text
lua/server/Items/ProceduralDistributions.lua:3034-3059:
	BankDeposit = {
		rolls = 4,
		items = {
			"Bag_MoneyBag", 0.1,
			...
			"Money", 100,
			"Money", 50,
			"Money", 20,
			"Money", 20,
			"MoneyBundle", 100,
```

`lua/server/Items/ProceduralDistributions.lua:19663-19695`（`DrugLabMoney`）：

```text
			"MoneyBundle", 50,
			"MoneyBundle", 20,
			...
			"MoneyBundle", 100,
			"MoneyBundle", 50,
			"MoneyBundle", 20,
			"MoneyBundle", 10,
```

`lua/server/Items/Distributions.lua:849` 还有一个"藏钱"点位：

```text
				{name="PlankStashMoney", min=0, max=99, weightChance=20},
```

`StoryClutter`（随机世界叙事杂物，也是原版发钱点）：

```
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:588   "Base.Money"          -- GigamartClutter
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:612   "Base.Money"          -- GroceryClutter
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:901   "Base.Money"
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:1101  "Base.MoneyBundle"    -- 与 Base.Briefcase_Money 同组
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:1318  "Base.Money"
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:1341-1342 "Base.Money" + "Base.MoneyBundle"
lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:1421  "Base.Money"
```

**结论：原版只有"刷钱（loot/车/翻垃圾/叙事杂物）+ 烧钱 + 打包/拆包"，没有任何消费/结算系统。**

### 5.2 "钱不是物品而是角色属性"的第二套机制：**不存在**

```bash
# 玩家/角色类里没有任何 money/coin/cash/currency/wallet 成员
$ $JAVAP -p /tmp/pzfull/zombie/characters/IsoPlayer.class | grep -in "money\|coin\|cash\|wallet\|currency"
（无输出）
$ $JAVAP -p /tmp/pzfull/zombie/characters/IsoGameCharacter.class | grep -in "money\|coin\|cash\|wallet\|currency"
（无输出）

# 全 jar 提到 Money 的 zombie 类只有 8 个，全是"物品键注册/随机世界内容"，没有货币系统
$ grep -rl "Money" /tmp/pzfull | head
/tmp/pzfull/zombie/scripting/objects/ItemKey$Normal.class      ← 物品键常量表（Money=..., MoneyBundle=...）
/tmp/pzfull/zombie/scripting/objects/ItemKey$Container.class
/tmp/pzfull/zombie/scripting/objects/ModelKey.class            ← 模型键 Money / MoneyBundle
/tmp/pzfull/zombie/scripting/objects/CraftRecipeKey.class      ← UnbundleMoney
/tmp/pzfull/zombie/randomizedWorld/randomizedBuilding/RBHeatBreakAfternoon.class
/tmp/pzfull/zombie/randomizedWorld/randomizedBuilding/RBStripclub.class
/tmp/pzfull/zombie/randomizedWorld/randomizedVehicleStory/RVSRichJerk.class
/tmp/pzfull/zombie/randomizedWorld/randomizedDeadSurvivor/RDSPokerNight.class
```

`ItemKey$Normal` 里 Money 只是**字符串常量**（注意 `Normal` 是"普通物品键"类，不是"正常/稀有"）：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/scripting/objects/ItemKey\$Normal.class | grep -n "Money"
4176:      5803: ldc_w         #3275               // String Money
4179:      5812: ldc_w         #3280               // String MoneyBundle
```

**`getXp()` 与钱无关**（那是技能经验）；**没有 `player:getMoney()`**。

### 5.3 容易误认成"钱"的东西：都不是

| 物品/概念 | 真实用途 | 证据 |
|---|---|---|
| `Base.CreditCard` / `CreditCard_Stolen` | 纯 Junk，`Tags = base:fitswallet` / `base:applyownername`，无面值 | `scripts/generated/items/normal.txt:8586-8594`、`:8597-8605` |
| `Base.StockCertificate` / `Base.GoldBar` / `Base.SmallGoldBar` | 战利品，原版无兑换系统 | `StoryClutter_Definitions.lua:1341-1345` 附近与 `Base.Money` 同组 |
| 引擎里的 `TradingUI*Packet`（`TradingUIAddItemPacket` / `TradingUIRemoveItemPacket`） | **玩家对玩家"交易窗口"的 UI 握手**，搬运的是**任意物品**，与服务端货币无关 | `unzip -l projectzomboid.jar \| grep Trading` 见 `zombie/network/packets/TradingUIAddItemPacket.class`、`TradingUIRemoveItemPacket.class` |
| `GameServer.createItemTransaction` / `isItemTransactionConsistent` | 反作弊用的物品移动事务校验，不是钱 | `LuaManager$GlobalObject.class:735-740` |

### 5.4 `available()` 的纯原版实现

```lua
--[[ 纯原版口味永远可用：只要 Base.Money 脚本注册成功。
     用 ScriptManager.FindItem 而不是"数玩家身上有没有钱"——注册成功与身上有没有钱是两件事。 ]]
function VanillaMoney.available()
    local sm = getScriptManager and getScriptManager()
    if sm == nil then return false end
    local ok, item = pcall(function() return sm:FindItem(MONEY_TYPE) end)
    return ok and item ~= nil
end
```

依据：`zombie.scripting.ScriptManager.FindItem(String)Item`（§7.3 javap），
以及原版 `playerInv:getCountTypeRecurse` 的可用性判定风格（`ISWorldObjectContextMenu.lua:1878-1881`）。

---

## 6. 单人/主机（SP）与专用服的差异

### 6.1 三种运行形态（引擎事实）

```bash
# GameServer.server / GameClient.client 是判定依据；isServer()/isClient() 是它们的 Lua 门面
$ grep -rn "function isServer\|function isClient" "$G/media/lua" | head
（isServer/isClient 由引擎注入，Lua 侧只使用不定义）
```

原版用法（直接用 `isServer()` 包住发包，用 `isClient()` 在服务端文件顶部早退）：

```
lua/server/ClientCommands.lua:1:            if isClient() then return end          ← 整个服务端文件
lua/server/ClientCommands.lua:280:          if isServer() then                     ← 只在真的有服务器时发包
lua/shared/NPCs/SurvivorSwap.lua:1:         if isClient() then return end          ← shared 也能早退
lua/server/TransactionProcessor.lua:1:      if isClient() then return end
lua/server/Fishing/BuildingObjects/FishingNet.lua:69:   if isClient() then return end
lua/server/Camping/SCampfireSystem.lua:154: if isClient() then return end
lua/server/Camping/BuildingObjects/campingCampfire.lua:8-9: 不加 isServer() 直接 RemoveAll + send*（靠 §6.2 的守卫）
```

典型片段 `lua/server/ClientCommands.lua:276-290`（省略了 `else` 与 `print` 分支）：

```lua
Commands.object.emptyTrash = function(player, args)
	local object = _getTrashCan(args.x, args.y, args.z, args.index)
	if object then
		local container = object:getContainer()
		if isServer() then
			sendRemoveItemsFromContainer(container, container:getItems())
		end
		-- 然后本地才真正 DoRemoveItem（顺序：先发包、后本地删）
		while container:getItems():size() > 0 do
			local item = container:getItems():get(0)
			container:DoRemoveItem(item)
		end
		container:clear()
	end
end
```

### 6.2 `send*` 家族在非服务器下是**精确 no-op**（不用自己判，但判了更清楚）

`sendRemoveItemsFromContainer` / `sendAddItemToContainer` 对玩家容器走这条路：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/network/GameServer.class
  public static void sendRemoveItemsFromContainer(zombie.inventory.ItemContainer, java.util.ArrayList<zombie.inventory.InventoryItem>);
    Code:
         0: aload_0
         1: invokevirtual #3252               // ItemContainer.getCharacter:()Lzombie/characters/IsoGameCharacter;
         4: instanceof    #1330               // class zombie/characters/IsoPlayer
         7: ifeq          38
        10: aload_0
        11: invokevirtual #3252               // getCharacter:()...
        17: getstatic     #2531               // Field PacketTypes$PacketType.RemoveInventoryItemFromContainer
        20: iconst_2
        21: anewarray     #6                  // Object[]
        ...
        32: invokestatic  #2501               // INetworkPacket.send:(IsoPlayer,PacketType,Object[])V
```

而 `INetworkPacket.send(IsoPlayer,...)` 的第一条指令就是服务器判定：

```bash
$ $JAVAP -p -c /tmp/pzfull/zombie/network/packets/INetworkPacket.class
  public static void send(zombie.characters.IsoPlayer, zombie.network.PacketTypes$PacketType, java.lang.Object...);
    Code:
         0: getstatic     #87                 // Field GameServer.server:Z
         3: ifeq          21                    ← 不是服务器 → 直接 return
         6: aload_0
         7: invokestatic  #100               // GameServer.getConnectionFromPlayer:(IsoPlayer)UdpConnection;
        ...
        21: return
```

（`sendToAll` / `sendToRelative` 同样以 `getstatic GameServer.server : ifeq` 开头。）

⇒ **SP（含主机自己玩的客户端）里调用 `sendRemoveItemsFromContainer` / `sendAddItemToContainer`
不会有任何网络副作用**；但为了语义清楚与可读性，公共层仍然建议照原版包 `if isServer() then`。

### 6.3 三种环境下的行为矩阵

| 操作 | SP（`isServer()==false`、`isClient()==false`） | 专用服（`isServer()==true`） | 纯客户端（`isClient()==true`） |
|---|---|---|---|
| `getCountTypeRecurse` 计数 | ✅ 本机权威 | ✅ 服务端权威 | ⚠️ 只能看到**已同步到本机**的容器；玩家自己的背包是同步的，别人的不是 |
| 读 worn 容器计数 | ✅ | ✅ | ⚠️ 同上 |
| `AddItem` / `Remove` | ✅ 立即生效 | ✅ 但**必须**跟 `send*` | ❌ 只改本地假象，会被服务端覆盖 |
| `sendRemoveItemsFromContainer` / `sendAddItemToContainer` | ✅ 调用安全（no-op） | ✅ 真正发包 | ⚠️ `GameServer.server==false` ⇒ no-op（**打回服务端的包不是靠这个 API**） |
| `replaceItemInContainer`（小写） | ✅ 改排队 action | ❌ no-op（`GameServer.server` 为 true 直接 return） | ❌ no-op（`GameClient.client` 为 true 直接 return） |

**给公共层的建议**：

```lua
--[[ 写操作的守卫。1 = 这台机器就是权威；nil = 必须走 sendClientCommand 回服务端。 ]]
local function authority()
    if isServer() then return "server" end      -- 专用服 / SP 主机
    if isClient() then return "client" end      -- 联机客户端：无权直接改库存
    return "single"                             -- SP（无网络层）
end
```

调用点（对齐 `Service.lua:401` / `Maintain.lua:180` 现有 `Economy.pay(player, price)` 的签名）：

- `authority() == "client"` 时 → `sendClientCommand(Config.MODULE, "hire", {...})`，
  让服务端在 `Events.OnClientCommand` 里执行 `Economy.pay`。这与上游口味
  （`economy-integration-hooks.md` 的"服务端权威"结论）保持同一形状。
- `authority() == "server" | "single"` 时 → 直接执行。

### 6.4 单人专属的坑

- **`SandboxVars` 在联机客户端也存在，但专用服上的值才权威**；公共层 `Config.opt` 已经用 `pcall` 包了（`Config.lua:75`）。
- **SP 下 `getWornItems()` 一样有效**，worn 容器问题（§2.3b）与联机无关，SP 也会漏数。
- **SP 下 `isClient()` 返回 false**，所以"`if isClient() then return end` 把文件顶部挡掉"的写法
  **不影响 SP**（`SurvivorSwap.lua:1` 就是这个模式），可以放心照抄到 server 层文件。

---

## 7. Kahlua 兼容性红线

### 7.1 `pcall` / `ipairs` / `pairs` 可用；**没有 `next`**

```bash
$ JAVAP=~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap
$ $JAVAP -p -c -constants /tmp/pzfull/se/krka/kahlua/stdlib/BaseLib.class | grep -oE 'String [a-zA-Z]+$' | sort -u
String bytecodeloader
String classpath
String collect
String collectgarbage
String count
String debugstacktrace
String error
String getfenv
String getmetatable
String loader
String package
String pcall          ← ✅
String print
String rawequal
String rawget
String rawset
String select
String setfenv
String setmetatable
String step
String tonumber
String tostring
String type
String unpack
```

```bash
$ $JAVAP -p -c -constants /tmp/pzfull/se/krka/kahlua/stdlib/TableLib.class | grep -oE 'String [a-zA-Z]+$' | sort -u
String concat
String insert
String ipairs       ← ✅
String isempty
String newarray
String pairs        ← ✅
String remove
String table
String wipe
```

- **没有 `next`**（BaseLib 名单里没有；`pairs` 由 `TableLib` 提供）。
  → 公共层现有 `Config.lua:203-206` 用 `for _ in pairs(source) do total = total + 1 end`，没有用 `next`，是对的。
- `pcall` 存在，所以 §2.4/§3.5 的探测写法成立（和公共层 `Economy.lua:39,54,71` 一致）。

### 7.2 Java 集合的遍历：用 `:size()` + `:get(i-1)`，`#` 也能用

`#` 对 Java List 有效（原版很多地方这么写，虽然多数是 Lua table，但下面这两处是
`getSomeTypeRecurse` / `getItemsFromType` 这类 **Java 返回列表**）：

```text
lua/client/ISUI/ISInventoryPaneContextMenu.lua:1942:  local items = inventory:getSomeTypeRecurse(ammoType, ammoCount)
lua/server/BuildingObjects/ISBuildUtil.lua:164:        local count = math.min(itemCount, #items)
lua/server/BuildingObjects/ISBuildUtil.lua:201:        local items = playerInv:getAllTypeRecurse(itemFullType)
lua/shared/BuildingObjects/TimedActions/ISMultiStageBuild.lua:130:  local count = math.min(itemCount, #items)
```

```text
lua/shared/BuildingObjects/TimedActions/ISMultiStageBuild.lua:81-84:
    local items = playerInv:getAllTypeRecurse(itemFullType)
    for i=1,items:size() do
        local item = items:get(i-1)
lua/server/BuildingObjects/ISBuildUtil.lua:201-204:
    local items = playerInv:getAllTypeRecurse(itemFullType)
    for i=1,items:size() do
        local item = items:get(i-1)
```

⇒ **索引契约：`items:get(0)` 是第一个元素**；`#items` 与 `items:size()` 都可作为长度。
建议公共层统一用 `for i = 0, list:size() - 1 do local x = list:get(i) end`，不要混用。

### 7.3 运行期方法探测的正确写法

```lua
--[[ 好：type() 判成员存在性 + pcall 判调用期异常 ]]
local function hasMethod(obj, name)
    if obj == nil then return false end
    local ok, fn = pcall(function() return obj[name] end)
    return ok and type(fn) == "function"
end

if hasMethod(inv, "getCountTypeRecurse") then ... end
```

**反例（不要写）**：`if inv.getCountTypeRecurse then`——Kahlua 对未暴露的 Java 方法会触发
`__index` 反射查找，失败时的行为依版本而定，历史上出现过抛错而不是返回 `nil` 的情况。
用 `pcall` + `type()` 判断在两种行为下都安全。

**必须 pcall 的地方**：

| 调用 | 为什么 |
|---|---|
| `getScriptManager():FindItem(...)` | 脚本未加载/拼错时可能抛错（`AddItem(String)` 反汇编里对未知类型只 `DebugLog.log` 后返回 null，但 `FindItem` 本身没这层保护） |
| `BodyLocations.getGroup("Human")` | 世界未初始化时为 nil；`BodyLocations.reset()` 会在换档时清空（`BodyLocations.java: public static void reset()`） |
| `addItemsToContainer` / `getWornItems()` | 角色创建阶段可能为 nil |
| 所有 `AddItem` / `Remove` 循环 | 中途抛错会"扣一半钱"，必须整段 pcall 并在失败时按 §3.5 回滚 |

### 7.4 其它红线

- **不要用 `#` 之外的下标魔法**：`list[1]` 在 Kahlua 的 Java converter 上有歧义风险
  （`ISMoveableSpriteProps.lua:4614` 写过 `items[1].returnItem`，但那是 Lua table）。
  Java 列表一律 `:get(i)`。
- **不要用 `os.time()` / `os.date()` 做"日薪到期"计算**：公共层已有 `Config.worldHours()` / `Config.nowMs()`，
  继续用它们（`Config.lua:181,193`）。
- **不要 `require` 游戏自己的文件**：`BodyLocations` / `ScriptManager` 都是全局。

---

## 给实现者的结论

### A. 公共层需要抽象出的最小接口（纯原版实现要点）

现有契约（`Economy.lua`）只有 6 个函数，纯原版口味应当**原样实现同一张表**，让
`Service.lua:59,99,367,401,435,453,466,476` 与 `Maintain.lua:162-180` 零改动即可切换：

| 接口 | 上游经济模组（现状） | **纯原版实现要点** |
|---|---|---|
| `Economy.available()` | `type(economyServer().Pay) == "function"`（`Economy.lua:31-33`） | `getScriptManager():FindItem("Base.Money") ~= nil`，用 `pcall` 包；**永真**是正常的 |
| `Economy.balance(player)` | `pcall(server.PlayerData, player).coins`（`:36-42`） | `getCountTypeRecurse(MONEY) + 100 * getCountTypeRecurse(BUNDLE)`，**两段**：`player:getInventory()` + 所有 `worn` 容器（§2.4）。读不到返回 `nil`，保持"没钱 vs 读不到"的区分 |
| `Economy.pay(player, amount)` | `pcall(server.Pay, player, price)`（`:48-59`） | ① 守卫 `authority()`（§6.3）；② 先 `collectMoneyItems` 算总额，不足返回 `false, "no_funds"`；③ **整捆优先**选子集；④ 需要找零时返回 `false, "no_change"`（B42 无堆叠，§3.3）；⑤ `sendRemoveItemFromContainer` + `box:Remove(item)`；⑥ 失败回滚 `refund` |
| `Economy.refund(player, amount)` | `pcall(server.AddCoins, player, price)`（`:67-77`） | 先 `AddItems(MONEY_BUNDLE, n/100)` 再 `AddItem(MONEY)` 逐张（§4.2）；每个新 item 都 `sendAddItemToContainer`；日志 keep "refunded N to <player>" |
| `Economy.flow(...)` | `server.RecordPlayerFlow`（`:83-93`） | 纯原版**没有流水可写** → 返回 `false`，但**保留函数**（调用方不判返回值）；把同一份信息写进 `Config.log` / `Config.always`，别丢 |
| `Economy.wage()` | `Config.dailyWage()`（`:101-104`） | 不变（与货币载体无关） |
| `Config.economyServer()` | 上游全局表 | 纯原版口味**不要**注入任何 `ECONOMY_SERVER_GLOBAL`；`Config.economyServer()` 返回 `nil`，`Economy.available()` 不能依赖它 |

另外建议给纯原版口味新增两个**内部**（不进公共契约）的私有函数，用于把它自己的边界写清楚：

```lua
VanillaMoney.BUNDLE_VALUE = 100      -- ← 唯一硬编码常量，注释里写 "recipes_packing.txt:180"
VanillaMoney.authority()             -- "single" | "server" | "client"
```

### B. 必须避开的坑（按危害排序）

1. **worn 容器漏数（最高危）**：玩家把 `Bag_MoneyBag` / `Briefcase_Money` 穿身上后，
   `player:getInventory():getCountTypeRecurse` **看不到里面的钱**。
   实证：`IsoGameCharacter.setWornItem` 在 offset 163-169 调 `getInventory():Remove(item)`；
   `SurvivorSwap.lua:54-78` 就是把 `AddItem` 之后立刻 `setWornItem`，且 `SurvivorSwap.lua:73`
   专门注释"忘了 setDrawDirty 就会出问题"。
   **对策**：`balance/pay/refund` 三段都必须把 worn 容器算进去（§2.4 的 `BodyLocations.getGroup("Human")` 循环）。
2. **以为 `setCount` 能找零**：`InventoryItem.count` 不联网、不入档、`CanStack()` 恒 false；
   全游戏 Lua 零处 `:setCount(`。**对策**：整捆/整张选子集，不够就 `false, "no_change"`，或自建钱包物品。
3. **以为 `AddItem("Base.Money", 5)` 会给 5 张**：那个 `float` 只对 `Drainable` 有意义，返回值是 `boolean` 不是 item。
   **对策**：要 N 个实例用 `AddItems(type, n)`（返回 ArrayList）或循环 `AddItem(type)`。
4. **忘了 `send*`**：`AddItem` / `Remove` / `setCount` 都不发包，联机下客户端 UI 不会变。
   **对策**：每个 `Remove` 配 `sendRemoveItemFromContainer`，每个 `AddItem` 配 `sendAddItemToContainer`；
   批量删用 `RemoveAll(...)` 的返回值喂 `sendRemoveItemsFromContainer`（原版写法：
   `campingCampfire.lua:8-9`、`ISMoveableSpriteProps.lua:4435`）。
5. **把 `setDrawDirty(true)` 当同步**：它只标本地 UI 脏（`SurvivorSwap.lua:73`）。
6. **用 `lua/shared/` 里无条件执行扣钱**：`shared` 在客户端也会跑。
   照原版把服务端写操作放 `lua/server/` 文件、顶部 `if isClient() then return end`
   （`ClientCommands.lua:1`、`SurvivorSwap.lua:1`），或在函数里 `if not isServer() then return false, "not_authoritative" end`。
7. **`RemoveAll` 只在本容器**：不递归；多层背包里的钱要自己递归进 `InventoryContainer:getInventory()`。
8. **按 `Type` 匹配时别只写短名**：`RemoveAll` 比的是 `type` 或 `fullType` 的 equals，
   写 `"Money"` 或 `"Base.Money"` 都行；但 `getItemCountFromTypeRecurse` 比的是 `getFullType()`，
   **必须写 `"Base.Money"`**。统一用 full type。
9. **`getItemCountFromTypeRecurse` 与 `getCountTypeRecurse` 是同一件事**，不要以为前者是"金额求和"。
10. **不要在 `Balance` 里"顺手"扣钱**：`Service.lua:99` 会在每次界面刷新时调 `balance`，
    它必须是只读且便宜的（`Recurse` + worn 是 O(物品数)，可以接受；**不要**在里面 `AddItem` 拆捆）。

### C. 还需要实测确认的两点（本报告已标注为未证实）

| 未证实点 | 建议验证方法 |
|---|---|
| worn 容器确实不被 `InheritRecurse` 覆盖（目前由 `setWornItem` 的 `Remove` 反汇编间接证明） | SP 控制台一行：`local p=getPlayer(); local b=p:getInventory():AddItem("Base.MoneyBag"); p:setWornItem(ItemBodyLocation.BACK,b); b:getInventory():AddItem("Base.Money"); print(p:getInventory():getCountTypeRecurse("Base.Money"))` ⇒ 期望 `0` |
| `100:1` 是配方约定而非引擎常量 | 检查 `getScriptManager():getRecipe("UnbundleMoney")` 的 outputs；或直接看游戏更新是否改动 `recipes_packing.txt:180` |

### D. 参考命令速查（本报告全部 javap 结论可一键复现）

```bash
JAVA="/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"
JAVAP=~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap
mkdir -p /tmp/pzmoney && cd "$JAVA" \
  && unzip -o -q projectzomboid.jar 'zombie/inventory/*' 'zombie/characters/IsoGameCharacter.class' \
       'zombie/characters/WornItems/*' 'zombie/network/GameServer.class' 'zombie/network/packets/*' \
       'zombie/Lua/LuaManager$GlobalObject.class' 'zombie/scripting/objects/Item*.class' \
       'se/krka/kahlua/stdlib/*' -d /tmp/pzmoney

$JAVAP -p    /tmp/pzmoney/zombie/inventory/ItemContainer.class | grep -E "getCountType|Remove|getItemsFromType"
$JAVAP -p -c /tmp/pzmoney/zombie/inventory/ItemContainer.class | grep -A40 "getCountTypeRecurse"
$JAVAP -p -c /tmp/pzmoney/zombie/inventory/InventoryItem.class | grep -A6  "public boolean CanStack"
$JAVAP -p -c /tmp/pzmoney/zombie/characters/IsoGameCharacter.class | grep -A200 "setWornItem(zombie.scripting.objects.ItemBodyLocation, zombie.inventory.InventoryItem, boolean)"
$JAVAP -p -c /tmp/pzmoney/zombie/network/packets/INetworkPacket.class | grep -A8 "send(zombie.characters.IsoPlayer"
$JAVAP -p -c -constants /tmp/pzmoney/se/krka/kahlua/stdlib/BaseLib.class  | grep -oE 'String [a-zA-Z]+$' | sort -u
$JAVAP -p -c -constants /tmp/pzmoney/se/krka/kahlua/stdlib/TableLib.class | grep -oE 'String [a-zA-Z]+$' | sort -u
```

---

## 附录：本报告用到的全部游戏侧 file:line 清单

| 位置 | 内容 |
|---|---|
| `$G/media/scripts/generated/items/normal.txt:8636-8645` | `item Money` 完整定义 |
| `$G/media/scripts/generated/items/normal.txt:8647-8657` | `item MoneyBundle` 完整定义（含 `DoubleClickRecipe = UnbundleMoney`） |
| `$G/media/scripts/generated/recipes/recipes_packing.txt:168-182` | `UnbundleMoney`：1 MoneyBundle → 100 Money |
| `$G/media/scripts/generated/recipes/recipes_packing.txt:795-822` | 通用打包：`100:Base.Money` → `Base.MoneyBundle = Base.Money` |
| `$G/media/scripts/generated/recipes/recipes_packing.txt:802` | `100:Base.Money` 的 ItemCount 输入标记 |
| `$G/media/scripts/generated/items/container.txt:277` / `:1776` | `Bag_MoneyBag` / `Briefcase_Money`（钱的运输容器） |
| `$G/media/scripts/generated/models_items.txt:2900` / `:12883` | `model Money` / `model MoneyBundle` |
| `$G/media/lua/shared/Translate/CN/ItemName.json:1065,2268` | `Base.Money` = 钞票 / `Base.MoneyBundle` = 捆装钞票 |
| `$G/media/lua/server/ClientCommands.lua:1` | `if isClient() then return end`（服务端文件惯例） |
| `$G/media/lua/server/ClientCommands.lua:210-218` | 删袋 + `Remove` + `sendRemoveItemFromContainer` + `AddItem` + `sendAddItemToContainer` |
| `$G/media/lua/server/ClientCommands.lua:276-284` | `if isServer() then sendRemoveItemsFromContainer(...) end` |
| `$G/media/lua/server/ClientCommands.lua:1234` | `sendReplaceItemInContainer(item:getContainer(), item, item)` |
| `$G/media/lua/server/Camping/BuildingObjects/campingCampfire.lua:8-9` | `RemoveAll(type, n)` 的返回值直接喂 `sendRemoveItemsFromContainer` |
| `$G/media/lua/server/Fishing/BuildingObjects/FishingNet.lua:73-74` / `:69` | `AddItem` + `sendAddItemToContainer`，`isClient()` 早退 |
| `$G/media/lua/server/Traps/STrapGlobalObject.lua:321-322` | 同上 |
| `$G/media/lua/shared/NPCs/SurvivorSwap.lua:1,54-78` | 穿戴顺序 `AddItem` → `setWornItem`；`:73` setDrawDirty 注释 |
| `$G/media/lua/shared/BuildingObjects/TimedActions/ISShovelGround.lua:101-104` | `Remove` + `sendRemoveItemFromContainer` + `AddItem` |
| `$G/media/lua/shared/Moveables/ISMoveableSpriteProps.lua:4435` | `sendRemoveItemsFromContainer(inv, inv:RemoveAll(type, n))` |
| `$G/media/lua/shared/TimedActions/ISLitCandleExtinguish.lua:44-45` | `sendReplaceItemInContainer` + `replaceItemInContainer` 成对出现 |
| `$G/media/lua/client/ISUI/ISWorldObjectContextMenu.lua:1875-1882` | `getCountTypeRecurse` 可用性判定先例 |
| `$G/media/lua/client/ISUI/ISWorldObjectContextMenu.lua:1880` | `playerInv:getCountTypeRecurse(itemType)` |
| `$G/media/lua/client/ISUI/ISInventoryPaneContextMenu.lua:1652,2157,1942,1996` | `getItemsFromType` / `getSomeTypeRecurse` 用法 |
| `$G/media/lua/server/BuildingObjects/ISBuildUtil.lua:201-204` | `getAllTypeRecurse` + `items:size()` / `items:get(i-1)` |
| `$G/media/lua/shared/BuildingObjects/TimedActions/ISMultiStageBuild.lua:81-84,130` | 同上 + `#items` |
| `$G/media/lua/shared/TimedActions/ISReadABook.lua:470` | `getWornItems():getItem(ItemBodyLocation.EYES)` |
| `$G/media/lua/shared/NPCs/BodyLocations.lua:3,113` | `BodyLocations.getGroup("Human")` / `ItemBodyLocation.BACK` |
| `$G/media/lua/shared/Foraging/Categories/Trash.lua:67` | 翻垃圾出 `Base.Money` |
| `$G/media/lua/server/Camping/camping_fuel.lua:37,110` | `Money = 5/60.0`（钞票当燃料） |
| `$G/media/lua/server/Items/Distributions.lua:197-201,849,1677-1681` | 建筑战利品刷钱 / `PlankStashMoney` |
| `$G/media/lua/server/Items/ProceduralDistributions.lua:3034-3059` | `BankDeposit`（含 Money/MoneyBundle） |
| `$G/media/lua/server/Items/ProceduralDistributions.lua:19663-19695` | `DrugLabMoney` |
| `$G/media/lua/server/Vehicles/VehicleDistributions.lua:133-134,3460-3465` 等 | 车里刷钱 |
| `$G/media/lua/server/RandomizedWorldContent/StoryClutter/StoryClutter_Definitions.lua:588,612,901,1101,1318,1341-1342,1421` | 叙事杂物放钱 |
| `$G/media/lua/shared/Translate/*/ItemName.json` | 各语种钞票名（证明它是一等物品） |
| `~/Zomboid/console.txt`（`version=42.21.0 4a0e9546ec`） | 版本判定 |
