# Project Zomboid B42 嵌套容器：拿取时自动倒空（Auto Unpack）设计

> 记录时间：2026-10-02　对象：模组 **NestedContainersAutoUnpack v1.0.0**
> （[`bin2_nested_containers_auto_unpack/`](../bin2_nested_containers_auto_unpack/README.md)）
> ＋ 游戏 **42.21.0 / build `4a0e9546ec`**
>
> **前置文档**：引擎级根因、`javap` 反编译证据、ZombieBuddy 哨兵线格式见
> [`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)；
> 纯 Lua 客户端/服务端协议见 [`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)；
> 纯客户端"三步法"见 [`docs/pz-b42-nested-container-mp-fix-client.md`](pz-b42-nested-container-mp-fix-client.md)；
> 同仓库的"物品拿取"（沿用 Picking Meister 机制）见 [`docs/pz-b42-nested-container-take.md`](pz-b42-nested-container-take.md)。
> **本文件不重复那些字节码证据**，只重述一段根因，然后讲"**不改地址、把坏操作的数量降到 0**"的第四条路。
>
> **结论一句话**：本方案**不修容器寻址**，而是**换掉工作流** ——
> 当玩家把一只容器（包）拿进自己背包时，在**那次搬运真的完成之后**，
> 用原版 `ISInventoryTransferAction` 把包里的每一件东西逐个搬进玩家背包；包里若还有包，
> 由同一个补丁递归接管、逐层倒空（上限 `MAX_DEPTH = 6`）。
> 于是"从嵌套包里取东西"这个**坏操作根本不会被产生**；服务端自始至终只看到原版事务，
> 用原版逻辑校验与广播 —— **纯客户端、零协议、服务端零安装**。
> 代价是**玩法变了**：拿包等于连内容物一起拿走（无法选择性保留），
> 也帮不了"把物品放进仍留在箱子里的嵌套包"这个反方向。

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

**本方案既不修引擎，也不另开协议，更不改写那次搬运** ——
它承认"这条线上的地址坏了"，于是**让玩家不必去用那条线**：
先去拿整只包（这一步原版合法），再在包已经落到背包里之后逐件取出（每一步也都原版合法）。

---

## 二、为什么不修地址，而改工作流

本仓库对同一个根因现在有五条路。它们的差别不在"能不能用"，而在**把哪一层当成要修的对象**：

| | (a) Java 版 `mp_fix` | (b) 协议版 `mp_fix_lua` | (c) 三步法 `mp_fix_client` | **(d) 本方案 auto unpack** | (e) 物品拿取 `take` |
|---|---|---|---|---|---|
| 修的对象 | `ContainerID`（引擎，字节码补丁） | 搬运动作 + 自定义命令通道 | 一次搬运的**时序** | **玩家的工作流本身** | 一次搬运改由**服务端权威动作**执行 |
| 服务端安装 | **必须**（ZombieBuddy + 模组） | **必须**（模组） | 什么都不用 | **什么都不用** | **必须**（客户端与服务端都要装） |
| 新增网络面 | 无（复用 `ObjectInVehicle` 线格式） | 有（`sendClientCommand`） | 无（只发原版事务） | **无（只发原版事务）** | 复用引擎的 `NetTimedActionPacket` 通道 |
| "坏操作"的数量 | 0（地址被修好） | 0（改走新通道） | 0（拆成多次好搬运） | **0（压根不产生）** | 0（那条搬运不再走 `ContainerID`） |
| 观察者视图 | 精确 | 受广播锚点限制（可能陈旧） | 受影响的背包**可见地位移** | 正常（包与内容物各按原版事务广播） | 靠 `sendReplaceItemInContainer` 整包重发刷新 |
| 需要玩家改习惯吗 | 不需要 | 不需要 | 不需要 | **需要**：拿包 = 连内容一起拿走 | 不需要（照常从包里拖单件） |
| 反方向（放进嵌套包） | 支持 | 支持 | 支持 | **不支持**（仍会撞上原 bug） | 不支持（本方案只做"取出"） |

(e) 与 (d) 是**互补**的：(d) 解决"我要整只包"，(e) 解决"我只要包里的一件、包留在原处"。
(e) 走的是引擎的"网络定时动作"通道（第七节详述），因此**必须双端安装**，
而 (d) 刻意保持在纯客户端。

### 为什么 (d) 能做到"零协议、服务端零安装"

因为**原版对"包已经在自己背包链上"这一形态是完全支持的**（第三节）。
(d) 不发明任何东西，它只是把玩家原本想做的两件事**排好顺序**：

