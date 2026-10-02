# Project Zomboid B42 嵌套容器：物品拿取（Take Single Item）设计

> 记录时间：2026-10-02　对象：模组 **NestedContainersTake v1.0.0**
> （[`bin2_nested_containers_take/`](../bin2_nested_containers_take/README.md)）
> ＋ 游戏 **42.21.0 / build `4a0e9546ec`**
>
> **前置文档**：引擎级根因、`javap` 反编译证据、ZombieBuddy 哨兵线格式见
> [`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)；
> 纯 Lua 客户端/服务端协议见 [`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)；
> 纯客户端"三步法"见 [`docs/pz-b42-nested-container-mp-fix-client.md`](pz-b42-nested-container-mp-fix-client.md)；
> "拿取时自动倒空"见 [`docs/pz-b42-nested-container-auto-unpack.md`](pz-b42-nested-container-auto-unpack.md)。
> **本文件不重复那些字节码证据**，只重述一段根因，然后讲"**换用引擎自带的网络定时动作通道**"的第五条路。
>
> **结论一句话**：本方案**不修 `ContainerID`**，而是把这次取物**整件事**交给引擎的
> "网络定时动作"通道 —— 一个放在 `shared/`、并定义了 `complete()` 的 Lua 定时动作，
> 会被 `LuaTimedActionNew` 自动变成 `NetTimedActionPacket` 发给服务端，
> **由服务端权威执行**；参数只带"物品 id + 容器引用"，两端各自按 id 还原路径
> （`bagParent:getItemById(包id)` → `包:getInventory()` → `getItemById(物品id)`），
> **完全不依赖任何容器地址**。服务端在 `complete()` 里**先过一遍 `isValid()`**（容量 / 白名单 /
> 可否取出），再按"**先 `AddItem` 后发同步包**"的顺序搬运 —— 其中
> `sendReplaceItemInContainer(bagParent, 包, 包)` 把**整只包（含包内内容）重发一次**，
> 补上"嵌套包容器没有相对广播锚点"的洞。
> 机制**沿用 Picking Meister**（工坊 `3422220305`，本机加载的 `42.20` 版 = `modversion=1.9.1`）
> 的 `P4PickingAction`；客户端 `if not isClient() then return end` ⇒ **单机不介入**。
>
> **三个必须写明的边界**：① **客户端与服务端都要装**（搬运在服务端跑），且**没有回退机制**；
> ② 只覆盖"**包直接位于可寻址容器里**"这一层 —— `bagParent` 自身若还是"嵌套包里的包"，
> 服务端同样还原不出来（表现为**静默不生效**，不是损坏），更深的嵌套需要配合三步法版或协议版；
> ③ 校验仍有一处残留差距：服务器选项 `ItemNumbersLimitPerContainer` 没有复刻。

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

**本方案的做法**：既然"给这次搬运写地址"这条路走不通，那就**不写地址** ——
把这次取物换成一个**引擎认识的自定义定时动作**，只发 id，让服务端用它自己那份世界状态去还原。

---

## 二、为什么是"换通道"而不是"新协议"

本仓库对同一个根因现在有五条路。区别在**"谁来执行这次搬运、服务端需要知道什么"**：

| | (a) Java 版 `mp_fix` | (b) 协议版 `mp_fix_lua` | (c) 三步法 `mp_fix_client` | (d) auto unpack | **(e) 本方案 take** |
|---|---|---|---|---|---|
| 修的对象 | `ContainerID`（字节码补丁） | 搬运动作 + 自定义命令 | 一次搬运的**时序** | 玩家的工作流 | **执行者**：改用服务端权威动作 |
| 执行搬运的人 | 原版服务端 | **服务端**（模组自己的校验 + `ISTransferAction`） | 原版服务端（多次） | 原版服务端（多次） | **服务端**（模组自己的动作） |
| 服务端要能理解什么 | 新的 `ContainerID` 载荷 | **模组的地址串 + 命令** | 什么都不用（只发原版事务） | 什么都不用 | **模组的 Lua 动作类**（`shared/` 里那份） |
| 新增网络面 | 无（复用 `ObjectInVehicle`） | **有**（`sendClientCommand`） | 无 | 无 | 复用引擎的 `NetTimedActionPacket`（**不新增自定义包**） |
| 服务端没装时 | 退回修复前 | 超时后退回修复前 | 不适用 | 不适用 | **这次取物静默失败**（没有回退） |
| 方向 | 取 / 放 | 取 / 放 | 取 / 放 | 只能"整包取出" | 只能"取出" |

**(e) 与 (b) 的差别最值得注意**：(b) 也是"服务端权威"，但它**自己开了一条协议**并**自己复刻了**
距离 / 安全屋 / 归属 / 容量 / 件数上限等校验；**(e) 把动作本身交给引擎去同步**（省掉了协议），
代价是**这些校验目前没有复刻**（见第十一节）。

**(e) 与 (d) 的差别**：(d) 换的是**玩家的工作流**（拿包 = 连内容一起拿走）；
(e) 保持工作流不变（照常从包里拖一件），换的是**这次搬运的执行者**。

---

## 三、引擎的"网络定时动作"通道（字节码证据）

`zombie.characters.CharacterTimedActions.LuaTimedActionNew` 在 B42.21 的
`projectzomboid.jar` 里**没有对应的 `.lua` 源文件**。本机 `javap -p -c` 逐条核对：

