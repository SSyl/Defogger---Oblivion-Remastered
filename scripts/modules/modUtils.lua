--------------------------------------------------------------------------------
-- Mods/Defogger/Scripts/modules/modUtils.lua
-- Common Utilities used across the Defogger mod
--------------------------------------------------------------------------------

local modUtils = {}

--------------------------------------------------------------------------------
-- String Utils
--------------------------------------------------------------------------------

---Trim leading / trailing whitespace from a string (nil-safe).
---@param str string|nil The string to trim
---@return string The trimmed string or empty string if nil
function modUtils.trim(str)
    return (str or ""):match("^%s*(.-)%s*$")
end

---Strip comments from a config line (nil-safe).
---@param str string|nil The string to strip comments from
---@return string The string without comments
function modUtils.stripComment(str)
    return (str or ""):match("^[^#;]*"):match("^%s*(.-)%s*$")
end

---Check if a string represents a "game" token (empty or "game").
---@param str string|nil The string to check
---@return boolean True if the string is empty or "game" (case-insensitive)
function modUtils.isGameToken(str)
    return modUtils.trim(str):lower() == "game" or modUtils.trim(str) == ""
end

--------------------------------------------------------------------------------
-- Color Parsing
--------------------------------------------------------------------------------

---Parse an RGBA string into a UE-style {R, G, B, A} table.
---Accepts either "r=255,g=255,b=255,a=255" or "255,255,255,255".
---@param raw string The raw color string
---@return table|nil The color table or nil if parsing failed
function modUtils.parseColor(raw, shouldNormalize)
    raw = modUtils.trim(raw)
    if raw == "" then return nil end

    local r, g, b, a

    -- Named format: r=255,g=...
    if raw:find("=") then
        for part in raw:gmatch("([^,]+)") do
            local k, v = part:match("^(%w)%s*=%s*(%d+%.?%d*)$")
            if k and v then
                local n = tonumber(v)
                if     k:lower() == "r" then r = n
                elseif k:lower() == "g" then g = n
                elseif k:lower() == "b" then b = n
                elseif k:lower() == "a" then a = n end
            end
        end
    else
        -- Positional format: 255,255,255,255
        local values = {}
        for part in raw:gmatch("([^,]+)") do
            values[#values + 1] = tonumber(modUtils.trim(part))
        end
        if #values >= 4 then r, g, b, a = table.unpack(values, 1, 4) end
    end

    if r and g and b and a then
        if shouldNormalize then
            return { R = r / 255, G = g / 255, B = b / 255, A = a / 255 }
        else
            return { R = r, G = g, B = b, A = a }
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Value Formatting & Type Handling
--------------------------------------------------------------------------------

---Format a value for display/logging, handling special types like colors.
---@param value any The value to format
---@return string The formatted value as string
function modUtils.formatValue(value)
    local t = type(value)

    -- Handle nil explicitly
    if value == nil then
        return "nil"
    end

    -- Color‐like struct or table
    if (t == "table" or t == "userdata")
       and type(value.R) == "number"
       and type(value.G) == "number"
       and type(value.B) == "number"
       and type(value.A) == "number"
    then
        return string.format("{R=%.3f,G=%.3f,B=%.3f,A=%.3f}",
            value.R, value.G, value.B, value.A)
    end

    -- UObject: try ToString()
    if t == "userdata" and value.ToString then
        local ok, s = pcall(value.ToString, value)
        if ok and type(s)=="string" then
            return s
        end
    end

    return tostring(value)
end

---Attempt to coerce a string into an appropriate typed value.
---@param valueStr string The string value to parse
---@return any The parsed value or nil if parsing failed
function modUtils.parseValue(valueStr)
    local lower = valueStr:lower()

    if lower == "true"  then return true end
    if lower == "false" then return false end

    -- Try as number
    local num = tonumber(valueStr)
    if num ~= nil then return num end

    -- Return as is if all else fails
    return valueStr
end

---Parse a value specifically for a property, handling special types like colors.
---@param propName string Name of the property (to determine parsing method)
---@param valueStr string String representation of the value
---@param colorProperties table? Optional table of property names that expect color values
---@param logger table? Optional logger for reporting errors
---@return any The parsed value or nil if parsing failed
function modUtils.parseValueForProperty(propName, valueStr, colorProperties, logger)
    colorProperties = colorProperties or {}

    local lower = valueStr:lower()

    if lower == "true"  then return true end
    if lower == "false" then return false end

    if colorProperties[propName] then
        -- Determine if we should normalize (divide by 255) based on property name
        local shouldNormalize = propName ~= "VolumetricFogAlbedo"
        local c = modUtils.parseColor(valueStr, shouldNormalize)
        if c then return c end
        if logger then 
            logger.log(true, "[Defogger] Invalid color '%s'", valueStr)
        end
        return nil
    end

    local num = tonumber(valueStr)
    if num ~= nil then return num end

    if logger then
        logger.log(true, "[Defogger] Invalid value '%s'", valueStr)
    end
    return nil
end

---Compare two values, handling special cases like floats vs ints, colors, etc.
---@param oldVal any The old value
---@param newVal any The new value
---@return boolean True if the values differ
function modUtils.valuesDiffer(oldVal, newVal)
    local oNum = tonumber(tostring(oldVal))
    local nNum = tonumber(tostring(newVal))
    if oNum and nNum then
        return math.abs(oNum - nNum) > 1e-4
    end
    return modUtils.formatValue(oldVal):lower() ~= modUtils.formatValue(newVal):lower()
end

--------------------------------------------------------------------------------
-- Table Utilities
--------------------------------------------------------------------------------

---Clone a table (shallow copy).
---@param tbl table The table to clone
---@return table The cloned table
function modUtils.clone(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

return modUtils