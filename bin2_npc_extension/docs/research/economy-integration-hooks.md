# 橙子社区经济（OrangeCommunityEconomy / workshop 3777900792）逆向集成报告

> 目的：为独立扩展模组 `bin2_npc_extension` 找出「往橙子经济 UI 里加一个 NPC 招募页 + 一条自己的服务端指令」的全部接入点。
>
> **只读分析**：本报告未修改 `$ECO` 下任何文件。
>
> **路径约定**：除特别注明外，所有 `相对路径:行号` 均相对于
> `$ECO/media/lua/`，例如 `client/ui/page_registry.lua:29` 表示
> `/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600/3777900792/mods/OrangeTradingMod/42/media/lua/client/ui/page_registry.lua` 第 29 行。
> 引擎级结论引用游戏自带 jar：
> `~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/projectzomboid.jar`。

---

## 结论速览

| 我们需要的能力 | 对应 file:line | 挂接方式 |
|---|---|---|
| 注册一个新页面 | `client/ui/page_registry.lua:29` (`Registry.Register(id, factory)`) | 直接调用，公开 API |
| 打开页面 | `client/event_handlers.lua:710` (`OrangeTradingMod.Open(number, pageId)`) 或 `client/ui/workbench/shell_window.lua:497` (`shell:setPage(id)`) | 直接调用 |
| 页面对象契约 | `client/ui/workbench/shell_window.lua:497-570`、`client/ui/workbench/list_page.lua:77` | 抄 `WorkbenchListPage.Create` |
| 侧边导航加一项 | `client/ui/workbench/shell_window.lua:28` (`local MENU`) | **加不进**，只能改首页按钮 / 自建入口 |
| 首页放入口按钮 | `client/ui/bootstrap.lua:64-116`（模组自己的先例） | monkey patch `registry.factories["index"]`，幂等 |
| 发一条自己的服务端指令 | `client/client_api.lua:325`（会被白名单挡）→ 改用原生 `sendClientCommand(自己模块名, ...)` | **零 patch**：用独立 module 名 |
| 服务端收包 | `server/command_router.lua:677`（`module ~= ModuleName` 就 return）+ `:1075` | 自己注册第二个 `Events.OnClientCommand` |
| 服务端路由注册 API | `server/command_router.lua:63` (`local routes`) / `:134` (`local function register`) | **不存在公开 API**，但也不需要 |
| 加钱 / 扣钱 / 查余额 | `server/runtime_core.lua:502` `AddCoins` / `:510` `Pay` / `:108` `AccountBalance` | 直接调用 |
| 社区金库 | `server/community_treasury_service.lua:466/488/530/627/1695` | 直接调用，带 requestId 幂等 |
| 单人游戏支持 | `client/single_player_bridge.lua:31,48,255` | 服务端文件在 SP 也会加载，但要自建本地分发 |
| 管理员判定 | `server/runtime_core.lua:702/707`、`client/client_api.lua:471/481` | 直接调用 |
| 存储自己的数据 | `server/runtime_core.lua:211/260` (`DataBucket`/`Transmit`) | 用自己的 ModData TAG |

---

## 1. 全局命名空间与加载顺序

### 1.1 两个全局命名空间

- 客户端 + shared：**`OrangeTradingMod`**（单表，所有子模块挂在它下面）。
  `shared/protocol.lua:1` `OrangeTradingMod = OrangeTradingMod or {}`；该写法是全部文件的统一第一行，例如
  `client/ui/page_registry.lua:1`、`client/ui/theme.lua:1`、`shared/orange_settings.lua:1`。
- 服务端：**`OrangeTradingModServer`**（在 `server/server_runtime.lua:4` 创建）。
  `server/runtime_core.lua:1` `local server = OrangeTradingModServer` 之后所有服务端函数都挂在 `server.*` 上。

**子命名空间清单**（第三方最常碰的）：

| 名字 | 定义处 |
|---|---|
| `OrangeTradingMod.UIPageRegistry` | `client/ui/page_registry.lua:11` |
| `OrangeTradingMod.UIShell` / `.UI` | `client/ui/workbench/shell_window.lua:227` / `client/ui/bootstrap.lua:117` |
| `OrangeTradingMod.UIPrimitives` | `client/ui/primitives.lua:14` |
| `OrangeTradingMod.UITheme` / `.UILayout` | `client/ui/theme.lua:3` 附近 / `client/ui/layout.lua:9` |
| `OrangeTradingMod.UIStore` / `.UIActions` / `.UIModalLayer` | `client/ui/store.lua:9` / `client/ui/actions.lua:9` / `client/ui/modal_layer.lua` |
| `OrangeTradingMod.WorkbenchListPage` | `client/ui/workbench/list_page.lua:6` |
| `OrangeTradingMod.WorkbenchCommercePages` | `client/ui/workbench/commerce_pages.lua:11` |
| `OrangeTradingMod.DialogConfirm` / `.DialogAlert` | `client/ui/dialogs/confirm.lua:6` / `client/ui/dialogs/alert.lua:8` |
| `OrangeTradingMod.Protocol` / `.Const` / `.Version` | `shared/protocol.lua:446` / `shared/orange_settings.lua:430` / `:9` |
| `OrangeTradingMod.Window`（当前打开的壳窗口） | `client/event_handlers.lua:757` |
| `OrangeTradingMod.CommunityCenter`（社区中心窗口） | `client/ui/community_center/window.lua:3942` |

**没有 `OCE.*` 这种东西**（全库 grep 无 `OCE` 命名空间）。

### 1.2 创建时机

- 全部是**文件首行建表 + 模块级 `if XLoaded then return end` 幂等守卫**，不是 `OnGameStart` 里创建。
  例：`shared/protocol.lua:3-6`、`client/ui/bootstrap.lua`（无守卫）、`client/ui/store.lua:5-6`。
- `Events.OnGameStart` 只用于**行为**（建 launcher 按钮、请求状态），见 `client/event_handlers.lua:3076` `Events.OnGameStart.Add(onStart)`。

### 1.3 模块间引用：只用 `require`

跨模块引用一律 `require`（PZ 覆写的 `require` 有缓存，不会重复执行）：

```lua
-- client/ui/workbench/shell_window.lua:1-10（摘）
require "ISUI/ISPanel"
require "ui/theme"
require "ui/primitives"
require "ui/page_registry"
local DisasterCatalog = require "disaster_catalog"
```

`require` 路径不带 `client/` 前缀，因为 PZ 的搜索根就是 `media/lua/{shared,client,server}`。

### 1.4 主入口文件与加载顺序

**客户端主入口 = `client/event_handlers.lua`**，它在文件头把整棵依赖树拉起来：

```lua
-- client/event_handlers.lua:1-34（摘）
require "settings"          -- → shared/settings.lua → shared/orange_settings.lua
require "catalog"
require "protocol"
require "client_api"
require "economy"
require "single_player_bridge"
...
require "ui/bootstrap"      -- ← UI 总入口
```

**UI 总入口 = `client/ui/bootstrap.lua`**，用一张显式列表决定页面加载顺序：

```lua
-- client/ui/bootstrap.lua:1-6, 58-60
local modules = {
    "ui/theme", "ui/layout", "ui/primitives", "ui/page_registry",
    "ui/store", "ui/actions", "ui/modal_layer", ...
}
for index = 1, #modules do require(modules[index]) end
```

页面注册是**自注册**的，文件被 require 时立刻注册，例如
`client/ui/pages/recycle.lua:2-4`：

```lua
local pages = require "ui/workbench/commerce_pages"
OrangeTradingMod.UIPageRegistry.Register("recycle", function(context)
    return pages.Create("recycle", context)
end)
```

**服务端主入口 = `server/command_router.lua`**，头 55 行 require 全部 service，然后在文件尾注册引擎事件：

```lua
-- server/command_router.lua:1075-1080（摘）
Events.OnClientCommand.Add(dispatch)
if Events.OnServerStarted then Events.OnServerStarted.Add(startServer) end
if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(initializeGlobalData) end
```

### 1.5 引擎真实加载顺序（读字节码验证，不是猜测）

`zombie/Lua/LuaManager.java`（class 反汇编）确认：

