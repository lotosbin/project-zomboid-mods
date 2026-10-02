# bin2_nested_containers_take / NestedContainersTake

面向 **Project Zomboid Build 42（42.21.0）** 的联机修复模组：
**从"嵌在板条箱 / 衣柜 / 尸体里的包"中拿取单个物品** —— 不必整包拿走，包留在原处。

它**不修容器寻址**，也不走原版 `ContainerID` 事务，而是**改用引擎自带的"网络定时动作"通道**：
把一次自定义定时动作放在 `shared/` 并给它定义 `complete()`，引擎
（`zombie.characters.CharacterTimedActions.LuaTimedActionNew`）就会把它变成一次
`NetTimedActionPacket` 发给服务端，**由服务端权威执行**；动作参数只带"物品 id + 容器引用"，
两端各自按 id 还原路径（`bagParent:getItemById(包id)` → `包:getInventory()` → `getItemById(物品id)`），
**完全不依赖容器地址**。这套机制**沿用 Picking Meister**（工坊
[`3422220305`](https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305)，mod id `P4PickingMeister`，
本机加载的 `42.20` 版即 `modversion=1.9.1`）里的 `P4PickingAction`。

> * 引擎级根因（`ContainerID` 为什么表达不了嵌套容器）与 `javap` 字节码证据：
>   [`docs/pz-b42-nested-container-multiplayer-fix.md`](../docs/pz-b42-nested-container-multiplayer-fix.md)
> * 本模组的**机制三步、引擎证据、与另外五个方案的对比、源码修订表**：
>   [`docs/pz-b42-nested-container-take.md`](../docs/pz-b42-nested-container-take.md)

**与"拿取时自动倒空"（[`bin2_nested_containers_auto_unpack`](../bin2_nested_containers_auto_unpack/README.md)）互补**：
那个解决"我要整只包"，本模组解决"我只要包里的一件、包留在原处"。

---

## 它做什么、不做什么

| | 本模组 |
|---|---|
| 修 `ContainerID` / 线格式 / 引擎吗 | **不修**。只是**绕开**它，改用引擎的网络定时动作通道 |
| 新增自定义网络包 / `sendClientCommand` 吗 | **不新增**。复用引擎的 `NetTimedActionPacket` |
| 服务端要装什么吗 | **必须装本模组**（客户端靠它发请求，服务端靠它执行搬运） |
| 触发条件 | 这次搬运的**源容器**是"原版 `ContainerID` 寻址不了的嵌套包"（即包在一个物体容器里），**且** id 链检查通过 |
| 覆盖范围 | **只覆盖"包直接位于可寻址容器里"这一层**（板条箱 / 衣柜 / 货架 / 尸体……）；更深嵌套不受益 |
| 方向 | 只做"**取出**"（包 → 玩家背包 / 其它容器）；不做"放进嵌套包" |
| 校验 | `isValid()` 做 `destContainer:isItemAllowed` + `destContainer:hasRoomFor` + `pcall(srcContainer:isRemoveItemAllowed)`（取不到就不拦），并且**服务端 `complete()` 会再过一次**；仍**未复刻**服务器选项 `ItemNumbersLimitPerContainer` |
| 时长与动画 | 沿用原版：`getDuration()` 照抄 `ISInventoryTransferAction:new` 的算法，`start()` 放 `RummageInInventory` 与 `Loot` 动画 |
| 单机能用吗 | **单机不介入**（`Client.lua` 开头 `if not isClient() then return end`，见下文"单机行为"） |

---

## ⚠️ 与其它几个模组的关系

本仓库现在有**五种**处理同一个根因的方案：

| 方案 | 实现层 | 服务端安装 | 一句话 |
|---|---|---|---|
| (a) [`bin2_nested_containers_mp_fix`](../bin2_nested_containers_mp_fix/README.md) | [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy) 字节码补丁，改 `ContainerID` | **必须**（双端 ZombieBuddy + 模组） | 引擎级修复，同步最彻底，安装面最重 |
| (b) [`bin2_nested_containers_mp_fix_lua`](../bin2_nested_containers_mp_fix_lua/README.md) | 纯 Lua **自定义协议**（地址串 / 命令 / 回执） | **必须** | 零 Java 依赖，但要自己复刻校验与广播 |
| (c) [`bin2_nested_containers_mp_fix_client`](../bin2_nested_containers_mp_fix_client/README.md) | 纯客户端"提升 → 搬运 → 放回"三步法 | **不用装** | 唯一"服务端零安装"的取放方案，代价是背包可见地位移 |
| (d) [`bin2_nested_containers_auto_unpack`](../bin2_nested_containers_auto_unpack/README.md) | 纯客户端：拿包时顺手把包倒空 | **不用装** | 坏操作"压根不产生"，但玩法变了（拿包 = 连内容一起拿走） |
| (e) `bin2_nested_containers_take`（**本模组**） | 纯 Lua **双端**：共享定时动作 + 服务端权威执行（沿用 Picking Meister 机制） | **必须** | 照常从包里拖单件，包留在原处；只覆盖一层嵌套 |

**与 (d) 的关系**：互补且可以共存 —— (e) 只在"源端是物体容器里的包"时接管，
(d) 只在"把包搬进玩家背包"时追加回调，两者不会抢同一次搬运。
要整包用 (d)，要单件用 (e)。

**与 Picking Meister 的关系**：机制相同（共享动作 + `complete()` ⇒ 网络定时动作 + 按 id 还原 + 显式同步），
本模组是**针对"嵌套包"这一种情形专门写的小实现**（只有一个动作、只做取出、不做通用拾取 UI）。
区别与取舍见设计文档。

**同一时间只装一个（重叠时）**：(a) / (b) / (c) / (e) 都在"处理那次坏搬运"，
彼此不能共存；(d) 让嵌套搬运不再产生，因此和 (a)(b)(c) 混装没有意义。

**(e) 与 Nested Containers 界面模组**（[Nested Containers - Complete](https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436)，工坊 `3801776436`）**兼容**：
本模组不替换任何 UI，只是在原版那条坏掉的取物路径上换了个执行者。

---

## 根因（一段话）

