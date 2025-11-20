--[[
    main.lua

    Main loader for RmNotificationLog mod.
    Loads all dependencies in the correct order.

    Author: Ritter
]]

local modDirectory = g_currentModDirectory

-- Load logging utility first (required by all other files)
source(modDirectory .. "scripts/RmLogging.lua")

-- Load GUI components (depends on RmLogging for debug output)
source(modDirectory .. "gui/RmNotificationLogFrame.lua")

-- Load main mod logic last (depends on RmLogging and GUI components)
source(modDirectory .. "scripts/RmNotificationLog.lua")