- `LoadDirBase()` → `LoadDirBase("shared")` → `LoadDirBase("client")`，`LoadDirBase(String)` 内部转调 `LoadDirBase(String, boolean)`。
- `LoadDirBase(dir, bool)` 对每个已启用模组扫描 `<mod>/media/lua/<dir>`，用 `searchFolders` **递归**进入子目录，只收 `.lua`。
- 收集完 `loadList` 后执行 `Collections.sort(loadList, String.CASE_INSENSITIVE_ORDER)`，所以**同一目录层内是按「相对路径字典序」加载，子目录同样参与排序**。
- 单机：`zombie/GameWindow.class` 调 `LuaManager.LoadDirBase()`（只有 shared + client）；进入世界时 `zombie/gameStates/GameLoadingState.enter()` **无条件**再调 `LuaManager.LoadDirBase("server")`。
- 专用服/联机主机：`zombie/network/GameServer.main()` 依次 `shared` → `client(true)` → `server`。

**对扩展模组的三个实际结论**：

1. `media/lua/server/**` 在**单机进世界后也会被加载**（这点和很多 B41 教程相反）；
2. 加载顺序是字典序，所以 `client/event_handlers.lua`(e) 先于 `client/ui/bootstrap.lua`(u)；但**不要依赖**，一律用 `require` 显式定序；
3. 自己的模组要做到「橙子已加载」才注册 UI，最稳的时机是 `Events.OnGameStart`（那时所有文件都 load 完了），见第 12 节骨架。

---

## 2. 客户端 UI 扩展点（最重要）

### 2.1 页面注册 API：干净、公开、就是给扩展用的

```lua
-- client/ui/page_registry.lua:29-58
function Registry.Register(pageId, factory)
    local key = pageKey(pageId)
    if not key then registrationError("Orange Trading page id is required") end
    if type(factory) ~= "function" then registrationError("Orange Trading page factory is invalid", key) end
    if Registry.factories[key] then registrationError("Orange Trading page is already registered", key) end
    Registry.factories[key] = factory
    Registry.order[#Registry.order + 1] = key
end

function Registry.Create(pageId, context)
    local key = pageKey(pageId)
    local build = key and Registry.factories[key]
    if not build then return nil, "Orange Trading page is unavailable: " .. tostring(key or pageId) end
    local page = build(context)
    if page == nil then return nil, "Orange Trading page could not be created: " .. key end
    page.pageId = key
    return page
end
```

- `Registry.Has(id)`（`:60`）、`Registry.Ids()`（`:65`）也是公开的。
- **注意 `Register` 重复注册会 `error()`**，所以扩展必须先 `Registry.Has(id)` 判重。
- `Registry.factories[id]` 是**公开可写表**——这正是模组自己打补丁用的手段（见 2.5）。

### 2.2 页面对象需要哪些字段

页面由 shell 驱动，shell 调用点全部在 `client/ui/workbench/shell_window.lua:497-570`：

| 成员 | 必需性 | 调用处 | 说明 |
|---|---|---|---|
| `ISUIElement` 派生（`ISPanel:new`） | 必需 | `:540 self:addChild(page)` | shell 是 ISPanel |
| `relayout(rect)` | 强烈建议 | `:543 pcall(page.relayout, page, self.ymLayout.content)` | 收到 `{x,y,w,h,width,height,right,bottom}` |
| `activate(params)` | 可选 | `:487-489 activatePage` | 缺省则 `setVisible(true)` |
| `deactivate()` | 可选 | `:491-494 deactivatePage` | 缺省则 `setVisible(false)` |
| `refresh(domains)` | 可选 | `:590-591 self.activePage:refresh({full=true})` | 状态推送后刷新 |
| `destroy()` / `clearChildren()` | 可选 | `:571-576 discardPage` | 关闭时释放 |
| `prerender()` / `render()` | 可选 | ISUI 引擎 | 自绘 |
| `pageId` | 只读 | `client/ui/page_registry.lua:56 page.pageId = key` | **shell 自动赋值，不要自己设** |
| 权限等级 | 无此字段 | — | 权限靠 `MENU` 的第三个元素 `adminOnly`，见 2.4 |

**没有 `title/icon` 字段**：标题/图标由 `MENU`(`:28`) + `MENU_ICONS`(`:61`) 单独维护，扩展页拿不到，只能自己画标题。

### 2.3 可复用的 UI 原语（真实签名）

`client/ui/primitives.lua:431-442`：

```lua
function UI.CreateCard(x, y, width, height, options) ... end
function UI.CreateButton(x, y, width, height, title, target, callback, variant)
function UI.CreateList(x, y, width, height) ... end
function UI.CreateCardGrid(x, y, width, height, options) ... end
function UI.CreateModal(x, y, width, height, options) ... end
function UI.CreateTextEntry(x, y, width, text, options) ... end
function UI.CreateComboBox(x, y, width, target, callback, options) ... end
function UI.CreateToggle(x, y, width, target, callback, options) ... end
```

- `variant` 取值：`"action" | "muted" | "danger" | "success" | "purchase"`（`client/ui/primitives.lua:283-292`）。
- 文本工具：`UI.FitText(value, font, width)`（`:185`）、`UI.DrawCurrencyValue(canvas, value, x, y, options)`（`:150`）、`UI.ListRowHeight(lineCount, font, options)`（`:66`）、`UI.GetDensityMetrics(font)`（`:48`）。
- 滚动条：`UI.AttachVerticalScroll(host, options)`（`:424`）。
- 主题：`OrangeTradingMod.UITheme.Colors`（`client/ui/theme.lua:9-45`）与 `.Metrics`（`:47-68`）。
- 布局：`UILayout.ComputeShell(w,h)`（`client/ui/layout.lua:67`）返回 `{window, topBar, navigation, content}`。
- 弹窗：`Modals.Open(modal, owner)` / `Modals.Close(modal)`（`client/ui/modal_layer.lua:138/114`）、`DialogConfirm.Open(context, owner, options)`（`client/ui/dialogs/confirm.lua:21`）、`DialogAlert.Open(context, owner, message, onClosed)`（`client/ui/dialogs/alert.lua:156`）。

**最省事的做法**：直接用官方「列表页工厂」，它把搜索框 + 翻页卡片列表 + 数量 +/- + 主按钮 + relayout 全做好了：

```lua
-- client/ui/workbench/list_page.lua:77 / :294 / :310（接口）
local page = OrangeTradingMod.WorkbenchListPage.Create(context, {
    titleKey = "租用NPC",
    actionKey = "Hire",
    rows = function(snapshot, page) return myRows end,       -- :296
    execute = function(page, row, quantity) ... end,          -- :128
    canExecute = function(page, row) return true end,         -- :260
    cardGrid = true, cardHeight = 138, maxColumns = 5,
})
```

### 2.4 窗口怎么打开、导航怎么做

- 窗口类：`client/ui/workbench/shell_window.lua:226-243`，`ISPanel:derive("OrangeTradingModUIShell")`。
- 打开：`OrangeTradingMod.Open(number, targetPage)`（`client/event_handlers.lua:710`），已开时复用并 `setPage(targetPage)`（`:716-717`）。
- 切页：`shell:setPage(rawId, params)`（`:497`）。
- 页面上下文（页面工厂收到的 `context`）：

```lua
-- client/ui/workbench/shell_window.lua:358-363
function Shell:pageContext()
    return { player = self.player, shell = self, store = Store, actions = Actions,
             theme = Theme, primitives = UI, modalLayer = Modals, text = text }
end
```

- **入口按钮**：不是按键、不是聊天命令、不是物品，而是一个常驻屏幕的 `ISButton` launcher：
  `client/event_handlers.lua:2852`（`launcher = Button:new(12, 200, ..., function() ... OrangeTradingMod.Open(0) end)`），
  以及 `:2953` 的社区中心 launcher。
- **全库没有任何按键绑定**（grep `OnKeyStartPressed|OnKeyPressed|OnCustomUIKey|addKeyBinding|Keyboard[` 在 `client/` 下零命中）。所以「按 K 打开」是我们自己要加的，不会冲突。
- 导航是**静态局部表** `MENU`（`:28-59`），渲染/排版在 `Shell:layoutMenu`（`:670-692`）与可见性在 `Shell:refreshNavigationVisibility`（`:612-632`）。