1. 先把包搬进背包 —— 这一步原版合法（物体容器 → 玩家背包）；
2. 再把包里的东西搬进背包 —— 此时源端容器的 `parent` 已经是 `IsoPlayer`，
   落在 `ContainerType.InventoryContainer` 分支上，原版可寻址（服务端递归查找）。

而 (c) 三步法做的是"把包临时提升上来搬完再放回去"，(d) 做的是"**根本不放回去**"。
(d) 因此不需要放回步骤、不需要处理"面板重选"、不需要 `canMergeAction` 加固 ——
但也因此**没有中间态可回滚**：包一旦进背包，它就留在背包里。

---

## 三、关键例外：包一进玩家背包链，原版就能寻址

这是 (d) 成立的**唯一支点**。`ContainerID#set(ItemContainer)` 的分支（本机
`javap -p -c zombie/network/fields/ContainerID.class` 逐条核对）：

| 包的最外层容器的 `parent` | 走的分支 | 服务端怎么找回来 | 结果 |
|---|---|---|---|
| `IsoPlayer` | `setInventoryContainer` → `ContainerType.InventoryContainer` + `worldItemId` | `player:getInventory():getItemWithIDRecursiv(包id)`（**递归**） | ✅ 任意深度的包都能寻址 |
| `BaseVehicle` | `setObjectInVehicle` → `vid` + `index` + `worldItemId` | `part:getItemContainer():getItemWithID(id)`（**非递归**） | ⚠️ 只有直接子物品能寻址 |
| 其他 `IsoObject`（板条箱 / 衣柜 / 尸体……） | `setObject(container, o, o.square)` → `containerIndex = o.getContainerIndex(container)` | `object.getContainerByIndex(containerIndex)` | ❌ 包容器上求得的 `containerIndex == -1` → 服务端 `null` |

第 1 行就是本方案依赖的那一支。两条 `findObject()` 侧的字节码证据：

* `ContainerType.InventoryContainer` 分支在 `findObject()` 里调用
  `ItemContainer.getItemWithIDRecursiv(int)`（`javap` 输出中该方法名出现于 `findObject` 的代码段内）；
* 该分支的容器由 `InventoryContainer.getItemContainer()` 取得（`instanceof InventoryContainer` 检查之后）。

另外，"目的地是不是在角色背包链上"这个判定用的是
`ItemContainer.isInCharacterInventory(IsoGameCharacter)`，其字节码语义为：

```
container == character:getInventory()
  || (containingItem != null && character:getInventory():contains(containingItem, true))
  || (containingItem != null && containingItem:getContainer().isInCharacterInventory(character))
```

也就是"**玩家背包本身，或背包里任意深度的包**"。本模组正是拿它当门槛（第六节），
它同时保证了"倒出来的东西有地方放"和"源端容器可寻址"。

---

## 四、时序

```
客户端（发起者）                                        原版服务端
  │
  │ 玩家把"板条箱里的包"拖进自己背包（或双击 / loot all）
  │ ISInventoryTransferAction:new(...)      ← 本模组不改 new
  │ ISInventoryTransferAction:start()
  │   ├─ OLD_start(self)  —— 原版逻辑照跑（含 createItemTransaction）
  │   │        └─ ItemTransactionPacket ─────────────────────────►│ isConsistent 校验
  │   │                                                            │ Transaction.updateItem 执行
  │   │        ◄──────────────── 原版广播（Remove / Add packet）────│
  │   ├─ 钩子（pcall）：AUNPACK.shouldUnpack(...) ?
  │   │     命中 → chainOnComplete(action, character, bagId, depth)
  │   └─ 返回（对原版这次搬运零影响）
  │
  │ … 动作推进到收尾 … ISInventoryTransferAction:perform()（原版 :477）
  │   └─ 原版按 8 个显式参数调用 self.onCompleteFunc(args[1..8])（:543–:545）
  │        ├─ 先跑"调用方原本的 onComplete"（pcall，失败只 warnOnce）
  │        └─ AUNPACK.afterTransfer(character, bagId, depth)
  │             └─ pcall(AUNPACK.unpackInto, character, bagId, depth)
  │                  ├─ playerInv:getItemById(bagId)（退路 getItemWithID）← 按 id 重新解析
  │                  ├─ 快照 inner:getItems()，截断到 64 件
  │                  └─ 逐件 ISInventoryTransferAction:new(character, contentItem, inner, playerInv, 30)
  │                       + action.aunpackDepth = depth
  │                       + ISTimedActionQueue.add(action)
  │                            └─► 这些动作各自再走一遍上面整条链（原版事务 + 原版广播）
  │                                 若 contentItem 本身是包 ⇒ 命中同一个钩子 ⇒ 递归（depth + 1）
```