原版 `zombie.network.fields.ContainerID` **无法表达"嵌在物体容器里的容器"**：
`ContainerID#set(ItemContainer)` 处理包容器时会取该包的**最外层容器**，再按最外层容器的 `parent` 分支；
当 `parent` 是板条箱 / 衣柜 / 货架 / 尸体这类普通 `IsoObject` 时，它走
`setObject(container, o, o.square)`，写出的 `containerIndex = o.getContainerIndex(container) == -1`；
服务端 `ContainerID#findObject()` 据此调用 `object.getContainerByIndex(-1)` → `null`，
于是 `Transaction#updateItem()` 返回 `false`，事务被 Rejected —— **物品永远不动，玩家侧也没有任何提示**。
单机从不使用 `ContainerID` / `Transaction`（`ISTransferAction:transferItem` 直接操作对象引用），所以单机一直正常。

> 逐条 `javap -p -c` 字节码证据在
> [`docs/pz-b42-nested-container-multiplayer-fix.md`](../docs/pz-b42-nested-container-multiplayer-fix.md) 第三、四章。
> 本文件不重复，只讲"**为什么不修它，而是换一条引擎通道**"。

---

## 机制：三步

```
① 客户端拦截（client/NestedContainersTake/Client.lua）
   文件开头 `if not isClient() then return end` —— 单机不装补丁（见"单机行为"）
   覆盖 ISInventoryTransferAction:start()
     ├─ sourceNeedsRemoteTake(srcContainer)  —— 源端是不是"原版寻址不了的嵌套包"（镜像 ContainerID.set 的分支）
     ├─ canTakeById(action)                  —— PM 式 id 链检查：外层容器 → 包 → 物品，全靠 id
     └─ 都通过 ⇒ ISTimedActionQueue.addAfter(self, NCFNestedTakeAction)
                  self.ncfNestedTakeStep = true                  ← 标记已接管，再次进入不会重复排队
                  self.started = true; self.action:setTime(0)     ← 本次原版动作"空转完成"
       否则 ⇒ OLD_start(self)（原版路径，一个字节都不改）

② 引擎把它变成网络定时动作（zombie.characters.CharacterTimedActions.LuaTimedActionNew）
   动作定义了自己的 complete() ⇒ 构造函数不再置 useCustomRemoteTimedActionSync
     ⇒ start() 里 GameClient.client && !useCustomRemoteTimedActionSync
        ⇒ ActionManager.createNetTimedAction(player, table) → NetTimedActionPacket 发给服务端
     ⇒ 服务端 NetTimedActionPacket.processServer 校验（isConsistent）后 ActionManager.start()

③ 服务端权威执行（NCFNestedTakeAction:complete()，引擎只在 !GameClient.client 时回调 Lua）
   isValid() 作为最后一道闸：updateResources()（按 id 还原"外层容器 → 包 → 物品"）
                             + destContainer:isItemAllowed(item)
                             + destContainer:hasRoomFor(character, item)
                             + pcall(srcContainer:isRemoveItemAllowed(item))
   ⚠️ 顺序：先 destContainer:AddItem(item)（它内部会把物品从原容器摘掉）
            └─ 返回 nil ⇒ 直接 return false，源端未被改动（不会丢物品）
            └─ 成功 ⇒ sendRemoveItemFromContainer(srcContainer, item)
                       sendReplaceItemInContainer(bagParent, bagItem, bagItem)   ← 关键：整包重发
                       sendAddItemToContainer(destContainer, addedItem)
```

**为什么必须"整包重发"**：被拿走的物品里那层容器（`srcContainer` = 包自己的 `ItemContainer`）
`getCharacter()` / `getParent()` / `getWorldItem()` **三个广播锚点全为空**，
所以 `sendRemoveItemFromContainer(srcContainer, item)` **到不了任何观察者**（下面有字节码证据）。
而 `bagParent`（装着这只包的板条箱容器）**有锚点**，把"整只包"替换一次，客户端就会重收这只包
（`InventoryContainer.save()` 会**连同包内内容一起序列化**），发起者与附近玩家的包内视图因此刷新。

---

## 引擎证据（本机 `javap -p -c`，`projectzomboid.jar`）

### 1. 网络定时动作通道

`zombie.characters.CharacterTimedActions.LuaTimedActionNew`（B42.21 里**没有 `.lua` 源文件**，只有 class）：

| 位置 | 字节码语义 |
|---|---|
| 构造函数 | `if (table.getMetatable().rawget("complete") == null) useCustomRemoteTimedActionSync = true;` —— 反过来说：**定义了自己的 `complete` ⇒ `useCustomRemoteTimedActionSync == false`** |
| `start()` | `if (GameClient.client && !useCustomRemoteTimedActionSync) { setWaitForFinished(true); transactionId = ActionManager.createNetTimedAction((IsoPlayer)chr, table); playerId.set(...); started = true; }` |
| `update()` | 客户端在 `GameClient.client && !useCustomRemoteTimedActionSync` 时轮询 `ActionManager.isDone / isRejected` → `forceComplete() / forceStop()` |
| `complete()` | `super.complete(); if (!GameClient.client) { rawget("complete") → LuaCaller.pcall(thread, fn, table) }` —— **Lua 的 `complete` 只在服务端（或单机）被执行** |
| `valid()` | 调 Lua 的 `isValid`，**只有明确返回 `true` 才算有效** ⇒ `NCFNestedTakeAction:isValid()` 为假时动作不会执行 |

`zombie.network.packets.NetTimedActionPacket.processServer(...)` 的反汇编：先 `isConsistent(...)`，
再 `zombie.core.ActionManager.start(Action)` —— 也就是"服务端自己跑一遍这个动作"。
（`Action.isConsistent` 只做 `PlayerID.isConsistent` 这一层的身份/连接校验。）

### 2. 为什么 `sendReplaceItemInContainer` 能补上广播洞

`zombie.network.GameServer.sendReplaceItemInContainer(container, oldItem, newItem)` 的分支：

| 条件 | 行为 |
|---|---|
| `container:getCharacter() instanceof IsoPlayer` | `INetworkPacket.send(player, ReplaceInventoryItemInContainer, …)` |
| 否则 `container:getParent() != null` | `INetworkPacket.sendToRelative(…, parent.x, parent.y, …)` |
| 否则 `container.inventoryContainer:getWorldItem() != null` | `sendToRelative(…, worldItem.x, worldItem.y, …)` |
| **都不满足** | **直接 return —— 什么都不发**（这就是"嵌套包容器没有锚点"的那个洞） |

