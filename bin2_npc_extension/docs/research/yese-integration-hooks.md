# YeseMarket（3735641567）扩展挂接点逆向分析

- **被测模组根** `Y = ~/Library/Application Support/Steam/steamapps/workshop/content/108600/3735641567/mods/YeseMarket/42`
- **对照模组根** `O = ~/Library/Application Support/Steam/steamapps/workshop/content/108600/3777900792/mods/OrangeTradingMod/42`
- 本文所有路径：YeseMarket 的相对于 `Y`，橙子的相对于 `O`（已显式标注）。
- 全文 **只读分析**，未修改任何被测文件。行号来自 86 个 Lua 文件的实际内容。

---

## 结论速览

| 能力 | 入口（file:line） | 评级 | 降级方案 |
|---|---|---|---|
| 页面注册/查询 | `media/lua/client/ui/page_registry.lua:21` `Register` / `:50` `Has` / `:55` `Ids` | 【稳定接口】 | 无（唯一入口）；重复注册会 `error`，必须先 `Has` |
| 页面工厂 context | `media/lua/client/ui/shell.lua:397` `pageContext()` | 【半稳定】 | 只用 `player/shell/primitives/theme/text/store`，别碰 `modalLayer` |
| 打开窗口 | `media/lua/client/event_handlers.lua:299` `YeseMarket.Open(playerNum)` | 【稳定接口】 | 无（唯一入口）；**只接受 1 个参数** |
| 切到指定页 | `media/lua/client/ui/shell.lua:726` `shell:setPage(id)` | 【半稳定】 | `Open()` 后用 `YeseMarket.Window:setPage(id)` |
| 首页加按钮 | 无官方钩子；照抄橙子 `O/client/ui/bootstrap.lua:73` 包装 `registry.factories.index` | 【内部实现细节】 | 包装 `Registry.Create` 或直接不加入口，只走热键 |
| 侧栏导航 | `media/lua/client/ui/shell.lua:32` `local NAVIGATION` | 【不可用】 | 自建页面内 tab，或包 `setPage` 画自己的导航 |
| 热键 | 全库 **零** 按键绑定（grep 无命中） | 【无冲突】 | 自建 `Events.OnKeyStartPressed` |
| 收发包 | 发送 `client_api.lua:167` 白名单锁死；路由 `server/command_router.lua:184` 硬判 module | 【不可借用/不可扩展】 | **自带 module**：自己 Add `OnClientCommand` + `OnServerCommand` |
| 扣款 | `media/lua/server/server_runtime.lua:733` `YeseMarketServer.Pay(player, price)` | 【稳定接口】 | `AddCoins(player, -price)`（无余额校验，不推荐） |
| 余额 | `.../server_runtime.lua:646` `PlayerData(player).coins` | 【稳定接口】 | 客户端读 `YeseMarket.PlayerData(player).coins`（只读缓存） |
| 流水/账目 | `media/lua/server/economy_service.lua:384` `RecordPlayerFlow(...)` | 【半稳定】 | 无；不写流水则玩家账单看不到雇人支出 |
| 翻译 | `media/lua/client/client_api.lua:26` `YeseMarket.Text(key, ...)` | 【稳定接口】 | 自建 `getText` 直接查 `IGUI_Bin2_*` |

---

## 1. 命名空间与加载顺序

两张全局表都在 **shared** 层创建，早于 client/server：

- `YeseMarket` 首次创建于 `media/lua/shared/protocol.lua:1`（`YeseMarket = YeseMarket or {}`），随后 `media/lua/shared/settings.lua:1`、`media/lua/shared/catalog.lua:3` 等继续补字段。
- `YeseMarketServer` 首次创建于 `media/lua/server/server_settings.lua:4`，并在这里把 shared 常量整体别名过来：

```lua
-- media/lua/server/server_settings.lua:4-11
YeseMarketServer = YeseMarketServer or {}
if YeseMarketServer.ConfigLoaded then return end
YeseMarketServer.ConfigLoaded = true
YeseMarketServer.Const = YeseMarket.Const
YeseMarketServer.SeasonFactors = YeseMarket.SeasonFactors
```

- **版本号常量**：`YeseMarket.Version = 1`（`media/lua/shared/settings.lua:8`）。它被写进每个存档桶：`media/lua/server/server_runtime.lua:337`、`:663`、`:688`。
- **协议常量**：`YeseMarket.Protocol.Module = "YeseMarket"`（`media/lua/shared/protocol.lua:8`），C2S 表 87 项（`:9-96`），S2C 表 22 项（`:97-120`）。
- **加载顺序**：`media/lua/client/ui/bootstrap.lua:1-30` 是 UI 的显式 require 清单（theme→layout→primitives→page_registry→store→actions→modal_layer→shell→各 pages）。`media/lua/client/event_handlers.lua:1-14` 是客户端总入口。服务端总入口是 `media/lua/server/command_router.lua:4-25`。
- **没有单一的 `ready/initialized` 标志位**，而是每个文件一个 `XxxLoaded` 幂等布尔：`settings.lua:2` `ConfigLoaded`、`protocol.lua:2` `ProtocolLoaded`、`page_registry.lua:2` `UIPageRegistryLoaded`、`shell.lua:13` `UIShellLoaded`、`command_router.lua:27` `EventsLoaded`。
- **B42 重要事实**：服务端 Lua 在联机客户端上也会加载。`media/lua/server/command_router.lua:1-2` 开头就防了：

```lua
-- media/lua/server/command_router.lua:1-2
-- B42 also loads server Lua on MP clients; do not register server timers there.
if isClient and isClient() then return end
```

所以 `YeseMarketServer` 在 MP 客户端上可能存在但为空桶——`server_runtime.lua:231` 明确 `if isClient and isClient() then return {} end`。**不要假设客户端能读到真实余额。**

---

## 2. 客户端 UI 扩展点

### 2.1 `UIPageRegistry` 的确切实现

```lua
-- media/lua/client/ui/page_registry.lua:21-34
function Registry.Register(pageId, factory)
    local id = normalizedId(pageId)
    if not id then error("page id is required") end
    if type(factory) ~= "function" then
        error("page factory must be a function: " .. id)
    end
    if Registry.factories[id] ~= nil then
        error("duplicate page id already registered: " .. id)   -- 重复注册 = 抛错
    end
    Registry.factories[id] = factory
    table.insert(Registry.order, id)
end
```

- `Create(pageId, context)`（`:36-48`）：查工厂→`factory(context)`→工厂返回 nil 则返回 `nil, err`；成功则**强行写 `page.pageId = id`**（`:46`）并返回 `page, nil`。
- `Has(pageId)`（`:50-53`）：纯查表。
- `Ids()`（`:55-61`）：按注册顺序返回数组副本。
- **重复注册行为 = `error()`**，不是 warnings。所以必须 `if not registry.Has(ID) then registry.Register(...) end`。注意 `pcall` 外面不用包 `Has`，但 `Register` 建议 `pcall`（Kahlua 的 `error` 会向上抛）。
- 文件级幂等靠 `Registry` 持久挂在 `YeseMarket.UIPageRegistry`（`:11`），并被 `Loaded` 标志保护（`:2-5`）。

### 2.2 页面工厂收到的 `context` 字段

```lua
-- media/lua/client/ui/shell.lua:397-408
function YeseMarket.UIShell:pageContext()
    return {
        player = self.player, shell = self, store = Store, actions = Actions,
        theme = Theme, primitives = Primitives, modalLayer = ModalLayer,
        text = localized,
    }
end
```

