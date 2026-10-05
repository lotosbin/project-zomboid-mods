--[[
    Bin2NPCExtensionYese :: Config（shared，客户端与服务端共用）

    职责：常量、沙盒选项读取、日志、探测三个依赖是否可用。

    设计红线（来自 A-Life 生态的历史教训，见 docs/research/jeem-recruit-api.md §8）：
      * 网络 module 名只能是**我们自己的 mod id**；"ProjectALife" 与 "ProjectALifeJimmy"
        分别是 A-Life 与 Jeem 的命令通道，第三方复用会撞车。
      * 绝不把 A-Life / Jeem 的 Lua 文件复制进本包（A-Life 的 Compat.foreignCopies 会点名）。
      * 缺依赖只降级、不报错：任何一处都用存在性探测 + pcall。
]]

Bin2NPCExtensionYese = Bin2NPCExtensionYese or {}

local Config = Bin2NPCExtensionYese

-- 翻译工具挂到同一张表上（Text 不依赖 Config，没有循环 require）
require "Bin2NPCExtensionYese/Text"

Config.MODULE = "Bin2NPCExtensionYese"       -- 必须等于 mod.info 的 id
Config.VERSION = "0.2.1"
Config.TAG = "Bin2NPCExtensionYese.Contracts.v1"   -- 我们自己的 ModData 存档表

--[[
    同一个工坊物品里的"另一个口味"的 mod id（可选）。

    这两个模组可以同时启用、名册各自独立，但**同一个 A-Life NPC 不能被两边同时雇走**，
    所以 Service.hireExisting 会顺手读一眼兄弟模组的存档（只读、拿不到就当没有）。
    生成器会把这一行在变体里翻成对方的 id（见 tools/fork_variant.py 的 PRE_SUBS_PATCHES）。
]]
Config.SIBLING_MODULE = "Bin2NPCExtensionYese"
Config.SCHEMA = 1

-- 存储结构里的模式常量
Config.MODE_FOLLOW = "follow"
Config.MODE_GUARD = "guard"
Config.MODE_RESIDENT = "resident"

-- 沙盒选项表名
Config.TABLE = "Bin2NPCExtensionYese"

-- 沙盒选项默认值（沙盒表缺失时用同一份默认值）
Config.DEFAULTS = {
    Enabled = true,
    MaxContracts = 3,
    SignPrice = 500,
    SpawnPrice = 1500,
    RecruitRadius = 6,
    AllowHostile = false,
    MakeAllied = true,
    SpawnDistance = 2,
    WageEnabled = true,
    DailyWage = 20,
    UnpaidGraceDays = 1,
    DefaultMode = 1,          -- 1 = follow, 2 = guard, 3 = resident
    CreateCamp = true,
    DebugLog = false,
}

-- 客户端每次进入世界最多尝试注册 UI 的次数（橙子经济可能比我们晚加载）
Config.UI_RETRY_MAX = 60

--[[
    读沙盒选项。

    为什么用 pcall：SandboxVars 是引擎注入的全局，单机/联机客户端专用服上可能缺失，
    而且我们的沙盒表在玩家没碰过时可能整个不存在。
]]
function Config.opt(key, default)
    local fallback = default
    if fallback == nil then fallback = Config.DEFAULTS[key] end
    local ok, value = pcall(function()
        local vars = SandboxVars
        local table_ = vars and vars[Config.TABLE]
        if type(table_) ~= "table" then return nil end
        return table_[key]
    end)
    if ok and value ~= nil then return value end
    return fallback
end

function Config.int(key, minimum, maximum)
    local value = math.floor(tonumber(Config.opt(key)) or 0)
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

function Config.flag(key)
    return Config.opt(key) == true
end

function Config.enabled()
    return Config.flag("Enabled")
end

function Config.verbose()
    return Config.flag("DebugLog")
end

function Config.maxContracts()
    return Config.int("MaxContracts", 1, 10)
end

function Config.signPrice()
    return Config.int("SignPrice", 0, 100000)
end

function Config.spawnPrice()
    return Config.int("SpawnPrice", 0, 100000)
end

function Config.recruitRadius()
    return Config.int("RecruitRadius", 2, 20)
end

function Config.spawnDistance()
    return Config.int("SpawnDistance", 1, 8)
end

function Config.dailyWage()
    return Config.int("DailyWage", 0, 10000)
end

function Config.unpaidGraceDays()
    return Config.int("UnpaidGraceDays", 0, 7)
