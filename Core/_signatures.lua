-- ============================================================================
-- VE_signatures.lua - API Reference
-- Function signatures for VamoosesEndeavors addon
-- ============================================================================

-- ============================================================================
-- Store.lua - Redux-lite state management
-- ============================================================================

VE.Store:GetState()                                  -- Returns current state table
VE.Store:RegisterReducer(action, reducerFn)          -- Register a reducer function for an action type
VE.Store:Dispatch(action, payload)                   -- Dispatch action to update state, triggers VE_STATE_CHANGED event
VE.Store:LoadFromSavedVariables()                    -- Load persisted state from VE_DB SavedVariables
VE.Store:SaveToSavedVariables()                      -- Save current state to VE_DB SavedVariables
VE.Store:QueueSave()                                 -- Queue a debounced save (1 second delay)
VE.Store:Flush()                                     -- Cancel pending save timer and save immediately

-- Built-in reducers (dispatch these actions):
-- "SET_CONFIG"                { key, value }        -- Update config setting
-- "SET_ENDEAVOR_INFO"         { seasonName, seasonEndTime, daysRemaining, currentProgress, maxProgress, milestones }
-- "SET_TASKS"                 { tasks }             -- Update endeavor tasks list
-- "UPDATE_CHARACTER_PROGRESS" { charKey, name, realm, class, tasks }
-- "SET_SELECTED_CHARACTER"    { charKey }           -- Change viewed character
-- "SET_HOUSE_GUID"            { houseGUID }         -- Cache current house GUID
-- "SET_HOUSE_LEVEL"           { level, xp, xpForNextLevel, maxLevel }
-- "SET_COUPONS"               { count, iconID }     -- Update community coupons

-- ============================================================================
-- EventBus.lua - Pub/Sub messaging
-- ============================================================================

VE.EventBus:Register(event, callback)                -- Register callback for event, returns nil
VE.EventBus:Trigger(event, payload)                  -- Fire event with optional payload to all listeners
VE.EventBus:Unregister(event, callback)              -- Remove specific callback, returns true/false

-- Internal events:
-- "VE_STATE_CHANGED"          { action, state }     -- Fired after Store:Dispatch
-- "VE_THEME_UPDATE"           { themeName }         -- Theme changed
-- "VE_ACTIVITY_LOG_UPDATED"                         -- Activity log data received

-- ============================================================================
-- Constants.lua - Theme and UI constants
-- ============================================================================

VE.Constants:GetThemeColors()                        -- Returns color scheme table for current theme
VE.Constants:ApplyTheme()                            -- Apply current theme to VE.Constants.Colors
VE.Constants:ToggleTheme()                           -- Cycle to next theme, returns new theme key
VE.Constants:GetCurrentTheme()                       -- Returns current theme key (e.g., "solarizeddark")
VE.Constants:GetColorCode(colorName)                 -- Returns WoW color code string "|cFFxxxxxx"

-- Tables:
-- VE.Constants.Colors         -- Current active color scheme
-- VE.Constants.UI             -- UI sizing constants (mainWidth, mainHeight, rowHeight, etc.)
-- VE.Constants.CURRENCY_IDS   -- Currency ID constants (COMMUNITY_COUPONS = 3363)
-- VE.Constants.ThemeOrder     -- Array of theme keys in cycle order
-- VE.Constants.ThemeNames     -- Map of theme key to scheme name
-- VE.Constants.ThemeDisplayNames -- Map of theme key to display name
-- VE.Colors.Schemes           -- All color scheme tables (SolarizedDark, SolarizedLight, etc.)

-- ============================================================================
-- Framework.lua - UI factory methods
-- ============================================================================

VE.UI:CreateMainFrame(name, title)                   -- Create main draggable window with title bar, returns frame
VE.UI:CreateButton(parent, text, width, height)      -- Create themed button, returns button frame
VE.UI:CreateTabButton(parent, text)                  -- Create tab button with active/inactive states, returns button
VE.UI:CreateProgressBar(parent, options)             -- Create progress bar with milestones, returns container
VE.UI:CreateTaskRow(parent, options)                 -- Create task row with status/points/progress, returns row
VE.UI:CreateDropdown(parent, options)                -- Create dropdown selector, returns container
VE.UI:CreateSectionHeader(parent, text)              -- Create section header with line, returns header frame
VE.UI:CreateScrollFrame(parent)                      -- Create scroll frame with styled scrollbar, returns scrollFrame, content
VE.UI:ColorCode(colorName)                           -- Returns WoW color code for named color "|cFFxxxxxx"

