# Project Zomboid B42 联机"嵌套容器拿不出物品"根因与修复设计

> ⚠️ **本方案已于 2026-10-02 放弃**（用户决定）。模组目录已删除，仅保留本文档作为根因与证据记录；
> 现役方案见 `docs/pz-b42-nested-container-take.md`（物品拿取）与 `docs/pz-b42-nested-container-auto-unpack.md`（拿包即倒空）。

> 记录时间：2026-10-02　对象：Steam 工坊 [`3801776436`](https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436)
> **Nested Containers - Complete**（mod id `NestedContainersComplete`，ModOptions id `nm_nested_containers`）
> ＋ 游戏 **42.21.0 / build `4a0e9546ec`**（`projectzomboid.jar` class 文件主版本 69 → Java 25 运行时）
>
> **结论一句话**：原版 `zombie.network.fields.ContainerID` **无法表达"嵌套在物体容器里的容器"**
> （编码出的 `containerIndex` 恒为 `-1`），服务端据此解析出 `null` 容器，事务被 `Reject`，
> 物品永远不动且玩家侧没有任何提示；单机不走这条链，所以单机正常。
>
> 修复实现（ZombieBuddy 运行时字节码补丁）：[`bin2_nested_containers_mp_fix/`](../bin2_nested_containers_mp_fix/README.md)。

---

## 一、结论

| 问题 | 结论 |
|---|---|
| 症状 | 联机时无法从"嵌套容器"（战利品窗口里以容器按钮出现的包）取出/放入物品；单机正常 |
| 根因位置 | `zombie.network.fields.ContainerID#set(ItemContainer)` → `setObject(...)` 写出的 `containerIndex = -1` |
| 断链点 | `IsoObject.getContainerByIndex(-1) == null` → `Transaction.updateItem()` 的 `else return false` → 事务 `Reject` |
| 为什么单机没事 | 单机 `ISTransferAction:transferItem` 直接用对象引用搬运，完全不经过 `ContainerID`/`Transaction` |
| 原版是否知情 | 是。原版 Lua 注释里明确写了"物体容器里的包中包不做支持" |
| 修复思路 | 复用现有 `ContainerType.ObjectInVehicle` 的线格式，用 `vid = -1` 作哨兵，`worldItemId` 携带"容器所属物品 id"，服务端按格子 + 物品 id 递归定位 |
| 协议影响 | **零**：不新增 `ContainerType`，不改字段顺序与长度，不升协议版本 |

---

## 二、调用链（Lua → Java → 包 → 服务端）

```
[客户端 Lua]  ISInventoryTransferAction:start()
                 │
                 ├─ createItemTransaction()                       ← media/lua/client/TimedActions/ISInventoryTransferAction.lua
                 │
[客户端 Java]  zombie.core.TransactionManager.createItemTransaction(player, items, source, destination) : byte
                 │
                 └─ zombie.core.Transaction.set(player, items, source, destination, extra, dir, xoff, yoff, zoff)
                        │
                        └─ entries: List<Transaction$TransactionEntry>
                               └─ 每个待移动物品一个 entry：
                                      final Integer                  itemId
                                      final ContainerID              sourceId       ← 源容器的"网络地址"
                                      final ContainerID              destinationId  ← 目标容器的"网络地址"

       ContainerID.set(ItemContainer)                    ← ★ 问题就出在这里
           ├─ container.getContainingItem().getOutermostContainer()   // outermost
           └─ switch (outermost.getParent())
                  ├─ IsoPlayer    → setInventoryContainer(container, player)     // ✅ 服务端递归查找
                  ├─ BaseVehicle  → setObjectInVehicle(container, o, sq, part)   // ⚠️ 服务端非递归查找
                  └─ 其他 IsoObject → setObject(container, o, o.square)          // ❌ containerIndex = -1

[网络]         zombie.network.packets.ItemTransactionPacket           （ContainerID.write(ByteBuffer)）

[服务端]       ItemTransactionPacket 解析 → ContainerID.parse(...) → ContainerID.findObject()
                 │
                 ├─ zombie.core.TransactionManager.isConsistent(...) : byte   校验（Reject 在这里产生）
                 └─ zombie.core.Transaction.updateItem(entry) @ endTime       执行（container == null → false）
```

