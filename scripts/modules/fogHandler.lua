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
    local actualLevelName = "Interior" -- Default value

    local success, determinedNameOrError = pcall(function()
        local gs = UEHelpers.GetGameplayStatics()
        if not gs then
            logger.log("[CRITICAL][fogHandler.getLevelType] UEHelpers.GetGameplayStatics() returned nil instead of erroring. This is unexpected.")
            error("FATAL: GameplayStatics object is nil in getLevelType.")
        end

        local worldContext = UEHelpers.GetWorldContextObject()
        if not worldContext or not worldContext:IsValid() then
            logger.log("[Warning][fogHandler.getLevelType] worldContext is nil or invalid. GS valid: %s, WC: %s, WC IsValid: %s",
                tostring(gs and gs:IsValid()), tostring(worldContext), tostring(worldContext and worldContext:IsValid()))
            error("WorldContext is nil or invalid in getLevelType.")
        end

        logger.log("[Debug][fogHandler.getLevelType] Pre-call check: GS IsValid: %s, WorldContext IsValid: %s (%s)",
            tostring(gs:IsValid()), tostring(worldContext:IsValid()), tostring(worldContext))

        -- CRITICAL CALL: This returns an FString
        local levelNameObject = gs:GetCurrentLevelName(worldContext, true)

        if not levelNameObject then
            logger.log("[Warning][fogHandler.getLevelType] gs:GetCurrentLevelName returned nil.")
            error("GetCurrentLevelName returned nil.")
        end

        local levelNameStr
        local objectType = type(levelNameObject)

        if objectType == "string" then
            -- This case is unlikely if the error says it's an FString, but good to keep
            logger.log("[Debug][fogHandler.getLevelType] GetCurrentLevelName returned a LUA STRING directly: '%s'", levelNameObject)
            levelNameStr = levelNameObject
        elseif objectType == "userdata" then
            -- This is expected to be an FString object from UE4SS
            if levelNameObject.ToString then
                levelNameStr = levelNameObject:ToString()
                logger.log("[Debug][fogHandler.getLevelType] GetCurrentLevelName returned userdata (expected FString), ToString() gives: '%s'", levelNameStr)
            else
                local fallbackStr = tostring(levelNameObject)
                logger.log("[Warning][fogHandler.getLevelType] GetCurrentLevelName returned userdata but it does not have a :ToString() method. tostring() representation: %s", fallbackStr)
                error("GetCurrentLevelName returned userdata without :ToString(): " .. fallbackStr)
            end
        else
            logger.log("[Warning][fogHandler.getLevelType] GetCurrentLevelName returned an unexpected type: %s. Value: %s", objectType, tostring(levelNameObject))
            error("GetCurrentLevelName returned unexpected type: " .. objectType)
        end

        -- Final check on the extracted string
        if not levelNameStr or type(levelNameStr) ~= "string" or levelNameStr == "" then
             logger.log("[Warning][fogHandler.getLevelType] Processed level name is nil, not a string, or empty after ToString. Value: '%s'", tostring(levelNameStr))
             error("Processed level name is not a valid string.")
        end
        
        return levelNameStr -- This is now the actual Lua string name
    end)

    if success then
        local levelName = determinedNameOrError -- This should be a string if success is true
        -- No need for another type check here if the pcall function guarantees returning a string or erroring

        logger.log("[Debug][fogHandler.getLevelType] Successfully retrieved and validated level name: '%s'", levelName)
        if levelName == "L_Tamriel"           then actualLevelName = "Tamriel_Outside"
        elseif levelName == "L_PersistentDungeon" then actualLevelName = "Interior"
        elseif levelName:find("^L_IC")         then actualLevelName = "Imperial_City"
        elseif levelName:find("^L_Oblivion")   then actualLevelName = "Oblivion_Planes_Outside"
        elseif levelName == "L_SEWorld"        then actualLevelName = "Shivering_Isles_Outside"
        else
            logger.log(true,"Unknown map '%s', defaulting to Interior", levelName)
            actualLevelName = "Interior" -- Already the default, but explicit
        end
    else
        logger.log("[Error][fogHandler.getLevelType] pcall failed during level name retrieval. Error: %s. Defaulting to 'Interior'.", tostring(determinedNameOrError))
        actualLevelName = "Interior" -- Default if any error occurred
    end

    return actualLevelName
end


function fogHandler.isMapFogValid(comp)
    if not comp or not comp:IsValid() then
        logger.log("isMapFogValid: Early exit - comp nil or invalid.") -- Debug, can be noisy
        return false
    end

    local ok, fullName_or_err = pcall(function() return comp:GetFullName() end)

    if not ok then
        logger.log("[CRITICAL_WARNING] isMapFogValid: pcall to comp:GetFullName() FAILED for comp: %s. Error: %s", comp, tostring(fullName_or_err))
        return false
    end

    local fullName = fullName_or_err
    if not fullName or type(fullName) ~= "string" then
        logger.log("[Warning] isMapFogValid: comp:GetFullName() returned nil or not a string for comp: %s (Name: %s)", comp, tostring(fullName))
        return false
    end

    return fullName:find("/Game/Maps/") ~= nil
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
    -- Most important: initial check
    if not comp or not comp:IsValid() then
        logger.log("[Warning] applyAll: Early exit - comp nil or invalid at start of function.")
        return
    end

    local section = fogHandler.getLevelType()
    local cfg = fullConfig[section]
    if not cfg or not cfg.Enabled then
        logger.log("applyAll: %s disabled or missing in INI, skipping for comp: %s", section)
        return
    end

    logger.log("applyAll: Processing section %s for comp: %s", section, comp:GetFullName())

 for key, prop in pairs(fogHandler.propertyMap) do
        local newVal = cfg[key]
        if newVal ~= nil then
            if not comp:IsValid() then
                logger.log("[Warning] applyAll: Comp %s became invalid mid-loop before processing key: %s", comp:GetFullName(), key)
                return -- Exit applyAll if component becomes invalid
            end

            local read_ok, oldVal_or_err = pcall(function() return comp[prop] end)

            if read_ok then
                local oldVal = oldVal_or_err
                if utils.valuesDiffer(oldVal, newVal) then
                    logger.log("applyAll: %s: %s -> %s for comp %s",
                        key,
                        fogHandler.formatValue(oldVal),
                        fogHandler.formatValue(newVal),
                        comp:GetFullName()
                    )

                    if not comp:IsValid() then
                        logger.log("[Warning] applyAll: Comp %s became invalid before setting property '%s'.", comp:GetFullName(), prop)
                        return -- Exit applyAll if component became invalid
                    end

                    local set_ok, err_msg = pcall(function() comp[prop] = newVal end)
                    if not set_ok then
                        logger.log("[Warning] applyAll: Failed to set property '%s' to %s for comp %s. Error: %s", prop, fogHandler.formatValue(newVal), comp:GetFullName(), tostring(err_msg))
                        -- return for safety, meaning if one property fails to set, subsequent ones for this component are skipped.
                        return
                    end
                end
            else
                logger.log("[Warning] applyAll: Failed to read property '%s' from comp %s. Error: %s", prop, comp:GetFullName(), tostring(oldVal_or_err))
            end
        end
    end
end

-- Apply a single property (used by console commands)
function fogHandler.applySingle(propName, value)
    local comp = fogHandler.findMapFogComponent()
    if comp and comp:IsValid() then
        -- Use pcall for safety
        local ok = pcall(function() comp[propName] = value end)
        return ok
    end
    return false
end

return fogHandler