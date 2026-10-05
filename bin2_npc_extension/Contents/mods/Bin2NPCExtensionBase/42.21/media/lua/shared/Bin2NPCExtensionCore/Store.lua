Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（由 tools/extract_base.py 从口味模组机械搬移而来；来源表见该脚本的 FILES）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。口味的 Profile.lua 这样实例化它：

        <NS>.Store = require("Bin2NPCExtensionCore/Store")(<NS>)

    参数 NS 是该口味的命名空间表（见 Bin2NPCExtensionCore/Namespace.lua）；接线（Events 注册）
    由口味的 client/server 层文件调用工厂返回对象的 install() 触发。
    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]
local function factory(NS)
    --[[
        Bin2NPCExtensionCore :: Store（公共层工厂）

        我们自己的存档表：ModData[Config.TAG]。服务端权威写，写完 ModData.transmit 同步给客户端
        （客户端只读镜像，用于渲染招募面板）。

        为什么不借上游经济模组的 DataBucket：
        它只把自己的白名单键当"权威桶"（fixedBucketSet），第三方键会退化成普通 ModData
        —— 那还不如我们直接用 ModData，少一层间接。证据见 docs/research/economy-integration-hooks.md。
    ]]

    local Config = NS
    local Contracts = Config.Contracts

    local Store = {}
    Config.Store = Store

    -- 玩家键前缀由口味注入：两个口味各自独立记账，同一个玩家在两边的契约不串档
    Store.PLAYER_PREFIX = Config.PLAYER_PREFIX

    --[[
        玩家标识（契约按"账号"记，不按角色记 —— 与经济模组的钱包同一粒度）。

        优先用引擎用户名；取不到退到 displayName；再取不到用 LocalPlayer。
        单机下 getUsername 返回的是本地档名，多人下是 Steam 用户名 —— 两者都够稳定。
    ]]
    function Store.playerName(player)
        if player == nil then return "LocalPlayer" end
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and type(name) == "string" and name ~= "" then return name end
        local okDisplay, display = pcall(function() return player:getDisplayName() end)
        if okDisplay and type(display) == "string" and display ~= "" then return display end
        return "LocalPlayer"
    end

    function Store.playerKey(player)
        return Store.PLAYER_PREFIX .. Store.playerName(player)
    end

    -- 存档表（就地修补，引用稳定）
    function Store.data()
        if type(ModData) ~= "table" or type(ModData.getOrCreate) ~= "function" then
            return Contracts.blank()
        end
        local ok, store = pcall(ModData.getOrCreate, Config.TAG)
        if not ok or type(store) ~= "table" then return Contracts.blank() end
        return Contracts.sanitize(store)
    end

    -- 某个玩家的节点；create=true 时按需新建
    function Store.node(player, create)
        return Contracts.player(Store.data(), Store.playerKey(player), create)
    end

    --[[
        把改动同步给所有客户端。

        单机下 ModData.transmit 也需要调用：它负责把桶打脏并落盘，否则重进档会丢。
    ]]
    function Store.transmit()
        if type(ModData) ~= "table" or type(ModData.transmit) ~= "function" then return false end
        local ok = pcall(ModData.transmit, Config.TAG)
        if not ok then Config.warn("ModData.transmit failed for " .. Config.TAG) end
        return ok
    end

    return Store
end

Bin2NPCExtensionCore.Store = factory
return factory
