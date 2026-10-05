--[[
    Bin2NPCExtensionYese :: Bootstrap（server）

    事件接线：
      * OnClientCommand   —— 收客户端命令（module 必须是我们自己的 mod id）
      * OnGameStart / OnServerStarted —— 进档恢复指令 + 打日志自检
      * EveryOneMinute    —— 日薪结算
      * OnTick            —— 岗位补派 / 指令重下 / 阵亡清理（内部节流到 ~1 秒）

    注意：纯单机下 server 文件**也会加载**（引擎会 LoadDirBase("server")），
    但 OnClientCommand 不会触发 —— 单机路径由客户端 Net 层直接调用 Service.dispatch。
]]

require "Bin2NPCExtensionYese/Config"
require "Bin2NPCExtensionYese/Store"
require "Bin2NPCExtensionYese/Alife"
require "Bin2NPCExtensionYese/Jimmy"
require "Bin2NPCExtensionYese/Economy"
require "Bin2NPCExtensionYese/Service"
require "Bin2NPCExtensionYese/Maintain"

local Config = Bin2NPCExtensionYese
local Service = Config.Service
local Maintain = Config.Maintain

-- 幂等 + 防"Reset Lua"重入：判据是 Events 表的身份（同一张表 = 同一次会话，跳过；
-- 换表 = 引擎重置过 Lua，必须重新注册，否则 5 个处理器会静默失效）。
if Config.ServerBootstrapEvents == Events and Config.ServerBootstrap ~= nil then return Config.ServerBootstrap end
Config.ServerBootstrapEvents = Events

local Bootstrap = {}
Config.ServerBootstrap = Bootstrap

--[[
    兼容自检（**只读**）：把 A-Life 自己的"谁带了 A-Life Lua 副本 / 谁 rebind 了它的表"检测器跑一遍。

    为什么**不往** `ProjectALife.ModCompat.known` 里写我们自己（这里踩过一次，记录在案）：
      * `Compat.known` 是 A-Life 作者手写的**数据表**，不是注册 API；
      * `Compat.report()`（`shared/ProjectALife/Compat/ALifeModCompat.lua:314-330`）会遍历它，
        把**启用中的**条目按 `entry.verdict` 打印成
        `[A-Life] compat: <name> (<id>) -> adapted: <note>`；
      * 也就是说第三方往里写，等于借 A-Life 的口替自己背书 —— 而那个 verdict 并不是它给的。
    （同域的 `bin2_ProjectALifeNPCs_extensions/docs/integration-brainstorm.md` §1 已经写明这一点，
      本次对照时纠正。）

    真正有用的是另一半：`Compat.foreignCopies(active)` 会点名那些自带 A-Life Lua 副本的模组。
    它们会让 **每次 NPC 水合**都抛 "no such location" 之类的错 —— 而"把 NPC 生成出来"正是本模组的主路径，
    所以这条日志直接服务于本模组的排障。
]]
local compatAttempts = 0
local compatReported = false