`text` 是 `localized`（`shell.lua:135-140`），内部就是 `YeseMarket.Text`。
**没有** `setPage`、没有 `open`、没有 `network`。要切页只能 `context.shell:setPage(id)`。

### 2.3 页面对象契约：shell 在哪里调用什么

shell 是 `ISPanel` 派生（`shell.lua:322`），页面作为子控件被 `addChild`（`:780`）。

| 回调 | 调用点 | 说明 |
|---|---|---|
| `relayout(rect)` | `shell.lua:786`（切页前）、`:963`（shell 自身 relayout 时） | `rect = self.ymLayout.content`；**在 activate 之前**调用 |
| `activate(params)` | `shell.lua:808`；同页重入走 `:679` | 无 `params` 时 `params = {}`（`:808`） |
| `deactivate()` | `shell.lua:800`（切走）、`:1002`（关闭窗口） | |
| `refresh(domains)` | `shell.lua:835`；`activateSamePage` 里 `refresh({full=true})`（`:689`） | `domains` 形如 `{full=true}` 或 `{player=true}` |
| `destroy()` | `shell.lua:1004-1011`（close 时对 `pageRoots` 全量）、`:715`（创建失败时） | 之后还会调 `clearChildren()` |
| `render()` | 无显式调用——`ISPanel` 子控件机制自动渲染 | 不要指望 shell 帮你调 |

失败保护很完整：`pcall` 包住工厂（`:762-771`）、`relayout`（`:785-794`）、`activate`（`:806-820`），任一失败都会 `showPageError` + 回滚到上一页（`:696-709`）。

### 2.4 页面 id **不会**自动进侧栏

```lua
-- media/lua/client/ui/shell.lua:32-54（节选）
local NAVIGATION = {
    { id = "index", key = "NavHome", group = "NavGroup_Overview", icon = "nav_home.png" },
    ...
    { id = "accountManage", key = "NavAccountManagement", icon = "nav_account_manage.png", admin = true },
}
```

`NAVIGATION` 是 **文件级 local 表**，侧栏按钮在 `:564-596` 一次性按它构建：

```lua
-- media/lua/client/ui/shell.lua:587-595（节选）
local button = Primitives.CreateButton(0, 0, 1, 1, localized(metadata.key), self, onNavigate, "muted")
button.pageId = metadata.id
button.ymNavId = metadata.id
...
viewport:addChild(button)
self.navButtons[metadata.id] = button
```

结论：**外部无法往侧栏加项**（无 `RegisterNavigation`、也没有 `TABS` 可变表）。`setPage` 对未登记 id 是放行的——`navigationEnabled(id)` 默认返回 `true`（`:132`），`navigationMetadata(id)` 返回 nil 就跳过 admin 校验（`:744-748`）。所以页能开，只是**侧栏没有入口、也不会有高亮**（`updateNavigationSelection` 遍历的是 NAVIGATION，`:643-650`）。

### 2.5 `YeseMarket.Open` 的完整签名 —— 只有一个参数

```lua
-- media/lua/client/event_handlers.lua:299-302
function YeseMarket.Open(playerNum)
    playerNum = normalizePlayerNum(playerNum)
    local player = getSpecificPlayer(playerNum or 0)
    if not player then return end
```

- **`Open(playerNum)` 只接受 1 个参数，函数没有 `return`（返回 nil）。**
- **不支持"直接打开某个 pageId"**。窗口创建后（`:348-350`）延迟到下一 tick 才发 `RequestState`（`:357`），首页由 `completeInitialOpen` 强制设为 `"index"`：

```lua
-- media/lua/client/ui/shell.lua:972-980
function YeseMarket.UIShell:completeInitialOpen()
    self.initialStateReady = true
    self:refreshNavigationVisibility()
    if self.activePageId == nil or not navigationEnabled(self.activePageId) then
        self:setPage("index")
    else
        self:refresh({ full = true })
    end
end
```

切页函数就是 `shell:setPage(pageId, params)`（`shell.lua:726`）。

**打开我们自己页面的最小调用（推荐写法）：**

```lua
-- 先开窗口，再立刻切页；因为 setPage 会写 self.activePageId，
-- 后续 completeInitialOpen 判定 activePageId ~= nil 就只 refresh，不会把我们踢回 index。
YeseMarket.Open(0)
local window = YeseMarket.Window          -- event_handlers.lua:348 已同步创建
if window and window.setPage then
    window:setPage("bin2NpcRecruit")      -- shell.lua:726
end
```

### 2.6 首页入口按钮的先例

YeseMarket **自己没有**"给首页加按钮"的代码。真正的先例在橙子：

```lua
-- O/client/ui/bootstrap.lua:64-77（节选）
local function installCommunityCenterHomeEntry()
    local registry = OrangeTradingMod.UIPageRegistry
    if OrangeTradingMod.CommunityCenterHomeEntryInstalled or not registry
            or type(registry.factories) ~= "table" then return end
    local homePageId = type(registry.factories.index) == "function" and "index"
        or type(registry.factories.home) == "function" and "home" or nil
    local originalFactory = homePageId and registry.factories[homePageId] or nil
    if type(originalFactory) ~= "function" then return end
    OrangeTradingMod.CommunityCenterHomeEntryInstalled = true
    registry.factories[homePageId] = function(context)
        local page = originalFactory(context)
        ...
        local button = primitives.CreateButton(0, 0, 140, 30, ..., page, callback, "action")
        button:initialise(); button:instantiate(); page:addChild(button)
```

**这个手法在 YeseMarket 上完全等价可用**，因为 `shell:setPage` 每次切页都重新查工厂（`shell.lua:763` `Registry.Create(id, self:pageContext())`），而不是缓存工厂引用。

⚠️ **橙子的锚点不能照抄**：橙子首页有 `page.homeViewButtons.classic/launcher`（`O/client/ui/pages/home.lua:727-736`）和 `page.communityCenterButton`；YeseMarket 首页的 `controls` 只有 `hero / summaryCards / onlineClaimButton / recentFlow(Card) / marketStatus / pendingClaims / pendingList / claimAllPending`（`media/lua/client/ui/pages/home.lua:863-887`），**没有 `homeViewButtons`、没有 `communityCenterButton`**。我们的按钮定位必须退回贴边或参照 `summaryCards[1]`。

### 2.7 按键绑定：全库为零

对 `Y` 全库 grep `OnKeyStartPressed|OnKeyPressed|OnCustomUIKey|addKeyBinding|Keyboard.KEY|OnKeyKeepPressed` → **零命中**。
唯一相关的是对话层消费 ESC（`YeseMarket` 里没有；橙子在 `O/client/ui/primitives.lua:414`）。
**结论：Ctrl+Alt+N 不会与 YeseMarket 冲突，自行注册 `Events.OnKeyStartPressed` 即可。**

---

## 3. 协议与命令

### 3.1 客户端发送：带白名单，且不可扩展

```lua
-- media/lua/client/client_api.lua:167-185
function YeseMarket.SendMarketCommand(command, args)
    if type(command) ~= "string" or command == "" then return false end
    if not commandLookup()[command] then return false end       -- 白名单
    if YeseMarket.IsSinglePlayer and YeseMarket.IsSinglePlayer() then
        if YeseMarket.DispatchSinglePlayerCommand then
            return YeseMarket.DispatchSinglePlayerCommand(command, args or {})
        end
        return false
    end
    if sendClientCommand then
        sendClientCommand(P.Module or "YeseMarket", command, args or {})
        return true
    end
    return false
end
```