| 位置 | 字节码语义 |
|---|---|
| 构造函数（形参 `KahluaTable table, IsoGameCharacter`） | `if (table.getMetatable().rawget("complete") == null) useCustomRemoteTimedActionSync = true;` —— **反过来说：只要 Lua 表定义了自己的 `complete`，这个标志就是 `false`** |
| `start()` | `if (GameClient.client && !useCustomRemoteTimedActionSync) { setWaitForFinished(true); transactionId = ActionManager.createNetTimedAction((IsoPlayer)chr, table); playerId.set(...); started = true; }` |
| `update()` | 客户端在 `GameClient.client && !useCustomRemoteTimedActionSync` 时轮询 `ActionManager.isDone / isRejected` → `forceComplete() / forceStop()`；`getTime() == -1` 时还会用服务端回写的时长修正本地进度 |
| `complete()` | `super.complete(); if (!GameClient.client) { rawget("complete") → LuaCaller.pcall(thread, fn, table) }` —— **Lua 的 `complete` 只在服务端（或单机）被执行** |
| `valid()` | 调 Lua 的 `isValid`，**只有明确返回 `true` 才算有效**（否则该动作不执行） |

服务端侧：`zombie.network.packets.NetTimedActionPacket.processServer(...)` 的反汇编显示它先
`isConsistent(...)`，再 `zombie.core.ActionManager.start(Action)` —— 也就是**服务端自己把这个动作跑一遍**。
其中 `Action.isConsistent` → `PlayerID.isConsistent` → `IDShort.isConsistent`，
**只做身份 / 连接层次的校验**（不含容器、距离、容量）。

> **一句话总结这条通道**：`shared/` 里的 Lua 动作 + 一个 `complete()` 方法 = 一次服务端权威执行的网络动作。
> 本方案就是踩在这一点上：**动作体里自己搬东西**，而不是让原版事务去搬。

（对照：Picking Meister 的 `P4PickingAction` 用的正是同一条通道 —— 所以它同样要求服务端装模组。）

---

## 四、时序

```
客户端（发起者）                                            服务端
  │ Client.lua 开头 if not isClient() then return end  ← 单机不装补丁
  │ 玩家从"板条箱里的包"里拖出一件物品
  │ ISInventoryTransferAction:new(...)         ← 本模组不改 new
  │ ISInventoryTransferAction:start()
  │   ├─ OLD_start 被跳过（命中时）
  │   ├─ sourceNeedsRemoteTake(srcContainer)   ← 源端是"物体容器里的包"？
  │   ├─ canTakeById(self)                     ← 外层容器 → 包 → 物品，id 链都能走通？
  │   ├─ NCFNestedTakeAction:new(character, itemId, bagId, bagParent, destContainer)
  │   ├─ ISTimedActionQueue.addAfter(self, action)
  │   ├─ self.ncfNestedTakeStep = true                  ← 标记已接管（守卫不再是死代码）
  │   └─ self.started = true; self.action:setTime(0)   ← 本次原版动作空转完成
  │
  │ … 队列推进到 NCFNestedTakeAction …
  │   ├─ isValid() → updateResources() + isItemAllowed + hasRoomFor + pcall(isRemoveItemAllowed)
  │   └─ LuaTimedActionNew.start()
  │        └─ GameClient.client && !useCustomRemoteTimedActionSync 成立
  │             └─ ActionManager.createNetTimedAction(player, table)
  │                  └─ NetTimedActionPacket ──────────────────────►│ processServer
  │                                                                  │   isConsistent(playerId)
  │                                                                  │   ActionManager.start(action)
  │                                                                  │     LuaTimedActionNew.complete()
  │                                                                  │       └─ (!GameClient.client) → Lua 的 complete()
  │                                                                  │            isValid()（服务端权威闸门：再校验一次）
  │                                                                  │            destContainer:AddItem(item)  ← 先加（内部会从原容器摘掉）
  │                                                                  │              └─ 返回 nil ⇒ return false，源端未动
  │                                                                  │            sendRemoveItemFromContainer(srcContainer, item)
  │                                                                  │            sendReplaceItemInContainer(bagParent, bag, bag)
  │                                                                  │            sendAddItemToContainer(destContainer, addedItem)
  │◄──────────────── 引擎既有的完成/拒绝回执（forceComplete / forceStop）──────────┘
  │ perform() → 收尾（停 loopSound）
```

**两点值得强调**：

* 客户端**没有等自己的 `AddItem`**：搬运只在服务端发生，客户端靠上面三条 `send*` 的广播刷新。
* 客户端在"接管"那一刻**已经把原版动作作废了**（`setTime(0)`），所以哪怕服务端环节失败，
  也不会退回去跑那个注定被拒的原版事务 —— 表现为"这次取物什么都没发生"。
* **搬运顺序是"先 `AddItem` 再发同步包"**：`ItemContainer:AddItem()` 内部会把物品从原容器摘掉，
  所以失败时源端一丝未动（下面 6.4 有字节码证据）。

---

## 五、容器还原：按 id 的三段链

```lua
function NCFNestedTakeAction:updateResources()
    ...
    self.bagItem      = self.bagParent:getItemById(self.bagId)   -- ① 外层容器里按 id 找到那只包
    if not self.bagItem or not self.bagItem:IsInventoryContainer() then return false end
    self.srcContainer = self.bagItem:getInventory()              -- ② 拿到包自己的容器
    self.item         = self.srcContainer:getItemById(self.itemId)  -- ③ 在包里按 id 找到那件东西
    ...
```

* **`getItemById` 是唯一的定位手段**，完全绕开 `ContainerID`。
* 这条链**两端都要能走通**：客户端用 `canTakeById` **预先模拟**一遍（第六节），
  服务端在 `complete()` 里**再走一遍**（`updateResources`）。
* 服务端能走通的前提是 **`bagParent` 在服务端仍然有效** —— 这是本方案的**硬边界**（第十一节第 1 条）。

---

## 六、同步：三条 `send*` 与"整包重发"

`complete()` 的内容（发送部分与 Picking Meister 的 `P4PickingAction:complete()` 相同，
但**顺序相反**：本模组先 `AddItem`）：

