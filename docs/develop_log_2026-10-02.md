# 开发日志 - 2026-10-02

## 嵌套容器联机修复：从引擎根因定位到两个交付模组

### 任务背景

用户报告：**"联机模式无法拿取嵌套包内的物品，单机可以"**，服务的模组是
Nested Containers - Complete（工坊 `3801776436`，本地只读目录
`~/Library/Application Support/Steam/steamapps/workshop/content/108600/3801776436/mods/NestedContainersComplete`）。
要求：定位问题，并新建一个"通过补丁方式修复"的模组。

### 一、根因：引擎层缺陷，不是模组 bug

联机搬运链路：

```
ISInventoryTransferAction:start()            -- media/lua/client/TimedActions/ISInventoryTransferAction.lua
  → createItemTransaction()                  -- Java 全局函数
    → zombie.core.TransactionManager.createItemTransaction
      → zombie.core.Transaction.set()        -- 为源/目标各建一个 ContainerID
        → 客户端发 zombie.network.packets.ItemTransactionPacket
          → 服务端 TransactionManager.isConsistent(...) → Transaction.updateItem(...)
```

`zombie.network.fields.ContainerID#set(ItemContainer)` 对"嵌在物体容器里的容器"
（板条箱/衣柜/货架/冰箱/尸体里的包）会走 `setObject(container, o, o.square)`，写入
`containerIndex = o.getContainerIndex(container)`；该容器**不属于**这个物体 ⇒ **`-1`**。
服务端 `ContainerID#findObject()` 执行 `object.getContainerByIndex(-1)` → **null**
（`zombie.iso.IsoObject`），`Transaction#updateItem()` 随即 `return false` ⇒ 事务 **Reject**，物品从未移动。

三条旁证（均为本机 `javap -p -c` / CFR 反编译 `projectzomboid.jar` 所得）：

1. `IsoObject.getContainerByIndex(-1)` 返回 null；
2. `Transaction.updateItem` 在容器为 null 时走 `iconst_0; ireturn`；
3. `DebugType.noise` 首句 `if (!Core.debug) return` ⇒ **玩家侧毫无提示**（这也是"什么都没有发生"的原因）。

**单机为什么正常：** 单机不走事务，`ISTransferAction:transferItem` 直接用对象引用搬运。
原版自己也承认该限制（`ISInventoryTransferAction.lua` 注释）：
*"This isn't done for bags inside bags in object containers."*

### 二、方案评估（5 选 2）

| # | 方案 | 依赖 | 决策 |
|---|------|------|------|
| 1 | ZombieBuddy Java 补丁，直接改 `ContainerID` | 客户端+服务端都要 ZombieBuddy | 放弃 |
| 2 | 纯 Lua 客户端+服务端自定义命令协议 | 服务端必须装 | 放弃 |
| 3 | 纯客户端"三步法"（提升→搬运→放回） | 无 | 放弃 |
| 4 | 拿包即倒空 `bin2_nested_containers_auto_unpack` | 无（纯客户端） | **保留** |
| 5 | 物品拿取 `bin2_nested_containers_take` | 客户端+服务端都要装本模组 | **保留** |

放弃 1/2/3 是用户决定（2026-10-02）：三者都是"修容器地址"路线，实现与边界复杂；方案 5 正面解决了原始诉求
（从嵌套包里拿**单个**物品），方案 4 作为"服务端不能装模组"时的纯客户端备选保留。
三个方案对应的模组目录已由用户删除，`~/Zomboid/{mods,Workshop}` 下 6 个悬空软链已清理；
`docs/` 保留其三份设计文档并加"已放弃"标注（其中根因证据仍被保留方案引用）。

#### 决定取舍的关键发现：引擎自带"网络动作"通道

`zombie.characters.CharacterTimedActions.LuaTimedActionNew`：

```java
// 构造函数
if (table.getMetatable().rawget("complete") == null) this.useCustomRemoteTimedActionSync = true;
// start()
if (GameClient.client && !this.useCustomRemoteTimedActionSync) {
    this.setWaitForFinished(true);
    this.transactionId = ActionManager.getInstance().createNetTimedAction((IsoPlayer)this.chr, this.table);
}
// update()：轮询 ActionManager.isDone/isRejected，并把服务端 duration 回写 maxTime
// complete()
if (!GameClient.client) { ...pcall( table.rawget("complete") )... }
```

服务端 `zombie.network.packets.NetTimedActionPacket.processServer` 会先
`isConsistent(connection)` 再 `ActionManager.start(act)`；服务端侧 `zombie.core.NetTimedAction`
只回调 `getDuration / adjustMaxTime / serverStart / serverStop / complete / animEvent`。

⇒ **只要一个共享 Lua 动作定义了 `complete()`，它就自动获得"客户端请求、服务端权威执行"的能力**，
无需任何自定义协议，`Done/Reject`、时长、动画、队列语义全部由引擎负责。

#### 先例模组：Picking Meister（工坊 3422220305）

