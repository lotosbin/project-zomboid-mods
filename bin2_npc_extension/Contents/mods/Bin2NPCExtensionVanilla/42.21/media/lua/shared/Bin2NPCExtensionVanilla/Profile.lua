--[[
    Bin2NPCExtensionVanilla :: Profile（shared）—— **本口味的全部差异都在这个文件里**

    「纯原版」口味：不依赖任何经济模组，用**原版钞票物品 Base.Money** 结算（签约金、派遣费、日薪）。
    左侧入口也不用经济模组的界面，而是原版左侧竖排图标栏（ISEquippedItem）里的一个 NPC 图标
    （见 ui/Icon.lua）。

    与另外两个口味（橙子社区经济版 / YeseMarket 版）的关系：

      * 三者共用公共层 Bin2NPCExtensionBase 的同一份逻辑（A-Life/Jeem 适配、契约模型、维护循环）；
      * 存档表、沙盒表、翻译前缀、玩家键前缀全部独立 —— 互不串档、互不覆盖对方的选项；
      * sibling 列了另外两个口味：**同一个 A-Life NPC 不能被两个口味同时雇走**
        （公共层的 Service.takenBySibling 会只读它们的存档表）。

    改这里的身份字段之前先读 docs/design.md §12「公共层抽取」与 §13「原版口味」：
    spec 里的 coreApi 与公共层的 Core.API 必须相等，否则本口味会打印一条明确的
    "请更新整个工坊物品"的错误日志并停用自己（拆分后只更新一半是最典型的坏法）。
]]

local Core = require "Bin2NPCExtensionCore/Namespace"

-- 公共层缺失（或没启用）时 require 会返回 nil：停用自己，但把话说清楚
if type(Core) ~= "table" or type(Core.namespace) ~= "function" then
    print("[Bin2NPCExtensionVanilla][ERROR] Bin2NPCExtensionBase is missing or not enabled."
        .. " Enable it too (the mod list auto-enables it when you pick this mod), then restart.")
    return nil
end

local NS = Core.namespace({
    module = "Bin2NPCExtensionVanilla",
    version = "0.4.0",
    coreApi = 2,

    -- 存档与沙盒：三个口味各一套，互不串档、互不覆盖对方的选项
    tag = "Bin2NPCExtensionVanilla.Contracts.v1",
    sandboxTable = "Bin2NPCExtensionVanilla",

    -- 同一个工坊物品里的另外两个口味：只读它们的存档，防止同一个 A-Life NPC 被两边同时雇走。
    -- spec.sibling 可以是字符串或字符串表（三个口味时必须是表，见 Namespace.lua）。
    sibling = { "Bin2NPCExtension", "Bin2NPCExtensionYese" },

    -- 我们自己的命名空间（翻译键 / 玩家键 / 账单条目）
    textPrefix = "IGUI_Bin2NPCExtensionVanilla_",
    playerPrefix = "Bin2NPCExtensionVanillaPlayer_",
    flowItem = "Bin2NPCExtensionVanilla.contract",

    -- 收钱方式：原版钞票物品（不需要任何经济模组；翻译键里也写作「钞票」）
    money = "cash",
    currencyName = "钞票",

    -- 沙盒默认值：钞票据稀缺，签约/派遣/日薪都比另两个口味低一个数量级。
    -- 这份值必须与 media/sandbox-options.txt 里的 default 一致 ——
    -- 前者是"沙盒表整个读不到"时的兜底（见 Config.DEFAULTS 上面的说明），
    -- 两边不一致会让玩家在那种情况下看到另一套价格。
    defaults = { SignPrice = 50, SpawnPrice = 200, DailyWage = 5 },

    -- 入口装不上时打给人看的那句话（ClientBootstrap 试满 Config.UI_RETRY_MAX 次后打印）
    uiHint = "the vanilla left sidebar (ISEquippedItem) was not found."
        .. " Another mod may be replacing the HUD",
})

if NS == nil then return nil end          -- coreApi 不符 / 收钱方式认不出：Core.namespace 已经打过日志

Core.bind(NS)

Bin2NPCExtensionVanilla = NS
return NS
