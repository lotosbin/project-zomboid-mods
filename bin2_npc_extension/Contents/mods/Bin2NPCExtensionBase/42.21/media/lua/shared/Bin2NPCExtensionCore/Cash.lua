Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}

--[[
    公共层工厂（**本文件是手写的**，与 Namespace.lua 一样不由 tools/extract_base.py 生成）。

    收钱方式的第二个实现：**原版钞票物品**，不需要任何经济模组。
    口味在 Profile.lua 里写 `money = "cash"` 就会选中它（见 Namespace.lua 的 Core.MONEY_PROVIDERS）。

    单位与物品（证据见 docs/research/vanilla-money-integration.md）
    ------------------------------------------------------------
      * `Base.Money`       一张钞票 = 1 个单位（media/scripts/generated/items/normal.txt:8636，
                           weight 0.01，带 base:fitswallet）；
      * `Base.MoneyBundle` 一捆 = **100** 张。唯一依据是游戏自己的配方
                           `craftRecipe UnbundleMoney`（recipes/recipes_packing.txt:168-182）
                           的 outputs 写着 `item 100 Base.Money`。不认捆会让"身上带一捆钱
                           却雇不起人"变成必然事件。

    B42 没有"堆叠数量"这回事 —— 这决定了整个算法的形状
    --------------------------------------------------
      * `InventoryItem.CanStack()` / `CanStackNoTemp()` 在字节码里是 `iconst_0; ireturn`（恒 false），
        `count` 恒为 1、**不进存档、不进 SyncItemFieldsPacket**，全游戏 Lua 零处 `:setCount(`。
      * 所以**没有"部分扣除/找零"的引擎原语**：一个钞票物品实例永远值 1，
        "给一捆收 30、找回 70" 只能靠**删掉一捆 + 新发 70 张**来实现。
      * 于是扣款算法写成：先用散钞（删 N 个实例），不够再破捆（删 1 捆，找零 ≤99 张）。

    钱在哪儿：主背包 + **穿戴中的容器**
    ----------------------------------
      * `IsoGameCharacter.setWornItem` 会把穿戴的容器从主背包里 `Remove` 掉
        （javap：offset 163-169），所以 `player:getInventory():getCountTypeRecurse(...)`
        **数不到背着的背包/腰包里的钱**。必须另外遍历 Human 身体部位上的容器。
      * 容器内部的嵌套（背包里的钱包）由 `getItemsFromType(type, true)` / `getCountTypeRecurse`
        的 recurse 参数覆盖，不用自己递归。

    联机：改完背包必须显式发包
    --------------------------
      `AddItem` / `Remove` / `RemoveAll` **都不发包**；`setDrawDirty(true)` 只是本地 UI 脏标记。
      真正的同步是引擎全局（javap：zombie.Lua.LuaManager$GlobalObject）：
          sendRemoveItemsFromContainer(ItemContainer, ArrayList)
          sendAddItemsToContainer(ItemContainer, ArrayList)
      游戏自己的写法见 media/lua/server/ClientCommands.lua:210-218、
      Camping/BuildingObjects/campingCampfire.lua:8-9、ISShovelGround.lua:101-104。
      非服务器进程里这两个调用是精确 no-op（INetworkPacket.send 首指令判 GameServer.server），
      所以单机/主机下照调不误。
]]

