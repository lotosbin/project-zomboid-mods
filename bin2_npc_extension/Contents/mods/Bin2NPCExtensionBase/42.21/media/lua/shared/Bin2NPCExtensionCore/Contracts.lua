Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（由 tools/extract_base.py 从口味模组机械搬移而来；来源表见该脚本的 FILES）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。口味的 Profile.lua 这样实例化它：

        <NS>.Contracts = require("Bin2NPCExtensionCore/Contracts")(<NS>)

    参数 NS 是该口味的命名空间表（见 Bin2NPCExtensionCore/Namespace.lua）；接线（Events 注册）
    由口味的 client/server 层文件调用工厂返回对象的 install() 触发。
    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]
local function factory(NS)
    --[[
        Bin2NPCExtensionCore :: Contracts（公共层工厂，纯数据逻辑）

        这里只做"表怎么长、怎么增删查"的纯函数，不碰引擎对象、不碰 A-Life、不写日志。
        服务端（权威）与客户端（只读镜像）共用同一份代码，保证两边对存档形状的理解一致。

        存档形状（ModData[Config.TAG]）：
            {
                schema = 1,
                players = {
                    [playerKey] = {
                        seq = 3,                       -- 自增序号（给 id 用）
                        contracts = {
                            [uid] = {                  -- 键就是 A-Life actor uid，天然去重
                                id = "c:1",
                                uid = "palife:...",
                                name = "John",
                                factionId = "…",
                                profileId = "…",
                                mode = "follow" | "guard" | "resident",
                                source = "hired" | "spawned",
                                baseId = "…",          -- 居民模式用（Jeem 基地 id）
                                anchor = { x = 0, y = 0, z = 0 },
                                hiredHours = 12.5,
                                wagePaidHours = 12.5,
                                unpaidSince = nil,
                                status = "active" | "dead" | "dismissed",
                                deadHours = nil,
                                price = 500,
                                note = "…",            -- 最近一次降级/失败原因（给 UI 显示）
                            },
                        },
                        order = { "uid1", "uid2" },    -- 显示顺序（Kahlua 没有 next()，显式维护）
                    },
                },
            }
    ]]

    local Config = NS
    local Contracts = {}

    Config.Contracts = Contracts

    local function isTable(value)
        return type(value) == "table"
    end

    -- 一个空的存档骨架
    function Contracts.blank()
        return { schema = Config.SCHEMA, players = {} }
    end

    --[[
        就地修补一份可能来自旧版本 / 手改存档的数据；返回同一张表（引用稳定，ModData 用得上）。
    ]]
    function Contracts.sanitize(store)
        if not isTable(store) then store = Contracts.blank() end
        store.schema = Config.SCHEMA
        if not isTable(store.players) then store.players = {} end
        for key, node in pairs(store.players) do
            if type(key) ~= "string" or not isTable(node) then
                store.players[key] = nil
            else
                if type(node.contracts) ~= "table" then node.contracts = {} end
                if type(node.order) ~= "table" then node.order = {} end
                node.seq = math.max(0, math.floor(tonumber(node.seq) or 0))
                -- 第一步：先把非法项剔掉（键不是字符串 / 值不是表）。
                -- 必须**先剔再重建 order**，否则刚删掉的那个键会被重建进 order，要跑第二遍才干净。
                for uid, contract in pairs(node.contracts) do
                    if type(uid) ~= "string" or not isTable(contract) then node.contracts[uid] = nil end
                end
                -- 第二步：修补字段
                for uid, contract in pairs(node.contracts) do
                    contract.uid = uid
                    contract.mode = Config.normalizeMode(contract.mode)
                    if type(contract.status) ~= "string" then contract.status = "active" end
                    if type(contract.name) ~= "string" or contract.name == "" then
                        contract.name = tostring(contract.profileId or uid)
                    end
                end
                -- 第三步：order 与 contracts 漂移时重建（以 contracts 为准，尽量保留已有顺序）
                local seen, rebuilt = {}, {}
                for _, uid in ipairs(node.order) do
                    if type(uid) == "string" and node.contracts[uid] ~= nil and not seen[uid] then
                        seen[uid] = true
                        rebuilt[#rebuilt + 1] = uid
                    end
                end
                for uid in pairs(node.contracts) do
                    if not seen[uid] then
                        seen[uid] = true
                        rebuilt[#rebuilt + 1] = uid
                    end
                end
                node.order = rebuilt
            end
        end
        return store
    end

    -- 取（或按需创建）某个玩家的节点
    function Contracts.player(store, playerKey, create)
        if not isTable(store) or type(playerKey) ~= "string" or playerKey == "" then return nil end
        if not isTable(store.players) then store.players = {} end
        local node = store.players[playerKey]
        if not isTable(node) then
            if create ~= true then return nil end
            node = { seq = 0, contracts = {}, order = {} }
            store.players[playerKey] = node
        end
        if type(node.contracts) ~= "table" then node.contracts = {} end
        if type(node.order) ~= "table" then node.order = {} end
        node.seq = math.max(0, math.floor(tonumber(node.seq) or 0))
        return node
    end

    function Contracts.get(node, uid)
        if not isTable(node) or type(uid) ~= "string" then return nil end
        return isTable(node.contracts) and node.contracts[uid] or nil
    end

    -- 显示顺序的数组（跳过已不存在的 uid）
    function Contracts.list(node)
        local rows = {}
        if not isTable(node) then return rows end
        for _, uid in ipairs(node.order or {}) do
            local contract = Contracts.get(node, uid)
            if contract ~= nil then rows[#rows + 1] = contract end
        end
        return rows
    end

    -- 未解约的契约数量（名额判定只看这个；阵亡/解雇的不占名额）
    function Contracts.activeCount(node)
        local total = 0
        for _, contract in ipairs(Contracts.list(node)) do
            if contract.status == "active" then total = total + 1 end
        end
        return total
    end

    -- 加入一份契约；同 uid 覆盖（幂等）
    function Contracts.add(node, contract)
        if not isTable(node) or type(contract) ~= "table" or type(contract.uid) ~= "string" then
            return nil
        end
        node.seq = math.max(0, math.floor(tonumber(node.seq) or 0)) + 1
        contract.id = contract.id or ("c:" .. tostring(node.seq))
        node.contracts[contract.uid] = contract
        local found = false
        for _, uid in ipairs(node.order) do
            if uid == contract.uid then found = true break end
        end
        if not found then node.order[#node.order + 1] = contract.uid end
        return contract
    end

    -- 彻底删除（解雇后用）；返回被删的契约
    function Contracts.remove(node, uid)
        if not isTable(node) or type(uid) ~= "string" then return nil end
        local contract = Contracts.get(node, uid)
        if contract == nil then return nil end
        node.contracts[uid] = nil
        local kept = {}
        for _, value in ipairs(node.order) do
            if value ~= uid then kept[#kept + 1] = value end
        end
        node.order = kept
        return contract
    end

    --[[
        全局查 uid 属于谁：返回 playerKey, contract。
        用途：防止同一个 NPC 被两名玩家同时雇佣（服务端权威判定）。
    ]]
    function Contracts.owner(store, uid)
        if not isTable(store) or not isTable(store.players) or type(uid) ~= "string" then return nil end
        for key, node in pairs(store.players) do
            if isTable(node) and isTable(node.contracts) then
                local contract = node.contracts[uid]
                if isTable(contract) and contract.status == "active" then return key, contract end
            end
        end
        return nil
    end

    -- 契约签名（用于显示"雇佣于"与排序）
    function Contracts.hiredOrder(rows)
        table.sort(rows, function(left, right)
            local a = tonumber(left.hiredHours) or 0
            local b = tonumber(right.hiredHours) or 0
            if a ~= b then return a < b end
            return tostring(left.uid or "") < tostring(right.uid or "")
        end)
        return rows
    end

    return Contracts
end

Bin2NPCExtensionCore.Contracts = factory
return factory
