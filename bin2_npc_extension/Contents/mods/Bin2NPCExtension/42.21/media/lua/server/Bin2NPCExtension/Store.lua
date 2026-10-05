--[[
    Bin2NPCExtension :: Store（server）

    我们自己的存档表：ModData[Config.TAG]。服务端权威写，写完 ModData.transmit 同步给客户端
    （客户端只读镜像，用于渲染招募面板）。

    为什么不借橙子经济的 DataBucket：
    它只把自己的白名单键当"权威桶"（runtime_core.lua 的 fixedBucketSet），
    第三方键会退化成普通 ModData —— 那还不如我们直接用 ModData，少一层间接。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Contracts"

local Config = Bin2NPCExtension
local Contracts = Config.Contracts

local Store = {}
Config.Store = Store

Store.PLAYER_PREFIX = "Bin2NPCExtensionPlayer_"

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
