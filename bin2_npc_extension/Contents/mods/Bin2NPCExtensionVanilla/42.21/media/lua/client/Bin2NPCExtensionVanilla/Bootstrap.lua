--[[
    Bin2NPCExtensionVanilla :: Bootstrap（client，**只有接线**）

    客户端的全部逻辑在公共层（Bin2NPCExtensionBase 的 Net 与 ClientBootstrap）。
    这里存在的唯一理由：**界面容器是口味自己的**（ui/Panel.lua 招募窗口 + ui/Icon.lua
    左侧图标入口，原版 ISUI 与各家经济模组的 UI 原语完全不同），必须先把它加载好，
    公共层的接线才有东西可接；而"客户端事件只在客户端注册"这条语义也需要一个 client
    层文件来表达。
]]

local NS = require "Bin2NPCExtensionVanilla/Profile"
if NS == nil then return nil end

-- 顺序声明：公共层的 ClientBootstrap 通过 Config.Entry 使用它（Icon 会 require Panel）
require "Bin2NPCExtensionVanilla/ui/Icon"

return NS.ClientBootstrap.install()
