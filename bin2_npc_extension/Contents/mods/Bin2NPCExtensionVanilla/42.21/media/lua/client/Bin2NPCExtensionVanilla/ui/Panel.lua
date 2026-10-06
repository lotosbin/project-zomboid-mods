--[[
    Bin2NPCExtensionVanilla :: ui/Panel（client）

    招募窗口本体：**自己用原版 ISUI 画的**，不挂在任何经济模组的界面上
    （橙子经济版与 YeseMarket 版把页面注册进对方的窗口，原版没有这样的宿主）。

    窗口类是 ISCollapsableWindowJoypad：原版带手柄支持的窗口基类
    （ISLiteratureUI 等用的就是它），标题栏/拖动/关闭按钮都是原版的。

    页面内容与两个经济口味**完全一致**（同一份 Net 协议、同一套命令）：
        名册（我的雇员）／收编（身边现成的 NPC）／中介（花钱让 A-Life 现造一个）
    差别只在钱的叫法与入口：这里的钱是原版钞票（公共层 Cash.lua 结算）。

    为什么用「一个列表 + 三个页签按钮」而不是 ISTabPanel：
    招募页的数据源与按钮状态本来就是"当前页签"的函数（名册/候选/中介三种视图共用
    一次状态推送），一个列表重建最省事，也与两个经济口味的 Page.lua 结构一一对应，
    出问题时三边可以对着看。
]]

-- 引擎 UI 基类。游戏里这些文件由 client 层自动加载，这里的 require 只是**显式声明**
-- 依赖顺序；真缺东西时不应该在加载期就报错（与两个经济口味的 Page.lua 同一写法）。
if type(require) == "function" then
    pcall(require, "ISUI/ISPanel")
    pcall(require, "ISUI/ISButton")
    pcall(require, "ISUI/ISScrollingListBox")
    pcall(require, "ISUI/ISCollapsableWindow")
    pcall(require, "ISUI/ISCollapsableWindowJoypad")
end

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间；这里 require 是
-- **显式的顺序声明**：本文件要用 Config.Net / Config.Text，Profile 负责把它们建出来。
local Config = require "Bin2NPCExtensionVanilla/Profile"
if Config == nil then return nil end      -- 公共层缺失或版本不符：Profile 已经打过日志

local Net = Config.Net
local T = Config.Text.get

local Panel = {}
Config.RecruitPanel = Panel

-- 与两个经济口味同名（公共层的日志与自检历史上会读这个 id）
Panel.ID = "bin2NpcRecruit"
Config.RecruitPage = Panel

local FONT = UIFont.Small

-- 深色面板上的配色（只求可读：原版 ISUI 的默认配色本来就是这一路）
local COLORS = {
    text = { r = 0.92, g = 0.94, b = 0.96 },
    weak = { r = 0.74, g = 0.77, b = 0.81 },
    muted = { r = 0.62, g = 0.66, b = 0.70 },
    accent = { r = 0.45, g = 0.78, b = 0.95 },
    danger = { r = 0.94, g = 0.42, b = 0.40 },
    success = { r = 0.52, g = 0.85, b = 0.55 },
    gold = { r = 1.00, g = 0.78, b = 0.32 },
}

-- 字体行高：拿不到就退回一个保守值（只影响排版，不影响功能）
local function fontHeight()
    local ok, value = pcall(function() return getTextManager():getFontHeight(FONT) end)
    if ok and tonumber(value) ~= nil then return math.max(11, math.floor(tonumber(value))) end
    return 14
end

-- 金额显示：原版钞票没有小数，统一走翻译键，方便两种语言各自自然
local function cash(value)
    return T("CurrencyAmount", tostring(math.floor(tonumber(value) or 0)))
end

local function statusColor(status)
    if status == "dead" then return COLORS.danger end
    if status == "dismissed" then return COLORS.weak end
    if status == "unpaid" then return COLORS.gold end
    return COLORS.success
end

local function rowAccent(data)
    if data.kind == "candidate" then
        return data.hostile and COLORS.danger or COLORS.success
    end
    return statusColor(data.unpaid and "unpaid" or data.status)
end

