--**************************
-- Respawn
--**************************
--* Coded by: LichKingNZ
--* Date Created: 09/01/2022
--**************************

RespawnOption = RespawnOption or {}
RespawnOption.Options = RespawnOption.Options or {}

-- RespawnOption.Options.overwriteSystemRate = true
RespawnOption.Options.xpRate = 0.5

if ModOptions and ModOptions.getInstance then
    local xpRate = { 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }

    local function onModOptionsApply(optionValues)
        -- RespawnOption.Options.xpRate = xpRate[optionValues.settings.options.xpRate]
        -- getPlayer():Say("Current xp rate " .. RespawnOption.Options.xpRate)

        if isAdmin() or not isClient() then
            -- RespawnOption.Options.overwriteSystemRate = optionValues.settings.options.overwriteSystemRate
            RespawnOption.Options.xpRate = xpRate[optionValues.settings.options.xpRate]
            getPlayer():Say("Current xp rate " .. RespawnOption.Options.xpRate)
        else
            getPlayer():Say("Cannot edit xp rate, current rate: " .. RespawnOption.Options.xpRate)
        end
    end

    local SETTINGS = {
        options_data = {
            xpRate = {
                "0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%",
                name = "UI_RespawnOption_RespawnOption",
                tooltip = "UI_RespawnOption_RespawnOption_Tooltip",
                default = 6,
                -- OnApplyMainMenu = onModOptionsApply,
                OnApplyInGame = onModOptionsApply,
            },
        },

        mod_id = 'Respawn',
        mod_shortname = 'Respawn',
        mod_fullname = 'Respawn',
    }

    local optionsInstance = ModOptions:getInstance(SETTINGS)
    ModOptions:loadFile()

end

local function showCurrentRespawnOption(key)
    -- keypad number 9
    if key == 73 then
        getPlayer():Say("Current xp rate: " .. RespawnOption.Options.xpRate)
    end
end

-- Events.OnKeyPressed.Add(showCurrentRespawnOption)