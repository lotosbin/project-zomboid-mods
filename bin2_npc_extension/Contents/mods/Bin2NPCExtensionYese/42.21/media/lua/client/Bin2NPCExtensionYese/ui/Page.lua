--[[
    Bin2NPCExtensionYese :: ui/Page（client）

    招募面板。与橙子经济版的**行为相同、容器不同**，所以这个文件在变体里是**独立实现**：

      * 橙子经济有 `UIPrimitives.CreateCardGrid`（带 `drawCard`/`onCardSelected`/`setOffset`），
        YeseMarket **没有**；它只有 `CreateList`（`ISScrollingListBox` 的派生类，见
        `client/ui/primitives.lua:443/620`）。所以这里改用 `CreateList` + 自定义 `doDrawItem`，
        选中回调走 `list.onmousedown` + `list.target`（`client/ui/pages/goods.lua:432-435` 的写法）。
      * YeseMarket 也**没有** `GetDensityMetrics`（那是橙子经济的），改为用
        `UITheme.FontHeight(UIFont.Small, 16)` 自己算行高/按钮高（`client/ui/theme.lua:81`）。
      * `UITheme.DrawRoundedSurface(ui, x, y, w, h, {fill=…, border=…, alpha=…, borderAlpha=…, radius=…})`
        的选项名与橙子版略有差别（它用 `alpha`，橙子用 `fillAlpha`）—— 见 `client/ui/theme.lua:278-291`。

    其余的页面契约（`relayout` / `activate` / `deactivate` / `render` / `refresh`、文本区与按钮块
    互不重叠的几何关系）与橙子版保持一致，所以两边可以共用同一套离线几何断言。
]]

if type(require) == "function" then
    pcall(require, "ISUI/ISPanel")
    pcall(require, "ui/page_registry")
end
require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Text"
require "Bin2NPCExtensionYese/Net"

local Config = Bin2NPCExtensionYese
local Net = Config.Net

local Page = {}
Config.RecruitPage = Page

Page.ID = "bin2NpcRecruit"

local T = Config.Text.get
local ROW_HEIGHT = 92

local function add(parent, child)
    child:initialise()
    child:instantiate()
    parent:addChild(child)
    return child
end

local function coins(value)
    if Config.economy() ~= nil and type(Config.economy().FormatCoins) == "function" then
        return Config.economy().FormatCoins(tonumber(value) or 0)
    end
    return string.format("%.2f", math.floor((tonumber(value) or 0) * 100 + 0.5) / 100)
end

local function statusColor(colors, status)
    if status == "dead" then return colors.Danger end
    if status == "dismissed" then return colors.TextWeak end
    if status == "unpaid" then return colors.Warning or colors.Danger end
    return colors.Success
end

-- YeseMarket 没有 GetDensityMetrics：按字体高度自己算一套（缺 theme 时给保守值）
local function density(context)
    local fontHeight = 16
    local theme = context and context.theme or nil
    if theme ~= nil and type(theme.FontHeight) == "function" then
        local ok, value = pcall(theme.FontHeight, UIFont.Small, 16)
        if ok and tonumber(value) ~= nil then fontHeight = math.max(12, math.floor(tonumber(value))) end
    end
    return {
        lineHeight = math.max(18, fontHeight + 5),
        buttonHeight = math.max(30, fontHeight + 14),
    }
end

