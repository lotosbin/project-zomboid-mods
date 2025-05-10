function CoopMapSpawnSelect:fillList()
	-- local function disabledBULLSHIT()
	MapSpawnSelect.fillList(self)

	local respawningPlayerIndex = CoopCharacterCreation.instance.playerIndex
	for playerIndex=0,getNumActivePlayers()-1 do
		local playerObj = getSpecificPlayer(playerIndex)
		if not self:canRespawnWithSelf() then
			if playerIndex == respawningPlayerIndex then
				playerObj = nil
			end
		end
		if not self:canRespawnWithOther() then
			if playerIndex ~= respawningPlayerIndex then
				playerObj = nil
			end
		end
		-- if not playerObj:isDead() then -- only alive - Tommysticks
		if playerObj then
			local x = playerObj:getX()
			local y = playerObj:getY()
			local z = playerObj:getZ()
			local wx = math.floor(x/300)
			local wy = math.floor(y/300)
			local region = {
				name = getText("UI_mapspawn_WithPlayer" .. (playerIndex+1)),
				points = {
					unemployed = {
						{worldX=wx, worldY=wy, posX=(x-wx*300), posY=(y-wy*300), posZ=z},
					},
				}
			}
			local item = {
				name = region.name,
				region = region,
				dir = "",
				desc = "",
				worldimage = nil
			}
			self.listbox:addItem(item.name, item)
		end
	end
end

function ISPostDeathUI:prerender() -- replaced to enable spawning without going to menu
	ISPostDeathUI.instance[self.playerIndex] = self
	if self.screenWidth ~= getPlayerScreenWidth(self.playerIndex) or self.screenHeight ~= getPlayerScreenHeight(self.playerIndex) then
		local x = getPlayerScreenLeft(self.playerIndex)
		local y = getPlayerScreenTop(self.playerIndex)
		local w = getPlayerScreenWidth(self.playerIndex)
		local h = getPlayerScreenHeight(self.playerIndex)
		self.screenX = x
		self.screenWidth = w
		self.screenHeight = h
		self:setX(x + (w - self.width) / 2)
		self:setY(h - 40 - self.height)
	end
	if not self.waitOver then
		self.waitOver = getTimestamp() > self.timeOfDeath + 3
	end
	local allPlayersDead = IsoPlayer.allPlayersDead()
	-- local allowRespawn = isClient() or (getNumActivePlayers() > 1)
	local allowRespawn = isClient() or (getNumActivePlayers() > 0)
	if isClient() and getServerOptions():getBoolean("DropOffWhiteListAfterDeath") then
		allowRespawn = false
	end	
	self.buttonRespawn:setVisible(self.waitOver and allowRespawn)
	
	self.buttonQuit:setVisible(self.waitOver and allPlayersDead)
	self.buttonExit:setVisible(self.waitOver and allPlayersDead)
	-- self.buttonRespawn:setVisible(self.waitOver and allPlayersDead) -- wtf
	ISPanelJoypad.prerender(self)
end