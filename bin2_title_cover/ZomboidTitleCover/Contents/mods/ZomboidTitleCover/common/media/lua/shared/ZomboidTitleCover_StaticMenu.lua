--[[
    Zomboid 末世封面 / Zomboid Apocalypse Cover —— 让引擎走"可被覆盖的静态标题背景"

    背景（全部来自 Build 42.21 的引擎字节码，不是猜的）：

      zombie.gameStates.MainScreenState.renderBackground():
          if (Core.getInstance().getOptionDoVideoEffects()) { if (renderVideo()) return; }
          renderOriginalBackground(1.0f - lightningDelta * 0.6f);

    `renderVideo()` 播放 media/videos/title_screen_background.bik（真实存在，本机约 83 MB），
    而 `doVideoEffects` 这个选项的默认值是 **true**。也就是说：新档/新用户下引擎永远走视频
    分支，`renderOriginalBackground()` 根本不会被调用 —— **只把 Title*.png 放进 media/ui/
    是不够的**，视频会把图盖住。（本目录参考的 L4D2 Zombie Siege background 模组也是靠关掉
    这个选项才生效的，区别是它会 saveOptions() 把用户设置持久化掉。）

    所以本文件只做一件事：把 `doVideoEffects` 关掉，让引擎去画那些可以被模组覆盖的纹理。
    不碰 logoTexture、不碰菜单排版、不碰 lightningDelta（原版里恒为 0）。
]]

local LOG_TAG = "[ZomboidTitleCover] "

local state = {
    applied = false,        -- 选项已经处理过（成功走通了 get/set）
    hooked = false,         -- MainScreen.instantiate 已经挂上
    mainScreen = nil,       -- require 到的 MainScreen 类
}

--- 关闭"视频背景特效"，让引擎转去绘制可覆盖的 media/ui/Title*.png。
--- 幂等：只做一次；任何一步失败都安静早退，绝不让主菜单崩掉。
local function applyStaticTitleBackground()
    if state.applied then return end

    local core = getCore()
    if not core then return end

    local ok, err = pcall(function()
        if core:getOptionDoVideoEffects() then
            core:setOptionDoVideoEffects(false)
            -- 不调用 saveOptions()：只在本局内存里生效，不动用户的 options.ini。
            -- 想永久关掉的话，游戏内「选项 -> 视频背景特效」自己切一次即可。
            print(LOG_TAG .. "Video Effects disabled for this session so the modded "
                .. "media/ui/Title*.png is drawn instead of title_screen_background.bik")
        else
            print(LOG_TAG .. "Video Effects already off, using modded media/ui/Title*.png")
        end
    end)

    if ok then
        state.applied = true
    else
        print(LOG_TAG .. "cannot toggle Video Effects (" .. tostring(err)
            .. "); the vanilla .bik title video will cover this mod")
    end
end

--- 挂 MainScreen:instantiate。挂钩时机必须在任何一帧 renderBackground 之前。
local function hookMainScreen()
    if state.hooked then return true end

    -- 延迟 require：共享阶段里 OptionScreens/MainScreen 未必已经加载好
    local ok, mainScreen = pcall(require, "OptionScreens/MainScreen")
    if not ok or mainScreen == nil then
        return false
    end
    if type(mainScreen.instantiate) ~= "function" then
        return false
    end

    state.mainScreen = mainScreen
    local original = mainScreen.instantiate

    function mainScreen:instantiate(...)
        original(self, ...)
        if not self.inGame then          -- 游戏内复用这个界面时不要动全局选项
            applyStaticTitleBackground()
        end
    end

    state.hooked = true
    print(LOG_TAG .. "hooked MainScreen:instantiate()")
    return true
end

-- 载入即尝试一次；失败（模块还没加载）则交给下面的事件重试。
if not hookMainScreen() then
    Events.OnGameBoot.Add(function()
        if hookMainScreen() then
            applyStaticTitleBackground()
        end
    end)
end

-- 双保险：主菜单进入时再确认一次（也覆盖"hook 挂上时 instantiate 已经跑过"的加载顺序）
Events.OnMainMenuEnter.Add(function()
    hookMainScreen()
    applyStaticTitleBackground()
end)
