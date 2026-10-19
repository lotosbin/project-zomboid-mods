Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（**手写文件**，与 Namespace.lua / Sidebar.lua / Cash.lua 同类；不由
    tools/extract_base.py 产出）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。接线由 ClientBootstrap.install() 调用 Context.install()
    触发（和 Net 一样：公共层是 shared，文件体里注册 Events 会变成"所有口味共享一次注册"）。
    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]

--[[
    Bin2NPCExtensionCore :: Context（公共层工厂）

    能力：**站在 A-Life NPC 旁边右键**就有「收编 <名字>」，点一下直接走 HireExisting。

    为什么要有它（玩家原话）：「招募中立 NPC 放到右键菜单中，现在 NPC 跑太快来不及招募」。
    在此之前收编只有一条路：按 Ctrl+Alt+N 开面板 → 切到「收编」页签 → 点「扫描附近」→ 在列表里
    找到那个人 → 选中 → 点收编。NPC 在走，等这一串动作做完他可能已经出了服务端的
    `RecruitRadius`，于是「太远了」。（面板那条路保留：它还能看名额、日薪、改岗位。）

    设计上的几条硬约束
    ------------------
      * **只看点击处**（和 Jeem 自己的右键「邀请入住」一致：`Menu.radius = 2`，见
        `ProjectALifeJimmy/Features/Residents/Menu.lua`）。取 `worldObjects[1]:getSquare()`，
        取不到才退回玩家脚下 —— 右键点在地上/人上都能用。
      * **候选名单复用 `Alife.candidates`**（同一份过滤规则：跳过前哨驻军 / 已是 Jeem 居民 /
        来访商人 / 已有契约的人 / 敌对的），只是把"距离原点"从玩家换成**点击的那格**。
        这样"右键菜单里能点的人"与"面板里能收编的人"永远是同一批，不会分叉出第二套规则。
      * **不包 `ISWorldObjectContextMenu.createMenu`**，只 `Add` 一个
        `Events.OnFillWorldObjectContextMenu` 监听器（两边的经济模组 UI 宿主都包过那个函数，
        再包一层就是叠套娃）。证据：docs/research/economy-integration-hooks.md 的
        「零冲突钩子」一节、docs/research/yese-integration-hooks.md 里「双方都包了
        createMenu」那一条（文件名带口味名，公共层不引用它）。
      * **服务端仍是唯一权威**：这里只发 `HireExisting`（金额 / 名额 / 距离 / 敌对全在服务端校验），
        结果显示走 `Net.notify`（"招募操作已完成" / 失败原因），与面板那条路完全一致。
      * 与 Jeem 的条目**并排而不是代替**：我们的条目前面有口味自己的前缀，点错谁的都不会串。
]]

