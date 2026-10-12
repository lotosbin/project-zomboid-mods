--[[
    Bin2NPCExtensionYese :: ui/Entry（client）

    把招募页接进 **YeseMarket** 的界面。注意它与橙子经济版的**策略不同**：

      * 橙子经济版：包首页工厂 `registry.factories.index`，在首页塞一个按钮
        （那是对方 `ui/bootstrap.lua` 自己示范过的做法）。
      * YeseMarket 版：导航栏**插一行**。它的导航是 `client/ui/shell.lua` 里的 `local NAVIGATION`
        表驱动的（第三方加不进去），但壳把建好的按钮与度量存在实例字段上
        （`self.navButtons` / `self.navigationViewport` / `self.navigationButtonHeight` /
        `self.navigationGap` / `self.navigationContentHeight`），所以包住
        `YeseMarket.UIShell:buildNavigation` 与 `:layoutNavigationItems` 就能挤进一行。
      * 页面本身仍走公开的 `YeseMarket.UIPageRegistry.Register(id, factory)`。
      * `YeseMarket.UIShell:setPage(id)` 对**不在 NAVIGATION 里**的 id 默认放行：
        `navigationEnabled()` 的兜底是 `return true`，`navigationMetadata()` 返回 nil（无权限门），
        这正是导航按钮回调要做的事（`self:setPage(button.pageId)`）。
      * 打开窗口：`YeseMarket.Open(playerNum)` **只接一个参数**（不像橙子经济的 `Open(n, pageId)`），
        所以入口是"先开窗 → 再 `YeseMarket.Window:setPage(我们的 id)`"。
      * 入口有两个（分工不同，见下面「侧边栏图标」一段）：
        ① YeseMarket 左侧导航栏最后一行「NPC 招募」——进我们的页面；
        ② **原版左侧竖排图标栏**最下面一个交易站图标 —— 点一下开关**幸存者交易站窗口**
           （YeseMarket 全库没有任何按键绑定，交易站本身没有快捷入口）。
      * 兜底：**Ctrl+Alt+N 永远可用**，而且它直达①的招募页 —— 万一上游把导航字段改名、
        或原版侧边栏被别的模组换掉，热键照开。
]]

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间；这里 require 是
-- **显式的顺序声明**：本文件要用 Config.Text，Profile 负责把它建出来。
local Config = require "Bin2NPCExtensionYese/Profile"
if Config == nil then return nil end      -- 公共层缺失或版本不符：Profile 已经打过日志

require "Bin2NPCExtensionYese/ui/Page"

local T = Config.Text.get

local Entry = {}
Config.Entry = Entry

Entry.NAV_ID = Config.RecruitPage.ID

-- ---------------------------------------------------------------- 侧边栏图标

--[[
    入口②：把**幸存者交易站**挂到原版左侧竖排图标栏（ISEquippedItem —— 心/背包/建造那一列）
    的最下面。挂接的实现与全部引擎侧约束在公共层 `Bin2NPCExtensionCore/Sidebar.lua`
    （另见 docs/research/vanilla-sidebar-entry.md §2），这里只交本口味的一张 spec。

    为什么这一格是"交易站"而不是"招募页"：
      * YeseMarket 全库没有任何按键绑定 —— 它自己的入口只有右击菜单里的「打开幸存者交易站」，
        最常用的那一屏反而没有快捷入口；
      * 这一列图标的语义就是"打开某个窗口"（心 → 健康、背包、建造、地图）。玩家点它是想进
        交易站，所以点一下开关**交易站窗口**（标题就是 IGUI_YeseMarket_Title = 幸存者交易站）；
        我们的招募页在交易站的左侧导航里一行就能点到；
      * **Ctrl+Alt+N 仍然直达招募页**（Entry.open）：热键与图标各司其职，谁坏了都不影响另一个。
]]