---

## 三、反编译证据（B42.21.0 / class 主版本 69）

> 取证方式：`unzip -p projectzomboid.jar <class> | ...` 后用
> `~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap -p -c <class>` 逐条读字节码。
> 下面的伪代码是**按字节码还原**的，不是反编译器的输出（有偏移量可复核）。

### 3.1 `ContainerID` 的字段与枚举

```java
public class zombie.network.fields.ContainerID implements INetworkPacketField {
    public  final PlayerID      playerId;
    public        ContainerType containerType;
    public        int           x;
    public        int           y;
    public        byte          z;
    /* 包私有 */  short         index;          // 物体在 square.getObjects() 里的下标
    /* 包私有 */  short         containerIndex; // 物体第几个容器
    /* 包私有 */  short         vid;            // 载具 id
    public        int           worldItemId;
    public        int[]         floorXY;
    /* 包私有 */  ItemContainer container;      // 解析结果（findObject 填充）
    /* 包私有 */  IsoObject     object;
}
```

`ContainerID$ContainerType` 的常量顺序（＝线格式里的 `ordinal()`，**顺序即协议**）：

```
Undefined, DeadBody, WorldObject, IsoObject, ObjectContainer, ObjectInVehicle, Vehicle, PlayerInventory, InventoryContainer, Floor
```

> 这条事实有两层意义：① 我们只是"用了一个已存在的枚举值"；② 因此不能插入新常量——插进去会改变所有后续常量的 `ordinal`，等于改协议。

### 3.2 `set(ItemContainer)` 按 outermost 的 parent 分支

字节码关键点（方法内偏移）：`18: instanceof IsoPlayer` → `60/70: InventoryItem.getOutermostContainer()` →
`80: instanceof IsoPlayer` → `96: setInventoryContainer(...)`；`103: instanceof BaseVehicle` → `117: setObjectInVehicle(...)`；否则落到 `setObject(container, o, o.square)`。

```java
public void set(ItemContainer container) {                                   // 偏移 12 起
    if (container == null) { containerType = ContainerType.Undefined; return; }   // 0–11
    IsoObject parent = container.getParent();                                     // 12–16
    if (!(parent instanceof IsoPlayer)                                            // 17–21
        && container.getContainingItem() != null
        && container.getContainingItem().getWorldItem() != null) {
        parent = container.getContainingItem().getWorldItem();                    // 24–48（地面物品包的情况）
    }
    if (container.containingItem != null
        && container.containingItem.getOutermostContainer() != null) {            // 49–63
        ItemContainer outermost = container.containingItem.getOutermostContainer(); // 66–73
        parent = outermost.getParent();                                           // 74–78  ★ 分支判据换成 outermost 的 parent
        if (parent instanceof IsoPlayer)                                          // 79–83
            setInventoryContainer(container, (IsoPlayer) parent);                 //     92–96
        else if (parent instanceof BaseVehicle)                                   // 102–106
            setObjectInVehicle(container, parent, parent.square, outermost);      //     109–117
        else
            setObject(container, parent, parent.square);                          //     123–130  ★ parent 为 null 时这里就 NPE
    }
}
```

**分支判据是"最外层容器的 parent"，不是"容器本身属于谁"。** 这就是 bug 的结构性来源：
一个背包里的包，它的最外层容器是玩家的 `ItemContainer`；而**一个放在板条箱里的包**
（板条箱里还有一层包），`container` 参数是那个**内层包自己的容器**，
但它并不属于板条箱 —— 却仍然走 `setObject`，并且被告知"你就是板条箱的容器"。

### 3.3 `setObject` 写出 `containerIndex = -1`

```java
public void setObject(ItemContainer container, IsoObject object, IsoGridSquare square) {
    x = square.getX(); y = square.getY(); z = (byte) square.getZ();
    this.container = container;
    if (object != null) {                                                  // 偏移 30: ifnull 70
        containerType  = ContainerType.ObjectContainer;                    // 34–38
        index          = (short) object.square.getObjects().indexOf(object); // 41–54
        containerIndex = (short) object.getContainerIndex(container);      // 57–64  ★ 这里是 -1
    } else {
        containerType  = ContainerType.IsoObject;                          // 70–74
        index          = -1;
        containerIndex = -1;
    }
}
```