所以本模组传的是 **`bagParent`（装着包的那个板条箱容器）**，它落在第 2 支、锚点是板条箱所在格子；
如果传的是 `srcContainer`（包自己的容器），就会落进第 4 支、一个包都发不出去。

序列化链：`PlayerItem.write` → `InventoryItem.save(ByteBuffer, boolean)`（虚方法）→
`InventoryContainer.save(ByteBuffer, boolean)` → `ItemContainer.save(ByteBuffer)`
⇒ **整只包连同包内内容一起上线**，这正是"替换一次就刷新包内视图"的原理。
（`INetworkPacket.send(IsoPlayer, …)` 与 `sendToRelative(...)` 的第一句都是
`if (GameServer.server)` ⇒ 单机下这些 `send*` 是引擎侧空操作。）

### 3. "按 id 还原"用到的 API

`ItemContainer.getItemById(long)` 是本模组唯一的定位手段（`canTakeById` 里还额外要求它存在）。
整条链是：`bagParent:getItemById(bagId)` → `bagItem:IsInventoryContainer()` →
`bagItem:getInventory()`（`InventoryContainer` 提供）→ `srcContainer:getItemById(itemId)`。

---

## 目录结构

```
bin2_nested_containers_take/                          ← Steam 工坊物品目录
│                                                        （本机已软链到 ~/Zomboid/Workshop/bin2_nested_containers_take）
├── workshop.txt                                      ← 工坊发布信息（中文优先，当前 visibility=private）
├── README.md                                         ← 本文件
├── tools/
│   └── apicheck.sh                                   ← 离线 API 契约自检（只读，不需要启动游戏）
└── Contents/mods/NestedContainersTake/
    └── 42.21/                                        ← B42 版本目录（必须有，否则模组管理里看不到）
        ├── mod.info                                  ← id / versionMin=42.20.0（无 require、无 javaJarFile）
        ├── poster.png                                ← 封面图（512×768 PNG）
        └── media/lua/
            ├── shared/TimedActions/NCFNestedTakeAction.lua   ← 共享动作（**双端都要有**：定义 complete() 才走网络定时动作）
            └── client/NestedContainersTake/Client.lua         ← 补丁 ISInventoryTransferAction:start()（只装客户端）
    （没有 server/：服务端靠 shared/ 里的那个动作）
```

> 注：`tools/apicheck.sh` 现已把校验用的 `isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed` 一并纳入自检（共 **34 项**，本机实测 `== 全部命中（34 项）==`）。

> 模组管理里的名字：**嵌套容器 · 单品拿取**（`mod.info` 的 `name` 是
> `嵌套容器 · 单品拿取 (Nested Containers - Take Single Item)`；`id` = `NestedContainersTake`）。
>
> 日志前缀是 `[NestedContainersTake]`（与 mod id 一致）。

---

## 文件清单

| 文件 | 行数 | 作用 |
|---|---|---|
| `shared/TimedActions/…/NCFNestedTakeAction.lua` | 185 | 共享动作 `NCFNestedTakeAction`（`ISBaseTimedAction:derive`）。`updateResources()` 按 id 还原"外层容器 → 包 → 物品"；**`isValid()` = `updateResources()` + `destContainer:isItemAllowed(item)` + `destContainer:hasRoomFor(character, item)` + `pcall(srcContainer:isRemoveItemAllowed(item))`（取不到该项就不拦）**；`getDuration()` 照抄 `ISInventoryTransferAction:new` 的时长算法；`start()` 只做客户端表现（`RummageInInventory` 音效 + `Loot` 动画 + 容器方位）；`stopLoopingSound/stop/perform` 收尾；**`complete()` 先过 `isValid()`，再按"先 AddItem 后发同步包"的顺序服务端权威搬运**；`new(character, itemId, bagId, bagParent, destContainer)` 设 `stopOnWalk/stopOnRun = true`、`maxTime = getDuration()`。 |
| `client/…/Client.lua` | 134 | 补丁面。**文件开头 `if not isClient() then return end`（单机不装补丁）**；`sourceNeedsRemoteTake(container)` 镜像 `ContainerID.set` 的分支（只看源端）判断"是不是物体容器里的包"；`canTakeById(action)` 做 PM 式 id 链检查；命中则 `action.ncfNestedTakeStep = true` + `ISTimedActionQueue.addAfter(self, NCFNestedTakeAction)` + `self.ncfNestedTakeStep = true` + `self.started = true` + `self.action:setTime(0)` 让原版动作空转，否则 `OLD_start(self)`；日志 `logOnce` + 计数器 `NCFTakeCount` + 一次性告警 `NCFTakeWarned`。 |
| `42.21/mod.info` | 17 | 模组元数据：`id=NestedContainersTake`、`modversion=1.0.0`、`versionMin=42.20.0`、`poster=poster.png`，**无 `require=`、无 `javaJarFile`**；描述明确写"**客户端与服务端都要启用本模组**"以及"只覆盖一层嵌套"。 |
| `workshop.txt` | 21 | 工坊发布信息（中英双语描述、要求与限制、`tags=Build 42`、`visibility=private`）。 |
| `tools/apicheck.sh` | 19 | 离线 API 契约自检：把本模组依赖的 **31 个游戏 API** 逐个回查游戏自带 `media/lua`，全部命中才输出 `== 全部命中（34 项）==`。 |

### 本文档对应的源码修订（可用于核对是否被改动）

以 `bin2_nested_containers_take/Contents/mods/NestedContainersTake/42.21/` 为基准：

| 文件 | 行数 | mtime | SHA-256 |
|---|---|---|---|
| `media/lua/shared/TimedActions/NCFNestedTakeAction.lua` | 185 | 20:10:22 | `724077ffd086ae9edc41d0f4efd3aa2bdf202c6b3642191c836994c586027b6d` |
| `media/lua/client/NestedContainersTake/Client.lua` | 134 | 20:10:22 | `30a0aae5d221fea9cdc2225d33560de4843cc02b0a2b95c95bd966f52aa4ee6a` |
| `mod.info` | 17 | 19:55:42 | `66df3d0f1a9982add3db9b2750733b168cd301b7513fc098f2827ac232243f53` |