--- 交易站窗口（YeseMarket.Window 是它唯一的窗口句柄；close() 会把它置回 nil）
local function marketWindow()
    local ui = Config.economy()
    local window = ui ~= nil and ui.Window or nil
    if window ~= nil and type(window.getIsVisible) == "function" then
        local ok, visible = pcall(window.getIsVisible, window)
        if ok and visible == true then return window end
    end
    return nil
end

--- 交易站窗口开着吗（侧边栏图标的两态贴图、以及"这一下是开还是关"都看它）
function Entry.isMarketOpen()
    return marketWindow() ~= nil
end

--[[
    开关交易站（侧边栏图标点一下走这里）：开着就关，关着就开。

    关：`UIShell:close()` 会 setVisible(false) + removeFromUIManager + `YeseMarket.Window = nil`
        （client/ui/shell.lua:991-1029），所以下一次点击会走"开"的分支。
    开：`YeseMarket.Open(playerNumber)` 只吃一个参数、不返回窗口
        （client/event_handlers.lua:299），窗口句柄只能从 `ui.Window` 上取。
]]
function Entry.toggleMarket(playerNumber)
    local window = marketWindow()
    if window ~= nil then
        return (pcall(function() window:close() end))
    end
    local ui = Config.economy()
    if ui == nil or type(ui.Open) ~= "function" then return false end
    local number = math.max(0, math.floor(tonumber(playerNumber) or 0))
    return (pcall(ui.Open, number))
end

--[[
    交给公共层的那张 spec。
    * 贴图名 `Trade`：10 张两态图标（五档 x On/Off），装在本口味自己的 media/ui/Sidebar/ 下，
      由 tools/make_icons.py 生成（画的是遮阳篷 + 柜台 + 金币的交易摊位）。
    * `id` 是按钮的 internal（点击守卫）：公共层按它把按钮存在面板上，两个口味同时启用也不撞。
]]
local MARKET_SPEC = {
    id = "BIN2NPCTRADE",
    texture = "Trade",
    tooltip = T("IconTooltip"),
    log = "sidebar icon hooked into ISEquippedItem (opens the YeseMarket trading station)",
    isOpen = function() return Entry.isMarketOpen() end,
    toggle = function(playerNumber) return Entry.toggleMarket(playerNumber) end,
}

-- ---------------------------------------------------------------- 打开面板

local function playerNumberOf(player)
    if player ~= nil and player.getPlayerNum ~= nil then
        local ok, value = pcall(player.getPlayerNum, player)
        if ok then return math.max(0, math.floor(tonumber(value) or 0)) end
    end
    return 0
end

--[[
    打开我们的页面。优先用"当前已开的窗口"（不重新开窗），否则 `YeseMarket.Open` 后再切页。
]]
function Entry.open(playerNumber)
    local ui = Config.economy()
    if ui == nil then return false end
    local number = math.max(0, math.floor(tonumber(playerNumber) or 0))

    local window = ui.Window
    if window ~= nil and window.getIsVisible and window:getIsVisible() then
        if type(window.setPage) == "function" then
            local ok = pcall(window.setPage, window, Entry.NAV_ID)
            if ok then return true end
        end
        return false
    end

    if type(ui.Open) == "function" then
        local ok = pcall(ui.Open, number)
        if ok then
            window = ui.Window
            if window ~= nil and type(window.setPage) == "function" then
                local switched = pcall(window.setPage, window, Entry.NAV_ID)
                if switched then return true end
            end
            return true                       -- 窗口开了，只是没切到我们的页
        end
    end
    return false
end

local function openPage(target)
    local context = target and target.context or nil
    local player = context and context.player or nil
    Entry.open(playerNumberOf(player))
end

-- ---------------------------------------------------------------- 导航栏插行