白名单来自 `media/lua/client/client_api.lua:13-24` `commandLookup()`——把 `Protocol.C2S` 的所有值塞进 `C2SLookup`。`media/lua/client/ui/actions.lua:13-22` 又做了第二层 `isKnownCommand` 校验。
**module 名硬编码为 `"YeseMarket"`：借它的通道发不出我们自己的命令。必须自带 module。**

### 3.2 服务端路由：硬拒非本 module，无可注册路由表

```lua
-- media/lua/server/command_router.lua:183-190
local function onClientCommand(module, command, player, args)
    if module ~= (P.Module or "YeseMarket")
            or type(command) ~= "string"
            or command == ""
            or not YeseMarketServer.IsPlayerObject(player) then
        return
    end
```

`handlers` 表是 `local`（`:87`），没有 `RegisterHandler` 之类的公开接口。注册点是 `command_router.lua:346` `Events.OnClientCommand.Add(onClientCommand)`。
**结论：我们自己 `Events.OnClientCommand.Add` 一个独立处理器，module 用自己的名字，两者互不干扰**（对方第一个 `if` 就把我们的包 return 掉了）。

### 3.3 单机分发

`media/lua/client/single_player_bridge.lua` 提供两条路：

- `YeseMarket.IsSinglePlayer()`（`:17-19`）＝ `not isClient()`
- `YeseMarket.DispatchSinglePlayerCommand(command, args)`（`:222-266`）：先查 `multiplayerOnlyCommands` 黑名单（`:149-164`），再查 `commandHandlers[command]`（`:237-241`），只认它自己那张表 → **我们的命令会 `return false`**。
- 单机下它的服务端是**同进程真跑**：`:21-68` `loadServerModules()` 逐个 `require "server_runtime"` 等服务端文件，并伪造 `YeseMarketServer.SendToPlayer`（`:60-64`）把回包直接转给 `YeseMarket.HandleServerCommand`。
- 回包：`media/lua/client/event_handlers.lua:1061-1066` `onServerCommand` 同样先判 module 再 return。

### 3.4 「我们自己 module 收发包」最小骨架

```lua
-- ============ shared: 协议常量 ============
Bin2NPCNet = Bin2NPCNet or {}
Bin2NPCNet.MODULE = "Bin2NPCExtensionYese"   -- 必须等于 mod.info 的 id
Bin2NPCNet.C2S = { Hire = "Hire", PayWage = "PayWage" }
Bin2NPCNet.S2C = { State = "State" }

-- ============ client: 发送 ============
function Bin2NPCNet.send(command, args)
    args = type(args) == "table" and args or {}
    args.requestId = tostring(args.requestId or (getTimestampMs and getTimestampMs() or 0))
    if isClient and isClient() then
        sendClientCommand(Bin2NPCNet.MODULE, command, args)
        return true
    end
    -- 单机：服务端 Lua 同进程已加载，直接调用（与 YeseMarket 的 SP 桥同思路）
    local service = rawget(_G, "Bin2NPCService")
    if service and service.dispatch then
        service.dispatch(getSpecificPlayer(0), command, args)
        return true
    end
    return false
end

-- ============ client: 收包（与 YeseMarket 的 OnServerCommand 互不干扰）============
local function onServerCommand(module, command, args)
    if module ~= Bin2NPCNet.MODULE then return end     -- 关键：不抢别人的包
    Bin2NPCNet.apply(command, args)
end
Events.OnServerCommand.Add(onServerCommand)

-- ============ server: 路由 ============
local function onClientCommand(module, command, player, args)
    if module ~= Bin2NPCNet.MODULE then return end     -- 关键：不抢 YeseMarket 的包
    if not player then return end
    -- 自己重算权威值 + requestId 去重，永不采信客户端金额
    Bin2NPCService.dispatch(player, command, type(args) == "table" and args or {})
end
Events.OnClientCommand.Add(onClientCommand)
```

---

## 4. 货币

```lua
-- media/lua/server/server_runtime.lua:722-731
function YeseMarketServer.AddCoins(player, amount)
    if not YeseMarketServer.IsPlayerObject(player) then return 0 end
    amount = YeseMarketServer.SafeInt(amount, 0, -MAX_COMMAND_NUMBER, MAX_COMMAND_NUMBER)
    local data = YeseMarketServer.PlayerData(player)
    data.coins = YeseMarketServer.ClampCoins((data.coins or 0) + amount)
    YeseMarketServer.Transmit(YeseMarketServer.PlayerKey(player))
    return data.coins            -- 返回【扣/加后的新余额】
end

-- media/lua/server/server_runtime.lua:733-747
function YeseMarketServer.Pay(player, price)
    if not YeseMarketServer.IsPlayerObject(player) then return false end
    price = YeseMarketServer.SafeInt(price, 0, nil, MAX_COMMAND_NUMBER)
    if price <= 0 then return false end              -- price<=0 也返回 false
    local data = YeseMarketServer.PlayerData(player)
    if (data.coins or 0) < price then return false end  -- 先查
    YeseMarketServer.AddCoins(player, -price)           -- 后扣
    return true                                          -- 布尔，不返回余额
end
```

- **`Pay` 返回值语义：`true` = 已扣；`false` = 非玩家 / price≤0 / 余额不足。三种失败不可区分。**
- **是"先查后扣"，非原子**：查询与扣款之间没有锁。单线程 Lua 下实际安全，但**同一 tick 内不要对同一玩家连续调两次 `Pay` 再合并判断**——第二次会基于更新后的余额正确判定，这条是安全的。
- 余额字段名：**`data.coins`**（`server_runtime.lua:667`；客户端镜像 `client/client_api.lua:106`）。
- 上限 `MAX_ACCOUNT_BALANCE = 2147483647`（`server_runtime.lua:11-14`），`ClampCoins` 在 `:59-61`。整数货币，**没有小数**（橙子有 `COIN_SCALE = 100`，见 §9）。
- 客户端只读镜像：`YeseMarket.PlayerData(player).coins`（`client/client_api.lua:104-165`），由 `S2C.PlayerState` 推送（`media/lua/client/event_handlers.lua:856-917`，`:860` 写 `pdata.coins`）。服务端载荷构造在 `media/lua/server/state_sync.lua:1426-1447`（`coins = pdata.coins or 0`）。

### 4.1 流水/账目函数：**有**

```lua
-- media/lua/server/economy_service.lua:384-389
function YeseMarketServer.RecordPlayerFlow(player, direction, kind, itemType, amount, coins, extra)
    if not player then return end
    return YeseMarketServer.RecordPlayerFlowByKey(YeseMarketServer.PlayerKey(player), direction, kind, itemType, amount, coins, extra)
end
```

`RecordPlayerFlowByKey(playerKey, direction, kind, itemType, amount, coins, extra)`（`:331-382`）行为：

- `direction`：`"in"` / `"out"`（其它值归一为 `"out"`，`:340`）。
- `kind`：自由字符串，用于前端查 `IndexFlow_<kind>_<direction>` 翻译键（见 `media/lua/client/ui/pages/home.lua:332-338`）。
- `extra` 可含：`peer / label / labelKey / cash / items / logItem / allowFractionalAmount`（`:351-355`、`:190`）。
- 副作用：累加 `data.flowIncome` / `data.flowExpense`（`:372-376`）→ 前插 `data.accountFlowLedger`（`:378`）→ `WriteTransactionLog`（`:379`，logger 名 `"yesemarket-transactions"`，`economy_service.lua:10`）→ `Transmit(playerKey)`（`:380`）。