### 2.5 有没有官方「外部模组追加页面」钩子？

**没有。** 全库 `Events.` 事件清单里没有任何 `OnOrange*Addon` / `RegisterPage` 之类；`grep -rn "addon|extension|hook"` 无命中。

但模组**自己**留了一个可照抄的先例——`client/ui/bootstrap.lua:64-116` 把首页工厂包了一层，往首页塞一个「社区中心」按钮：

```lua
-- client/ui/bootstrap.lua:64-93（摘）
local function installCommunityCenterHomeEntry()
    local registry = OrangeTradingMod.UIPageRegistry
    if OrangeTradingMod.CommunityCenterHomeEntryInstalled or not registry
            or type(registry.factories) ~= "table" then return end
    local homePageId = type(registry.factories.index) == "function" and "index"
        or type(registry.factories.home) == "function" and "home" or nil
    local originalFactory = homePageId and registry.factories[homePageId] or nil
    if type(originalFactory) ~= "function" then return end
    OrangeTradingMod.CommunityCenterHomeEntryInstalled = true          -- ← 幂等标志
    registry.factories[homePageId] = function(context)
        local page = originalFactory(context)
        ...
        local button = primitives.CreateButton(0, 0, 140, 30, "…", page, callback, "action")
        button:initialise(); button:instantiate(); page:addChild(button)   -- ← 手工初始化三连
        ...
        local originalRelayout = page.relayout
        function page:relayout(rect) ... end                            -- ← 包 relayout 定位
        return page
    end
end
installCommunityCenterHomeEntry()                                      -- :116 文件末尾立即执行
```

**这就是我们该照抄的「最小侵入挂接点」**（第 12 节给完整骨架）。

另一个可用的机制：`Shell:setPage` **对未登记的 id 不做权限拦截**。因为
`menuItem(id)`（`:188-193`）对未知 id 返回 `nil`、`enabledPage(id)`（`:166-186`）的 switch 表里没有的 id 默认 `true`，所以
**只要 `Registry.Register` 过 id，`shell:setPage("bin2NpcRecruit")` 就能开** —— 唯一的缺口是没有侧栏按钮，需要我们自己塞入口。

### 2.6 上下文菜单注册点

| 事件 | 位置 |
|---|---|
| `Events.OnFillWorldObjectContextMenu` | `client/event_handlers.lua:3077`（车辆认证）、`client/gas_pump_patch.lua:651`（油泵）、`client/safehouse_utility_client.lua:640` |
| `Events.OnFillInventoryObjectContextMenu` | `client/event_handlers.lua:3078` |
| `Events.OnServerCommand` | `client/event_handlers.lua:3080` |
| `Events.OnGameStart` | `client/event_handlers.lua:3076` |

我们要加「对着 NPC 右键 → 招募」就可以再 `Add` 一个 `OnFillWorldObjectContextMenu` 监听器，零冲突。

---

## 3. 客户端 ↔ 服务端协议

### 3.1 消息格式

```lua
-- shared/protocol.lua:8-11, 446
local Protocol = { Module = "OrangeTradingMod", C2S = { ... }, S2C = { ... } }
OrangeTradingMod.Protocol = Protocol
```

- **三要素：`module`（字符串）+ `command`（字符串）+ `args`（Lua table）**，由 `sendClientCommand` / `sendServerCommand` 传，PZ 引擎自己序列化，**不是 JSON**。
- `shared/json_codec.lua` 与网络协议**无关**，它只被 web bridge / 配置文件导入导出用到：
  `server/admin_item_vault.lua:3`、`server/economy_web_bridge.lua:2`、`server/community_web_bridge.lua:7`、`server/disaster_web_bridge.lua:2`、`server/mystery_box_service.lua:5`（都是落盘 JSON）。
- C2S 名称表 `shared/protocol.lua:11-353`（约 300 条），S2C 名称表 `:355-443`。

### 3.2 服务端收包：`command_router` 没有注册 API，但我们不需要它

```lua
-- server/command_router.lua:61-63
local ModuleName = Protocol.Module or "OrangeTradingMod"
local Commands = Protocol.C2S or {}
local routes = {}
-- :134  local function register(names) ... routes[wireName] = implementation ... end
```

`routes` 与 `register` 都是 **local**，`command_router` 也没有把路由表暴露到 `OrangeTradingModServer` 上。**结论：第三方无法往 `routes` 里加自己的 cmd；也不需要。**

真正要看的入口是 `dispatch`：

```lua
-- server/command_router.lua:677-691（摘）
local function dispatch(module, command, player, args)
    if module ~= ModuleName or type(command) ~= "string" or command == "" then return end
    if not OrangeTradingModServer.IsPlayerObject(player) then return end
    local handler = routes[command]
    if type(handler) ~= "function" then log("unknown client command", command) return end
    ...
```

**`module ~= ModuleName` 直接 return** —— 这就是最干净的扩展缝隙：

> **用我们自己的 module 名（例如 `"bin2NpcExtension"`）发指令，橙子的 router 会静默忽略；我们自己再挂一个
> `Events.OnClientCommand` 监听器处理自己的 module。全程零 monkey patch，且永不受对方重构影响。**

回包同理：`sendServerCommand(player, "bin2NpcExtension", "NpcRoster", payload)`。
如果图省事想用橙子的 `OrangeTradingModServer.SendToPlayer`（`server/runtime_core.lua:687`），注意它**硬编码了 `protocol.Module`**：

```lua
-- server/runtime_core.lua:687-693
function server.SendToPlayer(player, command, args)
    if sendServerCommand and server.IsPlayerObject(player) then
        local payload = args or {}
        recordSyncTelemetry(command, payload)
        sendServerCommand(player, protocol.Module or "OrangeTradingMod", command, payload)
    end
end
```

用它会走橙子的 module，客户端被 `onServerCommand` 的 `module ~= Protocol.Module` 过滤后**只有橙子自己的 handler 表才认**，而那张表（`client/event_handlers.lua:2322`）也是 local。所以**要么完全用自己的 module，要么 monkey patch `OrangeTradingMod.HandleServerCommand`**（`:2601`）。推荐前者。

服务端 handler 的语义约定（`server/command_router.lua:698-720`）：

```lua
-- server/command_router.lua:698-714（摘）
OrangeTradingModServer.BeginTransmitBatch()
local ok, err = pcall(function()
    ... prepareEconomy() ...
    OrangeTradingModServer.ActiveCommandContext = { command = command, requestId = ... }
    local handled, reason = pcall(handler, player, normalizedArgs)
    if not handled then log("command " .. command .. " failed", reason) end
    if not OrangeTradingModServer.StateSentInCommand then OrangeTradingModServer.SendScopedState(player) end
end)
OrangeTradingModServer.EndTransmitBatch()
```

即：**handler 签名 = `function(player, args)`**，`args` 已被 `OrangeTradingModServer.CommandArgs(args)` 归一化（`server/runtime_core.lua:25`）。

### 3.3 客户端发/收

```lua
-- client/client_api.lua:325-337
function OrangeTradingMod.SendMarketCommand(command, arguments)
    if not validCommands[command] then return false end            -- ← 只认 Protocol.C2S 里的名字
    arguments = type(arguments) == "table" and arguments or {}
    if OrangeTradingMod.IsSinglePlayer and OrangeTradingMod.IsSinglePlayer() then
        if OrangeTradingMod.DispatchSinglePlayerCommand then
            return OrangeTradingMod.DispatchSinglePlayerCommand(command, arguments) == true
        end
        return false
    end
    if not sendClientCommand then return false end
    sendClientCommand(Protocol.Module, command, arguments)
    return true
end
```

`validCommands` 在 `client/client_api.lua:12-16` 由 `Protocol.C2S` 生成 —— **我们的 cmd 名不在里面，所以 `SendMarketCommand` 会直接返回 `false`**。我们要自己写一层（骨架第 12 节给了）。

客户端收包：

```lua
-- client/event_handlers.lua:2601-2627（摘）
function OrangeTradingMod.HandleServerCommand(command, args, player)
    player = player or activePlayer(0)
    local handler = handlers[command]          -- :2322 起的 local 表
    if handler then ... return end
    ...
end
local function onServerCommand(module, command, args)
    if module ~= Protocol.Module then return end
    local ok, failure = pcall(OrangeTradingMod.HandleServerCommand, command, args)
    ...
end
```