function Bootstrap.reportCompat()
    if compatReported then return true end
    local alife = rawget(_G, "ProjectALife")
    local compat = alife and alife.ModCompat or nil
    if type(compat) ~= "table" or type(compat.foreignCopies) ~= "function" then
        compatAttempts = compatAttempts + 1
        return false                                   -- A-Life 还没起来：交给下一次重试
    end
    compatReported = true

    local active = nil
    if type(compat.activeSet) == "function" then
        local okSet, set = pcall(compat.activeSet)
        if okSet and type(set) == "table" then active = set end
    end
    if active == nil and type(getActivatedMods) == "function" then
        -- A-Life 自己读这个列表时会先剥掉反斜杠前缀（ALifeModCompat.lua:95），我们照做
        local okMods, mods = pcall(getActivatedMods)
        if okMods and mods ~= nil then
            local set = {}
            pcall(function()
                for index = 0, mods:size() - 1 do
                    set[string.gsub(tostring(mods:get(index)), "^\\+", "")] = true
                end
            end)
            active = set
        end
    end

    local ok, lines = pcall(compat.foreignCopies, active)
    if not ok or type(lines) ~= "table" or #lines == 0 then return true end
    Config.warn("A-Life reports " .. tostring(#lines) .. " incompatible mod(s) in this stack:")
    for _, line in ipairs(lines) do Config.warn("  " .. tostring(line)) end
    Config.warn("Those mods replace A-Life's Lua. This mod spawns NPCs through the same pipeline, "
        .. "so expect 'no such location' errors and NPCs that stutter or fail to spawn until they are disabled.")
    return true
end

--[[
    能力自检：把我们真正会用到的**半公开入口**逐个探一遍。

    这是同域项目"通用工程约定 §3 可观测"的落地（见
    `bin2_ProjectALifeNPCs_extensions/docs/roadmap.md` 阶段 4）：
    A-Life / Jeem 升级把某个函数改了名，第一次进游戏就能在日志里看到 `inactive=`，
    而不是等玩家点了按钮没反应、再来翻代码。
]]
local CAPABILITIES = {
    { "alife.registry", function(alife)
        return type(alife.ActorRegistry) == "table" and type(alife.ActorRegistry.create) == "function"
            and type(alife.ActorRegistry.update) == "function"
    end },
    { "alife.spawn", function(alife)
        return type(alife.SpawnService) == "table" and type(alife.SpawnService.request) == "function"
    end },
    { "alife.orders", function(alife)
        return type(alife.DecisionLoop) == "table" and type(alife.DecisionLoop.setOrder) == "function"
    end },
    { "alife.watchdog", function(alife)
        return type(alife.Watchdog) == "table" and type(alife.Watchdog.bindings) == "table"
    end },
    { "alife.catalog", function(alife)
        return type(alife.Catalog) == "table" and type(alife.Catalog.faction) == "function"
            and type(alife.Catalog.npc) == "function"
    end },
    { "alife.stance", function(alife)
        return type(alife.Relations) == "table" and type(alife.Relations.baselineStance) == "function"
    end },
    { "jeem.residents", function()
        local jeem = Config.jeem()
        return jeem ~= nil and type(jeem.Residents.recruit) == "function"
    end },
    { "jeem.baseAreas", function()
        local jeem = Config.jeem()
        return jeem ~= nil and type(jeem.BaseAreas) == "table"
            and type(jeem.BaseAreas.basesFor) == "function"
    end },
    { "jeem.standing", function()
        local jeem = Config.jeem()
        return jeem ~= nil and type(jeem.StandingService) == "table"
            and type(jeem.StandingService.addGroup) == "function"
    end },
    { "economy.pay", function()
        local server = Config.economyServer()
        return server ~= nil and type(server.Pay) == "function" and type(server.AddCoins) == "function"
    end },
}

function Bootstrap.capabilities()
    local alife = rawget(_G, "ProjectALife") or {}
    local active, inactive = 0, {}
    for _, entry in ipairs(CAPABILITIES) do
        local ok = false
        local ran, value = pcall(entry[2], alife)
        if ran then ok = value == true end
        if ok then
            active = active + 1
        else
            inactive[#inactive + 1] = entry[1]
        end
    end
    return active, inactive
end

-- 依赖自检：把"三个依赖各在不在 + 挂了几个能力"打成一行日志，方便一眼定位"点了没反应"
function Bootstrap.report()
    local economy = Config.economy() ~= nil
    local economyServer = Config.economyServer() ~= nil
    local alife = Config.alife() ~= nil
    local jeem = Config.jeem() ~= nil
    local active, inactive = Bootstrap.capabilities()
    Config.always(string.format(
        "loaded v%s | economy=%s(server=%s) alife=%s jeem=%s | hooks active=%d inactive=%d"
        .. " | max=%d sign=%d spawn=%d wage=%d",
        Config.VERSION, tostring(economy), tostring(economyServer), tostring(alife), tostring(jeem),
        active, #inactive,
        Config.maxContracts(), Config.signPrice(), Config.spawnPrice(), Config.dailyWage()))
    if #inactive > 0 then
        Config.warn("inactive hooks (" .. tostring(#inactive) .. "): " .. table.concat(inactive, ", ")
            .. " -- an upstream rename looks like this; the matching feature degrades instead of throwing")
    end
    if not economy then
        Config.warn("YeseMarket (YeseMarket) is missing; the recruit page stays hidden")
    elseif not alife then
        Config.warn("Project A-Life is missing or not started yet; NPC hiring is disabled")
    end
end

--[[
    A-Life 的 ActorRegistry / SpawnService 只在世界开始后才存在，
    所以"依赖自检 + 兼容自检"要能被重复调用（幂等，且每次只看当前状态）。
]]
local function onWorldReady()
    Bootstrap.reportCompat()
    Bootstrap.report()
    local ok, err = pcall(Maintain.restore)
    if not ok then Config.warn("restore failed: " .. tostring(err)) end
end

local function onClientCommand(module, command, player, args)
    if module ~= Config.MODULE then return end
    local ok, err = pcall(Service.dispatch, player, command, args)
    if not ok then Config.error("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

-- OnTick 节流：Maintain.tick 内部只做"该不该动"的判断，但没必要每帧进
local lastTickMs = 0
local function onTick()
    local now = Config.nowMs()
    if now - lastTickMs < 1000 then return end
    lastTickMs = now
    local ok, err = pcall(Maintain.tick)
    if not ok then Config.error("maintain.tick failed: " .. tostring(err)) end
end

-- 一分钟一次：先补一次兼容自检（A-Life 加载顺序靠后时第一次会失败，最多试 5 次），再结算工资
local function onEveryMinute()
    if compatAttempts < 5 then Bootstrap.reportCompat() end
    local ok, err = pcall(Maintain.settleWages)
    if not ok then Config.error("wage settlement failed: " .. tostring(err)) end
end

if Events ~= nil then
    if Events.OnClientCommand ~= nil then Events.OnClientCommand.Add(onClientCommand) end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onWorldReady) end
    if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(onWorldReady) end
    if Events.EveryOneMinute ~= nil then Events.EveryOneMinute.Add(onEveryMinute) end
    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
end

-- 文件加载即尝试一次（A-Life 的 shared 文件在启动期就建好 ModCompat，所以这一发通常就够）
Bootstrap.reportCompat()

return Bootstrap
