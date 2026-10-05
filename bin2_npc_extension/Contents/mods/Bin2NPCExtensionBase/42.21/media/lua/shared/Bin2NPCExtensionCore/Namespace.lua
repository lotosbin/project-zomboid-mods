--[[
    Bin2NPCExtensionCore :: Namespace（公共层，**本文件是手写的**，其余 Core/*.lua 由
    tools/extract_base.py 从口味模组机械搬移而来）

    公共层的唯一入口：把一份"口味 spec"变成该口味的命名空间表 NS。

    为什么需要它
    ------------
    A-Life / Jeem 适配、契约模型、维护循环、命令路由这些逻辑，两个口味**完全同源**；
    但"叫什么名字、存在哪张表里、扣谁的钱、用哪套翻译前缀"必须各归各。于是把这些
    **身份字段**收进一张 spec，公共层只认 NS 上的字段，不认任何字面量。

    不变量
    ------
      * 公共层目录（media/lua/shared/Bin2NPCExtensionCore/）里不允许出现任何口味身份
        字面量 —— 由 tools/check_base.py 守着；
      * Core.API 是公共层与口味之间的接口版本。两者必须相等，否则口味会打一条明确的
        错误日志并**停用自己**（而不是抛异常）。这是"同一个工坊物品拆成多个模组"最典型
        的坏法：只更新了一半。宁可功能不生效 + 日志说清楚，也不要让玩家看到一堆报错。
]]

Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

local Core = Bin2NPCExtensionCore

-- 公共层与口味之间的接口版本。改公共层的**对外契约**（NS 上的字段、工厂返回对象的
-- 方法名、install() 的语义）时必须 +1，并同步各口味 Profile.lua 里的 coreApi。
Core.API = 1

--[[
    建一个命名空间表。

    spec 字段（除 module 外都可省；省了就是"该能力不启用"）：
        module               必填。mod.info 的 id；同时是网络命令 channel 与日志前缀
        version              mod.info 的 modversion（自检日志里打出来）
        coreApi              期望的 Core.API（不等就停用，见文件头）
        tag                  ModData 存档表名（两个口味各一张，互不串档）
        sandboxTable         SandboxVars 表名（两个口味各一套独立沙盒选项）
        sibling              同一个工坊物品里"另一个口味"的 mod id（只读，防重复雇佣）
        textPrefix           翻译键前缀，如 "IGUI_<mod id>_"
        playerPrefix         契约的玩家键前缀
        flowItem             记进对方账单的条目标识
        economyGlobal        经济模组**客户端**全局表名
        economyServerGlobal  经济模组**服务端**全局表名
        economyModId         经济模组的 mod id（日志用）
        economyName          经济模组的人类可读名（日志用）
        currencyName         货币的叫法（日志用，可空）

    返回 NS：就是该口味自己的全局表（例如 <mod id>），字段名沿用抽取前的
    Config.MODULE / Config.TAG / … —— 抽取只搬了实现，没有改名字。
]]
function Core.namespace(spec)
    if type(spec) ~= "table" or type(spec.module) ~= "string" or spec.module == "" then
        print("[Bin2NPCExtensionCore][ERROR] namespace(): spec.module is required")
        return nil
    end
    if tonumber(spec.coreApi) ~= Core.API then
        print(string.format("[%s][ERROR] public layer mismatch: this mod needs Bin2NPCExtensionBase"
            .. " core API %s but found %s. Update the whole workshop item (all three mods ship in"
            .. " the same item) and restart.",
            tostring(spec.module), tostring(spec.coreApi), tostring(Core.API)))
        return nil
    end

    local NS = {}

    -- 身份
    NS.MODULE = spec.module
    NS.VERSION = tostring(spec.version or "0.0.0")
    NS.TAG = spec.tag or (spec.module .. ".Contracts.v1")
    NS.TABLE = spec.sandboxTable or spec.module
    NS.SIBLING_MODULE = spec.sibling
    NS.TEXT_PREFIX = spec.textPrefix or ("IGUI_" .. spec.module .. "_")
    NS.PLAYER_PREFIX = spec.playerPrefix or (spec.module .. "Player_")
    NS.FLOW_ITEM = spec.flowItem or (spec.module .. ".contract")

    -- 经济模组
    NS.ECONOMY_GLOBAL = spec.economyGlobal
    NS.ECONOMY_SERVER_GLOBAL = spec.economyServerGlobal
    NS.ECONOMY_MOD_ID = spec.economyModId
    NS.ECONOMY_NAME = spec.economyName or spec.economyModId
    NS.CURRENCY_NAME = spec.currencyName

    -- 反查用（排障时能一眼看出这个 NS 是哪个口味、按哪份 spec 建的）
    NS.SPEC = spec

    return NS
end

--[[
    按依赖顺序把公共层的 12 个模块实例化到这个 NS 上。

    顺序是有意义的：Jimmy 在实例化时就 `local Alife = Config.Alife` 抓住兄弟模块的引用，
    所以 Alife 必须先于 Jimmy、Store 必须先于 Service，以此类推。顺序写在这里（而不是散在
    各口味的 Profile 里），就是为了让"公共层有哪些模块、谁依赖谁"只有一处真相。

    Config 不参与赋值：它返回的就是 NS 自己（NS 上的 MODULE/TAG/… 已经建好了）。
]]
function Core.bind(NS)
    require("Bin2NPCExtensionCore/Config")(NS)
    NS.Text = require("Bin2NPCExtensionCore/Text")(NS)
    NS.Contracts = require("Bin2NPCExtensionCore/Contracts")(NS)
    NS.Store = require("Bin2NPCExtensionCore/Store")(NS)
    NS.Economy = require("Bin2NPCExtensionCore/Economy")(NS)
    NS.Alife = require("Bin2NPCExtensionCore/Alife")(NS)
    NS.Jimmy = require("Bin2NPCExtensionCore/Jimmy")(NS)
    NS.Service = require("Bin2NPCExtensionCore/Service")(NS)
    NS.Maintain = require("Bin2NPCExtensionCore/Maintain")(NS)
    NS.Net = require("Bin2NPCExtensionCore/Net")(NS)
    NS.ServerBootstrap = require("Bin2NPCExtensionCore/ServerBootstrap")(NS)
    NS.ClientBootstrap = require("Bin2NPCExtensionCore/ClientBootstrap")(NS)
    return NS
end

return Core