end

-- 默认岗位：沙盒里是 1/2/3 的枚举
function Config.defaultMode()
    local value = Config.int("DefaultMode", 1, 3)
    if value == 2 then return Config.MODE_GUARD end
    if value == 3 then return Config.MODE_RESIDENT end
    return Config.MODE_FOLLOW
end

function Config.allowHostile() return Config.flag("AllowHostile") end
function Config.makeAllied() return Config.flag("MakeAllied") end
function Config.wageEnabled() return Config.flag("WageEnabled") end
function Config.createCamp() return Config.flag("CreateCamp") end

-- 岗位是否合法；非法一律落回 follow
function Config.normalizeMode(mode)
    local value = tostring(mode or "")
    if value == Config.MODE_GUARD or value == Config.MODE_RESIDENT or value == Config.MODE_FOLLOW then
        return value
    end
    return Config.MODE_FOLLOW
end

-- 日志：统一前缀，方便玩家把 console.txt 直接发给我们
function Config.log(message)
    if Config.verbose() then
        print("[" .. Config.MODULE .. "] " .. tostring(message))
    end
end

function Config.always(message)
    print("[" .. Config.MODULE .. "] " .. tostring(message))
end

function Config.warn(message)
    print("[" .. Config.MODULE .. "][WARN] " .. tostring(message))
end

function Config.error(message)
    print("[" .. Config.MODULE .. "][ERROR] " .. tostring(message))
end

--[[
    当前世界已过去多少小时（A-Life / Jeem 的通行时间轴）。

    取不到就返回 0：只影响工资结算与"签约时长"的显示，不影响功能本身。
]]
function Config.worldHours()
    local ok, hours = pcall(function()
        if type(getGameTime) ~= "function" then return nil end
        local time = getGameTime()
        if time == nil then return nil end
        return time:getWorldAgeHours()
    end)
    if ok and tonumber(hours) ~= nil then return math.max(0, tonumber(hours)) end
    return 0
end

-- 毫秒时间戳（取不到退化为 0，仅用于日志与节流）
function Config.nowMs()
    local ok, value = pcall(getTimestampMs)
    if ok and tonumber(value) ~= nil then return math.max(0, math.floor(tonumber(value))) end
    return 0
end

--[[
    版本无关的"表里有多少项"计数（Kahlua 没有 next()，不能靠 next(t) == nil 判空）。
    调用方自己维护 count，这里只作为兜底工具。
]]
function Config.count(source)
    local total = 0
    if type(source) ~= "table" then return 0 end
    for _ in pairs(source) do total = total + 1 end
    return total
end

--[[
    依赖探测：YeseMarket（硬依赖，但探测写法保持软性）
]]
function Config.economy()
    local mod = rawget(_G, "YeseMarket")
    if type(mod) ~= "table" then return nil end
    return mod
end

function Config.economyServer()
    local server = rawget(_G, "YeseMarketServer")
    if type(server) ~= "table" then return nil end
    if type(server.PlayerData) ~= "function" then return nil end
    return server
end

--[[
    依赖探测：A-Life 核心。

    只探测 server 侧的表（ActorRegistry / SpawnService）—— 它们只在世界开始后才存在，
    所以"能造人"这件事必须每次调用现探，不能缓存。
]]
function Config.alife()
    local alife = rawget(_G, "ProjectALife")
    if type(alife) ~= "table" then return nil end
    local registry = alife.ActorRegistry
    local spawn = alife.SpawnService
    if type(registry) ~= "table" or type(registry.read) ~= "function" then return nil end
    if type(spawn) ~= "table" or type(spawn.request) ~= "function" then return nil end
    return alife
end

--[[
    依赖探测：Jeem Extension。

    判据按可靠性排序（见报告 §8）：
      1. 全局表存在（shared 文件启动即建表）；
      2. J.enabled("residents") 没被玩家关掉（拿不到就当作开）；
      3. R.recruit 存在 —— 它在 server 文件里，只有世界开始后才有。
]]
function Config.jeem()
    local jeem = rawget(_G, "ProjectALifeJimmy")
    if type(jeem) ~= "table" then return nil end
    local residents = jeem.Residents
    if type(residents) ~= "table" or type(residents.recruit) ~= "function" then return nil end
    if type(jeem.enabled) == "function" then
        local ok, on = pcall(jeem.enabled, "residents")
        if ok and on ~= true then return nil end
    end
    return jeem
end

return Config