**顺序是正确性的核心**：倒空必须发生在包**真的落进玩家背包之后**。
如果提前到 `start()` 里就搬，源端容器那时还在板条箱里（`containerIndex = -1`），
每一次内层搬运都会变成被拒的原版事务。

---

## 五、递归与层数

* 包内物品如果是包，它自己那次"搬进背包"的搬运会被同一个钩子命中；
* `unpackInto` 创建的每条动作都带 `action.aunpackDepth = depth`；
* 钩子里 `local depth = (self.aunpackDepth or 0) + 1` —— 于是每下沉一层，depth 加一；
* `unpackInto` 开头 `if depth > AUNPACK.MAX_DEPTH then warnOnce("depth", "nesting deeper than 6, stop unpacking") return 0 end`。

所以"三层包"的表现是：**逐层倒空**，直到第 6 层为止（正常玩法远远到不了）。
`MAX_DEPTH` 的取值会进入日志文本（`"nesting deeper than " .. tostring(AUNPACK.MAX_DEPTH)`），
改了常量日志也会跟着变。

---

## 六、实现要点

### 6.1 唯一的补丁点与失败隔离

* 补丁面只有一个：把 `ISInventoryTransferAction.start` 存进 `OLD_start`，随后覆盖它。
  `new()` **没有被改写** —— 决策放在 `start()` 时刻，这样它反映的是**当时**的世界状态。
* `OLD_start(self)` **无条件先跑**，返回值原样 `return`。
* 钩子体（门槛判定 + 挂回调）整段包在 `pcall` 里，出错只 `warnOnce("hook", "auto unpack hook failed: …")`。
* 回调体里对"调用方原有 onComplete"和"倒空"各自再 `pcall` 一层 ——
  因为回调是在原版 `perform()` 内部被调用的，**异常绝不能冒泡回原版的收尾逻辑**。

### 6.2 门槛 `AUNPACK.shouldUnpack`

| 检查 | 意图 |
|---|---|
| `destContainer:isInCharacterInventory(character)` | 目的地必须在角色背包链上（内容物有去处、源端可寻址） |
| `item:IsInventoryContainer()` | 被搬的东西本身是容器 |
| `not AUNPACK.NEVER_UNPACK[item:getType()]` | 白名单整类跳过（默认空，示例 `Base.FirstAidKit`） |
| `item:getInventory():getItems():size() > 0` | 包里确实有东西（空包不排队） |

（早先版本这里还有一行 `AUNPACK.MP_ONLY and not isClient()`；该开关已删除，见 6.5。）

### 6.3 串联而不是覆盖 `onComplete`

原版 `perform()` 是按 **8 个显式位置参数**调用 `onCompleteFunc` 的，所以串联也必须按同样形式转交：

```lua
local previousFunc = action.onCompleteFunc
local previousArgs = action.onCompleteArgs
action:setOnComplete(function()
    if previousFunc then
        local okPrev, errPrev = pcall(previousFunc,
            previousArgs and previousArgs[1], … , previousArgs and previousArgs[8])
        if not okPrev then AUNPACK.warnOnce("oncomplete", "previous onComplete failed: " .. tostring(errPrev)) end
    end
    AUNPACK.afterTransfer(character, bagId, depth)
end)
```

* 原版 `setOnComplete(func, arg1..arg8)`（`:693`）把参数打包成 `onCompleteArgs` 表，
  `perform()` 再展开成 8 个实参 —— 所以取 `args[1..8]` 是**和原版等价**的转交方式。
* 只挂一次：`start()` 每个动作只被调用一次。
* **读码观察（未实测）**：原版 `canMergeAction`（`:702`）里有
  `if action.onCompleteFunc or self.onCompleteFunc then return false end`（`:707`），
  所以本模组装了回调**之后**这个动作不再参与合并；但 `start()` 内部那次 `checkQueueList()`
  发生在**装回调之前**（`OLD_start` 先跑完），因此这一次合并仍可能发生。
  两条路径都不会导致物品丢失（倒空是按 `bagId` 重新解析、幂等地做的），但**顺序细节未经实测**。

### 6.4 `unpackInto`：按 id 重新解析 + 先快照再排队

**为什么必须按 id 重新解析**：联机下服务端把包重新加进玩家背包时，客户端会**新建**一份
物品 / 容器对象；旧引用可能已经脱离世界。用旧对象去 `getInventory()` 会拿到失效容器
（这正是"陈旧引用"那类坑）。因此：

