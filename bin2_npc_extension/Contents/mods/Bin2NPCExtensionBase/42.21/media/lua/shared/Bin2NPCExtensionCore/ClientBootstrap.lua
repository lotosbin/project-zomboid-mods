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
          1. 让口味把招募界面的入口装上（可能是上游经济模组窗口里的一个按钮，
             也可能是原版左侧侧边栏里的一个图标；对方可能比我们晚就绪 → 重试到成功为止）；
          2. 挂一个热键（Ctrl+Alt+N）—— 上游经济模组全库没有任何按键绑定，不会冲突；
          3. 进世界时打一行自检日志（依赖状态 + 是否接上了 UI）。

        界面的**容器**（ui/Panel.lua、ui/Entry.lua 或 ui/Icon.lua）是口味自己实现的：不同
        宿主（各家经济模组的 UI 原语、原版 ISUI）差别太大，这一层没法共用。这里只依赖它的
        契约入口：Config.Entry.install / .open，都按"可能还没就绪"探测。
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
        -- 一行自检：钱从哪来（money=收钱方式）、有没有上游经济模组的客户端全局、
        -- 我们的入口有没有装上去。三个口味的入口形态完全不同（首页按钮 / 导航行 / 左侧图标），
        -- 所以这里只报"装没装上"，具体入口见各口味 ui/Entry.lua 自己的日志。
        Config.always(string.format("client ready v%s | money=%s economy=%s ui=%s",
            Config.VERSION,
            tostring(Config.MONEY_KIND),
            tostring(Config.economy() ~= nil),
            tostring(installed)))
        Config.always("hotkey: Ctrl+Alt+N = NPC recruit panel")
    end

    local function onTick()
        if installed or retries >= Config.UI_RETRY_MAX then return end
        local now = Config.nowMs()
        if now - lastTryMs < 1000 then return end
        lastTryMs = now
        retries = retries + 1
        if not Bootstrap.tryInstall() and retries >= Config.UI_RETRY_MAX then
            -- 排障提示由口味自己给（spec.uiHint）：三个口味的入口装不上的原因完全不同，
            -- 公共层不猜（历史上这里写的是"is <经济模组 id> enabled?"，对原版口味毫无意义）。
            Config.warn("gave up installing the recruit entry after " .. tostring(retries)
                .. " attempts; " .. tostring(Config.UI_HINT))
        end
    end

    --[[
        接线。由口味的 client 层文件调用（见该口味的 client/Bootstrap.lua）：
            require("Bin2NPCExtensionCore/ClientBootstrap")(NS).install()

        调用前口味的 client 层必须已经把 ui/Entry（连带 ui/Page）加载好。

        **install() 自身幂等**：判据是 Events 表的身份（见文件头那段"防 Reset Lua 重入"的说明）。
        工厂里那道判据只保证"同一个 NS 不会被建两次"，挡不住"install 被调两次" ——
        而引擎 Reset Lua 会**重跑所有 Lua 文件**，口味的 client/Bootstrap.lua 会再调一次 install；
        没有这道闸，`OnTick` 会注册两遍（Maintain 每帧跑两次），Ctrl+Alt+N 会"开了又关"。
    ]]
    function Bootstrap.install()
        if Config.ClientBootstrapInstalledEvents == Events then return Bootstrap end
        Config.ClientBootstrapInstalledEvents = Events

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
