-- Scripts/modules/logger.lua
local logger = {}

-- Global on/off toggle
logger.debug = false

-- log(overrideOrFmt, fmtOrArg, ...)
-- * log("message") hen debug==true
-- * log(true, "[INFO] %s", x) always
function logger.log(flag, fmt, ...)
    local isOverride, formatStr, args

    if type(flag) == "boolean" then
        isOverride = flag
        formatStr  = fmt
        args       = {...}
    else
        isOverride = false
        formatStr  = flag
        args       = {fmt, ...}
    end

    if not isOverride and not logger.debug then
        return
    end

    local ok, msg = pcall(string.format, formatStr, table.unpack(args))
    msg = ok and msg or formatStr
    print(("[Defogger]%s %s"):format(
      isOverride and "[INFO]" or "",
      msg.."\n"
    ))
end

return logger
