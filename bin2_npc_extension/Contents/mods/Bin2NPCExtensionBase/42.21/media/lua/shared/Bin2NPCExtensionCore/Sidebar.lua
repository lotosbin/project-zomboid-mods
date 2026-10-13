Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（**手写文件**，与 Namespace.lua / Cash.lua 同类；不由 tools/extract_base.py 产出）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。口味的 Profile.lua 这样实例化它：

        <NS>.Sidebar = require("Bin2NPCExtensionCore/Sidebar")(<NS>)

    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]

--[[
    Bin2NPCExtensionCore :: Sidebar（公共层工厂）

    能力：把**我们自己的一个图标按钮**追加到原版左侧竖排图标栏（ISEquippedItem ——
    屏幕上那一列 心/背包/建造/家具/地图）的最下面，点它开关口味自己的窗口。

    为什么它在公共层：两个口味都要这个入口（纯原版口味只有这一个入口；挂在经济模组窗口里的
    口味也希望玩家在屏幕左边就能点到），而下面的每一条约束都只在引擎源码里写着 ——
    复制一份就是让它们分叉。口味只交一张 spec（贴图名 / 悬停提示键 / 窗口开没开 / 点击做什么）。

    引擎侧的硬约束（证据：docs/research/vanilla-sidebar-entry.md §1-§3）
    ------------------------------------------------------------------
      * 原版 `ISEquippedItem:initialise()` 建完整列按钮后会调 `self:shrinkWrap()`，而它覆写的
        **零参** `shrinkWrap` 只统计 `Type == "ISButton"` 的子元素（ISEquippedItem.lua:972-984）。
        ⇒ 我们的按钮必须用 `ISButton:new(...)` 建（derive 会打上 Type），追加之后再调一次
          `shrinkWrap()`，面板才会把自己算进高度。
      * 只能**追加在最后**：插在中间就得平移原版所有按钮的 y，而原版在 initialise 里就把
        `movableTooltip/movablePopup` 的坐标按 `movableBtn:getY()` 写死了（:807-812，后者还已经
        addToUIManager）。整体下移会让这两个浮层错位。
      * 原版按钮列**只在 player 0 的面板里**建（整段包在 `if self.chr:getPlayerNum() == 0 then`，
        :737…:967）；分屏 player 1+ 的侧边栏只有 mainHand/offHand 两张图。我们不去造。
      * `TEXTURE_WIDTH` / `TEXTURE_HEIGHT` / `setTextureWidth()` 是对方文件里的 local（:4-8），
        模组读不到 ⇒ 尺寸一律**从原版按钮上量**（invBtn → healthBtn → craftingBtn → mapBtn），
        再吸附到 48/64/80/96/128 最近的一档。不自己复刻 `getOptionSidebarSize()` 的映射
        （它还有一个 `size == 6 -> getOptionFontSizeReal() - 1` 的分支，复刻容易错）。
      * 贴图路径由引擎按 `media/ui/Sidebar/<宽>/<贴图名>_<On|Off>_<宽>.png` 拼出来，真实像素必须是
        `宽 x 0.75*宽`（否则 `ISButton:render` 会走 drawTextureScaledAspect 把图缩掉）；
        tools/make_icons.py 生成并自检这五档两态。
      * 玩家在选项里改"侧边栏尺寸"时，原版 `checkSidebarSizeOption()` 会把整个面板
        `setVisible(false)` + `removeFromUIManager()` 后**重建一个新实例**（:1059-1068）。
        ⇒ ① 面板引用只能挂在面板自己身上（模块级全局会指向已经死掉的那个面板）；
          ② 新面板会重跑 initialise，我们的按钮自动以新尺寸重生（副作用是正面的）。
      * 同一个方法会有别人也 hook（同一个物品里的另一个口味、别的模组）：本模块的幂等判据是
        **类表的身份**（同一张表 = 同一次会话，不重复包），并且每个面板按 `spec.id` 分开记，
        所以两个口味同时启用时会在同一列下面各得一个图标，互不覆盖。
]]