-- Widget methods:
-- progressBar:SetProgress(current, max)             -- Update progress bar fill and text
-- progressBar:SetMilestones(milestones, max)        -- Add milestone diamonds
-- taskRow:SetTask(task)                             -- Update row with task data
-- dropdown:SetItems(items)                          -- Set dropdown options [{key, label}]
-- dropdown:SetSelected(key, data)                   -- Set selected item
-- dropdown:GetSelected()                            -- Returns selected key
-- tabButton:SetActive(active)                       -- Set active state (boolean)

-- ============================================================================
-- ThemeEngine.lua - Live theme switching
-- ============================================================================

VE.Theme:Initialize()                                -- Initialize theme engine, listen for VE_THEME_UPDATE
VE.Theme:Register(widget, widgetType)                -- Register widget for theme updates
VE.Theme:UpdateAll()                                 -- Re-skin all registered widgets with current scheme
VE.Theme:GetScheme()                                 -- Returns current color scheme table
VE.Theme.ApplyTextShadow(fontString, scheme)         -- Apply/remove text shadow based on theme

-- Tables:
-- VE.Theme.registry           -- Weak table of registered widgets
-- VE.Theme.currentScheme      -- Current active color scheme
-- VE.Theme.Skinners           -- Skinner functions by widget type
-- VE.Theme.BACKDROP_FLAT      -- Standard backdrop with border
-- VE.Theme.BACKDROP_BORDERLESS -- Backdrop without border

-- Skinner types: Frame, Panel, Button, Text, SectionHeader, ProgressBar,
--                TaskRow, Dropdown, ScrollFrame, Checkbox, TitleBar, TabButton, HeaderText

-- ============================================================================
-- EndeavorTracker.lua - Endeavor data via C_NeighborhoodInitiative
-- ============================================================================

VE.EndeavorTracker:Initialize()                      -- Register events, setup listeners
VE.EndeavorTracker:FetchEndeavorData(skipRequest)    -- Fetch endeavor data, skipRequest=true skips API call
VE.EndeavorTracker:ProcessInitiativeInfo(info)       -- Process raw initiative info into Store
VE.EndeavorTracker:GetTaskProgress(task)             -- Extract current progress from task requirements
VE.EndeavorTracker:GetTaskMax(task)                  -- Extract max value from task requirements
VE.EndeavorTracker:GetTaskCouponReward(task)         -- Get coupon reward amount for task
VE.EndeavorTracker:RefreshTrackedTasks()             -- Update tracked status from API
VE.EndeavorTracker:LoadPlaceholderData()             -- Load fallback placeholder data
VE.EndeavorTracker:SaveCurrentCharacterProgress()    -- Save current character's task progress to Store
VE.EndeavorTracker:GetTrackedCharacters()            -- Returns array of tracked character info
VE.EndeavorTracker:GetCharacterProgress(charKey)     -- Returns character progress data or nil
VE.EndeavorTracker:TrackTask(taskID)                 -- Add task to objective tracker
VE.EndeavorTracker:UntrackTask(taskID)               -- Remove task from objective tracker
VE.EndeavorTracker:GetTaskLink(taskID)               -- Returns chat link for task or nil
VE.EndeavorTracker:GetActivityLogData()              -- Returns activity log info or nil
VE.EndeavorTracker:RequestActivityLog()              -- Request activity log from server
VE.EndeavorTracker:IsActivityLogLoaded()             -- Returns true if activity log has been loaded

-- ============================================================================
-- HousingTracker.lua - House level and currency via C_Housing
-- ============================================================================

VE.HousingTracker:Initialize()                       -- Register events for housing updates
VE.HousingTracker:RequestHouseInfo()                 -- Request house level/XP data from API
VE.HousingTracker:OnHouseListUpdated(houseInfoList)  -- Process PLAYER_HOUSE_LIST_UPDATED event
VE.HousingTracker:OnHouseLevelFavorUpdated(favor)    -- Process HOUSE_LEVEL_FAVOR_UPDATED event
VE.HousingTracker:UpdateCoupons()                    -- Fetch and dispatch community coupon count
VE.HousingTracker:GetHouseLevel()                    -- Returns level, xp, xpForNextLevel
VE.HousingTracker:GetCoupons()                       -- Returns coupons, couponsIcon
