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

    钱的接口（NS.Economy）
    ----------------------
    "怎么收钱"不是公共逻辑，而是**可换的实现**。公共层只认下面这组方法，谁来实现由
    spec.money 决定（见 Core.MONEY_PROVIDERS）：

        available()                         -> boolean        收钱这件事现在能不能用
        balance(player)                     -> number | nil   余额；读不到返回 nil（与 0 区分）
        pay(player, amount)                 -> ok, why        扣款；why 是 Text.reason 的键
        refund(player, amount)              -> boolean        退款（造人/收编失败时）
        flow(player, dir, kind, key, price) -> boolean        记一笔流水（可为空实现）
        wage()                              -> number         每名雇员的日薪

    现有的两个实现：

        "upstream"（默认）  Bin2NPCExtensionCore/Economy.lua  上游经济模组的服务端 Pay/AddCoins
        "cash"             Bin2NPCExtensionCore/Cash.lua     原版钞票物品 Base.Money（不需要任何经济模组）

    服务端权威这条线不能破：pay/refund 只在服务端跑，客户端传来的价格一律不采信。
]]

Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

local Core = Bin2NPCExtensionCore

-- 公共层与口味之间的接口版本。改公共层的**对外契约**（NS 上的字段、工厂返回对象的
-- 方法名、install() 的语义）时必须 +1，并同步各口味 Profile.lua 里的 coreApi。
--
-- 2 = 1 + 可换的钱实现（spec.money -> NS.MONEY_KIND）与客户端 UI 的排障提示（spec.uiHint）。
--     这一版是**加字段**，老口味不加也能跑；但"只更新了一半的工坊物品"必须被拦下来
--     （新口味要的 Cash.lua 在旧公共层里不存在 → 会静默变成"没有经济模组"，正是最坏的降级），
--     所以仍然按接口变更处理：+1。
Core.API = 2

-- 钱的两个实现，名字 -> 公共层文件名（Core.bind 按 NS.MONEY_KIND 取）。
-- 新增一种收钱方式就在这里加一行，并在下面 spec 文档里写清它的语义。
Core.MONEY_PROVIDERS = {
    upstream = "Economy",
    cash = "Cash",
}

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
        money                收钱方式："upstream"（默认，上游经济模组）或 "cash"（原版钞票）
        uiHint               客户端入口装不上时的排障提示（一句话，写进日志）
        defaults             沙盒选项的默认值覆盖（见 Config.DEFAULTS 上面的说明）

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
            .. " core API %s but found %s. Update the whole workshop item (every mod of this series"
            .. " ships in the same item) and restart.",
            tostring(spec.module), tostring(spec.coreApi), tostring(Core.API)))
        return nil
    end

    -- 认不出的收钱方式 = 配置错误，不能"当作没有经济模组"悄悄跑下去
    local moneyKind = spec.money or "upstream"
    if Core.MONEY_PROVIDERS[moneyKind] == nil then
        print(string.format("[%s][ERROR] namespace(): unknown money provider %q (this public layer"
            .. " supports: %s). Update the whole workshop item and restart.",
            tostring(spec.module), tostring(moneyKind), Core.moneyProviderNames()))
        return nil
    end

    local NS = {}

    -- 身份
    NS.MODULE = spec.module
    NS.VERSION = tostring(spec.version or "0.0.0")
    NS.TAG = spec.tag or (spec.module .. ".Contracts.v1")
    NS.TABLE = spec.sandboxTable or spec.module

    --[[
        sibling：同一个工坊物品里的**其它口味**（只读它们的存档，防止同一个 NPC 被两边雇走）。

        可以是一个字符串（两个口味）或一张字符串表（三个以上口味）。统一归一化成数组
        NS.SIBLING_MODULES；NS.SIBLING_MODULE 保留第一个，供旧调用点与自检读。
        指向自己的项被丢掉（历史 bug：生成器把 sibling 翻成了自己，于是"你雇过这个人"被
        读成"别人雇了他"，重招自己人反而被拒），并在日志里留一句。
    ]]
    local siblings = {}
    if type(spec.sibling) == "string" and spec.sibling ~= "" then
        siblings[1] = spec.sibling
    elseif type(spec.sibling) == "table" then
        for _, id in ipairs(spec.sibling) do
            if type(id) == "string" and id ~= "" then siblings[#siblings + 1] = id end
        end
    end
    for index = #siblings, 1, -1 do
        if siblings[index] == spec.module then
            table.remove(siblings, index)
            print("[" .. tostring(spec.module) .. "][WARN] spec.sibling points at this mod itself; ignored")
        end
    end
    NS.SIBLING_MODULES = siblings
    NS.SIBLING_MODULE = siblings[1]

    NS.TEXT_PREFIX = spec.textPrefix or ("IGUI_" .. spec.module .. "_")
    NS.PLAYER_PREFIX = spec.playerPrefix or (spec.module .. "Player_")
    NS.FLOW_ITEM = spec.flowItem or (spec.module .. ".contract")

    -- 经济模组
    NS.ECONOMY_GLOBAL = spec.economyGlobal
    NS.ECONOMY_SERVER_GLOBAL = spec.economyServerGlobal
    NS.ECONOMY_MOD_ID = spec.economyModId
    NS.ECONOMY_NAME = spec.economyName or spec.economyModId
    NS.CURRENCY_NAME = spec.currencyName

    -- 收钱方式（见文件头「钱的接口」）；入口装不上时打给玩家看的那句话
    NS.MONEY_KIND = moneyKind
    NS.UI_HINT = spec.uiHint or "the client UI host of this flavour is unavailable"

    -- 沙盒默认值的覆盖（Config.lua 在建 DEFAULTS 时套用；口味只在"沙盒表读不到"时用到它）
    NS.DEFAULTS_OVERRIDE = type(spec.defaults) == "table" and spec.defaults or nil

    -- 反查用（排障时能一眼看出这个 NS 是哪个口味、按哪份 spec 建的）
    NS.SPEC = spec

    return NS
end

-- 逗号分隔的实现名列表（错误日志与自检用）
function Core.moneyProviderNames()
    local names = {}
    for name, _ in pairs(Core.MONEY_PROVIDERS) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

--[[
    按依赖顺序把公共层的 12 个模块实例化到这个 NS 上。

    顺序是有意义的：Jimmy 在实例化时就 `local Alife = Config.Alife` 抓住兄弟模块的引用，
    所以 Alife 必须先于 Jimmy、Store 必须先于 Service，以此类推。顺序写在这里（而不是散在
    各口味的 Profile 里），就是为了让"公共层有哪些模块、谁依赖谁"只有一处真相。

    Economy 那一行按 NS.MONEY_KIND 选实现（"upstream" -> Economy.lua，"cash" -> Cash.lua）：
    两者给出同一组方法（见文件头「钱的接口」），Service/Maintain 看不见区别。

    Config 不参与赋值：它返回的就是 NS 自己（NS 上的 MODULE/TAG/… 已经建好了）。
]]
function Core.bind(NS)
    require("Bin2NPCExtensionCore/Config")(NS)
    NS.Text = require("Bin2NPCExtensionCore/Text")(NS)
    NS.Contracts = require("Bin2NPCExtensionCore/Contracts")(NS)
    NS.Store = require("Bin2NPCExtensionCore/Store")(NS)
    NS.Economy = require("Bin2NPCExtensionCore/" .. Core.MONEY_PROVIDERS[NS.MONEY_KIND])(NS)
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