```lua
local bagItem = playerInv:getItemById(bagId)          -- 主路径
if not bagItem then bagItem = playerInv:getItemWithID(bagId) end   -- 退路
if not bagItem or not bagItem:IsInventoryContainer() then
    AUNPACK.warnOnce("resolve", "cannot find bag " .. bagId .. " in the player inventory, skip unpacking")
    return 0
end
```

这个兜底同时覆盖了原版的两条早退路径：如果这次 `start()` 因为 `isAlreadyTransferred`（`:563`）
或 `dontAdd` 直接 `action:setTime(0)` 收尾，包可能压根不在背包里 —— 解析失败即**安全跳过**。

**为什么要快照**：`inner:getItems()` 是随搬运实时变化的列表，必须在排队**之前**把条目抄进
`contents`（同时截断到 `AUNPACK.MAX_PER_CONTAINER = 64`），再对快照逐件建动作。

**每件动作的构造**：`ISInventoryTransferAction:new(character, contentItem, inner, playerInv, 30)`
（`new` 在 `:764`；第 5 个参数 `time` 会覆盖原版算出的 `maxTime`，见 `:842`–`:843`；
而在客户端原版随后会把它改成 `-1`（`:854`–`:855`），表示"客户端等 `ItemTransactionPacket` 回执"），
再 `ISTimedActionQueue.add(action)`。

### 6.5 单机：为什么是零影响（`MP_ONLY` 已删除）

`client/Client.lua` 打补丁之前就有一道早退：

```lua
local AUNPACK = require("NestedContainersAutoUnpack/Unpack")

if not isClient() then
    return
end
```

* `isClient()` 是引擎全局函数；`javap -p -c 'zombie/Lua/LuaManager$GlobalObject.class'` 显示它就是
  `return GameClient.client;`（`isServer()` 同理是 `GameServer.server`）。
  **单机（非联机的本地游戏）`GameClient.client == false`**，于是这个文件在打补丁之前就 `return` 了。
* 结论：**单机下钩子根本不存在，本模组零影响**；`Unpack.lua` 只是被 `require` 进来定义常量与函数。
  这与仓库另一版纯客户端修复
  [`bin2_nested_containers_mp_fix_client`](../bin2_nested_containers_mp_fix_client/README.md) 的单机语义一致
  （"`not isClient()` ⇒ 文件直接 `return`"）。
* **本模组的目标场景从一开始就只有联机**（单机能直接开包拿单品）。
  早先版本里 `Unpack.lua` 还有一个 `AUNPACK.MP_ONLY` 开关，注释写着 "`false` = 单机也生效"，
  与上面这道早退**自相矛盾**（无论 `true` 还是 `false`，钩子都只存在于联机进程里，行为完全相同）。
  这个**死配置现在已被删除**，`mod.info` 的描述也同步改成
  "**联机**拿取容器（包/袋子）时自动把它里面的东西一起拿进玩家背包"，
  特性行改成"只在联机时安装（单机能直接开包拿单品，本模组在单机为零影响）"。
* 也就是说：这里选择的不是"让单机生效"，而是**让说明与行为一致**，并去掉一个永远不会起作用的开关。
  如果你**真的想让单机也自动倒空**，需要放宽 `Client.lua` 的这道早退 —— 那是另一件事。

### 6.6 配置与日志

| 常量 | 默认 | 含义 |
|---|---|---|
| `AUNPACK.MAX_DEPTH` | `6` | 递归倒空层数上限（防御性） |
| `AUNPACK.MAX_PER_CONTAINER` | `64` | 单只包一次最多排队的物品数 |
| `AUNPACK.NEVER_UNPACK` | `{}` | 按 `item:getType()` 整类跳过 |

> 常量区里现在是一条**注释**（不再是开关）："本补丁只在联机时安装
> （`Client.lua` 开头 `if not isClient() then return end`）；单机本来就能直接开包拿单品，
> 不需要它插手，所以单机为零影响。"

日志前缀是 **`[NestedContainersUnpack]`**（注意：**不是** mod id `NestedContainersAutoUnpack`，少一个 `Auto`）。

| 行 | 触发 | 频率 |
|---|---|---|
| `auto unpack enabled: taking a nested bag also moves its contents into your inventory` | 第一次真的排了队 | `loggedOnce`，每局一次 |
| `WARN nesting deeper than 6, stop unpacking` | `depth > MAX_DEPTH` | `warnOnce("depth")` |
| `WARN cannot find bag <id> in the player inventory, skip unpacking` | 解析不到包 | `warnOnce("resolve")` |
| `WARN auto unpack hook failed: …` | 钩子抛错 | `warnOnce("hook")` |
| `WARN unpack failed: …` | `unpackInto` 抛错 | `warnOnce("unpack")` |
| `WARN previous onComplete failed: …` | 调用方回调抛错 | `warnOnce("oncomplete")` |

