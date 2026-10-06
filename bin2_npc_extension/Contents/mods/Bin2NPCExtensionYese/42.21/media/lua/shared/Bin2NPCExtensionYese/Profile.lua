--[[
    Bin2NPCExtensionYese :: Profile（shared）—— **本口味的全部差异都在这个文件里**

    「YeseMarket」口味：把公共层（模组 Bin2NPCExtensionBase）按本口味的身份实例化。
    公共层里不含任何口味身份，所以差异只剩：

      * 这张 spec（mod id / 存档表名 / 沙盒表名 / 翻译前缀 / 经济模组的全局名与显示名）；
      * ui/Entry.lua（怎么挂进对方的界面）与 ui/Page.lua（用对方的 UI 原语画列表）——
        这两件事各经济模组的 API 不一样，没法共用；
      * mod.info / 翻译 JSON / 沙盒选项。

    改这里的身份字段之前先读 docs/design.md §12「公共层抽取」：
    spec 里的 coreApi 与公共层的 Core.API 必须相等，否则本口味会打印一条明确的
    "请更新整个工坊物品"的错误日志并停用自己（拆分后只更新一半是最典型的坏法）。
]]

local Core = require "Bin2NPCExtensionCore/Namespace"

-- 公共层缺失（或没启用）时 require 会返回 nil：停用自己，但把话说清楚
if type(Core) ~= "table" or type(Core.namespace) ~= "function" then
    print("[Bin2NPCExtensionYese][ERROR] Bin2NPCExtensionBase is missing or not enabled."
        .. " Enable it too (the mod list auto-enables it when you pick this mod), then restart.")
    return nil
end

local NS = Core.namespace({
    module = "Bin2NPCExtensionYese",
    version = "0.4.0",
    coreApi = 2,

    -- 存档与沙盒：三个口味各一套，互不串档、互不覆盖对方的选项
    tag = "Bin2NPCExtensionYese.Contracts.v1",
    sandboxTable = "Bin2NPCExtensionYese",

    -- 同一个工坊物品里的另外两个口味：只读它们的存档，防止同一个 A-Life NPC 被两边同时雇走
    -- （三个口味时必须是表；两个口味时可以写字符串，见公共层 Namespace.lua）
    sibling = { "Bin2NPCExtension", "Bin2NPCExtensionVanilla" },

    -- 我们自己的命名空间（翻译键 / 玩家键 / 账单条目）
    textPrefix = "IGUI_Bin2NPCExtensionYese_",
    playerPrefix = "Bin2NPCExtensionYesePlayer_",
    flowItem = "Bin2NPCExtensionYese.contract",

    -- 收钱方式：默认（不写 money）就是用上游经济模组的服务端 Pay/AddCoins
    -- 经济模组（YeseMarket 3735641567）：客户端全局 / 服务端全局 / 工坊 id / 显示名
    economyGlobal = "YeseMarket",
    economyServerGlobal = "YeseMarketServer",
    economyModId = "YeseMarket",
    economyName = "YeseMarket",
    currencyName = "金币",

    -- 入口（经济窗口首页的按钮）装不上时打给人看的那句话
    uiHint = "is YeseMarket enabled?",
})

if NS == nil then return nil end          -- coreApi 不符：Core.namespace 已经打过日志

Core.bind(NS)

Bin2NPCExtensionYese = NS
return NS
