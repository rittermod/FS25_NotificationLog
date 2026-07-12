-- Notification Log Frame
-- Displays notification history in a GUI dialog

local Log = RmLogging.getLogger("NotificationLog")

RmNotificationLogFrame = {}
local RmNotificationLogFrame_mt = Class(RmNotificationLogFrame, MessageDialog)

-- UI Color constants (cached for performance)
RmNotificationLogFrame.ERROR_COLOR = {0.9, 0.2, 0.2, 1}       -- Red for errors/critical
RmNotificationLogFrame.WARNING_COLOR = {1.0, 0.8, 0.2, 1}     -- Yellow for warnings  
RmNotificationLogFrame.INFO_COLOR = {0.7, 0.7, 0.7, 1}        -- Gray for info
RmNotificationLogFrame.SUCCESS_COLOR = {0.2, 0.8, 0.2, 1}     -- Green for success

RmNotificationLogFrame.CONTROLS = {
    "notificationTable",
    "tableSlider", 
    "totalNotificationsLabel",
    "totalNotificationsValue",
    "buttonClearLog"
}

function RmNotificationLogFrame.new(target, custom_mt)
    Log:trace("RmNotificationLogFrame:new()")
    local self = MessageDialog.new(target, custom_mt or RmNotificationLogFrame_mt)
    self.notifications = {}
    return self
end

function RmNotificationLogFrame:onGuiSetupFinished()
    Log:trace("RmNotificationLogFrame:onGuiSetupFinished()")
    RmNotificationLogFrame:superClass().onGuiSetupFinished(self)
    self.notificationTable:setDataSource(self)
    self.notificationTable:setDelegate(self)
end

function RmNotificationLogFrame:onCreate()
    Log:trace("RmNotificationLogFrame:onCreate()")
    RmNotificationLogFrame:superClass().onCreate(self)
end

--- Newest-first dual-clock comparator: primary key is in-game time, real time is
--- the tiebreak within the same in-game minute. Both are zero-padded fixed-width
--- strings, so plain string comparison orders them correctly. Nil fields coerce to
--- "" so a record missing either clock sorts as oldest rather than erroring.
--- Pure (dot, no self) so it is unit-testable without a live dialog. Equal keys
--- return false in both directions (equal under a strict-weak ordering); table.sort
--- stability is not relied upon.
---@param a table Notification record with ingameDateTime / realDateTime strings.
---@param b table Notification record with ingameDateTime / realDateTime strings.
---@return boolean sortsBefore True when a should sort before b (a is newer).
function RmNotificationLogFrame.compareNotificationsNewestFirst(a, b)
    local aIngame = a.ingameDateTime or ""
    local bIngame = b.ingameDateTime or ""
    if aIngame == bIngame then
        return (a.realDateTime or "") > (b.realDateTime or "")
    end
    return aIngame > bIngame
end

function RmNotificationLogFrame:onOpen()
    Log:trace("RmNotificationLogFrame:onOpen()")
    RmNotificationLogFrame:superClass().onOpen(self)

    -- Get notifications from the main notification log
    if RmNotificationLog.notifications then
        self.notifications = RmNotificationLog.notifications
        -- Sort notifications by in-game time, then by real time if same, newest first
        table.sort(self.notifications, RmNotificationLogFrame.compareNotificationsNewestFirst)
    else
        self.notifications = {}
    end
    
    -- Update total notifications display
    self.totalNotificationsValue:setText(tostring(#self.notifications))
    
    -- Reload the table data
    self.notificationTable:reloadData()
    
    -- Set focus to the table
    self:setSoundSuppressed(true)
    FocusManager:setFocus(self.notificationTable)
    self:setSoundSuppressed(false)
end

function RmNotificationLogFrame:onClose()
    Log:trace("RmNotificationLogFrame:onClose()")
    self.notifications = {}
    RmNotificationLogFrame:superClass().onClose(self)
end

-- Table data source methods
function RmNotificationLogFrame:getNumberOfItemsInSection(list, section)
    if list == self.notificationTable then
        return #self.notifications
    else
        return 0
    end
end

function RmNotificationLogFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.notificationTable then
        local notification = self.notifications[index]
        if notification then
            -- Set notification data in the cell
            cell:getAttribute("ingameDateTime"):setText(notification.ingameDateTime or g_i18n:getText("ui_notification_log_no_data"))
            cell:getAttribute("notificationText"):setText(notification.notificationText or "")
            
            -- Set color based on original notification color
            local notificationTextElement = cell:getAttribute("notificationText")
            local color = notification.color
            
            if color then
                notificationTextElement.textColor = color
            else
                notificationTextElement.textColor = RmNotificationLogFrame.INFO_COLOR
            end
        end
    end
end

-- Button handlers
function RmNotificationLogFrame:onClickClose()
    Log:trace("RmNotificationLogFrame:onClickClose()")
    self:close()
end

function RmNotificationLogFrame:onClickClearLog()
    Log:trace("RmNotificationLogFrame:onClickClearLog()")
    
    -- Show confirmation dialog
    local confirmationText = string.format(g_i18n:getText("ui_notification_log_clear_confirmation"), #self.notifications)
    
    YesNoDialog.show(self.onYesNoClearLog, self, confirmationText, g_i18n:getText("ui_notification_log_clear_title"), g_i18n:getText("ui_notification_log_clear_yes"), g_i18n:getText("ui_notification_log_clear_no"))
end

function RmNotificationLogFrame:onYesNoClearLog(yes)
    if yes then
        -- Clear the notification log
        if RmNotificationLog then
            RmNotificationLog.notifications = {}
            self.notifications = {}
            
            -- Update display
            self.totalNotificationsValue:setText("0")
            self.notificationTable:reloadData()
            
            Log:info("Notification log cleared via GUI")
        end
    end
end

function RmNotificationLogFrame.register()
    Log:trace("RmNotificationLogFrame.register()")
    local dialog = RmNotificationLogFrame.new(g_i18n)
    g_gui:loadGui(RmNotificationLog.dir .. "gui/RmNotificationLogFrame.xml", "RmNotificationLogFrame", dialog)
end
