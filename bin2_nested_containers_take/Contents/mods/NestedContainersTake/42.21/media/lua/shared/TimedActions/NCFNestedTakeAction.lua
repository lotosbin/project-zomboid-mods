--[[
    从"嵌套包"里拿取物品（批量版）—— 机制沿用 Picking Meister

    为什么不用原版 ISInventoryTransferAction：它走 ContainerID 事务，而"嵌在板条箱/衣柜/尸体里的包"
    原版表达不了位置（containerIndex = -1 → 服务端 findObject() 得 null → 事务被拒）。

    这套做法：
      1. 参数只传 "物品 id 列表 + 容器引用"，服务端按 id 还原：
         bagParent:getItemById(bagId) -> bag:getInventory() -> 逐个 getItemById(itemId)
      2. 本动作定义了 complete()，于是引擎（LuaTimedActionNew）不会走"自定义同步"，
         客户端 start() 时 ActionManager.createNetTimedAction() 发 NetTimedActionPacket，
         服务端校验后自己跑一遍；LuaTimedActionNew.complete() 只在 !GameClient.client 时回调
         Lua 的 complete() ⇒ **搬运只在服务端发生**。
      3. complete() 手动搬运并显式同步；其中 sendReplaceItemInContainer(外层容器, 包, 包)
         会把整只包重发给客户端（InventoryContainer.save() 连包内内容一起序列化），
         用于刷新"包内视图"。
      4. 批量：一次动作搬多件（itemIds 逗号分隔），只有一次服务端往返。
]]

require "TimedActions/ISBaseTimedAction"

NCFNestedTakeAction = ISBaseTimedAction:derive("NCFNestedTakeAction")

local function splitIds(csv)
    local out = {}
    if not csv or csv == "" then return out end
    for id in string.gmatch(csv, "[^,]+") do
        local n = tonumber(id)
        if n then table.insert(out, n) end
    end
    return out
end

--- 按 id 还原"包 / 源容器 / 要拿的物品列表"。客户端与服务端都会调用（服务端在 isValid/complete/getDuration 里调用）
function NCFNestedTakeAction:updateResources()
    self.bagItem = nil
    self.srcContainer = nil
    self.items = {}
    if not self.itemIdsCsv or not self.bagId or not self.bagParent or not self.destContainer then
        return false
    end
    if not self.bagParent.getItemById then
        return false
    end
    self.bagItem = self.bagParent:getItemById(self.bagId)
    if not self.bagItem or not self.bagItem:IsInventoryContainer() then
        return false
    end
    self.srcContainer = self.bagItem:getInventory()
    if not self.srcContainer then
        return false
    end
    -- 逐个解析；已经不在了的（被别人先拿走）就跳过，不影响同批次其它物品
    for _, id in ipairs(splitIds(self.itemIdsCsv)) do
        local item = self.srcContainer:getItemById(id)
        if item then
            table.insert(self.items, item)
        end
    end
    return #self.items > 0
end

--- 校验：id 链可还原 + 目标容器允许且放得下 + 源容器允许取出。
--- 同时是"客户端提前拦截 / 引擎 valid() 判定 / 服务端 complete() 第一句的权威闸门"。
function NCFNestedTakeAction:isValid()
    if not self:updateResources() then
        return false
    end
    for _, item in ipairs(self.items) do
        if not self.destContainer:isItemAllowed(item) then
            return false
        end
        if not self.destContainer:hasRoomFor(self.character, item) then
            return false
        end
        local okCheck, canRemove = pcall(function()
            return self.srcContainer:isRemoveItemAllowed(item)
        end)
        if okCheck and canRemove == false then
            return false
        end
    end
    return true
end