---

## 实现要点

### 唯一的补丁点：`ISInventoryTransferAction:start()`

```lua
-- Client.lua 开头：单机不装补丁（单机本来就能开包拿单品，且单机下 send* 是空操作、动作链路不同）
if not isClient() then
    return
end

function ISInventoryTransferAction:start()
    if not self.ncfNestedTakeStep then
        local ok, handled = pcall(function()
            if not self.item or not self.srcContainer or not self.destContainer then return false end
            if not sourceNeedsRemoteTake(self.srcContainer) then return false end
            local bag, bagParent = canTakeById(self)
            if not bag then return false end
            local action = NCFNestedTakeAction:new(self.character, self.item:getID(), bag:getID(), bagParent, self.destContainer)
            action.ncfNestedTakeStep = true
            ISTimedActionQueue.addAfter(self, action)
            self.ncfNestedTakeStep = true  -- 标记本次原版动作已被接管：再次进来不会重复排队
            self.started = true
            self.action:setTime(0)         -- 本次原版动作空转完成，搬运交给上面的动作
            NCFTakeCount = (NCFTakeCount or 0) + 1
            logOnce("nested take: taking single items out of nested bags (e.g. "
                .. tostring(self.item:getName()) .. " from bag " .. tostring(bag:getID()) .. ")")
            return true
        end)
        if ok and handled then return end
        if not ok then
            if not NCFTakeWarned then
                NCFTakeWarned = true
                print("[NestedContainersTake] WARN hook failed: " .. tostring(handled))
            end
        end
    end
    return OLD_start(self)
end
```

* **单机直接不装**：`if not isClient() then return end`（放在 `require` / `log` 之后），与
  [`bin2_nested_containers_auto_unpack`](../bin2_nested_containers_auto_unpack/README.md) 版约定一致
  ⇒ 单机零影响。
* **命中时完全不跑 `OLD_start`** —— 于是这次搬运**不会**去构造 `ContainerID`、**不会**产生那个注定被拒的原版事务。
* 用 `started = true` + `action:setTime(0)` 让原版动作**空转完成**（原版 `isValid()` 里
  `if not self.started and not isItemTransactionConsistent(...)` 这一句会因此跳过）。
* **`ncfNestedTakeStep` 两边都设**：新动作上设一次（语义标记），**本次原版动作上也设一次** ——
  守卫 `if not self.ncfNestedTakeStep then` 因此不再是死代码（同一动作再次进入不会重复排队）。
* 一切判定包在 `pcall` 里；出错只打**一行** `WARN hook failed: …`（`NCFTakeWarned` 一次性）然后**回落原版**（`OLD_start`）。
* `ISTimedActionQueue.addAfter(self, action)`：把自定义动作排在这次空转动作之后。

### `sourceNeedsRemoteTake(container)`：只判断"源端是不是需要远端代拿"

| 检查 | 返回 | 对应 `ContainerID#set` 的哪一支 |
|---|---|---|
| `container:getParent()` 是 `IsoPlayer` | `false`（不接管） | `PlayerInventory` —— 原版本来就能寻址 |
| `container:getContainingItem()` 为 `nil` | `false` | 不是"某只包自己的容器"（例如 floor / worldItem 容器） |
| `bag:getContainer()` 为 `nil` | `false` | 包不在任何容器里（失效引用） |
| 包所在容器的 `parent` 是 `IsoPlayer` | `false` | `InventoryContainer`（服务端 `getItemWithIDRecursiv` 递归查找） |
| 包所在容器的 `parent` 是 `BaseVehicle` | `false` | `ObjectInVehicle`（直接子物品可用） |
| 包所在容器 `getType() == "floor"` | `false` | `floor` / `WorldObject` 分支 |
| `bag:getWorldItem() ~= nil` | `false` | 地面上的包（世界物品） |
| **以上都不满足** ⇒ 包在一个普通物体容器里 | **`true`（接管）** | `setObject(...)` → `containerIndex = -1` → 服务端 `null` |

也就是说：**只有"包在板条箱 / 衣柜 / 货架 / 尸体这类物体容器里"才会接管**；
地面上的包、载具部件里的包、玩家背包里的包中包一律走原版（它们本来就可用）。

### `canTakeById(action)`：PM 式可行性检查

```
bag = srcContainer:getContainingItem()          必须是 IsInventoryContainer
bagParent = bag:getContainer()                  必须存在且有 getItemById
resolvedBag = bagParent:getItemById(bag:getID())   ← 服务端将来也要走同一条路
inner = resolvedBag:getInventory()
inner:getItemById(item:getID())                 必须能找到要拿的那件东西
```

**这条检查是"预先模拟服务端能否还原"**：`bagParent` 作为动作参数发给服务端，
服务端到时也要用 `bagParent:getItemById(bagId)` 找回那只包。客户端先验证一遍，
避免明明不可能成功还去发一个注定失败的网络动作。

### `isValid()`：不只是"id 链能不能还原"

```lua
function NCFNestedTakeAction:isValid()
    if not self:updateResources() then return false end
    if not self.destContainer:isItemAllowed(self.item) then return false end   -- 目标容器白名单
    if not self.destContainer:hasRoomFor(self.character, self.item) then return false end  -- 放得下吗
    local okCheck, canRemove = pcall(function()                               -- 源容器允许取走吗
        return self.srcContainer:isRemoveItemAllowed(self.item)
    end)
    if okCheck and canRemove == false then return false end                   -- 取不到该方法就不拦
    return true
end
```

* 这一个函数**同时**是：客户端的提前拦截、引擎 `valid()` 的判定依据（Java `LuaTimedActionNew.valid()`
  只认布尔 `true`）、以及**服务端 `complete()` 的第一道闸**（`complete()` 第一句就是 `if not self:isValid() then return false end`）。
* `isRemoveItemAllowed` 用 `pcall` 包住："方法名跨版本可能变，取不到就不拦" —— 与协议版 (b) 同策略。
* **仍然没有复刻**的是原版事务内部的 `ItemNumbersLimitPerContainer`（服务器选项控制的每容器物品数上限）——
  它写在原版 `ISInventoryTransferAction:isValid()` 里，本动作不复刻（见"已知限制"第 3 条）。

