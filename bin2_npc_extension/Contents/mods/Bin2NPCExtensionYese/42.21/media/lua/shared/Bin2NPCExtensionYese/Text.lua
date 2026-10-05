--[[
    Bin2NPCExtensionYese :: Text（shared）

    我们自己的翻译命名空间：IGUI_Bin2NPCExtensionYese_*，文件在
    media/lua/shared/Translate/<LANG>/IG_UI.json。

    为什么不复用橙子经济的 YeseMarket.Text()：
    那个函数会把所有不以 "IGUI_YeseMarket_" 开头的键**强行加前缀**，
    我们没法在不污染对方命名空间的前提下使用它。所以这里自己做同样的"取不到就退化"逻辑。
]]

Bin2NPCExtensionYese = Bin2NPCExtensionYese or {}
local Text = {}
Bin2NPCExtensionYese.Text = Text

Text.PREFIX = "IGUI_Bin2NPCExtensionYese_"

--[[
    取翻译。取不到时退回键名（去掉前缀），方便在游戏里一眼看出漏翻了哪一条。

    getText 在 Kahlua 里是宽松的：多传参数没问题，少传会原样吐出 %1，
    所以这里按 select('#') 分流，与橙子经济的做法一致。
]]
function Text.get(key, ...)
    local name = tostring(key or "")
    if string.sub(name, 1, #Text.PREFIX) ~= Text.PREFIX then
        name = Text.PREFIX .. name
    end
    if type(getText) ~= "function" then
        return string.gsub(name, "^" .. Text.PREFIX, "")
    end
    local ok, value
    if select("#", ...) > 0 then
        ok, value = pcall(getText, name, ...)
    else
        ok, value = pcall(getText, name)
    end
    if ok and type(value) == "string" and value ~= "" and value ~= name then
        return value
    end
    return (string.gsub(name, "^" .. Text.PREFIX, ""))
end

-- 岗位名（follow / guard / resident）→ 翻译
function Text.mode(mode)
    local value = tostring(mode or "follow")
    if value == "guard" then return Text.get("ModeGuard") end
    if value == "resident" then return Text.get("ModeResident") end
    return Text.get("ModeFollow")
end

-- 契约状态 → 翻译
function Text.status(status)
    local value = tostring(status or "active")
    if value == "dead" then return Text.get("StatusDead") end
    if value == "dismissed" then return Text.get("StatusDismissed") end
    if value == "unpaid" then return Text.get("StatusUnpaid") end
    return Text.get("StatusActive")
end

--[[
    失败码 → 人话。

    这里的码分两类：
      * 我们自己的（no_funds / no_alife / limit_reached …）
      * 转述上游的（Jeem 的 not_allied / no_beds，A-Life 的 shell_hydration_failed …）
    上游的码不做穷举翻译，统一用 RecruitFailedUpstream + 原始码，避免上游改字串后我们露出错文案。
]]
local REASONS = {
    no_funds = "ReasonNoFunds",
    no_alife = "ReasonNoAlife",
    no_economy = "ReasonNoEconomy",
    disabled = "ReasonDisabled",
    limit_reached = "ReasonLimitReached",
    already_hired = "ReasonAlreadyHired",
    taken_by_other = "ReasonTakenByOther",
    not_found = "ReasonNotFound",
    not_active = "ReasonNotActive",
    too_far = "ReasonTooFar",
    hostile = "ReasonHostile",
    spawn_failed = "ReasonSpawnFailed",
    not_yours = "ReasonNotYours",
    no_jeem = "ReasonNoJeem",
    too_fast = "ReasonTooFast",
    duplicate = "ReasonDuplicate",
    pending = "ReasonPending",
    dead = "StatusDead",
    unpaid = "ReasonUnpaid",

    --[[
        Jeem 的拒绝码（`Features/Residents/Server.lua:519-558` 的 refusals 表）。

        为什么要穷举：这些码会**原样进契约的 note**，玩家在面板上看到的就是它。
        不翻的话 `Text.reason` 会落到 ReasonUpstream，玩家看到的是
        「居民化被拒（resident（上游返回）），已降级为跟随」—— 策划案里没有一句人话
        （本轮线上就是这么暴露的：`resident` 的真实含义是"他已经是居民了"）。
        上游改字串的风险由 ReasonUpstream 兜底，所以这里翻错也不会崩。
    ]]
    not_allied = "ReasonNotAllied",
    resident = "ReasonAlreadyResident",
    garrison = "ReasonGarrison",
    trader = "ReasonTrader",
    busy = "ReasonBusy",
    no_base = "ReasonNoBase",
    beds_unknown = "ReasonBedsUnknown",
    no_beds = "ReasonNoBeds",
    full = "ReasonFull",
    full_cap = "ReasonFullCap",
    moving = "ReasonMoving",
    off = "ReasonJeemOff",
    unavailable = "ReasonJeemNotReady",
    no_areas = "ReasonNoAreas",
    create_failed = "ReasonBaseCreateFailed",
    update_failed = "ReasonBaseUpdateFailed",
    already_resident = "ReasonAlreadyResident",
    leave_busy = "ReasonLeaveBusy",
    left_residence = "ReasonLeftResidence",
}

-- 带前缀的复合 reason（我们在 Service 里拼出来的，例如 "resident:no_beds"）
local PREFIXES = {
    resident = "ReasonResidentRefused",
    guard = "ReasonGuardRefused",
    follow = "ReasonFollowRefused",
}

function Text.reason(code)
    local value = tostring(code or "")
    if value == "" then return "" end
    local key = REASONS[value]
    if key ~= nil then return Text.get(key) end
    for prefix, wrapper in pairs(PREFIXES) do
        local head, tail = string.match(value, "^([a-z_]+):(.+)$")
        if head == prefix and tail ~= nil then
            return Text.get(wrapper, Text.reason(tail))
        end
    end
    return Text.get("ReasonUpstream", value)
end

return Text
