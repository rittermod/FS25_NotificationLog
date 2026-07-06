-- Module declaration
-- Note: Dependencies (RmLogging, RmNotificationLogFrame) are loaded via scripts/main.lua
RmNotificationLog = {}
local RmNotificationLog_mt = Class(RmNotificationLog)

-- Logger instance
local Log = RmLogging.getLogger("NotificationLog")

-- Constants
RmNotificationLog.startYear = 2025                                       -- Start year for the notification log (Year 1 = 2025)
RmNotificationLog.TOP_NOTIFICATION_COLOR = { 0.0003, 0.5647, 0.9822, 1 } -- FS22 blue color for top notifications
RmNotificationLog.WARNING_COLOR = { 1, 0.3, 0.3, 1 }                     -- Red color for blinking warnings

-- Configure logging
-- Log:setLevel("DEBUG")

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
        Log:warning("logNotification called with nil notificationText")
        return
    end

    -- The in-game clock lives on g_currentMission.environment. On a joining
    -- client it can be briefly nil before the mission is fully initialised;
    -- drop the notification rather than index a nil environment.
    if g_currentMission == nil or g_currentMission.environment == nil then
        Log:trace("Skipping notification - g_currentMission.environment not ready")
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
    Log:info("Notification logged: %s %s | Text: %s",
        notification.realDateTime, notification.ingameDateTime, notification.notificationText)
    Log:trace("Notification table size: %d", #RmNotificationLog.notifications)
end

function RmNotificationLog.showNotificationLog()
    Log:debug("Showing notification log GUI")
    -- Defensive: a headless server has no g_gui. The RightShift+M action is never
    -- registered without a local viewer, but guard the entry point regardless.
    if g_gui == nil then
        return
    end
    if g_gui:getIsGuiVisible() then
        return
    end
    g_gui:showDialog("RmNotificationLogFrame")
end

function RmNotificationLog.loadMap()
    Log:debug("Mod loaded!")

    -- loadMap must stay GUI-only: everything below this guard is skipped on a
    -- headless dedicated server, which has no g_gui to register against. Check
    -- g_dedicatedServer first - a dedicated server also has g_server and g_client set.
    if g_dedicatedServer ~= nil then
        Log:debug("Dedicated server detected - skipping GUI registration")
        return
    end

    -- Load GUI profiles
    g_gui:loadProfiles(RmNotificationLog.dir .. "gui/guiProfiles.xml")

    -- Register Notification Log GUI
    RmNotificationLogFrame.register()
end

function RmNotificationLog.addPlayerActionEvents(self, controlling)
    -- No local input on a headless dedicated server -> do not register the action
    -- event (g_inputBinding is a client-side system). Symmetric with the loadMap /
    -- currentMissionStarted guards; keeps the RightShift+M binding viewer-only.
    if g_dedicatedServer ~= nil then
        Log:debug("Dedicated server detected - skipping action event registration")
        return
    end

    Log:debug("Adding player action events")
    local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = false, true,
        false, true, nil, true
    local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent("RM_SHOW_MESSAGE_LOG",
        RmNotificationLog, RmNotificationLog.showNotificationLog, triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings);

    if not success and controlling ~= "VEHICLE" then
        -- If we failed to register the action event, log an error
        -- except if we are in a vehicle then success is false even if the registration succeeded
        Log:error("Failed to register action event for RM_SHOW_MESSAGE_LOG")
        return
    end
    -- Hide the action event text
    g_inputBinding:setActionEventTextVisibility(actionEventId, false)
end

function RmNotificationLog.currentMissionStarted()
    Log:debug("Current mission started")

    -- No local viewer on a dedicated server -> do not install capture hooks
    -- (otherwise the headless server accumulates an unviewable, unbounded log).
    -- Check g_dedicatedServer first - a dedicated server also has g_server/g_client.
    if g_dedicatedServer ~= nil then
        Log:debug("Dedicated server detected - skipping capture hooks")
        return
    end

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
                    -- The in-game clock can be briefly nil on a joining client;
                    -- skip this warning rather than index a nil environment.
                    if g_currentMission == nil or g_currentMission.environment == nil then
                        return
                    end
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