---

## 七、与 Picking Meister 的对比：同一个点子的两种实现

工坊物品 [`3422220305` "Picking Meister"](https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305)
（mod id `P4PickingMeister`）里的 `media/lua/shared/TimedActions/P4PickingAction.lua`
用的是**同一个思路** —— "不修地址，按物品 id 重新解析，让服务端权威执行" ——
但它把搬运**自己做**了，因此走的是**引擎的"网络定时动作"通道**。

### 7.1 Picking Meister 怎么定位容器

```lua
function P4PickingAction:updateResources()
    ...
    self.srcItem     = self.srcParent:getItemById(self.srcId)   -- 先按 id 找到"装着包的容器所属的物品"
    self.srcContainer = self.srcItem:getInventory()             -- 再拿到那只包自己的容器
    self.item        = self.srcContainer:getItemById(self.itemId)  -- 再按 id 找要搬的那件东西
```

也就是说：**它不依赖 `ContainerID` 能表达什么**，而是自己拿着"包物品 id + 内容物 id"
在服务端重新走一遍"物品 → 容器 → 物品"的解析。这是与 (d) 相同的精神。

### 7.2 它与 (d) 的机制差别

| | 本方案 (d) | Picking Meister `P4PickingAction` |
|---|---|---|
| 谁执行搬运 | **原版服务端**（普通 `ISInventoryTransferAction` → 原版 `ItemTransactionPacket`） | **模组自己的 Lua 定时动作**，由服务端权威执行 |
| 服务端要不要装 | **不要** | **要**（否则服务端不认识这个 Lua 动作） |
| 新网络面 | 无 | 复用引擎的 `NetTimedAction` 通道 |
| 广播/同步 | 不用做（原版事务自带） | 手工同步（见 7.4） |
| 容器地址 | 靠"包已在玩家背包链上"这一原版分支 | 靠 `complete()` 在**服务端**重新解析 id |

### 7.3 "网络定时动作"通道的字节码证据

`zombie.characters.CharacterTimedActions.LuaTimedActionNew` 在 `projectzomboid.jar` 里（没有 `.lua` 源文件）。
本机 `javap -p -c` 逐条核对：

| 位置 | 字节码语义 |
|---|---|
| 构造函数（形参 `KahluaTable table, IsoGameCharacter`） | `if (table.getMetatable().rawget("complete") == null) useCustomRemoteTimedActionSync = true;` —— 反过来说：**只要 Lua 表定义了自己的 `complete`，`useCustomRemoteTimedActionSync` 就是 `false`** |
| `start()` | `if (GameClient.client && !useCustomRemoteTimedActionSync) { setWaitForFinished(true); transactionId = ActionManager.createNetTimedAction((IsoPlayer)chr, table); playerId.set(...); started = true; }` —— 客户端把它变成一次**网络定时动作** |
| `update()` | 客户端在 `GameClient.client && !useCustomRemoteTimedActionSync` 时轮询 `ActionManager.isDone / isRejected` → `forceComplete() / forceStop()` |
| `complete()` | `super.complete(); if (!GameClient.client) { rawget("complete") → LuaCaller.pcall(thread, fn, table) }` —— Lua 的 `complete` **只在服务端（或单机）被执行** |

所以 `P4PickingAction` 定义 `complete()` 的直接效果是：
"客户端不再本地完成，而是发一个 `NetTimedAction` 给服务端，**服务端跑 `complete()` 里的 Lua**"。
这就是它"服务端必须装"的根因 —— 服务端没有这份 Lua 动作，那条网络定时动作就无从执行。

### 7.4 `complete()` 里的手工同步

```lua
self.srcContainer:Remove(self.item)
local addedItem = self.destContainer:AddItem(self.item)
if addedItem ~= self.item then self.srcContainer:AddItem(self.item) return true end
sendRemoveItemFromContainer(self.srcContainer, self.item)
sendReplaceItemInContainer(self.srcParent, self.srcItem, self.srcItem)
sendAddItemToContainer(self.destContainer, addedItem)
```

`sendReplaceItemInContainer(srcParent, bag, bag)` 是这里的关键：**整个背包被替换了一遍**，
用来自动刷新观察者（以及发起者自己）那边"包里的东西变了"的视图。
本方案 (d) 不需要这些，因为每一步都是原版事务，原版广播本来就会处理。

### 7.5 版本核对（本机实测）

本机 Steam 工坊内容 `…/workshop/content/108600/3422220305/mods/P4PickingMeister/`
下每个版本目录的 `modversion` 各不相同：

