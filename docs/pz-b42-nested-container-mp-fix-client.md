# Project Zomboid B42 联机嵌套容器：纯客户端"三步法"设计

> ⚠️ **本方案已于 2026-10-02 放弃**（用户决定）。模组目录已删除，仅保留本文档作为根因与证据记录；
> 现役方案见 `docs/pz-b42-nested-container-take.md`（单品拿取）与 `docs/pz-b42-nested-container-auto-unpack.md`（拿包即倒空）。

> 记录时间：2026-10-02　对象：模组 **NestedContainersMPFixClient v1.0.0**
> （[`bin2_nested_containers_mp_fix_client/`](../bin2_nested_containers_mp_fix_client/README.md)）
> ＋ 游戏 **42.21.0 / build `4a0e9546ec`**
>
> **前置文档**：引擎级根因、反编译（`javap`）证据、ZombieBuddy 哨兵线格式设计见
> [`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)；
> 纯 Lua 客户端/服务端协议设计见
> [`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)。
> **本文件不重复那些字节码证据**，只重述一段根因，然后专注讲"**不新增协议、服务端零安装**"的纯客户端改写方案。
>
> **结论一句话**：客户端只补一个方法 `ISInventoryTransferAction:start()` ——
> 当这次搬运有一端是"嵌在物体容器里的包"这类**原版网络地址表达不了**的容器时，
> **不创建原版事务**，而是往动作队列里插一段**原版自己的 `ISInventoryTransferAction` 序列**：
> 先把嵌套包按层级**提升**到玩家背包（每一步都是"物体容器 → 玩家背包"或"玩家背包里的包 → 玩家背包"），
> 此时两端都变成原版能寻址的普通容器，于是**真正搬运**就是一次普通原版事务，
> 最后把包**逆序放回**原处（内层先回到外层包里，外层包此刻还在玩家背包里）。
> 服务端从头到尾只看到原版事务，用原版逻辑执行并广播 —— **不需要在服务器上装任何东西**。
> 代价是**受影响的背包会可见地短暂进出玩家背包**（其他玩家也看得到），以及一次搬运变成多次搬运。

---

## 一、根因（一段话）

原版 `zombie.network.fields.ContainerID` **无法表达"嵌套在物体容器里的容器"**：
`ContainerID#set(ItemContainer)` 处理包容器时会取该包的**最外层容器**，再按最外层容器的 `parent` 分支；
当 `parent` 是板条箱 / 衣柜 / 货架 / 尸体这类普通 `IsoObject` 时，它走
`setObject(container, o, o.square)`，写出的 `containerIndex = o.getContainerIndex(container) == -1`；
服务端 `ContainerID#findObject()` 据此调用 `object.getContainerByIndex(-1)` → `null`（`zombie.iso.IsoObject`），
于是 `Transaction#updateItem()` 返回 `false`，事务被 Rejected —— **物品永远不动，玩家侧也没有任何提示**。
单机从不使用 `ContainerID` / `Transaction`（`ISTransferAction:transferItem` 直接操作对象引用），所以单机一直正常。
（逐条字节码证据：前置文档第三、四章。）

本模组**既不修引擎，也不另开协议** —— 它承认"这条线上的**地址**坏了"，
于是**先花几次合法搬运把地址修好，再搬真正要搬的东西**。

---

## 二、为什么是"改写"而不是"新通道"

| | 原版事务通道 | Java 版（`mp_fix`） | 协议版（`mp_fix_lua`） | **本方案（纯客户端）** |
|---|---|---|---|---|
| 修在哪 | — | `ContainerID`（引擎内，字节码补丁） | `ISInventoryTransferAction` + 自定义命令 | **只改 `ISInventoryTransferAction` 的时序** |
| 服务端安装 | — | **必须**（ZombieBuddy + 模组） | **必须**（模组） | **什么都不用装** |
| 新增网络面 | — | 无（复用 `ObjectInVehicle` 线格式） | 有（`sendClientCommand` 命令） | **无**（服务端只看到原版事务） |
| 观察者视图 | — | 精确（原版广播） | 受广播锚点限制（可能陈旧） | **受影响的背包会可见地位移** |
| 一次搬运的代价 | 1 | 1 | 1 次往返 | **1 层 3 次、N 层 `2N+1` 次原版搬运** |

