--------------------------------------------------------------------------------
-- Mods/Defogger/Scripts/consoleCommands.lua
-- Registers every "defogger.*" console command and provides a built-in help
-- listing.  All command metadata lives in a single table so help, registration
-- and implementation stay in sync.

----------------------------------------------------------------------------------
-- module imports
----------------------------------------------------------------------------------
local fogHandler    = require("modules.fogHandler")
local configHandler = require("modules.configHandler")
local utils         = require("modules.modUtils")
local logger        = require("modules.logger")

local consoleCommands = {}          -- module export at the bottom
local commandRecords = {}           -- list of {name, desc, fn} tables

-- Keys that expect an RGBA color table instead of numeric / boolean input.
local colorProperties = {
    SkyAtmosphereAmbientContributionColorScale = true,
    VolumetricFogAlbedo                        = true,
}

-- --------------------------------------------------------------------------------
--  built-in help  (typed as just "defogger" in the console)
-- --------------------------------------------------------------------------------
commandRecords[#commandRecords + 1] = {
    name = "defogger",
    desc = "Display this help",
    fn   = function(_, _, Ar)
        Ar:Log("[Defogger] Available commands:")
        for _, cmd in ipairs(commandRecords) do
            Ar:Log(string.format("  %-36s — %s", cmd.name, cmd.desc))
        end
        return true
    end
}

-- --------------------------------------------------------------------------------
-- Config reload  ("defogger.reload")
-- --------------------------------------------------------------------------------
commandRecords[#commandRecords + 1] = {
    name = "defogger.reload",
    desc = "Reload config.ini and re-apply fog",
    fn   = function(_, _, Ar)
        Ar:Log("[Defogger] Reloading config...")
        local cfg = (configHandler.reloadConfig or configHandler.mergeConfig)()
        local comp = fogHandler.findMapFogComponent()
        if comp and comp:IsValid() then
            fogHandler.applyAll(comp, cfg)
            Ar:Log("[Defogger] Settings reapplied.")
        else
            Ar:Log("[Defogger] No valid fog component found.")
        end
        return true
    end
}

-- --------------------------------------------------------------------------------
--    per-property shortcut commands
--    Each row:  { console-suffix , fog-property , description }
-- --------------------------------------------------------------------------------
local propertyShortcuts = {
    { "StartDistance",                        "StartDistance",                                  "Set the base fog start distance"},
    { "VolumetricFogDistance",                "VolumetricFogDistance",                          "Set the volumetric fog distance"},
    { "FogcutoffDistance",                    "FogCutOffDistance",                              "Set the fog cut off distance"},
    { "SkyAtmosphereColor",                   "SkyAtmosphereAmbientContributionColorScale",     "Set the sky atmosphere color with RGBA values 0-1"},
    { "EnableVolumetricFog",                  "bEnableVolumetricFog",                           "Toggle volumetric fog"},
    { "VolumetricFogStartDistance",           "VolumetricFogStartDistance",                     "Set volumetric fog start"},
    { "VolumetricFogNearFadeInDistance",      "VolumetricFogNearFadeInDistance",                "Set volumetric fog fade-in"},
    { "VolumetricFogAlbedo",                  "VolumetricFogAlbedo",                            "Set volumetric fog albedo (color) with RGBA values 0-255"},
    { "VolumetricFogScatteringDistribution",  "VolumetricFogScatteringDistribution",            "Set VolumetricFogScatteringDistribution"},
    { "VolumetricFogStaticLightingIntensity", "VolumetricFogStaticLightingScatteringIntensity", "Set VolumetricFogStaticLightingScatteringIntensity"},
    { "OverrideLightColorsWithFogInscatteringColors","bOverrideLightColorsWithFogInscatteringColors",  "Toggle bOverrideLightColorsWithFogInscatteringColors"},
}

-- Create a concrete command record for each property row.
for _, entry in ipairs(propertyShortcuts) do
    local suffix, propName, description = table.unpack(entry)
    local consoleName = "defogger." .. suffix

    commandRecords[#commandRecords + 1] = {
        name = consoleName,
        desc = description,
        fn   = function(_, parts, Ar)
            --------------------------------------------------------------------
            -- Parse user input
            --------------------------------------------------------------------
            local rawValue = parts[2] and utils.trim(parts[2]) or nil
            local flagArg  = parts[3] and utils.trim(parts[3]) or ""
            local forceSet = flagArg:lower():match("^%-?force$") ~= nil

            --------------------------------------------------------------------
            -- If no value supplied → echo current engine value
            --------------------------------------------------------------------
            if not rawValue or rawValue == "" then
                local comp = fogHandler.findMapFogComponent()
                if comp and comp:IsValid() then
                    -- Use pcall to safely read property
                    local success, current = pcall(function() return comp[propName] end)
                    if success then
                        Ar:Log(string.format("[Defogger] %s = %s", propName, fogHandler.formatValue(current)))
                    else
                        Ar:Log("[Defogger] Failed to read property value (component may be invalid)")
                    end
                else
                    Ar:Log("[Defogger] No valid fog component found.")
                end
                return true
            end

            --------------------------------------------------------------------
            -- Validate / coerce input
            --------------------------------------------------------------------
            local parsedValue = utils.parseValueForProperty(propName, rawValue, colorProperties, {
                log = function(_, fmt, ...) Ar:Log(fmt:format(...)) end
            })
            if parsedValue == nil then return true end

            --------------------------------------------------------------------
            -- Apply override
            --------------------------------------------------------------------
            local comp = fogHandler.findMapFogComponent()
            if comp and comp:IsValid() then 
                -- Use pcall to safely set the force flag
                pcall(function() comp._defoggerForce = forceSet end)
            end

            local success = fogHandler.applySingle(propName, parsedValue)

            if success then
                Ar:Log(string.format("[Defogger] %s %s to %s",
                                     propName,
                                     forceSet and "force-set" or "set",
                                     rawValue))
            else
                Ar:Log("[Defogger] Failed to apply value (component may be invalid)")
            end

            return true
        end
    }
end

-- --------------------------------------------------------------------------------
-- register every command with UE4SS
-- --------------------------------------------------------------------------------
for _, cmd in ipairs(commandRecords) do
    -- Create a case-insensitive command handler function
    local handlerFn = function(fullCommand, parts, Ar)
        -- Wrap the entire handler in pcall for safety
        local success, err = pcall(function()
            return cmd.fn(fullCommand, parts, Ar)
        end)

        if not success then
            Ar:Log(string.format("[Defogger] Command error: %s", tostring(err)))
            return true
        end

        return success
    end

    -- Register the original command (for those who know the correct case)
    RegisterConsoleCommandHandler(cmd.name, handlerFn)

    -- Register a lowercase version (for case-insensitive matching)
    local lowerName = cmd.name:lower()
    if lowerName ~= cmd.name then
        RegisterConsoleCommandHandler(lowerName, handlerFn)
    end
end

-- Optional alias so "defogger " (with trailing space) also triggers help
RegisterConsoleCommandHandler("defogger ", commandRecords[1].fn)

return consoleCommands