**雇人支出 / 退款就该用它：**

```lua
YeseMarketServer.RecordPlayerFlow(player, "out", "npc_hire", "FlowHire", 1, price, { labelKey = "FlowHire" })
YeseMarketServer.RecordPlayerFlow(player, "in",  "npc_hire_refund", "FlowRefund", 1, price, { labelKey = "FlowRefund" })
```

实参形状可直接照抄既有调用：`media/lua/server/furniture_service.lua:358-359`、`media/lua/server/animal_service.lua:584-585`、`media/lua/server/trade_service.lua:1740-1741`。
账目保留上限：`accountFlowLedger` 由 `compactAccountFlowLedger`（`economy_service.lua:269-299`）在有 `FLOW_ITEM_DETAIL_MAX_ENTRIES = 100` 的明细上限下裁剪；下发给客户端只取前 10 条（`media/lua/server/state_sync.lua:1390`）。
前端渲染：`media/lua/client/ui/pages/home.lua:304-338`（`flowRows` + `flowTypeText` + `flowDetailText`）。

---

## 5. 权限与限速

**管理员判定（客户端）**：

```lua
-- media/lua/client/client_api.lua:528-541
function YeseMarket.IsAdmin(player)
    if YeseMarket.IsSinglePlayer and YeseMarket.IsSinglePlayer() then return true end
    ...
    return accessLevel == "admin" or accessLevel == "moderator" or accessLevel == "overseer"
end
```

- `YeseMarket.CanEditAdminPrices(player)`（`:543-555`）：仅 `admin`，单机恒 true。
- `YeseMarket.IsFullAdmin(player)`（`:557-559`）＝ `CanEditAdminPrices`。
- 服务端同名版本：`media/lua/server/server_runtime.lua:1240-1253`（`IsAdmin`）、`:1255-1267`（`IsFullAdmin`）。**服务端 `IsFullAdmin` 单机也恒 true**（`:1256-1258`）。

**限速：有，但只在服务端命令入口，且是全局固定值。**

```lua
-- media/lua/server/command_router.lua:178-212（节选）
local COMMAND_MIN_INTERVAL_MS = 200
local REQUEST_STATE_MIN_INTERVAL_MS = 1000
local lastCommandAt = {}
...
    local lastAt = lastCommandAt[bucketKey]
    if lastAt and nowMs - lastAt < minInterval then
        return                                   -- 静默丢弃，不回复
    end
    lastCommandAt[bucketKey] = nowMs
```

- 按键 = `PlayerKey(player)`（`:193`），部分命令再拼后缀（`:201-206`）。
- **没有 `requestId` 幂等键、没有每命令策略表**。`requestId` 只在少数子服务里出现：`media/lua/server/safehouse_service.lua:807-815`、`media/lua/server/catalog_transfer.lua:454-458`、`media/lua/server/animal_catalog_transfer.lua:286-290`。
- **结论：我们自己的命令必须自带 `requestId` 去重 + 自己的节流**（可参考橙子 `O/server/action_request_guard.lua:7-70`，它才有 `policies` 表 + `history.seen[id]` + `lastAcceptedAt`）。

---

## 6. 翻译

- 目录：`media/lua/shared/Translate/{CN,EN}/{IG_UI.json, ItemName.json, Sandbox.json, Tooltip.json}`。
- 键前缀：**`IGUI_YeseMarket_*`**（`media/lua/shared/Translate/CN/IG_UI.json:2` `"IGUI_YeseMarket_Title"`）；沙盒键前缀 **`Sandbox_YeseMarket_*`**（`.../CN/Sandbox.json:2`）；物品用 `ItemName_YeseMarket.*` + 裸 FullType 双写（`.../CN/ItemName.json:2-3`）。

`YeseMarket.Text` **确实强制加前缀**，且是"已加则不重复加"：

```lua
-- media/lua/client/client_api.lua:26-40
function YeseMarket.Text(key, ...)
    local fullKey = tostring(key or "")
    if string.sub(fullKey, 1, 16) ~= "IGUI_YeseMarket_" then   -- "IGUI_YeseMarket_" 正好 16 字符
        fullKey = "IGUI_YeseMarket_" .. fullKey
    end
    local value = fullKey
    if getText then
        local ok, translated = pcall(getText, fullKey, ...)
        if ok and translated and translated ~= "" then value = translated end
    end
    return value        -- 查不到就返回裸键，不做短名回退
end
```

注意：**失败时返回的是 `IGUI_YeseMarket_xxx` 全键**（不像橙子会回退到短名）。所以 `home.lua:324-330` 专门写了 `resolvedText` 来判"键还是译文"。

---

## 7. 沙盒/配置

- 有 `media/sandbox-options.txt`（947 行），`VERSION = 1,`（`:1`），每项 `page = YeseMarket,`（`:7`），选项名形如 `option YeseMarket.MoneyPerCoin`（`:11`）。
- 读取方式：**没有 `YeseMarket.opt`**。走 `media/lua/shared/settings.lua:424-437`：

```lua
-- media/lua/shared/settings.lua:424-437
local function sandboxOptionValue(optionName)
    if not SandboxVars then return nil end
    local modOptions = SandboxVars.YeseMarket          -- 表名 = "YeseMarket"
    if type(modOptions) == "table" and modOptions[optionName] ~= nil then
        return modOptions[optionName]
    end
    local dottedKey = "YeseMarket." .. tostring(optionName or "")
    if SandboxVars[dottedKey] ~= nil then return SandboxVars[dottedKey] end
    return nil
end
```

- 选项定义表：`YeseMarket.SandboxOptionDefs`（`settings.lua:316-408`），每项 `{ option, key, kind, default, min, max }`。
- 生效入口：`YeseMarket.ApplySandboxOptions()`（`settings.lua:555-574`），文件末尾自动跑一次（`:702`）；服务端 `command_router.lua:253-255` 在 `OnServerStarted` 再跑一次；客户端在右键菜单里按需刷新（`client/event_handlers.lua:257-259`）。
- 我们的 mod 有自己的 `page = Bin2NPCExtensionYese`（若要加沙盒项）。**不要往 `SandboxVars.YeseMarket` 里塞自己的键**——它的 `ApplySandboxOptions` 会按 `SandboxOptionDefs` 逐项覆盖 `YeseMarket.Const`，但不会清除未知键，混用会造成"看起来生效其实被忽略"。

---

## 8. 持久化

**这是它做得最严的一块。** TAG 前缀清单（`media/lua/shared/settings.lua:131-145`）：