其 `P4PickingAction`（本地 `.../3422220305/mods/P4PickingMeister/42.20/media/lua/shared/TimedActions/P4PickingAction.lua`，
该目录 `modversion=1.9.1`）正是这条路线的现成实现：

- `updateResources()` 按物品 id 还原容器：`srcParent:getItemById(srcId)` → `srcItem:getInventory()` → `getItemById(itemId)`；
- `complete()`：`Remove` + `sendRemoveItemFromContainer` + **`sendReplaceItemInContainer(srcParent, bag, bag)`** + `AddItem` + `sendAddItemToContainer`；
- 其中 `sendReplaceItemInContainer(外层容器, 包, 包)` 把**整只包重发**，而 `InventoryContainer.save()` 会连包内内容一起序列化，
  正好补上"嵌套包容器没有相对广播锚点"的洞（其 `getCharacter()` / `getParent()` / `getWorldItem()` 全为空，
  `sendRemoveItemFromContainer` 对它是空操作）。

### 三、交付物 1：`bin2_nested_containers_take`（物品拿取，已提交推送）

```
bin2_nested_containers_take/
├── preview.png                     # 256x256 工坊预览图（官方 ModTemplate 同尺寸）
├── poster.png                      # 模组管理器海报（512x768）
├── changelog.txt                   # 版本 1.0.0 (2026-10-02)
├── workshop.txt / README.md
├── tools/apicheck.sh               # 34 项游戏 API 契约自检
└── Contents/mods/NestedContainersTake/42.21/
    ├── mod.info
    └── media/lua/
        ├── shared/TimedActions/NCFNestedTakeAction.lua   # 204 行：共享动作（定义 complete() ⇒ 自动同步）
        └── client/NestedContainersTake/Client.lua        # 184 行：拦截 + 批量合并 + 面板刷新
```

**机制：**

1. 客户端拦截 `ISInventoryTransferAction:start()`，仅在**源容器是原版寻址不了的嵌套包**且
   id 链检查（`bagParent:getItemById(bagId)` → `getInventory()` → `getItemById(itemId)`）通过时接管；
2. 把队列里**同源容器 + 同目标容器**的连续搬运动作合并成**一次** `NCFNestedTakeAction`
   ⇒ 多选 / 全拿只花一次服务端往返；
3. 服务端 `complete()` 按 id 还原后逐件搬运并显式同步，最后整包 `sendReplaceItemInContainer` 刷新；
4. 拿完客户端按包 id 把正开着的面板重新指向刷新后的容器（短时重试 ≤3s），解决"包内容显示没更新"。

**校验复刻原版：** `destContainer:isItemAllowed` / `hasRoomFor` / `srcContainer:isRemoveItemAllowed`，
并且服务端 `complete()` 第一句就调 `isValid()` 作为权威闸门。**防丢物品：** 先 `AddItem`（内部会摘下源物品）再发同步包。

**验证：** `luaparse`(Lua 5.1) 通过；`tools/apicheck.sh` `== 全部命中（34 项）==`；
`preview.png` 尺寸对齐官方模板 256×256。**没有运行过游戏**（本机无 Lua 解释器），全部结论为静态核对。

**提交：** `0edb1fe bin2_nested_containers_take`，已推送 `origin/main`（`f96de5c..0edb1fe`）。

### 四、交付物 2：`bin2_nested_containers_auto_unpack`（拿包即倒空，纯客户端）

拿取容器时自动把包内物品一起搬进玩家背包（逐层递归，`MAX_DEPTH=6`），**服务端零安装**。

关键顺序：包必须先落进玩家背包，其容器才被原版寻址
（`ContainerID` 的 `InventoryContainer` 分支：`player:getInventory():getItemWithIDRecursiv(包id)`），
之后每一步都是普通原版事务，因此公开服也能用。校验：`tools/apicheck.sh` `== 全部命中（16 项）==`。
代价：拿包就整包倒空（不能选择性保留），且不解决"往仍留在箱子里的嵌套包放东西"。

### 五、过程中被修掉的真实缺陷（子代理读码复核发现）

| 缺陷 | 修法 |
|---|---|
| 单机也会接管（`Client.lua` 缺 `isClient()` 早退） | 加早退，单机零影响 |
| 缺容量/白名单/可取走校验 | 补 `isItemAllowed` / `hasRoomFor` / `isRemoveItemAllowed`，服务端 `complete()` 再校验 |
| `AddItem` 返回 nil 时物品已离开源容器（丢物品窗口） | 改为"先 AddItem，成功才发同步包" |
| 批量=每件一次往返 | 合并同源同目标动作，一次往返 |
| 拿完包内视图不刷新（面板仍捏着旧容器对象） | `sendReplaceItemInContainer` 整包重发 + 客户端按包 id 重指面板（短时重试） |
| auto_unpack 的 `MP_ONLY` 是死配置、说明与行为不符 | 删除死配置，说明改为"只在联机时安装" |

### 六、手工联机验证清单（尚未执行）

