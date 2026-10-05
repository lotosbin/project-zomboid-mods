--[[
    Bin2NPCExtension :: Bootstrap（client，**只有接线**）

    客户端的全部逻辑在公共层（Bin2NPCExtensionBase 的 Net 与 ClientBootstrap）。
    这里存在的唯一理由：**页面容器是口味自己的**（ui/Entry.lua → ui/Page.lua，
    不同经济模组的 UI 原语不一样），必须先把它加载好，公共层的接线才有东西可接；
    而"客户端事件只在客户端注册"这条语义也需要一个 client 层文件来表达。
]]

local NS = require "Bin2NPCExtension/Profile"
if NS == nil then return nil end

-- 顺序声明：公共层的 ClientBootstrap 通过 Config.Entry / Config.RecruitPage 使用它
require "Bin2NPCExtension/ui/Entry"

return NS.ClientBootstrap.install()