local function factory(NS)
    local Config = NS

    local Sidebar = {}
    Config.Sidebar = Sidebar

    -- 原版侧边栏的五个尺寸档（= ISEquippedItem.setTextureWidth 的五个映射结果）
    local SIZES = { 48, 64, 80, 96, 128 }
    Sidebar.SIZES = SIZES

    --[[
        面板上存按钮的字段名。

        为什么按 `spec.id` 再分一层：三个口味可以同时启用，其中两个（或更多）都会往同一个
        面板上追加图标。用"一个面板一个字段"的写法时，第二个口味会看见字段非空而以为自己
        装过了。这里固定一个通用字段名，里面按 spec.id 分开存，谁也不挡谁。
    ]]
    local FIELD = "bin2NpcSidebar"

    -- 类级 hook 的现状：装到哪张类表上（判据是**类表的身份**，见文件头）、当前生效的 spec
    Sidebar.hooked = nil
    Sidebar.spec = nil

    -- 引擎 API 一律走 pcall：这些是别人的全局，改名/缺失都不该让我们的入口把游戏打崩
    local function call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if ok then return value end
        return nil
    end

    local function holder(panel)
        local found = panel[FIELD]
        if type(found) ~= "table" then
            found = {}
            panel[FIELD] = found
        end
        return found
    end

    -- 只读地拿本模块在这个面板上的按钮（幂等判据就靠它）
    local function iconButton(panel, spec)
        if panel == nil or spec == nil then return nil end
        local found = panel[FIELD]
        local entry = type(found) == "table" and found[spec.id] or nil
        return type(entry) == "table" and entry.button or nil
    end

    -- 面板属于哪个玩家（拿不到就当 0：原版按钮列也只给 0 号建）
    local function playerNumberOf(panel)
        local chr = panel ~= nil and panel.chr or nil
        if chr ~= nil then
            local value = tonumber(call(chr.getPlayerNum, chr))
            if value ~= nil then return math.max(0, math.floor(value)) end
        end
        return 0
    end

    --[[
        量出原版按钮用的是哪一档尺寸。

        为什么要"量"：`TEXTURE_WIDTH` 是对方文件里的 local，我们看不见；而
        `getOptionSidebarSize()` 到尺寸的映射里还有一个 `size == 6 -> getOptionFontSizeReal() - 1`
        的分支，自己复刻容易错。原版每个按钮都是 `ISButton:new(0, y, TEXTURE_WIDTH, TEXTURE_HEIGHT, …)`
        建的，所以拿任何一个按钮的宽就是那一档（再吸附到最近的档，防原版哪天给出非整数宽）。
    ]]
    local function measureSize(panel)
        local candidates = { panel.invBtn, panel.healthBtn, panel.craftingBtn, panel.mapBtn }
        for _, button in ipairs(candidates) do
            if button ~= nil then
                local width = tonumber(call(button.getWidth, button)) or 0
                if width > 0 then
                    local best = SIZES[1]
                    for _, size in ipairs(SIZES) do
                        if math.abs(size - width) < math.abs(best - width) then best = size end
                    end
                    return best
                end
            end
        end
        return SIZES[1]
    end

    -- 贴图路径是引擎拼出来的，我们只是照着拼；拿不到图就返回 nil（ISButton 允许 image 为空）
    local function iconTexture(spec, size, state)
        local path = string.format("media/ui/Sidebar/%d/%s_%s_%d.png", size, spec.texture, state, size)
        return call(getTexture, path)
    end

    --[[
        刷新两态贴图 + 跟随尺寸档。

        每帧重新量一次档位：原版改"侧边栏尺寸"时会整体重建面板（新面板新按钮），但万一哪天它
        改成原地换贴图，这里也能跟上（量一个宽度，代价可忽略）。
    ]]
    local function refresh(panel, spec)
        local button = iconButton(panel, spec)
        if button == nil then return end
        local size = measureSize(panel)
        if button.bin2SidebarSize ~= size then
            button.bin2SidebarSize = size
            button:setWidth(size)
            button:setHeight(math.floor(size * 0.75))
            call(function() panel:shrinkWrap() end)
        end
        local open = type(spec.isOpen) == "function" and call(spec.isOpen) == true
        button:setImage(iconTexture(spec, size, open and "On" or "Off"))
    end

    --[[
        点击图标：交给口味自己去开关窗口，然后按新的开关状态换贴图。

        注意回调签名：`ISButton:onMouseUp` 调的是 `self.onclick(self.target, self, …)`，
        也就是第一个参数是**注册时给的目标**（这里就是侧边栏面板本身），第二个才是按钮
        （原版 `ISEquippedItem:onOptionMouseDown(button, x, y)` 之所以能把第一个参数叫 button，
        是因为它是以面板为 self 的方法）。写成单参数会把面板当按钮。
    ]]
    local function onClicked(target, button, spec)
        if button ~= nil and button.internal ~= spec.id then return end
        if type(spec.toggle) == "function" then
            pcall(spec.toggle, playerNumberOf(target))
        end
        refresh(target, spec)
    end

    --[[
        往一个侧边栏面板里追加我们的按钮。

        幂等判据挂在**面板自己**身上（`panel[FIELD][spec.id]`），不能挂模块全局：
        玩家在选项里改"侧边栏尺寸"时，原版会把整个面板 removeFromUIManager 后重建一个新面板，
        模块级引用会指向已经死掉的那个。

        返回 true = 已经装好（或这个面板不需要装）；false = 这个面板还不适合装（稍后再来）。
    ]]
    local function attach(panel)
        local spec = Sidebar.spec
        if spec == nil or panel == nil or panel.chr == nil then return false end
        -- 原版的设计：按钮列只有 player 0 有；分屏的 player 1+ 我们也不去造
        if playerNumberOf(panel) ~= 0 then return true end
        if iconButton(panel, spec) ~= nil then return true end
        if panel.addChild == nil or panel.shrinkWrap == nil then return false end
        if type(ISButton) ~= "table" or type(ISButton.new) ~= "function" then return false end

        local size = measureSize(panel)
        local button = ISButton:new(0, panel:getHeight() + 15, size, math.floor(size * 0.75), "",
            panel, function(target, clicked) onClicked(target, clicked, spec) end)
        button.internal = spec.id
        button:initialise()
        button:instantiate()
        button:setImage(iconTexture(spec, size, "Off"))
        -- 这几个和原版图标按钮保持一致（证据：ISEquippedItem.lua:742-751）
        button:setDisplayBackground(false)
        button.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
        button:ignoreWidthChange()
        button:ignoreHeightChange()
        button.bin2SidebarSize = size
        holder(panel)[spec.id] = { button = button }
        panel:addChild(button)

        -- 让面板把自己算进高度（原版实现只统计 Type == "ISButton" 的子元素）
        call(function() panel:shrinkWrap() end)

        -- 悬停提示走原版自己的 tooltip 列表（它会显示在左侧栏上方）。
        -- 文案由口味自己翻译好交进来（公共层不认识任何翻译前缀），空串 = 不要提示。
        if type(spec.tooltip) == "string" and spec.tooltip ~= "" then
            call(function() panel:addMouseOverToolTipItem(button, spec.tooltip) end)
        end

        refresh(panel, spec)
        return true
    end

    --[[
        装入口。返回 true 表示"入口已经在（或已经不需要）"。

        spec 字段（必填的三条 + 可选的三条）：
            id       必填。按钮的 internal 标识，同一个面板上必须唯一（两个口味各用各的）
            texture  必填。贴图基名，拼成 media/ui/Sidebar/<宽>/<texture>_<On|Off>_<宽>.png
            toggle   必填。function(playerNumber)；点击时调用（开关口味自己的窗口）
            isOpen   可选。function() -> boolean；决定用 On 还是 Off 贴图（缺省恒 Off）
            tooltip  可选。悬停提示的**文案**（口味自己用 Text.get 查好；缺省不加提示）
            log      可选。装好时打给日志的那句话（英文；缺省用一句通用文案）

        调用方（口味的 client 层）应当把返回值当成"稍后可能就绪"来处理：原版侧边栏是进世界
        时才建的，可能比我们晚。装不上时这里**如实**返回 false，由公共层的 ClientBootstrap
        继续重试并在试满之后打印口味自己的 uiHint。
    ]]
    function Sidebar.install(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
            Config.warn("Sidebar.install: spec.id is required")
            return false
        end
        if type(spec.texture) ~= "string" or spec.texture == "" then
            Config.warn("Sidebar.install: spec.texture is required (" .. tostring(spec.id) .. ")")
            return false
        end
        if type(spec.toggle) ~= "function" then
            Config.warn("Sidebar.install: spec.toggle is required (" .. tostring(spec.id) .. ")")
            return false
        end

        local class = rawget(_G, "ISEquippedItem")
        if type(class) ~= "table" then return false end
        if type(rawget(_G, "ISButton")) ~= "table" then return false end
        local originalInitialise, originalPrerender = class.initialise, class.prerender
        if type(originalInitialise) ~= "function" or type(originalPrerender) ~= "function" then
            -- 原版改名了，或别的模组把它换成了非函数：如实失败，让调用方去重试 / 打日志
            return false
        end

        -- 同一个 NS 只认第一张 spec：下面的 hook 已经闭包住了它，换一张只会让两边不一致
        if Sidebar.spec == nil then Sidebar.spec = spec end

        -- 幂等 + 防 Reset Lua：判据是**类表的身份**（同一张表 = 同一次会话，不重复包）
        if Sidebar.hooked ~= class then
            Sidebar.hooked = class
            class.initialise = function(self, ...)
                originalInitialise(self, ...)
                --[[
                    原版 ISUIElement.initialise() 会把 children 整个清空（ISUIElement.lua:13-20，
                    引擎自己在那行写着 FIXME "need to avoid calling this method more than once"）。
                    我们存在面板上的按钮引用这一刻已经变成孤儿 —— 不清掉的话下面的 attach 会看见
                    "装过了"直接返回 true，图标从此永久消失（prerender 里那道兜底会被同一个陈旧
                    引用挡住，只有整块面板被重建才能恢复）。

                    只能清**本口味这一条**，绝不能连整个 FIELD 一起清：两个口味同时启用时 hook 是
                    套娃的（后装的包住先装的），里层刚写完自己的记录、外层紧接着清空整表 ——
                    里层随后就会再装一次，结果是同一列下面出现两个图标。
                ]]
                local current = Sidebar.spec
                if current ~= nil then
                    local found = self[FIELD]
                    if type(found) == "table" then found[current.id] = nil end
                end
                attach(self)
            end
            class.prerender = function(self, ...)
                originalPrerender(self, ...)
                local current = Sidebar.spec
                if current ~= nil and iconButton(self, current) == nil then attach(self) end
                refresh(self, current)
            end
            Config.always(spec.log or ("sidebar entry installed: " .. tostring(spec.id)))
        end

        -- 已经建好的面板（重载 Lua / 重进世界时原版面板可能已经在了）：直接补一次
        local panel = call(function()
            local data = getPlayerData(0)
            return data and data.equipped or nil
        end)
        if panel ~= nil then attach(panel) end

        return true
    end

    return Sidebar
end

Bin2NPCExtensionCore.Sidebar = factory
return factory
