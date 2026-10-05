--[[
    Bin2NPCExtension :: Bootstrap（client）

    客户端只做三件事：
      1. 把招募页注册进橙子社区经济并装上首页入口（对方可能比我们晚就绪 → 重试到成功为止）；
      2. 挂一个热键（Ctrl+Alt+N）—— 对方全库没有任何按键绑定，不会冲突；
      3. 进世界时打一行自检日志（依赖状态 + 是否接上了 UI）。
]]

require "Bin2NPCExtension/Config"
require "Bin2NPCExtension/Net"
require "Bin2NPCExtension/ui/Entry"

local Config = Bin2NPCExtension
local Entry = Config.Entry

-- 幂等 + 防"Reset Lua"重入：判据是 Events 表的身份（同一张表 = 同一次会话，跳过；
-- 换表 = 引擎重置过 Lua，必须重新注册，否则 3 个处理器会静默失效）。
if Config.ClientBootstrapEvents == Events and Config.ClientBootstrap ~= nil then return Config.ClientBootstrap end
Config.ClientBootstrapEvents = Events

local Bootstrap = {}
Config.ClientBootstrap = Bootstrap

local HOTKEY = Keyboard and Keyboard.KEY_N or nil
local retries = 0
local installed = false
local lastTryMs = 0

--[[
    尝试接入 UI。橙子经济的 client 文件可能比我们晚加载（它们内部还有一长串 require），
    所以这里既要"文件加载时试一次"，也要在进世界后按秒重试（上限 Config.UI_RETRY_MAX）。
]]
function Bootstrap.tryInstall()
    if installed then return true end
    local ok, result = pcall(Entry.install)
    if not ok then
        Config.warn("UI install failed: " .. tostring(result))
        installed = true                    -- 出错就不再刷屏，日志里已经说清楚了
        return false
    end
    if result == true then
        installed = true
        return true
    end
    return false
end

local function modifiedKeysDown()
    local ctrl, alt = false, false
    pcall(function() ctrl = isCtrlKeyDown() == true end)
    pcall(function() alt = isAltKeyDown() == true end)
    return ctrl and alt
end

local function onKeyPressed(key)
    if HOTKEY == nil or key ~= HOTKEY then return end
    if not modifiedKeysDown() then return end
    local player = Config.localPlayer and Config.localPlayer() or nil
    local number = 0
    if player ~= nil and player.getPlayerNum ~= nil then
        local ok, value = pcall(player.getPlayerNum, player)
        if ok then number = math.max(0, math.floor(tonumber(value) or 0)) end
    end
    if Entry.open(number) then
        Config.log("recruit panel opened via hotkey")
    else
        Config.warn("hotkey pressed but the Orange economy UI is unavailable")
    end
end

local function onGameStart()
    Bootstrap.tryInstall()
    local ui = Config.economy()
    Config.always(string.format("client ready v%s | economy=%s page=%s",
        Config.VERSION,
        tostring(ui ~= nil),
        tostring(ui ~= nil and ui.UIPageRegistry ~= nil
            and type(ui.UIPageRegistry.Has) == "function"
            and ui.UIPageRegistry.Has(Config.RecruitPage.ID) == true)))
    Config.always("hotkey: Ctrl+Alt+N = NPC recruit panel")
end

local function onTick()
    if installed or retries >= Config.UI_RETRY_MAX then return end
    local now = Config.nowMs()
    if now - lastTryMs < 1000 then return end
    lastTryMs = now
    retries = retries + 1
    if not Bootstrap.tryInstall() and retries >= Config.UI_RETRY_MAX then
        Config.warn("gave up installing the recruit page after " .. tostring(retries)
            .. " attempts; is OrangeCommunityEconomy enabled?")
    end
end

if Events ~= nil then
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onGameStart) end
    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
    if Events.OnKeyPressed ~= nil then Events.OnKeyPressed.Add(onKeyPressed) end
end

-- 文件加载时先试一次（我们的 mod 声明了 loadModAfter，通常这时对方已经就绪）
Bootstrap.tryInstall()

return Bootstrap
