--[[--------------------------------------------------------------------------
    ViewpointMac —— 客户端 Lua 入口（1.9）

    设计约定（按需求调整）：
      * **只有一个快捷键**：Ctrl+Alt+D 打开/关闭调试控制面板；
      * 所有开关（3D 场景、覆盖层、体素、地面、模型包、角色……）都在面板上点；
      * 不再为每个功能单独占一个快捷键。

    注意：所有对 Java 的调用都做了存在性与 pcall 保护 —— 即使 JAR 没被
    ZombieBuddy 装载（或被策略拦下），这个 Lua 文件也不会报错刷屏。
----------------------------------------------------------------------------]]

require "ISUI/ISPanel"
require "ISUI/ISButton"

local MOD = "ViewpointMac"

-- 与 Java 侧 Vp.VERSION / mod.info 的 modversion 保持一致。
-- Java class 不能热重载，而 Lua 会被游戏重载；两者不一致时必须明确报出来，
-- 否则新 Lua 调老 jar 的方法只会得到 nil，很难排查。
local LUA_VERSION = "2.2.0"

local function japi()
    if type(ViewpointMac) == "table" then return ViewpointMac end
    return nil
end

local function log(msg)
    print("[" .. MOD .. "] " .. tostring(msg))
end

local missingReported = {}

local function call(name, ...)
    local api = japi()
    if not api then return nil end
    local fn = api[name]
    if fn == nil then
        if not missingReported[name] then
            missingReported[name] = true
            log("java method '" .. name .. "' is not exposed - the JAR is older than this Lua file."
                .. " Java classes cannot hot-reload: restart the game.")
        end
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        log("java call " .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function printStatus()
    local status = call("status")
    if status then
        log(status)
    else
        log("java API unavailable (JAR not loaded?)")
        return
    end
    log("backend=" .. tostring(call("backend"))
        .. " gl=" .. tostring(call("glVersion"))
        .. " glsl=" .. tostring(call("glslVersion")))
    log("scene3d: " .. tostring(call("sceneInfo")))
    log("voxel: " .. tostring(call("voxelInfo")))
    log("mouse look: " .. tostring(call("mouseLookInfo")))
    log("sky: " .. tostring(call("skyInfo")))
    log("entities: " .. tostring(call("entitiesInfo")))
    log("character models: " .. tostring(call("characterModelsInfo")))
    log("floor uv: " .. tostring(call("floorUvInfo")))
    log("camera: " .. tostring(call("cameraInfo")))
end

-- 文字 HUD：用游戏自己的字体通道，避免在 GL 里手写位图字体。
-- 只在存档内绘制（主菜单阶段完全不碰 UI 渲染），任何异常只发生一次然后永久关闭。
local hudEnabled = true
local inGame = false

local function drawHud()
    if not hudEnabled or not inGame then return end
    if not japi() then hudEnabled = false; return end
    -- 面板开着的时候不重复显示状态行，避免叠字
    if VP_PANEL and VP_PANEL:getIsVisible() then return end

    local ok, err = pcall(function()
        local tm = getTextManager and getTextManager()
        if not tm then return end
        local text = call("status")
        if not text then return end
        local font = UIFont and UIFont.Small or nil
        if not font then return end
        -- B42 的签名是 DrawString(font, x, y, text, r, g, b, a) —— 字符串在第 4 个参数
        tm:DrawString(font, 18, 140, text, 0.9, 0.95, 1.0, 0.85)
    end)

    if not ok then
        hudEnabled = false
        log("text HUD disabled after an API mismatch: " .. tostring(err))
    end
end

--[[--------------------------------------------------------------------------
    调试控制面板（唯一的 UI 入口）
----------------------------------------------------------------------------]]

local ROW_H = 24

-- 面板上的布尔开关；名字与 Java 侧 VpConfig.option() 一一对应
local OPTIONS = {
    { name = "scene3d",         label = "3D scene" },
    { name = "overlay",         label = "2D info overlay" },
    { name = "mouseLook",       label = "Mouse look (hide cursor)" },
    { name = "voxel",           label = "Voxel world" },
    { name = "voxelFloor",      label = "Ground slabs (cover game)" },
    { name = "voxelModels",     label = "PZ Voxel Studio models" },
    { name = "voxelTextured",   label = "Vanilla sprite textures" },
    { name = "voxelSkipOwn3d",  label = "Yield to vanilla 3D" },
    { name = "characterModels", label = "Characters in our 3D" },
    { name = "entities",        label = "Entity boxes" },
    { name = "voxelWireframe",  label = "Wireframe only" },
    { name = "voxelSky",        label = "Sky box" },
    { name = "alignVanillaView", label = "Align to vanilla view" },
    { name = "coverVanilla", label = "3D world view (cover vanilla)" },
    { name = "controlFacing", label = "Character follows 3D view (aim)" },
    { name = "flipModelTextureV", label = "Flip model texture V" },
    { name = "invertMouseY", label = "Invert mouse Y" },
}

ViewpointMacPanel = ISPanel:derive("ViewpointMacPanel")

function ViewpointMacPanel:new(x, y)
    local o = ISPanel:new(x, y, 380, 120)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.88 }
    o.borderColor = { r = 0.45, g = 0.85, b = 0.55, a = 1 }
    o.moveWithMouse = true
    o.buttons = {}
    o:initialise()
    return o