--[[
    列表：一张卡片四行字（标题 + 三行细节），与两个经济口味的卡片一一对应。

    为什么自己写 doDrawItem：原版默认只画一行（self.font 行高），我们要在一行里塞
    姓名/阵营/距离/价格四件事 —— 那样玩家不用点来点去就能挑人。
]]
-- 本口味的 UI 类**都是 local**：不该漏进 _G（公共层的自检与离线测试都会数"多出来的全局"）。
-- 想让外部（测试 / 排障）拿到就挂到 Panel 上，别依赖全局。
local Bin2NpcRecruitList = ISScrollingListBox:derive("Bin2NpcRecruitList")
Panel.RecruitList = Bin2NpcRecruitList

function Bin2NpcRecruitList:new(x, y, width, height)
    local o = ISScrollingListBox:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.font = FONT
    o.fontHgt = fontHeight()
    o.itemPadY = 4
    o.itemheight = o.fontHgt * 4 + o.itemPadY * 2
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    o.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.9 }
    o.textColor = COLORS.text
    o.selectedTextColor = COLORS.text
    return o
end

function Bin2NpcRecruitList:doDrawItem(y, item, alt)
    if not item.height then item.height = self.itemheight end
    if item.height <= 0 then return y + item.height end
    -- 视口外直接跳过（原版 doDrawItem 也这么做：列表可能有几百行）
    if (y + self:getYScroll() + item.height < 0) or (y + self:getYScroll() >= self.height) then
        return y + item.height
    end

    local data = item.item or {}
    local selected = self.selected == item.index
    local hovered = (self.mouseoverselected == item.index) and self:isMouseOver()
        and not self:isMouseOverScrollBar()
    if selected then
        self:drawSelection(0, y, self:getWidth(), item.height - 1)
    elseif hovered then
        self:drawMouseOverHighlight(0, y, self:getWidth(), item.height - 1)
    end

    local accent = data.accent or rowAccent(data)
    local x, width = 14, math.max(20, self:getWidth() - 22)
    self:drawRect(5, y + 4, 3, item.height - 8, 0.95, accent.r, accent.g, accent.b)

    local ty = y + self.itemPadY
    local line = self.fontHgt
    local title = COLORS.text
    self:drawText(tostring(data.title or item.text or ""), x, ty, title.r, title.g, title.b, 1, FONT)
    ty = ty + line
    local weak = COLORS.weak
    self:drawText(tostring(data.line1 or ""), x, ty, weak.r, weak.g, weak.b, 1, FONT)
    ty = ty + line
    local muted = COLORS.muted
    self:drawText(tostring(data.line2 or ""), x, ty, muted.r, muted.g, muted.b, 1, FONT)
    ty = ty + line
    self:drawText(tostring(data.line3 or ""), x, ty, accent.r, accent.g, accent.b, 1, FONT)

    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.35,
        self.borderColor.r, self.borderColor.g, self.borderColor.b)
    return y + item.height
end

-- ---------------------------------------------------------------- 窗口

local Bin2NpcRecruitWindow = ISCollapsableWindowJoypad:derive("Bin2NpcRecruitWindow")
Panel.Window = Bin2NpcRecruitWindow

function Bin2NpcRecruitWindow:new(x, y, width, height, player)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.title = T("PageTitle")
    o.mode = "roster"
    o.selectedUid = nil
    o.pendingMode = nil
    o.seenRevision = nil
    o:setResizable(false)
    Bin2NpcRecruitWindow.instance = o
    return o
end

function Bin2NpcRecruitWindow:makeButton(x, y, width, height, title, onclick)
    local button = ISButton:new(x, y, width, height, title, self, function() onclick() end)
    button:initialise()
    button:instantiate()
    -- 窗口固定大小，关闭锚点，免得原版窗口的 resize/anchor 逻辑把按钮拉走
    button.anchorLeft, button.anchorRight = false, false
    button.anchorTop, button.anchorBottom = false, false
    self:addChild(button)
    return button
end

