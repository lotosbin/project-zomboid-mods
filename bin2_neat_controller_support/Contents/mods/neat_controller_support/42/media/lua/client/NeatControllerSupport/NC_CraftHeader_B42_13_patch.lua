local NeatControllerSupport = {}
NeatControllerSupport.MOD_ID = "Neat_Controller_Support"
NeatControllerSupport.MOD_Name = "Neat Controller Support"
NeatControllerSupport.closeButton = Joypad.BButton
function NeatControllerSupport:addJoypad(windowClass)
    if (windowClass == nil) then
        return
    end
    local originalOnJoypadDown = windowClass.onJoypadDown
    function windowClass:onJoypadDown(button)
        if (originalOnJoypadDown) then
            originalOnJoypadDown(self, button)
        end
        if button == NeatControllerSupport.closeButton then
            self.close(self)
        end
    end
end

NeatControllerSupport:addJoypad(NC_HandcraftWindow)
NeatControllerSupport:addJoypad(NB_BuildingPanel)
