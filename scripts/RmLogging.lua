RmLogging = {}
local RmLogging_mt = Class(RmLogging)

-- Module constants
RmLogging.LOG_PREFIX = "[RmLogging]"

-- Log levels (higher numbers = more verbose)
RmLogging.LOG_LEVEL = {
    ERROR = 1,
    WARNING = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5
}

-- Current log level (default to INFO)
RmLogging.CURRENT_LOG_LEVEL = RmLogging.LOG_LEVEL.INFO

local function debugPrint(msg, ...)
    -- Handle format string like Logging.* functions do
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    print(string.format("  Debug: %s", msg))
end

local function tracePrint(msg, ...)
    -- Handle format string like Logging.* functions do
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    print(string.format("  Trace: %s", msg))
end

local function logCommon(logFunc, ...)
    local numArgs = select("#", ...)

    if numArgs == 0 then
        return
    end

    -- Get first argument to check if it's a format string
    local firstArg = select(1, ...)

    if numArgs == 1 then
        -- Single argument - just log it
        local v = firstArg
        if type(v) == "nil" then
            v = "(nil)"
        elseif type(v) == "table" then
            local parts = {}
            for k, val in pairs(v) do
                if type(val) == "table" then
                    val = "(table)"
                end
                table.insert(parts, string.format("%s: %s", tostring(k), tostring(val)))
            end
            v = table.concat(parts, ", ")
        end
        logFunc(RmLogging.LOG_PREFIX .. " %s", tostring(v))
    else
        -- Multiple arguments - assume first is format string, rest are arguments
        -- Pre-format the message ourselves since we're passing through to Logging.*
        local message = string.format(firstArg, select(2, ...))
        logFunc(RmLogging.LOG_PREFIX .. " %s", message)
    end
end

---Logs info messages
---@param ... any Values to log
function RmLogging.logInfo(...)
    if RmLogging.CURRENT_LOG_LEVEL >= RmLogging.LOG_LEVEL.INFO then
        logCommon(Logging.info, ...)
    end
end

---Logs warning messages
---@param ... any Values to log
function RmLogging.logWarning(...)
    if RmLogging.CURRENT_LOG_LEVEL >= RmLogging.LOG_LEVEL.WARNING then
        logCommon(Logging.warning, ...)
    end
end

---Logs error messages
---@param ... any Values to log
function RmLogging.logError(...)
    if RmLogging.CURRENT_LOG_LEVEL >= RmLogging.LOG_LEVEL.ERROR then
        logCommon(Logging.error, ...)
    end
end

---Logs debug messages if debug is enabled
---@param ... any Values to log
function RmLogging.logDebug(...)
    if RmLogging.CURRENT_LOG_LEVEL >= RmLogging.LOG_LEVEL.DEBUG then
        logCommon(debugPrint, ...)
    end
end

---Logs trace messages if trace is enabled
---@param ... any Values to log
function RmLogging.logTrace(...)
    if RmLogging.CURRENT_LOG_LEVEL >= RmLogging.LOG_LEVEL.TRACE then
        logCommon(tracePrint, ...)
    end
end

---Converts table to string representation with configurable depth
---@param tbl table Table to convert
---@param indent number|nil Current indentation level
---@param maxDepth number|nil Maximum depth to traverse
---@param initialIndent number|nil Initial indentation level
---@return string String representation of the table
function RmLogging.tableToString(tbl, indent, maxDepth, initialIndent)
    indent = indent or 0
    maxDepth = maxDepth or 2
    initialIndent = initialIndent or indent
    local result = {}

    if (indent - initialIndent) >= maxDepth then
        table.insert(result, string.rep("  ", indent) .. "...")
        return table.concat(result, "\n")
    end

    for k, v in pairs(tbl) do
        local formatting = string.format("%s%s: ", string.rep("  ", indent), tostring(k))
        if type(v) == "table" then
            table.insert(result, formatting)
            table.insert(result, RmLogging.tableToString(v, indent + 1, maxDepth, initialIndent))
        else
            table.insert(result, string.format("%s%s", formatting, tostring(v)))
        end
    end

    return table.concat(result, "\n")
end

---Converts function parameters to string representation
---@param ... any Function parameters to convert
---@return string String representation of parameters
function RmLogging.functionParametersToString(...)
    local args = { ... }
    local result = {}

    for i, v in ipairs(args) do
        table.insert(result, string.format("Parameter %d: (%s) %s", i, type(v), tostring(v)))
        if type(v) == "table" then
            table.insert(result, RmLogging.tableToString(v, 0, 2))
        end
    end

    return table.concat(result, "\n")
end

---Sets the log prefix for all logging functions
---@param prefix string|nil New log prefix (defaults to "[RmLogging]")
function RmLogging.setLogPrefix(prefix)
    RmLogging.LOG_PREFIX = prefix or "[RmLogging]"
end

---Sets the current log level
---@param level number|string Log level (use RmLogging.LOG_LEVEL constants or string names)
function RmLogging.setLogLevel(level)
    if type(level) == "string" then
        -- Convert string to log level constant
        local upperLevel = string.upper(level)
        if RmLogging.LOG_LEVEL[upperLevel] then
            RmLogging.CURRENT_LOG_LEVEL = RmLogging.LOG_LEVEL[upperLevel]
        else
            RmLogging.logError("Invalid log level string: %s. Valid levels: ERROR, WARNING, INFO, DEBUG, TRACE", level)
        end
    elseif type(level) == "number" then
        -- Validate numeric log level
        if level >= 1 and level <= 5 then
            RmLogging.CURRENT_LOG_LEVEL = level
        else
            RmLogging.logError("Invalid log level number: %s. Valid range: 1-5", tostring(level))
        end
    else
        RmLogging.logError("Invalid log level type: %s. Expected string or number", type(level))
    end
end

---Gets the current log level name
---@return string Current log level name
function RmLogging.getLogLevel()
    for name, value in pairs(RmLogging.LOG_LEVEL) do
        if value == RmLogging.CURRENT_LOG_LEVEL then
            return name
        end
    end
    return "UNKNOWN"
end