### `complete()`：服务端权威搬运 + 显式同步

```lua
function NCFNestedTakeAction:complete()
    -- 服务端权威校验（最后一道闸）：不合法就什么都不做
    if not self:isValid() then return false end
    local bagParent, bagItem = self.bagParent, self.bagItem

    -- 顺序很重要：ItemContainer:AddItem() 内部会把物品从原容器摘掉，
    -- 所以先 Add 再发同步包 —— 若 Add 失败（返回 nil）源端仍未被动过，不会丢物品。
    local addedItem = self.destContainer:AddItem(self.item)
    if not addedItem then return false end

    sendRemoveItemFromContainer(self.srcContainer, self.item)
    if bagParent and bagItem then
        sendReplaceItemInContainer(bagParent, bagItem, bagItem)   -- 关键：整包重发，刷新包内视图
    end
    sendAddItemToContainer(self.destContainer, addedItem)
    return true
end
```

三个细节：

* **先 `AddItem` 再发同步包**（与 Picking Meister 的 `Remove` → `send…` → `AddItem` → `send…` 顺序**相反**）。
  这是刻意的：`ItemContainer:AddItem(item)` 内部会先 `item.container.Remove(item)` 再把物品挂到自己身上
  （本机 `javap -p -c zombie/inventory/ItemContainer.class` 已核对），
  所以**"能不能加进去"这一步失败时源端一丝未动** —— 不存在"已从源端摘掉却加不进目标端"的丢物品窗口。
* **`sendReplaceItemInContainer(bagParent, bagItem, bagItem)` 的第二个/第三个参数都是同一只包** ——
  "把这只包替换成它自己"，效果是**让客户端重收一份（含内容）**；这是本方案唯一一处"绕过原版增量广播"的地方。
* **搬运本身没有自定义回执**：`complete()` 在服务端执行，广播由上面三条 `send*` 负责；
  引擎既有的 `forceComplete / forceStop`（客户端 `update()` 轮询 `ActionManager.isDone / isRejected`）
  仍然会走，但**动作里没有任何"物品到底搬没搬成"的返回字段**，所以客户端不掌握结果。

### 日志与失败语义

| 行 | 触发 | 频率 |
|---|---|---|
| `[NestedContainersTake] nested take: taking single items out of nested bags (e.g. <物品名> from bag <包id>)` | 第一次接管成功 | **每局只打一次**（`logOnce` / `NCFTakeLoggedOnce`）；括号里是**首次**那件物品的例子 |
| `[NestedContainersTake] WARN hook failed: …` | 钩子体抛错 | **每局只打一次**（`NCFTakeWarned`），之后同类错误静默回落原版 |

* 接管次数记在全局计数器 **`NCFTakeCount`** 上 —— 但它**只在内存里累加、不打印**
  （供将来做汇总行或调试用）。
* `NCFNestedTakeAction` 自身**没有任何日志**（服务端也不打印）。
* 也就是说：**本模组的日志是"每局一行成功 + 最多一行告警"**，不会因批量操作刷屏。

失败路径是"静默"的：

| 情形 | 结果 |
|---|---|
| `canTakeById` 返回 nil（客户端预先检查失败） | 不接管，走 `OLD_start`（原版行为，该次搬运仍会被服务端拒绝——与修复前一致） |
| 钩子抛错 | 每局一次 `WARN hook failed` + 回落 `OLD_start` |
| 客户端创建了动作，但服务端 `isValid()` / `updateResources()` 失败 | `isValid()` / `complete()` 为假 ⇒ 该动作不执行搬运 ⇒ **物品不动**（静默）。客户端那次原版动作已经空转完成，所以**这次拿取等于什么都没发生** |
| 目标容器**满** / 不允许放入 / 源容器不允许取走 | 现在会被 `isValid()` 拦下（客户端提前拦、服务端 `complete()` 再拦一次）⇒ **物品不动**，且**不会**改坏任何容器 |

---

## 安装

### 客户端（**必须**）

1. 订阅 / 安装本模组，或把仓库目录软链到 `~/Zomboid/mods/` 与 `~/Zomboid/Workshop/`
   （**本机已经建好这两条软链**）：
   ```bash
   ln -s "/Volumes/StorageMacMini/liubinbin/Github/lotosbin/project-zomboid-mods/bin2_nested_containers_take/Contents/mods/NestedContainersTake" \
         ~/Zomboid/mods/NestedContainersTake
   ln -s "/Volumes/StorageMacMini/liubinbin/Github/lotosbin/project-zomboid-mods/bin2_nested_containers_take" \
         ~/Zomboid/Workshop/bin2_nested_containers_take
   ```
2. 启动游戏 → **模组管理** → 勾选 **Nested Containers - Take Single Item**。
3. 进游戏即可，**没有构建步骤、没有授权弹窗、没有额外依赖**。

### 专用服务器（**必须，否则本模组完全不生效**）

把 `bin2_nested_containers_take` 放进服务器的 `Workshop/`（或 `steamapps/workshop/content/108600/`），
在 `servertest.ini` 的 `Mods=` 里加上 `NestedContainersTake`。

**语义限制（不是 bug）**：本方案需要客户端与服务器**双方都装**。
原因是搬运由**服务端**的 Lua 动作执行（第 3 步）—— 服务端没有这份 `NCFNestedTakeAction`，
那条 `NetTimedActionPacket` 就无从执行。

> 注意与 (a)(b) 的差别：那两个是"服务端没装 ⇒ 退回修复前"，
> 而本模组**没有回退机制** —— 客户端拦下原版动作之后就把希望寄托在那条网络动作上，
> 服务端没装时表现为**这次拿取什么都没发生**（不崩、不复制、不卡动作）。

### 单机

**不需要启用，也不会有任何影响** —— 原因见下一节。

---

## 单机行为：已加 `isClient()` 早退，单机为零影响

`client/NestedContainersTake/Client.lua` 在 `require` / `log` 之后就是：

