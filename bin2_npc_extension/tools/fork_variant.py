#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从「橙子社区经济」版本生成/校验同物品里的**另一个口味**的模组（当前：YeseMarket 版）。

为什么用生成器而不是手抄一份
--------------------------
同一个工坊物品里放两个模组（`Bin2NPCExtension` 与 `Bin2NPCExtensionYese`），
它们的差别只有"UI 容器 + 钱包"这一层：A-Life / Jeem 适配、契约模型、维护循环、命令路由**完全同源**。
手抄一份的代价是"上游一改就得改两处"，而最容易改的恰恰是 A-Life 的适配层。

所以：**变体目录 100% 由本脚本产出**，人只改本脚本里的替换表（和 per-file 补丁）。
`--check` 会重新生成到临时目录并与磁盘上的变体逐字节比较 —— 只要有人手改了变体目录里的文件就会报差异，
这就是防分叉的守卫。

用法：
    python3 tools/fork_variant.py --check        # 只校验（CI/提交前跑）
    python3 tools/fork_variant.py --write        # 重新生成变体
    python3 tools/fork_variant.py --check --verbose
"""

from __future__ import annotations

import argparse
import difflib
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)                       # bin2_npc_extension/
MODS_DIR = os.path.join(ITEM_DIR, "Contents", "mods")
SOURCE_MOD = "Bin2NPCExtension"
TARGET_MOD = "Bin2NPCExtensionYese"
VERSION_DIR = "42.21"

# ---------------------------------------------------------------------------
# 替换表：顺序很重要（长的/带前缀的先替换）
# ---------------------------------------------------------------------------
GLOBAL_SUBS = [
    # 代码标识符：先长后短，避免 OrangeTradingMod 先命中把 OrangeTradingModServer 切坏
    ("OrangeTradingModServer", "YeseMarketServer"),
    ("OrangeTradingMod", "YeseMarket"),
    ("OrangeCommunityEconomy", "YeseMarket"),
    ("IGUI_OrangeTradingMod_", "IGUI_YeseMarket_"),
    # 我们的命名空间（含文本前缀 IGUI_Bin2NPCExtension_ → IGUI_Bin2NPCExtensionYese_）
    ("Bin2NPCExtension", TARGET_MOD),
    # 事实性数字/文字：工坊 id、对方名字、对方货币叫法（YeseMarket 的 UI 里叫「金币」）
    ("3777900792", "3735641567"),
    ("橙子社区经济", "YeseMarket"),
    ("社区货币", "金币"),
    # 英文散文/日志里的残留
    ("Orange Community Economy", "YeseMarket"),
    ("the Orange economy UI", "the YeseMarket UI"),
    ("Orange Economy", "YeseMarket"),
]

# ---------------------------------------------------------------------------
# per-file 补丁（在全局替换之后逐条字面替换；文件不存在就跳过）
# key 是相对模组版本目录的路径
# ---------------------------------------------------------------------------
FILE_PATCHES = {
    "mod.info": [
        # 标题/描述要人写清楚，不能靠替换拼出来
        ("name=Project A-Life NPC招募 (bin2_npc_extension)(YeseMarket)",
         "name=YeseMarket NPC 招募 (bin2_npc_extension)(A-Life/Jeem)"),
        ("description=在「YeseMarket」里开一家佣兵中介",
         "description=在「YeseMarket / 夜市市场」里开一家佣兵中介"),
    ],
    # 简体中文里"金币"更自然（YeseMarket 自己的 UI 也是这么写的）
    "media/lua/shared/Translate/CN/IG_UI.json": [
        ("金币：%1", "金币：%1"),
    ],
}


# ---------------------------------------------------------------------------
# 整文件覆盖：**策略不同**的文件不靠替换，直接给变体写一份
# （Entry.lua 就是这种：橙子经济版包首页工厂，YeseMarket 版往导航栏插一行）
# ---------------------------------------------------------------------------
FILE_OVERRIDES = {
    # 容器不同：橙子版用 UIPrimitives.CreateCardGrid（YeseMarket 没有这个原语），
    # YeseMarket 版改用 CreateList + doDrawItem，密度也自己算（它没有 GetDensityMetrics）。
    "media/lua/client/Bin2NPCExtension/ui/Page.lua": r"""--[[
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
-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间；这里 require 是
-- **显式的顺序声明**：本文件要用 Config.Net / Config.Text，Profile 负责把它们建出来。
local Config = require "Bin2NPCExtensionYese/Profile"
if Config == nil then return nil end      -- 公共层缺失或版本不符：Profile 已经打过日志

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
        self.pendingMode = nil
        self.list.selected = 0
        self:requestState(true)
        self:rebuild()
        if self.lastRect ~= nil then self:relayout(self.lastRect) end
    end

    function page:chooseMode(mode)
        local wanted = Config.normalizeMode(mode)
        if self.mode == "roster" and self:selectedContract() == nil then return end
        self.pendingMode = wanted
        self:updateActions()
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
            return self.pendingMode or (contract and contract.mode) or nil
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
        self.pendingMode = nil
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
            local wanted = self.pendingMode
            if wanted == nil or wanted == Config.normalizeMode(contract.mode) then return end
            Net.send("SetMode", { uid = contract.uid, mode = wanted }, true)
            self.pendingMode = nil
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
            self.primary:setEnable(ready and contract ~= nil
                and self.pendingMode ~= nil
                and self.pendingMode ~= Config.normalizeMode(contract.mode))
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
""",
    # 入口策略不同：橙子版包首页工厂，YeseMarket 版往导航栏插一行（见文件头注释）。
    # 这个文件是**手写**的变体实现，不走替换 —— --check 仍会守住它与生成器一致。
    "media/lua/client/Bin2NPCExtension/ui/Entry.lua": r"""--[[
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

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间；这里 require 是
-- **显式的顺序声明**：本文件要用 Config.Text，Profile 负责把它建出来。
local Config = require "Bin2NPCExtensionYese/Profile"
if Config == nil then return nil end      -- 公共层缺失或版本不符：Profile 已经打过日志

require "Bin2NPCExtensionYese/ui/Page"

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
""",
}


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def read_bytes(path):
    with open(path, "rb") as handle:
        return handle.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


# ---------------------------------------------------------------------------
# 区域替换：把 [start_anchor, end_anchor) 之间的内容整段换掉（锚点本身保留/丢弃见实现）
# 比"整文件覆盖"小得多，又能表达"这一段策略不同"
# ---------------------------------------------------------------------------
REGION_PATCHES = {}


def apply_regions(rel_path, text):
    for start_anchor, end_anchor, replacement in REGION_PATCHES.get(rel_path, []):
        start = text.find(start_anchor)
        if start < 0:
            raise SystemExit("%s: 找不到区域起点锚点 %r" % (rel_path, start_anchor[:40]))
        end = text.find(end_anchor, start)
        if end < 0:
            raise SystemExit("%s: 找不到区域终点锚点 %r" % (rel_path, end_anchor[:40]))
        text = text[:start] + replacement + text[end:]
    return text


# 必须在全局替换**之前**做的替换（用于把"兄弟模组的 id"翻过来：
# 全局替换会把 Bin2NPCExtension → Bin2NPCExtensionYese，直接改会在字面量上叠加）
PRE_SUBS_PATCHES = {
    # 兄弟模组的 id 要写成"**另一个**口味"。这里不能直接写字面量：
    # GLOBAL_SUBS 随后会把 Bin2NPCExtension 再切一次，于是 sibling 变成自己 ——
    # 这正是历史上真实发生过的 bug（YeseMarket 版把 sibling 写成了
    # "Bin2NPCExtensionYese"，导致重招被解雇/阵亡的 NPC 误报"已被其他玩家雇走"）。
    # 所以先换成哨兵"\x00SIBLING\x00"，全局替换之后在 PROTECT_AFTER 里还原成
    # "Bin2NPCExtension"。tools/check_base.py 会把"sibling 不能指向自己"当断言守着。
    "media/lua/shared/Bin2NPCExtension/Profile.lua": [
        ('sibling = "Bin2NPCExtensionYese"', 'sibling = "\x00SIBLING\x00"'),
    ],
}

# ---------------------------------------------------------------------------
# 全局替换的"幸存者"
# ---------------------------------------------------------------------------
# GLOBAL_SUBS 把 Bin2NPCExtension 换成 Bin2NPCExtensionYese，会连带切坏公共层的字面量：
#     Bin2NPCExtensionBase -> Bin2NPCExtensionYeseBase   （公共层模组 id，mod.info 的 require=）
#     Bin2NPCExtensionCore -> Bin2NPCExtensionYeseCore   （公共层命名空间，require 路径）
# 替换期间先换成控制字符哨兵，替换完再还原。哨兵不可能出现在源码里。
PROTECT_BEFORE = [
    ("Bin2NPCExtensionBase", "\x00BASE\x00"),
    ("Bin2NPCExtensionCore", "\x00CORE\x00"),
]
PROTECT_AFTER = [
    ("\x00BASE\x00", "Bin2NPCExtensionBase"),
    ("\x00CORE\x00", "Bin2NPCExtensionCore"),
    ("\x00SIBLING\x00", "Bin2NPCExtension"),
]


def transform(rel_path, text):
    if rel_path in FILE_OVERRIDES:
        return FILE_OVERRIDES[rel_path]
    for old, new in PRE_SUBS_PATCHES.get(rel_path, []):
        text = text.replace(old, new)
    for old, new in PROTECT_BEFORE:
        text = text.replace(old, new)
    for old, new in GLOBAL_SUBS:
        text = text.replace(old, new)
    for old, new in PROTECT_AFTER:
        text = text.replace(old, new)
    for old, new in FILE_PATCHES.get(rel_path, []):
        text = text.replace(old, new)
    return apply_regions(rel_path, text)


TEXT_EXT = (".lua", ".json", ".txt", ".info", ".md", ".js", ".sh")

# test 19 的入口断言按 flavour 不同（见文件末尾的 REGION_PATCHES 填充）


def rename_path(rel):
    """路径里的 Lua 模块目录名（Bin2NPCExtension/…）也必须跟着改名，否则 require 找不到文件。"""
    parts = [part.replace(SOURCE_MOD, TARGET_MOD) for part in rel.split(os.sep)]
    return os.path.join(*parts)


def generate_source_tree(dest_root):
    """把源模组版本目录整棵转成目标变体，写到 dest_root/<TARGET_MOD>/<版本目录>。"""
    src_version_root = os.path.join(MODS_DIR, SOURCE_MOD, VERSION_DIR)
    if not os.path.isdir(src_version_root):
        raise SystemExit("源模组版本目录不存在：%s" % src_version_root)
    count = 0
    for dirpath, _, filenames in os.walk(src_version_root):
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, src_version_root)
            dest_rel = os.path.join(TARGET_MOD, VERSION_DIR, rename_path(rel))
            dest = os.path.join(dest_root, dest_rel)
            if name.lower().endswith(TEXT_EXT):
                write(dest, transform(rel, read(src)))
            else:                                   # 二进制（poster.png 等）原样复制
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(src, dest)
            count += 1
    return count


def generate_test_tree(dest_root):
    """测试套件同样由替换生成，这样 `--check` 也能守住"测试与变体不同步"。"""
    src_test = os.path.join(HERE, "test")
    if not os.path.isdir(src_test):
        return 0
    count = 0
    for dirpath, dirnames, filenames in os.walk(src_test):
        dirnames[:] = [d for d in dirnames if d != "node_modules"]
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, src_test)
            dest = os.path.join(dest_root, rel)
            if name.lower().endswith(TEXT_EXT) or name in ("package.json",):
                write(dest, transform(rel, read(src)))
            count += 1
    return count


def compare_tree(a_root, b_root, verbose):
    """逐文件比较两棵树（a=磁盘现状，b=刚生成）。返回差异描述列表。"""
    problems = []

    def snapshot(root):
        files = {}
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "node_modules"]
            for name in filenames:
                full = os.path.join(dirpath, name)
                files[os.path.relpath(full, root)] = full
        return files

    a_files, b_files = snapshot(a_root), snapshot(b_root)
    for rel in sorted(set(a_files) | set(b_files)):
        if rel not in a_files:
            problems.append("缺失（生成器会写但磁盘上没有）：%s" % rel)
            continue
        if rel not in b_files:
            problems.append("多余（磁盘上有但生成器不产出）：%s" % rel)
            continue
        left_raw, right_raw = read_bytes(a_files[rel]), read_bytes(b_files[rel])
        if left_raw != right_raw:
            problems.append("内容不一致：%s" % rel)
            if verbose:
                try:
                    left = left_raw.decode("utf-8")
                    right = right_raw.decode("utf-8")
                except UnicodeDecodeError:
                    problems.append("    （二进制文件，跳过逐行 diff）")
                    continue
                diff = difflib.unified_diff(
                    left.splitlines(), right.splitlines(),
                    fromfile="磁盘/" + rel, tofile="生成/" + rel, lineterm="")
                for line in list(diff)[:24]:
                    problems.append("    " + line)
    return problems


REGION_PATCHES["mock_env.lua"] = [
    (
        "    YeseMarketServer.EconomyLoaded = true",
        "M.setBalance = function(value)",
        '    YeseMarketServer.EconomyLoaded = true\n\n    -- ===== YeseMarket 版专有：Open(playerNum) + Window:setPage(id) + UIShell 导航钩子 =====\n    -- 这三件事与橙子版的差异见 docs/research/yese-integration-hooks.md：\n    --   * Open(playerNum) 只吃一个参数、不返回窗口（client/event_handlers.lua:299）\n    --   * 切页要自己 YeseMarket.Window:setPage(id)（client/ui/shell.lua:726；未进 NAVIGATION 的 id 默认放行）\n    --   * 导航由 shell.lua:32 的 local NAVIGATION 构建，第三方加不进去 ——\n    --     但壳把按钮与度量放在实例字段上，所以我们包 buildNavigation / layoutNavigationItems 插一行\n    YeseMarket.UIPrimitives = YeseMarket.UIPrimitives or {}\n    if type(YeseMarket.UIPrimitives.CreateButton) ~= "function" then\n        function YeseMarket.UIPrimitives.CreateButton(x, y, width, height, title, target, callback, variant)\n            local button = ISButton:new(x, y, width, height)\n            button.title, button.target = title, target\n            button.callback, button.variant = callback, variant\n            function button:click()\n                if type(self.callback) == "function" then return self.callback(self.target, self) end\n            end\n            return button\n        end\n    end\n\n    -- 重建一个干净的假壳（每个用例开头调一次，避免上一轮的包装残留）\n    function M.resetShell()\n        YeseMarket.Window = nil\n        local Shell = {}\n        function Shell:buildNavigation()\n            local viewport = { width = 220, height = 400, children = {} }\n            function viewport:addChild(child) self.children[#self.children + 1] = child end\n            function viewport:setScrollHeight(value) self.scrollHeight = value end\n            function viewport:setYScroll(value) self.yScroll = value end\n            function viewport:getYScroll() return 0 end\n            self.navigationViewport = viewport\n            self.navButtons = {}\n            self.navigationButtonHeight = 30\n            self.navigationGap = 5\n            self.navigationContentHeight = 0\n            return true\n        end\n        function Shell:layoutNavigationItems() self.layoutCalls = (self.layoutCalls or 0) + 1 end\n        function Shell:setPage(pageId)\n            record("UIShell.setPage", { pageId = tostring(pageId or "") })\n            self.activePageId = tostring(pageId or "")\n            return true\n        end\n        YeseMarket.UIShell = Shell\n        return Shell\n    end\n    M.resetShell()\n\n    function YeseMarket.Open(playerNum)\n        record("YeseMarket.Open", { number = tonumber(playerNum) or 0 })\n        local window = {}\n        function window:getIsVisible() return self.visible == true end\n        function window:setPage(pageId)\n            record("YeseMarket.Window.setPage", { pageId = tostring(pageId or "") })\n            self.activePageId = tostring(pageId or "")\n            M.state.opened[#M.state.opened + 1] = { number = tonumber(playerNum) or 0,\n                pageId = tostring(pageId or "") }\n            return true\n        end\n        function window:bringToTop() return self end\n        function window:clampToScreen() return self end\n        window.visible = true\n        YeseMarket.Window = window\n        return window\n    end\nend\n\n',
    ),
]

REGION_PATCHES["test_recruit.lua"] = [
    (
        '    -- 重置成"橙子经济刚加载完"的样子，再重新装一次入口',
        "    local primitives = {}",
        '    --[[\n        YeseMarket 版的入口策略是**导航栏插一行**（橙子版才是包首页工厂 `factories.index`），\n        所以这里换成对应断言：钩子把按钮塞进 `self.navButtons`，点它走 `self:setPage(我们的 id)`；\n        另外 `Entry.open()` 走"`Open(number)` → `Window:setPage(id)`"两步（YeseMarket 的 Open 只吃一个参数）。\n    ]]\n    registry.factories = {}\n    registry.order = {}\n    Config.Entry.installed = false\n    Config.Entry.navInstalled = false\n    M.resetShell()\n\n    local installed = Config.Entry.install()\n    M.assert_eq(installed, true, "Entry.install() returned true")\n    M.assert_eq(registry.Has("bin2NpcRecruit"), true, "UIPageRegistry.Has(\'bin2NpcRecruit\')")\n    local ids, idCount = {}, 0\n    for _, id in ipairs(registry.Ids()) do ids[id] = (ids[id] or 0) + 1 idCount = idCount + 1 end\n    M.assert_eq(ids.bin2NpcRecruit, 1, "the recruit page was registered exactly once")\n    M.assert_eq(idCount, 1, "only the recruit page was registered by Entry.install")\n    local ok, err = pcall(registry.Register, "bin2NpcRecruit", function() end)\n    M.assert_eq(ok, false, "registering the same page twice raises (idempotence relies on Has)")\n\n    -- 包了 YeseMarket.UIShell 的 buildNavigation / layoutNavigationItems\n    local shell = ui.UIShell\n    M.assert_truthy(type(shell) == "table", "YeseMarket.UIShell present")\n    M.assert_truthy(type(shell.buildNavigation) == "function", "buildNavigation is hooked")\n    local instance = setmetatable({}, { __index = shell })\n    instance:buildNavigation()\n    M.assert_truthy(type(instance.navButtons) == "table", "mock shell built its navButtons")\n    local navButton = instance.navButtons["bin2NpcRecruit"]\n    M.assert_truthy(navButton ~= nil, "the recruit page got its own navigation row")\n    M.assert_eq(navButton and navButton.pageId, "bin2NpcRecruit", "nav button carries the page id")\n    instance:layoutNavigationItems()\n    M.assert_truthy(navButton and tonumber(navButton.y) ~= nil and navButton.y >= 0,\n        "the injected nav row is positioned by layoutNavigationItems")\n\n    -- 幂等：再调一次 buildNavigation 不会插第二行\n    local rowsBefore = 0\n    for _, child in ipairs(instance.navigationViewport.children) do\n        if child.ymNavId == "bin2NpcRecruit" then rowsBefore = rowsBefore + 1 end\n    end\n    instance:buildNavigation()\n    local rowsAfter = 0\n    for _, child in ipairs(instance.navigationViewport.children) do\n        if child.ymNavId == "bin2NpcRecruit" then rowsAfter = rowsAfter + 1 end\n    end\n    M.assert_eq(rowsAfter, rowsBefore, "the nav row is not injected twice")\n\n    -- 点击导航行 -> shell 切到我们的页面\n    M.state.opened = {}\n    navButton:click()\n    local switched = M.calls_named("UIShell.setPage")\n    M.assert_truthy(#switched >= 1, "clicking the nav row calls shell:setPage")\n    M.assert_eq(switched[#switched] and switched[#switched].pageId, "bin2NpcRecruit",\n        "…with our page id")\n\n    -- Entry.open：窗口没开时先 Open(number) 再切页；已开则只切页\n    ui.Window = nil\n    M.state.opened = {}\n    local opensBefore = M.count_calls("YeseMarket.Open")\n    M.assert_eq(Config.Entry.open(0), true, "Entry.open() with no window open returns true")\n    M.assert_truthy(M.count_calls("YeseMarket.Window.setPage") >= 1, "Entry.open switched the window with Window:setPage")\n    M.assert_eq(M.count_calls("YeseMarket.Open"), opensBefore + 1, "…and it called Open(playerNum)")\n    local openCall = M.calls_named("YeseMarket.Open")\n    M.assert_eq(openCall[#openCall] and openCall[#openCall].number, 0, "Open got the player number")\n    M.assert_eq(Config.Entry.open(0), true, "Entry.open() on an already-open window returns true")\n    M.assert_eq(M.count_calls("YeseMarket.Open"), opensBefore + 1,\n        "…and it did NOT open a second window (only setPage)")\n\n',
    ),
]

REGION_PATCHES["test_recruit.lua"].append(
    (
        "    local page = registry.factories.index(context)",
        "    -- Page.Create 的页面契约",
        "    -- （入口这一段的断言已经在上面 YeseMarket 段落里做过：橙子版此处是\n"
        "    --   「包首页工厂 + page.bin2NpcButton」，YeseMarket 版没有对应物）\n\n",
    ),
)


# ==== Yese 变体：mock 必须忠实于 YeseMarket 的真实 UI 原语（见脚本注释）====
FILE_PATCHES.setdefault("test_recruit.lua", []).extend([
    (
        '    function primitives.GetDensityMetrics(font)\n        return { lineHeight = 21, buttonHeight = 34, fontHeight = 16 }\n    end\n',
        '    -- YeseMarket 的 UIPrimitives **没有** GetDensityMetrics（那是橙子经济的原语），\n    -- 所以 mock 也不提供：页面要是再依赖它，测试会当场炸而不是等到游戏里。\n',
    ),
    (
        '    function primitives.CreateCardGrid(x, y, width, height, options) return list end',
        '    -- YeseMarket 只有 CreateList（IScrollingListBox 的派生类），没有 CreateCardGrid\n    function primitives.CreateList(x, y, width, height) return list end',
    ),
    (
        '    function list:setOffset(value) self.offset = math.max(0, tonumber(value) or 0) end\n    function list:getYScroll() return -self.offset end\n',
        '    function list:setOffset(value) self.offset = math.max(0, tonumber(value) or 0) end\n    function list:getYScroll() return self.yScroll or 0 end\n    function list:setYScroll(value) self.yScroll = tonumber(value) or 0 end\n',
    ),
    (
        '        local entry = { text = tostring(label or ""), item = item, index = #self.items + 1 }',
        '        local entry = { text = tostring(label or ""), item = item, index = #self.items + 1,\n            height = self.itemheight or 92 }',
    ),
    (
        '                PanelRaised = { r = .2, g = .2, b = .2 }, Action = { r = 0, g = .5, b = 1 },',
        '                PanelRaised = { r = .2, g = .2, b = .2 }, Action = { r = 0, g = .5, b = 1 },\n                Selection = { r = .3, g = .2, b = .1 },',
    ),
    (
        '            Metrics = { Padding = 12, Gap = 12 },\n            DrawRoundedSurface = function(...) end,',
        '            Metrics = { Padding = 12, Gap = 12 },\n            DrawRoundedSurface = function(...) end,\n            FontHeight = function(font, fallback) return tonumber(fallback) or 16 end,\n            CenterTextY = function(y, height) return math.floor((tonumber(y) or 0) + 4) end,',
    ),
])

# 用例 19 的标题也换掉（橙子版是 "home entry wrapped"）
FILE_PATCHES.setdefault("test_recruit.lua", []).append((
    "    -- 造 context 并调用被包装的 index 工厂",
    "    -- 造一份 context，供下面的 registry.Create / Page.Create 使用",
))
FILE_PATCHES.setdefault("test_recruit.lua", []).append((
    "runTest(19, \"ui: page registered, home entry wrapped, button opens the page, page renders\"",
    "runTest(19, \"ui: page registered, YeseMarket navigation row injected, button opens the page, page renders\"",
))


def main():
    parser = argparse.ArgumentParser(description="生成/校验 bin2_npc_extension 的 YeseMarket 变体")
    parser.add_argument("--write", action="store_true", help="把变体写到 Contents/mods/<TARGET_MOD> 与 tools/test-yese")
    parser.add_argument("--check", action="store_true", help="重新生成并比对（发现手改即失败）")
    parser.add_argument("--verbose", action="store_true", help="打印差异细节")
    args = parser.parse_args()
    if not args.write and not args.check:
        args.check = True

    with tempfile.TemporaryDirectory() as tmp:
        mod_count = generate_source_tree(os.path.join(tmp, "mods"))
        test_count = generate_test_tree(os.path.join(tmp, "tests"))

        if args.write:
            dest_mod = os.path.join(MODS_DIR, TARGET_MOD)
            if os.path.isdir(dest_mod):
                shutil.rmtree(dest_mod)
            shutil.copytree(os.path.join(tmp, "mods", TARGET_MOD), dest_mod)
            dest_test = os.path.join(HERE, "test-yese")
            if os.path.isdir(dest_test):
                shutil.rmtree(dest_test)
            if test_count:
                shutil.copytree(os.path.join(tmp, "tests"), dest_test)
                # 入口脚本要可执行（生成器不保留权限位）
                runner = os.path.join(dest_test, "run_lua_test.sh")
                if os.path.isfile(runner):
                    os.chmod(runner, 0o755)
            print("写入变体：%s（%d 个文件）" % (dest_mod, mod_count))
            if test_count:
                print("写入测试：%s（%d 个文件，含 run_lua_test.sh）" % (dest_test, test_count))
            return 0

        problems = []
        dest_mod = os.path.join(MODS_DIR, TARGET_MOD)
        if not os.path.isdir(dest_mod):
            print("变体还没生成过：%s\n先跑 --write" % dest_mod)
            return 1
        problems += compare_tree(dest_mod, os.path.join(tmp, "mods", TARGET_MOD), args.verbose)
        dest_test = os.path.join(HERE, "test-yese")
        if os.path.isdir(dest_test):
            problems += compare_tree(dest_test, os.path.join(tmp, "tests"), args.verbose)

        if problems:
            print("变体与生成器不一致（%d 处）—— 变体目录是**生成物**，请改生成器而不是手改变体：" % len(problems))
            for line in problems[:60]:
                print("  " + line)
            return 1
        print("变体与生成器一致（mod %d 文件 / test %d 文件）" % (mod_count, test_count))
        return 0


if __name__ == "__main__":
    sys.exit(main())