```lua
if not self:isValid() then return false end                          -- ⓪ 服务端权威闸门（见 7.5）
local addedItem = self.destContainer:AddItem(self.item)              -- ① 先加：内部会把物品从原容器摘掉
if not addedItem then return false end                               --    失败 ⇒ 源端未动（见 6.4）
sendRemoveItemFromContainer(self.srcContainer, self.item)            -- ② 源端广播（到不了观察者，见 6.1）
sendReplaceItemInContainer(bagParent, bagItem, bagItem)              -- ③ 关键：整包重发（见 6.2）
sendAddItemToContainer(self.destContainer, addedItem)                -- ④ 目标端广播
```

> Picking Meister 是"先本地 `Remove` + 发同步、再 `AddItem`"；本模组刻意**调换**了顺序，
> 理由见 6.4（`AddItem` 自己会摘掉原容器里的那一份，先做它就消除了"摘掉却加不进"的窗口）。

### 6.1 为什么 ② 到不了观察者

`zombie.network.GameServer.sendRemoveItemFromContainer` / `sendReplaceItemInContainer` /
`sendAddItemToContainer` 共用同一套**四支锚点**逻辑（本机 `javap -p -c` 核对）：

| 条件 | 行为 |
|---|---|
| `container:getCharacter() instanceof IsoPlayer` | 发给该玩家（`INetworkPacket.send(player, …)`） |
| 否则 `container:getParent() != null` | `sendToRelative(…, parent.x, parent.y, …)` |
| 否则 `container.inventoryContainer:getWorldItem() != null` | `sendToRelative(…, worldItem.x, worldItem.y, …)` |
| **都不满足** | **直接 return —— 一个包都不发** |

被拿走东西的那个容器（`srcContainer` = **包自己的** `ItemContainer`）：
`getCharacter()` 会沿 `containingItem.getContainer().getCharacter()` 向上走，
而板条箱物体不是角色 ⇒ `null`；它的 `parent` 也是 `null`；它也没有 `worldItem`。
⇒ **落进第 4 支，什么都不发**。这就是"嵌套包容器没有相对广播锚点"的那个洞。

### 6.2 为什么 ③ 能补上

本模组传的是 **`bagParent`** —— **装着这只包的那个板条箱容器**。它有 `parent`（板条箱 `IsoObject`），
⇒ 落进**第 2 支**，锚点是板条箱所在格子，`sendToRelative` 能覆盖到发起者与附近的玩家。

而"替换"的载荷是**整只包**：`PlayerItem.write` → `InventoryItem.save(ByteBuffer, boolean)`
（虚方法）→ `InventoryContainer.save(ByteBuffer, boolean)` → `ItemContainer.save(ByteBuffer)`
⇒ **包连同包内内容一起上线**。客户端收到后替换掉自己那份包，
于是"包里少了一件东西"这件事在**发起者与旁观者**两边都刷新了。

> **参数为什么是 `(bagParent, bag, bag)`**：第二个参数是"旧物品"（`oldItemId`），
> 第三个是"新物品"（`PlayerItem`）。把**同一只包既当旧的又当新的**，
> 语义就是"这只包被替换成了它自己"，效果等价于**强制重发**。
> 这是本方案唯一一处"绕过原版增量广播"的地方。

### 6.3 单机下这些 `send*` 是空操作（现在只是背景知识）

`INetworkPacket.send(zombie.characters.IsoPlayer, …)` 与
`INetworkPacket.sendToRelative(PacketType, float, float, …)` 的第一句都是 `if (GameServer.server)`。
单机 `GameServer.server == false` ⇒ 不发包。

> 这一节现在只是**引擎事实**：因为 `Client.lua` 已经在单机直接 `return`（7.1），
> 单机根本不会走到 `complete()`。它仍然值得记录，因为它解释了"如果当初没有加 `isClient()` 早退，
> 单机会怎样"——读码结论是"能搬，但走的是本模组的动作而不是原版搬运路径"。

### 6.4 为什么"先 `AddItem` 再发同步包"是安全的

本机 `javap -p -c zombie/inventory/ItemContainer.class` 里 `AddItem(InventoryItem)` 的分支顺序：

| 步骤 | 字节码行为 |
|---|---|
| ① | `item == null` ⇒ 返回 `null` |
| ② | `containsID(item.id)` ⇒ `DebugType.error("Error, container already has id")` 并返回**已存在的那件**（不是 nil） |
| ③ | `item.container != null` ⇒ `item.container.Remove(item)` —— **先把它从原容器摘掉** |
| ④ | `item.container = this` → `items.add(item)` → 返回 `item` |

所以"加得进 / 加不进"这一步**先做完**：失败（返回 nil）时物品还没被摘走，源端完全没被动过；
成功时物品已经挂在目标容器上，接下来三条 `send*` 只是**同步**。
这就是 `complete()` 里**先 `AddItem` 后 `send*`**（与 Picking Meister 相反的次序）的原因 ——
它把"从源端摘掉却加不进目标端"这个丢物品窗口消掉了。
（唯一没被消除的边角是第 ② 支：目标容器已存在同 id 物品时会返回"已存在的那件"，
动作仍会继续发同步包 —— 已列入"未验证"。）

---

## 七、实现要点

### 7.1 唯一的补丁点、`isClient()` 早退与"命中即作废原版动作"

`client/Client.lua` 在 `require` / `log` 之后的第一件事就是：

```lua
-- 与 auto_unpack 版保持一致：单机不需要本模组（单机本来就能开包拿单品），
-- 而且单机下 send* 是空操作、动作链路不同，接管只会改变原有行为 —— 所以单机直接不装补丁。
if not isClient() then
    return
end
```