同样按 module 过滤 —— 我们用自己 module 名再挂一个 `Events.OnServerCommand` 即可。

### 3.4 客户端状态怎么同步

- 服务端把快照按 **domain**（`"account"`, `"homepublic"`, `"treasury"`, `"animalmarket"` …）推给玩家：
  `server/sync_transport.lua:704 SendScopedState`、`:716 SendDomainState`、`:905 Reply`。
- 客户端把 S2C 载荷写进**全局表**：`handlers` 表（`client/event_handlers.lua:2322-2400`）→ `sharedState`/`playerState`/`accountDelta` 等函数。
- 读取统一走 `OrangeTradingMod.DataBucket(key)`（`client/client_api.lua:181-248`）→ 例如 `OrangeTradingMod.ClientEconomy`、`ClientPlayerData`。
- UI 再包一层：`client/ui/store.lua:117 Store.Snapshot(player)`、`:156 Store.Status(player)`（余额在这里：`NormalizeCoins(account.coins)`）。
- Shell 在切页时按 `PAGE_DOMAINS[id]`（`client/ui/workbench/shell_window.lua:76-105`）请求 `RequestDomainState`（`:268`）。

> ⚠️ **`PAGE_DOMAINS` 也是 local**：我们的页面 id 不在表里，`Shell:requestDomainsForPage` 会直接 `return false`（`:271-272`），**切到我们的页面不会触发任何状态推送**。
> 需要余额/金库数据时，自己发一次读指令（`RequestDomainState` 在 `readOnlyCommands` 白名单里，见 `server/command_router.lua:66`），例如：
> `sendClientCommand("OrangeTradingMod", "RequestDomainState", { domains = { "account" } })`。

---

## 4. 货币系统

### 4.1 余额存在哪

- **按玩家一个 ModData 表**：TAG = `OrangeTradingModPlayer_<playerKey>`，字段 `coins`。
  前缀常量：`shared/orange_settings.lua:55` `PLAYER_KEY_PREFIX = "OrangeTradingModPlayer_"`。
- 服务端内存权威副本：`server.AuthoritativeBuckets[key]`，通过 `server.DataBucket(key)` 获取（`server/runtime_core.lua:211-220`）；
  判定哪些 key 走权威副本看 `server.IsAuthoritativeDataKey(key)`（`:180-185`）。

### 4.2 公开函数与签名（推荐只用这些）

```lua
-- server/runtime_core.lua:103-130
function server.NormalizeAccountBalance(value)                 -- 允许负数的唯一字段
function server.AccountBalance(account)          -> coins      -- :108 读取并归一化
function server.CreditAccountBalance(account, amount) -> newBalance, applied  -- :114
function server.SpendAccountBalance(account, amount)  -> true/false, balance  -- :123

-- server/runtime_core.lua:502-518
function server.AddCoins(player, amount) -> newBalance          -- :502 加钱（超上限自动截断）
function server.Pay(player, amount)      -> true/false          -- :510 扣钱（向上取整，原子性检查）
```

`server.Pay` 的实现就是「检查+扣减」一体，天然防负数与并发双花：

```lua
-- server/runtime_core.lua:510-518
function server.Pay(player, amount)
    local charge = server.CeilCoins(server.SafeNumber(amount, 0, 0, server.MAX_COMMAND_NUMBER))
    if not server.IsPlayerObject(player) or charge <= 0 then return false end
    local data = server.PlayerData(player)
    if not server.SpendAccountBalance(data, charge) then return false end
    server.Transmit(server.PlayerKey(player))
    return true
end
```

客户端只读：`OrangeTradingMod.PlayerData(player).coins`（`client/client_api.lua:250`）、
`OrangeTradingMod.NormalizeCoins(v)`（`:58`）、`OrangeTradingMod.FormatCoins(v)`（`:62`）。

### 4.3 社区金库 API（`server/community_treasury_service.lua`）

| 函数 | 行 | 语义 / 返回 |
|---|---|---|
| `S.NormalizeCommunityTreasuryState()` | `:157` | 取（并修复）金库状态表 |
| `S.CommunityTreasuryCredit(category, amount, context)` | `:466` | 入账 → `true, {code="credited", entryId, amount, balance}` |
| `S.CommunityTreasuryReserve(category, amount, context)` | `:488` | **预留**（escrow）→ `true, {code="reserved", token, ...}` |
| `S.CommunityTreasuryCommitReservation(token, context)` | `:530` | 预留转实扣 |
| `S.CommunityTreasuryReleaseReservation(token, context)` | `:571` | 释放预留 |
| `S.CommunityTreasuryDebit(category, amount, context)` | `:627` | 直接扣款 → `true, {code="debited", ...}` |
| `S.CommunityTreasurySnapshot()` | `:1695` | 只读快照 |
| `S.BuildCommunityTreasuryState(player, raw)` / `SendCommunityTreasuryState` | `:1866` / `:1925` | 生成 / 下发 UI 状态 |

所有金额变更方法都要求 `context.requestId`（`requestKey`/`cached`/`remember`，`:325-347`），
**同一 requestId 重放返回缓存结果**，这是它做幂等的机制。

### 4.4 「扣款 + 防作弊」推荐写法

项目里的标准范式是 **先 `Pay`、干活、失败就 `AddCoins` 退款**，全程在同一个 command 分发内（已被 `BeginTransmitBatch/EndTransmitBatch` 包住）：

```lua
-- server/animal_purchase.lua:206-229（摘，这是最标准的原子购买写法）
    if not Server.Pay(player, row.basePrice) then return Server.Reply(player, "NoMoney") end
    local ok, animal = spawnPreparedAnimal(row, breed, square)
    if not ok then
        Server.AddCoins(player, row.basePrice)          -- ← 回滚
        return Server.Reply(player, "AnimalSpawnFailed")
    end
```

物品侧的 escrow 工具在 `server/trade_item_escrow.lua`：
`server.CaptureTradeItem(item, options)`（`:608`）、`server.AddInventoryItemFromSnapshot(player, snapshot, fallbackType, options)`（`:652`）、
`server.RestoreSnapshotBatch(player, snapshots, fallbackType)`（`:816`）。

**给 NPC 雇用的建议**：金额小、无物品交付 → 直接
`if not S.Pay(player, cost) then reply("NoMoney") end` → 生成/绑定 NPC → 失败 `S.AddCoins(player, cost)` 退款；
再配一个自己的 `requestId` 去重表（模仿 `server/action_request_guard.lua:50` 的 `CheckHighRiskActionRequest`）。

---

## 5. 服务端权威与权限

### 5.1 频率限制：白名单制，我们不在里面

```lua
-- server/action_request_guard.lua:7-24
local policies = {
    BuyLotteryTicket = 750, BuyLotteryRandom = 750, SpinFruitMachine = 900,
    OpenMysteryBox = 900, ClaimMysteryBoxReward = 500, ClaimSupporterGift = 1000,
    CreateSupporterVehicleAuction = 1500, SubmitTaskItems = 750, ...
}
-- :50
function S.CheckHighRiskActionRequest(player, command, raw)
    local interval = policies[tostring(command or "")]
    if not interval then return true, nil, "" end       -- ← 未登记 = 不限速、不去重
```

调用点：`server/command_router.lua:689-696`（MP）与 `client/single_player_bridge.lua:266`（SP）。
**我们的 cmd 默认不受保护 → 必须自己实现限速/去重**（照抄 `:50-79` 的 `history/seen/lastAcceptedAt` 结构即可）。

### 5.2 管理员判定

```lua
-- server/runtime_core.lua:695-709
local function accessLevel(player)
    if OrangeTradingMod and OrangeTradingMod.IsSinglePlayer and OrangeTradingMod.IsSinglePlayer() then return "admin" end
    if not player or not player.getAccessLevel then return "" end
    local ok, value = pcall(player.getAccessLevel, player)
    return ok and string.lower(tostring(value or "")) or ""
end
function server.IsAdmin(player) ... end      -- admin / moderator / overseer
function server.IsFullAdmin(player) ... end  -- 仅 admin
```

