Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（由 tools/extract_base.py 从口味模组机械搬移而来；来源表见该脚本的 FILES）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。口味的 Profile.lua 这样实例化它：

        <NS>.ClientBootstrap = require("Bin2NPCExtensionCore/ClientBootstrap")(<NS>)

    参数 NS 是该口味的命名空间表（见 Bin2NPCExtensionCore/Namespace.lua）；接线（Events 注册）
    由口味的 client/server 层文件调用工厂返回对象的 install() 触发。
    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]
local function factory(NS)
    --[[
        Bin2NPCExtensionCore :: ClientBootstrap（公共层工厂）

        客户端只做三件事（全部由 ClientBootstrap.install() 触发，口味的 client 层文件负责调用）：
          1. 把招募页注册进经济模组并装上入口（对方可能比我们晚就绪 → 重试到成功为止）；
          2. 挂一个热键（Ctrl+Alt+N）—— 对方全库没有任何按键绑定，不会冲突；
          3. 进世界时打一行自检日志（依赖状态 + 是否接上了 UI）。

        页面的**容器**（ui/Page.lua、ui/Entry.lua）是口味自己实现的：不同经济模组的 UI 原语
        不一样，这一层没法共用。这里只依赖它的两个契约入口：Config.Entry.install / .open
        与 Config.RecruitPage.ID，且都按"可能还没就绪"探测。
    ]]

    local Config = NS

    -- 幂等 + 防"Reset Lua"重入：判据是 Events 表的身份（同一张表 = 同一次会话，跳过；
    -- 换表 = 引擎重置过 Lua，必须重新注册，否则 3 个处理器会静默失效）。
    if Config.ClientBootstrapEvents == Events and Config.ClientBootstrap ~= nil then return Config.ClientBootstrap end
    Config.ClientBootstrapEvents = Events

    local Bootstrap = {}
    Config.ClientBootstrap = Bootstrap

    local HOTKEY = Keyboard and Keyboard.KEY_N or nil
    local retries = 0
    local installed = false
    local lastTryMs = 0

    --[[
        尝试接入 UI。橙子经济的 client 文件可能比我们晚加载（它们内部还有一长串 require），
        所以这里既要"文件加载时试一次"，也要在进世界后按秒重试（上限 Config.UI_RETRY_MAX）。
    ]]
    function Bootstrap.tryInstall()
        if installed then return true end
        -- Entry 是口味的 client 层文件，可能还没加载（或这个口味根本没实现）
        local Entry = Config.Entry
        if Entry == nil or type(Entry.install) ~= "function" then return false end
        local ok, result = pcall(Entry.install)
        if not ok then
            Config.warn("UI install failed: " .. tostring(result))
            installed = true                    -- 出错就不再刷屏，日志里已经说清楚了
            return false
        end
        if result == true then
            installed = true
            return true
        end
        return false
    end

    local function modifiedKeysDown()
        local ctrl, alt = false, false
        pcall(function() ctrl = isCtrlKeyDown() == true end)
        pcall(function() alt = isAltKeyDown() == true end)
        return ctrl and alt
    end

    local function onKeyPressed(key)
        if HOTKEY == nil or key ~= HOTKEY then return end
        if not modifiedKeysDown() then return end
        local player = Config.localPlayer and Config.localPlayer() or nil
        local number = 0
        if player ~= nil and player.getPlayerNum ~= nil then
            local ok, value = pcall(player.getPlayerNum, player)
            if ok then number = math.max(0, math.floor(tonumber(value) or 0)) end
        end
        local Entry = Config.Entry
        if Entry ~= nil and type(Entry.open) == "function" and Entry.open(number) then
            Config.log("recruit panel opened via hotkey")
        else
            Config.warn("hotkey pressed but the economy mod UI is unavailable")
        end
    end

    local function onGameStart()
        Bootstrap.tryInstall()
        local ui = Config.economy()
        Config.always(string.format("client ready v%s | economy=%s page=%s",
            Config.VERSION,
            tostring(ui ~= nil),
            tostring(ui ~= nil and ui.UIPageRegistry ~= nil
                and type(ui.UIPageRegistry.Has) == "function"
                and ui.UIPageRegistry.Has(Config.RecruitPage.ID) == true)))
        Config.always("hotkey: Ctrl+Alt+N = NPC recruit panel")
    end

    local function onTick()
        if installed or retries >= Config.UI_RETRY_MAX then return end
        local now = Config.nowMs()
        if now - lastTryMs < 1000 then return end
        lastTryMs = now
        retries = retries + 1
        if not Bootstrap.tryInstall() and retries >= Config.UI_RETRY_MAX then
            Config.warn("gave up installing the recruit page after " .. tostring(retries)
                .. " attempts; is " .. Config.ECONOMY_MOD_ID .. " enabled?")
        end
    end

    --[[
        接线。由口味的 client 层文件调用（见该口味的 client/Bootstrap.lua）：
            require("Bin2NPCExtensionCore/ClientBootstrap")(NS).install()

        调用前口味的 client 层必须已经把 ui/Entry（连带 ui/Page）加载好。
    ]]
    function Bootstrap.install()
        -- 回包通道属于客户端接线，跟着一起装（Net 本身由 Profile 在 shared 层实例化）
        local Net = Config.Net
        if Net ~= nil and type(Net.install) == "function" then Net.install() end

        if Events ~= nil then
            if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onGameStart) end
            if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
            if Events.OnKeyPressed ~= nil then Events.OnKeyPressed.Add(onKeyPressed) end
        end

        -- 装完先试一次（我们的 mod 声明了 loadModAfter，通常这时对方已经就绪）
        Bootstrap.tryInstall()
        return Bootstrap
    end

    return Bootstrap
end

Bin2NPCExtensionCore.ClientBootstrap = factory
return factory