**为什么不能和另外两个同时装**：被本方案接管的搬运**根本不会去构造 `ContainerID`**，
所以 Java 版补在 `ContainerID` 上的钩子在这些搬运上**永远不会被触发**；
而本方案假设"服务端是纯原版"，协议版的超时/握手语义也无从谈起。
三者修的是同一个缺陷，**同一时间只装一个**。

---

## 三、三步法：把一次坏搬运改写成多次好搬运

### 3.1 流程

```
                             ┌─ 提升 (lift)  ：物体容器 → 玩家背包（外层包先走；多层时逐层走）
一次坏掉的搬运（两端之一）───┼─ 搬运 (move)  ：item: src → dst（此时两端都可寻址，就是一次普通原版搬运）
                             └─ 放回 (return)：玩家背包 → 物体容器（内层先回，最外层最后回）
```

`NR.buildDancePlan(player, item, src, dst)`
（[`Reach.lua:139`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L139)）
把计划构造成一张**按执行顺序排列的 `{ item, src, dst }` 列表**：

1. 对**源端**、再对**目标端**，各自调用一次 `collectLifts`：
   如果该容器原版可寻址就直接返回；否则 `chainAndRoot` 取出"背包含（外→内）"，
   **外层包先提升**（`table.insert(chain, 1, bag)` 保证顺序），逐个生成 `{ bag, home, playerInv }`；
2. 插入一条 `{ item, srcContainer, destContainer }` —— 这才是**真正要搬的东西**；
3. **逆序**把提升过的包放回：`for i = #lifted, 1, -1 do … { bag, playerInv, home }`。

同时返回**被提升的背包 id 列表**（`liftedIds`），供事后修面板用（第六节）。

### 3.2 每一步为什么都是"原版合法事务"

判定标准是 `canVanillaAddress`（第四节），它镜像的就是 `ContainerID#set` 的分支规则。
三步法用到的方向一一落在**原版本来就能寻址**的那几支上：

| 步骤 | 源端 → 目标端 | 落在原版的哪一支 |
|---|---|---|
| 提升（第 1 层） | 物体容器 → 玩家背包 | 源端 `ObjectContainer`（`parent` 是 `IsoObject`，`index`/`containerIndex` 都有效）；目标端 `PlayerInventory` |
| 提升（第 N 层） | 玩家背包里的包 → 玩家背包 | 源端 `InventoryContainer`（服务端 `getItemWithIDRecursiv` **递归**查找） |
| 搬运 | 玩家背包里的包 ↔ 玩家背包里的包 | 两端都是 `InventoryContainer` |
| 放回（内层） | 玩家背包 → 玩家背包里的包 | 目标端 `InventoryContainer`；**此刻外层包还在玩家背包里**，所以目标端可寻址 |
| 放回（最外层） | 玩家背包 → 物体容器 | 目标端 `ObjectContainer`：`containerIndex` 由**物体容器本身**上的 `getContainerIndex` 求得，不是 `-1` |

两个细节决定了正确性：

* **逆序放回**：放内层包时，外层包必须**还留在玩家背包里**。顺序一旦反了，内层包的目标容器
  就变回"物体容器里的包"，又成了原版寻址不了的形态。
* **被搬运的物品本身如果是链上的某一层包，不进提升列表**
  （`bag:getID() == item:getID() → break`）：把这只包搬出去**就是**这次搬运本身，不是前置条件。

### 3.3 与"协议版"的本质差别

协议版把容器的**真实位置**声明给服务端，让服务端自己去定位；
本方案**不声明任何东西**，只改变操作的**先后顺序**，让每一步都落在原版已经支持的形态上。
因此：

* 服务端**没有任何新代码路径**要信任 —— 它执行的每一笔都是它本来就会执行的；
* 物品个数上限（`ItemNumbersLimitPerContainer`）、容量校验（`hasRoomFor` / `isItemAllowed`）
  **完全是原版的**（协议版需要自己复刻这些校验，本方案不用）；
* 没有握手、没有超时、没有回执字段，也就没有"协议版本协商"。

---

## 四、可寻址性判定：`canVanillaAddress`