| 版本目录 | `modversion` | `P4PickingAction.lua` 行数 |
|---|---|---|
| `42` | `1.5.1` | —（该目录无此文件） |
| `42.13` | `1.6.1` | 155 |
| `42.15` | `1.7.1` | 155 |
| `42.20` | `1.9.1` | 187 |

游戏 **B42.21 实际加载 `42.20`**（最高不超过游戏版本的目录），所以**本文以 `1.9.1` 为准**；
早先任务简报里写的 `1.7.1` 来自 `42.15` 目录，属于**目录差异**，不是记错。
本节引用的行号（`updateResources` 的 id 链、`complete()` 的三条 `send*`）都以 **`42.20` 那份 187 行**为准。

### 7.6 为什么本方案**刻意**保持纯客户端

(d) 不需要 `NetTimedAction`，因为**每一步搬运都是原版自己的动作**，
服务端本来就会执行并广播。这也是 (d) 在"公开服 / 别人的服务器"上可用的唯一理由。
代价是 (d) 只能做"取出"这一个方向，而 Picking Meister 那种服务端权威动作可以做任意方向的搬运。

> 同仓库的 [`bin2_nested_containers_take`](../bin2_nested_containers_take/README.md)（方案 (e)）
> 就是把 Picking Meister 这套机制**搬进本仓库**，用来解决"我只想从嵌套包里拿一件"这个 (d) 覆盖不了的场景；
> 它的设计文档见 [`docs/pz-b42-nested-container-take.md`](pz-b42-nested-container-take.md)。
> 两者互补：要整包用 (d)，要单件用 (e)。

---

## 八、兼容性矩阵

| 服务端 | 客户端 | 结果 |
|---|---|---|
| 纯原版（什么都没装） | 装了本模组 | ✅ **目标场景**：拿包时内容物自动跟进背包，逐层递归 |
| 装了 Java 版 / Lua 版 / 三步法版 | 同时装了本模组 | ⚠️ **不推荐**：三者假设"服务端也装"，本方案假设"服务端是纯原版"，故障时无法判断是谁在生效；且它们处理的坏操作在本方案下不会再产生 |
| 装了 `NestedContainersTake`（物品拿取，**服务端也装了**） | 同时装了本模组 | ✅ 兼容：两者补丁点不同（(e) 只在"源端是物体容器里的包"时接管，(d) 只在"把包搬进背包"时追加回调），互不抢占 |
| 装了 `NestedContainersTake`（**只装了客户端**） | 同时装了本模组 | ⚠️ 物品拿取会失败（服务端不认识那个动作），本模组的整包拿取不受影响 |
| 装了 Nested Containers 界面模组 | 装了本模组 | ✅ 兼容（本模组不替换任何 UI；嵌套按钮在"拿包"时用不上） |
| 纯原版 | 原版客户端 | ❌ 原 bug |
| 单机 | — | ✅ **零影响**（`not isClient()` ⇒ `Client.lua` 直接 `return`，见 6.5） |

---

## 九、威胁模型

**新增网络面：无。** 客户端没有新增任何 `sendClientCommand` / `sendServerCommand` /
自定义 packet，也没有改 `ContainerID` 的线格式；服务端收到的仍然只有原版 `ItemTransactionPacket`。

| 攻击面 | 处置 |
|---|---|
| "客户端伪造容器地址" | 不存在地址声明 —— 每一步都是原版事务，服务端用原版 `TransactionManager.isConsistent` 与 `Transaction.updateItem` 独立校验/执行 |
| "客户端越权拿别人的东西" | 原版 `ISInventoryTransferAction:isValid()` 照常生效（含源端 `contains` 检查等） |
| "绕过容量 / 件数上限" | **不绕过**：每一步都是原版搬运，`hasRoomFor` / `ItemNumbersLimitPerContainer` 原样生效 |
| "新增协议解析漏洞" | 无新解析面（不新增字段、不新增命令） |
| "动作队列被压死" | `MAX_PER_CONTAINER = 64` 截断；`MAX_DEPTH = 6` 限制递归 |
| 客户端自身健壮性 | 钩子 `pcall`、回调 `pcall`、原有 `onComplete` 单独 `pcall`；全部失败路径只 `warnOnce` 一行 |

**固有弱点（设计取舍，不是遗漏）**：倒空是**多次独立事务**，不是原子操作 ——
中途失败（例如背包容量不足）会留下"包已经在你背包里、内容物只搬了一部分"的中间态。
不丢东西、可手动继续搬，但模组不做事务性回滚。这一点 (c) 三步法同样存在（它的中间态是"包在背包里"）。

---

## 十、已知限制

