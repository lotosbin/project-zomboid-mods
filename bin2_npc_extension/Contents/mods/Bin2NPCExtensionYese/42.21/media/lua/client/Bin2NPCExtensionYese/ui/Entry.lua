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
      * 兜底：**Ctrl+Alt+N 永远可用**。万一上游把导航字段改名，按钮会静默消失，但热键照开。
]]

require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Text"
require "Bin2NPCExtensionYese/ui/Page"

local Config = Bin2NPCExtensionYese
local T = Config.Text.get

local Entry = {}
Config.Entry = Entry

Entry.NAV_ID = Config.RecruitPage.ID

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
    注册页面 + 插导航行。返回 true 表示两边都装好了；false 表示 YeseMarket 还没就绪（稍后重试）。
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

    if Entry.navInstalled == true then return true end
    if installNavRow(ui) then
        Config.always("recruit page registered; YeseMarket navigation row installed")
        return true
    end
    return false
end

return Entry