end

function ViewpointMacPanel:addRow(label, onClick, width)
    local button = ISButton:new(8, self.nextY, width or (self.width - 16), ROW_H - 2, label, self, onClick)
    button:initialise()
    button:instantiate()
    button.borderColor = { r = 0.45, g = 0.85, b = 0.55, a = 0.55 }
    button.backgroundColor = { r = 0.05, g = 0.12, b = 0.07, a = 0.9 }
    self:addChild(button)
    self.nextY = self.nextY + ROW_H
    return button
end

function ViewpointMacPanel:createChildren()
    self.nextY = 30
    self.buttons = {}

    for _, opt in ipairs(OPTIONS) do
        local button = self:addRow("", ViewpointMacPanel.onToggle)
        button.optName = opt.name
        button.optLabel = opt.label
        table.insert(self.buttons, button)
    end

    -- 体素采样半径
    self.radiusMinus = self:addRow("-", ViewpointMacPanel.onRadiusMinus, 40)
    self.radiusShow = ISButton:new(52, self.radiusMinus.y, 150, ROW_H - 2,
        "Voxel radius", self, ViewpointMacPanel.onNoop)
    self.radiusShow:initialise(); self.radiusShow:instantiate()
    self:addChild(self.radiusShow)
    self.radiusPlus = ISButton:new(206, self.radiusMinus.y, 40, ROW_H - 2, "+", self, ViewpointMacPanel.onRadiusPlus)
    self.radiusPlus:initialise(); self.radiusPlus:instantiate()
    self:addChild(self.radiusPlus)
    self.nextY = self.nextY + ROW_H

    -- 一键预设（Viewpoint 等价）
    self.viewButton = self:addRow("Toggle view: vanilla / 3D  (Ctrl+Alt+V)", ViewpointMacPanel.onToggleView)
    self.presetButton = self:addRow("PRESET: FULL 3D (Viewpoint-like)", ViewpointMacPanel.onPreset)

    -- 其它操作
    self.uvButton = self:addRow("Ground UV", ViewpointMacPanel.onFloorUv)
    self.cameraButton = self:addRow("Camera mode", ViewpointMacPanel.onCamera)
    self.reportButton = self:addRow("Write report to file + console", ViewpointMacPanel.onReport)
    self.closeButton = self:addRow("Close", ViewpointMacPanel.onClose)

    self:setHeight(self.nextY + 14)
end

function ViewpointMacPanel:prerender()
    ISPanel.prerender(self)
    for _, button in ipairs(self.buttons) do
        local on = call("optionOn", button.optName)
        button:setTitle(button.optLabel .. ": " .. (on and "ON" or "OFF"))
    end
    if self.radiusShow then
        self.radiusShow:setTitle("Voxel radius: " .. tostring(call("optionInt", "voxelRadius")))
    end
    if self.uvButton then
        self.uvButton:setTitle("Ground UV mode: " .. tostring(call("floorUvMode")))
    end
end

-- ISUI 的回调签名是 onclick(clicktarget, button)
function ViewpointMacPanel:onToggle(button)
    local name = button.optName
    local now = call("optionOn", name)
    call("setOption", name, not now)
    log("option " .. tostring(name) .. " = " .. tostring(call("optionOn", name)))
end

function ViewpointMacPanel:onRadiusMinus()
    log("voxel radius = " .. tostring(call("addOptionInt", "voxelRadius", -2)))
end