⇒ **单机不覆盖 `ISInventoryTransferAction:start()`，本模组在单机零影响**
（`isClient()` == `GameClient.client`，单机为 `false`，字节码见 12.2）。

补丁面只有一个：`ISInventoryTransferAction:start()`（存成 `OLD_start` 后覆盖）。
命中时**完全不调用 `OLD_start`**：

* 于是这次搬运**不会**构造 `ContainerID`、**不会**产生那个注定被拒的原版事务；
* `self.ncfNestedTakeStep = true`：**本次原版动作上也置标记**，守卫 `if not self.ncfNestedTakeStep then`
  因此不再是死代码（同一动作再次进入不会重复排队）；
* `self.started = true`：原版 `isValid()` 里有
  `if not self.started and not isItemTransactionConsistent(...) then return false end`，
  置位后跳过客户端事务一致性检查；
* `self.action:setTime(0)`：让这个原版动作**空转完成**（原版在 `isAlreadyTransferred` 早退分支里也是这么干的）；
* `NCFTakeCount = (NCFTakeCount or 0) + 1`：接管计数（只在内存里，不打印）；
* 真正的搬运由排在它后面的 `NCFNestedTakeAction` 完成（`ISTimedActionQueue.addAfter`）。

未命中时 `return OLD_start(self)` —— **与修复前逐字节相同的原版路径**。
整个判定包在 `pcall` 里，出错只打**一次** `WARN hook failed: …`（`NCFTakeWarned`）再回落原版。

### 7.2 `sourceNeedsRemoteTake(container)`：镜像 `ContainerID#set`（只看源端）

| 检查 | 返回 | 对应原版分支 |
|---|---|---|
| `container:getParent()` 是 `IsoPlayer` | `false` | `PlayerInventory`（本来就能寻址） |
| `container:getContainingItem()` 为 `nil` | `false` | 不是"某只包自己的容器"（floor / worldItem 等） |
| `bag:getContainer()` 为 `nil` | `false` | 包已不在任何容器里（失效引用） |
| 包所在容器的 `parent` 是 `IsoPlayer` | `false` | `InventoryContainer`（服务端 `getItemWithIDRecursiv` 递归查找） |
| 包所在容器的 `parent` 是 `BaseVehicle` | `false` | `ObjectInVehicle`（直接子物品可用） |
| 包所在容器 `getType() == "floor"` | `false` | `floor` / `WorldObject` 分支 |
| `bag:getWorldItem() ~= nil` | `false` | 地面上的包（世界物品） |
| 以上都不满足 | **`true`（接管）** | `setObject(...)` → `containerIndex = -1` → 服务端 `null` |

**只有"包在板条箱 / 衣柜 / 货架 / 尸体这类物体容器里"才会接管**，
其余情形（地面包、载具部件、玩家背包、floor）一律交回原版。

### 7.3 `canTakeById(action)`：把"服务端能否还原"提前验一遍

```
bag         = srcContainer:getContainingItem()      必须是 IsInventoryContainer
bagParent   = bag:getContainer()                    必须存在且有 getItemById
resolvedBag = bagParent:getItemById(bag:getID())     ← 与服务端 complete() 里同一条路
inner       = resolvedBag:getInventory()
inner:getItemById(item:getID())                     必须能找到要拿的那件
```

这条检查的意义是**避免发一个注定失败的网络动作**：`bagParent` 会作为动作参数发给服务端，
服务端也要用它去 `getItemById(bagId)`。客户端先验一遍，不通过就回落原版（等价修复前行为）。

### 7.4 时长与表现

* `getDuration()` **照抄** `ISInventoryTransferAction:new` 的算法（基础 120 / 跨容器 50 /
  `destCapacityDelta` 下限 0.4 / 重量上限 3 / `LastStand` ×0.3 / `DEXTROUS` ×0.5 /
  `ALL_THUMBS` 或笨重手套 ×2.0）；`isTimedActionInstant()` 时返回 1。
* `start()` **只在客户端跑**（引擎不会在服务端调用它）：`RummageInInventory` 循环音效 +
  `Loot` 动画 + 容器方位变量（含尸体 / `floor` 的 `"Low"` 特例、`freezer` 的冷冻位）。
* `stop()` / `perform()` 收尾停掉循环音效 —— 与原版搬运同一套语义。
* `new()` 里 `stopOnWalk = true` / `stopOnRun = true`：**走路或跑步会打断**（与原版搬运一致）。

### 7.5 `isValid()`：补齐的校验与"服务端权威闸门"

```lua
function NCFNestedTakeAction:isValid()
    if not self:updateResources() then return false end                       -- id 链可还原
    if not self.destContainer:isItemAllowed(self.item) then return false end   -- 目标容器白名单
    if not self.destContainer:hasRoomFor(self.character, self.item) then return false end  -- 放得下吗
    local okCheck, canRemove = pcall(function()                               -- 源容器允许取走吗
        return self.srcContainer:isRemoveItemAllowed(self.item)
    end)
    if okCheck and canRemove == false then return false end                   -- 取不到该方法就不拦
    return true
end
```

这一个函数**同时**承担三个角色：

| 角色 | 机制 |
|---|---|
| 客户端提前拦截 | `new()` / 队列推进时引擎调 Lua `isValid`（Java `LuaTimedActionNew.valid()` **只认布尔 `true`**），不合法就不发起那个动作 |
| 服务端权威闸门 | `complete()` **第一句**就是 `if not self:isValid() then return false end` —— 即使客户端被改过，服务端也会重新校验一遍 |
| 失败即"什么都不做" | 返回假 ⇒ 不 `AddItem`、不发任何包 ⇒ 物品不动、容器不变 |