1. 单机对照：装上模组后单机行为与原来一致（`take` 因早退完全不介入）。
2. 板条箱 → 包 → 取出一件物品；（**本条是原始诉求**）
3. 框选多件 / "全拿" → 期望一次动作搬完，包内视图随即刷新；
4. 尸体里的包、载具部件里的包、地面上的包；
5. 背包里再套包（原版本来可用）→ 不应被接管；
6. 服务端不装 `take` 时 → 行为退回修复前（物品拿不出来），无崩溃、无复制、无不同步；
7. `console.txt` 期望：`[NestedContainersTake] nested take enabled: ...`（每局一次）、
   `[NestedContainersUnpack] auto unpack enabled: ...`（每局一次）；
   不再出现原版 `ERROR: sendItemsToContainer: invalid vehicle id`（需 `-debug` 才有的 `Inconsistent:` 除外）。
8. 回归重点：物品数量守恒、动作队列不卡、面板重选后能继续正常拿取。

### 七、未验证与已知风险（诚实版）

1. **零运行时验证**：本机没有 Lua 解释器、没有跑过联机会话；所有"能用"都是静态推断。
2. `bagParent`（`ItemContainer` 对象引用）能否原样通过 `NetTimedActionPacket` 往返，是本方案**最需要真机确认**的一环
   （先例 Picking Meister 同样依赖它）。
3. `take` 只覆盖"包直接位于可寻址容器里"这一层；更深的嵌套会进入拦截判定但被 id 链/服务端校验判否 ⇒ **静默不生效（非损坏）**。
4. 服务端 `updateResources()` 失败时客户端不掌握结果（无回执/无回滚，只被客户端预检削弱）；
   服务器选项 `ItemNumbersLimitPerContainer` 未复刻（属原版事务内部逻辑）。
5. `apicheck.sh` 只能证明"用到的 API 名字仍出现在游戏自带 `media/lua` 里"，不能证明语义未变。

### 八、经验沉淀

- **引擎层缺陷要到引擎里找证据**：`javap -p -c` + CFR 反编译 `projectzomboid.jar` 是把"猜"变成"证"的最快路径；
  本次所有关键结论（`containerIndex = -1`、`getContainerByIndex(-1) → null`、`updateItem → ireturn false`、
  `LuaTimedActionNew` 的 `complete()` 开关）都来自字节码，而非文档。
- **能用引擎现成通道就不要自造协议**：`complete()` 一写，就白拿"服务端权威执行 + Done/Reject + 时长回写 + 动画 + 队列"。
- **嵌套容器没有相对广播锚点** ⇒ `sendReplaceItemInContainer(外层容器, 包, 包)` 整包重发是通用刷新手段。
- **客户端会重建物品/容器对象**：任何跨帧保留的容器引用都可能 `getContainer() == nil`（陈旧引用），
  必须按物品 id 重新解析；把陈旧引用交回原版可能落进 floor 分支，甚至产生永远等不到回执的事务（动作卡死）。
- **手动搬运顺序**：先 `AddItem` 再发同步包，避免 `AddItem` 失败时物品已离开源容器。
- **离线自检要工具化**：`luaparse`（Lua 5.1 语法）+ 每个模组自带 `tools/apicheck.sh`（游戏 API 契约回查）。
- **子代理读码复核确实能抓到真缺陷**：本轮 3 处真实问题（SP 接管、缺校验、丢物品窗口）都是复核发现的。
- **构建环境**：B42.21 的 `projectzomboid.jar` 是 **Java 25**（class 主版本 69）编译，
  `javac 17` 读不了游戏 class；JDK 必须 ≥ 游戏版本（已装 Temurin 25 于
  `~/Library/Java/JavaVirtualMachines/temurin-25.jdk`，且 `/usr/libexec/java_home -v 25` 认不出手工解包版，
  构建脚本需自行遍历目录）。ZombieBuddy 2.3.2 仍是 Java 17 字节码。

### 参考链接

| 内容 | 链接 |
|---|---|
| 被修复的 UI 模组 Nested Containers - Complete（3801776436） | https://steamcommunity.com/sharedfiles/filedetails/?id=3801776436 |
| 原始 Nested Containers（Sioyth，2946221823） | https://steamcommunity.com/sharedfiles/filedetails/?id=2946221823 |
| 机制先例 Picking Meister（3422220305） | https://steamcommunity.com/sharedfiles/filedetails/?id=3422220305 |
| ContainerID Javadoc | https://projectzomboid.com/modding/zombie/network/fields/ContainerID.html |
| ZombieBuddy（已放弃方案曾依赖） | https://github.com/zed-0xff/ZombieBuddy |
| 引擎类（本机反编译 `projectzomboid.jar`） | `zombie.network.fields.ContainerID`、`zombie.core.Transaction(Manager)`、`zombie.characters.CharacterTimedActions.LuaTimedActionNew`、`zombie.network.packets.NetTimedActionPacket`、`zombie.core.NetTimedAction` |
| 本仓库相关文档 | `docs/pz-b42-nested-container-multiplayer-fix.md`（根因/字节码证据）、`docs/pz-b42-nested-container-take.md`、`docs/pz-b42-nested-container-auto-unpack.md` |
