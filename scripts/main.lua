-- Mods/Defogger/Scripts/main.lua

local config = require("modules.configHandler")
local fogHandler = require("modules.fogHandler")
local logger = require("modules.logger")

require("modules.consoleCommands")

logger.debug = false

config.invalidateCache()
local settings = config.mergeConfig()

-- Apply whenever a new fog component appears (e.g. on level load)
NotifyOnNewObject(
    "/Script/Engine.ExponentialHeightFogComponent",
    function(comp)
        local delayMilliseconds = 5 -- ExecuteWithDelay in milliseconds. Should help prevent crash. Higher than 10 stops fog from being applied in certain interiors)

        ExecuteWithDelay(delayMilliseconds, function()
            local success, err = pcall(function()
                if not comp or not comp:IsValid() then
                    return -- Silently skip invalid components
                end

                if fogHandler.isMapFogValid(comp) then
                    if comp:IsValid() then
                        fogHandler.applyAll(comp, settings)
                        logger.log("Applied fog settings to: %s", comp:GetFullName())
                    end
                end
            end)

            if not success then
                logger.log("[Error] Failed to process fog component: %s", tostring(err))
            end
        end)
    end
)

logger.log("Mod loaded!")