--[[
    Bin2NPCExtensionVanilla :: ui/Icon（client）

    入口：把招募窗口挂到**原版左侧竖排图标栏**（ISEquippedItem —— 心/背包/建造那一列）最下面。

    为什么不新建一个浮动按钮：那条竖排栏是玩家最熟的"功能入口"位置（心=健康、背包、建造、
    家具、地图都在那儿），挂在它里面就自动获得原版的位置、尺寸档、拖动/隐藏行为。

    挂接方式（证据与备选方案见 docs/research/vanilla-sidebar-entry.md §2）
    ----------------------------------------------------------------
      * **后置 hook `ISEquippedItem:initialise`**，在原版把所有按钮建完之后追加自己的
        `ISButton`，再调一次 `self:shrinkWrap()`。`shrinkWrap` 只统计 `Type == "ISButton"`
        的子元素（ISEquippedItem.lua:972-984），所以它会自动把我们的按钮算进面板高度。
      * 只能**追加在最后**：插在中间就得平移原版按钮的 y，而原版把
        `movableTooltip/movablePopup` 的坐标写死在 `:initialise` 里（:807-812），一平移就错位。
      * 原版的按钮列整个包在 `if self.chr:getPlayerNum() == 0 then`（:737…:967）里 ——
        只有 player 0 有这一列。分屏的 player 1+ 没有入口，我们也不去造（那是原版的设计）。
      * `TEXTURE_WIDTH` / `setTextureWidth()` 是 ISEquippedItem.lua 的**文件级 local**，模组读不到，
        所以尺寸一律**从原版按钮上量**（`self.invBtn:getWidth()`），不从选项值反推。

    两态贴图：`media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png`（尺寸 = 48/64/80/96/128，
    真实像素 48x36 … 128x96，由 tools/make_icons.py 生成）。窗口开着时用 On。
]]

-- 引擎 UI 基类（游戏里由 client 层自动加载；require 只是显式声明，缺了也不该在加载期炸）
if type(require) == "function" then
    pcall(require, "ISUI/ISButton")
    pcall(require, "ISUI/ISEquippedItem")
end

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间
local Config = require "Bin2NPCExtensionVanilla/Profile"
if Config == nil then return nil end

-- 顺序声明：本文件要用 Config.RecruitPanel 打开窗口
require "Bin2NPCExtensionVanilla/ui/Panel"

local T = Config.Text.get

local Icon = {}
Config.Entry = Icon

-- 原版侧边栏的五个尺寸档（ISEquippedItem.setTextureWidth 的映射结果）
local SIZES = { 48, 64, 80, 96, 128 }

--[[
    量出原版按钮用的是哪一档。

    为什么要"量"：`TEXTURE_WIDTH` 是对方文件里的 local，我们看不见；而 `getOptionSidebarSize()`
    到尺寸的映射里还有一个 `size == 6 -> getOptionFontSizeReal() - 1` 的分支，自己复刻容易错。
    原版每个按钮都是用 `ISButton:new(0, y, TEXTURE_WIDTH, TEXTURE_HEIGHT, ...)` 建的，
    所以拿任何一个按钮的宽高就是那一档。
]]
local function measureSize(panel)
    local candidates = { panel.invBtn, panel.healthBtn, panel.craftingBtn, panel.mapBtn }
    for _, button in ipairs(candidates) do
        if button ~= nil then
            local ok, width = pcall(function() return button:getWidth() end)
            local value = ok and math.floor(tonumber(width) or 0) or 0
            if value > 0 then
                -- 取最接近的一档，防原版哪天改成非整数宽
                local best = SIZES[1]
                for _, size in ipairs(SIZES) do
                    if math.abs(size - value) < math.abs(best - value) then best = size end
                end
                return best
            end
        end
    end
    return SIZES[1]
end

local function iconTexture(size, state)
    local ok, texture = pcall(getTexture,
        string.format("media/ui/Sidebar/%d/NPC_%s_%d.png", size, state, size))
    if ok then return texture end
    return nil
end

-- 让按钮的两态跟着窗口开关走（原版是每帧 prerender 里 setImage，这里同样）
local function refreshIcon(panel)
    local button = panel and panel.bin2NpcIcon or nil
    if button == nil then return end
    -- 每帧重新量一次档位：原版改"侧边栏尺寸"时会整体重建面板（新面板新按钮），
    -- 但万一哪天它改成原地换贴图，这里也能跟上（量一个宽度，代价可忽略）
    local size = measureSize(panel)
    if button.bin2NpcSize ~= size then
        button.bin2NpcSize = size
        button:setWidth(size)
        button:setHeight(math.floor(size * 0.75))
        pcall(function() panel:shrinkWrap() end)
    end
    button:setImage(iconTexture(size, Config.RecruitPanel.isOpen() and "On" or "Off"))