function Bin2NpcRecruitWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)

    local pad, gap = 10, 8
    local fontHgt = fontHeight()
    local buttonHgt = fontHgt + 8
    local top = self:titleBarHeight() + pad
    local bottom = self.height - self:resizeWidgetHeight() - pad

    -- 左列（列表）与右列（详情 + 按钮）：左 58%，右剩下的
    local leftWidth = math.floor((self.width - pad * 2 - gap) * 0.58)
    local rightX = pad + leftWidth + gap
    local rightWidth = math.max(160, self.width - rightX - pad)

    local tabWidth = math.floor((leftWidth - gap * 2) / 3)
    local tabHeight = buttonHgt + 2
    local self_ = self
    self.tabRoster = self:makeButton(pad, top, tabWidth, tabHeight, T("TabRoster"),
        function() self_:setMode("roster") end)
    self.tabHire = self:makeButton(pad + tabWidth + gap, top, tabWidth, tabHeight, T("TabHire"),
        function() self_:setMode("hire") end)
    self.tabSummon = self:makeButton(pad + (tabWidth + gap) * 2, top, tabWidth, tabHeight,
        T("TabSummon"), function() self_:setMode("summon") end)
    self.btnRefresh = self:makeButton(rightX, top, rightWidth, tabHeight, T("Refresh"),
        function() self_:requestState(true) end)

    local listTop = top + tabHeight + gap
    self.list = Bin2NpcRecruitList:new(pad, listTop, leftWidth, math.max(80, bottom - listTop))
    self.list.target = self
    -- 原版列表的回调签名是 (self.target, 选中项)
    self.list.onmousedown = function(_, item) self_:onRowSelected(item) end
    -- 手柄 A 键：选中并直接执行当前页签的主操作（面板里的按钮仍是可导航的）
    self.list.overrideAButtonFunction = function(_, item) self_:activateRow(item) end
    self:addChild(self.list)

    -- 右侧自下而上排版：岗位行 → 主按钮 → 次按钮（两块**永远预留**，切页签时不跳）
    local actionHgt = buttonHgt + 8
    local dismissY = bottom - actionHgt
    local primaryY = dismissY - gap - actionHgt
    local modeY = primaryY - gap - buttonHgt
    local modeWidth = math.floor((rightWidth - gap * 2) / 3)
    self.btnFollow = self:makeButton(rightX, modeY, modeWidth, buttonHgt, T("ModeFollow"),
        function() self_:setPendingMode(Config.MODE_FOLLOW) end)
    self.btnGuard = self:makeButton(rightX + modeWidth + gap, modeY, modeWidth, buttonHgt,
        T("ModeGuard"), function() self_:setPendingMode(Config.MODE_GUARD) end)
    self.btnResident = self:makeButton(rightX + (modeWidth + gap) * 2, modeY, modeWidth, buttonHgt,
        T("ModeResident"), function() self_:setPendingMode(Config.MODE_RESIDENT) end)
    self.btnPrimary = self:makeButton(rightX, primaryY, rightWidth, actionHgt, "",
        function() self_:primaryAction() end)
    self.btnDismiss = self:makeButton(rightX, dismissY, rightWidth, actionHgt, T("Dismiss"),
        function() self_:dismissAction() end)

    self.detailX, self.detailWidth = rightX, rightWidth
    self.detailTop, self.detailBottom = listTop, math.max(listTop + fontHgt, modeY - 6)
    self.lineHeight = fontHgt + 2

    -- 手柄导航：两行按钮（岗位行 / 动作行）。原版 ISPanelJoypad 按行导航。
    self:clearJoypadButtonsList()
    self:insertNewListOfButtons({ self.btnFollow, self.btnGuard, self.btnResident })
    self:insertNewListOfButtons({ self.btnPrimary, self.btnDismiss })
    self.joypadIndex, self.joypadIndexY = 1, 1
    self.joypadButtons = self.joypadButtonsY[1]

    self:updateButtons()
end

--[[
    关闭：**必须**把元素从 UIManager 摘掉并清掉单例。

    原版 ISCollapsableWindow:close() 只是 setVisible(false)（ISCollapsableWindow.lua:134），
    留着实例的话下次"打开"会拿到一个还在 UIManager 里的隐藏窗口，反复开关会越积越多。
]]
function Bin2NpcRecruitWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if Bin2NpcRecruitWindow.instance == self then Bin2NpcRecruitWindow.instance = nil end
    -- 手柄焦点别留在一个已经消失的窗口上（否则摇杆会"卡住"）
    if self.playerNum ~= nil then
        pcall(setJoypadFocus, self.playerNum, nil)
    end