| 常量 | TAG 值 |
|---|---|
| `ECONOMY_KEY` | `economy` |
| `STATS_KEY` | `YeseMarketStats` |
| `TRADE_KEY` | `YeseMarketTrades` |
| `BUY_ORDER_KEY` | `YeseMarketBuyOrders` |
| `VEHICLE_POOL_KEY` | `YeseMarketVehiclePool` |
| `ADMIN_PRICE_OVERRIDES_KEY` | `YeseMarketAdminPriceOverrides` |
| `ANIMAL_CATALOG_KEY` | `YeseMarketAnimalCatalog` |
| `FURNITURE_CATALOG_KEY` | `YeseMarketFurnitureCatalog` |
| `MANAGED_CATALOG_KEY` | `managed_catalog` |
| `MANAGED_STOCK_KEY` | `YeseMarketManagedStock` |
| `LOTTERY_KEY` | `YeseMarketLottery` |
| `AUCTION_KEY` | `YeseMarketAuctions` |
| `PLAYER_INDEX_KEY` | `YeseMarketPlayerIndex` |
| `PLAYER_KEY_PREFIX` | `YeseMarketPlayer_`（每玩家，后缀 = 玩家名，`server_runtime.lua:213-215`） |
| `ANNOUNCEMENT_KEY` | `YeseMarketAnnouncement` |
| （兼容残留） | `YeseMarketPrivateStorage`（`server_runtime.lua:153-173`，只读迁移） |

机制：

- **权威桶白名单**：`server_runtime.lua:100-122` `IsAuthoritativeDataKey(key)` → 玩家前缀 + 上表所有键。
- **预载**：`PreloadAuthoritativeBuckets()`（`:137-178`）用 `ModData.getTableNames()` 扫全表，命中的搬进 `AuthoritativeBuckets` 内存表；`DataBucket`（`:225-243`）优先读内存。
- **写同步**：`Transmit(key)`（`:265-277`）——**只有非权威键才走 `ModData.transmit`**（`:274`）；权威键靠 `sendServerCommand` 全量下发。批量：`BeginTransmitBatch`（`:279`）/`FlushPendingTransmitKeys`（`:283`）/`EndTransmitBatch`（`:301`）。
- **显式落盘**：`PersistBucket`（`:245`）/`PersistAllBuckets`（`:259`），在 `OnSave`（`command_router.lua:305-307`）与 `OnInitGlobalModData`（`:291-295`）调用。
- **反外部篡改**：`OnReceiveGlobalModData` 对权威键直接忽略并打日志（`command_router.lua:309-315`）。

**给我们自己的数据选 TAG（建议，全部避开上表）：**

```lua
-- 每玩家合约：Bin2NPCExtensionYesePlayer_<玩家名>
-- 世界级桶：  Bin2NPCExtensionYeseContracts
-- 使用 ModData.getOrCreate(TAG) / ModData.transmit(TAG)，不要走它的 DataBucket
```

理由：`YeseMarketServer.DataBucket` 对非权威键会 fallback 到 `modDataBucket`（`:242`），能用；但**不要用**——`PreloadAuthoritativeBuckets` 会在同一张 `ModData` 命名空间里跟我们的桶混在一起扫，且将来它扩白名单时可能误吞我们的键。自己直连 `ModData` 最干净。

---

## 9. 与橙子社区经济的关系

### 9.1 是不是同源分支？**是，但橙子是"上游/更早的形态"，且**全局命名空间完全不同**。**

关键证据：

1. **命名空间根不是 `OrangeCommunityEconomy`，而是 `OrangeTradingMod`。** `mod.info` 的 `id=OrangeCommunityEconomy`（`O/mod.info:2`），但所有 Lua 全局都是 `OrangeTradingMod`（`O/client/client_api.lua:4-8`、`O/client/ui/page_registry.lua:1`）。
2. 同理 module 名：`O/shared/protocol.lua:9` `Module = "OrangeTradingMod"`，而 YeseMarket 是 `"YeseMarket"`（`shared/protocol.lua:8`）。
3. 目录形态高度同构：`client/client_api.lua`、`client/single_player_bridge.lua`、`client/ui/page_registry.lua`、`client/ui/bootstrap.lua`、`server/{command_router,server_runtime,economy_service,state_sync}.lua`、`ui/pages/home.lua` 等一一对应（shell 从 `client/ui/shell.lua` 挪到了 `client/ui/workbench/shell_window.lua`）。
4. `page_registry.lua` 是同一份代码的两种措辞——同样的 `factories/order/Register/Create/Has/Ids` 五件套，只是错误信息文案不同：

| | YeseMarket | Orange |
|---|---|---|
| `Register` 幂等标志 | `YeseMarket.UIPageRegistryLoaded`（`:2-5`，早退 `return`） | `OrangeTradingMod.UIPageRegistryLoaded`（`:4-6`，早退 `return existing`） |
| 重复注册 | `error("duplicate page id already registered: "..id)`（`:30`） | `registrationError(..., 3)`（`:38`，带 level 3） |
| `Create` 失败返回 | `nil, "unknown page id not registered: "..id`（`:40`） | `nil, "Orange Trading page is unavailable: "..key`（`:49`） |
| `Create` 成功返回 | `page, nil`（`:47`） | `page`（`:57`，**单值**） |
| `page.pageId` | 由 `Create` 写（`:46`） | 由 `Create` 写（`:56`） |

**判定：YeseMarket 是橙子的重构/分支（同作者 LUA 风格、同目录树、同 API 形状），但作者做了破坏性改名与若干修复。**

### 9.2 「与橙子社区经济的 API 差异表」

左列 = `OrangeTradingMod.*`，右列 = YeseMarket 等价调用。

| OrangeCommunityEconomy（全局名 `OrangeTradingMod`） | YeseMarket 等价 | 备注 |
|---|---|---|
| `OrangeTradingMod.Text(key, ...)`（`O/client/client_api.lua:138`） | `YeseMarket.Text(key, ...)`（`Y/media/lua/client/client_api.lua:26`） | 前缀不同：`IGUI_OrangeTradingMod_` vs `IGUI_YeseMarket_` |
| `OrangeTradingMod.IsSinglePlayer()`（`O/client/single_player_bridge.lua:17`） | `YeseMarket.IsSinglePlayer()`（`Y/.../single_player_bridge.lua:17`） | **签名完全一致** |
| `OrangeTradingMod.Open(number, targetPage)`（`O/client/event_handlers.lua:710`） | `YeseMarket.Open(playerNum)`（`Y/.../event_handlers.lua:299`） | ⚠️ **YeseMarket 少了 `targetPage` 且不 return 窗口** |
| `Shell.completeInitialOpen(targetPage)`（`O/.../workbench/shell_window.lua:714`） | `UIShell:completeInitialOpen()`（`Y/.../shell.lua:972`） | ⚠️ **YeseMarket 无参数，且硬编码 `setPage("index")`** |
| `Shell:setPage(rawId, params)`（`O/.../shell_window.lua:497`） | `UIShell:setPage(pageId, params)`（`Y/.../shell.lua:726`） | 同名同义，参数语义相同 |
| `OrangeTradingMod.UIPageRegistry.Register/Has/Create/Ids`（`O/client/ui/page_registry.lua:29/60/45/65`） | 同名同义（`Y/.../page_registry.lua:21/50/36/55`） | `Create` 成功返回值个数不同（1 vs 2） |
| `OrangeTradingMod.SendMarketCommand(cmd, args)`（`O/client/client_api.lua:325`） | `YeseMarket.SendMarketCommand(cmd, args)`（`Y/.../client_api.lua:167`） | 白名单机制相同，module 名不同 |
| `OrangeTradingMod.DispatchSinglePlayerCommand(cmd,args)`（`O/.../single_player_bridge.lua:255`） | `YeseMarket.DispatchSinglePlayerCommand(cmd,args)`（`Y/.../single_player_bridge.lua:222`） | YeseMarket 用 `handlers` 闭包表；橙子用 `LOCAL_COMMAND_METHODS` 名单 |
| `OrangeTradingModServer.PlayerData(player).coins`（`O/server/runtime_core.lua:450`） | `YeseMarketServer.PlayerData(player).coins`（`Y/server/server_runtime.lua:646`） | ✅ **字段名一致：`coins`** |
| `OrangeTradingModServer.Pay(player, amount)`（`O/server/runtime_core.lua:510`） | `YeseMarketServer.Pay(player, price)`（`Y/server/server_runtime.lua:733`） | ⚠️ **完全相同**（见下） |
| `OrangeTradingModServer.AddCoins(player, amount)`（`O/server/runtime_core.lua:502`） | `YeseMarketServer.AddCoins(player, amount)`（`Y/server/server_runtime.lua:722`） | ✅ **完全相同** |
| `OrangeTradingModServer.IsAdmin / IsFullAdmin`（`O/server/runtime_core.lua`） | `YeseMarketServer.IsAdmin / IsFullAdmin`（`Y/server/server_runtime.lua:1240 / :1255`） | 语义一致 |
| `OrangeTradingMod.RecordPlayerFlow` | `YeseMarketServer.RecordPlayerFlow(player, direction, kind, itemType, amount, coins, extra)`（`Y/.../economy_service.lua:384`） | ✅ 存在；橙子同名函数在 `O/server/` |
| 橙子 `requestId` + `action_request_guard.lua` 去重（`O/server/action_request_guard.lua:50`） | **无** | ⚠️ YeseMarket 只有 200ms 全局节流（`command_router.lua:178-212`） |
| 橙子 `COIN_SCALE = 100`（小数货币，`O/server/runtime_core.lua:7`） | **无** | ⚠️ YeseMarket 整数货币 |
| 橙子 `page.homeViewButtons` / `communityCenterButton`（`O/client/ui/pages/home.lua:727`） | **无** | ⚠️ YeseMarket 首页没有这两个锚点 |