客户端版本：`client/client_api.lua:471 IsAdmin` / `:481 IsFullAdmin`。

### 5.3 单人 / 多人分支

```lua
-- client/single_player_bridge.lua:13-19
local function multiplayerClient() return isClient and isClient() == true end
function OrangeTradingMod.IsSinglePlayer() return not multiplayerClient() end
```

**单机也会跑服务端服务**（重要）：

1. 引擎侧：`GameLoadingState.enter()` 会 `LoadDirBase("server")`，`media/lua/server/**` 在单机进世界后被加载（见 1.5）。
2. 但单机没有 `OnClientCommand` 往返，所以模组自己搭了一座桥：

```lua
-- client/single_player_bridge.lua:48-52
    OrangeTradingModServer.SendToPlayer = function(player, command, payload)
        if OrangeTradingMod.HandleServerCommand then
            OrangeTradingMod.HandleServerCommand(command, payload or {}, player)
        end
    end
```

3. 单机指令分发走一张**硬编码白名单**（`client/single_player_bridge.lua:74-152 LOCAL_COMMAND_METHODS`）+ `handlers()`（`:159-177`），
   入口是 `OrangeTradingMod.DispatchSinglePlayerCommand(command, args)`（`:255-304`），它开头就：

```lua
-- client/single_player_bridge.lua:255-260
function OrangeTradingMod.DispatchSinglePlayerCommand(command, args)
    if not OrangeTradingMod.IsSinglePlayer() or rejectedCommands[command] then return false end
    local player = currentPlayer()
    if not player or not ensureRuntime() then return false end
    local callback = handlers()[command]
    if not callback then return false end
```

`handlers()` 与 `LOCAL_COMMAND_METHODS` 都是 local，**我们塞不进去**。

**结论**：`bin2_npc_extension` **必须自己同时支持单机**。做法是在我们自己的网络层里分叉（第 12 节骨架的 `Send` / `Dispatch`）：

- `isClient() == true` → `sendClientCommand("bin2NpcExtension", cmd, args)`；
- 否则（单机）→ 直接 `pcall(Bin2NpcServer[cmd], getSpecificPlayer(0), args)`，并把「回包」直接送进我们自己的客户端 handler。

不要去 wrap `OrangeTradingMod.DispatchSinglePlayerCommand`（能做，但会把我们绑死在它的内部实现上）；独立 module 更稳。

---

## 6. 翻译与文本

### 6.1 文件与键名前缀

`media/lua/shared/Translate/{CN,EN}/` 下各 4 个 JSON：

| 文件 | 键数量 | 键名前缀 |
|---|---|---|
| `IG_UI.json` | 5529 | `IGUI_OrangeTradingMod_*`（另有少量 `IGUI_ItemCat_*`） |
| `ItemName.json` | 120 | `ItemName_OrangeTradingMod.*` + 裸 `OrangeTradingMod.*` |
| `Tooltip.json` | 69 | `Tooltip_OrangeTradingMod.*` |
| `Sandbox.json` | 423 | `Sandbox_OrangeTradingMod*` |

### 6.2 读文本 API

```lua
-- client/client_api.lua:138-144（摘）
function OrangeTradingMod.Text(key, ...)
    local original = tostring(key or "")
    local name = original
    if name:sub(1, 23) ~= "IGUI_OrangeTradingMod_" then
        name = "IGUI_OrangeTradingMod_" .. name        -- ← 强制加前缀
    end
    ...
    ok, translated = pcall(getText, name, ...)
```

> **关键结论**：`OrangeTradingMod.Text("Foo")` 一定会去查 `IGUI_OrangeTradingMod_Foo`。
> 我们**不能**用它读自己的键，除非把自己的键也命名成 `IGUI_OrangeTradingMod_*`。

其他读取方式（模组内实际用法）：`getText(key, ...)`（`client/event_handlers.lua:598-599`，`localizedNoticeItemName`），
`getTextOrNull(key)`（`client/ui/pages/profession.lua:155-156`）。

### 6.3 第三方该怎么做

1. 在**自己模组**里建 `media/lua/shared/Translate/CN/IG_UI.json` 和 `.../EN/IG_UI.json`，用**自己的前缀**，例如：
   ```json
   { "IGUI_Bin2Npc_RecruitTitle": "NPC 招募", "IGUI_Bin2Npc_Hire": "雇佣" }
   ```
2. 读的时候用原生 `getText("IGUI_Bin2Npc_RecruitTitle")`，不要过 `OrangeTradingMod.Text`。
3. 若确实想复用橙子的 `Text()`（能自动拿到它的缺省兜底逻辑），可以把键名写成
   `IGUI_OrangeTradingMod_Bin2Npc_Recruit` 放在**我们的** JSON 里 —— Translator 会合并所有模组的 `IG_UI.json`。
   代价是与橙子未来新增键存在**命名碰撞风险**，不推荐作为默认方案。

---

## 7. 沙盒 / 配置

- **`media/sandbox-options.txt` 存在**（不是没有）：2017 行，首行 `VERSION = 1,`，每个 option 形如

```
option OrangeTradingMod.CommunityCenterEnabled
{
    type = boolean,
    default = false,
    page = OrangeTradingMod,
    translation = OrangeTradingMod_CommunityCenterEnabled,
}
```
  （`media/sandbox-options.txt:849-855`）

- `shared/settings.lua` 只有 2 行，是兼容壳：

```lua
-- shared/settings.lua:1-2
-- Compatibility entry point retained for existing OrangeTradingMod modules.
return require "orange_settings"
```

- 读取路径（两种都支持）：

```lua
-- shared/orange_settings.lua:666-680（摘）
local function sandboxOptionValue(optionName, legacyOptionName)
    if not SandboxVars then return nil end
    local modOptions = SandboxVars.OrangeTradingMod
    ...
        if type(modOptions) == "table" and modOptions[name] ~= nil then return modOptions[name] end
        local flatValue = SandboxVars["OrangeTradingMod." .. tostring(name or "")]
```

- 定义表：`OrangeTradingMod.SandboxOptionDefs`（`shared/orange_settings.lua:432`）；
  应用时机：`OrangeTradingMod.ApplySandboxOptions()`（`:828-843`）在文件末尾立即调一次（`:843`），
  联机时客户端改用服务端下发值：`OrangeTradingMod.ApplyServerSandboxConfig(config)`（`:809`）。
- 常量表：`OrangeTradingMod.Const`（`:430`），沙盒值以大写 KEY 存在这里。

### 7.1 有没有开关能关掉我们的页面？

- `COMMUNITY_CENTER_ENABLED`（`shared/orange_settings.lua:397`，沙盒开关 `media/sandbox-options.txt:849`）与
  `OrangeTradingMod.IsCommunityCenterEnabled()`（`:845-849`）只控制**社区中心窗口**和首页那个按钮。
- `STORE_*_PAGE_VISIBLE` 系列（`shared/orange_settings.lua` 内）只被 `Shell:enabledPage`（`client/ui/workbench/shell_window.lua:166-186`）读取；
  **我们的 id 不在它的 switch 表里 → 默认 `true`（永远显示）**。
- 所以：**没有任何现成开关能关掉我们的页面**。若需要服主可关，要自己加沙盒项（自己模组的 `media/sandbox-options.txt`，页名用自己的 mod id），
  或者复用 `OrangeTradingMod.Const.COMMUNITY_CENTER_ENABLED` / `IsCommunityCenterEnabled()` 做软开关。

---

## 8. 持久化

### 8.1 橙子用到的 ModData TAG 全前缀

全部定义在 `shared/orange_settings.lua:34-70`（`defaultConstants`）：

