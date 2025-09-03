RmUtils = {}
local RmUtils_mt = Class(RmUtils)

local debugEnabled = false
local traceEnabled = false
local LOG_PREFIX = "[RmNotificationLog] "

local function debugPrint(msg)
    print(string.format("  Debug: %s", msg))
end

local function tracePrint(msg)
    print(string.format("  Trace: %s", msg))
end

local function logCommon(logFunc, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "nil" then
            v = "(nil)"
        end
        if type(v) == "table" then
            local parts = {}
            for k, val in pairs(v) do
                if type(val) == "table" then
                    val = "(table)"
                end
                table.insert(parts, string.format("%s: %s", tostring(k), tostring(val)))
            end
            v = table.concat(parts, ", ")
        end
        logFunc(string.format("%s%s", LOG_PREFIX, tostring(v)))
    end
end

function RmUtils.logInfo(...)
    logCommon(Logging.info, ...)
end

function RmUtils.logWarning(...)
    logCommon(Logging.warning, ...)
end

function RmUtils.logError(...)
    logCommon(Logging.error, ...)
end

function RmUtils.logDebug(...)
    if debugEnabled then
        logCommon(debugPrint, ...)
    end
end

function RmUtils.logTrace(...)
    if traceEnabled then
        logCommon(tracePrint, ...)
    end
end

function RmUtils.tableToString(tbl, indent, maxDepth, initialIndent)
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
            table.insert(result, RmUtils.tableToString(v, indent + 1, maxDepth, initialIndent))
        else
            table.insert(result, string.format("%s%s", formatting, tostring(v)))
        end
    end

    return table.concat(result, "\n")
end

function RmUtils.functionParametersToString(...)
    local args = { ... }
    local result = {}

    for i, v in ipairs(args) do
        table.insert(result, string.format("Parameter %d: (%s) %s", i, type(v), tostring(v)))
        if type(v) == "table" then
            table.insert(result, RmUtils.tableToString(v, 0, 2))
        end
    end

    return table.concat(result, "\n")
end