local function factory(NS)
    local Config = NS

    local Context = {}
    Config.Context = Context

    --[[
        右键一次最多列出几个人。

        不做"一人一条"地铺满菜单：点在人堆里时列表会长得没法看，而真正要的往往是最近的那个。
        最近的先列（`Alife.candidates` 已按距离排序）。
    ]]
    Context.maxRows = 4

    local function warn(message)
        if type(Config.warn) == "function" then Config.warn(message) else print("[Context] " .. tostring(message)) end
    end

    --[[
        点击处所在的那一格。

        `worldObjects[1]` 是引擎交给右键菜单的"光标下的对象"：可能是 NPC 自己、可能是地板上的
        一张纸、也可能是格子本身。三种都试一遍，最后退到玩家脚下 —— 右键永远有用，不会因为
        某个对象的接口形状不同就整条入口消失。
    ]]
    local function clickedSquare(player, worldObjects)
        local object = type(worldObjects) == "table" and worldObjects[1] or nil
        if object ~= nil then
            local ok, square = pcall(function() return object:getSquare() end)
            if ok and square ~= nil then return square end
            local okX, x = pcall(function() return object:getX() end)
            if okX and tonumber(x) ~= nil then return object end            -- 本身就是格子
        end
        if player ~= nil then
            local ok, square = pcall(function() return player:getSquare() end)
            if ok and square ~= nil then return square end
            local okX, x = pcall(function() return player:getX() end)
            if okX and tonumber(x) ~= nil then return player end            -- 单机测试桩 / 极端情况
        end
        return nil
    end

    --[[
        已经有契约的人不进菜单（别人雇走的、自己雇着的都不进）。

        `Alife.candidates` 的 isTaken 回调就是干这个的：面板扫描附近时传的是同一个判断
        （见 Service 的 ScanCandidates），所以两条入口看到的名单一致。
    ]]
    local function taken()
        local store = Config.Store
        local contracts = Config.Contracts
        if store == nil or contracts == nil or type(contracts.owner) ~= "function" then return nil end
        local data = store.data()
        return function(uid)
            return contracts.owner(data, uid) ~= nil
        end
    end

    --[[
        点击处附近可收编的人：{ {uid, name, distance, hostile, factionId, profileId}, ... }。

        只读，不动任何状态 —— 右键菜单在引擎里会被**多次**填充（`test` 那一遍也在内），
        这里多算几次只是几格的距离比较，没有副作用。
    ]]
    function Context.rows(player, square)
        local alife = Config.Alife
        if alife == nil or type(alife.candidates) ~= "function" then return {} end
        if player == nil or square == nil then return {} end
        local origin = type(alife.position) == "function" and alife.position(square) or nil
        if origin == nil then return {} end
        local radius = math.max(1, tonumber(Config.recruitRadius()) or 2)
        local rows = alife.candidates(player, radius, taken(), origin) or {}
        local trimmed = {}
        for index = 1, math.min(#rows, Context.maxRows) do trimmed[index] = rows[index] end
        return trimmed
    end

    --[[
        菜单条目文案。

        走口味自己的翻译（`Config.Text` → `IGUI_<口味>_ContextRecruit`），键名在公共层里，
        文案在各口味的 Translate/<LANG>/IG_UI.json 里 —— 公共层不写死任何一句话。
    ]]
    function Context.label(name)
        return Config.Text.get("ContextRecruit", tostring(name or "?"))
    end

    function Context.title()
        return Config.Text.get("ContextRecruitMenu")
    end

    --[[
        点击：走面板同一条命令（服务端校验、结果用 Net.notify 提示）。
        mode 用沙盒的 DefaultMode —— 与面板「收编」按钮不选岗位时完全一致。
    ]]
    function Context.hire(uid)
        local net = Config.Net
        if net == nil or type(net.send) ~= "function" then return false end
        return net.send("HireExisting", {
            uid = tostring(uid),
            mode = Config.defaultMode(),
        }, true)
    end

    --[[
        把条目插到 Project A-Life 自己的 `[A-LIFE] …` 条目**之后**（没有就追加在末尾）。

        理由是可发现性：右键菜单在我们之前已经有一长串原版条目，把"收编"追加在最下面意味着
        玩家每次都要把鼠标滚到底；而 A-Life 自己的"和附近的人说话"就在最上面，跟着它排最自然。
        做法与 Jeem 的 `Menu.addPersonOption` 相同（先找最后一个以 `[A-LIFE]` 开头的条目，
        再用 `insertOptionAfter`）—— 引擎不提供 `insertOptionAfter` 时退回 `addOption`。
    ]]
    local function addAfterAlife(context, name, target, onSelect)
        local after = nil
        for _, option in ipairs(type(context.options) == "table" and context.options or {}) do
            if type(option.name) == "string" and string.sub(option.name, 1, 8) == "[A-LIFE]" then
                after = option.name
            end
        end
        if after ~= nil and type(context.insertOptionAfter) == "function" then
            return context:insertOptionAfter(after, name, target, onSelect)
        end
        return context:addOption(name, target, onSelect)
    end

    --[[
        填充一份右键菜单（`Events.OnFillWorldObjectContextMenu` 的回调）。

        只服务 player 0：本模组的其它客户端入口（面板、热键、侧边栏图标）都只服务 player 0，
        而 `Net.send` 取的就是 player 0 —— 分屏的 player 1 点这条会把命令以 player 0 的身份发出去。
    ]]
    function Context.fill(playerNum, context, worldObjects)
        if (tonumber(playerNum) or 0) ~= 0 then return false end
        if type(context) ~= "table" or type(context.addOption) ~= "function" then return false end
        if Config.enabled() ~= true then return false end
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
        if player == nil then return false end

        local square = clickedSquare(player, worldObjects)
        if square == nil then return false end
        local rows = Context.rows(player, square)
        if #rows == 0 then return false end

        --[[
            同一份菜单只填一次。引擎在"量宽度"那一趟与正式那一趟之间通常各建一份 context，
            但两边 UI 宿主都包过 `ISWorldObjectContextMenu.createMenu`：一旦有人
            在同一张表上再触发一遍事件，这里就会多出一份一模一样的子菜单。记在 context 自己身上
            （每次右键都是新表）最省事，也不影响别的监听器。
        ]]
        if context.bin2ContextFilled == true then return false end
        context.bin2ContextFilled = true

        local alife = Config.Alife
        local function add(sub, row, withDistance)
            local name = Context.label(row.name)
            if withDistance and tonumber(row.distance) ~= nil then
                -- 整数米：面板的候选卡片显示的是 tostring(1.0) = "1.0"，右键菜单里那样太吵
                name = string.format("%s (%d m)", name, math.floor(tonumber(row.distance) + 0.5))
            end
            local option = addAfterAlife(sub, name, player, function()
                Context.hire(row.uid)
            end)
            --[[
                第一人称模组（Viewpoint 这类）按"光标下的对象"过滤右键条目：把 NPC 的 shell 塞进
                最后一个参数槽（param10，本项目没有任何地方读它），它才会在那种菜单里留下我们这条
                （Jeem 的 `Menu.tie` 用的就是这个槽位）。取不到 shell（NPC 还没落地）就不塞 ——
                此时条目仍然出现在普通右键里。
            ]]
            if type(option) == "table" and alife ~= nil and type(alife.shell) == "function" then
                local ok, shell = pcall(alife.shell, row.uid)
                if ok and shell ~= nil and option.param10 == nil then option.param10 = shell end
            end
            return option
        end

        if #rows == 1 then
            add(context, rows[1], false)
            return true
        end

        --[[
            人多时收进一个子菜单：`[bin2] NPC 招募` → 每个人一条（带距离，方便挑最近的那个）。
            子菜单用 `ISContextMenu:getNew(context)` 建 —— 与 Jeem 的写法一致；引擎里没有这个类表时
            退回"一人一条平铺"，不让整条入口消失。
        ]]
        local class = rawget(_G, "ISContextMenu")
        if type(class) ~= "table" or type(class.getNew) ~= "function" then
            for _, row in ipairs(rows) do add(context, row, false) end
            return true
        end
        local root = addAfterAlife(context, Context.title(), nil, nil)
        local sub = class:getNew(context)
        context:addSubMenu(root, sub)
        for _, row in ipairs(rows) do add(sub, row, true) end
        return true
    end

    local function onFillWorldObjectContextMenu(playerNum, context, worldObjects)
        local ok, err = pcall(Context.fill, playerNum, context, worldObjects)
        if not ok then warn("context menu entry failed: " .. tostring(err)) end
    end

    --[[
        接线（由 ClientBootstrap.install() 调用，幂等）。

        判据是 **Events 表的身份**：同一张表 = 同一次 Lua 会话（跳过）；换了一张表 = 引擎
        Reset Lua 过（必须重注册，否则右键入口会静默消失）。这与 Net/ClientBootstrap 的
        "防 Reset Lua 重入"是同一条约定。
    ]]
    function Context.install()
        if Config.ContextEvents == Events and Config.ContextInstalled == true then return Context end
        Config.ContextEvents = Events
        Config.ContextInstalled = true
        if Events ~= nil and Events.OnFillWorldObjectContextMenu ~= nil then
            Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
            Config.log("context menu entry installed (right-click an A-Life NPC to hire)")
        end
        return Context
    end

    return Context
end

Bin2NPCExtensionCore.Context = factory
return factory
