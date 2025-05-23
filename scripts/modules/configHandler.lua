--------------------------------------------------------------------------------
-- Mods/Defogger/Scripts/modules/configHandler.lua
--------------------------------------------------------------------------------
--  · Reads defaults.ini + user config.ini (creates user file on first run)
--  · Merges user overrides; blank or "default" = fall back to engine defaults
--  · Caches the merged table per session
--  · Call invalidateCache() -> mergeConfig() to force a reload
--------------------------------------------------------------------------------

local lip         = require("modules.LIP")      -- Lua INI Parser
local logger      = require("modules.logger")
local utils       = require("modules.modUtils")

-- Resolve paths ---------------------------------------------------------------
local thisFile   = debug.getinfo(1, "S").source:sub(2)
local moduleDir  = thisFile:match("(.+)[/\\][^/\\]+$")
local rootDir    = moduleDir:gsub("[/\\]modules$", "")

local defaultsPath = moduleDir .. "/defaults.ini"
local userPath     = rootDir  .. "/config.ini"

-- Module table / cache --------------------------------------------------------
local configHandler = {}
local configCache   = nil                  -- nil = not loaded yet

-- Parser dispatch table
local parserByType = {
    boolean = function(s) local v=utils.trim(s):lower(); if v=="true" then return true
                          elseif v=="false" then return false end; return nil end,
    number  = function(s) return tonumber(utils.trim(s)) end,
    color   = utils.parseColor,
}

--------------------------------------------------------------------------------
-- Schema (section -> key -> type)
--------------------------------------------------------------------------------
local fogSchema = {
    Enabled                         = "boolean",
    FogStartDistance                = "number",
    FogCutOffDistance               = "number",
    SkyAtmosphereColor              = "color",
    EnableVolumetricFog             = "boolean",
    VolumetricFogStartDistance      = "number",
    VolumetricFogNearFadeInDistance = "number",
    VolumetricFogAlbedo             = "color",
    VolumetricFogDistance           = "number",
}

local schemaBySection = {
    Tamriel_Outside         = utils.clone(fogSchema),
    Interior                = utils.clone(fogSchema),
    Imperial_City           = utils.clone(fogSchema),
    Oblivion_Planes_Outside = utils.clone(fogSchema),
    Shivering_Isles_Outside = utils.clone(fogSchema),
}

--------------------------------------------------------------------------------
-- File I/O helpers
--------------------------------------------------------------------------------
local function loadIni(path)
    local ok, tbl = pcall(lip.load, path)
    return ok and tbl or {}
end

local function loadRawIni()
    local defaults = loadIni(defaultsPath)
    local user     = loadIni(userPath)

    if next(user) == nil then
        logger.log("[Config] config.ini not found; creating from defaults")
        local src = assert(io.open(defaultsPath, "r"))
        local dst = assert(io.open(userPath,     "w"))
        dst:write(src:read("*a"));  src:close();  dst:close()
        user = loadIni(userPath)
    end
    return defaults, user
end

--------------------------------------------------------------------------------
-- Cache control
--------------------------------------------------------------------------------
function configHandler.invalidateCache() configCache = nil end

--------------------------------------------------------------------------------
-- mergeConfig : read / merge (cached)
--------------------------------------------------------------------------------
function configHandler.mergeConfig()
    -- Serve from cache if we already built the table this session
    if configCache then return configCache end

    local defaultsIni, userIni = loadRawIni()
    local mergedConfig = {}

    for sectionName, defaultSection in pairs(defaultsIni) do
        local schema      = schemaBySection[sectionName]
        local userSection = userIni[sectionName] or {}
        local outSection  = {}
        local badVals     = {}

        -- Iterate every key in the shipped defaults (order not important)
        for key, defaultRaw in pairs(defaultSection) do
            if schema and schema[key] then
                local parser  = parserByType[schema[key]]
                local userRaw = utils.stripComment(userSection[key] or "")
                local defaultRaw = utils.stripComment(defaultSection[key] or "")

                -- Decide which raw string (if any) to keep -------------------
                local finalRaw = nil  -- Default to game engine defaults

                -- Case 1: User explicitly set a non-game value
                if userRaw and not utils.isGameToken(userRaw) then
                    finalRaw = userRaw
                -- Case 2: User explicitly set "game" - use game defaults, ignore defaults.ini
                elseif userRaw and utils.isGameToken(userRaw) then
                    -- finalRaw stays nil (engine defaults)
                -- Case 3: User config missing/malformed, check defaults.ini
                elseif defaultRaw and not utils.isGameToken(defaultRaw) then
                        finalRaw = defaultRaw
                end
                -- Case 4: defaults.ini is "game" - finalRaw stays nil (engine defaults)

                if not finalRaw then
                    outSection[key] = nil
                else
                    -- Parse; nil result = bad value
                    local value = parser and parser(finalRaw)
                    if value == nil then
                        badVals[#badVals + 1] = { key = key, raw = finalRaw }
                    end
                    outSection[key] = value
                end
            end
        end

        mergedConfig[sectionName] = outSection

        -- Log invalid values once per section
        if #badVals > 0 then
            logger.log("[Config][WARN] %d invalid values in [%s]:", #badVals, sectionName)
            for _, err in ipairs(badVals) do
                logger.log("  • %s = '%s' (ignored)", err.key, err.raw)
            end
        end
    end

    -- Cache the result so future calls are fast
    configCache = mergedConfig

    -- Optional debug dump
    if logger.debug then
        logger.log("[Config] Final merged table:")
        local function dump(tbl, indent)
            indent = indent or ""
            for k, v in pairs(tbl) do
                if type(v) == "table" then
                    logger.log("%s%s:", indent, k)
                    dump(v, indent .. "  ")
                else
                    logger.log("%s%s = %s", indent, k, tostring(v))
                end
            end
        end
        dump(mergedConfig)
    end

    return mergedConfig
end

--------------------------------------------------------------------------------
-- dumpConfig : convenience wrapper (never cached)
--------------------------------------------------------------------------------
function configHandler.dumpConfig()
    logger.log(true, "[Config] Manual dump requested:")
    configHandler.mergeConfig()   -- mergeConfig handles the dump when debug is on
end

--------------------------------------------------------------------------------
-- reloadConfig : convenience wrapper to invalidate and reload
--------------------------------------------------------------------------------
function configHandler.reloadConfig()
    configHandler.invalidateCache()
    return configHandler.mergeConfig()
end

return configHandler