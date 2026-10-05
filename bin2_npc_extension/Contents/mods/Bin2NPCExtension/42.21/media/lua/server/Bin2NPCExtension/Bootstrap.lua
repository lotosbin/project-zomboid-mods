--[[
    Bin2NPCExtension :: Bootstrap（server，**只有接线**）

    服务端的全部逻辑在公共层（Bin2NPCExtensionBase 的 ServerBootstrap）。
    这里存在的唯一理由：公共层是 shared 文件，**多人客户端也会加载**；
    而"服务端事件只在服务端注册"这条语义必须由一个 server 层文件来表达。
]]

local NS = require "Bin2NPCExtension/Profile"
if NS == nil then return nil end

return NS.ServerBootstrap.install()