```lua
-- 与 auto_unpack 版保持一致：单机不需要本模组（单机本来就能开包拿单品），
-- 而且单机下 send* 是空操作、动作链路不同，接管只会改变原有行为 —— 所以单机直接不装补丁。
if not isClient() then
    return
end
```

* `isClient()` 是引擎全局函数；`javap -p -c 'zombie/Lua/LuaManager$GlobalObject.class'` 显示它就是
  `return GameClient.client;`（`isServer()` 同理是 `GameServer.server`）。
  **单机（非联机的本地游戏）`GameClient.client == false`** ⇒ 这个文件在**打补丁之前就 `return`**。
* 结论：**单机下 `ISInventoryTransferAction:start()` 没有被覆盖，本模组零影响** ——
  单机照常走原版 `ISTransferAction:transferItem`（直接操作对象引用）那条路，本来就能开包拿单品。
  这与 [`bin2_nested_containers_auto_unpack`](../bin2_nested_containers_auto_unpack/README.md) 版的约定一致。
* 为什么要加这道早退（即使不加也"大概能用"）：单机下 `LuaTimedActionNew.start()` 不会创建 `NetTimedAction`
  （`GameClient.client == false`），而 `complete()` 会在本地被调用（`if (!GameClient.client)`），
  `send*` 又都是引擎空操作（`INetworkPacket.send(IsoPlayer, …)` / `sendToRelative(…)` 首句是 `if (GameServer.server)`）——
  结果是"能搬，但走的不是原版搬运路径"，属于无意义的差异。早退把它变成**纯零影响**。

---

## 手工联机验证清单

> ⚠️ **本模组只有静态验证，从未在真实联机会话里跑过**（见文末"未验证（诚实版）"）。
> 第一次实测请按下面的清单逐项核对，并把 `console.txt` 里的 `[NestedContainersTake]` 行
> （以及原版报错行）一起记录下来。

准备：一台**装好本模组**的专用服务器 + 一个装好本模组的客户端；
另备两次对照实验：**服务器不装**、以及**单机**。

### 期望在 `~/Zomboid/console.txt` 看到的（我们的行）

| 时机 | 日志行 | 含义 |
|---|---|---|
| 第一次接管成功（**每局仅一次**） | `[NestedContainersTake] nested take: taking single items out of nested bags (e.g. <物品名> from bag <包id>)` | 该次取物已改由网络定时动作执行；括号里是首次那件物品 |
| 钩子出错（**每局仅一次**） | `[NestedContainersTake] WARN hook failed: …` | 该次回落原版，之后同类错误不再打印 |

> 本模组**没有启动横幅、没有每局一次的汇总行**（接管次数只记在内存变量 `NCFTakeCount` 里、不打印）；
> 服务端侧也没有本模组自己的日志。
> 排查时请对照服务端 `console.txt` 里原版的 `NetTimedActionPacket` / Action 相关行。

### 期望**不再**看到的（原版的拒绝路径）

| 日志行 | 出处 | 说明 |
|---|---|---|
| `Inconsistent: source container is not contain the item (…)` | `TransactionManager.isConsistent` | 走本通道的取物不再产生原版事务，因此不应出现 |
| `Inconsistent: destination container can't be found (…)` | 同上 | 同上 |
| `ERROR: sendItemsToContainer: invalid vehicle id` | `ContainerID.findObject()` | 本模组不产生嵌套地址，不应出现 |

> 这些 `Inconsistent:` 文本走 `DebugType.noise` → `noiseWithTraceOffset`，
> 而该方法第一句就是 `if (!Core.debug) return;` —— **只有调试模式（`-debug`）才会落盘**。

### 手工场景表

| # | 场景 | 期望 |
|---|---|---|
| 1 | 联机：板条箱 → 包（**直接**在箱子里）→ 从包里**拖单件**到玩家背包 | 能拿出来；包**留在箱子里**且只剩没拿的东西（这正是本模组存在的理由）；出现 `nested take: …` |
| 2 | 同上 → 把单件**放进**那只包 | 本模组不处理（`sourceNeedsRemoteTake` 看的是**源**端）；`ISInventoryTransferAction` 的源端是玩家背包 ⇒ 走原版，仍会被服务端拒绝（与修复前一致） |
| 3 | 衣柜 / 货架 / 冰箱里的包 → 取单件 | 同场景 1（同为普通 `IsoObject` 容器） |
| 4 | **尸体**容器里的包 → 取单件 | 同场景 1 |
| 5 | 玩家背包里的包中包 → 取单件 | **不接管**（`getParent()` 是 `IsoPlayer`），与修复前一致（原版本就能用） |
| 6 | 载具部件里的包（直接子物品）→ 取单件 | **不接管**（`parent` 是 `BaseVehicle`），与修复前一致 |
| 7 | 地面上的包 → 取单件 | **不接管**（`getType() == "floor"` / 有 `worldItem`），与修复前一致 |
| 8 | **两层包**：板条箱 → 包 A → 包 B → 从 B 里取单件 | ⚠️ **不受益**：`bagParent` 是包 A 的容器，服务端同样还原不出来。`canTakeById` 通常仍会通过（客户端能按 id 找到 B），接管后由服务端 `updateResources()` 判否 ⇒ **什么都不做**（静默不生效，不是损坏）；正确做法是先用三步法 / 协议版把 A 提到背包 |
| 9 | **对照组：服务器不装**本模组 | 客户端仍会接管并排动作，但服务端没有 `NCFNestedTakeAction` ⇒ 该次取物**什么都没发生**（不崩、不复制、不卡动作） |
| 10 | **单机**：板条箱里的包 → 取单件 | ✅ **完全不接管**（`not isClient()` ⇒ `Client.lua` 直接 `return`）；与未装模组的单机完全一致 |
| 11 | 目标容器**已满** / 不允许放入 / 源容器不允许取走 | 现在**会被 `isValid()` 拦下**（客户端提前拦 + 服务端 `complete()` 再拦一次）⇒ 物品不动、容器不变；需要实测确认"不接管"还是"接管后动作无效" |
| 12 | 取物期间**走路 / 跑步** | 本动作 `stopOnWalk = true` / `stopOnRun = true` ⇒ 会打断（与原版搬运同语义） |
| 13 | 连续取多件（同一只包、同一目标） | 日志只出现**一次** `nested take: …`（`logOnce`）；`NCFTakeCount` 只在内存里累加，每件仍各走一次网络动作 |