* `isRemoveItemAllowed` 用 `pcall` 包住："方法名跨版本可能变，取不到就不拦" —— 与协议版 (b) 同策略。
* **仍然没有复刻**的是服务器选项 `ItemNumbersLimitPerContainer`（每容器物品数上限）：
  它写在原版 `ISInventoryTransferAction:isValid()` 内部、依赖 `getServerOptions()`，
  本动作不复刻（见第十一节第 3 条）。

### 7.6 日志与失败语义

| 行 | 触发 | 频率 |
|---|---|---|
| `[NestedContainersTake] nested take: taking single items out of nested bags (e.g. <物品名> from bag <包id>)` | 第一次接管成功 | **每局只打一次**（`logOnce` / `NCFTakeLoggedOnce`），括号里是首次那件物品 |
| `[NestedContainersTake] WARN hook failed: …` | 钩子体抛错 | **每局只打一次**（`NCFTakeWarned`），之后同类错误静默回落原版 |

* 接管次数记在全局计数器 `NCFTakeCount` 上，但**只在内存里累加、不打印**。
* `NCFNestedTakeAction` 自身**没有任何日志**（服务端也不打印）。
* 代价：**"第二件之后发生了什么"在日志里看不出来**（只有首次一行 + 最多一行告警）。

失败路径总结：

| 情形 | 结果 |
|---|---|
| `sourceNeedsRemoteTake` 为假 | 原版路径（与修复前逐字节相同） |
| `canTakeById` 返回 nil | 原版路径（该次嵌套搬运仍会被服务端拒绝 —— 与修复前一致） |
| 钩子抛错 | 每局一次 `WARN hook failed` + 原版路径 |
| `isValid()` 为假（客户端） | 动作不发起，原版动作已空转完成 ⇒ **这次取物什么都没发生**（静默） |
| 服务端 `isValid()` / `updateResources()` 为假 | `complete()` 直接 `return false` ⇒ **不搬运**；客户端原版动作已空转完成 ⇒ **这次取物什么都没发生**（静默） |
| 目标容器满 / 不允许放入 / 源容器不允许取走 | 由 `isValid()` 拦下（客户端 + 服务端各一次）⇒ 物品不动、容器不变 |
| `AddItem` 返回 nil | `complete()` 直接 `return false`，**源端未被改动**（见 6.4） |

---

## 八、与另外四个方案、以及 Picking Meister 的关系

| | 一句话 | 与本方案的关系 |
|---|---|---|
| (a) [`bin2_nested_containers_mp_fix`](../bin2_nested_containers_mp_fix/README.md) | ZombieBuddy 字节码补丁修 `ContainerID` | 修在引擎里、同步最彻底；与本方案**不要混装**（都假设自己对那次搬运有支配权） |
| (b) [`bin2_nested_containers_mp_fix_lua`](../bin2_nested_containers_mp_fix_lua/README.md) | 自定义客户端↔服务端协议 | 同样是"服务端权威"，但它**自己复刻了全部校验**；本方案省掉了协议，也暂时省掉了那些校验 |
| (c) [`bin2_nested_containers_mp_fix_client`](../bin2_nested_containers_mp_fix_client/README.md) | 纯客户端三步法 | **唯一的"服务端零安装"取放方案**；服务端装不了模组时用它 |
| (d) [`bin2_nested_containers_auto_unpack`](../bin2_nested_containers_auto_unpack/README.md) | 拿包时自动把包倒空 | **互补**：要整包用 (d)，要单件用本方案；两者补丁点互不抢占 |
| **Picking Meister**（工坊 `3422220305`） | 通用拾取助手，同一套机制 | **本方案的机制来源**（见下） |

### Picking Meister 对照与版本差异（本机实测）

本机 Steam 工坊内容 `…/workshop/content/108600/3422220305/mods/P4PickingMeister/`
每个版本目录的 `modversion` 各不相同：

| 版本目录 | `modversion` | `P4PickingAction.lua` 行数 |
|---|---|---|
| `42` | `1.5.1` | —（该目录没有此文件） |
| `42.13` | `1.6.1` | 155 |
| `42.15` | `1.7.1` | 155 |
| `42.20` | **`1.9.1`** | **187** |

游戏 **B42.21 实际加载 `42.20`**（取不超过游戏版本的最高目录），所以本文以 **`1.9.1`** 为准。
早先任务简报里的 `1.7.1` 来自 `42.15` 目录 —— 属于**目录差异**，不是记错。
本节引用的行号都以 `42.20` 那份 187 行为准。

本模组与 `P4PickingAction` 的同构与差异：

| | `P4PickingAction`（1.9.1） | 本模组 `NCFNestedTakeAction` |
|---|---|---|
| 通道 | 共享动作 + `complete()` ⇒ `NetTimedAction` | **相同** |
| 还原方式 | `srcParent:getItemById(srcId)` → `getInventory()` → `getItemById(itemId)` | **相同**（`bagParent` / `bagId` / `itemId`） |
| 时长 | 自己算一套（`calcDuration`） | **照抄 `ISInventoryTransferAction:new`**（更贴近原版手感） |
| 同步 | `Remove` + `sendRemoveItemFromContainer` + `sendReplaceItemInContainer(srcParent, bag, bag)` + `AddItem` + `sendAddItemToContainer` | **相同五步** |
| 触发方式 | 由它自己的 UI / 队列（`P4PickingMeister.lua`、`P4PickingMeisterQueue.lua`）发起 | **拦截 `ISInventoryTransferAction:start()`**，只在"源端是物体容器里的包"时接管 |
| 定位 | 通用拾取助手（可选 UI、高亮等） | 针对"嵌套包"这一种情形的**小实现**（只有一个动作） |
| 版本目录 | `42` / `42.13` / `42.15` / `42.20` | 只有 `42.21` |

---

## 九、兼容性矩阵