local function factory(NS)
    --[[
        Bin2NPCExtensionCore :: Cash（公共层工厂，原版钞票结算）

        实现的是 Namespace.lua 文件头里那组"钱的接口"：
            available / balance / pay / refund / flow / wage
    ]]

    local Config = NS

    local Cash = {}
    Config.Economy = Cash

    Cash.ITEM = "Base.Money"
    Cash.BUNDLE = "Base.MoneyBundle"
    -- 一捆 = 100 张（游戏配方 UnbundleMoney 的 outputs，见文件头）
    Cash.BUNDLE_VALUE = 100

    --[[
        原版钞票不需要任何上游模组，所以"能不能收钱"永远是 true。
        真正的失败原因留给 pay（钱不够 = no_funds）。
    ]]
    function Cash.available()
        return true
    end

    local function inventoryOf(player)
        if player == nil then return nil end
        local ok, inventory = pcall(function() return player:getInventory() end)
        if ok and inventory ~= nil then return inventory end
        return nil
    end

    --[[
        玩家身上所有"可能装着钱"的根容器：主背包 + 穿戴中的容器。

        穿戴容器必须单独列：setWornItem 已经把它从主背包里摘掉了，从主背包递归也看不到它。
        BodyLocations / getWornItems() 在世界初始化之前可能为 nil，全程 pcall。
    ]]
    local function rootContainers(player)
        local roots = {}
        local inventory = inventoryOf(player)
        if inventory ~= nil then roots[#roots + 1] = inventory end

        local okGroup, group = pcall(function()
            local api = rawget(_G, "BodyLocations")
            if type(api) ~= "table" then return nil end
            return api.getGroup("Human")
        end)
        if okGroup and group ~= nil then
            local okWorn, worn = pcall(function() return player:getWornItems() end)
            if okWorn and worn ~= nil then
                local size = 0
                pcall(function() size = group:size() end)
                for index = 0, (tonumber(size) or 0) - 1 do
                    local location = nil
                    pcall(function() location = group:getLocationByIndex(index) end)
                    if location ~= nil then
                        local item = nil
                        pcall(function() item = worn:getItem(location:getId()) end)
                        if item ~= nil then
                            local container = nil
                            pcall(function() container = item:getInventory() end)
                            if container ~= nil then roots[#roots + 1] = container end
                        end
                    end
                end
            end
        end
        return roots
    end

    -- 某容器树里一个类型的件数（recurse：背包里的背包/钱包都算）
    local function countOf(container, itemType)
        local ok, value = pcall(function() return container:getCountTypeRecurse(itemType) end)
        if not ok then return 0 end
        return math.max(0, math.floor(tonumber(value) or 0))
    end

    -- 某容器树值多少钱：散钞按张、捆按 100
    local function containerValue(container)
        if container == nil then return 0 end
        return countOf(container, Cash.ITEM) + countOf(container, Cash.BUNDLE) * Cash.BUNDLE_VALUE
    end

    --[[
        列出"此刻装着钞票/捆"的容器。

        先让引擎递归找出所有钞票实例，再问每个实例 `getContainer()` 要它真正的宿主容器
        （可能是一个背包、一个钱包，而不是主背包）。**允许重复**：重复的容器在一次扣款里
        会被 `RemoveAll` 再问一次，返回空列表，无害；因此不需要拿 Java 对象当表键去重
        （Kahlua 里 Java 对象的身份语义不值得赌）。
    ]]
    local function moneyContainers(player)
        local out = {}
        for _, root in ipairs(rootContainers(player)) do
            for _, itemType in ipairs({ Cash.ITEM, Cash.BUNDLE }) do
                local ok, items = pcall(function() return root:getItemsFromType(itemType, true) end)
                if ok and items ~= nil then
                    local size = 0
                    pcall(function() size = items:size() end)
                    for index = 0, (tonumber(size) or 0) - 1 do
                        local item = nil
                        pcall(function() item = items:get(index) end)
                        if item ~= nil then
                            local container = nil
                            pcall(function() container = item:getContainer() end)
                            if container ~= nil then out[#out + 1] = container end
                        end
                    end
                end
            end
        end
        return out
    end

    --[[
        从一个容器里删掉至多 count 个某类型物品，并把**真正删掉的**那批同步给客户端。

        `RemoveAll(type, n)` 一次搞定"删 + 返回被删列表"（javap：
        `ItemContainer.RemoveAll(String, int) -> ArrayList<InventoryItem>`），
        返回的列表正好是 `sendRemoveItemsFromContainer` 要的参数。
        用 `Remove` 逐个删再自己攒列表也行，但那样每次都要碰 Java 集合。
    ]]
    local function takeFromContainer(container, itemType, count)
        if container == nil or count <= 0 then return 0 end
        local ok, removed = pcall(function() return container:RemoveAll(itemType, count) end)
        if not ok or removed == nil then return 0 end
        local size = 0
        pcall(function() size = removed:size() end)
        local taken = math.max(0, math.floor(tonumber(size) or 0))
        if taken > 0 and type(sendRemoveItemsFromContainer) == "function" then
            pcall(sendRemoveItemsFromContainer, container, removed)
        end
        return taken
    end

    -- 从玩家身上（所有装钱的容器）删掉 count 个某类型物品，返回真实删掉的件数
    local function takeItems(player, itemType, count)
        local need = math.floor(tonumber(count) or 0)
        local removed = 0
        if need <= 0 then return 0 end
        for _, container in ipairs(moneyContainers(player)) do
            if removed >= need then break end
            removed = removed + takeFromContainer(container, itemType, need - removed)
        end
        return removed
    end

    -- 发散钞（退款 / 破捆找零）。返回真实发出去的张数。
    local function addNotes(player, count, reason)
        local amount = math.floor(tonumber(count) or 0)
        local inventory = inventoryOf(player)
        if amount <= 0 or inventory == nil then return 0 end
        local ok, items = pcall(function() return inventory:AddItems(Cash.ITEM, amount) end)
        if not ok or items == nil then
            Config.warn("could not hand out " .. tostring(amount) .. " " .. Cash.ITEM
                .. " (" .. tostring(reason) .. ")")
            return 0
        end
        if type(sendAddItemsToContainer) == "function" then
            pcall(sendAddItemsToContainer, inventory, items)
        end
        pcall(function() inventory:setDrawDirty(true) end)
        local size = 0
        pcall(function() size = items:size() end)
        return math.max(0, math.floor(tonumber(size) or 0))
    end

    Cash.addNotes = addNotes

    -- 余额（读不到返回 nil，让调用方区分"没钱"与"读不到"）
    function Cash.balance(player)
        if inventoryOf(player) == nil then return nil end
        local total = 0
        for _, container in ipairs(rootContainers(player)) do
            total = total + containerValue(container)
        end
        return total
    end

    --[[
        扣款。返回 (true) 或 (false, 原因键)。

        算法（服务端权威，客户端传来的价格一律不采信）：
          1. 确认余额够（不够直接失败，**一个物品都不动**）；
          2. 先花散钞：一张 = 1 个单位，删 count 个实例；
          3. 散钞不够就破捆：删 1 捆（=100），多出来的当场找零（新发钞票）；
          4. 走到"删完还不够"只可能是并发改包，如实失败并记日志。

        绝不静默多收或少收：每一件被删掉的物品都是按面值算进去的。
    ]]
    function Cash.pay(player, amount)
        local price = math.floor(tonumber(amount) or 0)
        if price <= 0 then return true end
        if inventoryOf(player) == nil then return false, "no_economy" end

        local total = Cash.balance(player)
        if total == nil then return false, "no_economy" end
        if total < price then return false, "no_funds" end

        local remaining = price

        -- 散钞（每张 1 个单位）
        remaining = remaining - takeItems(player, Cash.ITEM, remaining)

        -- 破捆：一捆 100，多出来的找零（找不到零钱的算法不存在 —— 找零就是新发钞票）
        while remaining > 0 do
            if takeItems(player, Cash.BUNDLE, 1) == 0 then break end
            local change = Cash.BUNDLE_VALUE - remaining
            remaining = remaining - Cash.BUNDLE_VALUE
            if change > 0 then addNotes(player, change, "change") end
        end

        if remaining > 0 then
            Config.warn("cash payment short by " .. tostring(remaining)
                .. " after deduction (concurrent inventory change?)")
            return false, "no_funds"
        end
        return true
    end

    -- 退款：把钞票原样发回去（造人失败 / 收编失败时）
    function Cash.refund(player, amount)
        local handed = addNotes(player, amount, "refund")
        if handed > 0 then
            Config.warn("refunded " .. tostring(handed) .. " " .. Cash.ITEM .. " to "
                .. tostring(Config.Store.playerName(player)))
            return true
        end
        return false
    end

    -- 原版没有账单流水（账单是上游经济模组的能力），如实返回"没记"
    function Cash.flow()
        return false
    end

    function Cash.record(player, amount, labelKey)
        return Cash.flow(player, "out", "npc_hire", labelKey or "FlowHire", amount)
    end

    -- 每名雇员的日薪（与 Economy.lua 同一套沙盒选项，只是钱从哪来不同）
    function Cash.wage()
        if not Config.wageEnabled() then return 0 end
        return Config.dailyWage()
    end

    return Cash
end

Bin2NPCExtensionCore.Cash = factory
return factory
