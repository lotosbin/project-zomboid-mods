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
    # 入口策略不同：橙子版包首页工厂，YeseMarket 版往导航栏插一行（见文件头注释）。
    # 这个文件是**手写**的变体实现，不走替换 —— --check 仍会守住它与生成器一致。
    "media/lua/client/Bin2NPCExtension/ui/Entry.lua": """--[[
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
    local text = ui.Text
    if type(primitives) ~= "table" or type(primitives.CreateButton) ~= "function" then return false end

    Entry.navInstalled = true
    Config.log("hooking YeseMarket.UIShell navigation for the recruit page")

    shell.buildNavigation = function(self, ...)
        build(self, ...)
        -- 自己造一个导航按钮。字段缺失就什么都不做（宁可没有按钮，也不要污染对方的界面）
        local viewport, buttons = self.navigationViewport, self.navButtons
        if viewport == nil or type(buttons) ~= "table" then return end
        if buttons[Entry.NAV_ID] ~= nil then return end
        local title = "NPC Recruit"
        if type(text) == "function" then
            local ok, value = pcall(text, "EntryButton")
            if ok and type(value) == "string" and value ~= "" then title = value end
        end
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
    "media/lua/shared/Bin2NPCExtension/Config.lua": [
        ('Config.SIBLING_MODULE = "Bin2NPCExtensionYese"',
         'Config.SIBLING_MODULE = "Bin2NPCExtension"'),
    ],
}


def transform(rel_path, text):
    if rel_path in FILE_OVERRIDES:
        return FILE_OVERRIDES[rel_path]
    for old, new in PRE_SUBS_PATCHES.get(rel_path, []):
        text = text.replace(old, new)
    for old, new in GLOBAL_SUBS:
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
