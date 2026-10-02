--[[
    从嵌套包里拿物品（批量）— 客户端拦截 + 包内视图刷新

    拦截 ISInventoryTransferAction:start()：
      * 只有当源容器是原版 ContainerID 寻址不了的嵌套包时才介入
      * 先做 PM 式可行性检查（外层容器 → 包 → 物品，全靠 id）
      * 通过后：把队列里**紧随其后、同一个源容器与目标容器**的搬运动作一起收进来，
        合成**一次** NCFNestedTakeAction（一次服务端往返搬多件 ⇒ 支持"全拿/多选"）
      * 自己空转完成（setTime(0)），搬运交给合成后的动作

    刷新问题：服务端用 sendReplaceItemInContainer(外层容器, 包, 包) 把整只包重发，
    但客户端会**新建**一份容器对象，而玩家正开着的 loot 面板还捏着旧对象
    ⇒ 包里那件物品看起来还在（内容没更新）。所以动作完成时在这里按包 id 找到新容器，
    把面板重新指过去（只在面板仍看着这只包时才动手）。
]]

local NCFTake = NCFTake or {}
NCFTake.PENDING = {}
NCFTake.REFRESH_TIMEOUT_MS = 3000

local function log(msg)
    print("[NestedContainersTake] " .. tostring(msg))
end

local function logOnce(msg)
    if not NCFTake.loggedOnce then
        NCFTake.loggedOnce = true
        log(msg)
    end
end

--- 源容器是否原版寻址不了（镜像 ContainerID.set 的分支；只看源端）
local function sourceNeedsRemoteTake(container)
    if not container then return false end
    if instanceof(container:getParent(), "IsoPlayer") then return false end
    local bag = container:getContainingItem()
    if not bag then return false end
    local bagContainer = bag:getContainer()
    if not bagContainer then return false end
    local parent = bagContainer:getParent()
    if instanceof(parent, "IsoPlayer") then return false end
    if instanceof(parent, "BaseVehicle") then return false end
    if bagContainer:getType() == "floor" then return false end
    if bag:getWorldItem() then return false end
    return true
end

--- PM 式可行性检查：外层容器 → 包 → 物品（全靠 id）
local function canTakeById(action)
    local src, item = action.srcContainer, action.item
    if not src or not item then return nil end
    local bag = src:getContainingItem()
    if not bag or not bag.IsInventoryContainer or not bag:IsInventoryContainer() then return nil end
    local bagParent = bag:getContainer()
    if not bagParent or not bagParent.getItemById then return nil end
    local resolvedBag = bagParent:getItemById(bag:getID())
    if not resolvedBag then return nil end
    local inner = resolvedBag:getInventory()
    if not inner or not inner:getItemById(item:getID()) then return nil end
    return bag, bagParent
end

--- 把队列里紧随其后、同源同目标的搬运动作并成一批（原版 checkQueueList 的思路）
local function collectBatchIds(self, queue, indexSelf, firstId)
    local ids = { tostring(firstId) }
    if not indexSelf or indexSelf == -1 then
        return table.concat(ids, ",")
    end
    local i = indexSelf + 1
    while i <= #queue.queue do
        local other = queue.queue[i]
        local mergeable = other
            and other.ncfNestedTakeStep ~= true
            and other.srcContainer == self.srcContainer
            and other.destContainer == self.destContainer
            and other.item
            and not other.onCompleteFunc
        if not mergeable then
            break
        end
        table.insert(ids, tostring(other.item:getID()))
        other.ncfNestedTakeStep = true      -- 标记已并入，避免它自己再触发一次
        table.remove(queue.queue, i)        -- 从队列里摘掉（与原版一致）
    end
    return table.concat(ids, ",")
end

--- 面板重选：按包 id 找到刷新后的容器，把正开着它的面板指过去（仅当面板确实看着这只包）
function NCFTake.tryRefreshPane(player, bagId)
    if not player or not bagId then return true end
    local function currentBagId(page)
        local pane = page and page.inventoryPane
        local inv = pane and pane.inventory
        local bag = inv and inv:getContainingItem()
        return bag and bag:getID() or nil
    end
    local function tryPage(page)
        if not page or not page.backpacks then return false end
        if currentBagId(page) ~= bagId then return false end      -- 玩家已经看别的容器了，别抢
        for _, button in ipairs(page.backpacks) do
            local inv = button.inventory
            local bag = inv and inv:getContainingItem()
            if bag and bag:getID() == bagId and inv ~= page.inventoryPane.inventory then
                page:selectButtonForContainer(inv)
                return true
            end
        end
        return false
    end
    local num = player:getPlayerNum()
    local playerPage = getPlayerInventory and getPlayerInventory(num) or nil
    if not playerPage then
        local data = getPlayerData and getPlayerData(num) or nil
        playerPage = data and data.playerInventory or nil
    end
    if tryPage(playerPage) then return true end
    return tryPage(getPlayerLoot(num))
end

--- 服务端的"整包刷新"包到达顺序不确定，所以排一个短时重试，直到成功或超时
function NCFTake.schedulePaneRefresh(player, bagId)
    table.insert(NCFTake.PENDING, {
        player = player,
        bagId = bagId,
        deadline = getTimestampMs() + NCFTake.REFRESH_TIMEOUT_MS,
    })
end

Events.OnPlayerUpdate.Add(function(player)
    if #NCFTake.PENDING == 0 then return end
    local now = getTimestampMs()
    local remaining = {}
    for _, job in ipairs(NCFTake.PENDING) do
        local done = false
        if job.player == player then
            local ok, refreshed = pcall(NCFTake.tryRefreshPane, job.player, job.bagId)
            done = ok and refreshed
        end
        if not done and now < job.deadline then
            table.insert(remaining, job)
        end
    end
    NCFTake.PENDING = remaining
end)

-- 单机不需要本模组（单机本来就能开包拿单品），也不该改变原有行为
if not isClient() then
    return
end

local OLD_start = ISInventoryTransferAction.start

function ISInventoryTransferAction:start()
    if not self.ncfNestedTakeStep then
        local ok, handled = pcall(function()
            if not self.item or not self.srcContainer or not self.destContainer then return false end
            if not sourceNeedsRemoteTake(self.srcContainer) then return false end
            local bag, bagParent = canTakeById(self)
            if not bag then return false end

            local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
            local indexSelf = queue and queue:indexOf(self) or -1
            local csv = collectBatchIds(self, queue, indexSelf, self.item:getID())

            local action = NCFNestedTakeAction:new(self.character, csv, bag:getID(), bagParent, self.destContainer)
            action.ncfNestedTakeStep = true
            ISTimedActionQueue.addAfter(self, action)
            self.ncfNestedTakeStep = true      -- 本次原版动作已被接管
            self.started = true
            self.action:setTime(0)             -- 自己空转完成，搬运交给合成后的动作
            NCFTake.count = (NCFTake.count or 0) + 1
            logOnce("nested take enabled: taking nested-bag items in batches (single server round-trip per batch)")
            return true
        end)
        if ok and handled then
            return
        end
        if not ok and not NCFTake.warned then
            NCFTake.warned = true
            print("[NestedContainersTake] WARN hook failed: " .. tostring(handled))
        end
    end
    return OLD_start(self)
end