function Page.Create(context)
    local ui = context.primitives
    local theme = context.theme
    local colors = theme.Colors
    local metrics = density(context)

    local page = ISPanel:new(0, 0, 1, 1)
    page.background, page.border = false, false
    page.context = context
    page.mode = "roster"
    page.selectedUid = nil
    page.selectedCandidate = nil
    page.pendingMode = nil
    page.lastRect = nil
    page.lineHeight = metrics.lineHeight

    page.tabRoster = add(page, ui.CreateButton(0, 0, 1, 30, T("TabRoster"), page,
        function(target) target:setMode("roster") end, "action"))
    page.tabHire = add(page, ui.CreateButton(0, 0, 1, 30, T("TabHire"), page,
        function(target) target:setMode("hire") end, "muted"))
    page.tabSummon = add(page, ui.CreateButton(0, 0, 1, 30, T("TabSummon"), page,
        function(target) target:setMode("summon") end, "muted"))
    page.refreshButton = add(page, ui.CreateButton(0, 0, 1, 30, T("Refresh"), page,
        function(target) target:requestState(true) end, "muted"))

    page.list = add(page, ui.CreateList(0, 0, 1, 1))
    page.list.itemheight = ROW_HEIGHT
    page.list.target = page
    page.list.onmousedown = function(target) target:onListSelected() end
    page.list.doDrawItem = function(list, y, entry) return page:drawRow(list, y, entry) end

    page.modeFollow = add(page, ui.CreateButton(0, 0, 1, 28, T("ModeFollow"), page,
        function(target) target:chooseMode(Config.MODE_FOLLOW) end, "muted"))
    page.modeGuard = add(page, ui.CreateButton(0, 0, 1, 28, T("ModeGuard"), page,
        function(target) target:chooseMode(Config.MODE_GUARD) end, "muted"))
    page.modeResident = add(page, ui.CreateButton(0, 0, 1, 28, T("ModeResident"), page,
        function(target) target:chooseMode(Config.MODE_RESIDENT) end, "muted"))

    page.primary = add(page, ui.CreateButton(0, 0, 1, 34, "", page,
        function(target) target:primaryAction() end, "action"))
    page.dismiss = add(page, ui.CreateButton(0, 0, 1, 34, T("Dismiss"), page,
        function(target) target:dismissAction() end, "danger"))

    function page:state()
        return Net.cache
    end

    function page:requestState(scan)
        if self.mode == "hire" and scan == true then
            Net.send("ScanCandidates", {}, false)
        else
            Net.send("RequestState", {}, false)
        end
    end

    function page:setMode(mode)
        self.mode = tostring(mode or "roster")
        self.selectedUid, self.selectedCandidate = nil, nil
        self.list.selected = 0
        self:requestState(true)
        self:rebuild()
        if self.lastRect ~= nil then self:relayout(self.lastRect) end
    end

    function page:chooseMode(mode)
        local wanted = Config.normalizeMode(mode)
        if self.mode == "roster" then
            local contract = self:selectedContract()
            if contract == nil then return end
            Net.send("SetMode", { uid = contract.uid, mode = wanted }, true)
        else
            self.pendingMode = wanted
            self:updateActions()
        end
    end

    function page:selectedContract()
        local uid = self.selectedUid
        if uid == nil then return nil end
        for _, contract in ipairs(self:state().contracts or {}) do
            if contract.uid == uid then return contract end
        end
        return nil
    end

    function page:activeMode()
        if self.mode == "roster" then
            local contract = self:selectedContract()
            return contract and contract.mode or nil
        end
        return self.pendingMode or Config.defaultMode()
    end

    -- 列表选中（IScrollingListBox 的 onmousedown 把 list.target 也就是本页传进来）
    function page:onListSelected()
        local entry = self.list.items[self.list.selected]
        local row = entry and entry.item or nil
        self.selectedUid, self.selectedCandidate = nil, nil
        if row ~= nil then
            if self.mode == "hire" then
                self.selectedCandidate = row
            else
                self.selectedUid = row.uid
            end
        end
        self:updateActions()
    end

    function page:primaryAction()
        local state = self:state()
        if self.mode == "hire" then
            local candidate = self.selectedCandidate
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
            Net.send("SetMode", {
                uid = contract.uid,
                mode = self.pendingMode or contract.mode,
            }, true)
        end
    end

    function page:dismissAction()
        local contract = self:selectedContract()
        if contract == nil then return end
        Net.send("Dismiss", { uid = contract.uid }, true)
        self.selectedUid = nil
        self.list.selected = 0
    end

    -- 一行卡片：四行文本 + 左侧强调条（颜色对应岗位/状态）
    function page:drawRow(list, y, entry)
        local data = entry and entry.item or nil
        local height = tonumber(entry and entry.height) or list.itemheight
        if type(data) ~= "table" then return y + height end

        local accent = data.kind == "candidate"
            and (data.hostile and colors.Danger or colors.Success)
            or statusColor(colors, data.status)
        if list.selected == entry.index then
            theme.DrawRoundedSurface(list, 2, y + 1, math.max(0, list.width - 6), math.max(0, height - 3), {
                fill = colors.Selection, border = colors.Action, radius = 5,
            })
        end
        list:drawRect(8, y + 8, 3, math.max(0, height - 16), 0.95, accent.r, accent.g, accent.b)

        local textX = 18
        local textWidth = math.max(1, list.width - 34)
        local lineHeight = self.lineHeight
        local textY = y + 8
        list:drawText(ui.FitText(tostring(data.title or ""), UIFont.Small, textWidth), textX, textY,
            colors.Text.r, colors.Text.g, colors.Text.b, 1, UIFont.Small)
        textY = textY + lineHeight
        list:drawText(ui.FitText(tostring(data.line1 or ""), UIFont.Small, textWidth), textX, textY,
            colors.TextWeak.r, colors.TextWeak.g, colors.TextWeak.b, 1, UIFont.Small)
        textY = textY + lineHeight
        list:drawText(ui.FitText(tostring(data.line2 or ""), UIFont.Small, textWidth), textX, textY,
            colors.TextMuted.r, colors.TextMuted.g, colors.TextMuted.b, 1, UIFont.Small)
        textY = textY + lineHeight
        list:drawText(ui.FitText(tostring(data.line3 or ""), UIFont.Small, textWidth), textX, textY,
            accent.r, accent.g, accent.b, 1, UIFont.Small)
        entry.tooltip = data.tooltip
        return y + height
    end

    function page:rebuild()
        local state = self:state()
        -- 服务端每 8 秒左右会推一次状态，重建时保留滚动位置
        local keepScroll = 0
        if type(self.list.getYScroll) == "function" then
            local ok, value = pcall(self.list.getYScroll, self.list)
            if ok and tonumber(value) ~= nil then keepScroll = tonumber(value) end
        end
        self.list:clear()

        local rows
        if self.mode == "hire" then
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

        for _, row in ipairs(rows) do
            local title, line1, line2, line3, tooltip
            if self.mode == "hire" then
                title = tostring(row.name or row.uid)
                line1 = T("CardFaction", tostring(row.factionId or "?"))
                line2 = T("CardDistance", tostring(row.distance or "?"))
                line3 = row.hostile and T("CardHostile") or T("HireCost", coins(state.prices and state.prices.sign or 0))
                tooltip = title .. "\n" .. tostring(row.profileId or "") .. "\n" .. line3
            else
                title = tostring(row.name or row.uid)
                line1 = T("CardMode", Config.Text.mode(row.mode))
                line2 = T("CardStatus", Config.Text.status(row.unpaid and "unpaid" or row.status))
                local extra = row.note ~= nil and Config.Text.reason(row.note) or ""
                line3 = extra ~= "" and extra or T("CardHiredFor", coins(row.price or 0))
                tooltip = title .. "\n" .. line1 .. "\n" .. line2 .. "\n" .. line3
            end
            self.list:addItem(title, {
                kind = self.mode == "hire" and "candidate" or "contract",
                uid = row.uid, status = row.status, hostile = row.hostile,
                title = title, line1 = line1, line2 = line2, line3 = line3, tooltip = tooltip,
            })
        end

        if type(self.list.setYScroll) == "function" then pcall(self.list.setYScroll, self.list, keepScroll) end
        self:updateActions()
    end

    function page:updateActions()
        local state = self:state()
        local capabilities = state.capabilities or {}
        local limits = state.limits or { max = 0, used = 0 }
        local prices = state.prices or {}
        local contract = self:selectedContract()
        local mode = self:activeMode()

        self.tabRoster.variant = self.mode == "roster" and "action" or "muted"
        self.tabHire.variant = self.mode == "hire" and "action" or "muted"
        self.tabSummon.variant = self.mode == "summon" and "action" or "muted"

        self.modeFollow.ymNavActive = mode == Config.MODE_FOLLOW
        self.modeGuard.ymNavActive = mode == Config.MODE_GUARD
        self.modeResident.ymNavActive = mode == Config.MODE_RESIDENT
        self.modeResident:setVisible(capabilities.jeem == true)

        local full = (tonumber(limits.used) or 0) >= (tonumber(limits.max) or 0)
        local ready = capabilities.enabled == true and capabilities.alife == true
            and capabilities.economy == true

        if self.mode == "hire" then
            self.primary:setTitle(T("HireCost", coins(prices.sign or 0)))
            self.primary:setEnable(ready and not full and self.selectedCandidate ~= nil)
            self.dismiss:setVisible(false)
        elseif self.mode == "summon" then
            self.primary:setTitle(T("SummonCost", coins(prices.spawn or 0)))
            self.primary:setEnable(ready and not full)
            self.dismiss:setVisible(false)
        else
            self.primary:setTitle(T("ApplyMode"))
            self.primary:setEnable(ready and contract ~= nil)
            self.dismiss:setVisible(contract ~= nil)
            self.dismiss:setEnable(contract ~= nil)
        end
    end

    function page:refresh()
        self:rebuild()
    end

    function page:syncState()
        local revision = tonumber(self:state().revision) or 0
        if self.seenRevision ~= revision then
            self.seenRevision = revision
            self:rebuild()
        end
    end

    function page:activate()
        self:setVisible(true)
        self:requestState(true)
        self.seenRevision = tonumber(self:state().revision) or 0
        self:rebuild()
    end

    function page:deactivate()
        self:setVisible(false)
    end

    --[[
        右侧面板自下而上排版（与橙子版同一套几何契约：文本区止于模式行上方，
        按钮块永远预留两块高度，切页签不跳）。
    ]]
    function page:relayout(rect)
        rect = rect or self.lastRect or { x = 0, y = 0, w = self.width, h = self.height }
        local rectW = tonumber(rect.w) or tonumber(rect.width) or self.width
        local rectH = tonumber(rect.h) or tonumber(rect.height) or self.height
        self.lastRect = { x = rect.x, y = rect.y, w = rectW, h = rectH }
        self:setX(rect.x)
        self:setY(rect.y)
        self:setWidth(rectW)
        self:setHeight(rectH)

        local pad, gap = 12, 8
        local tabHeight = metrics.buttonHeight
        local refreshWidth = 110
        local tabsWidth = math.max(1, math.floor((self.width - pad * 2 - refreshWidth - gap * 4) / 3))
        self.tabRoster:setX(pad); self.tabRoster:setY(10)
        self.tabRoster:setWidth(tabsWidth); self.tabRoster:setHeight(tabHeight)
        self.tabHire:setX(pad + tabsWidth + gap); self.tabHire:setY(10)
        self.tabHire:setWidth(tabsWidth); self.tabHire:setHeight(tabHeight)
        self.tabSummon:setX(pad + (tabsWidth + gap) * 2); self.tabSummon:setY(10)
        self.tabSummon:setWidth(tabsWidth); self.tabSummon:setHeight(tabHeight)
        self.refreshButton:setX(self.width - pad - refreshWidth); self.refreshButton:setY(10)
        self.refreshButton:setWidth(refreshWidth); self.refreshButton:setHeight(tabHeight)

        local listTop = 10 + tabHeight + 12
        local leftWidth = math.max(320, math.floor(self.width * 0.62))
        self.list:setX(pad); self.list:setY(listTop)
        self.list:setWidth(leftWidth - pad)
        self.list:setHeight(math.max(120, self.height - listTop - pad))

        local rightX = leftWidth + gap
        local rightWidth = math.max(180, self.width - rightX - pad)
        self.detailX, self.detailY, self.detailW = rightX, listTop, rightWidth

        local actionHeight = 34
        local modeHeight = math.max(26, tabHeight - 6)
        local actionBlock = actionHeight * 2 + gap
        local modeY = math.max(listTop, self.height - pad - actionBlock - gap - modeHeight)
        local primaryY = math.max(modeY + modeHeight + gap, self.height - pad - actionBlock)
        local dismissY = primaryY + actionHeight + gap

        local modeWidth = math.max(1, math.floor((rightWidth - gap * 2) / 3))
        self.modeFollow:setX(rightX); self.modeFollow:setY(modeY)
        self.modeFollow:setWidth(modeWidth); self.modeFollow:setHeight(modeHeight)
        self.modeGuard:setX(rightX + modeWidth + gap); self.modeGuard:setY(modeY)
        self.modeGuard:setWidth(modeWidth); self.modeGuard:setHeight(modeHeight)
        self.modeResident:setX(rightX + (modeWidth + gap) * 2); self.modeResident:setY(modeY)
        self.modeResident:setWidth(modeWidth); self.modeResident:setHeight(modeHeight)

        self.primary:setX(rightX); self.primary:setY(primaryY)
        self.primary:setWidth(rightWidth); self.primary:setHeight(actionHeight)
        self.dismiss:setX(rightX); self.dismiss:setY(dismissY)
        self.dismiss:setWidth(rightWidth); self.dismiss:setHeight(actionHeight)

        self.textTop = listTop
        self.textBottom = math.max(listTop + self.lineHeight, modeY - 6)
    end

    function page:drawLines(x, width, startY, lines)
        local y = startY
        local limit = self.textBottom or (self.height or 600)
        local lineHeight = self.lineHeight
        for _, entry in ipairs(lines) do
            if y + lineHeight > limit then return y end
            local color = entry.color or colors.TextMuted
            local font = entry.font or UIFont.Small
            self:drawText(ui.FitText(tostring(entry.text or ""), font, width), x, y,
                color.r, color.g, color.b, 1, font)
            y = y + lineHeight + (tonumber(entry.gap) or 0)
        end
        return y
    end

    function page:render()
        self:syncState()
        local state = self:state()
        local capabilities = state.capabilities or {}
        local limits = state.limits or { max = 0, used = 0 }
        local prices = state.prices or {}
        local x, y, w = self.detailX or 400, self.textTop or self.detailY or 60, self.detailW or 300

        local lines = {
            { text = T("PageTitle"), color = colors.Text, font = UIFont.Medium, gap = 6 },
            { text = T("Wallet", coins(state.coins or 0)), color = colors.Currency },
            { text = T("Slots", tostring(limits.used or 0), tostring(limits.max or 0)),
              color = colors.TextMuted },
            { text = T("WageLine", coins(prices.wage or 0)), color = colors.TextMuted, gap = 4 },
        }

        if capabilities.enabled ~= true then
            lines[#lines + 1] = { text = T("WarnDisabled"), color = colors.Danger }
        end
        if capabilities.economy ~= true then
            lines[#lines + 1] = { text = T("WarnNoEconomy"), color = colors.Danger }
        end
        if capabilities.alife ~= true then
            lines[#lines + 1] = { text = T("WarnNoAlife"), color = colors.Danger }
        end
        if capabilities.jeem ~= true then
            lines[#lines + 1] = { text = T("WarnNoJeem"), color = colors.TextWeak }
        end

        if self.mode == "summon" then
            for _, key in ipairs({ "SummonHint1", "SummonHint2", "SummonHint3" }) do
                lines[#lines + 1] = { text = T(key), color = colors.TextMuted }
            end
            self:drawLines(x, w, y, lines)
            return
        end

        local row = self.mode == "hire" and self.selectedCandidate or self:selectedContract()
        if row == nil then
            lines[#lines + 1] = {
                text = T(self.mode == "hire" and "HireHint" or "RosterHint"),
                color = colors.TextMuted, gap = 4,
            }
            self:drawLines(x, w, y, lines)
            return
        end

        lines[#lines + 1] = { text = T("DetailName", tostring(row.name or row.uid)),
            color = colors.Text, gap = 4 }
        lines[#lines + 1] = { text = T("DetailFaction", tostring(row.factionId or "?")),
            color = colors.TextMuted }
        lines[#lines + 1] = { text = T("DetailProfile", tostring(row.profileId or "?")),
            color = colors.TextMuted }
        if self.mode == "hire" then
            lines[#lines + 1] = { text = T("DetailDistance", tostring(row.distance or "?")),
                color = colors.TextMuted }
            lines[#lines + 1] = {
                text = row.hostile and T("DetailHostile") or T("DetailFriendly"),
                color = row.hostile and colors.Danger or colors.Success,
            }
        else
            lines[#lines + 1] = { text = T("DetailMode", Config.Text.mode(row.mode)),
                color = colors.TextMuted }
            lines[#lines + 1] = {
                text = T("DetailStatus", Config.Text.status(row.unpaid and "unpaid" or row.status)),
                color = statusColor(colors, row.unpaid and "unpaid" or row.status),
            }
            if row.note ~= nil then
                lines[#lines + 1] = { text = T("DetailNote", Config.Text.reason(row.note)),
                    color = colors.TextWeak }
            end
            if row.unpaid then
                lines[#lines + 1] = { text = T("DetailUnpaid"), color = colors.Danger }
            end
        end
        self:drawLines(x, w, y, lines)
    end

    page:setVisible(false)
    return page
end

return Page
