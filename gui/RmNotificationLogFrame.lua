-- Notification Log Frame
-- Displays notification history in a GUI dialog

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
    RmLogging.logTrace("RmNotificationLogFrame:new()")
    local self = MessageDialog.new(target, custom_mt or RmNotificationLogFrame_mt)
    self.notifications = {}
    return self
end

function RmNotificationLogFrame:onGuiSetupFinished()
    RmLogging.logTrace("RmNotificationLogFrame:onGuiSetupFinished()")
    RmNotificationLogFrame:superClass().onGuiSetupFinished(self)
    self.notificationTable:setDataSource(self)
    self.notificationTable:setDelegate(self)
end

function RmNotificationLogFrame:onCreate()
    RmLogging.logTrace("RmNotificationLogFrame:onCreate()")
    RmNotificationLogFrame:superClass().onCreate(self)
end

function RmNotificationLogFrame:onOpen()
    RmLogging.logTrace("RmNotificationLogFrame:onOpen()")
    RmNotificationLogFrame:superClass().onOpen(self)
    
    -- Get notifications from the main notification log
    if RmNotificationLog.notifications then
        self.notifications = RmNotificationLog.notifications
        -- Sort notifications by in-game time, then by real time if same, newest first
        table.sort(self.notifications, function(a, b)
            local aIngame = a.ingameDateTime or ""
            local bIngame = b.ingameDateTime or ""
            if aIngame == bIngame then
                return (a.realDateTime or "") > (b.realDateTime or "")
            end
            return aIngame > bIngame
        end)
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
    RmLogging.logTrace("RmNotificationLogFrame:onClose()")
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
    RmLogging.logTrace("RmNotificationLogFrame:onClickClose()")
    self:close()
end

function RmNotificationLogFrame:onClickClearLog()
    RmLogging.logTrace("RmNotificationLogFrame:onClickClearLog()")
    
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
            
            RmLogging.logInfo("Notification log cleared via GUI")
        end
    end
end

function RmNotificationLogFrame.register()
    RmLogging.logTrace("RmNotificationLogFrame.register()")
    local dialog = RmNotificationLogFrame.new(g_i18n)
    g_gui:loadGui(RmNotificationLog.dir .. "gui/RmNotificationLogFrame.xml", "RmNotificationLogFrame", dialog)
end

-- Static function to show the notification log dialog
function RmNotificationLogFrame.showNotificationLog()
    RmLogging.logTrace("RmNotificationLogFrame.showNotificationLog()")
    
    -- Create and show the dialog
    local dialog = RmNotificationLogFrame.new()
    g_gui:showDialog("RmNotificationLogFrame")
end