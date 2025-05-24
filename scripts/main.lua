-- Mods/Defogger/Scripts/main.lua
print("[Defogger] Mod loading...\n")

local UEHelpers = require("UEHelpers")
local config = require("modules.configHandler")
local fogHandler = require("modules.fogHandler")
local logger = require("modules.logger")

logger.debug = false

config.invalidateCache()
local settings = config.mergeConfig()

-- Apply whenever a new fog component appears (e.g. on level load)
NotifyOnNewObject(
    "/Script/Engine.ExponentialHeightFogComponent",
    function(comp)
        logger.log("NotifyOnNewObject triggered for component: %s", comp and comp:GetFullName() or "Comp Nil or Invalid Initially")

        local delayMilliseconds = 5 -- ExecuteWithDelay in milliseconds. Should help prevent crash. Higher than 10 stops fog from being applied in certain interiors
        logger.log("NotifyOnNewObject - Scheduling delayed processing in %s ms for component: %s", delayMilliseconds, comp and comp:GetFullName() or "Comp Nil or Invalid Initially")

        ExecuteWithDelay(delayMilliseconds, function()
            logger.log("NotifyOnNewObject (Delayed via ExecuteWithDelay): Processing component: %s", comp and comp:IsValid() and comp:GetFullName() or "Comp Nil or Invalid Initially after delay")

            local success, err = pcall(function()
                if not comp or not comp:IsValid() then
                    logger.log("[Warning] NotifyOnNewObject (Delayed): Component became invalid or was invalid after delay for: %s", comp)
                    return
                end

                if fogHandler.isMapFogValid(comp) then
                    if comp:IsValid() then
                        logger.log("NotifyOnNewObject (Delayed): Applying settings to: %s", comp:GetFullName())
                        fogHandler.applyAll(comp, settings)
                    else
                        logger.log("[Warning] NotifyOnNewObject (Delayed): Component %s became invalid just before applyAll.", comp:GetFullName())
                    end
                else
                     logger.log("NotifyOnNewObject (Delayed): Component %s not considered valid map fog after delay.", comp and comp:GetFullName() or "Comp was nil")
                end
            end)

            if not success then
                logger.log("[Error] NotifyOnNewObject (Delayed): Failed to process new fog component: %s. Error: %s", comp and comp:GetFullName(), tostring(err))
            end
        end)
    end
)

-- Hooks for console commands
local setterHooks = {
    StartDistance                       = "/Script/Engine.ExponentialHeightFogComponent:SetStartDistance",
    FogCutOffDistance                   = "/Script/Engine.ExponentialHeightFogComponent:SetFogCutoffDistance",
    VolumetricAlbedo                    = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogAlbedo",
    VolumetricFogDistance               = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogDistance",
    VolumetricFogScatteringDistribution = "/Script/Engine.ExponentialHeightFogComponent:SetVolumetricFogScatteringDistribution",
}

for property, fnPath in pairs(setterHooks) do
    local hook_success, errorMsg = pcall(function()
        RegisterHook(fnPath, function(self, newVal)
            local hookExecSuccess, hookErr = pcall(function()
                if not self or not self:IsValid() then return end
                if self._defoggerForce then
                    self._defoggerForce = nil
                    return false
                end
            end)
            if not hookExecSuccess then
                logger.log("[Error] Hook execution error for %s on %s: %s", property, self and self:GetFullName(), tostring(hookErr))
            end
        end)
    end)

    if hook_success then
        logger.log("Registered hook for %s", property)
    else
        logger.log("[Warning] Failed to hook %s: %s", property, tostring(errorMsg))
    end
end

logger.log(true, "Mod loaded!")