`NR.canVanillaAddress(container)`
（[`Reach.lua:83`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L83)）
的每条分支都对应 `ContainerID#set` 的一个分支：

| 判定 | 命中的原版分支 | 服务端怎么找回来 | 结论 |
|---|---|---|---|
| `container:getParent()` 是 `IsoPlayer` | `setInventoryContainer` → `PlayerInventory` | `player:getInventory()` | ✅ |
| 无 `containingItem`（floor / worldItem 容器） | floor 分支（`getFloorContainer` / `getFloorSquare`） | 按 `x,y,z` 取回方格 + `worldItemId` | ✅ |
| 有 `containingItem`，且它已不在任何容器里 | —（**失效引用**） | — | ❌（且必须**安全放弃**，见 5.2） |
| 最外层容器 `parent` 是 `IsoPlayer` | `setInventoryContainer` → `InventoryContainer` | `player:getInventory():getItemWithIDRecursiv(id)`（**递归**） | ✅ |
| 最外层容器 `parent` 是 `BaseVehicle` 且该包是**直接子物品** | `setObjectInVehicle` | `part:getItemContainer():getItemWithID(id)`（**非递归**） | ✅ |
| 最外层容器 `parent` 是 `BaseVehicle` 但包**再套了一层** | 同上 | 同上 —— 非递归查找找回**深层**包 | ❌ |
| 最外层容器 `parent` 是其他 `IsoObject`（箱 / 柜 / 尸体…） | `setObject(container, o, o.square)` | `object.getContainerByIndex(-1)` → `null` | ❌ |
| 容器为 `nil` | — | — | ✅（判为"原版可用"，让原版自己去处理/失败） |

配套的两个内部函数：

* `NR.itemOutermost(bag)`
  （[`Reach.lua:43`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L43)）
  **逐条镜像** `zombie.inventory.InventoryItem#getOutermostContainer()`
  （本机 `javap -p -c` 复核）：`container == null` 或 `container:getType() == "floor"` 直接返回 `nil`；
  否则沿 `container:getContainingItem()` 向上走，遇到"所属物品没有容器"或"所属容器是 floor"就停。
  这个 `floor` 短路是**语义的一部分**（原版就是用"最外层是 floor"来表示"这是个地面物品分支"）。
* `NR.chainAndRoot(container)`
  （[`Reach.lua:65`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L65)）
  从容器沿 `getContainingItem()` / `bag:getContainer()` 向上走，返回
  "背包含（**外→内**）+ 根容器"；深度上限 `NR.MAX_DEPTH = 8`（防御性上限，正常玩法到不了）。

`NR.needsDance(item, src, dst)` = 两端任意一端判为 ❌。

### 4.1 "掉在地上的包，包里还有包"确实由三步法接管

必须分深度，两种情况的结论相反：

* **深度 0（包直接躺在地上）**：`container:getContainingItem():getWorldItem() ~= null`，
  `ContainerID#set` 会把 `o` 换成该格的 `IsoWorldInventoryObject`，随后走 `WorldObject` 分支
  （`worldItemId` = 那只包的 id），服务端 `findObject()` 据此取回它的容器。
  ⇒ 原版可用，`canVanillaAddress` 返回 `true`，本模组**放行**。
* **深度 ≥ 1（地上的包里再套着包）**：`InventoryItem#getOutermostContainer()` 返回的是
  "外层包自己的容器"（`this.container.type` 是物品类型而不是 `floor`，所以既不触发 `floor` 短路，
  循环条件 `!"floor".equals(outer.getContainingItem().getContainer().type)` 也不成立，直接返回该容器）。
  接着 `outermost.getParent()` 为 **`null`**（背包容器由 `new ItemContainer()` 创建，`parent` 恒为 null），
  代码落到 `setObject(container, o, o.square)` 且 `o == null` ⇒ **客户端 NPE**。
  ⇒ `canVanillaAddress` 返回 `false`，**三步法接管**：两层包一起提升 → 搬运物品 → 逐个放回地面
  （`home` 就是那个 `floor` 容器，放回等价于正常丢回地面）。

`floor` 分支（`getFloorContainer` / `getFloorSquare`）只在 `getOutermostContainer() == null`
或容器没有 `containingItem` 时进入，与上面第二种情况无关。


