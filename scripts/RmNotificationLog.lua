-- Module declaration
-- Note: Dependencies (RmLogging, RmNotificationLogFrame) are loaded via scripts/main.lua
RmNotificationLog = {}
local RmNotificationLog_mt = Class(RmNotificationLog)

-- Constants
RmNotificationLog.startYear = 2025                                       -- Start year for the notification log (Year 1 = 2025)
RmNotificationLog.TOP_NOTIFICATION_COLOR = { 0.0003, 0.5647, 0.9822, 1 } -- FS22 blue color for top notifications
RmNotificationLog.WARNING_COLOR = { 1, 0.3, 0.3, 1 }                     -- Red color for blinking warnings

-- Configure logging
RmLogging.setLogPrefix("[RmNotificationLog]")
-- RmLogging.setLogLevel(RmLogging.LOG_LEVEL.DEBUG)

-- Table to store notifications (module level for compatibility)
RmNotificationLog.notifications = {}

-- Table to track logged warnings with timestamps to prevent duplicates within duration
RmNotificationLog.loggedWarnings = {}

function RmNotificationLog.new(customMt)
    local self = setmetatable({}, customMt or RmNotificationLog_mt)
    self.notifications = RmNotificationLog.notifications -- Reference to shared notification table
    return self
end

RmNotificationLog.dir = g_currentModDirectory
-- Note: RmNotificationLogFrame loaded via main.lua

function RmNotificationLog.logNotification(notificationText, color)
    -- Parameter validation
    if notificationText == nil then
        RmLogging.logWarning("logNotification called with nil notificationText")
        return
    end

    -- Convert the ingame datetime to a calender datetime.
    -- Adjust month to be 1-12 range. Periods starts in march, so we add 2 to align with the calendar.
    -- Then we adjust the month if it exceeds 12 (i.e., January and February).
    local month = g_currentMission.environment.currentPeriod + 2
    if month > 12 then
        month = month - 12
    end
    -- Ingame year changes in March, so we need to adjust the "calendar" year
    local year = g_currentMission.environment.currentYear + RmNotificationLog.startYear - 1
    if month < 3 then
        year = year + 1
    end
    -- For ingame day we just use the current day in the period
    local day = g_currentMission.environment.currentDayInPeriod
    local hour = g_currentMission.environment.currentHour
    local minute = g_currentMission.environment.currentMinute
    local ingameDateTime = string.format("%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
    local realDateTime = getDate("%Y-%m-%dT%H:%M:%S%z")

    local notification = {
        realDateTime = realDateTime,
        ingameDateTime = ingameDateTime,
        notificationText = notificationText,
        color = color,
    }

    table.insert(RmNotificationLog.notifications, notification)
    RmLogging.logInfo(string.format("Notification logged: %s %s | Text: %s",
        notification.realDateTime, notification.ingameDateTime, notification.notificationText))
    RmLogging.logTrace("Notification table size:", #RmNotificationLog.notifications)
end

function RmNotificationLog.showNotificationLog()
    RmLogging.logDebug("Showing notification log GUI")
    if g_gui:getIsGuiVisible() then
        return
    end
    g_gui:showDialog("RmNotificationLogFrame")
end

function RmNotificationLog.loadMap()
    RmLogging.logDebug("Mod loaded!")

    -- Load GUI profiles
    g_gui:loadProfiles(RmNotificationLog.dir .. "gui/guiProfiles.xml")

    -- Register Notification Log GUI
    RmNotificationLogFrame.register()
end

function RmNotificationLog.addPlayerActionEvents(self, controlling)
    RmLogging.logDebug("Adding player action events")
    local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = false, true,
        false, true, nil, true
    local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent("RM_SHOW_MESSAGE_LOG",
        RmNotificationLog, RmNotificationLog.showNotificationLog, triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings);

    if not success and controlling ~= "VEHICLE" then
        -- If we failed to register the action event, log an error
        -- except if we are in a vehicle then success is false even if the registration succeeded
        RmLogging.logError("Failed to register action event for RM_SHOW_MESSAGE_LOG")
        return
    end
    -- Hide the action event text
    g_inputBinding:setActionEventTextVisibility(actionEventId, false)
end

function RmNotificationLog.currentMissionStarted()
    RmLogging.logDebug("Current mission started")

    -- Hook into HUD side notifications
    if g_currentMission.hud and g_currentMission.hud.addSideNotification then
        g_currentMission.hud.addSideNotification = Utils.appendedFunction(g_currentMission.hud.addSideNotification,
            function(self, color, text, duration, sound)
                if text and text ~= "" then
                    RmNotificationLog.logNotification(text, color)
                end
            end)
    end

    -- Hook into HUD top notifications
    if g_currentMission and g_currentMission.addGameNotification then
        g_currentMission.addGameNotification = Utils.prependedFunction(g_currentMission.addGameNotification,
            function(self, title, text, info, icon, duration, notification, iconFilename)
                local notificationTitle = title or ""
                local notificationText = text or ""
                local notificationInfo = info or ""
                -- Build notification from available parts
                local parts = {}
                if notificationTitle and notificationTitle:match("%S") then
                    table.insert(parts, notificationTitle)
                end
                if notificationText and notificationText:match("%S") then
                    table.insert(parts, notificationText)
                end
                if notificationInfo and notificationInfo:match("%S") then
                    table.insert(parts, notificationInfo)
                end

                if #parts > 0 then
                    local combinedNotification = table.concat(parts, " - ")
                    RmNotificationLog.logNotification(combinedNotification, RmNotificationLog.TOP_NOTIFICATION_COLOR)
                end
            end)
    end

    -- Hook into blinking warnings
    if g_currentMission and g_currentMission.showBlinkingWarning then
        g_currentMission.showBlinkingWarning = Utils.prependedFunction(g_currentMission.showBlinkingWarning,
            function(self, text, _, _)
                if text and text ~= "" then
                    -- Get current in-game minute for tracking
                    local currentMinute = g_currentMission.environment.currentMinute
                    local currentHour = g_currentMission.environment.currentHour
                    local currentDay = g_currentMission.environment.currentDayInPeriod
                    local currentPeriod = g_currentMission.environment.currentPeriod
                    local currentYear = g_currentMission.environment.currentYear

                    -- Create unique time key for this in-game minute
                    local timeKey = string.format("%d-%d-%d-%d-%d", currentYear, currentPeriod, currentDay, currentHour,
                        currentMinute)

                    -- Create unique key using self identity, text, and time
                    local selfId = tostring(self)
                    local warningKey = selfId .. "|" .. text .. "|" .. timeKey

                    -- Check if we've already logged this warning in this in-game minute
                    if not RmNotificationLog.loggedWarnings[warningKey] then
                        local warningText = "Warning: " .. text
                        RmNotificationLog.logNotification(warningText, RmNotificationLog.WARNING_COLOR)
                        RmNotificationLog.loggedWarnings[warningKey] = true
                    end
                end
            end)
    end
end

g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, RmNotificationLog.currentMissionStarted)

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents, RmNotificationLog.addPlayerActionEvents)

addModEventListener(RmNotificationLog)
