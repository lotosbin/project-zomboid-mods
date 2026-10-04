--[[
    ALifeStartWithNPC :: Config
    读取沙盒选项、日志、per-角色/ per-存档 标记键。

    设计要点（全部来自对 A-Life 1.3.15 与 Jeem 0.4.6 的实测）：
      * 选项名用我们自己的表 ALifeStartWithNPC.*，绝不写 ALife.*（会污染 A-Life 的 SandboxVars 表）。
      * 日志统一前缀 [ALifeStartWithNPC]，便于玩家把 console.txt 发给我们。
      * 幂等键分两层：角色级（modData）+ 存档级（ModData），见 Grant.lua。
]]

ALifeStartWithNPC = ALifeStartWithNPC or {}

local Config = ALifeStartWithNPC

Config.MODULE = "ALifeStartWithNPC"      -- 网络 module 名必须等于自己的 mod id（A-Life 的红线）
Config.VERSION = "0.1.5"

-- 沙盒表名（mod.info 的 id 一致）
Config.TABLE = "ALifeStartWithNPC"

-- 角色 modData 键
Config.KEY_GRANTED = "ALifeStartWithNPCGranted"   -- 本角色已发放
Config.KEY_TOKEN = "ALifeStartWithNPCToken"       -- 本角色的一次性令牌（用于 operationId 唯一化）
Config.KEY_ATTEMPTS = "ALifeStartWithNPCAttempts"          -- 生成尝试次数（按角色记，随死亡重置）
Config.KEY_LAST_ATTEMPT_MS = "ALifeStartWithNPCLastMs"     -- 上次尝试时间戳

-- 存档级 ModData 键（GrantOnRespawn = false 时用）
Config.SAVE_TAG = "ALifeStartWithNPC.Save.v1"

-- 等待世界就绪的最长时间（毫秒）；超时后转交每分钟重试
Config.READY_TIMEOUT_MS = 90000
Config.RETRY_MAX = 5

-- 生成重试节流（防止"数据没就绪"时每帧 create/remove，把日志刷爆）
Config.SPAWN_RETRY_MS = 2000      -- 两次生成尝试之间至少间隔
Config.MAX_SPAWN_ATTEMPTS = 5     -- 每个玩家每会话最多尝试几次

-- 兼容旧版本沙盒表可能不存在的情况
function Config.opt(key, default)
    local ok, value = pcall(function()
        local vars = SandboxVars
        local table_ = vars and vars[Config.TABLE]
        if type(table_) ~= "table" then return nil end
        return table_[key]
    end)
    if ok and value ~= nil then return value end
    return default
end

function Config.enabled()
    return Config.opt("Enabled", true) == true
end

function Config.verbose()
    return Config.opt("DebugLog", true) == true
end

function Config.count()
    local n = math.floor(tonumber(Config.opt("Count", 1)) or 1)
    if n < 1 then n = 1 end
    if n > 5 then n = 5 end
    return n
end

function Config.distance()
    local n = math.floor(tonumber(Config.opt("Distance", 2)) or 2)
    if n < 1 then n = 1 end
    if n > 6 then n = 6 end
    return n
end

-- 1 = 居民（需要 Jeem），2 = 普通同伴
function Config.mode()
    local n = math.floor(tonumber(Config.opt("Mode", 1)) or 1)
    return n == 2 and 2 or 1
end

function Config.residentMode()
    return Config.mode() == 1
end

-- 是否在生成瞬间把该 NPC 的阵营声望拉到「同盟」（Jeem 声望阶梯最高档）
function Config.makeAllied()
    return Config.opt("MakeAllied", true) == true
end

function Config.createCamp()
    return Config.opt("Resident_CreateCamp", true) == true
end

function Config.grantOnRespawn()
    return Config.opt("GrantOnRespawn", true) == true
end

function Config.factionId()
    local id = Config.opt("FactionId", "")
    if type(id) ~= "string" or id == "" then return nil end
    return id
end

function Config.profileId()
    local id = Config.opt("ProfileId", "")
    if type(id) ~= "string" or id == "" then return nil end
    return id
end

-- 日志：详细日志关闭时只输出错误级
function Config.log(message, force)
    if force or Config.verbose() then
        print("[" .. Config.MODULE .. "] " .. tostring(message))
    end
end

function Config.warn(message)
    print("[" .. Config.MODULE .. "][WARN] " .. tostring(message))
end

function Config.error(message)
    print("[" .. Config.MODULE .. "][ERROR] " .. tostring(message))
end

return Config