## 五、两处边界加固（都是真实缺陷修复）

三步法本身只重排时序；下面两处是**会让修复静默失效、或把玩家卡死**的真实缺陷。

### 5.1 编排动作禁止参与原版多物品合并（`canMergeAction`）

**症状**：从"把物品放进嵌套包"这个方向操作时，三步法会**整条白跑** —— 状态不损坏，但物品还是进不去。

**原因链**（全部在原版 Lua 里可读）：

1. 编排动作是 `(物品, 玩家背包, 嵌套包)`；紧随其后的"真正搬运"步骤**也是** `(物品, 玩家背包, 嵌套包)`；
2. 原版 `perform()` 会调用 `checkQueueList()`（`client/TimedActions/ISInventoryTransferAction.lua:712`），
   它用 `canMergeAction`（`:702`）判断"队列里紧随其后的动作能不能吞并"，
   条件是 `Type` / `srcContainer` / `destContainer` 相同（且没有 `onCompleteFunc`、`allowMissingItems` 一致）；
3. 命中后该步骤被并入 `self.queueList`，`perform()` 走到
   `if #self.queueList > 0`（`:508`）分支时会**重新调用原版 `createItemTransaction`**（`:526`）——
   **回到坏掉的那条路**，服务端照旧拒绝，核心动作被吞掉。

**为什么不总是被拦下**：这套合并里还有一条 `if action.onCompleteFunc or self.onCompleteFunc then return false end`
（`:707`）。本方案只在**有背包被提升**时才会给最后一个步骤挂 `onComplete`
（用于修面板，第六节）；当 `liftedIds` 为空时（例如源端本来就是原版的直接子背包 / 地面物品，
只有目标端是嵌套包）**没有任何 `onComplete`**，于是核心步骤就会被合并 —— 修复静默失效。

