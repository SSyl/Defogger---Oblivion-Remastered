-- Mods/Defogger/Scripts/main.lua
print("[Defogger] Mod loading...\n")

local logger = require("modules.logger")
logger.debug = true   -- Enable debug logging to the UE4SS log
local config       = require("modules.configHandler")
local fogHandler   = require("modules.fogHandler")
local consoleCmds  = require("modules.consoleCommands")
local modUtils     = require("modules.modUtils")

-- 2) Merge defaults.ini + config.ini into a typed settings table
config.invalidateCache() -- Clears the cached INI if one existed
local settings = config.mergeConfig()

-- 3) Initial application of INI values at startup
ExecuteInGameThread(function()
    -- Wrap in pcall to prevent crashes during initialization
    local success, err = pcall(function()
        local fog = fogHandler.findMapFogComponent()
        if fog and fog:IsValid() then
            logger.log("Found fog component at startup, applying settings")
            fogHandler.applyAll(fog, settings)
        else
            logger.log("[Warning] No valid map fog component found at startup (normal if in main menu).")
        end
    end)

    if not success then
        logger.log("[Error] Failed to apply initial settings: %s", tostring(err))
    end
end)

-- 4) Re-apply whenever a new fog component appears (e.g. on level load)
NotifyOnNewObject(
    "/Script/Engine.ExponentialHeightFogComponent",
    function(comp)
        ExecuteInGameThread(function()
            -- Wrap in pcall to prevent crashes when processing new objects
            local success, err = pcall(function()
                -- Check validity before processing
                if not comp or not comp:IsValid() then
                    logger.log("[Warning] Invalid component in NotifyOnNewObject")
                    return
                end

                if fogHandler.isMapFogValid(comp) then
                    -- Double-check validity before applying
                    if comp:IsValid() then
                        fogHandler.applyAll(comp, settings)
                    else
                        logger.log("[Warning] Component became invalid before applying settings")
                    end
                end
            end)

            if not success then
                logger.log("[Error] Failed to process new fog component: %s", tostring(err))
            end
        end)
    end
)

-- Map of component setters to their native UFunction paths
local setterHooks = {
    StartDistance                       = "/Script/Engine.ExponentialHeightFogComponent:SetStartDistance",
    FogCutOffDistance                   = "/Script/Engine.ExponentialHeightFogComponent:SetFogCutoffDistance",
    VolumetricAlbedo                    = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogAlbedo",
    VolumetricFogDistance               = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogDistance",
    VolumetricFogScatteringDistribution = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogScatteringDistribution",
}

-- Track which hooks were successfully registered
local registeredHooks = {}

-- Register a hook for each setter (with safer error handling)
for property, fnPath in pairs(setterHooks) do
    local success, errorMsg = pcall(function()
        RegisterHook(fnPath, function(self, newVal) -- Hook engine setter functions to block only when forced via console
            -- Wrap hook logic in pcall
            local hookSuccess, hookErr = pcall(function()
                if self and self:IsValid() and self._defoggerForce then
                    self._defoggerForce = nil -- clear the flag so only this one setter is blocked
                    return false  -- veto only forced console calls
                end
            end)

            if not hookSuccess then
                logger.log("[Error] Hook error for %s: %s", property, tostring(hookErr))
            end
            -- allow normal engine-driven sets otherwise
        end)
    end)

    if success then
        logger.log("Registered hook for %s", property)
    else
        logger.log("[Warning] Failed to hook %s: %s", property, tostring(errorMsg))
    end
end

logger.log(true, "Mod loaded!")