**回归重点**：物品数量守恒（不复制、不消失、包内剩余数量正确）、
**动作不卡住**（不出现"一直卡在搬运动作里"）、
`console.txt` 里没有落在 `ContainerID` / `Transaction` 上的 `NullPointerException`。

---

## 已知限制

1. **只覆盖"包直接位于可寻址容器里"这一层**（板条箱 / 衣柜 / 货架 / 尸体 / 冰箱……）。
   原因：`bagParent` 也会作为动作参数发给服务端，**它自己若还是"嵌套包里的包"**，
   服务端同样还原不出来（`ContainerID` 表达不了它，客户端的 `getItemById` 链也就断在服务端）。
   "板条箱 → 包A → 包B → 取 B 里的东西"这种更深的嵌套，需要先用
   [三步法版](../bin2_nested_containers_mp_fix_client/README.md) 或
   [协议版](../bin2_nested_containers_mp_fix_lua/README.md) 把外层包提到背包。
   **注意**：客户端的 `sourceNeedsRemoteTake` **不判断深度**，`canTakeById` 往往也仍会通过，
   所以深层场景**仍会被接管**，然后由服务端 `updateResources()` 判否 —— 表现为**静默不生效**
   （物品不动、容器不变，属"什么都没发生"而非"损坏"）。这一条**未实测**。
2. **必须双端安装**，且**没有回退机制**：服务端没装时，被接管的那次取物"什么都没发生"
   （不会像 (b) 协议版那样超时后回落）。
3. **校验已补齐，但仍有一处残留差距**：`isValid()` 现在做了
   `destContainer:isItemAllowed` / `destContainer:hasRoomFor` /
   `pcall(srcContainer:isRemoveItemAllowed)`（取不到该方法就不拦），
   **仍然没有复刻**的是服务器选项 `ItemNumbersLimitPerContainer`（每容器物品数上限）——
   它写在原版 `ISInventoryTransferAction:isValid()` 内部、依赖 `getServerOptions()`，
   本动作不复刻。服务端侧的 `Action.isConsistent` 也只做 `PlayerID` 这一层的身份/连接校验。
4. **只做"取出"方向**：把物品**放进**仍留在物体容器里的嵌套包不在覆盖范围内。
5. **单机为零影响**：`Client.lua` 有 `if not isClient() then return end` 早退，
   单机不会覆盖 `ISInventoryTransferAction:start()`（见"单机行为"）。
6. **补丁了 `ISInventoryTransferAction`**：与同样补丁这个类的模组存在**加载顺序**关系
   （后加载者的 `OLD_start` 指向先加载者的版本）。
7. **依赖 `shared/TimedActions/` 这个路径**：动作必须放在 `shared/`（双端都能加载到）并定义 `complete()`；
   放进 `client/` 或去掉 `complete()` 都会让引擎改走"本地执行"，方案立刻失效。
8. **日志是"每局一次"**：成功行由 `logOnce`（`NCFTakeLoggedOnce`）控制、告警由 `NCFTakeWarned` 控制；
   接管次数只在 `NCFTakeCount` 里累加、**不打印**。代价是"第二件之后发生了什么"在日志里看不出来。

---

## 未验证（诚实版）

**已验证（静态、可复现）**

* 文件与行数：`NCFNestedTakeAction.lua` 185 / `Client.lua` 134 行；SHA-256 见上文"本文档对应的源码修订"
  （改动后哈希会变，可用它判断是否已被修改）。
* **API 契约自检**：`./tools/apicheck.sh` 在本机（42.21.0，build `4a0e9546ec`）实测输出
  `== 全部命中（34 项）==`（本次源码修订后复跑，退出码 0）—— 本模组用到的每个游戏 API
  都能在游戏自带 `media/lua` 里找到出处：
  `ISBaseTimedAction` / `ISInventoryTransferAction` / `ISTimedActionQueue` / `addAfter` /
  `getItemById` / `IsInventoryContainer` / `getInventory` / `getContainingItem` / `getContainer` /
  `getType` / `getWorldItem` / `getParent` / `getID` / `getName` / `isInCharacterInventory` /
  `getCapacityWeight` / `getMaxWeight` / `getActualWeight` / `isWearingAwkwardGloves` /
  `isTimedActionInstant` / `Remove` / `AddItem` / `sendRemoveItemFromContainer` /
  `sendAddItemToContainer` / `sendReplaceItemInContainer` / `getContainerPosition` /
  `getFreezerPosition` / `setActionAnim` / `setAnimVariable` / `playSound` / `getEmitter`。
  （新增的 `isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed` 三项**不在**这份 34 项清单里，
  它们是本机 `javap -p -c zombie/inventory/ItemContainer.class` 逐个核对存在的方法。）
* **语法**：两个 Lua 文件用 `luaparse`（`luaVersion: '5.1'`）解析通过 ——
  **本次源码修订后由主导 agent 复跑，仍通过**（本机**没有 Lua 解释器**，
  因此**没有执行过任何一行 Lua 代码**；文档作者未重装 / 未重跑该检查）。