1. **玩法真的变了**：拿包 = 连内容物一起拿走，**无法再从包里选择性只取一部分而把包留在原处**。
2. **反方向不受益**：把物品**放进**一只仍留在板条箱里的嵌套包，本模组不处理 ——
   那里仍会产生被拒的嵌套事务。
3. **单次每只包最多 64 件**（`MAX_PER_CONTAINER`）；更满的包需要**再次触发一次"搬进背包"**才会继续倒空。
4. **递归上限 6 层**（`MAX_DEPTH`），更深的嵌套不再继续倒空（防御性上限）。
5. **补丁了 `ISInventoryTransferAction`**：与同样补丁这个类的模组存在**加载顺序**关系
   （后加载者的 `OLD_start` 指向先加载者的版本）。
6. **只在联机时安装**（6.5）：单机下本模组不挂钩子、零影响；要让单机也自动倒空得改 `Client.lua` 的早退。
7. **`NEVER_UNPACK` 粒度是"物品类型"**，不能按"某一只具体的包"跳过。
8. **`canMergeAction` 的时序细节**（6.3）未经实测：`start()` 内部那次合并可能仍会发生。
9. **不处理原版本身就不允许的情形**：`dontAdd` / `isAlreadyTransferred` 等原版早退语义原样保留；
   本模组靠"按 id 重新解析失败即跳过"来保证这些路径上不误搬。
10. **它是"整包拿取"方案**：只覆盖"把包拿进背包"这一个方向；要单选包内某件物品请用 (e)
    [`bin2_nested_containers_take`](../bin2_nested_containers_take/README.md)（或三步法版 / 协议版）。

---

## 十一、验证状态

### 11.1 本文档对应的源码修订

以 `bin2_nested_containers_auto_unpack/Contents/mods/NestedContainersAutoUnpack/42.21/` 为基准：

| 文件 | 行数 | mtime | SHA-256 |
|---|---|---|---|
| `media/lua/shared/NestedContainersAutoUnpack/Unpack.lua` | 154 | 19:56:28 | `379f11958c398ba4ecd501e1e0773eb9095c68e8e7c810df26d3d1d0f2b5b48c` |
| `media/lua/client/NestedContainersAutoUnpack/Client.lua` | 67 | 19:51:07 | `ddf08c03c6efe8391bb3b86551321bd73fc1b3818f1920711bbe8ecd0bed6448` |
| `mod.info` | 19 | 19:56:28 | `a52330664ad8ef1b8f5698b9da15b1f77bf80483ac27eb398eb71c7b31be63f2` |

### 11.2 已完成（静态、可复现）

| 项 | 方式 | 结果 |
|---|---|---|
| API 契约 | `bin2_nested_containers_auto_unpack/tools/apicheck.sh`（只读；把 16 个 API 回查游戏自带 `media/lua`） | ✅ 本机实测输出 `== 全部命中（16 项）==`（退出码 0，本次源码修订后复跑） |
| 语法 | `luaparse`，`luaVersion: '5.1'` | ✅ 两个 Lua 文件解析通过；`Unpack.lua` 删除 `MP_ONLY` 后由主导 agent **复跑过**，仍通过（本机**没有 Lua 解释器**，因此没有执行过任何一行 Lua 代码；文档作者未重装 / 未重跑该检查） |
| 原版 API 出处 | 逐行读本机游戏 Lua | ✅ `ISInventoryTransferAction:start:258`、`update:129`、`stop:448`、`perform:477`（`onCompleteFunc` 8 参数显式调用 `:543`–`:545`、`#queueList > 0` 的二次 `createItemTransaction` `:526`）、`isAlreadyTransferred:563`、`setOnComplete:693`、`canMergeAction:702`（`onCompleteFunc` 检查 `:707`）、`checkQueueList:712`、`new:764`（`time` 覆盖 `maxTime`，客户端随后置 `-1`）、`ISBaseTimedAction:perform/forceComplete/forceStop`（`shared/TimedActions/ISBaseTimedAction.lua:68/24/28`） |
| 引擎侧根因 | 见[前置文档](pz-b42-nested-container-multiplayer-fix.md)第三、四章 | ✅ `javap -p -c` 逐条核对过（本文件不重复） |
| `ContainerID` 的 `InventoryContainer` 分支 | 本机 `javap -p -c zombie/network/fields/ContainerID.class` | ✅ `setInventoryContainer` 写入 `ContainerType.InventoryContainer`；`findObject()` 在该分支调用 `ItemContainer.getItemWithIDRecursiv(int)`；`setObject(...)` 写 `IsoObject.getContainerIndex(container)` |
| `ItemContainer` 判定语义 | 本机 `javap -p -c zombie/inventory/ItemContainer.class` | ✅ `isInCharacterInventory` 的三段递归语义（第三节）；`getItemById(long)` / `getItemWithID(int)` / `getItemWithIDRecursiv(int)` / `getItems()` 均存在 |
| `isClient()` 的真实含义 | 本机 `javap -p -c 'zombie/Lua/LuaManager$GlobalObject.class'` | ✅ `return GameClient.client;` ⇒ 单机为 `false` ⇒ `Client.lua` 早早 `return`（6.5） |
| Picking Meister 机制 | 本机工坊内容 `…/108600/3422220305/mods/P4PickingMeister/42.20/` 逐行读 Lua ＋ `LuaTimedActionNew.class` 的构造/`start`/`update`/`complete` 字节码 | ✅ 见第七节（含版本号 `1.9.1` 的实测记录） |