| 服务端 | 客户端 | 结果 |
|---|---|---|
| 装了本模组 | 装了本模组 | ✅ **目标场景**：可以从物体容器里的包里取单件，包留在原处 |
| **没装**本模组 | 装了本模组 | ❌ 客户端仍会接管并排动作，但服务端没有 `NCFNestedTakeAction` ⇒ **这次取物静默失败**（不崩、不复制、不卡动作）；**没有回退** |
| 装了本模组 | 没装本模组 | ✅ 与修复前一致（客户端不会发起那条动作） |
| 装了 (a) / (b) / (c) | 同时装了本模组 | ❌ **不要这么干**：都假设自己支配那次搬运；出问题无法判断是谁在生效 |
| —— | 同时装了 (d) auto unpack | ✅ **互补兼容**：(e) 只在"源端是嵌套包"时接管，(d) 只在"把包搬进玩家背包"时追加回调 |
| 装了 Nested Containers 界面模组 | 装了本模组 | ✅ 兼容（本模组不替换任何 UI） |
| 单机 | —— | ✅ **零影响**：`not isClient()` ⇒ `Client.lua` 直接 `return`，`ISInventoryTransferAction:start()` 不会被覆盖（见 7.1） |

---

## 十、威胁模型

**新增网络面：不是自定义协议，而是复用引擎既有的动作同步通道。**
客户端没有新增 `sendClientCommand` / `sendServerCommand`，也没有新增自定义 packet 类型；
但**新增了一类"服务端会去执行的动作"**（`NCFNestedTakeAction`），这本身就是一个需要审视的面：

| 攻击面 | 现状 |
|---|---|
| "客户端伪造一次容器搬运" | 服务端确实会执行客户端请求的 `NetTimedActionPacket`；`Action.isConsistent` 只做 `PlayerID`（身份/连接）校验，**不含距离 / 安全屋 / 归属**校验 |
| "客户端绕过容量 / 件数上限" | ✅ **已补**：`isValid()` 做 `destContainer:isItemAllowed` / `destContainer:hasRoomFor` / `pcall(srcContainer:isRemoveItemAllowed)`，且**服务端 `complete()` 第一句就再过一次 `isValid()`**（客户端被改也拦得住）<br>⚠️ **仍残留**：服务器选项 `ItemNumbersLimitPerContainer`（每容器物品数上限）没有复刻 —— 它写在原版 `ISInventoryTransferAction:isValid()` 内部、依赖 `getServerOptions()` |
| "客户端拿不属于它的东西" | 受限于 `canTakeById` 与 `updateResources()` 的 id 链 —— 只能操作"`bagParent` 能按 id 找到的包"里"按 id 找得到的那件"；再加上 `isRemoveItemAllowed` / `isItemAllowed`；但**仍然没有安全屋 / 距离校验** |
| "新增协议解析漏洞" | 没有新解析面（动作参数走引擎既有的 `KahluaTable` 序列化） |
| 客户端自身健壮性 | 判定整段 `pcall`，出错回落原版；`isValid()` 在客户端与服务端各跑一次 |
| 服务端自身健壮性 | `complete()` 第一句 `isValid()`；`AddItem` 返回 nil 即 `return false` 且**源端未被改动**（6.4），不会半搬 |

**结论（诚实版）**：校验补齐后本方案的安全性明显好于前一版，但仍**弱于** (b) 协议版
（后者还自己复刻了距离 / 安全屋 / 归属校验与件数上限），
与"原版事务由服务端 `TransactionManager` 独立校验"也不完全等价。
在本仓库里它适合**自己开的、信任玩家的服务器**；公开服仍建议优先 (a) / (b) / (c)。

---

## 十一、已知限制

1. **只覆盖"包直接位于可寻址容器里"这一层**（板条箱 / 衣柜 / 货架 / 尸体 / 冰箱……）。
   原因：`bagParent` 会作为动作参数发给服务端，**它自己若还是"嵌套包里的包"**，
   服务端同样还原不出来（`ContainerID` 表达不了它，`getItemById` 链在服务端就断了）。
   "板条箱 → 包 A → 包 B → 取 B 里的东西"需要先用
   [三步法版](../bin2_nested_containers_mp_fix_client/README.md) 或
   [协议版](../bin2_nested_containers_mp_fix_lua/README.md) 把外层包提到背包。
   ⚠️ **注意**：`sourceNeedsRemoteTake` **不判断深度**，`canTakeById` 往往也仍会通过
   （客户端能按 id 找到 B），所以深层场景**仍会被接管**，然后由服务端 `updateResources()` 判否 ——
   表现为**静默不生效**（物品不动、容器不变，属"什么都没发生"而非"损坏"）。
   **这一条未实测。**
2. **必须双端安装**，且**没有回退机制**：服务端没装 = 被接管的那次取物什么都没发生
   （不像 (b) 会超时后回落）。
3. **校验已补齐，但仍有一处残留差距**：`isValid()` 现在做
   `destContainer:isItemAllowed` / `destContainer:hasRoomFor` /
   `pcall(srcContainer:isRemoveItemAllowed)`（取不到该方法就不拦），
   且服务端 `complete()` 会再过一次；**仍然没有复刻**的是
   `ItemNumbersLimitPerContainer`（服务器选项控制的每容器物品数上限）—— 见第十节。
4. **只做"取出"方向**：把物品放进仍留在物体容器里的嵌套包不在覆盖范围内。
5. **单机为零影响**：`Client.lua` 有 `if not isClient() then return end` 早退，
   单机不会覆盖 `ISInventoryTransferAction:start()`（见 7.1）。
6. **补丁了 `ISInventoryTransferAction`**：与同样补丁这个类的模组存在**加载顺序**关系
   （后加载者的 `OLD_start` 指向先加载者的版本）。