`object.getContainerIndex(container)` 的语义是"**这个物体自己的**容器列表里的下标"。
嵌套包容器不属于这个物体，所以恒为 `-1`。

### 3.4 `IsoObject.getContainerByIndex(-1)` 返回 `null`

```java
public ItemContainer getContainerByIndex(int i) {          // 偏移 0：getfield container；ifnull 57
    if (container != null) {
        if (i == 0) return container;                      //  7–15：iload_1; ifne 16
        if (secondaryContainers == null) return null;      // 16–24：ifnonnull 25 / aconst_null; areturn
        if (i < 1 || i > secondaryContainers.size())       // 25–41：iconst_1; if_icmplt 41
            return null;                                   // 41：aconst_null; areturn   ★ -1 命中这里
        return secondaryContainers.get(i - 1);             // 43+
    }
    return null;                                           // 57
}
```

`i = -1` 既不是 `0`，也 `< 1`，因此**必然返回 `null`**（无论 `secondaryContainers` 是否为空）。

### 3.5 `findObject()` 把 `container` 解析成 `null`

`findObject()` 的开头就是 `container = null; object = null;`，然后按 `containerType` 分支。
`ObjectContainer` 分支：

```java
object    = square.getObjects().get(index);                    // 偏移 631–644
container = (object != null) ? object.getContainerByIndex(containerIndex) : null;  // 655–670
```

`containerIndex = -1` → `container = null`。

### 3.6 `Transaction.updateItem()` 返回 `false` → 事务 `Reject`

```java
private boolean updateItem(Transaction$TransactionEntry entry) {
    ...
    ItemContainer itemContainer = entry.sourceId.getContainer();   // 偏移 198–205
    if (itemContainer instanceof ItemContainer) {                  // 207–212：ifeq 243
        item = itemContainer.getItemWithID(entry.itemId);
        itemContainer.setExplored(true);
        itemContainer.setHasBeenLooted(true);                      // 215–240
    } else {
        return false;                                              // 243–244：iconst_0; ireturn  ★
    }
    ...
}
```

`container == null` 时 `instanceof` 为假，直接 `return false`。事务因此不会执行，最终被判 `Reject`
（`TransactionManager.isConsistent` 里两个 `TransactionState.Reject` 写入点在偏移 132 / 162 附近）。

`isConsistent` 的真实签名（同一份字节码）：

```java
public static byte isConsistent(int, InventoryItem, ItemContainer, ItemContainer,
                                String, zombie.network.packets.ItemTransactionPacket, IsoPlayer);
```

它失败时打印的诊断字符串（`ldc` 常量，已核对原文）：

```
Inconsistent: destination container can't be found (%s)
Inconsistent: source container is not contain the item (%s)
Inconsistent: destination container can't contain the item (%s)
Inconsistent: item to inventory (%s) t=(%s) / item from inventory (%s) / object to inventory (%s)
Inconsistent: this item is not on the floor (%s)
Inconsistent: destination square does not contain enough space for the item (%s)
Inconsistent: destination container is not contain enough space for the item (%s)
```

### 3.7 为什么玩家侧"什么提示都没有"

这些字符串都走 `DebugType.noise(...)`，而它的落点 `DebugLogStream.noiseWithTraceOffset(int, Object, Object...)`
的第一句是：

```java
if (!Core.debug) return;     // getstatic zombie/core/Core.debug; ifeq 23; ... return
```

**非调试模式（未加 `-debug`）时被静默丢弃。** 于是玩家的体验就是"点了没反应、东西拿不出来、也没有红字"。

### 3.8 单机为什么不走这条链

单机 `ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)`
拿的是**对象引用**，直接搬运；`ContainerID` / `ItemTransactionPacket` / `Transaction` 是联机专属基础设施。

原版在 Lua 侧留下了自述（`media/lua/client/TimedActions/ISInventoryTransferAction.lua`，本机 B42.21 文件第 25–27 行原文）：

```lua
-- Items can be taken from bags inside bags in the player's inventory.
-- This isn't done for bags inside bags in object containers.
-- Bags in vehicle containers and on seats work, since those are displayed in the loot window.
```

第 28 行紧跟着的判定也说明了 UI 层的同一假设：