local function installNavRow(ui)
    if Entry.navInstalled == true then return true end
    local shell = ui.UIShell
    if type(shell) ~= "table" then return false end
    local build, layout = shell.buildNavigation, shell.layoutNavigationItems
    if type(build) ~= "function" or type(layout) ~= "function" then return false end

    local primitives = ui.UIPrimitives
    if type(primitives) ~= "table" or type(primitives.CreateButton) ~= "function" then return false end

    Entry.navInstalled = true
    Config.log("hooking YeseMarket.UIShell navigation for the recruit page")

    shell.buildNavigation = function(self, ...)
        build(self, ...)
        -- 自己造一个导航按钮。字段缺失就什么都不做（宁可没有按钮，也不要污染对方的界面）
        local viewport, buttons = self.navigationViewport, self.navButtons
        if viewport == nil or type(buttons) ~= "table" then return end
        if buttons[Entry.NAV_ID] ~= nil then return end
        -- 用自己的翻译表：YeseMarket.Text 会强制加 `IGUI_YeseMarket_` 前缀，
        -- 拿我们的键去查会原样返回键名（游戏里按钮名就会显示成 IGUI_YeseMarket_EntryButton）。
        local title = Config.Text.get("EntryButton")
        local button = primitives.CreateButton(0, 0, 1, 1, title, self, function(target, clicked)
            if clicked ~= nil and clicked.pageId ~= nil then
                target:setPage(clicked.pageId)
            end
        end, "muted")
        button.pageId, button.ymNavId = Entry.NAV_ID, Entry.NAV_ID
        button:initialise()
        viewport:addChild(button)
        buttons[Entry.NAV_ID] = button
    end

    shell.layoutNavigationItems = function(self, ...)
        layout(self, ...)
        local button = type(self.navButtons) == "table" and self.navButtons[Entry.NAV_ID] or nil
        local viewport = self.navigationViewport
        if button == nil or viewport == nil then return end
        local height = tonumber(self.navigationButtonHeight) or 30
        local gap = tonumber(self.navigationGap) or 5
        local y = math.max(0, (tonumber(self.navigationContentHeight) or 0) - gap)
        button:setX(4)
        button:setY(y)
        button:setWidth(math.max(1, (tonumber(viewport.width) or 0) - 17))
        button:setHeight(height)
        local contentHeight = y + height + gap
        self.navigationContentHeight = math.max(tonumber(viewport.height) or 0, contentHeight)
        viewport:setScrollHeight(self.navigationContentHeight)
    end
    return true
end

-- ---------------------------------------------------------------- 安装

--[[
    注册页面 + 插导航行 + 装侧边栏图标。返回 true 表示三件事都装好了；
    false 表示还没就绪（YeseMarket 或原版侧边栏比我们晚）—— 调用方（公共层 ClientBootstrap）
    会按秒重试，试满之后打印口味自己的 uiHint。
]]
function Entry.install()
    local ui = Config.economy()
    if ui == nil then return false end
    local registry = ui.UIPageRegistry
    if type(registry) ~= "table" or type(registry.factories) ~= "table" then return false end

    if type(registry.Has) == "function" then
        if registry.Has(Entry.NAV_ID) ~= true then
            local ok, err = pcall(registry.Register, Entry.NAV_ID, Config.RecruitPage.Create)
            if not ok then
                Config.warn("page registration failed: " .. tostring(err))
                return false
            end
        end
    elseif registry.factories[Entry.NAV_ID] == nil then
        return false
    end

    --[[
        侧边栏图标**不依赖 YeseMarket**（原版那一列随时都在），但它跟导航行一起算作"入口装完"：
        返回 false 会让公共层继续重试。万一原版侧边栏被别的模组换掉（HUD 替换），这条
        WARN 会明确写出来，而 Ctrl+Alt+N 照常可用（热键不经过这里）。
    ]]
    local sidebarReady = Config.Sidebar.install(MARKET_SPEC) == true
    if sidebarReady ~= true and Entry.sidebarWarned ~= true then
        Entry.sidebarWarned = true
        Config.warn("the vanilla sidebar is not ready yet; the trading-station icon is not installed")
    end

    if Entry.navInstalled == true then return sidebarReady end
    if installNavRow(ui) then
        Config.always("recruit page registered; YeseMarket navigation row and sidebar icon installed")
        return sidebarReady
    end
    return false
end

return Entry