--- 时长：按原版 ISInventoryTransferAction:new 的算法逐件累加（服务端以它作为权威时长）
function NCFNestedTakeAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    if not self:updateResources() then
        return 1
    end
    local character, srcContainer, destContainer = self.character, self.srcContainer, self.destContainer
    local total = 0
    for _, item in ipairs(self.items) do
        local maxTime = 120
        local destCapacityDelta = 1.0
        if srcContainer == character:getInventory() then
            if destContainer:isInCharacterInventory(character) then
                destCapacityDelta = destContainer:getCapacityWeight() / destContainer:getMaxWeight()
            else
                maxTime = 50
            end
        elseif not srcContainer:isInCharacterInventory(character) then
            if destContainer:isInCharacterInventory(character) then
                maxTime = 50
            end
        end
        if destCapacityDelta < 0.4 then destCapacityDelta = 0.4 end
        local w = item:getActualWeight()
        if w > 3 then w = 3 end
        maxTime = maxTime * w * destCapacityDelta
        if getCore():getGameMode() == "LastStand" then maxTime = maxTime * 0.3 end
        if character:hasTrait(CharacterTrait.DEXTROUS) then maxTime = maxTime * 0.5 end
        if character:hasTrait(CharacterTrait.ALL_THUMBS) or character:isWearingAwkwardGloves() then maxTime = maxTime * 2.0 end
        total = total + maxTime
    end
    -- 批量整体允许多花点时间，但设个上限，避免一次"全拿"卡很久
    if total > 600 then total = 600 end
    return total
end

--- 只在客户端执行（服务端走 serverStart；引擎不会在服务端调用 start()）
function NCFNestedTakeAction:start()
    self.loopSound = self.character:getEmitter():playSound("RummageInInventory")
    self:setActionAnim("Loot")
    self:setAnimVariable("LootPosition", "")
    self:setOverrideHandModels(nil, nil)
    self.character:clearVariable("LootPosition")
    if self.bagParent then
        if self.bagParent:getContainerPosition() then
            self:setAnimVariable("LootPosition", self.bagParent:getContainerPosition())
        end
        if self.bagParent:getType() == "freezer" and self.bagParent:getFreezerPosition() then
            self:setAnimVariable("LootPosition", self.bagParent:getFreezerPosition())
        end
        if instanceof(self.bagParent:getParent(), "IsoDeadBody") or self.bagParent:getType() == "floor" then
            self:setAnimVariable("LootPosition", "Low")
        end
    end
end

function NCFNestedTakeAction:stopLoopingSound()
    if self.loopSound then
        self.character:getEmitter():stopSound(self.loopSound)
        self.loopSound = nil
    end
end

function NCFNestedTakeAction:stop()
    self:stopLoopingSound()
    ISBaseTimedAction.stop(self)
end

function NCFNestedTakeAction:perform()
    self:stopLoopingSound()
    -- 客户端：让正开着的那个包重新指向"刷新后的容器对象"（见 Client.lua 的 NCFTake.schedulePaneRefresh）
    if isClient() and NCFTake and NCFTake.schedulePaneRefresh then
        local ok, err = pcall(NCFTake.schedulePaneRefresh, self.character, self.bagId)
        if not ok then
            print("[NestedContainersTake] WARN pane refresh scheduling failed: " .. tostring(err))
        end
    end
    ISBaseTimedAction.perform(self)
end

--- 服务端权威执行：引擎在 !GameClient.client 时才会回调这里
function NCFNestedTakeAction:complete()
    if not self:isValid() then
        return false
    end
    local bagParent, bagItem = self.bagParent, self.bagItem
    local moved = 0
    for _, item in ipairs(self.items) do
        -- 先 Add：ItemContainer:AddItem() 内部会把物品从原容器摘下；返回 nil（例如目标已有同 id）就跳过，源端未被动过
        local addedItem = self.destContainer:AddItem(item)
        if addedItem then
            sendRemoveItemFromContainer(self.srcContainer, item)
            sendAddItemToContainer(self.destContainer, addedItem)
            moved = moved + 1
        end
    end
    -- 整包替换一次：让客户端重收这只包（含包内内容），补上嵌套包容器"没有相对广播锚点"的洞
    if moved > 0 and bagParent and bagItem then
        sendReplaceItemInContainer(bagParent, bagItem, bagItem)
    end
    return moved > 0
end

function NCFNestedTakeAction:new(character, itemIdsCsv, bagId, bagParent, destContainer)
    local o = ISBaseTimedAction.new(self, character)
    o.itemIdsCsv = itemIdsCsv
    o.bagId = bagId
    o.bagParent = bagParent
    o.destContainer = destContainer
    o.bagItem = nil
    o.srcContainer = nil
    o.items = {}
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