end

function Bin2NpcRecruitWindow:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    self.joypadIndex, self.joypadIndexY = 1, 1
    if self.joypadButtonsY and self.joypadButtonsY[1] then
        self.joypadButtons = self.joypadButtonsY[1]
        if self.joypadButtons[1] then self.joypadButtons[1]:setJoypadFocused(true) end
    end
end

function Bin2NpcRecruitWindow:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button)
end

-- ---------------------------------------------------------------- 状态

function Bin2NpcRecruitWindow:state()
    return Net.cache
end

function Bin2NpcRecruitWindow:requestState(scan)
    if self.mode == "hire" and scan == true then
        Net.send("ScanCandidates", {}, false)
    else
        Net.send("RequestState", {}, false)
    end
end

function Bin2NpcRecruitWindow:selectedContract()
    local uid = self.selectedUid
    if uid == nil then return nil end
    for _, contract in ipairs(self:state().contracts or {}) do
        if contract.uid == uid then return contract end
    end
    return nil
end

function Bin2NpcRecruitWindow:selectedCandidate()
    local uid = self.selectedUid
    if uid == nil or self.mode ~= "hire" then return nil end
    for _, candidate in ipairs(self:state().candidates or {}) do
        if candidate.uid == uid then return candidate end
    end
    return nil
end

function Bin2NpcRecruitWindow:selectedRow()
    if self.mode == "hire" then return self:selectedCandidate() end
    return self:selectedContract()
end

function Bin2NpcRecruitWindow:activeMode()
    if self.mode == "roster" then
        local contract = self:selectedContract()
        return self.pendingMode or (contract and contract.mode) or nil
    end
    return self.pendingMode or Config.defaultMode()
end

function Bin2NpcRecruitWindow:setMode(mode)
    local wanted = tostring(mode or "roster")
    if wanted ~= "roster" and wanted ~= "hire" and wanted ~= "summon" then wanted = "roster" end
    if self.mode == wanted then
        self:requestState(true)
        return
    end
    self.mode = wanted
    self.selectedUid, self.pendingMode = nil, nil
    self:requestState(true)
    self:rebuild()
end

function Bin2NpcRecruitWindow:onRowSelected(item)
    local data = type(item) == "table" and item or nil
    self.selectedUid = data and data.uid or nil
    -- 换人就把"待应用岗位"清掉：别把上一个人选的岗位带到他头上
    self.pendingMode = nil
    self:updateButtons()
end

-- 手柄 A 键：选中 + 执行主操作（鼠标玩家仍然靠下面的按钮）
function Bin2NpcRecruitWindow:activateRow(item)
    self:onRowSelected(item)
    if self.btnPrimary ~= nil and self.btnPrimary.enable then
        self:primaryAction()
    end
end

function Bin2NpcRecruitWindow:setPendingMode(mode)
    if self.mode == "roster" and self:selectedContract() == nil then return end
    self.pendingMode = Config.normalizeMode(mode)
    self:updateButtons()
end

--[[
    主操作（三个页签共用一个按钮）。

    名册页只发**变化了的**岗位 —— 旧版这里会把当前岗位再发一遍，对已经是居民的人来说
    等于请求 Jeem 再收编一次（他已经是居民 → 被拒 → 降级成跟随），玩家看到的是
    「居民化被拒…已降级为跟随」。服务端现在幂等（Service.applyMode），入口这边也别再发。
]]
function Bin2NpcRecruitWindow:primaryAction()
    if self.mode == "hire" then
        local candidate = self:selectedCandidate()
        if candidate == nil then return end
        Net.send("HireExisting", {
            uid = candidate.uid,
            mode = self.pendingMode or Config.defaultMode(),
        }, true)
    elseif self.mode == "summon" then
        Net.send("HireSpawned", { mode = self.pendingMode or Config.defaultMode() }, true)
    else
        local contract = self:selectedContract()
        if contract == nil then return end
        local wanted = self.pendingMode
        if wanted == nil or wanted == Config.normalizeMode(contract.mode) then return end
        Net.send("SetMode", { uid = contract.uid, mode = wanted }, true)
        self.pendingMode = nil
    end