```lua
if not containers:contains(self.srcContainer) and self.srcContainer:getOutermostContainer() ~= self.character:getInventory() then
    return false;
```

### 3.9 为什么载具"浅一层能用、深一层不能用"

`ContainerID.setObjectInVehicle(...)` 写的是 `containerType = ObjectInVehicle` + `BaseVehicle.vehicleId` + `index` + `worldItemId`（偏移 31–77）。
服务端解析这个分支走 `VehicleManager.instance.getVehicleByID(vid)` → `BaseVehicle.getPartByIndex(index)`，
**然后是非递归的** `part.getItemContainer().getItemWithID(worldItemId)`：

| 包的位置 | 服务端查找 | 结果 |
|---|---|---|
| 载具部件容器的**直接**子物品 | `part.getItemContainer().getItemWithID(id)` 命中 | ✅ 能用 |
| 部件容器 → 背包 → 再一层背包 | 递归不进去 | ❌ 解析为 null → Reject |

对照：`InventoryContainer` 分支用的是 `player.getInventory().getItemWithIDRecursiv(worldItemId)`（**递归**），
所以"玩家背包里的包中包"一直是好的。

### 3.10 顺带发现的客户端 NPE（同类根因）

"掉在地上的包"里的包：`outermost` 是那个**地面包自己的容器**，它的 `getParent()` 返回 `null`
（地面包不属于任何 `IsoObject`），于是走 `setObject(container, null, null.square)`。
按 §3.2 的字节码，`null.square`（偏移 126–127 的 `aload_2; getfield IsoObject.square`）在**进入
`setObject` 之前**就已经解引用，因此这里是**客户端 NPE**，而不是"写出一个坏地址"。
原版 `setObject` 内部对 `object == null` 是有处理的（偏移 70：写 `ContainerType.IsoObject`），
但那个兜底永远轮不到执行。

---

## 四、线格式与哨兵设计

`ContainerID.write(ByteBuffer)` 的实际布局（按 `ordinal` 分派）：

```
[容器类型: 1 byte = containerType.ordinal()]
├─ Undefined          → 结束
├─ PlayerInventory    → PlayerID
├─ InventoryContainer → PlayerID + worldItemId(int)
└─ 其他               → x(int) + y(int) + z(byte) + 按类型追加：
      ├─ Floor          → floorXY[]
      ├─ DeadBody       → ...
      ├─ WorldObject    → ...
      ├─ IsoObject      → index(short)
      ├─ ObjectContainer→ index(short) + containerIndex(short)      ← 就是我们修不好的那条路
      └─ ObjectInVehicle→ vid(short) + index(short) + worldItemId(int)   ← 复用这条
```

**哨兵编码（客户端）**：把"嵌套在物体容器里的容器"写成 `ObjectInVehicle` 形态：

| 字段 | 写入值 | 依据 |
|---|---|---|
| `containerType` | `ObjectInVehicle` | 线格式里信息量最大的一条（有 `worldItemId`） |
| `x, y, z` | 容器所在格子 | `ItemContainer.getSquare()`（兜底 `object.getSquare()`） |
| `vid` (short) | `-1` | 原版只会在 outermost 是 `BaseVehicle` 时产生此类型，`vid` 恒为非负 |
| `index` (short) | 物体在 `square.getObjects()` 里的下标 | **提示**，未知为 `-1` |
| `worldItemId` (int) | 容器所属背包物品 `getID()` | 物品 id 全局唯一 → 定位无歧义 |
| （`container`/`object` 字段） | 直接写入 | 本端不需要解码，但要保证本端逻辑一致 |

**服务端解析**（`findObject()` 钩子）：

1. 判据：`containerType == ObjectInVehicle && vid == -1 && worldItemId > 0`；
2. 取格子：`IsoWorld.instance.currentCell.getGridSquare(x, y, z)`，
   专用服务器上 `currentCell` 取不到时回落 `ServerMap.instance.getGridSquare(x, y, z)`；
3. 递归搜索（深度上限 8）：
   格子里每个 `IsoObject` 的所有容器 → `square.getStaticMovingObjects()`（尸体等，含 `BaseVehicle` 的部件容器）
   → `square.getWorldObjects()`（`IsoWorldInventoryObject` 地面物品包）→ `square.getVehicleContainer()`；