* **引擎侧事实**（本机 `javap -p -c`，`projectzomboid.jar`）：
  * `zombie.characters.CharacterTimedActions.LuaTimedActionNew`：构造函数
    `if (table.getMetatable().rawget("complete") == null) useCustomRemoteTimedActionSync = true;`；
    `start()` 在 `GameClient.client && !useCustomRemoteTimedActionSync` 时调
    `ActionManager.createNetTimedAction((IsoPlayer)chr, table)`；`update()` 轮询
    `ActionManager.isDone / isRejected`；`complete()` 只在 `!GameClient.client` 时 `pcall` Lua 的 `complete`；
    `valid()` 只有 Lua `isValid` 明确返回 `true` 才算有效。
  * `zombie.inventory.ItemContainer`：`isItemAllowed(InventoryItem)` / `hasRoomFor(IsoGameCharacter, InventoryItem)` /
    `isRemoveItemAllowed(InventoryItem)` 均存在；**`AddItem(InventoryItem)` 的内部顺序**是
    "`item == null` → null"、"`containsID(item.id)` → 打日志并返回**已存在的那件**"、
    否则 `if (item.container != null) item.container.Remove(item)` → `item.container = this` → `items.add(item)`
    —— 也就是**先把物品从原容器摘掉再挂到目标容器**，成功时返回该物品。
  * `zombie.network.packets.NetTimedActionPacket.processServer(...)` → `isConsistent(...)` +
    `ActionManager.start(Action)`；`Action.isConsistent` → `PlayerID.isConsistent` → `IDShort.isConsistent`
    （身份/连接层，不含容量校验）。
  * `zombie.network.GameServer.sendReplaceItemInContainer` / `sendRemoveItemFromContainer` /
    `sendAddItemToContainer` 的**四支锚点逻辑**（character → parent → worldItem → 什么都不发）；
    `INetworkPacket.send(IsoPlayer, …)` 与 `sendToRelative(PacketType, float, float, …)` 的第一句都是
    `if (GameServer.server)` ⇒ 单机为空操作。
  * 序列化：`PlayerItem.write` → `InventoryItem.save(ByteBuffer, boolean)`（虚）→
    `InventoryContainer.save(ByteBuffer, boolean)` → `ItemContainer.save(ByteBuffer)` ⇒ 整包含内容。
  * `zombie.Lua.LuaManager$GlobalObject.isClient()` == `GameClient.client`（单机为 `false`）。
* **原版 API 出处核对**（本机 B42.21 游戏文件）：
  `ISBaseTimedAction:perform/forceComplete/forceStop`（`shared/TimedActions/ISBaseTimedAction.lua:68/24/28`）、
  `ISTimedActionQueue.addAfter` 的调用形态（`shared/Vehicles/TimedActions/ISAddGasolineToVehicle.lua:99/102`）。
* **Picking Meister 对照**：本机 `…/108600/3422220305/mods/P4PickingMeister/42.20/`（`modversion=1.9.1`）
  的 `P4PickingAction.lua`（187 行）逐行读过，本模组的 `updateResources` / `getDuration` 与它同构；
  `complete()` 的**发送内容**相同，但**顺序相反**（本模组先 `AddItem` 再发同步包）。
* 本次文档工作**没有启动游戏、没有起专用服务器、没有安装任何东西、没有改任何源码**。

**未验证（没有任何运行时结论）**

* ❌ **从未在真实联机会话里执行过**：没有起过专用服务器、没有双客户端实测。
  "能拿出单件、包留在原处"是**基于引擎字节码与动作链路的设计推断**，不是实测结论。
* ❌ **最关键的一条**：`NetTimedAction` 会不会原样序列化 `bagParent` 这个 **Java 对象引用**
  （`KahluaTable` 里的 `ItemContainer`），以及服务端拿到的它是否还有效 —— **没有实测**。
  这既决定方案能否成立，也正是"更深嵌套会静默不生效"的原因所在。
* ❌ `sendReplaceItemInContainer(bagParent, bag, bag)` 是否真的能让**发起者**与
  **附近旁观玩家**的包内视图都刷新，没有实测（`PlayerItem` 的序列化链是读码结论）。
* ❌ 单机"零影响"虽然由 `not isClient()` ⇒ `return` 直接推出，但**没有实机跑过**。
* ❌ 新补的三项校验（`isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed`）在真实容器上
  是否拦得住该拦的、放得过该放的，没有实测；`ItemNumbersLimitPerContainer` 的残留差距也没有实测。
* ❌ "目标容器已存在同 id 物品"这条边角没有实测：按 `AddItem` 的字节码，这种情况**不会返回 nil**，
  而是打一行 `Error, container already has id` 并返回**已存在的那件**，动作会继续发同步包。
* ❌ 服务端没装时的"静默失败"、深层嵌套的"静默不生效"都没有实测。
* ❌ 走路 / 跑步打断、`loot all`、多人并发操作同一只包没有实测。
* ❌ 未测性能与网络量（每次取物都是一次 `NetTimedActionPacket` 往返 + 一次整包序列化）。

第一次实测请严格按上面的"手工联机验证清单"走，并把 `console.txt` 里的
`[NestedContainersTake]` 行、`Inconsistent:` 行一起记录下来。

---

## 致谢

* **PePePePePeil** —— "Picking Meister"（本模组的机制来源）
* **Sioyth** —— 原创 "Nested Containers"（工坊 [2946221823](https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823)）
* **Nikku Miru** —— "Nested Containers - Complete" 的 B42 维护
* **Zed** —— [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy)（本模组**不依赖**它）

本模组是独立的第三方修复，**不写入**上游模组所在的 Steam 工坊内容目录
（`steamapps/workshop/content/108600/` 下任何他人的物品目录），只读取它们来做现象与机制核对。

## 参考链接

* Nested Containers - Complete（界面模组，工坊 `3801776436`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* Picking Meister（机制来源，工坊 `3422220305`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305
* PZ 官方 Modding Javadoc：`zombie.network.fields.ContainerID` — https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* ZombieBuddy（Java agent 框架，本模组**不需要**）— https://github.com/zed-0xff/ZombieBuddy
* 本仓库内的相关文档：
  * [`docs/pz-b42-nested-container-multiplayer-fix.md`](../docs/pz-b42-nested-container-multiplayer-fix.md)（引擎级根因 + `javap` 字节码证据 + Java 哨兵方案）
  * [`docs/pz-b42-nested-container-mp-fix-lua.md`](../docs/pz-b42-nested-container-mp-fix-lua.md)（纯 Lua 客户端/服务端协议方案）
  * [`docs/pz-b42-nested-container-mp-fix-client.md`](../docs/pz-b42-nested-container-mp-fix-client.md)（纯客户端"三步法"方案）
  * [`docs/pz-b42-nested-container-auto-unpack.md`](../docs/pz-b42-nested-container-auto-unpack.md)（"拿取时自动倒空"方案，与本模组互补）
  * [`docs/pz-b42-nested-container-take.md`](../docs/pz-b42-nested-container-take.md)（本模组的设计文档）

> 链接核对记录（2026-10-02，`curl -s -L -o /dev/null -w '%{http_code}' --max-time 25`）：
> 上面 4 条外部链接均返回 **HTTP 200**。