end

function Bin2NpcRecruitWindow:dismissAction()
    local contract = self:selectedContract()
    if contract == nil then return end
    Net.send("Dismiss", { uid = contract.uid }, true)
    self.selectedUid = nil
    self:updateButtons()
end

function Bin2NpcRecruitWindow:rebuild()
    local list = self.list
    if list == nil then return end
    local offset = tonumber(list:getYScroll()) or 0
    list:clear()
    -- clear() 不会清 scrollHeight（原版的坑）：不清的话列表会留一条"能滚但没内容"的空白
    list:setScrollHeight(0)

    if self.mode ~= "summon" then
        local state = self:state()
        local rows
        if self.mode == "hire" then
            -- 服务端的候选快照是"请求时刻"的，可能还包含刚被雇走的人：名册里的人先滤掉
            local hired = {}
            for _, contract in ipairs(state.contracts or {}) do
                if contract.status == "active" then hired[contract.uid] = true end
            end
            rows = {}
            for _, candidate in ipairs(state.candidates or {}) do
                if hired[candidate.uid] ~= true then rows[#rows + 1] = candidate end
            end
        else
            rows = state.contracts or {}
        end

        local prices = state.prices or {}
        for _, row in ipairs(rows) do
            local title, line1, line2, line3, data
            if self.mode == "hire" then
                title = tostring(row.name or row.uid)
                line1 = T("CardFaction", tostring(row.factionId or "?"))
                line2 = T("CardDistance", tostring(row.distance or "?"))
                line3 = row.hostile and T("CardHostile")
                    or T("HireCost", cash(prices.sign or 0))
                data = { kind = "candidate", uid = row.uid, status = row.status,
                    hostile = row.hostile }
            else
                title = tostring(row.name or row.uid)
                line1 = T("CardMode", Config.Text.mode(row.mode))
                line2 = T("CardStatus", Config.Text.status(row.unpaid and "unpaid" or row.status))
                local note = row.note ~= nil and Config.Text.reason(row.note) or ""
                line3 = note ~= "" and note or T("CardHiredFor", cash(row.price or 0))
                data = { kind = "contract", uid = row.uid, status = row.status,
                    unpaid = row.unpaid }
            end
            data.title, data.line1, data.line2, data.line3 = title, line1, line2, line3
            local added = list:addItem(title, data)
            if self.selectedUid ~= nil and row.uid == self.selectedUid then
                list.selected = added.itemindex
            end
        end
        list:setYScroll(offset)
    end
    --[[
        记下"重建时看到的状态版本"。

        为什么：单机/主机下 `Net.send` 是直连（dispatch 的返回值当场应用），切页签时
        `requestState` 已经把 revision 推进了，紧接着这次显式 rebuild 就是"最新状态"了；
        不记的话下一帧 `syncState()` 会认为"状态变了"再重建一次 —— 列表白重建一遍
        （滚动位置也会被多恢复一次）。联机下状态是异步回来的，这条不影响正确性。
    ]]
    self.seenRevision = tonumber(self:state().revision) or 0
    self:updateButtons()
end

local function setButtonMode(button, active)
    button.ymNavActive = active == true
    button.borderColor = active and { r = 0.45, g = 0.78, b = 0.95, a = 1 }
        or { r = 0.4, g = 0.4, b = 0.4, a = 1 }
end

function Bin2NpcRecruitWindow:updateButtons()
    local state = self:state()
    local capabilities = state.capabilities or {}
    local limits = state.limits or { max = 0, used = 0 }
    local prices = state.prices or {}
    local contract = self:selectedContract()
    local mode = self:activeMode()

    setButtonMode(self.tabRoster, self.mode == "roster")
    setButtonMode(self.tabHire, self.mode == "hire")
    setButtonMode(self.tabSummon, self.mode == "summon")

    setButtonMode(self.btnFollow, mode == Config.MODE_FOLLOW)
    setButtonMode(self.btnGuard, mode == Config.MODE_GUARD)
    setButtonMode(self.btnResident, mode == Config.MODE_RESIDENT)
    self.btnResident:setVisible(capabilities.jeem == true)

    local full = (tonumber(limits.used) or 0) >= (tonumber(limits.max) or 0)
    local ready = capabilities.enabled == true and capabilities.alife == true
        and capabilities.economy == true

    if self.mode == "hire" then
        self.btnPrimary:setTitle(T("HireCost", cash(prices.sign or 0)))
        self.btnPrimary:setEnable(ready and not full and self:selectedCandidate() ~= nil)
        self.btnDismiss:setVisible(false)
    elseif self.mode == "summon" then
        self.btnPrimary:setTitle(T("SummonCost", cash(prices.spawn or 0)))
        self.btnPrimary:setEnable(ready and not full)
        self.btnDismiss:setVisible(false)
    else
        self.btnPrimary:setTitle(T("ApplyMode"))
        self.btnPrimary:setEnable(ready and contract ~= nil and self.pendingMode ~= nil
            and self.pendingMode ~= Config.normalizeMode(contract.mode))
        self.btnDismiss:setVisible(contract ~= nil)
        self.btnDismiss:setEnable(contract ~= nil)
    end
end

--[[
    状态自动刷新：Net.cache 带一个自增 revision，变了就重建列表。

    联机下服务端是异步推状态回来的，没有这一步玩家点了按钮会"没反应"（直到手动刷新）；
    只在 update 里比对 revision，重建本身有变化才发生，所以不会每帧重排。
]]
function Bin2NpcRecruitWindow:syncState()
    local revision = tonumber(self:state().revision) or 0
    if revision ~= self.seenRevision then
        self.seenRevision = revision
        self:rebuild()
    end
end

function Bin2NpcRecruitWindow:update()
    ISCollapsableWindowJoypad.update(self)
    self:syncState()
end

-- ---------------------------------------------------------------- 绘制

function Bin2NpcRecruitWindow:drawLines(x, width, startY, lines)
    local y = startY
    local limit = self.detailBottom or self.height
    for _, entry in ipairs(lines) do
        local height = entry.lineHeight or self.lineHeight
        if y + height > limit then return y end
        local color = entry.color or COLORS.muted
        local size = entry.font or FONT
        self:drawText(tostring(entry.text or ""), x, y, color.r, color.g, color.b, 1, size)
        y = y + height + (tonumber(entry.gap) or 0)
    end
    return y
end

function Bin2NpcRecruitWindow:render()
    ISCollapsableWindowJoypad.render(self)

    local state = self:state()
    local capabilities = state.capabilities or {}
    local limits = state.limits or { max = 0, used = 0 }
    local prices = state.prices or {}
    local x, width = self.detailX or 400, self.detailWidth or 260

    local lines = {
        { text = T("PageTitle"), color = COLORS.text, font = UIFont.Medium, lineHeight = self.lineHeight + 6, gap = 4 },
        { text = T("Wallet", cash(state.coins or 0)), color = COLORS.gold },
        { text = T("Slots", tostring(limits.used or 0), tostring(limits.max or 0)), color = COLORS.muted },
        { text = T("WageLine", cash(prices.wage or 0)), color = COLORS.muted, gap = 4 },
    }

    -- 依赖状态：缺什么就明说，别让玩家对着没反应的按钮猜
    if capabilities.enabled ~= true then
        lines[#lines + 1] = { text = T("WarnDisabled"), color = COLORS.danger }
    end
    if capabilities.economy ~= true then
        lines[#lines + 1] = { text = T("WarnNoEconomy"), color = COLORS.danger }
    end
    if capabilities.alife ~= true then
        lines[#lines + 1] = { text = T("WarnNoAlife"), color = COLORS.danger }
    end
    if capabilities.jeem ~= true then
        lines[#lines + 1] = { text = T("WarnNoJeem"), color = COLORS.weak }
    end

    if self.mode == "summon" then
        for _, key in ipairs({ "SummonHint1", "SummonHint2", "SummonHint3" }) do
            lines[#lines + 1] = { text = T(key), color = COLORS.muted, gap = 4 }
        end
        self:drawLines(x, width, self.detailTop or 60, lines)
    else
        local row = self:selectedRow()
        if row == nil then
            lines[#lines + 1] = {
                text = T(self.mode == "hire" and "HireHint" or "RosterHint"),
                color = COLORS.muted, gap = 4,
            }
        else
            lines[#lines + 1] = { text = T("DetailName", tostring(row.name or row.uid)),
                color = COLORS.text, gap = 4 }
            lines[#lines + 1] = { text = T("DetailFaction", tostring(row.factionId or "?")),
                color = COLORS.muted }
            lines[#lines + 1] = { text = T("DetailProfile", tostring(row.profileId or "?")),
                color = COLORS.muted }
            if self.mode == "hire" then
                lines[#lines + 1] = { text = T("DetailDistance", tostring(row.distance or "?")),
                    color = COLORS.muted }
                lines[#lines + 1] = {
                    text = row.hostile and T("DetailHostile") or T("DetailFriendly"),
                    color = row.hostile and COLORS.danger or COLORS.success,
                }
            else
                lines[#lines + 1] = { text = T("DetailMode", Config.Text.mode(row.mode)),
                    color = COLORS.muted }
                lines[#lines + 1] = {
                    text = T("DetailStatus",
                        Config.Text.status(row.unpaid and "unpaid" or row.status)),
                    color = statusColor(row.unpaid and "unpaid" or row.status),
                }
                if row.note ~= nil then
                    lines[#lines + 1] = { text = T("DetailNote", Config.Text.reason(row.note)),
                        color = COLORS.weak }
                end
                if row.unpaid then
                    lines[#lines + 1] = { text = T("DetailUnpaid"), color = COLORS.danger }
                end
            end
        end
        self:drawLines(x, width, self.detailTop or 60, lines)
    end

    -- 手柄焦点框（原版窗口的惯用画法）
    if self.joyfocus and self.joypadButtonsY then
        local children = self:getVisibleChildren(self.joypadIndexY)
        local child = children[self.joypadIndex]
        if child then
            self:drawRectBorder(child.x, child.y, child.width, child.height, 0.5, 0.2, 1.0, 1.0)
            self:drawRectBorder(child.x - 1, child.y - 1, child.width + 2, child.height + 2,
                0.5, 0.2, 1.0, 1.0)
        end
    end
end

-- ---------------------------------------------------------------- 对外入口（ui/Icon.lua 与热键用）

--[[
    打开窗口。已经有窗口时只把它提到最前（不重建，免得丢掉玩家选中的那一行）。

    窗口实例不存在时新建；player 为空时用公共层的 localPlayer() —— 热键路径上
    调用方可能拿不到 player。
]]
function Panel.open(player)
    if Bin2NpcRecruitWindow.instance ~= nil then
        local window = Bin2NpcRecruitWindow.instance
        window:setVisible(true)
        window:bringToTop()
        window:requestState(true)
        return window
    end
    if player == nil then player = Config.localPlayer and Config.localPlayer() or nil end
    if player == nil then return nil end

    local width, height = 780, 540
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.max(10, math.floor((screenW - width) / 2))
    local y = math.max(10, math.floor((screenH - height) / 2))

    local window = Bin2NpcRecruitWindow:new(x, y, width, height, player)
    window:initialise()
    window:addToUIManager()
    window:requestState(true)
    window:syncState()
    -- 手柄：打开就把焦点交给窗口（原版侧边栏自己完全没有手柄导航）
    if window.playerNum ~= nil then
        pcall(setJoypadFocus, window.playerNum, window)
    end
    return window
end

function Panel.isOpen()
    local window = Bin2NpcRecruitWindow.instance
    return window ~= nil and window:getIsVisible() == true
end

function Panel.close()
    if Bin2NpcRecruitWindow.instance ~= nil then
        Bin2NpcRecruitWindow.instance:close()
    end
end

-- 图标与热键都走它：开着就关，关着就开
function Panel.toggle(player)
    if Panel.isOpen() then
        Panel.close()
        return false
    end
    return Panel.open(player) ~= nil
end

return Panel