4. 先试 `index` 提示（快速路径），失败再整格扫描；
5. 命中 → 写回 `container`，**跳过原版方法体**；未命中 → 交回原版（打日志 + 拒绝，与修复前一致）。

**安全性论证**：

* `vid = -1` 与真车不可能撞号：`VehicleManager.getVehicleByID(short)` 是 map 查询，查不到返回 `null`，
  未打补丁端只会走 `DebugLog.log("ERROR: sendItemsToContainer: invalid vehicle id")` 并拒绝（＝修复前表现）；
* 线格式长度与顺序完全不变 → 未打补丁端不会解析错位（不会把 `worldItemId` 当成别的字段）；
* 三个钩子全部 `try/catch (Throwable)`，异常即 `return false`（交回原版）；
* `Main` 的反射式自检在启动时核对类/方法/字段/枚举常量，缺失即 `Fix.disable(reason)`，永久退回原版行为。

---

## 五、实现要点

| Patch | 目标方法 | 时机 | 作用 |
|---|---|---|---|
| `Patch_ContainerID_setObject` | `ContainerID#setObject(ItemContainer, IsoObject, IsoGridSquare)` | `OnEnter(skipOn = true)` | 容器是背包物品的容器、且 `object.getContainerIndex(container) == -1` 时写哨兵 |
| `Patch_ContainerID_setObjectInVehicle` | `ContainerID#setObjectInVehicle(...)` | `OnEnter(skipOn = true)` | 仅当 `part.getItemWithID(bagId) == null`（非直接子物品）时写哨兵 |
| `Patch_ContainerID_findObject` | `ContainerID#findObject()` | `OnEnter(skipOn = true)` | 识别哨兵并解析；**成功时跳过原版**，避免 `invalid vehicle id` 刷屏 |

实现细节（`NestedRef.java`）：

* `ContainerID` 的 `vid` / `index` / `container` / `object` 是**包私有**字段 → 用 `getDeclaredField` + `setAccessible(true)`；
* 钩子方法参数全部声明为 `Object`，返回值 `boolean`（`true` = 已接管）；
  这样 advise 类**静态不引用游戏类**，避免 ZombieBuddy 在类改写阶段触发连锁类加载；
* `Fix.java` 持有 `SENTINEL_VID = -1`、`MAX_DEPTH = 8`、`encoded/resolved/unresolved` 计数、
  `warnOnce(key, msg)` / `errorOnce(key, t)` 去重与熔断状态，日志前缀 `[NestedContainersMPFix] `；
* `Main.selfCheck()` 覆盖三个 patch 目标、五个 `ContainerID` 包私有字段，以及编码/解析用到的
  `ItemContainer` / `InventoryItem` / `InventoryContainer` / `IsoObject` / `IsoGridSquare` /
  `IsoWorldInventoryObject` / `BaseVehicle` / `VehiclePart` 成员。

---

## 六、兼容性矩阵

| 服务端 | 客户端 | 结果 | 说明 |
|---|---|---|---|
| 已装 | 已装 | ✅ 嵌套容器可用 | 目标场景 |
| 原版 | 已装 | ⚠️ 与修复前一致 | 服务端把 `vid = -1` 当非法载具 → `invalid vehicle id` → Reject；**不崩溃、不复制、不同步错乱** |
| 已装 | 原版 | ✅ 与修复前一致 | 原版客户端不产生哨兵，走老路径 |
| 原版 | 原版 | ❌ 原 bug | — |

另外：

* 单机（`GameClient.client == false && GameServer.server == false`）下钩子直接放行，零影响；
* 玩家背包里的包中包（`InventoryContainer` 路径）与载具直接子背包（`ObjectInVehicle` 原版路径）
  都被钩子主动放行，行为不变。

---

## 七、已知限制

1. **需要服务端与客户端同时安装**；服务端缺失＝行为退回修复前（这是本设计的语义边界，不是实现缺陷）。
2. 解析依赖"容器与物品在同一个方块"，且该方块已加载；未加载时打
   `WARN resolve: square X,Y,Z not loaded yet, fallback to vanilla` 并退回原版。