> 本次文档工作**没有启动游戏、没有起专用服务器、没有安装任何东西、没有改任何源码**；
> `tools/apicheck.sh` 只读回查游戏文件。

### 11.3 未完成（没有任何运行时结论）

* ❌ **从未在真实联机会话里执行过**：没有起过专用服务器、没有双客户端实测。
  "包和内容物都会进背包"是**基于原版代码与事务链路的设计推断**，不是实测结论。
* ❌ 拿包 → 内容物自动跟进的时序与体感（动作队列长度、音效、耗时、界面上包先出现再被填充）没有测过。
* ❌ `MAX_PER_CONTAINER = 64` 的截断与"再触发一次才继续倒空"没有实测。
* ❌ 递归层数（`aunpackDepth` 逐层 +1）与 `MAX_DEPTH = 6` 的停止行为没有实测。
* ❌ `chainOnComplete` 与"调用方已有 `onCompleteFunc`"的共存、以及 `canMergeAction` 的时序细节（6.3）没有实测。
* ❌ 单机零影响只是**读码结论**（虽然 `isClient()` 的字节码是硬的，`not isClient()` ⇒ `return` 也是直读的）。
* ❌ 未测性能与网络量；未测"两名玩家并发操作同一个容器"。

### 11.4 后续可加固（当前未做）

* 给"包内物品超过 64 件"的场景一条上屏提示（或提高上限 / 分批续排）；
* 对"loot all"与"走路打断"做一次真机实测，确认动作队列不会被压住。

**手工验证清单与期望日志**见
[模组 README 的"手工联机验证清单"](../bin2_nested_containers_auto_unpack/README.md#手工联机验证清单)。

---

## 十二、参考链接

* 模组本体：[`bin2_nested_containers_auto_unpack/`](../bin2_nested_containers_auto_unpack/README.md)（README 含安装、验证清单、已知限制）
* 引擎级根因与 `javap` 字节码证据：[`docs/pz-b42-nested-container-multiplayer-fix.md`](pz-b42-nested-container-multiplayer-fix.md)
* 纯 Lua 客户端 / 服务端协议方案：[`docs/pz-b42-nested-container-mp-fix-lua.md`](pz-b42-nested-container-mp-fix-lua.md)
* 纯客户端"三步法"方案：[`docs/pz-b42-nested-container-mp-fix-client.md`](pz-b42-nested-container-mp-fix-client.md)
* "物品拿取"方案（互补，走引擎网络定时动作通道）：[`bin2_nested_containers_take/`](../bin2_nested_containers_take/README.md)、[`docs/pz-b42-nested-container-take.md`](pz-b42-nested-container-take.md)
* 另外三个修复（与本模组**不要混装**）：[`bin2_nested_containers_mp_fix/`](../bin2_nested_containers_mp_fix/README.md)、[`bin2_nested_containers_mp_fix_lua/`](../bin2_nested_containers_mp_fix_lua/README.md)、[`bin2_nested_containers_mp_fix_client/`](../bin2_nested_containers_mp_fix_client/README.md)
* Picking Meister（同一个点子的独立实现，工坊 `3422220305`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305
* Nested Containers - Complete（界面模组，工坊 `3801776436`）— https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436
* Nested Containers（原始模组，Sioyth，工坊 `2946221823`）— https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823
* PZ 官方 Modding Javadoc：`zombie.network.fields.ContainerID` — https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html
* ZombieBuddy（Java agent 框架；本模组**不需要**）— https://github.com/zed-0xff/ZombieBuddy

> 链接核对记录（2026-10-02，`curl -s -L -o /dev/null -w '%{http_code}' --max-time 25`）：
> 上面 4 条外部链接均返回 **HTTP 200**。
> 本文件的核心论据一律以**本机游戏文件**（`media/lua` 原文行号、`javap` 字节码）与**本仓库源码**为准。
