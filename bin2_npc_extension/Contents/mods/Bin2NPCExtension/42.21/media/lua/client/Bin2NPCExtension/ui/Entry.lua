--[[
    Bin2NPCExtension :: ui/Entry（client）

    把招募页接进橙子社区经济的界面。只用两个挂接点：

      1. **公开的页面注册表** `OrangeTradingMod.UIPageRegistry.Register(id, factory)`
         —— 对方明确给扩展用的 API；重复注册会 error，所以先 Has() 判重。
      2. **首页工厂包装** —— 与对方自己的 `ui/bootstrap.lua:64-116` 给"社区中心"加入口
         的做法完全一致（幂等标志 + 手工初始化按钮 + 包 relayout 定位）。

    不碰它任何 local 表（MENU / TABS 都加不进，也不需要）。
]]

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间；这里 require 是
-- **显式的顺序声明**：本文件要用 Config.Text，Profile 负责把它建出来。
local Config = require "Bin2NPCExtension/Profile"
if Config == nil then return nil end      -- 公共层缺失或版本不符：Profile 已经打过日志

require "Bin2NPCExtension/ui/Page"

local T = Config.Text.get

local Entry = {}
Config.Entry = Entry

-- 首页按钮的宽度（跟随首页布局缩放，但不小于 118，保证中文标题还能看）
local function buttonWidth(page)
    return math.max(118, math.min(170, math.floor(math.max(118, page.width * 0.18))))
end

local function openPage(target)
    local context = target and target.context or nil
    local player = context and context.player or nil
    local number = 0
    if player ~= nil and player.getPlayerNum ~= nil then
        local ok, value = pcall(player.getPlayerNum, player)
        if ok then number = math.max(0, math.floor(tonumber(value) or 0)) end
    end
    local ui = Config.economy()
    if ui ~= nil and type(ui.Open) == "function" then
        local ok = pcall(ui.Open, number, Config.RecruitPage.ID)
        if ok then return end
    end
    if context ~= nil and context.shell ~= nil and type(context.shell.setPage) == "function" then
        pcall(context.shell.setPage, context.shell, Config.RecruitPage.ID)
    end
end

--[[
    注册页面 + 给首页加一个入口按钮。

    返回 true 表示"页面已注册且入口已装好"；false 表示橙子经济还没就绪（稍后重试）。
]]
function Entry.install()
    local ui = Config.economy()
    if ui == nil then return false end
    local registry = ui.UIPageRegistry
    if type(registry) ~= "table" or type(registry.factories) ~= "table" then return false end

    -- 1) 注册页面（幂等：重复 Register 会 error）
    if type(registry.Has) == "function" then
        if registry.Has(Config.RecruitPage.ID) ~= true then
            local ok, err = pcall(registry.Register, Config.RecruitPage.ID, Config.RecruitPage.Create)
            if not ok then
                Config.warn("page registration failed: " .. tostring(err))
                return false
            end
        end
    elseif registry.factories[Config.RecruitPage.ID] == nil then
        return false
    end

    -- 2) 首页入口（只包一次）
    if Entry.installed == true then return true end
    local homeId = type(registry.factories.index) == "function" and "index"
        or (type(registry.factories.home) == "function" and "home" or nil)
    if homeId == nil then return false end

    local original = registry.factories[homeId]
    if type(original) ~= "function" then return false end
    Entry.installed = true
    Config.always("recruit page registered; home entry installed")

    registry.factories[homeId] = function(context)
        local page = original(context)
        if page == nil then return page end
        if Config.enabled() ~= true then return page end
        local primitives = context.primitives
        if type(primitives) ~= "table" or type(primitives.CreateButton) ~= "function" then return page end
        if page.bin2NpcButton ~= nil then return page end

        local button = primitives.CreateButton(0, 0, 140, 30, T("EntryButton"), page, openPage, "muted")
        button.tooltip = T("EntryTooltip")
        button.ymNavId = "bin2NpcRecruit"
        button:initialise()
        button:instantiate()
        page:addChild(button)
        page.bin2NpcButton = button

        --[[
            定位：贴在首页那一排"视图/入口"控件**最左边那个**的左侧。

            游戏实测踩过一次：原来只认 `communityCenterButton` 当锚点，而它在
            `IsCommunityCenterEnabled()==false` 时根本不存在 —— 于是回退到"贴右边缘"，
            正好压在对方的「卡片」视图按钮上，两个标题叠成了「NPC 招募: 卡片」。
            现在把三个可能的锚点都收集起来取最左，实在都没有就贴左边缘（不与右侧控件抢位）。
        ]]
        local originalRelayout = page.relayout
        function page:relayout(rect)
            if originalRelayout then originalRelayout(self, rect) end
            local metrics = self.context and self.context.theme and self.context.theme.Metrics or nil
            local pad = tonumber(metrics and metrics.Padding) or 12
            local gap = tonumber(metrics and metrics.Gap) or 12

            local anchors = { self.communityCenterButton }
            local switches = self.homeViewButtons
            if type(switches) == "table" then
                anchors[#anchors + 1] = switches.classic
                anchors[#anchors + 1] = switches.launcher
            end
            local leftMost, sameRow = nil, nil
            for _, candidate in ipairs(anchors) do
                local cx = tonumber(candidate and candidate.x)
                if cx ~= nil and (leftMost == nil or cx < leftMost) then
                    leftMost = cx
                    sameRow = candidate
                end
            end

            local width = buttonWidth(self)
            local height = tonumber(sameRow and sameRow.height) or 30
            local y = tonumber(sameRow and sameRow.y) or pad
            local x
            if leftMost ~= nil then
                x = math.max(pad, leftMost - gap - width)
            else
                -- 一个锚点都没有：贴左上，绝不压右侧那排控件
                x, y = pad, pad
            end

            self.bin2NpcButton:setX(x)
            self.bin2NpcButton:setY(y)
            self.bin2NpcButton:setWidth(width)
            self.bin2NpcButton:setHeight(height)
            self.bin2NpcButton:setTitle(primitives.FitText(T("EntryButton"), UIFont.Small, width - 12))
            local reserved = x - gap - pad
            if self.homeTitleWidth ~= nil and reserved > 40 then
                self.homeTitleWidth = math.max(40, math.min(self.homeTitleWidth, reserved))
            end
        end
        return page
    end
    return true
end

--[[
    按快捷键或"被外部调用"打开招募面板（给热键用）。
]]
function Entry.open(playerNumber)
    local ui = Config.economy()
    local number = math.max(0, math.floor(tonumber(playerNumber) or 0))
    if ui ~= nil and type(ui.Open) == "function" then
        local ok = pcall(ui.Open, number, Config.RecruitPage.ID)
        if ok then return true end
    end
    return false
end

return Entry