3. `index` 提示可能因方块物体列表变化而失效 → 退化为整格递归扫描（正确但更慢）。
4. 递归深度上限 8 层。
5. 依赖物品 id 全局唯一；物品在解析前被销毁/移动会导致解析失败 → 退回原版。
6. 不新增 `ContainerType`、不改协议版本（换取向后兼容）。
7. 未覆盖第三方 Lua 容器与 `Floor`/`WorldObject` 分支的嵌套寻址。

---

## 八、验证状态

**已完成（静态/编译期）**

| 项 | 方式 | 结果 |
|---|---|---|
| 构建产物 | 只读检查 `media/java/NestedContainersMPFix.jar` | ✅ 存在，内含 6 个 `nestedcontainersmpfix/*.class`，class 主版本 61（＝`build.sh` 的 `--release 17`）；✅ 该 JAR 由当前 `src/` 构建（JAR mtime 晚于所有源文件，构建时间 16:54，源码最后改动 16:51），`./tools/selfcheck.sh` 离线自检 PASS |
| Patch 目标存在性 | `javap -p -c` 核对 `projectzomboid.jar` | ✅ `setObject` / `setObjectInVehicle` / `findObject` / `vid` / `index` / `worldItemId` / `container` / `object` / `ContainerType.ObjectInVehicle` 全部存在 |
| 断链点 | 同上 | ✅ `getContainerByIndex(-1) → null`、`updateItem` 的 `else ireturn false`、`invalid vehicle id` 字符串原文均已复核 |
| 原版自述 | 本机游戏 Lua 文件 | ✅ `ISInventoryTransferAction.lua:25-27` 原文一致 |

**未完成（运行时）**

* ❌ **从未在真实联机会话中执行过**（未起专用服务器、未做双客户端实测）——
  "能取出物品"是**设计推断**，不是实测结论；
* ❌ 未抓过真实 `ItemTransactionPacket` 往返；
* ❌ 尸体 / 载具深嵌套 / 地面物品包三条解析分支未逐个实测；
* ❌ 性能未测量。

详见 [模组 README 的"手工联机验证清单"](../bin2_nested_containers_mp_fix/README.md#手工联机验证清单)。

---

## 九、参考链接

* Nested Containers - Complete（被修复的 UI 模组，工坊 `3801776436`，标题实际带 `[SP]` 后缀）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，作者 Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* ZombieBuddy（Java agent 运行时字节码补丁框架，工坊 `3619862853`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853
* ZombieBuddy GitHub（`Patch` / `@Patch.OnEnter(skipOn=...)` / `@Patch.This` / `@Patch.Argument` API）— https://github.com/zed-0xff/ZombieBuddy
* ZombieBuddy ModdingGuide（`media/java/` 路径的 client/server 过滤规则）— https://raw.githubusercontent.com/zed-0xff/ZombieBuddy/master/doc/ModdingGuide.md
* ZombieBuddy Installation（macOS/Linux 手动安装、`-javaagent:ZombieBuddy.jar=... --`）— https://raw.githubusercontent.com/zed-0xff/ZombieBuddy/master/doc/Installation.md
* PZ 官方 Modding Javadoc（`ContainerID` / `ItemContainer` / `IsoObject`）— https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* PZ Wiki: Java — https://pzwiki.net/wiki/Java （站点有 Cloudflare 挑战页，脚本/工具访问返回 403，需浏览器打开）

> 链接核对记录（2026-10-02，`curl -L -o /dev/null -w '%{http_code}'`）：上面第 1–7 条均返回 **HTTP 200**；
> `pzwiki.net` 对所有路径（含站点根）返回 Cloudflare **403 挑战页**，非 404，因此保留并标注。
> 另外核对过 `projectzomboid.com/modding` 下的 `ContainerID.ContainerType.html` / `ItemContainer.html` /
> `IsoObject.html` / `InventoryContainer.html` / `IsoWorldInventoryObject.html` 均为 200；
> 而 `zombie/core/Transaction.html` / `zombie/core/TransactionManager.html` /
> `zombie/network/packets/ItemTransactionPacket.html` 均为 **404**（该 javadoc 只覆盖公开 API 子集）。
> 因此正文的核心证据一律以**本机 `javap` 为准**，只把能打开的类页面列进参考链接。
> 文中所有行号、日志字符串与字节码偏移均为本机 B42.21.0（`4a0e9546ec`）文件实测，可复现。