7. **动作必须放在 `shared/TimedActions/` 并定义 `complete()`**：放进 `client/`、或删掉 `complete()`，
   引擎会改走"本地执行"，方案立刻失效（服务端不会再跑它）。
8. **日志是"每局一次"**：成功行由 `logOnce`（`NCFTakeLoggedOnce`）控制、告警由 `NCFTakeWarned` 控制；
   接管次数只在 `NCFTakeCount` 里累加、**不打印**。代价是"第二件之后发生了什么"在日志里看不出来。
9. **`ncfNestedTakeStep` 现在两边都设**（新动作 + 本次原版动作），守卫 `if not self.ncfNestedTakeStep then`
   因此**不再是死代码**：同一动作再次进入时不会重复排队。
10. **搬运仍不是事务性操作**：`complete()` 现在是"先 `AddItem`、成功后才发同步包"，
   `AddItem` 返回 nil 时源端未被改动 ⇒ **丢物品的窗口已消除**。
   但仍有两条未被消除的语义缺口：① 动作里没有"结果字段"，服务端失败时客户端不掌握结果；
   ② 目标容器已存在同 id 物品时 `AddItem` 会返回**已存在的那件**（不是 nil）并继续发同步包 ——
   属边角情况，**未实测**。

---

## 十二、验证状态

### 12.1 本文档对应的源码修订

以 `bin2_nested_containers_take/Contents/mods/NestedContainersTake/42.21/` 为基准：

| 文件 | 行数 | mtime | SHA-256 |
|---|---|---|---|
| `media/lua/shared/TimedActions/NCFNestedTakeAction.lua` | 185 | 20:10:22 | `724077ffd086ae9edc41d0f4efd3aa2bdf202c6b3642191c836994c586027b6d` |
| `media/lua/client/NestedContainersTake/Client.lua` | 134 | 20:10:22 | `30a0aae5d221fea9cdc2225d33560de4843cc02b0a2b95c95bd966f52aa4ee6a` |
| `mod.info` | 17 | 19:55:42 | `66df3d0f1a9982add3db9b2750733b168cd301b7513fc098f2827ac232243f53` |

（改动后哈希会变，可用它判断文档是否过期。）

### 12.2 已完成（静态、可复现）

| 项 | 方式 | 结果 |
|---|---|---|
| API 契约 | `bin2_nested_containers_take/tools/apicheck.sh`（只读；把 31 个 API 回查游戏自带 `media/lua`） | ✅ 本机实测输出 `== 全部命中（34 项）==`（本次源码修订后复跑，退出码 0） |
| 语法 | `luaparse`，`luaVersion: '5.1'` | ✅ 两个 Lua 文件解析通过 —— **本次源码修订后由主导 agent 复跑，仍通过**（本机**没有 Lua 解释器**，因此没有执行过任何一行 Lua 代码；文档作者未重装 / 未重跑该检查） |
| 网络定时动作通道 | 本机 `javap -p -c zombie/characters/CharacterTimedActions/LuaTimedActionNew.class` | ✅ 构造函数 `rawget("complete") == null ⇒ useCustomRemoteTimedActionSync = true`；`start()` 在 `GameClient.client && !useCustomRemoteTimedActionSync` 时 `ActionManager.createNetTimedAction`；`update()` 轮询 `isDone/isRejected`；`complete()` 只在 `!GameClient.client` 回调 Lua；`valid()` 只认布尔 `true` |
| 服务端执行路径 | 本机 `javap -p -c zombie/network/packets/NetTimedActionPacket.class`、`zombie/core/Action.class`、`zombie/core/NetTimedAction.class` | ✅ `processServer` → `isConsistent` + `ActionManager.start`；`NetTimedAction.isConsistent` → `Action.isConsistent` → `PlayerID.isConsistent`（仅身份 / 连接） |
| 广播锚点 | 本机 `javap -p -c zombie/network/GameServer.class`、`zombie/network/packets/INetworkPacket.class` | ✅ `sendReplaceItemInContainer` / `sendRemoveItemFromContainer` / `sendAddItemToContainer` 的四支锚点（character → parent → worldItem → **什么都不发**）；`send(IsoPlayer, …)` 与 `sendToRelative(PacketType, float, float, …)` 首句均为 `if (GameServer.server)` |
| 整包序列化 | 本机 `javap -p -c zombie/network/fields/PlayerItem.class`、`zombie/inventory/InventoryItem.class`、`zombie/inventory/types/InventoryContainer.class` | ✅ `PlayerItem.write` → `InventoryItem.save(ByteBuffer, boolean)`（虚）→ `InventoryContainer.save(ByteBuffer, boolean)` → `ItemContainer.save(ByteBuffer)` |
| **`isValid()` 用到的容器方法** | 本机 `javap -p -c zombie/inventory/ItemContainer.class` | ✅ `isItemAllowed(InventoryItem)` / `hasRoomFor(IsoGameCharacter, InventoryItem)` / `isRemoveItemAllowed(InventoryItem)` 均存在；**`AddItem(InventoryItem)` 的分支顺序**为 `null ⇒ null`、`containsID ⇒ 返回已存在的那件`、否则 `item.container.Remove(item)` → `item.container = this` → `items.add(item)` → 返回该物品 ⇒ 证明 **6.4 的"先 Add 后同步"是安全的** |
| `isClient()` 的真实含义 | 本机 `javap -p -c 'zombie/Lua/LuaManager$GlobalObject.class'` | ✅ `return GameClient.client;`（单机为 `false`）⇒ 单机不覆盖 `start()`，即 7.1 / 第十一节第 5 条 |
| 引擎侧根因 | 见[前置文档](pz-b42-nested-container-multiplayer-fix.md)第三、四章 | ✅ `javap -p -c` 逐条核对过（本文件不重复） |
| Picking Meister 对照 | 本机 `…/108600/3422220305/mods/P4PickingMeister/42.20/` 逐行读 `P4PickingAction.lua`（187 行）＋ 各版本目录的 `modversion` | ✅ 见第八节（`42`=1.5.1 / `42.13`=1.6.1 / `42.15`=1.7.1 / `42.20`=1.9.1）；发送内容相同但**顺序相反**（本模组先 `AddItem`） |

