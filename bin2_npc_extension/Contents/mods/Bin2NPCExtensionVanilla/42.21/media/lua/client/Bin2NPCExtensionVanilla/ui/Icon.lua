--[[
    Bin2NPCExtensionVanilla :: ui/Icon（client）

    入口：把招募窗口挂到**原版左侧竖排图标栏**（ISEquippedItem —— 心/背包/建造那一列）最下面。

    为什么不新建一个浮动按钮：那条竖排栏是玩家最熟的"功能入口"位置（心=健康、背包、建造、
    家具、地图都在那儿），挂在它里面就自动获得原版的位置、尺寸档、拖动/隐藏行为。

    挂接的实现（含全部引擎侧约束、证据与备选方案）在**公共层**：
    `Bin2NPCExtensionCore/Sidebar.lua`（手写模块，见那一篇的注释与
    docs/research/vanilla-sidebar-entry.md §2）。这里只交本口味的那张 spec ——
    贴图名、悬停提示键、窗口开没开、点一下做什么。

    两态贴图：`media/ui/Sidebar/<尺寸>/NPC_{On,Off}_<尺寸>.png`（尺寸 = 48/64/80/96/128，
    真实像素 48x36 … 128x96，由 tools/make_icons.py 生成）。窗口开着时用 On。
]]

-- 引擎 UI 基类（游戏里由 client 层自动加载；require 只是显式声明，缺了也不该在加载期炸）
if type(require) == "function" then
    pcall(require, "ISUI/ISButton")
    pcall(require, "ISUI/ISEquippedItem")
end

-- 公共层（Bin2NPCExtensionBase）在 shared 层已经实例化好了命名空间
local Config = require "Bin2NPCExtensionVanilla/Profile"
if Config == nil then return nil end

-- 顺序声明：本文件要用 Config.RecruitPanel 打开窗口
require "Bin2NPCExtensionVanilla/ui/Panel"

local Icon = {}
Config.Entry = Icon

local T = Config.Text.get

--[[
    交给公共层的那张 spec。

    * `texture = "NPC"` —— 我们自己的两态贴图（10 张，五档 x On/Off），
      装在**本口味自己的** media/ui/Sidebar/ 下，不依赖别的口味是否启用。
    * `tooltip` 是**查好的文案**：公共层不认识任何翻译前缀，前缀这件事只有本口味自己知道
      （所以这里显式 `T("IconTooltip")` —— 顺带让 run.js 的翻译键扫描器看得见这个字面量）。
    * `toggle` 收到的参数是**面板所属的玩家序号**；招募窗口自己会用"玩家为空就取本地玩家"
      的兜底逻辑，所以这里忽略它也行 —— 但签名保持一致，两个口味才好读。
]]
local SPEC = {
    id = "BIN2NPCRECRUIT",
    texture = "NPC",
    tooltip = T("IconTooltip"),
    log = "sidebar icon hooked into ISEquippedItem (left column, below the vanilla buttons)",
    isOpen = function()
        return Config.RecruitPanel.isOpen()
    end,
    toggle = function()
        return Config.RecruitPanel.toggle(nil)
    end,
}

--[[
    装钩子。返回 true 表示"入口已经在（或已经不需要）"。

    公共层的 ClientBootstrap 会一直重试到 true：侧边栏是进世界时才建的，可能比我们晚。
]]
function Icon.install()
    return Config.Sidebar.install(SPEC)
end

--[[
    打开/关闭招募窗口（公共层把 Ctrl+Alt+N 送到这里）。

    侧边栏图标与热键走同一条路：开着就关、关着就开；热键**永远可用**，
    即使侧边栏图标没装上（翻译文案里承诺了 Ctrl+Alt+N，不能只靠鼠标）。
]]
function Icon.open()
    local player = Config.localPlayer and Config.localPlayer() or nil
    return Config.RecruitPanel.toggle(player)
end

return Icon
