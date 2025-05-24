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
    fn   = function(_, _, outputDevice)
        outputDevice:Log("[Defogger] Available commands:")
        for _, cmd in ipairs(commandRecords) do
            outputDevice:Log(string.format("  %-36s — %s", cmd.name, cmd.desc))
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
    fn   = function(_, _, outputDevice)
        outputDevice:Log("[Defogger] Reloading config...")
        local cfg = (configHandler.reloadConfig or configHandler.mergeConfig)()
        local comp = fogHandler.findMapFogComponent()
        if comp and comp:IsValid() then
            fogHandler.applyAll(comp, cfg)
            outputDevice:Log("[Defogger] Settings reapplied.")
        else
            outputDevice:Log("[Defogger] No valid fog component found.")
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

-- --------------------------------------------------------------------------------
-- Create a command record for each property row.
-- --------------------------------------------------------------------------------
for _, entry in ipairs(propertyShortcuts) do
    local suffix, propName, description = table.unpack(entry)
    local consoleName = "defogger." .. suffix

    commandRecords[#commandRecords + 1] = {
        name = consoleName,
        desc = description,
        fn   = function(fullCommand, parts, outputDevice)

            -- Parse user input using modUtils
            local rawValue = utils.parseConsoleCommand(fullCommand, suffix)

            -- If no value supplied echo current engine value
            if not rawValue or utils.trim(rawValue) == "" then
                local comp = fogHandler.findMapFogComponent()
                if comp and comp:IsValid() then
                    local success, current = pcall(function() return comp[propName] end)
                    if success then
                        outputDevice:Log(string.format("[Defogger] %s = %s", propName, fogHandler.formatValue(current)))
                    else
                        outputDevice:Log("[Defogger] Failed to read property value (component may be invalid)")
                    end
                else
                    outputDevice:Log("[Defogger] No valid fog component found.")
                end
                return true
            end

            -- Validate input using modUtils
            local parsedValue = utils.parseValueForProperty(propName, rawValue, colorProperties, {
                log = function(_, fmt, ...) outputDevice:Log(fmt:format(...)) end
            })
            if parsedValue == nil then return true end

            -- Apply the value
            local success = fogHandler.applySingle(propName, parsedValue)

            if success then
                outputDevice:Log(string.format("[Defogger] %s set to %s", propName, rawValue))
            else
                outputDevice:Log("[Defogger] Failed to apply value (component may be invalid)")
            end

            return true
        end
    }
end

-- --------------------------------------------------------------------------------
-- Register every command with UE4SS (case-insensitive)
-- --------------------------------------------------------------------------------
for _, cmd in ipairs(commandRecords) do
    -- Create a case-insensitive command handler function
    local handlerFn = function(fullCommand, parts, outputDevice)
        -- Wrap the entire handler in pcall for safety
        local success, err = pcall(function()
            return cmd.fn(fullCommand, parts, outputDevice)
        end)

        if not success then
            outputDevice:Log(string.format("[Defogger] Command error: %s", tostring(err)))
            return true
        end

        return success
    end

    -- Register the original command (exact case)
    RegisterConsoleCommandHandler(cmd.name, handlerFn)

    -- Register a lowercase version (for case-insensitive matching)
    local lowerName = cmd.name:lower()
    if lowerName ~= cmd.name then
        RegisterConsoleCommandHandler(lowerName, handlerFn)
    end

    -- Also register with different case variations for common mistakes
    if cmd.name:find("%.") then
        -- For commands like "defogger.StartDistance", also register "defogger.startdistance"
        local parts = {}
        for part in cmd.name:gmatch("[^%.]+") do
            table.insert(parts, part)
        end
        if #parts == 2 then
            local prefix = parts[1]:lower()  -- "defogger"
            local suffix = parts[2]:lower()  -- "startdistance"
            local mixedCase = prefix .. "." .. suffix
            if mixedCase ~= cmd.name and mixedCase ~= lowerName then
                RegisterConsoleCommandHandler(mixedCase, handlerFn)
            end
        end
    end
end

-- Optional alias so "defogger " (with trailing space) also triggers help
RegisterConsoleCommandHandler("defogger ", function(fullCommand, parts, outputDevice)
    return commandRecords[1].fn(fullCommand, {"defogger"}, outputDevice)
end)

return consoleCommands