| 常量 | TAG 字符串 |
|---|---|
| `ECONOMY_KEY` | `economy` |
| `STATS_KEY` | `OrangeTradingModStats` |
| `TRADE_KEY` | `OrangeTradingModTrades` |
| `BUY_ORDER_KEY` | `OrangeTradingModBuyOrders` |
| `VEHICLE_POOL_KEY` | `OrangeTradingModVehiclePool` |
| `VEHICLE_REGISTRY_KEY` | `OrangeTradingModVehicleRegistry` |
| `VEHICLE_OPERATION_LOG_KEY` | `OrangeTradingModVehicleOperationLog` |
| `ADMIN_PRICE_OVERRIDES_KEY` | `OrangeTradingModAdminPriceOverrides` |
| `ANIMAL_CATALOG_KEY` | `OrangeTradingModAnimalCatalog` |
| `MANAGED_CATALOG_KEY` | `managed_catalog` |
| `MANAGED_CATALOG_TEMPLATES_KEY` | `OrangeTradingModManagedCatalogTemplates` |
| `MANAGED_STOCK_KEY` | `OrangeTradingModManagedStock` |
| `RECYCLE_CATALOG_KEY` / `RECYCLE_TEMPLATES_KEY` | `OrangeTradingModRecycleCatalog` / `...RecycleTemplates` |
| `WORLD_MARKET_KEY` / `WORLD_MARKET_TEMPLATES_KEY` | `OrangeTradingModWorldMarket` / `...WorldMarketTemplates` |
| `BOUNTY_ORDER_KEY` | `OrangeTradingModBountyOrders` |
| `LOTTERY_KEY` | `OrangeTradingModLottery` |
| `PLAYER_INDEX_KEY` | `OrangeTradingModPlayerIndex` |
| `PLAYER_KEY_PREFIX` | `OrangeTradingModPlayer_` |
| `ECONOMY_WEB_BRIDGE_KEY` | `OrangeTradingModEconomyWebBridge` |
| `LEGACY_MIGRATION_KEY` | `OrangeTradingModLegacyMigration` |
| `SAFEHOUSE_UTILITIES_KEY` | `OrangeTradingModSafehouseUtilities` |
| `STOCK_MARKET_KEY` | `OrangeTradingModStockMarket` |
| `AUCTION_KEY` | `OrangeTradingModAuctions` |
| `BUSINESS_CONFIG_KEY` | `OrangeTradingModBusinessConfig` |
| `ADMIN_VAULT_KEY` | `OrangeTradingModAdminVault` |
| `PROFESSION_SERVICE_KEY` | `OrangeTradingModProfessionService` |
| `TASK_SYSTEM_KEY` | `OrangeTradingModTasks` |
| `DISASTER_KEY` | `OrangeTradingModDisasters` |
| `WELFARE_KEY` | `OrangeTradingModWelfare` |
| `COMMUNITY_PROJECT_KEY` | `OrangeTradingModCommunityProjects` |
| `COMMUNITY_GOVERNANCE_KEY` | `OrangeTradingModCommunityGovernance` |
| `COMMUNITY_TREASURY_KEY` | `OrangeTradingModCommunityTreasury` |
| `HONOR_KEY` | `OrangeTradingModHonors` |

### 8.2 读写与同步机制

```lua
-- server/runtime_core.lua:186-190
local function engineBucket(key)
    if not ModData or not ModData.getOrCreate then return {} end
    local ok, bucket = pcall(ModData.getOrCreate, key)
    return ok and type(bucket) == "table" and bucket or {}
end
-- server/runtime_core.lua:260-280（摘）
function server.Transmit(key)
    ...
    server.PersistBucket(key, false)
    if not server.IsAuthoritativeDataKey(key) and ModData and ModData.transmit then
        pcall(ModData.transmit, key)
    end
end
```

- 权威 key（`fixedBucketSet` 或 `OrangeTradingModPlayer_*`）**不会**走 `ModData.transmit`，全靠 S2C domain 推送；
- **非权威 key（= 我们的 key）会走 `ModData.transmit`**，这是意外之喜：第三方用自己的 ModData 表，天然获得多人同步。

### 8.3 推荐做法

- 服务端全局数据：`local data = ModData.getOrCreate("Bin2NpcExtensionRoster")`，改完 `if ModData.transmit then pcall(ModData.transmit, "Bin2NpcExtensionRoster") end`。
- 单角色数据：`player:getModData()`（模组自己的先例：`client/event_handlers.lua:797-799` 里车辆上的 `data.OrangeTradingModRegistrationId`）。
- **命名空间**：表名一律 `Bin2Npc*` / `Bin2NpcExtension*`，绝不复用 `OrangeTradingMod*`，也绝不要碰 `economy`、`managed_catalog` 这两个无前缀的 key。
- 单人下 `ModData` 全局表随存档保存，行为与多人一致（`engineBucket` 不区分环境）。

---

## 9. 失败与兼容

- **日志前缀**：
  - 客户端：`client/event_handlers.lua:458` `print("[OrangeTradingMod][Client] " .. scope .. ": " .. msg)`；
  - 服务端：`server/command_router.lua:115-117` `print(string.format("[OrangeTradingMod] %s: %s", scope, message))`；
  - 子模块自己加方括号标签，如 `[OrangeTradingMod][WorldMarket]`（`server/world_market_service.lua:538`）。
- **pcall 习惯**：几乎每次调引擎/跨模块都用 `pcall`：
  `server/command_router.lua:119-123 callProtected`、
  `shared/runtime_compat.lua:12-29 RuntimeCompat.Call/Invoke/Value`（把 `pcall(obj.method, obj, ...)` 包成统一入口），
  以及 shell 里的 `pcall(Pages.Create, id, ctx)`（`client/ui/workbench/shell_window.lua:531`）与 `pcall(page.relayout, ...)`（`:543`）。
- **缺依赖的降级**：页面创建失败 → `showPageError(Text("State_PageUnavailable"))` + 日志（`client/ui/workbench/shell_window.lua:533-537`）；
  数据为空 → 画 `State_Empty`（`client/ui/workbench/list_page.lua:381-384`）。
- **`getActivatedMods()` 全库零使用**（`grep -rn getActivatedMods` 无命中）。模组不检测其它模组，靠 `require` 成功/失败降级。
- **版本号常量**：`shared/orange_settings.lua:9` `OrangeTradingMod.Version = 1`（**这是数据 schema 版本**，被写进各种存档，例如 `server/runtime_core.lua:435 data.version = OrangeTradingMod.Version or ...`）。
  另有 `PRICE_FORMULA_VERSION = 11`（`shared/orange_settings.lua:35`）。
  **workshop 版本只能从 `mod.info` 读**：`versionMin=42.2.0`、`id=OrangeCommunityEconomy`、`name=橙子社区经济`。

---

## 10. 脆弱点清单（只读 vs 必须 patch）