function ViewpointMacPanel:onRadiusPlus()
    log("voxel radius = " .. tostring(call("addOptionInt", "voxelRadius", 2)))
end

function ViewpointMacPanel:onToggleView()
    toggle3dView()
end

function ViewpointMacPanel:onPreset()
    call("applyFull3dPreset")
    log("preset applied: FULL 3D (hide vanilla world + own camera + ground + models + characters + sky)")
    log("NOTE: the main menu stays normal - the world skip only applies in-game.")
end

function ViewpointMacPanel:onFloorUv()
    log("ground UV mode = " .. tostring(call("cycleFloorUv")))
    log("floor uv: " .. tostring(call("floorUvInfo")))
end

function ViewpointMacPanel:onCamera()
    local third = call("toggleCameraMode")
    log("camera = " .. (third and "third person" or "first person"))
end

function ViewpointMacPanel:onReport()
    log("report: " .. tostring(call("writeReport")))
    printStatus()
end

function ViewpointMacPanel:onClose()
    VP_TOGGLE_PANEL()
end

function ViewpointMacPanel:onNoop()
end

-- 面板打开时临时关掉鼠标视角（否则光标被隐藏，按钮点不到）
local savedMouseLook = nil

function VP_TOGGLE_PANEL()
    if not VP_PANEL then
        VP_PANEL = ViewpointMacPanel:new(60, 60)
        VP_PANEL:addToUIManager()
        VP_PANEL:setAlwaysOnTop(true)
    end
    local visible = VP_PANEL:getIsVisible()
    if visible then
        VP_PANEL:setVisible(false)
        if savedMouseLook ~= nil then
            call("setOption", "mouseLook", savedMouseLook)
            savedMouseLook = nil
        end
    else
        savedMouseLook = call("optionOn", "mouseLook")
        call("setOption", "mouseLook", false)
        VP_PANEL:setVisible(true)
    end
end

--[[--------------------------------------------------------------------------
    两个快捷键（就这两个）：
      Ctrl+Alt+D  打开/关闭调试控制面板
      Ctrl+Alt+V  在原版视图 / 3D 视图之间切换（等价于 coverVanilla 开关）
----------------------------------------------------------------------------]]

local PANEL_KEY = Keyboard.KEY_D
local VIEW_KEY = Keyboard.KEY_V

local function toggle3dView()
    local now = call("optionOn", "coverVanilla")
    call("setOption", "coverVanilla", not now)
    local on = call("optionOn", "coverVanilla")
    if on then
        -- 3D 视图需要不透明天空盖住原版；顺手确保它是开的
        if not call("optionOn", "voxelSky") then
            call("setOption", "voxelSky", true)
        end
    end
    log("view = " .. (on and "3D (covers vanilla)" or "vanilla (3D hidden)"))
end

local function modifierKeysAvailable()
    return type(isCtrlKeyDown) == "function" and type(isAltKeyDown) == "function"
end

local function onKeyPressed(key)
    if key ~= PANEL_KEY and key ~= VIEW_KEY then return end
    if modifierKeysAvailable() and not (isCtrlKeyDown() and isAltKeyDown()) then return end
    if key == PANEL_KEY then
        VP_TOGGLE_PANEL()
    else
        toggle3dView()
    end
end

local function checkVersionAndApi()
    local jarVersion = call("version")
    if jarVersion and jarVersion ~= LUA_VERSION then
        log("VERSION MISMATCH: jar=" .. tostring(jarVersion) .. " lua=" .. LUA_VERSION
            .. " -> restart the game (Java classes cannot hot-reload).")
    end
    local api = japi()
    if api then
        local names = {}
        for k, v in pairs(api) do
            names[#names + 1] = tostring(k) .. ":" .. type(v)
        end
        table.sort(names)
        log("java API (" .. #names .. "): " .. table.concat(names, " "))
    end
end

Events.OnGameStart.Add(function()
    inGame = true
    checkVersionAndApi()
    log("client ready - hotkeys: Ctrl+Alt+D = control panel, Ctrl+Alt+V = vanilla/3D view.")
    log("log file: " .. tostring(call("logPath")) .. " (state snapshots every ~5s)")
    printStatus()
end)

Events.OnMainMenuEnter.Add(function()
    inGame = false
    if VP_PANEL then
        VP_PANEL:setVisible(false)
    end
end)

Events.OnKeyPressed.Add(onKeyPressed)
Events.OnPostUIDraw.Add(drawHud)