**`Pay` 的确切差异（唯一有实质区别的签名）：**

```lua
-- O/server/runtime_core.lua:510-517
function server.Pay(player, amount)
    local charge = server.CeilCoins(server.SafeNumber(amount, 0, 0, server.MAX_COMMAND_NUMBER))
    if not server.IsPlayerObject(player) or charge <= 0 then return false end
    local data = server.PlayerData(player)
    if not server.SpendAccountBalance(data, charge) then return false end
    server.Transmit(server.PlayerKey(player))
    return true
end
```

对比 `Y/server/server_runtime.lua:733-747`：**返回语义、参数、结构三者完全一致。唯一区别是橙子用 `CeilCoins` 向上取整支持小数，YeseMarket 用 `SafeInt` 截断为整数。**

### 9.3 两者同时启用会不会冲突？

| 冲突面 | 结论 | 证据 |
|---|---|---|
| 全局表名 | ✅ 不冲突 | `YeseMarket`/`YeseMarketServer` vs `OrangeTradingMod`/`OrangeTradingModServer` |
| protocol module | ✅ 不冲突 | `"YeseMarket"` vs `"OrangeTradingMod"` |
| 翻译前缀 | ✅ 不冲突 | `IGUI_YeseMarket_` vs `IGUI_OrangeTradingMod_` |
| ModData TAG | ✅ 不冲突 | `YeseMarket*` vs `OrangeTradingMod*`（**唯一例外：`MANAGED_CATALOG_KEY = "managed_catalog"` 两边完全相同！** `Y/shared/settings.lua:138` / `O/shared/orange_settings.lua:44`） |
| UI 窗口单例 | ✅ 不冲突（各自 `YeseMarket.Window` / `OrangeTradingMod.Window`，是两扇独立窗口，可同时开） | `Y/.../event_handlers.lua:303`、`O/.../event_handlers.lua:713` |
| 按键绑定 | ✅ **两边都没有任何绑定** | 全库 grep 零命中 |
| `Events.OnClientCommand` | ⚠️ **各自 Add 一个 handler，靠 module 名互相 return**——无冲突但顺序敏感 | `Y/.../command_router.lua:184`、`O/.../command_router.lua:678` |
| `Events.OnServerCommand` | ⚠️ 同上 | `Y/.../event_handlers.lua:1062`、`O/.../event_handlers.lua` |
| `ISWorldObjectContextMenu.createMenu` | ⚠️ **两边都做了 wrapper！** 会叠成链式包装 | `Y/.../event_handlers.lua:444-465`（且带 `createMenuWrapper` 身份判重，能正确叠加）、橙子同类补丁 |
| 世界物品脚本/物品 | ⚠️ 都在 `media/scripts/*.txt` 新增物品，FullType 前缀不同（`YeseMarket.*`），不冲突 | `Y/media/scripts/yesemarket_items.txt` |

**结论：可以同时启用。真正的风险只有两个：**
1. **`managed_catalog` 这个 TAG 两边同名**（`Y/shared/settings.lua:138`、`O/shared/orange_settings.lua:44`）。两边都把它当权威桶读写，如果两个 mod 都开了"商品目录管理"，**会互相覆盖存档表**。这是唯一的硬冲突。
2. **`ISWorldObjectContextMenu.createMenu` 的双层 wrapper**。YeseMarket 的包装器有引用判重（`event_handlers.lua:448-450`：`if ISWorldObjectContextMenu.createMenu == createMenuWrapper then return end`）和 `pcall` 保护（`:422-438`，注释里明确处理了"第三方包装器"场景），但双层包装仍会放大每次右键的开销与失败面。**这是"能跑但别指望它快"的软冲突。**

---

## 10. 脆弱点清单与稳定性评级

### 【稳定接口】——必须用，且无更稳替代

| 接口 | 位置 | 理由 |
|---|---|---|
| `YeseMarket.UIPageRegistry.Register/Has` | `client/ui/page_registry.lua:21/50` | 明确为扩展设计；`Has` 可安全判重 |
| `YeseMarket.Open(playerNum)` | `client/event_handlers.lua:299` | 唯一官方开窗入口 |
| `YeseMarket.Text(key, ...)` | `client/client_api.lua:26` | 翻译唯一入口 |
| `YeseMarket.IsSinglePlayer()` | `client/single_player_bridge.lua:17` | 一行判定，语义稳定 |
| `YeseMarketServer.Pay(player, price)` | `server/server_runtime.lua:733` | 服务端权威扣款，**必须用**——绝不要自己改 `PlayerData().coins` |
| `YeseMarketServer.PlayerData(player).coins` | `server/server_runtime.lua:646` | 余额唯一字段名 |
| `YeseMarketServer.RecordPlayerFlow(...)` | `server/economy_service.lua:384` | 唯一账目出口 |

### 【半稳定】——可用，但建议加 `pcall` + 存在性检查 + 降级