end

--[[
    点击图标：开关招募窗口。

    注意回调签名：`ISButton:onMouseUp` 调的是 `self.onclick(self.target, self, ...)`，
    也就是说第一个参数是**注册时给的目标**（这里就是侧边栏面板本身），第二个才是按钮
    （原版 `ISEquippedItem.onOptionMouseDown(button, x, y)` 之所以能把第一个参数叫 `button`，
    是因为它是以面板为 self 的方法：`ISButton:new(..., self, ISEquippedItem.onOptionMouseDown)`）。
    写成单参数会把面板当按钮，判 `internal` 永远不成立 —— 按钮点了没反应。
]]
local function onIconClicked(target, button)
    if button ~= nil and button.internal ~= "BIN2NPCRECRUIT" then return end
    Config.RecruitPanel.toggle(nil)
    refreshIcon(target)
end

--[[
    往一个侧边栏面板里追加我们的按钮。

    幂等判据挂在**面板自己**身上（`panel.bin2NpcIcon`），不能挂模块全局：
    玩家在选项里改"侧边栏尺寸"时，原版的 checkSidebarSizeOption（ISEquippedItem.lua:1059-1068）
    会把整个面板 removeFromUIManager 后**重建**一个新面板，全局引用会指向已经死掉的那个。

    返回 true = 已经装好（或这个面板不需要装）。
]]
local function attach(panel)
    if panel == nil or panel.chr == nil then return false end
    local okNum, playerNum = pcall(function() return panel.chr:getPlayerNum() end)
    if okNum and tonumber(playerNum) ~= nil and tonumber(playerNum) ~= 0 then return true end
    if panel.bin2NpcIcon ~= nil then return true end
    if panel.addChild == nil or panel.shrinkWrap == nil then return false end

    local size = measureSize(panel)
    local width, height = size, math.floor(size * 0.75)
    local y = panel:getHeight() + 15          -- 原版每个按钮之间也是 +15（UI_BORDER_SPACING + 5）

    local button = ISButton:new(0, y, width, height, "", panel, onIconClicked)
    button.internal = "BIN2NPCRECRUIT"
    button:initialise()
    button:instantiate()
    button:setImage(iconTexture(size, "Off"))
    button:setDisplayBackground(false)
    button.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    button.bin2NpcSize = size
    panel.bin2NpcIcon = button
    panel:addChild(button)

    -- 让面板把自己算进高度（原版实现只统计 Type == "ISButton" 的子元素）
    pcall(function() panel:shrinkWrap() end)

    -- 悬停提示：走原版自己的 tooltip 列表（它会显示在左侧栏上方）
    pcall(function() panel:addMouseOverToolTipItem(button, T("IconTooltip")) end)

    refreshIcon(panel)
    return true
end

--[[
    装钩子。返回 true 表示"入口已经在（或已经不需要）"。

    公共层的 ClientBootstrap 会一直重试到 true：侧边栏是进世界时才建的，可能比我们晚。
]]
function Icon.install()
    local class = rawget(_G, "ISEquippedItem")
    if type(class) ~= "table" then return false end
    local originalInitialise = class.initialise
    local originalPrerender = class.prerender
    if type(originalInitialise) ~= "function" or type(originalPrerender) ~= "function" then
        -- 原版改名了（或别的模组把它换成了非函数）：如实失败，让公共层打日志
        return false
    end

    -- 幂等 + 防 Reset Lua：判据是**类表的身份**（同一张表 = 同一次会话，不重复包）
    if Icon.hooked ~= class then
        Icon.hooked = class
        class.initialise = function(self, ...)
            originalInitialise(self, ...)
            attach(self)
        end
        class.prerender = function(self, ...)
            originalPrerender(self, ...)
            if self.bin2NpcIcon == nil then attach(self) end
            refreshIcon(self)
        end
        Config.always("sidebar icon hooked into ISEquippedItem (left column, below the vanilla buttons)")
    end

    -- 已经建好的面板（例如玩家重载 Lua / 重进世界）：直接补一次
    local ok, panel = pcall(function()
        local data = getPlayerData(0)
        return data and data.equipped or nil
    end)
    if ok and panel ~= nil then attach(panel) end

    return true
end

--[[
    打开/关闭招募窗口（公共层把 Ctrl+Alt+N 送到这里）。

    侧边栏图标与热键走同一条路：开着就关、关着就开；热键**永远可用**，
    即使侧边栏图标没装上（翻译文案里承诺了 Ctrl+Alt+N，不能只靠鼠标）。
]]
function Icon.open()
    local player = Config.localPlayer and Config.localPlayer() or nil
    return Config.RecruitPanel.toggle(player)
end

return Icon