> 注：`tools/apicheck.sh` 现已把校验用的 `isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed` 一并纳入自检（共 **34 项**，本机实测 `== 全部命中（34 项）==`）。

> 本次文档工作**没有启动游戏、没有起专用服务器、没有安装任何东西、没有改任何源码**；
> `tools/apicheck.sh` 只读回查游戏文件。

### 12.3 未完成（没有任何运行时结论）

* ❌ **从未在真实联机会话里执行过**：没有起过专用服务器、没有双客户端实测。
  "能从物体容器里的包中取单件、包留在原处"是**基于引擎字节码与动作链路的设计推断**。
* ❌ **最关键的一条**：`bagParent` 作为 `KahluaTable` 里的一个 **Java 对象引用**，
  在 `createNetTimedAction` 的序列化与 `NetTimedActionPacket` 的往返中**能否原样到达服务端**，
  没有实测。这既决定方案能否成立，也决定"深层嵌套为何静默不生效"的确切表现。
* ❌ `sendReplaceItemInContainer(bagParent, bag, bag)` 是否真的让**发起者**与**附近旁观玩家**
  的包内视图都刷新，没有实测（序列化链是读码结论）。
* ❌ 服务端"静默失败"时的 `console.txt` 表现（有没有引擎侧告警）没有实测。
* ❌ 新补的三项校验（`isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed`）在真实容器上
  是否拦得住该拦的、放得过该放的，没有实测；`ItemNumbersLimitPerContainer` 的残留差距也没有实测。
* ❌ "目标容器已存在同 id 物品"这条边角没有实测：按 `AddItem` 的字节码，这种情况**不会返回 nil**，
  而是打一行 `Error, container already has id` 并返回**已存在的那件**，动作仍会继续发同步包。
* ❌ 单机"零影响"虽然由 `not isClient()` ⇒ `return` 直接推出，但没有实机跑过。
* ❌ 走路 / 跑步打断、`loot all`、多人并发操作同一只包没有实测。
* ❌ 未测性能与网络量（每次取物 = 一次网络往返 + 一次**整包**序列化，
  包很大时值得测一下）。

### 12.4 后续可加固（当前未做）

* **补上最后一处校验**：`ItemNumbersLimitPerContainer`（每容器物品数上限）——
  现在 `isValid()` 已经覆盖 `isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed` 并有服务端闸门，
  只剩这一项原版事务内部逻辑没有复刻（可参照 (b) 协议版的做法）；
* **把"深度"显式判断出来**：`sourceNeedsRemoteTake` 目前对"包 A 里的包 B"也会返回 `true`，
  可以改成"`bagParent` 本身也必须原版可寻址"，让深层场景**直接回落原版**而不是静默不生效；
* **给失败一条可见反馈**：服务端 `isValid()` / `AddItem` 失败时，客户端目前完全不知道
  （引擎只回 `forceComplete / forceStop`，动作里没有结果字段）；
* **把计数暴露出来**：`NCFTakeCount` 只累加不打印，可以考虑做成"每局一行汇总"
  （当前是"每局一行成功 + 最多一行告警"）；
* **边角**：`AddItem` 在"目标容器已存在同 id 物品"时会返回已存在的那件而不是 nil，
  动作会继续发同步包 —— 可以在这之前加一次 `containsID` 检查。

**手工验证清单与期望日志**见
[模组 README 的"手工联机验证清单"](../bin2_nested_containers_take/README.md#手工联机验证清单)。

---

## 十三、参考链接

* 模组本体：[`bin2_nested_containers_take/`](../bin2_nested_containers_take/README.md)（README 含安装、验证清单、已知限制）
* 机制来源：Picking Meister（工坊 `3422220305`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305
* 引擎级根因与 `javap` 字节码证据：[`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)
* 纯 Lua 客户端 / 服务端协议方案：[`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)
* 纯客户端"三步法"方案：[`docs/pz-b42-nested-container-mp-fix-client.md`](pz-b42-nested-container-mp-fix-client.md)
* "拿取时自动倒空"方案（与本模组互补）：[`bin2_nested_containers_auto_unpack/`](../bin2_nested_containers_auto_unpack/README.md)、[`docs/pz-b42-nested-container-auto-unpack.md`](pz-b42-nested-container-auto-unpack.md)
* 另外三个修复（与本模组**不要混装**）：[`bin2_nested_containers_mp_fix/`](../bin2_nested_containers_mp_fix/README.md)、[`bin2_nested_containers_mp_fix_lua/`](../bin2_nested_containers_mp_fix_lua/README.md)、[`bin2_nested_containers_mp_fix_client/`](../bin2_nested_containers_mp_fix_client/README.md)
* Nested Containers - Complete（界面模组，工坊 `3801776436`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* PZ 官方 Modding Javadoc：`zombie.network.fields.ContainerID` — https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* ZombieBuddy（Java agent 框架；本模组**不需要**）— https://github.com/zed-0xff/ZombieBuddy

> 链接核对记录（2026-10-02，`curl -s -L -o /dev/null -w '%{http_code}' --max-time 25`）：
> 上面 4 条外部链接均返回 **HTTP 200**。
> 本文件的核心论据一律以**本机游戏文件**（`media/lua` 原文行号、`javap` 字节码）与**本仓库源码**为准。