| 接口 / 挂接点 | 稳定性 | 理由与替代 |
|---|---|---|
| `UIPageRegistry.Register/Has/Create` (`client/ui/page_registry.lua:29/60/45`) | **【稳定接口】** | 参数校验明确、有 `Has` 判重、`factories` 表是设计给替换的 |
| `OrangeTradingMod.Open(number, pageId)` (`client/event_handlers.lua:710`) | **【稳定接口】** | 已带 `targetPage` 参数 |
| `Shell:setPage(id)` (`client/ui/workbench/shell_window.lua:497`) | **【半稳定】** | 对未知 id 不拦截（依赖 `menuItem`/`enabledPage` 的默认分支），很稳但不是文档承诺 |
| `UI.Create*` 原语 (`client/ui/primitives.lua:431-442`) | **【稳定接口】** | 集中式工厂，签名简单 |
| `WorkbenchListPage.Create(context, definition)` (`client/ui/workbench/list_page.lua:77`) | **【半稳定】** | 好用的整页脚手架，但 `definition` 字段无校验、可能随版本增删 |
| `context` 字段 `{player,shell,store,actions,theme,primitives,modalLayer,text}` (`shell_window.lua:358`) | **【半稳定】** | 集中返回，扩展风险低 |
| `registry.factories["index"]` 首页工厂 (`client/ui/bootstrap.lua:73`) | **【半稳定】** | 模组自己就在用；但首页内部结构（`homeViewButtons`）是内部实现 |
| `MENU` 侧栏表 (`shell_window.lua:28`) | **【内部实现细节】—— 改不了** | local 表，无法追加；只能自建入口 |
| `PAGE_DOMAINS` 域映射 (`shell_window.lua:76`) | **【内部实现细节】—— 改不了** | local 表；我们的页面拿不到自动状态推送 |
| `TABS` 社区中心标签 (`community_center/window.lua:31`) | **【内部实现细节】—— 改不了** | 同上 |
| `server/command_router.lua` 的 `routes` / `register` (`:63/:134`) | **【内部实现细节】** | local，不可注册；用独立 module 名绕过 |
| `client/event_handlers.lua` 的 `handlers` (`:2322`) | **【内部实现细节】** | local；用独立 module 名绕过 |
| `single_player_bridge.lua` 的 `LOCAL_COMMAND_METHODS` / `handlers()` (`:74/:159`) | **【内部实现细节】** | local，不可注册；自建 SP 本地分发 |
| `server.AddCoins` / `server.Pay` / `server.AccountBalance` (`runtime_core.lua:502/510/108`) | **【稳定接口】** | 全局函数，签名清晰，被 20+ 个 service 使用 |
| `S.CommunityTreasury*` (`community_treasury_service.lua:466/488/530/627`) | **【半稳定】** | 是服务间内部 API，但显式挂在 `OrangeTradingModServer` 上且语义稳定 |
| `server.SendToPlayer` (`runtime_core.lua:687`) | **【半稳定】** | 硬编码 module 名，混用会串台 |
| `server.Reply` (`sync_transport.lua:905`) | **【半稳定】** | 依赖 `ActiveCommandContext`，在橙子自己的 dispatch 之外调用会丢 command/requestId |
| `Const.PLAYER_KEY_PREFIX` / 各 TAG (`orange_settings.lua:34-70`) | **【稳定接口】**（只读） | 读余额可以，**写入绝对不要** |
| `OrangeTradingMod.Text(key,...)` (`client_api.lua:138`) | **【内部实现细节】** | 强制 `IGUI_OrangeTradingMod_` 前缀，不适合外键 |
| ModData TAG `economy` / `managed_catalog` | **【内部实现细节】**（只读） | 无前缀，命名冲突风险最高 |

**建议「只读不改」**：`shared/orange_settings.lua` 的所有 `*_KEY`、`client_api.lua` 的 `DataBucket/PlayerData`、
`server/runtime_core.lua` 的 `AuthoritativeBuckets`、`server/sync_*.lua` 的推送函数。
**必须扩展时**：只 patch 两个位置 ——（1）`UIPageRegistry.factories["index"]`（放入口按钮），（2）自己挂新的 `Events.OnClientCommand` / `Events.OnServerCommand` / `Events.OnGameStart`。这两者都不与橙子争用同一个 key。

---

## 11. 失败重试/去重的地方（补充）

橙子对「同一次点击重发」的处理在客户端 `client/ui/actions.lua`：

```lua
-- client/ui/actions.lua:15-29
local protectedCommands = { BuyLotteryTicket = { fields = { "front", "back" } }, ... }
-- :76-98
function Actions.Send(command, payload)
    if not Actions.IsAvailable(command) then return false, ... end
    ...
    payload.requestId = tostring(payload.requestId or "")
    if payload.requestId == "" then payload.requestId = requestId(command) end
```

我们自己的页面若要复用 `context.actions`，**不可行**（`Actions.IsAvailable` 只认 `Protocol.C2S`）。
自己写一个 8 行同级封装即可（见骨架 `NpcNet.Send`，内部也会生成 `requestId`）。

---

## 12. `bin2_npc_extension` 的最小客户端接入骨架（真实可跑）

> 目录：`bin2_npc_extension/Contents/mods/bin2_npc_extension/media/lua/`
> 依赖：橙子经济（`OrangeCommunityEconomy`）+ A-Life NPC 提供方。
> 设计：**零 monkey patch 路由**；唯一 patch 是首页工厂（照抄橙子自己的 `bootstrap.lua:64-116` 手法）。

### 12.1 `shared/Bin2NpcProtocol.lua`

```lua
Bin2Npc = Bin2Npc or {}
Bin2Npc.Module = "bin2NpcExtension"          -- 关键：与 "OrangeTradingMod" 不同名
Bin2Npc.PageId = "bin2NpcRecruit"
Bin2Npc.C2S = { Hire = "Hire", Roster = "Roster" }
Bin2Npc.S2C = { Roster = "Roster", HireResult = "HireResult" }
return Bin2Npc
```

### 12.2 `client/Bin2NpcRecruitPage.lua`（页面 + 入口按钮，幂等）

```lua
require "Bin2NpcProtocol"

local function install()
    local O = OrangeTradingMod
    if not O or not O.UIPageRegistry then return end          -- 橙子还没加载，等下一轮
    local Registry, UI = O.UIPageRegistry, O.UIPrimitives
    if not Registry or not UI then return end
    if Registry.Has and Registry.Has(Bin2Npc.PageId) then return end

    local rows = {}                                          -- 由 Bin2NpcNet 填充
    Registry.Register(Bin2Npc.PageId, function(context)
        local page = O.WorkbenchListPage.Create(context, {   -- list_page.lua:77
            titleKey = "BrandName", actionKey = "Confirm",
            cardGrid = true, cardHeight = 150,
            rows = function() return rows end,                -- list_page.lua:296
            execute = function(self, row, quantity)           -- list_page.lua:128
                Bin2NpcNet.Send(Bin2Npc.C2S.Hire,
                    { npcId = tostring(row.id or ""), count = tonumber(quantity) or 1 })
            end,
        })
        return page
    end)

    -- 首页入口：包一层 factories["index"]，与橙子 bootstrap.lua:64-116 同构
    if Bin2Npc.HomeEntryInstalled then return end
    local homeId = (Registry.factories.index and "index")
        or (Registry.factories.home and "home") or nil
    local original = homeId and Registry.factories[homeId] or nil
    if type(original) ~= "function" then return end
    Bin2Npc.HomeEntryInstalled = true

    Registry.factories[homeId] = function(context)
        local page = original(context)
        if not page or page.bin2NpcButton then return page end
        local primitives = context.primitives or UI
        local button = primitives.CreateButton(0, 0, 150, 30, getText("IGUI_Bin2Npc_HomeEntry"),
            page, function(target)
                Bin2NpcNet.Send(Bin2Npc.C2S.Roster, {})
                local shell = target.context and target.context.shell
                if shell and shell.setPage then shell:setPage(Bin2Npc.PageId) end   -- shell_window.lua:497
            end, "action")
        button.ymNavId = "bin2NpcEntry"
        button:initialise(); button:instantiate(); page:addChild(button)
        page.bin2NpcButton = button

        local originalRelayout = page.relayout
        function page:relayout(rect)
            if originalRelayout then originalRelayout(self, rect) end
            local pad = (self.context.theme.Metrics.Padding or 12)
            self.bin2NpcButton:setX(pad)
            self.bin2NpcButton:setY(pad + 40)            -- 避开首页标题行，实测可调
            self.bin2NpcButton:setWidth(150)
            self.bin2NpcButton:setHeight(30)
            self.bin2NpcButton:setTitle(primitives.FitText(
                getText("IGUI_Bin2Npc_HomeEntry"), UIFont.Small, 138))
        end
        return page
    end)
end

Events.OnGameStart.Add(function() pcall(install) end)   -- 此刻所有模组文件已加载完
```

### 12.3 `client/Bin2NpcNet.lua`（自己的一层网络，含单机分支）

```lua
require "Bin2NpcProtocol"

Bin2NpcNet = Bin2NpcNet or {}
local sequence = 0

local function newRequestId(command)
    sequence = sequence + 1
    return table.concat({ command, tostring(getTimestampMs and getTimestampMs() or 0), tostring(sequence) }, ":")
end

function Bin2NpcNet.Send(command, payload)
    payload = type(payload) == "table" and payload or {}
    payload.requestId = payload.requestId or newRequestId(tostring(command))
    payload.timestamp = getTimestampMs and getTimestampMs() or 0
    if isClient and isClient() == true then
        sendClientCommand(Bin2Npc.Module, command, payload)        -- 服务端 command_router 会忽略
    else
        local player = getSpecificPlayer and getSpecificPlayer(0) or nil
        local handler = Bin2NpcServer and Bin2NpcServer[command]
        if type(handler) == "function" and player then
            pcall(handler, player, payload)                        -- 单机：直接调自己的服务端函数
        end
    end
    return true
end

-- 客户端收包（自己的 module，绝不与橙子争用）
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Bin2Npc.Module then return end
    local page = OrangeTradingMod and OrangeTradingMod.Window
    if command == Bin2Npc.S2C.Roster then
        Bin2NpcRosterRows = args.rows or {}
        if page and page.activePageId == Bin2Npc.PageId and page.refresh then page:refresh({ full = true }) end
    elseif command == Bin2Npc.S2C.HireResult then
        if OrangeTradingMod and OrangeTradingMod.ShowRadioNotice then
            OrangeTradingMod.ShowRadioNotice(getSpecificPlayer(0), getText("IGUI_Bin2Npc_HireDone"))
        end
    end
end)
```

