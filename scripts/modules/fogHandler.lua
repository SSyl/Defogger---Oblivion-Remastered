-- Mods/Defogger/Scripts/modules/fogHandler.lua

local UEHelpers = require("UEHelpers")
local utils     = require("modules.modUtils")
local logger    = require("modules.logger")

local fogHandler = {}

-- Formats a value for logger.log - now uses the utility function
function fogHandler.formatValue(value)
    return utils.formatValue(value)
end

function fogHandler.getLevelType()
    local worldContext    = UEHelpers.GetWorldContextObject()
    local gs              = UEHelpers.GetGameplayStatics()
    local rawName         = gs:GetCurrentLevelName(worldContext, true)
    local levelName       = rawName:ToString()

    if levelName == "L_Tamriel"           then return "Tamriel_Outside"
    elseif levelName == "L_PersistentDungeon" then return "Interior"
    elseif levelName:find("^L_IC")         then return "Imperial_City"
    elseif levelName:find("^L_Oblivion")   then return "Oblivion_Planes_Outside"
    elseif levelName == "L_SEWorld"        then return "Shivering_Isles_Outside"
    else
        logger.log(true,"Unknown map '%s', defaulting to Interior", levelName)
        return "Interior"
    end
end

function fogHandler.isMapFogValid(comp)
    if not comp or not comp:IsValid() then return false end
    local ok, fullName = pcall(function() return comp:GetFullName() end)
    return ok and type(fullName)=="string" and fullName:find("/Game/Maps/")~=nil
end

function fogHandler.findMapFogComponent()
    local allFogs = FindAllOf("ExponentialHeightFogComponent")
    if type(allFogs)~="table" then
        logger.log("[Warning] FindAllOf returned %s, expected table", tostring(allFogs))
        return nil
    end
    for _,c in ipairs(allFogs) do
        if fogHandler.isMapFogValid(c) then
            return c
        end
    end
    return nil
end

fogHandler.propertyMap = {
    FogStartDistance                               = "StartDistance",
    FogCutOffDistance                              = "FogCutOffDistance",
    SkyAtmosphereColor                             = "SkyAtmosphereAmbientContributionColorScale",
    EnableVolumetricFog                            = "bEnableVolumetricFog",
    VolumetricFogStartDistance                     = "VolumetricFogStartDistance",
    VolumetricFogNearFadeInDistance                = "VolumetricFogNearFadeInDistance",
    VolumetricFogAlbedo                            = "VolumetricFogAlbedo",
    VolumetricFogDistance                          = "VolumetricFogDistance",
    VolumetricFogScatteringDistribution            = "VolumetricFogScatteringDistribution",
    VolumetricFogStaticLightingScatteringIntensity = "VolumetricFogStaticLightingScatteringIntensity",
    OverrideLightColorsWithFogInscatteringColors   = "bOverrideLightColorsWithFogInscatteringColors",
}

function fogHandler.applyAll(comp, fullConfig)
    local section = fogHandler.getLevelType()
    local cfg     = fullConfig[section]
    if not cfg or not cfg.Enabled then
        logger.log(true,"%s disabled or missing in INI, skipping", section)
        return
    end

    for key, prop in pairs(fogHandler.propertyMap) do
        local newVal = cfg[key]
        if newVal ~= nil then
            local oldVal = comp[prop]
            if utils.valuesDiffer(oldVal, newVal) then
                logger.log("%s: %s -> %s",
                    key,
                    fogHandler.formatValue(oldVal),
                    fogHandler.formatValue(newVal)
                )
                comp[prop] = newVal
            end
        end
    end
end

-- Add a function to apply a single property (used by console commands)
function fogHandler.applySingle(propName, value)
    local comp = fogHandler.findMapFogComponent()
    if comp then
        comp[propName] = value
        return true
    end
    return false
end

return fogHandler