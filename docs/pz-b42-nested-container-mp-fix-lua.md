# Project Zomboid B42 联机嵌套容器：纯 Lua 客户端 / 服务端协议设计

> ⚠️ **本方案已于 2026-10-02 放弃**（用户决定）。模组目录已删除，仅保留本文档作为根因与证据记录；
> 现役方案见 `docs/pz-b42-nested-container-take.md`（物品拿取）与 `docs/pz-b42-nested-container-auto-unpack.md`（拿包即倒空）。

> 记录时间：2026-10-02　对象：模组 **NestedContainersMPFixLua v1.0.0**
> （[`bin2_nested_containers_mp_fix_lua/`](../bin2_nested_containers_mp_fix_lua/README.md)）
> ＋ 游戏 **42.21.0 / build `4a0e9546ec`**
>
> **前置文档**：引擎级根因、反编译（`javap`）证据、ZombieBuddy 哨兵线格式设计见
> [`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)。
> **本文件不重复那些字节码证据**，只重述一段根因，然后专注讲"**不 patch Java 的纯 Lua 客户端/服务端协议**"。
>
> **结论一句话**：客户端在 `ISInventoryTransferAction` 上判断"原版网络地址能不能表达这个容器"，
> 不能表达时**不产生原版事务**，改为把两端容器描述成一个**可校验的地址串**用自定义客户端命令发给服务端；
> 服务端按物品 id **重新解析容器**、做距离/安全屋/容量/白名单校验后用原版单机搬运动作执行，并补目标端广播；
> 由于这类容器的变更**广播不到**其他客户端，发起端再**幂等地**补一次本地增量。
> 代价是"观察者可能看到陈旧数据，需要重新打开容器"。

---

## 一、根因（一段话）

原版 `zombie.network.fields.ContainerID` **无法表达"嵌套在物体容器里的容器"**：
`ContainerID#set(ItemContainer)` 对包容器会取它的最外层容器，再按最外层容器的 `parent` 分支，
当 `parent` 是板条箱 / 衣柜 / 货架 / 尸体这类普通 `IsoObject` 时走 `setObject(container, o, o.square)`，
写出的 `containerIndex = o.getContainerIndex(container) == -1`；服务端 `ContainerID#findObject()`
据此调用 `object.getContainerByIndex(-1)` 得到 `null`（`zombie.iso.IsoObject`），
于是 `Transaction#updateItem()` 返回 `false`、事务被 Rejected —— **物品永远不动，且玩家侧没有任何提示**。
单机从不使用 `ContainerID` / `Transaction`（`ISTransferAction:transferItem` 直接操作对象引用），所以单机一直正常。
（逐条字节码证据：前置文档第三、四章。）

本模组**不修引擎**，而是承认"原版这条线走不通"，在旁边另开一条**纯 Lua 的通道**。

---

## 二、为什么另起一套协议

### 2.1 两条通道的对比

| | 原版事务通道（`createItemTransaction` → `ItemTransactionPacket`） | 本模组的协议通道（`sendClientCommand` → `OnClientCommand`） |
|---|---|---|
| 容器寻址 | `ContainerID`（引擎内定长线格式） | 自定义文本地址串（客户端 → 服务端声明，服务端重新解析） |
| 嵌套容器 | ❌ `containerIndex = -1` → `null` → 事务 Reject | ✅ 根容器 + 沿背包逐层的物品 id |
| 执行者 | 服务端 `Transaction.updateItem()`（引擎） | 服务端 Lua `ISTransferAction:transferItem(...)`（原版单机路径） |
| 校验 | `TransactionManager.isConsistent(...)`（引擎） | Lua：距离 / 安全屋 / 物品归属 / 白名单 / 容量（见第六节） |
| 广播 | `RemoveInventoryItemFromContainerPacket` / `AddInventoryItemToContainerPacket`，按容器锚点 | 服务端广播 + 发起客户端**本地增量**（见第五节） |
| 能否被纯 Lua 干预 | ❌（Java 内部） | ✅ |

### 2.2 两个修复只能装一个

| 修复 | 修在哪 | 同步彻底性 | 依赖 |
|---|---|---|---|
| [`bin2_nested_containers_mp_fix`](../bin2_nested_containers_mp_fix/README.md) | `ContainerID`（ZombieBuddy 运行时字节码补丁） | **最好**：线格式不变，任何原版客户端都能被正常广播刷新 | ZombieBuddy + Java，**双端**安装 |
| `bin2_nested_containers_mp_fix_lua`（本设计） | `ISInventoryTransferAction` + 自定义命令 | 有边界：发起端可更新，**其他同时打开同一嵌套包的玩家会看到陈旧数据** | **无** |

> 两者修的是同一个缺陷，**同一时间只装一个**：同时启用时嵌套搬运会被 Lua 版先行接管
> （Java 版补的是 `ContainerID`，在那条路径上不会被触发），两套修复的依赖与回退语义会混在一起，
> 出问题时也很难判断是谁在生效。
> 另外纯 Lua 方案没有"未打补丁端也能安全拒绝"的哨兵（本模组不产生 `ContainerID`），
> 它的兼容性边界是"**服务端没装本模组就整单超时回退**"（见 4.3）。

---

## 三、容器地址（`shared/…/Address.lua`，模块 `NCF`）

### 3.1 设计目标

1. **可校验**：地址只是"声明"，服务端必须能重新解析出真实容器，否则拒绝（不能拿它当凭据）。
2. **可逆**：客户端 `describe` 出来的串，服务端 `resolve` 必须还原成同一个容器（两端共用同一份代码）。
3. **平铺**：全部是标量（`;` 与 `,` 分隔的字符串），不依赖嵌套表的网络序列化行为。
4. **可失败**：任何一环对不上就返回 `nil`，调用方一律退回原版行为（绝不猜测）。

### 3.2 语法

```
<kind>;<x>;<y>;<z>;<a>;<b>;<id1,id2,...>
```

| 字段 | 类型 | 含义 |
|---|---|---|
| `kind` | string | `player` / `object` / `deadBody` / `vehicle` / `worldItem` |
| `x,y,z` | int | 根容器所在格子（`player` 根固定 `0;0;0`） |
| `a` | int | 根在格子内的下标；含义随 `kind`（见下表） |
| `b` | int | 仅 `object` 根使用（容器在物体上的下标）；其余 `kind` 恒为 `0` |
| `id…` | int 列表（`,`） | 从根容器往下、每一层"拥有该容器的背包物品"的 id；空串表示根容器本身 |

### 3.3 五种根（`describe` / `resolveRoot` 的对应关系）

| `kind` | 根容器（`resolveRoot`） | `a` | `b` | 说明 |
|---|---|---|---|---|
| `player` | `player:getInventory()` | 忽略 | 忽略 | 根**绑定在连接的玩家对象上**，客户端无法指定别的玩家（见第九节） |
| `object` | `square:getObjects():get(a):getContainerByIndex(b)` | 物体下标 | 容器下标 | 板条箱 / 衣柜 / 货架 / 冰箱等 |
| `deadBody` | `square:getStaticMovingObjects():get(a):getContainer()` | 静态移动物体下标 | 0 | 尸体 |
| `vehicle` | `square:getVehicleContainer():getPartByIndex(a):getItemContainer()` | 载具部件下标 | 0 | 载具部件容器 |
| `worldItem` | `square:getWorldObjects()` 中 `getItem():getID() == a` 的世界物品的背包 | 地面物品 id | 0 | 地上的包 |

* `chainAndRoot(container)` 沿"所属物品"向上走（`container:getContainingItem()` → 物品 → `item:getContainer()`）
  ，得到 `{由外到内的背包链, 根容器}`；`describe` 把链上的物品 id 顺序写入尾串。
* `itemOutermost(bag)` 等价于原版 `InventoryItem#getOutermostContainer()`，但带 `floor` 短路
  （`getType() == "floor"` 时返回 `nil`），用来对齐原版的"最外层容器"语义。
* **`floor` 根会被改写**：当链的根是格子地板容器（例如包掉在地上）时，
  改写为等价的 `worldItem` 根（原版 `WorldObject` 分支语义）——
  取链上第一个物品的 `getWorldItem()`，把它的格子坐标与物品 id 写进地址，尾串去掉该物品 id。
  裸地板容器**自身**无法描述 ⇒ 返回 `nil`（见第十节第 3 条）。

### 3.4 `canVanillaAddress`：与原版 `ContainerID#set` 分支一一对应的判定

| 容器形态 | 原版走哪条分支 | 服务端能否找回 | `canVanillaAddress` |
|---|---|---|---|
| `parent` 是 `IsoPlayer`（玩家背包） | `setInventoryContainer` → `InventoryContainer` | ✅ 递归 `getItemWithIDRecursiv` | `true`（放行，不接管） |
| 包的最外层容器 `parent` 是 `IsoPlayer` | `InventoryContainer` | ✅ 递归 | `true`（放行） |
| 包的最外层容器 `parent` 是 `BaseVehicle`，且是**直接子物品** | `setObjectInVehicle` → `ObjectInVehicle` | ✅ 部件容器按 id 非递归查找 | `true`（放行） |
| 包的最外层容器 `parent` 是 `BaseVehicle`，**更深一层** | 同上 | ❌ 非递归查不到 | `false`（**接管**） |
| 包的最外层容器 `parent` 是普通 `IsoObject`（板条箱 / 尸体…） | `setObject` → `ObjectContainer`，`containerIndex = -1` | ❌ `null` | `false`（**接管**） |
| 没有所属物品（物体容器 / 载具部件 / 尸体 / 地面 / 玩家背包本身） | 各自分支 | ✅ | `true`（放行） |
| 所属物品的最外层容器为空 / `floor` 分支 | 原版另有处理 | — | `true`（放行） |

> 判定是**保守的**：只要原版可能表达得出来，就交回原版；只有确定会写坏地址时才接管。
> 玩家背包里的包中包、载具的直接子背包这两条"本来就好的路径"因此完全不受影响。

### 3.5 `canBroadcast`：服务端广播能不能到达这个容器

服务端的 `sendRemoveItemFromContainer` / `sendAddItemToContainer` 只能把相对包锚定在
"容器所属角色 / 父物体 / 世界物品"三者之一上：

| 判定（顺序） | 锚点 | 能否广播 |
|---|---|---|
| `container:getCharacter() ~= nil` | 角色 | ✅ |
| `container:getParent() ~= nil` | 父物体 | ✅ |
| `container:getContainingItem():getWorldItem() ~= nil` | 世界物品 | ✅ |
| 三者皆空（典型：**物体容器里的包**） | — | ❌ → 必须由发起客户端自己补本地增量 |

`ItemContainer#getCharacter()` 会沿 `containingItem.getContainer().getCharacter()` 向上走，
而板条箱物体不是角色，所以"板条箱里的包"三个锚点全为 `null`。这是本方案的**核心边界**，
不是实现偷懒（见第七节）。

### 3.6 `resolve` / `descend` 的失败语义

```lua
resolve(player, descriptor)
  ├─ 切分平铺串 → kind / x,y,z / a / b / chain
  ├─ kind ~= "player" → cell:getGridSquare(x,y,z)；取不到 → nil
  ├─ resolveRoot(...) → 根容器；取不到 → nil
  └─ descend(root, chain)：逐层 findItemById + IsInventoryContainer + getInventory
        任一环不存在 → 整单 nil（服务端据此回 "unresolved-container"）
```

* `findItemById` 先试 `container:getItemWithID(id)`，拿不到再遍历 `getItems()` 比对 `getID()`；
* `MAX_DEPTH = 8` 是链/递归的防御性上限（在 `chainAndRoot`、`itemOutermost` 里生效）；
* `descriptorSquare(descriptor)` 供服务端做距离/安全屋校验，`player` 根返回 `nil`；
* 客户端也用同一份 `resolve` 来应用本地增量（第七节），保证两端对同一个地址的理解一致。

---

## 四、协议

### 4.1 命令契约

module 名固定为 `NCF.MODULE = "NestedContainersMPFixLua"`（`NCF.VERSION = "1.0.0"` 目前只声明、未使用 ⇒
**成功路径不打印任何启动横幅**，只有 warn / note / error 会落 `console.txt`）。

| 命令 | 方向 | 参数 | 回复 |
|---|---|---|---|
| `hello` | 客户端 → 服务端（`Events.OnCreatePlayer`） | 无 | `helloAck` |
| `helloAck` | 服务端 → 客户端 | 无 | — |
| `transfer` | 客户端 → 服务端（被接管的 `start`） | `req`(int)、`items`(`"id,id,..."`)、`src`(地址)、`dst`(地址) | `transferResult` |
| `transferResult` | 服务端 → 客户端（`sendServerCommand(player, …)`） | `req`(int)、`ok`(1/0)、`reason`(string)、`moved`(`"id,id,..."`：**真正搬走的源物品 id**)、`addBroadcast`(1/0：目标端是否已由服务端广播) | — |

* `items` 用逗号串而不是数组：与地址串同样的理由（**参数表只用扁平标量**）；
* `reason` 是诊断用的短枚举：`no-descriptor` / `unresolved-container` / `same-container` /
  `out-of-reach` / `bad-item-list` / `replacement-unsupported` / `nothing-moved` / `server-error`。
  客户端消费 `ok` / `moved` / `addBroadcast`，`reason` 留给日志与后续提示使用；
* `moved` / `addBroadcast` 是"**服务端回执驱动本地增量**"的关键（5.4）：前者告诉客户端到底搬走了哪几件源物品，
  后者告诉客户端目标端要不要自己补（能广播就别补，避免点燃态物品被替换后重复加）；
* 服务端回包是**定向**的（`sendServerCommand(player, …)`），不是广播。

### 4.2 握手与三态状态机（为什么需要 5 秒超时）

`NCF.serverSupports` 有三态，客户端据此决定"要不要接管"：

| 状态 | 何时进入 | `new()` 的行为 |
|---|---|---|
| `nil`（未知） | 加载后默认；`hello` 已发出但还没回 | 仍然接管（乐观），第一次搬运用来"探路" |
| `true` | 收到 `helloAck` | 接管 |
| `false` | **只有 5 秒超时**才进入（收到 `transferResult{ok=0}` 只让这一次动作 `forceStop`，不改状态） | **不接管**，直接走原版 → 与修复前完全一致 |

* 超时路径：`start` 记 `self.ncfDeadline = getTimestampMs() + 5000`；`update` 里超过它就
  `NCF.serverSupports = false` + `warnOnce(...)` + `forceStop()`。
* 目的是：**在没有装本模组的服务器上只卡一次 5 秒**，之后不再尝试，不会每次搬运都等待。
* 代价：若 `helloAck` 丢失（例如刚好在连接早期），第一次搬运会白等 5 秒并永久退回原版
  （当前没有"重连后再 hello"以外的重试机制，也没有 `hello` 重发定时器）。

### 4.3 `requestId` 与结果表

* 客户端自增计数器 `nextRequestId`（从 1 开始）→ `RESULTS[requestId] = { ok, moved, addBroadcast }`；
* 收到 `transferResult` → `RESULTS[req] = { ok = (ok == 1), moved = splitIds(args.moved), addBroadcast = (args.addBroadcast == 1) }`；
* `update` 消费后立即 `RESULTS[req] = nil`；动作被取消时 `stop()` 覆盖也会清掉；
* 不同客户端的计数器互相独立，且回包定向到请求者，因此 **id 不需要全局唯一**。

### 4.4 一次完整搬运的时序

```
客户端（发起者）                                     服务端
  │ Events.OnCreatePlayer ── hello ────────────────►│ OnClientCommand("hello")
  │◄──────────── helloAck（serverSupports = true）
  │
  │ ISInventoryTransferAction:new
  │   ├─ srcBad = not canVanillaAddress(src)
  │   ├─ dstBad = not canVanillaAddress(dst)
  │   └─ (srcBad or dstBad) and serverSupports ~= false → self.ncfRemote = true
  │ start()
  │   ├─ describe(src) / describe(dst)                任一端失败 → setTime(0)，退回原版
  │   ├─ shadow createItemTransaction（只记录 items）
  │   ├─ OLD_start(self)                             音效 / 动画 / checkQueueList
  │   └─ transfer{req, items, src, dst} ────────────►│ handleTransfer
  │                                                   │ resolve(src) / resolve(dst)
  │                                                   │ same-container / out-of-reach / bad-item-list
  │                                                   │ 逐件：归属 → isRemoveItemAllowed → isItemAllowed → hasRoomFor
  │                                                   │      点燃态 + 目标端广播不到 → "replacement-unsupported"
  │                                                   │      ISTransferAction:transferItem(player, item, src, dst, nil)
  │                                                   │      sendAddItemToContainer(dst, movedItem)；movedIds += 源物品 id
  │                                                   │ setExplored / setDrawDirty；moved == 0 → "nothing-moved"
  │◄──── transferResult{req, ok = 1, moved, addBroadcast} ──│
  │ RESULTS[req] = { ok, moved, addBroadcast }
  │ update(): pcall(OLD_update) 照常跑 + ncfApplyLocalDelta(moved, addBroadcast) → forceComplete()
  │
  │ 5 秒无回包 → serverSupports = false → forceStop()（此后走原版）
```

---

## 五、客户端补丁（`client/…/Client.lua`）

### 5.1 拦截面

| 钩子 | 时机 | 做了什么 |
|---|---|---|
| `new` | 构造动作 | 调用原版 `new` 后判定两端容器；需要接管则 `self.ncfRemote = true`（**只在 `serverSupports ~= false` 时**） |
| `canMergeAction` | 原版多物品合并判定 | `self.ncfRemote` 时**直接返回 `false`**（见 5.3） |
| `stop` | 动作被取消/结束 | 清 `RESULTS[self.ncfRequestId]`、`ncfWaiting = false`，再调用原版 `stop` |
| `start` | 动作开始 | `ncfRemote` 时走协议（5.2）；否则 `OLD_start` |
| `update` | 每帧 | `ncfWaiting` 时先 `pcall(OLD_update, self)`（等待期照常跑原版逻辑），再按 `RESULTS` 里的 `{ok, moved, addBroadcast}` 应用本地增量并 `forceComplete` / `forceStop`；超时 5 秒；否则 `OLD_update` |

### 5.2 为什么"临时替换 `createItemTransaction`"而不是重写 `start`

原版 `start`（`media/lua/client/TimedActions/ISInventoryTransferAction.lua:258`）里除了创建事务，
还完成了很多与事务无关的必需动作：源/目标容器开关音效、`RummageInInventory` 循环音、
`startActionAnim()`，以及**多物品合并**（`checkQueueList()`，`:309`）——
合并后的物品列表来自 `self.queueList[1].items`，并在 `:313` 交给 `createItemTransaction`。

所以补丁只做最小侵入：

```lua
local savedCreate = createItemTransaction
createItemTransaction = function(_player, items, _src, _dst)
    self.ncfItemObjects = items or { self.item }   -- 只记录要移动的物品
    return 0
end
local ok = pcall(OLD_start, self)                   -- 复用音效/动画/排队
createItemTransaction = savedCreate                 -- 立刻还原全局函数
```

* `pcall` 包住是为了"原版改动导致 start 抛错"时也能回退（打 `ERROR vanilla start failed` 并 `setTime(0)`）；
* 还原全局函数保证其他动作/其他模组不受影响；
* 返回 `0` 让 `self.transactionId = 0`，后续 `removeItemTransaction(0, …)` 是空操作。

### 5.3 `canMergeAction` 覆盖的必要性（**容易踩的坑**）

原版 `perform()`（`:477`）在结束时若 `#self.queueList > 0`（`:513`）会**再次**调用
`createItemTransaction`（`:526`）—— 此时全局函数早已还原，于是又回到**坏掉的原版事务**。
而"合并"正是发生在原版 `start()` 的 `checkQueueList()`（`:712`）里。

因此补丁覆盖 `canMergeAction`（`:702`）：

```lua
function ISInventoryTransferAction:canMergeAction(action)
    if self.ncfRemote then return false end   -- 远端动作不吞并后续动作
    return OLD_canMerge(self, action)
end
```

效果：被接管的动作不会把后续排队动作合并进自己的 `queueList`，
`perform()` 时 `#self.queueList == 0`，走正常收尾，不会二次创建原版事务。
副作用是**远端搬运事实上是"一件物品一次请求"**（服务端的 64 件上限只是防御性冗余）。

### 5.4 本地幂等增量（由服务端回执精确驱动）

服务端成功的 `transferItem` 只会广播**源端**（`ISTransferAction.lua:100` 的 `sendRemoveItemFromContainer`），
目标端广播由 `Server.lua` 补 `sendAddItemToContainer`；但两者都受 3.5 的锚点限制。
**"物体容器里的包"广播不到任何客户端**，所以发起者必须在本地把这份视图改掉。
难点是"改多少、由谁来改"——`transferResult` 里的两个字段就是答案：

| 回执字段 | 含义 | 客户端怎么用 |
|---|---|---|
| `moved` | 服务端**真正从源容器搬走**的源物品 id（`,` 分隔；被替换后的新物品**不在**这里） | 源端**只**移除这些 id；为空/缺省时视为"全部"（兼容旧服务端） |
| `addBroadcast` | `1` = 服务端已经把目标端广播出去；`0` = 广播不到 | **只有 `0` 时**才本地 `addItem` |

```lua
-- 源端：只删服务端确认搬走的那些 id（幂等：找不到就跳过）
if (movedSet == nil) or movedSet[id] then
    local localItem = NCF.findItemById(src, id)
    if localItem then src:Remove(localItem) end
end

-- 目标端：服务端广播不到时才本地加（幂等：先 containsID）
if self.ncfDstDesc and not addBroadcast then
    if (movedSet == nil) or movedSet[id] then
        if not dst:containsID(id) then dst:addItem(it) end
    end
end
```

* **精确对齐**：服务端逐件执行、`moved ≥ 1` 即回 `ok = 1`，但"搬走了哪几件"由 `moved` 说清楚，
  所以即使发生部分成功（逐件的 `isItemAllowed`/`hasRoomFor` 拒掉其中一件），
  客户端也只会动服务端真正动过的那些 id，**不会出现本地视图比服务端"多搬一件"**；
* `movedSet == nil`（服务端 `moved` 为空）被当作"全部"，这样"旧服务端 + 新客户端"也不会漏删；
* 源端/目标端都幂等 ⇒ **服务端 packet 先到后到都不会重复增删**；
* 对齐原版 packet 的客户端语义：`container:Remove(item)` / `container:addItem(item)` + `setExplored(true)`；
* `setDrawDirty(true)` 与原版 `ISInventoryTransferAction:transferItem`（`:655`、`:657`）一致
  （同一处还有 `srcContainer:setHasBeenLooted(true)`，本模组没有复刻它）；
* `addBroadcast == 1` 时**整个目标端分支都跳过**（包括 `dst:setExplored/setDrawDirty`）——
  此时刷新由服务端 packet 负责，客户端不再插手。

> 历史：更早的版本用**请求参数** `srcLocal/dstLocal` 让客户端"猜"哪一端需要自己补，
> 既猜不到服务端实际搬走了哪几件（部分成功就会错），也多了一个跨端字段。
> 现在改为**服务端回执驱动**（`moved` + `addBroadcast`），把判断权放回权威一侧。

### 5.5 失败与回退语义（"等于修复前"是硬要求）

| 情形 | 处理 | 结果 |
|---|---|---|
| 一端 `describe` 失败（如目标是裸地板容器） | `warnOnce(...)` + `action:setTime(0)` + return | 动作不搬运，与修复前一致（与**原版自身的早退写法同类**：原版在 `isAlreadyTransferred`/`dontAdd` 分支里也是 `self.action:setTime(0)` + return） |
| 原版 `start` 抛错 | `ERROR vanilla start failed` + `setTime(0)` | 同上 |
| 服务端回 `ok = 0` | `forceStop()` | 物品不动 |
| 5 秒超时 | `serverSupports = false` + `warnOnce` + `forceStop()` | 物品不动，且此后不再尝试协议 |

"不卡住、不复制、不静默丢物品"是本模组的底线；任何新分支都必须落回这四条之一。

### 5.6 与其他原生路径的行为差异（代码层面）

**已消除的差异**：早期版本在等待服务端回复期间**不调用** `OLD_update`，于是原版 `update`（`:129`）里
的每帧副作用（尸体剥取的 Unhappiness、血恐惧 Stress、`jobDelta` 与动画、
`selectedContainer` 的每帧重新选中）在这段等待期里缺失。现在等待分支会先跑原版：

```lua
local okUpdate, errUpdate = pcall(OLD_update, self)
if not okUpdate then warnOnce("vanilla update raised while waiting: " .. tostring(errUpdate)) end
```

* 此时 `self.transactionId` **恒为 `0`**（`start` 里的 `createItemTransaction` 被换成返回 `0` 的桩），
  而事务 id 由引擎从 `1` 开始分配，因此原版 `update` 里的
  `isItemTransactionDone(0)` / `isItemTransactionRejected(0)` / `getItemTransactionDuration(0)`
  都是**安全空操作**，不会被误判成"已完成 / 已拒绝"；
* `pcall` 失败只 `warnOnce` 一次（不刷屏），并且**继续往下判断应答**，不会让动作卡死。

**仍然保留的差异**：原版 `start()` 里 `if self.dontAdd then … return end` 的早退
（物品已被合成消耗等情形）补丁没有复刻。这类动作会发出一次注定失败的请求
（服务端 `findItemById` 找不到 → `moved == 0` → `ok = 0`）然后 `forceStop()`；
代价只是一次无效往返，不影响正确性，但值得实测时留意。

---

## 六、服务端（`server/…/Server.lua`）

### 6.1 校验流水线（顺序即代码顺序）

| # | 检查 | 失败 `reason` |
|---|---|---|
| 1 | `player` 存在 | —（直接 return） |
| 2 | `src` / `dst` 描述串非空 | `no-descriptor` |
| 3 | 两端都能 `resolve` 成真实容器 | `unresolved-container` |
| 4 | `src ~= dst` | `same-container` |
| 5 | 两端位置校验（6.2） | `out-of-reach` |
| 6 | 物品 id 数 `1 ≤ n ≤ 64` | `bad-item-list` |
| 7 | 逐件：在源容器里能找到 | 跳过该件 |
| 8 | 逐件：`isRemoveItemAllowed` → `dst:isItemAllowed` → `dst:hasRoomFor` | 跳过该件 |
| 9 | 逐件：**点燃态物品且目标端广播不到**（6.3 末尾） | `replacement-unsupported`（**整单拒绝**：立即 reply + return，不是跳过该件） |
| 10 | 至少移动了 1 件 | `nothing-moved` |
| 11 | `pcall` 兜底（任何 Lua 异常） | `server-error` |

成功时 `reply(player, requestId, true, "", movedIds, addBroadcast)`：
`movedIds` = 真正搬走的**源物品 id** 列表，`addBroadcast = NCF.canBroadcast(dst) and 1 or 0`。

### 6.2 距离与安全屋

| 规则 | 值 | 说明 |
|---|---|---|
| 安全屋 | `SafeHouse.isSafehouseAllowLoot(square, player)` | 不允许拾取的安全屋直接拒绝 |
| 垂直 | `math.abs(player:getZ() - square:getZ()) > 1` → 拒绝 | 同层或 ±1 层 |
| 水平 | `dx² + dy² ≤ 6.25`（= 2.5 格） | `player:getX()/getY()`（浮点）对格子整数坐标 |
| `player` 根 | `descriptorSquare` 返回 `nil` → **放行** | 根绑定在请求者自己的背包上，天然"够得着" |
| 方块未加载 | `getGridSquare` 返回 `nil` → 距离检查放行 | 但此时 `resolve` 早已失败（`unresolved-container`），走不到这里 |

### 6.3 执行：复用原版单机搬运动作

```lua
local movedItem = ISTransferAction:transferItem(player, item, src, dst, nil)
if movedItem then
    sendAddItemToContainer(dst, movedItem)
    table.insert(movedIds, id)      -- 回执里记"源物品 id"，不是替换后的新物品
end
```

`ISTransferAction:transferItem`（`media/lua/shared/TimedActions/ISTransferAction.lua:95`）是**单机也在用**的
搬运实现，复用它等于免费继承了一堆容易漏掉的副作用：

* `srcContainer:DoRemoveItem(item)`，服务端分支里还会 `sendRemoveItemFromContainer(src, item)`（`:100`，**只广播源端**）；
* `destContainer:AddItem(item)`（`:160`），以及 `removeItemOnCharacter`（从手上/身上摘除）；
* 载具部件容器的 `setContainerContentAmount(...)`（两侧都做）；
* `CandleLit` / `Lantern_HurricaneLit` 会被替换成熄灭版**并返回新物品**——
  所以目标端广播必须用**返回值** `movedItem`，不能用原来的 `item`（否则广播的是已被 `Remove` 掉的旧实例）；
  而回执里的 `moved` 记的是**源物品 id**，客户端据此只做"本地移除"，替换后的新物品完全交给服务端 packet。

**点燃态物品的前置拒绝**：正因为"替换后的新物品只能靠服务端 packet 送达"，如果目标端是**广播不到**的嵌套容器
（`not NCF.canBroadcast(dst)`），客户端永远收不到那个新物品，本地就会出现"多出/缺一个熄灭版"的不一致。
所以服务端在**搬运前**检查，命中就整单拒绝：

```lua
if REPLACEMENT_TYPES[item:getType()] and not NCF.canBroadcast(dst) then
    reply(player, requestId, false, "replacement-unsupported")
    return
end
```

`REPLACEMENT_TYPES = { CandleLit = true, Lantern_HurricaneLit = true }`。
放进普通容器 / 玩家背包（能广播）**不受影响**；正常玩法几乎遇不到这个分支。

### 6.4 `isRemoveItemAllowed` 的 `pcall` 容错

```lua
local okCheck, canRemove = pcall(function() return src:isRemoveItemAllowed(item) end)
if okCheck and canRemove ~= nil then allowed = canRemove end
```

原版也做这一层校验，但**不同版本的方法名/可见性可能变化**；与其因校验 API 改名而拒绝正常搬运，
不如"校验不可用时不拦"——因为后面还有 `dst:isItemAllowed` + `dst:hasRoomFor`，
且 `transferItem` 自身也会处理不允许的情形。容错方向是"宁可放行、不新增功能"。

> 对照：早期版本还会调用 `src:setHasBeenLooted(true)`，现在已移除（`transferItem` 的目标端路径
> 不负责 looted 标记，而本模组也不再冒充原版 `ISInventoryTransferAction:transferItem` 的那段逻辑）。

### 6.5 广播与刷新标记

| 动作 | 目的 |
|---|---|
| `sendAddItemToContainer(dst, movedItem)` | 目标端相对包（`transferItem` 只广播源端）；用替换后的 `movedItem` |
| `addBroadcast = NCF.canBroadcast(dst) and 1 or 0`（回执字段） | 告诉客户端"目标端我已经广播了，你别再本地加一遍" |
| `src:setExplored(true)` / `dst:setExplored(true)` | 让"未探索"的容器进入已探索状态（战利品窗口刷新） |
| `src:setDrawDirty(true)` / `dst:setDrawDirty(true)` | 触发容器视图重绘 |

**没有**对 `src` 做 `sendRemoveItemFromContainer`：那是 `transferItem` 内部的行为，重复发会变成双删风险。

### 6.6 上限、批次与部分成功

* `MAX_ITEMS_PER_REQUEST = 64`：防御性上限（客户端因为 5.3 的原因基本只发 1 件）；
* 逐件独立校验、独立执行，**只要 `moved ≥ 1` 就回 `ok = 1`**（部分成功也算整单成功），
  同时用 `moved` 把"真正搬走了哪几件源物品"精确回执；
* 客户端的本地增量只处理 `moved` 里的 id、并且只在 `addBroadcast == 0` 时补目标端（5.4），
  因此**部分成功不会造成本地/服务端不一致**——这正是"回执驱动"要解决的问题
  （早期版本客户端只能对请求里的全部 id 应用增量，才有该隐患）；
* 因为被接管的动作禁用了合并（5.3），`items` 恒为 `{self.item}` 单件，`moved` 通常就是"这一件或空"。

---

## 七、广播可达性：本方案的核心边界

| 容器 | `getCharacter()` | `getParent()` | `containingItem:getWorldItem()` | 服务端能否广播 | 谁负责刷新 |
|---|---|---|---|---|---|
| 玩家背包 | 玩家 | 玩家 | — | ✅ | 服务端 packet |
| 物体容器本身（板条箱 / 衣柜 / 货架） | nil | 物体 | nil | ✅（父物体锚点） | 服务端 packet |
| 尸体容器 | nil | `IsoDeadBody` | nil | ✅ | 服务端 packet |
| 载具部件容器 | nil | `BaseVehicle` | nil | ✅ | 服务端 packet |
| 地上的包（世界物品） | nil | nil | 有 | ✅ | 服务端 packet |
| **物体容器里的包**（被修复的目标场景） | nil | **nil** | **nil** | ❌（回执 `addBroadcast = 0`） | **发起客户端本地增量**（5.4） |

由此产生两个可以直接讲清楚的结论：

1. **发起者永远看到正确结果**（服务端执行 + 本地增量）；
2. **其他同时打开同一个嵌套包的玩家会保留陈旧副本**，直到重新打开该容器
   （服务端没有"把这个 parent 为空的容器的变化通知所有观看者"的手段，
   原版相对包也没有这个锚点）。这不是"少写了几行代码"，而是**通道能力上限**——
   也正是 Java 版（修 `ContainerID`，进而让原版各级广播都能正常工作）在同步上更彻底的原因。

---

## 八、兼容性与回退矩阵

| 服务端 | 客户端 | 结果 | 说明 |
|---|---|---|---|
| 装了 | 装了 | ✅ 嵌套容器可用（发起者视角） | 目标场景；观察者可能陈旧 |
| **没装** | 装了 | ⚠️ 第一次搬运卡 5 秒 → `serverSupports = false` → **完全退回修复前** | `OnClientCommand` 无人处理，没有 `transferResult`；不崩溃、不复制 |
| 装了 | 没装 | ✅ 与修复前一致 | 没装的客户端不产生 `transfer` 命令 |
| 没装 | 没装 | ❌ 原 bug | — |
| 单机 | — | ✅ 零影响 | `isClient()` / `isServer()` 都为假 → 两个 Lua 文件直接 `return` |

---

## 九、威胁模型与安全性

**服务端的信任边界**：地址串完全来自客户端，因此它只是"**声明**"，不是凭据。

| 攻击面 | 服务端的处置 |
|---|---|
| 谎报容器下标 / 坐标 | `resolve` 必须在该格子上真的找到物体与容器；找不到即 `unresolved-container` |
| 远距离 / 越层操作 | 距离 + `SafeHouse.isSafehouseAllowLoot` 校验（6.2） |
| 指定别人的背包 | `player` 根的根容器取自 `OnClientCommand` 回调传入的**连接玩家对象**，客户端无法指定别的玩家 |
| 拿不属于自己的物品 | 物品必须能在**解析出来的源容器**里按 id 找到，并过 `isRemoveItemAllowed` / `isItemAllowed` / `hasRoomFor` |
| 超大批量 | `MAX_ITEMS_PER_REQUEST = 64` |
| 坏输入 | 全部走 `reason` 拒绝；`handleTransfer` 整体 `pcall`，异常回 `server-error`，不影响服务器 |
| 新增网络面 | **不新增 packet 类型**，只用原版 `OnClientCommand` / `OnServerCommand` 通道；不需要协议版本协商 |

**已知固有弱点（与设计取舍相关，不是遗漏）**

1. `object` / `deadBody` / `vehicle` 根依赖**下标型寻址**，与原版 `ObjectContainer`
   寻址的脆弱性同级（下标会随格子内容变化而失效）——失效的后果是**拒绝该次请求**，不会误伤别的容器。
2. **没有速率限制**：客户端可以高频发 `transfer`；服务端每次都要做一次解析 + 逐件校验。
   这是可以加固的点（例如每玩家 N 次/秒），当前代码里没有。
3. `reason` 会把内部原因回给客户端，信息量很低（只是一个短枚举），可接受。

**崩溃安全**：客户端 `start` 用 `pcall` 包原版调用；服务端 `handleTransfer` 用 `pcall` 包整段；
两端所有"不确定"分支都退化为"不动物品"。这是"纯 Lua 不能在引擎里兜底"前提下唯一可行的稳健策略。

---

## 十、已知限制

1. **客户端与服务器都要装**；服务器缺失 ⇒ 第一次搬运超时后完全退回修复前。
2. **观察者陈旧**：另一位玩家同时打开同一个嵌套包时需要重新打开才会刷新（第七节）。
3. **地板 / 地面容器作为目标不修**：裸地板容器没有可描述形式 ⇒ 整单退回原版
   （把物品拖进**地上的包**是可以的，走 `worldItem` 根）。
4. **下标型地址与下标型寻址一样脆弱**（第九节第 1 点），但服务端会重新解析并做距离/安全屋/归属/容量校验，
   校验强度**不低于**原版 `Transaction` 链路。
5. **单请求 ≤ 64 件**；且被接管的动作**禁用了原版多物品合并**，实际请求基本是单件；
   服务端按实际搬走的源物品 id 精确回执（`moved`）并用 `addBroadcast` 说明目标端是否已广播，
   客户端据此对齐（5.4），**不存在"部分成功导致本地与服务端不一致"的问题**。
6. **点燃态物品不能放进"广播不到的嵌套包"**：`CandleLit` / `Lantern_HurricaneLit` 会被原版
   `transferItem` 替换成新物品，而新物品只能靠服务端 packet 送达；目标端广播不到时服务端直接拒绝
   （`replacement-unsupported`，**整单拒绝**）。放进普通容器 / 玩家背包不受影响，正常玩法几乎遇不到。
7. **补丁了 `ISInventoryTransferAction`**：与同样补丁这个类的模组存在**加载顺序**关系
   （`OLD_new/OLD_start/OLD_update/OLD_canMerge/OLD_stop` 链条会随启用顺序串起来）。

---

## 十一、验证状态

### 11.1 本文档对应的源码修订

以 `bin2_nested_containers_mp_fix_lua/Contents/mods/NestedContainersMPFixLua/42.21/` 为基准
（源码已冻结；如后续改动，哈希会变化，可据此判断文档是否过期）：

| 文件 | 行数 | mtime | SHA-256 |
|---|---|---|---|
| `media/lua/shared/NestedContainersMPFixLua/Address.lua` | 425 | 17:27:24 | `196cbd2ae4b1dc32186e67f0fb52e6219e52cc07f2a1f210716b4469b98d0116` |
| `media/lua/client/NestedContainersMPFixLua/Client.lua` | 264 | 17:38:47 | `76b9dba4dedf32f7e68d199facec44fecc05262cf9f23a109cd69359ae08fb11` |
| `media/lua/server/NestedContainersMPFixLua/Server.lua` | 157 | 17:38:47 | `ce58145c624c6b55a741b0b786faa896a62bd8523ec4dfde22c5f6203fa69e4d` |
| `mod.info` | 24 | 17:28:28 | `1061ac030774398d207f36bc1a56a92f3f59eed386332cd6aafe3bad374f06e8` |

### 11.2 已完成（静态、可复现）

| 项 | 方式 | 结果 |
|---|---|---|
| API 契约 | `bin2_nested_containers_mp_fix_lua/tools/apicheck.sh`（只读，把 36 个 API 回查游戏自带 `media/lua`） | ✅ 本机实测输出 `== 全部命中（36 项）==`（本次源码修订后复跑，结果不变） |
| 语法 | `luaparse`，`luaVersion: '5.1'` | ✅ 三个 Lua 文件解析通过（本次源码修订后复跑；本机**没有 Lua 解释器**，因此没有执行过任何 Lua 代码） |
| 原版 API 出处 | 逐行读本机游戏 Lua | ✅ `ISTransferAction:transferItem`（`shared/TimedActions/ISTransferAction.lua:95`，源端广播 `:100`，`AddItem` `:160`）、`ISInventoryTransferAction` 的 `update:129`、`start:258`（`checkQueueList:309`、`createItemTransaction:313`）、`stop:448`、`forceComplete:461`、`perform:477`（`#queueList>0:513`、二次 `createItemTransaction:526`）、`isAlreadyTransferred:563`、`canMergeAction:702`、`checkQueueList:712`、`ISBaseTimedAction:forceComplete/forceStop`（`ISBaseTimedAction.lua:24/28`） |
| 引擎侧根因 | 见[前置文档](pz-b42-nested-container-multiplayer-fix.md)第三章 | ✅ `javap` 逐条核对过（本文件不重复） |

> 本次文档工作**没有启动游戏、没有起专用服务器、没有安装任何东西**；
> 上面两项只读检查（`tools/apicheck.sh`、`luaparse`）都是在源码修订后复跑得到的记录。

### 11.3 未完成（没有任何运行时结论）

* ❌ **从未在真实联机会话里执行过**：`hello` 握手、`transfer` / `transferResult` 往返、
  5 秒超时回退、本地幂等增量都只按代码读过；"能取出/放入物品"是**设计推断**。
* ❌ 新协议字段（`moved` / `addBroadcast`）驱动的本地增量、以及
  `replacement-unsupported` 的前置拒绝分支，没有在真实会话里验证过。
* ❌ `resolve` 的五个 `kind` 分支（`player` / `object` / `deadBody` / `vehicle` / `worldItem`）
  没有在真实世界里逐个验证。
* ❌ 未测性能与网络量；未测"两名玩家并发操作同一容器"。
* ❌ 未测"服务器没装时第一次搬运卡 5 秒"的体感与日志时序。

**手工验证清单与期望日志**见
[模组 README 的"手工联机验证清单"](../bin2_nested_containers_mp_fix_lua/README.md#手工联机验证清单)。

### 11.4 后续可加固（当前未做）

* 服务端加**速率限制**（每玩家每秒 N 次 `transfer`）；
* `hello` 重发 / 握手失败后的重试，避免"一次丢包 = 整局退回原版"；
* `transferResult.reason` 上屏提示（目前只落日志/未消费）；
* 观察者刷新：可用 `sendServerCommand` 广播一条"某容器已变，请重开"的提示（当前完全不做）；
* 对 `deadBody` / `vehicle` / `worldItem` 三个分支做真实联机实测。

---

## 十二、参考链接

* 模组本体：[`bin2_nested_containers_mp_fix_lua/`](../bin2_nested_containers_mp_fix_lua/README.md)（README 含安装、验证清单、已知限制）
* 引擎级根因与 Java 哨兵方案：[`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)
* 另一个修复（ZombieBuddy / Java 版，与本模组**只能装一个**）：[`bin2_nested_containers_mp_fix/`](../bin2_nested_containers_mp_fix/README.md)
* Nested Containers - Complete（被修复的 UI 模组，工坊 `3801776436`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* PZ 官方 Modding Javadoc：`zombie.network.fields.ContainerID` — https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* ZombieBuddy（Java agent 框架；本模组**不需要**）— https://github.com/zed-0xff/ZombieBuddy

> 链接核对记录（2026-10-02，`curl -L -o /dev/null -w '%{http_code}'`）：上面 4 条外部链接均返回 **HTTP 200**。
> 所以本文件的核心论据一律以**本机游戏文件**（`media/lua` 原文行号）与**本仓库源码**为准。