### 12.4 `server/Bin2NpcService.lua`（扣款 + 原子性 + 自带限速/去重 + 回包）

```lua
Bin2NpcServer = Bin2NpcServer or {}
local S                                            -- = OrangeTradingModServer（延迟取，避免加载顺序问题）
local seenRequestIds, lastAcceptedAt = {}, {}
local MIN_INTERVAL_MS = 500

local function server()
    S = S or OrangeTradingModServer
    return S
end

local function reply(player, command, payload)
    if sendServerCommand then sendServerCommand(player, Bin2Npc.Module, command, payload or {}) end
end

local function duplicate(player, requestId)
    local s = server()
    local key = tostring(requestId or "")
    if key == "" then return false end
    if seenRequestIds[key] then return true end
    local now = getTimestampMs and getTimestampMs() or 0
    local playerKey = s and s.PlayerKey and s.PlayerKey(player) or tostring(player)
    if now > 0 and (lastAcceptedAt[playerKey] or 0) + MIN_INTERVAL_MS > now then return true end
    lastAcceptedAt[playerKey] = now
    seenRequestIds[key] = true
    if #seenRequestIds > 512 then seenRequestIds = { [key] = true } end   -- 粗粒度清理，够用
    return false
end

function Bin2NpcServer.Hire(player, args)
    local s = server()
    if not s or not s.IsPlayerObject or not s.IsPlayerObject(player) then return end
    if duplicate(player, args.requestId) then return end

    local count = math.max(1, math.min(10, math.floor(tonumber(args.count) or 1)))
    local unitCost = 250                                                 -- 可由自己的沙盒项覆盖
    local cost = unitCost * count

    -- 原子扣款：Pay 内部先查后扣（server/runtime_core.lua:510）
    if not s.Pay(player, cost) then
        reply(player, Bin2Npc.S2C.HireResult, { ok = false, reason = "NoMoney" })
        return
    end

    -- 这里调用 A-Life 的生成接口；失败必须原额退回
    local ok, err = pcall(Bin2NpcAlife, player, count)
    if not ok then
        s.AddCoins(player, cost)                                         -- 回滚（runtime_core.lua:502）
        reply(player, Bin2Npc.S2C.HireResult, { ok = false, reason = tostring(err) })
        return
    end
    reply(player, Bin2Npc.S2C.HireResult, { ok = true, count = count, cost = cost })
end

function Bin2NpcServer.Roster(player, args)
    local rows = Bin2NpcAlife and Bin2NpcAlife.List and Bin2NpcAlife.List(player) or {}
    reply(player, Bin2Npc.S2C.Roster, { rows = rows })
end

-- 自己的 module → 橙子的 dispatch(command_router.lua:677) 会先 return，互不干扰
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Bin2Npc.Module then return end
    local handler = Bin2NpcServer[command]
    if type(handler) ~= "function" then return end
    local ok, err = pcall(handler, player, s and s.CommandArgs and s.CommandArgs(args) or args)
    if not ok then print("[Bin2NpcExtension] command " .. tostring(command) .. " failed: " .. tostring(err)) end
end)
```

> 说明：单机下 `Events.OnClientCommand` 永远不会为我们的 module 触发（第 5.3 节），
> 所以 `Bin2NpcNet.Send` 的单机分支直接调 `Bin2NpcServer[command]` —— 同一份服务端代码，两条触发路径。

### 12.5 `media/lua/shared/Translate/CN/IG_UI.json`（自己的前缀）

```json
{ "IGUI_Bin2Npc_HomeEntry": "NPC 招募", "IGUI_Bin2Npc_HireDone": "雇佣完成" }
```

### 12.6 `mod.info` 关键字段

```
id=bin2_npc_extension
name=NPC 招募扩展
versionMin=42.2.0
require=OrangeCommunityEconomy
```

（若 `require=` 在目标版本不生效，改成运行时软依赖：上面的 `install()` 已经用
`if not O or not O.UIPageRegistry then return end` + `Events.OnGameStart` 做了容错，橙子缺失时静默不装 UI。）

---

## 13. 未确认 / 证据不足

**我读到的（有 file:line 或字节码证据）**：

1. 所有 page registry / shell / protocol / runtime_core / treasury / sandbox / translate 的结构与行号 —— 见正文。
2. `media/lua/server/**` 在单机进世界后被加载 —— `zombie/gameStates/GameLoadingState.enter()` 无条件
   `LuaManager.LoadDirBase("server")`（`projectzomboid.jar` 反汇编）。
3. 加载顺序是「按目录（shared→client→server）× 按相对路径 CASE_INSENSITIVE 排序」——
   `LuaManager.LoadDirBase` 内的 `Collections.sort(loadList, String.CASE_INSENSITIVE_ORDER)`。
4. `command_router` 的 `routes`/`register` 是 local，无公开注册 API —— `server/command_router.lua:63,134`。
5. `PAGE_DOMAINS`/`MENU`/`TABS`/`handlers`/`LOCAL_COMMAND_METHODS` 全是 local，不可追加 —— 各自行号见正文。

**我推测的（未经运行验证，写作时请当作假设）**：

1. **`Shell:setPage` 对未登记 id 一定放行**：依据是 `menuItem()` 返回 `nil` 时跳过 admin 检查（`shell_window.lua:511-519`）
   且 `enabledPage()` 默认 `true`（`:166-186`）。**若某个未在正文覆盖的分支（如 `supporterVehiclePageAllowed`）意外命中，行为会变**。
   建议实测一次 `shell:setPage("bin2NpcRecruit")`。
2. **`registry.factories["index"]` 复包手法**：橙子自己这么用（`bootstrap.lua:64-116`），但**它执行时机在文件末尾、早于我们的 `OnGameStart`**；
   如果将来橙子把 `installCommunityCenterHomeEntry` 改成延迟安装并覆盖我们的包，我们会被覆盖。**建议在 `Shell:createMenu`/`pageContext` 上再挂一道兜底**（或改用 12.2 的按钮不作为唯一入口，同时提供按键/右键入口）。
3. **首页按钮的最终坐标**：正文里 `setY(pad + 40)` 是估的（避开标题与 `homeViewButtons`，后者见 `client/ui/pages/home.lua:727`），
   橙子自己用的是「右对齐到 `homeViewButtons.classic` 左侧」（`bootstrap.lua:100-107`）。**落地前需要一次实机目视校准**。
4. **`Translator` 对同名跨模组键的合并优先级**（哪个模组胜出）：**未验证**。因此正文不建议使用 `IGUI_OrangeTradingMod_*` 前缀。
5. **`seenRequestIds` 的清理策略**在骨架里是粗粒度（超过 512 条整体重置），只保证「短时间重发被忽略」，
   不是橙子那种 64 条 FIFO + 1 小时幂等。若雇用会产生持久凭证，请照抄 `server/action_request_guard.lua:56-77` 的
   `history.order/seen` 结构 + 落盘。
6. **`Bin2NpcAlife`**（A-Life 侧接口）是占位名字，本报告未分析 A-Life 模组，需要另一轮调研确认它的生成/查询 API 与
   「NPC 归属玩家」的数据结构。
7. **`require=` 在 `mod.info` 的强制加载顺序语义**未在本轮验证（正文已给运行时容错方案）。
8. `Actions.Send` 不能用于第三方命令 —— 依据是 `Actions.IsAvailable` 只查 `Protocol.C2S`（`client/ui/actions.lua:62-74`），
   这条是**读到的事实**；但「所以第三方必须自己写 requestId 去重」是**推论**。