**修法**（[`Client.lua:30`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/client/NestedContainersMPFixClient/Client.lua#L30)）：

```lua
function ISInventoryTransferAction:canMergeAction(action)
    if self.ncfOrchestrator then
        return false
    end
    return OLD_canMerge(self, action)
end
```

* `runDance` **先**置 `action.ncfOrchestrator = true`（`:65`）**再**插入步骤；
  插入失败时清回 `nil`（`:69`）—— 保证"插入中途出错"的编排动作也不会被误合并；
* **插入的步骤本身仍然允许被合并**（`ncfDanceStep` 不阻止合并）：那时容器已经可寻址，
  合并是正常且有益的 vanilla 行为（多件小物品会按原版规则批量处理），只是让三步法自己多跑几轮"搬运"。

### 5.2 失效容器引用：安全放弃，而不是交回原版（`NR.isDetached`）

**症状**：loot 面板可能还捏着一份**已经被服务端移除又重新加入**的旧容器对象。
这个容器对象本身还在，但 `container:getContainingItem():getContainer() == nil` ——
挂着的物品已经不在任何容器里了。

**为什么不能交回原版**：`ContainerID#set` 在这条路上会落进 floor 分支，
而 `getFloorContainer(container)` 此时返回 `null` ⇒ `IllegalStateException: Unable to resolve container location.`；
即便侥幸不抛，也会产生一个 `createItemTransaction` 返回 `0`、
**永远等不到服务端回执**的事务 —— 玩家**一直卡在搬运动作里**。

**修法**：判定与收尾分成两段。

* `NR.isDetached(container)`
  （[`Reach.lua:117`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L117)）：
  `container:getContainingItem() ~= nil and bag:getContainer() == nil`；
* `canVanillaAddress` 对失效引用返回 **false**（不信任原版）；
* 但 `buildDancePlan` 对失效引用也**编不出计划**（`chainAndRoot` 走不到根容器 ⇒ 返回 `nil`），
  所以**不能**用"计划失败就回落 `OLD_start`"——那等于把它交回原版。于是 `start()` 里的顺序是：

| 顺序 | 情况 | 处理 |
|---|---|---|
| 0 | `self.ncfDanceStep`（三步法自己的步骤） | 直接 `OLD_start`（永不再编排） |
| 1 | `needsDance` 为假 | `OLD_start`（**一个字节都不改**） |
| 2 | 能编出计划 | 接管：插入步骤 + 空转完成 |
| 3 | 编不出计划，但**任一端 `isDetached`** | `warnOnce("detached", "stale container reference; skipping this transfer")` + `started = true` + `self.action:setTime(0)`：**空转完成，什么都不搬，绝不进原版** |
| 4 | 其它失败原因（拿不到物品/背包、根容器解不出、`insertSteps` 失败、`runDance` 抛错） | `warnOnce("dance-failed", "dance aborted, falling back to vanilla behaviour")` + `OLD_start`（**等价修复前行为**） |

一句话：**能编排就编排；引用失效就安全放弃；其余才回落原版。**

---

## 六、实现要点

### 6.1 唯一的补丁点与插入手法

* 只保存两个旧实现：`OLD_start = ISInventoryTransferAction.start`、`OLD_canMerge = ISInventoryTransferAction.canMergeAction`
  （[`Client.lua:22-23`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/client/NestedContainersMPFixClient/Client.lua#L22)）。
* `ISInventoryTransferAction:new` **没有被改写**：决策放在 `start()` 时刻做，
  这样它反映的是**当时**的世界状态（`new` 到 `start` 之间，原版 `isValid()` 可能已经改过 `dontAdd` 等状态）。
* 插入步骤：

  ```lua
  local queued = ISInventoryTransferAction:new(player, step.item, step.src, step.dst, 1)
  queued.ncfDanceStep = true      -- 永不再次编排
  queued.stopOnWalk = false       -- 三步法必须原地一站做完
  queued.stopOnRun  = false
  ISTimedActionQueue.addAfter(owner, queued)   -- owner 链式往后接
  ```

  `addAfter` 的调用形态与原版 `shared/Vehicles/TimedActions/ISAddGasolineToVehicle.lua:99/102` 一致。
* 编排动作自己**空转完成**，把节奏交给插入的步骤（原版 `isAlreadyTransferred` 早退分支就是同一手法）：

  ```lua
  action:playSourceContainerOpenSound()   -- perform() 会放开包收尾音，开包音本来在 start() 里放
  action:playDestContainerOpenSound()     -- （ISInventoryTransferAction.lua:283/284）
  action.started = true                   -- 原版 start() 结尾同样设置（:317）；isValid() 用它跳过一致性检查
  action.action:setTime(0)                -- 原版 :261 / :267 也是这么写的
  ```

* 失败兜底：`start()` 把编排整体包在 **`pcall(runDance, self)`**（`:109`）里；
  任何异常都只 `warnOnce` 一行，然后走 `OLD_start`。

### 6.2 `mod.info` 关键项

| 键 | 值 | 说明 |
|---|---|---|
| `id` | `NestedContainersMPFixClient` | 模组 id |
| `modversion` | `1.0.0` | 与 `NR.VERSION` 一致 |
| `versionMin` | `42.20.0` | 游戏版本下限 |
| `require` / `javaJarFile` / `poster` | **无 `require`、无 `javaJarFile`**；`poster=poster.png` | 零依赖、无 Java、无构建（对比 Java 版需要 `require=\ZombieBuddy` + `javaJarFile`） |

### 6.3 日志

| 类型 | 行 | 触发 |
|---|---|---|
| info | `[NestedContainersMPFixClient] nested transfer detected: using lift -> move -> return (N vanilla transfers)` | **每局一次**（`NR.loggedOnce`）；`N = #plan`（1 层通常 3，N 层通常 `2N+1`） |
| warn | `WARN stale container reference; skipping this transfer` | 每局一次；命中 5.2 的安全放弃 |
| warn | `WARN dance aborted, falling back to vanilla behaviour: …` | 每局一次；命中 5.2 的第 4 步 |
| warn | `WARN pane re-select failed: …` | 每局一次；面板重选出错（不影响搬运结果） |
| warn | `WARN cannot resolve the outermost container (source/destination), skip dance` | 每局一次；`chainAndRoot` 解不出根 |
| warn | `WARN owning container of a nested bag is gone, skip dance` | 每局一次；要提升的包的"家"不见了 |

### 6.4 面板重选：尽力而为的收尾（`NR.reselectPane`）

**问题**：背包被"放回"时，服务端 packet 会在客户端**新建一份背包物品对象**，
而 loot / 背包面板可能还捏着**旧的容器对象**（`page.inventoryPane.inventory` 指向已失效的容器）。

**做法**（[`Reach.lua:205`](../bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/media/lua/shared/NestedContainersMPFixClient/Reach.lua#L205)）：
按物品 id 把面板重新指到新容器上，但**只在面板当前正看着被移动的那些背包时才动手**：

* 比对 `page.inventoryPane.inventory:getContainingItem():getID()` 与本次提升的 id 集合，不匹配就**不动**（不抢玩家的界面）；
* 依次尝试 `getPlayerInventory(num)` 与 `getPlayerLoot(num)` 两个页面，命中就 `page:selectButtonForContainer(inventory)`。

**三处加固**（由 `onComplete` 的调用环境决定：它是在原版 `perform()` 内部被调用的，
异常会冒泡进动作队列推进逻辑）：

1. `getPlayerInventory(num)` 取不到时**退回 `getPlayerData(num).playerInventory`**
   （原版 `ISInventoryPage.dirtyUI`（`client/ISUI/ISInventoryPage.lua:1330`）与
   `client/Hotbar/ISHotbar.lua:619` 都是这么拿玩家背包面板的）；
2. 挂 `onComplete` 时用 **`pcall(NR.reselectPane, player, liftedIds)`** 包住（`Client.lua:75-81`）；
3. 出错只打一次 `pane re-select failed: …`。

**语义**：**只在面板正看着被移动的那些背包时才重选；取不到面板或重选出错都不影响搬运结果。**

---

## 七、失败级联：为什么不会卡死

三步法是**普通动作序列**，没有事务、没有回滚；安全性来自"**任何一步失败，后面的步骤都会自己收敛**"：

| 失败点 | 后续行为 |
|---|---|
| 某个提升步骤被服务端拒绝（理论上不该发生：两端都可寻址） | 包还在原处 ⇒ "真正搬运"的源端不可寻址 ⇒ 被服务端拒绝 ⇒ 原版 `update()` 把它收进 `forceStop`；放回步骤命中 `isAlreadyTransferred` 早退（`ISInventoryTransferAction.lua:563`，`destContainer:contains(item)` 已为真）⇒ 瞬间完成 |
| 真正搬运被拒绝（例如容量不够） | 物品留在原处；放回步骤照常把背包一一放回 |
| 放回步骤被异常打断 | 背包留在玩家背包里（**不丢、不复制**，可手动放回） |
| 编排失败 / 失效引用 | 见 5.2：安全放弃或回落原版，**都不会留下"永远等不到回执的动作"** |

**没有一条路径会把玩家留在卡死状态** —— 这正是 5.2 把"失效引用"单独分出来、
而不与"其它失败"共用回落逻辑的原因。

---

## 八、兼容性矩阵

| 服务端 | 客户端 | 结果 |
|---|---|---|
| 纯原版（什么都没装） | 装了本模组 | ✅ **目标场景**：嵌套容器可用（受影响的背包会短暂进出玩家背包） |
| 装了 Java 版 / Lua 版 | 同时装了本模组 | ❌ **不要这么干**：被本方案接管的搬运不会构造 `ContainerID`，Java 版钩子不触发；协议版的握手语义也失效 |
| 纯原版 | 原版客户端 | ❌ 原 bug |
| 单机 | — | ✅ 零影响（`not isClient()` ⇒ 客户端文件直接 `return`） |

---

## 九、威胁模型

**新增网络面：无。** 客户端没有新增任何 `sendClientCommand` / `sendServerCommand`，
也没有改 `ContainerID` 的线格式；服务端收到的仍然只有原版 `ItemTransactionPacket`。

| 攻击面 | 处置 |
|---|---|
| "客户端伪造地址" | 不存在地址声明 —— 每一步都是原版事务，服务端用原版 `TransactionManager.isConsistent` 与 `Transaction.updateItem` 独立校验/执行 |
| "客户端越权拿别人的东西" | 每一步都要过原版 `isValid()`（含 `srcContainer:contains(self.item)`、距离/安全屋相关分支） |
| "绕过容量 / 件数上限" | **不绕过**：每一步都是原版 `ISInventoryTransferAction`，容量与 `ItemNumbersLimitPerContainer` 校验原样生效 |
| "新增协议解析漏洞" | 无新解析面（不新增字段、不新增命令） |
| 客户端自身健壮性 | 编排整体 `pcall`；面板回调 `pcall`；两条失败分支都只 `warnOnce` 一行 |

**固有弱点（设计取舍，不是遗漏）**：三步法是**多次独立事务**，不是原子操作 ——
中途失败会留下"包在玩家背包里"这种**中间态**（不丢东西、可手动恢复）。
这一点与另外两个方案（一个改引擎、一个有服务端权威）有本质区别，见第四节与第十节。

---

## 十、已知限制

1. **受影响的背包会可见地位移**：提升 / 放回都是真实搬运，**其他玩家也会看到**你的背包短暂进出背包。
2. **放回被异常打断 ⇒ 背包留在玩家背包里**：不丢、不复制，玩家可手动放回；mod 不做事务性回滚。
3. **一次搬运变成多次**：1 层 3 次、N 层 `2N+1` 次，更慢更吵（更多翻包音效与动画）；
   多件物品时是"若干个三步法序列首尾相接"。
4. **面板重选是尽力而为**（6.4）：只在面板正看着被移动的那些背包时才重选；
   取不到面板或重选出错**都不影响搬运结果**，但可能短暂显示旧容器。
5. **补丁了 `ISInventoryTransferAction`**：与同样补丁这个类的模组存在**加载顺序**关系
   （后加载者的 `OLD_start` / `OLD_canMerge` 指向先加载者的版本）。
6. **只在"原版寻址不了"时介入**：其它所有搬运保持**与修复前逐字节相同**的原版路径。
7. **深度上限 8**：`MAX_DEPTH = 8`（`itemOutermost` / `chainAndRoot` 共用），超过就放弃编排（防御性上限）。
8. **不处理"原版本身就不允许"的情形**：例如 `dontAdd` / `isAlreadyTransferred` 之类的原版早退语义，
   本方案**不复制**（受影响的动作会走原版自己的早退）。

---

## 十一、验证状态

### 11.1 本文档对应的源码修订

以 `bin2_nested_containers_mp_fix_client/Contents/mods/NestedContainersMPFixClient/42.21/` 为基准
（源码已冻结；如后续改动，哈希会变化，可据此判断文档是否过期）：

| 文件 | 行数 | mtime | SHA-256 |
|---|---|---|---|
| `media/lua/shared/NestedContainersMPFixClient/Reach.lua` | 254 | 17:54:28 | `d6a56f71a7a0c1edefa3d82510b11b9e096f023c7413c822de575f70d91c84b8` |
| `media/lua/client/NestedContainersMPFixClient/Client.lua` | 130 | 17:54:28 | `60cf3b70a144bb5257dcfa796c3dffea86e31c45d5e80ddcc5cf7c5aef0c3473` |
| `mod.info` | 24 | 17:48:06 | `5150347f1b434131490269a62ec2af97daba297a8ea7cdaf5df760e1ef2e213d` |

### 11.2 已完成（静态、可复现）

| 项 | 方式 | 结果 |
|---|---|---|
| API 契约 | `bin2_nested_containers_mp_fix_client/tools/apicheck.sh`（只读；把 20 个 API 回查游戏自带 `media/lua`） | ✅ 本机实测输出 `== 全部命中（20 项）==`（本次源码修订后复跑，结果不变） |
| 语法 | `luaparse`，`luaVersion: '5.1'` | ✅ 两个 Lua 文件解析通过（本机**没有 Lua 解释器**，因此没有执行过任何一行 Lua 代码） |
| 原版 API 出处 | 逐行读本机游戏 Lua | ✅ `ISInventoryTransferAction:start:258`（`isAlreadyTransferred` 早退 `:259`、`setTime(0)` `:261`、开包音效 `:283/284`、`started = true` `:317`）、`perform:477`（`checkQueueList:481`、`#queueList > 0:508`、二次 `createItemTransaction:526`、`onCompleteFunc:543`）、`isAlreadyTransferred:563`、`canMergeAction:702`（`onCompleteFunc` 检查 `:707`）、`checkQueueList:712`（`:719` 调 `canMergeAction`）、`ISBaseTimedAction:forceComplete/forceStop`（`shared/TimedActions/ISBaseTimedAction.lua:24/28`）、`ISTimedActionQueue.addAfter` 用法（`shared/Vehicles/TimedActions/ISAddGasolineToVehicle.lua:99/102`）、`getPlayerData(num).playerInventory`（`client/ISUI/ISInventoryPage.lua:1330`、`client/Hotbar/ISHotbar.lua:619`） |
| 引擎侧根因 | 见[前置文档](pz-b42-nested-container-multiplayer-fix.md)第三章 | ✅ `javap -p -c` 逐条核对过（本文件不重复） |
| `ContainerID#set` 的两条分支 | 本机 `javap -p -c`（`ContainerID.class`） | ✅ 复核了 (a) `containingItem == null || getOutermostContainer() == null` 才进 floor 分支、`getFloorContainer` 在 `worldItem ~= null` 时返回 floor 容器、返回 `null` 时抛 `IllegalStateException`；(b) `getOutermostContainer() != null` 时走 `outermost.getParent()` 分发，而背包容器 `parent == null` ⇒ `setObject(container, null, null.square)` 抛 NPE（4.1 的深度 ≥ 1 情形） |

> 本次文档工作**没有启动游戏、没有起专用服务器、没有安装任何东西**；
> `tools/apicheck.sh` 只读回查游戏文件。

### 11.3 未完成（没有任何运行时结论）

* ❌ **从未在真实联机会话里执行过**：这三步法、两条加固分支、面板重选都只按代码读过；
  "能取出 / 放入物品"是**设计推断**。
* ❌ `canMergeAction` 加固（5.1）、`isDetached` 安全放弃（5.2）、`pcall(reselectPane)`（6.4）
  **都没有在真实故障场景里被触发过** —— 它们是从原版 `canMergeAction` / `ContainerID` 的读码推出的防御。
* ❌ 三步法在真实网络往返下的时序与体感（背包出入背包的视觉、音效、耗时）没有测过。
* ❌ `reselectPane` 是否真能把面板从旧容器对象重指到新容器对象，没有实机验证。
* ❌ 走路 / 跑步打断、loot all 多件、第二名玩家旁观三个场景没有实测。
* ❌ 未测性能与网络量；未测"两名玩家并发操作同一容器"。

**手工验证清单与期望日志**见
[模组 README 的"手工联机验证清单"](../bin2_nested_containers_mp_fix_client/README.md#手工联机验证清单)。

### 11.4 后续可加固（当前未做）

* 放回步骤的**健壮性兜底**：若包最终留在玩家背包（异常打断），可给玩家一条上屏提示；
* `reselectPane` 失败时重试或强制 `refreshBackpacks`；
* 对"多件物品 / loot all"的场景做一次真机实测，确认合并与步骤插入的交互符合预期；
* 评估是否需要在三步法期间临时屏蔽"其它动作插队"（当前只关掉了 `stopOnWalk` / `stopOnRun`）。

---

## 十二、参考链接

* 模组本体：[`bin2_nested_containers_mp_fix_client/`](../bin2_nested_containers_mp_fix_client/README.md)（README 含安装、验证清单、已知限制）
* 引擎级根因与 Java 哨兵方案：[`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)
* 纯 Lua 客户端 / 服务端协议方案：[`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)
* 另一个修复（ZombieBuddy / Java 版，与本模组**只能装一个**）：[`bin2_nested_containers_mp_fix/`](../bin2_nested_containers_mp_fix/README.md)
* Nested Containers - Complete（被修复的 UI 模组，工坊 `3801776436`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* PZ 官方 Modding Javadoc：`zombie.network.fields.ContainerID` — https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* ZombieBuddy（Java agent 框架；本模组**不需要**）— https://github.com/zed-0xff/ZombieBuddy

> 链接核对记录（2026-10-02，`curl -s -L -o /dev/null -w '%{http_code}'`）：上面 4 条外部链接均返回 **HTTP 200**。
> 所以本文件的核心论据一律以**本机游戏文件**（`media/lua` 原文行号、`javap` 字节码）与**本仓库源码**为准。