| 接口 | 位置 | 风险 | 降级方案 |
|---|---|---|---|
| `shell:setPage(id)` | `client/ui/shell.lua:726` | 未见于扩展文档；`setPage` 内部对 `navigationEnabled`/admin 有分支 | 包 `pcall`；用 `Open()` 后再 `setPage` |
| `registry.factories[id] = wrapper` | `client/ui/page_registry.lua:8` | 直接改内部表，非公开 API | 改包 `Registry.Create`（同样内部）；或**干脆不加首页按钮**，只留热键 + 世界右键菜单 |
| `context` 字段 | `client/ui/shell.lua:397-408` | 字段集可能变 | 只读 `player/shell/primitives/theme/text`，用 `pcall` 探 `store/actions/modalLayer` |
| `page.pageId`（`Create` 写入） | `page_registry.lua:46` | 内部约定 | 自存 `self.myId = "..."` |
| `YeseMarket.PlayerData(player).coins`（客户端） | `client/client_api.lua:106` | 只是服务端推来的镜像，**可能是上一 tick 的值** | UI 只做展示；任何扣款判定都在服务端 |
| `YeseMarketServer.IsFullAdmin(player)` | `server/server_runtime.lua:1255` | 单机恒 true | 需要严格权限时自己判 `getAccessLevel` |
| `command_router` 的 200ms 节流 | `server/command_router.lua:179` | 只保护它的命令，与我们无关 | 自己实现（见 §5） |

### 【内部实现细节】——**不要碰**

| 东西 | 位置 | 为什么别碰 |
|---|---|---|
| `local NAVIGATION` | `client/ui/shell.lua:32` | 文件 local，语法上就改不到；只能靠 `setPage` |
| `local handlers` | `server/command_router.lua:87` | local，无法注册路由 |
| `YeseMarket.Const`（`shared/settings.lua:128`） | 全局可写 | **它是全局表，写它会影响全 mod**；只在极必要时读 |
| `SandboxVars.YeseMarket.*` | 运行时 | 由 `ApplySandboxOptions` 按 `SandboxOptionDefs` 覆盖；塞未知键会被静默忽略 |
| `ModData` 里 `YeseMarket*` 前缀的任何 TAG | — | 会被 `PreloadAuthoritativeBuckets` 扫入并全量下发 |
| `managed_catalog` TAG | `shared/settings.lua:138` | 与橙子同名，**最危险的一个** |
| `YeseMarket.Window.*` 内部字段（`pageRoots`/`navButtons`/`ymLayout`） | `client/ui/shell.lua:324-355` | 无兼容承诺 |

---

## 11. 新模组（YeseMarket 版）的最小接入骨架

```lua
-- client/Bin2NPCExtensionYese/Entry.lua：注册页面 + 首页入口 + 热键，全部软挂接。
local Config = Bin2NPCExtensionYese
local PAGE_ID = "bin2NpcRecruit"        -- 保证不与他人撞名

-- ---------- 1. 页面注册（幂等 + pcall）----------
local function ensurePage()
    local ui = Config.economy()                       -- 返回 rawget(_G,"YeseMarket")
    if ui == nil then return false end
    local registry = ui.UIPageRegistry                -- client/ui/page_registry.lua:11
    if type(registry) ~= "table" or type(registry.factories) ~= "table" then
        return false
    end
    if not registry.Has(PAGE_ID) then                 -- page_registry.lua:50
        local ok, err = pcall(registry.Register, PAGE_ID, Config.RecruitPage.Create)  -- :21
        if not ok then
            Config.warn("page register failed: " .. tostring(err))  -- 重复注册会 error
            return false
        end
    end
    return true
end

-- ---------- 2. 首页入口：包装 registry.factories.index ----------
-- 照抄橙子 O/client/ui/bootstrap.lua:64-114 的做法。
local function installHomeEntry()
    local registry = Config.economy().UIPageRegistry
    local homeId = type(registry.factories.index) == "function" and "index"
        or (type(registry.factories.home) == "function" and "home" or nil)
    if homeId == nil then return false end               -- home.lua 还没跑完
    if Config.HomeEntryInstalled then return true end
    Config.HomeEntryInstalled = true                     -- 只包一次

    local original = registry.factories[homeId]
    registry.factories[homeId] = function(context)       -- shell.lua:763 每次切页都查工厂
        local page = original(context)
        if page == nil or page.bin2NpcButton ~= nil then return page end
        local primitives = context.primitives
        if type(primitives) ~= "table" or type(primitives.CreateButton) ~= "function" then
            return page
        end
        local button = primitives.CreateButton(0, 0, 140, 30, Config.Text.get("EntryButton"),
            page, function(target) Config.openRecruitPage(target) end, "muted")
        button.tooltip = Config.Text.get("EntryTooltip")
        button:initialise(); button:instantiate(); page:addChild(button)
        page.bin2NpcButton = button

        local originalRelayout = page.relayout
        function page:relayout(rect)
            if originalRelayout then originalRelayout(self, rect) end
            -- YeseMarket 首页没有橙子的 homeViewButtons / communityCenterButton
            --（见 media/lua/client/ui/pages/home.lua:863-887），只能贴左边缘。
            local m = self.context.theme.Metrics
            button:setX(tonumber(m.Padding) or 12)
            button:setY(tonumber(m.Padding) or 12)
            button:setWidth(math.max(118, math.min(170, math.floor(self.width * 0.18))))
            button:setHeight(30)
        end
        return page
    end)
    return true
end

-- ---------- 3. 打开页面（YeseMarket 的 Open 只吃 1 个参数！）----------
function Config.openRecruitPage(target)
    local number = 0
    local player = target and target.context and target.context.player or nil
    if player and player.getPlayerNum then
        local ok, value = pcall(player.getPlayerNum, player)
        if ok then number = math.max(0, math.floor(tonumber(value) or 0)) end
    end
    local ui = Config.economy()
    if ui == nil then return end
    if type(ui.Open) ~= "function" then return end

    -- event_handlers.lua:299 —— 只有一个参数，没有 targetPage
    pcall(ui.Open, number)

    -- 降级方案：窗口是同步创建的（event_handlers.lua:348），随后自己切页。
    -- setPage 会写 activePageId，之后 completeInitialOpen（shell.lua:972-980）
    -- 判定 activePageId ~= nil 就只 refresh，不会把我们踢回 index。
    local window = ui.Window
    if window and type(window.setPage) == "function" then
        pcall(window.setPage, window, PAGE_ID)        -- shell.lua:726
    end
end

-- ---------- 4. 热键 Ctrl+Alt+N（YeseMarket 全库无任何按键绑定）----------
local function onKeyPressed(key)
    if type(Keyboard) ~= "table" or key ~= Keyboard.KEY_N then return end
    local ctrl, alt = false, false
    pcall(function() ctrl = isCtrlKeyDown() == true end)
    pcall(function() alt = isAltKeyDown() == true end)
    if not (ctrl and alt) then return end
    Config.openRecruitPage(nil)
end
Events.OnKeyStartPressed.Add(onKeyPressed)

-- ---------- 5. 装配（YeseMarket 可能比我们晚就绪 → 要重试）----------
function Config.install()
    if not ensurePage() then return false end
    return installHomeEntry()
end
```

```lua
-- ============================================================
-- 文件：server/Bin2NPCExtensionYese/Service.lua（节选：自己的 module 收发包 + 扣款）
-- ============================================================
local Config = Bin2NPCExtensionYese
local MODULE = "Bin2NPCExtensionYese"            -- 绝不借用 "YeseMarket"
local seenRequestId, lastAcceptedAt = {}, {}      -- 自己去重 + 自己限速

local function priceFor(command, player)          -- 服务端权威定价，永不采信客户端金额
    return Config.price and Config.price(command) or 0
end

function Config.dispatch(player, command, args)
    if type(player) ~= "table" or player.getUsername == nil then return end
    args = type(args) == "table" and args or {}

    -- 限速（YeseMarket 的 200ms 节流只保护它自己的命令）
    local now = getTimestampMs and tonumber(getTimestampMs()) or 0
    local key = tostring(player:getUsername()) .. "\31" .. tostring(command)
    if now > 0 and lastAcceptedAt[key] and now - lastAcceptedAt[key] < 250 then return end
    lastAcceptedAt[key] = now
    -- 去重（YeseMarket 没有 requestId 机制）
    local rid = tostring(args.requestId or "")
    if rid ~= "" then
        if seenRequestId[key] and seenRequestId[key][rid] then return end
        seenRequestId[key] = seenRequestId[key] or {}
        seenRequestId[key][rid] = true
    end

    if command == "Hire" then
        local server = rawget(_G, "YeseMarketServer")
        if server == nil or type(server.Pay) ~= "function" then
            return Config.reply(player, "State", { ok = false, err = "no_economy" })
        end
        local price = priceFor(command, player)         -- 服务端重算
        -- server_runtime.lua:733 —— 返回 true=已扣 / false=非玩家|price<=0|余额不足
        local ok, paid = pcall(server.Pay, player, price)
        if not ok or paid ~= true then
            return Config.reply(player, "State", { ok = false, err = "no_funds" })
        end
        -- economy_service.lua:384 —— 记一笔支出，否则玩家账单看不到这笔钱
        if server.RecordPlayerFlow then
            pcall(server.RecordPlayerFlow, player, "out", "npc_hire", "FlowHire", 1, price,
                { labelKey = "FlowHire" })
        end
        local spawned = Config.spawnNpc(player)          -- A-Life / Jeem 那一侧
        if spawned ~= true then
            -- 失败退款：必须"补钱 + 反向记流水"两件事都做
            if type(server.AddCoins) == "function" then
                pcall(server.AddCoins, player, price)     -- server_runtime.lua:722
            end
            if server.RecordPlayerFlow then
                pcall(server.RecordPlayerFlow, player, "in", "npc_hire_refund", "FlowRefund",
                    1, price, { labelKey = "FlowRefund" })
            end
            return Config.reply(player, "State", { ok = false, err = "spawn_failed" })
        end
        local coins = nil
        local dOk, data = pcall(server.PlayerData, player)   -- server_runtime.lua:646
        if dOk and type(data) == "table" then coins = tonumber(data.coins) end
        return Config.reply(player, "State", { ok = true, coins = coins })
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end        -- 不抢 YeseMarket 的包（反之亦然）
    local ok, err = pcall(Config.dispatch, player, command, args)
    if not ok then Config.warn("dispatch failed: " .. tostring(err)) end
end
Events.OnClientCommand.Add(onClientCommand)

local function onServerCommand(module, command, args)   -- 客户端侧
    if module ~= MODULE then return end
    Config.Net.apply(command, args)
end
Events.OnServerCommand.Add(onServerCommand)
```

```lua
-- ============================================================
-- 文件：shared/Bin2NPCExtensionYese/Config.lua（持久化 TAG，全部避开 YeseMarket/Orange）
-- ============================================================
Config.TAG_PLAYER  = "Bin2NPCExtensionYesePlayer_"   -- + 玩家名
Config.TAG_WORLD   = "Bin2NPCExtensionYeseContracts"
-- 用 ModData.getOrCreate(TAG) / ModData.transmit(TAG) 直连，
-- 不要走 YeseMarketServer.DataBucket（server_runtime.lua:225-243）。
```

---

## 12. 未确认 / 证据不足

**以下是我读到的代码（已确证）：** §1-§10 中所有带 `file:line` 的结论、`Pay` 的返回语义、"`Open` 只有 1 个参数且无 targetPage"、"`NAVIGATION` 是 local 且侧栏不可扩展"、"全库零按键绑定"、"`RecordPlayerFlow` 存在且带 `labelKey`"、"橙子根命名空间是 `OrangeTradingMod` 而非 `OrangeCommunityEconomy`"、"`managed_catalog` TAG 两边同名"。

**以下是推测，未经运行时验证：**

1. **"谁是上游"** —— 基于目录同构 + API 同形 + 命名空间改名推断为同源分支，但**没有 git 历史或可靠时间戳**作为方向证据。反向同样符合证据，只能说"一对分支"。
2. **"`managed_catalog` 两边会互相覆盖"** —— 只确认了 TAG 常量字符串相同，**没有逐行验证两边读写路径与数据形状是否兼容**。也可能是结构不同，那样后果是"读到对方的表 → 归一化时清空或报错"，比覆盖更糟。**上线前必须实测。**
3. **"两个 `ISWorldObjectContextMenu.createMenu` wrapper 能正确叠加"** —— 只确认 YeseMarket 侧有引用判重与 `pcall`（`event_handlers.lua:444-465`、`:422-438`）。**没有读到橙子侧对应的 wrapper 代码**（橙子目录太大，grep 超时被中止），所以"叠加失败"的风险未排除。
4. **"`Open()` 后立刻 `setPage()` 能保持住"** —— 逻辑上成立（`completeInitialOpen` 的 `activePageId ~= nil` 分支，`shell.lua:975`），但**没有实际跑过**。存在一个未验证的时序：MP 下 `S2C.SharedState` 到达时 `event_handlers.lua:964-966` 也会调 `completeInitialOpen`，若此时 `activePageId` 还没被我们的 `setPage` 写上，我们会被踢回 `index`。**降级保险**：延迟 1 个 tick（`Events.OnTick` 计数 2 次）再 `setPage`。
5. **"B42 服务端 Lua 在 MP 客户端也会加载，所以客户端能 `rawget(_G,"YeseMarketServer")`"** —— 依据是 `command_router.lua:1-2` 的注释与 `server_runtime.lua:231` 的 `if isClient then return {} end`。**我没有验证 `YeseMarketServer.Pay` 在 MP 客户端上是否可调用**；从 `server_runtime.lua:723` 的 `IsPlayerObject` 检查看，即便能调也不会有真实余额。**扣款必须走服务端。**
6. **"`SandboxVars.YeseMarket` 表名在 B42.20+ 下稳定"** —— 依据是 `shared/settings.lua:428` 与 `sandbox-options.txt:7` 的 `page = YeseMarket`。引擎版本升级可能导致表名组装方式变化（B42 有过 `SandboxVars.<page>.<option>` 与 `SandboxVars["<page>.<option>"]` 两种形态，代码里 `:432-435` 两种都兜了，说明作者也遇到过）。
7. **本仓库既有代码的两处不匹配（读代码得出，非运行时验证）：**
   - `Contents/mods/Bin2NPCExtensionYese/42.21/media/lua/client/Bin2NPCExtensionYese/ui/Entry.lua:39` 调用 `ui.Open(number, Config.RecruitPage.ID)` —— **YeseMarket 的 `Open` 忽略第 2 个参数**，此处等同于只是打开首页。
   - 同文件 `:113-118` 的定位锚点 `self.communityCenterButton` / `self.homeViewButtons` —— **YeseMarket 首页根本没有这两个字段**（对照 `media/lua/client/ui/pages/home.lua:863-887`），锚点全为 nil，实际会落到最后的兜底分支。注释里描述的"压在卡片视图按钮上"的场景在 YeseMarket 下不会发生，但按钮位置需要重新确认。
   - 另：`42.21` 版本目录名与 YeseMarket 的 `42` 不一致，`mod.info` 里 `require=\YeseMarket` 的解析路径需要实测（本次未验证引擎的版本目录匹配规则）。
