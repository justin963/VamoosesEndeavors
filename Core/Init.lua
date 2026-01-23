-- ============================================================================
-- Vamoose's Endeavors - Init
-- Addon initialization and slash commands
-- ============================================================================

VE = VE or {}
VE.frame = CreateFrame("Frame")
VE.frame:RegisterEvent("ADDON_LOADED")
VE.frame:RegisterEvent("PLAYER_LOGIN")
VE.frame:RegisterEvent("PLAYER_LOGOUT")

function VE:OnInitialize()
    -- Initialize SavedVariables
    VE_DB = VE_DB or {}

    -- Load persisted state
    VE.Store:LoadFromSavedVariables()

    -- Apply saved theme
    VE.Constants:ApplyTheme()

    -- Initialize Theme Engine (must be after theme is applied)
    if VE.Theme and VE.Theme.Initialize then
        VE.Theme:Initialize()
    end

    self.db = VE_DB

    local version = C_AddOns.GetAddOnMetadata("VamoosesEndeavors", "Version") or "Dev"
    print("|cFF2aa198[VE]|r Vamoose's Endeavors v" .. version .. " loaded. Type /ve to open.")
end

function VE:OnEnable()
    -- Trigger addon enabled event
    VE.EventBus:Trigger("VE_ADDON_ENABLED")

    -- Initialize UI
    if VE.CreateMainWindow then
        VE:CreateMainWindow()
    end

    -- Initialize Endeavor Tracker
    if VE.EndeavorTracker and VE.EndeavorTracker.Initialize then
        VE.EndeavorTracker:Initialize()
    end

    -- Initialize Housing Tracker
    if VE.HousingTracker and VE.HousingTracker.Initialize then
        VE.HousingTracker:Initialize()
    end

    -- Initialize Minimap Button
    if VE.Minimap and VE.Minimap.Initialize then
        VE.Minimap:Initialize()
    end
end

-- Event Handler
VE.frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "VamoosesEndeavors" then
        VE:OnInitialize()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        VE:OnEnable()
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGOUT" then
        VE.Store:Flush()
    end
end)

-- Toggle main window (alias for minimap/compartment)
function VE:Toggle()
    self:ToggleWindow()
end

-- Toggle main window
function VE:ToggleWindow()
    if not self.MainFrame then
        self:CreateMainWindow()
    end
    if self.MainFrame:IsShown() then
        self.MainFrame:Hide()
    else
        self.MainFrame:Show()
        self:RefreshUI()
    end
end

-- Refresh UI
function VE:RefreshUI()
    local frame = self.MainFrame
    if not frame or not frame:IsShown() then return end

    -- Refresh housing display (coupons + house level)
    if frame.UpdateHousingDisplay then
        frame:UpdateHousingDisplay()
    end

    -- Refresh header (always visible)
    if frame.UpdateHeader then
        frame:UpdateHeader()
    end

    -- Refresh the endeavors view (task list only)
    if frame.endeavorsTab and frame.endeavorsTab.Update then
        frame.endeavorsTab:Update()
    end
end

-- Rebuild UI after theme change
function VE:RebuildUI()
    local wasShown = self.MainFrame and self.MainFrame:IsShown()

    -- Destroy existing frame
    if self.MainFrame then
        self.MainFrame:Hide()
        self.MainFrame:SetParent(nil)
        self.MainFrame = nil
    end

    -- Recreate the window with new theme colors
    self:CreateMainWindow()

    -- Show if it was visible
    if wasShown then
        self.MainFrame:Show()
        self:RefreshUI()
    end
end

-- Get current character key
function VE:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_VE1 = "/ve"
SLASH_VE2 = "/endeavors"
SlashCmdList["VE"] = function(msg)
    local command = msg:lower():match("^(%S*)")

    if command == "" or command == "show" then
        VE:ToggleWindow()
    elseif command == "debug" then
        local state = VE.Store:GetState()
        VE.Store:Dispatch("SET_CONFIG", { key = "debug", value = not state.config.debug })
        print("|cFF2aa198[VE]|r Debug mode:", state.config.debug and "OFF" or "ON")
    elseif command == "refresh" then
        if VE.EndeavorTracker then
            VE.EndeavorTracker:FetchEndeavorData()
        end
        print("|cFF2aa198[VE]|r Refreshing endeavor data...")
    elseif command == "dump" then
        -- Debug: dump current state
        local state = VE.Store:GetState()
        print("|cFF2aa198[VE]|r Current state:")
        print("  Season:", state.endeavor.seasonName)
        print("  Tasks:", #state.tasks)
        print("  Characters:", 0)
        for k, _ in pairs(state.characters) do
            print("    -", k)
        end
    elseif command == "tasks" then
        -- Debug: dump task structure - search for specific tasks
        print("|cFF2aa198[VE]|r Searching for debug tasks...")
        if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo then
            local info = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo()
            if info and info.tasks then
                local found = false
                for _, task in ipairs(info.tasks) do
                    local taskName = task.taskName or ""
                    local nameLower = taskName:lower()
                    if nameLower:find("hoard") or nameLower:find("forbidden") or
                       nameLower:find("lumber") or nameLower:find("harvest") or
                       nameLower:find("rare") then
                        found = true
                        print(string.format("Task: %s", taskName))
                        print(string.format("  taskType = %s (0=Single, 1=RepeatableFinite, 2=Infinite)", tostring(task.taskType)))
                        print(string.format("  timesCompleted = %s", tostring(task.timesCompleted)))
                        print(string.format("  completed = %s", tostring(task.completed)))
                        print(string.format("  rewardQuestID = %s", tostring(task.rewardQuestID)))
                        print(string.format("  progressContributionAmount = %s", tostring(task.progressContributionAmount)))
                        -- Get ALL currency rewards from quest (not just coupons)
                        if task.rewardQuestID and task.rewardQuestID > 0 then
                            local rewards = C_QuestLog.GetQuestRewardCurrencies(task.rewardQuestID)
                            if rewards then
                                print("  Quest currency rewards:")
                                for _, reward in ipairs(rewards) do
                                    print(string.format("    ID %d: %s x%d", reward.currencyID or 0, reward.name or "?", reward.totalRewardAmount or 0))
                                end
                            end
                        end
                        -- Show all other fields
                        for k, v in pairs(task) do
                            if type(v) ~= "table" and k ~= "taskName" and k ~= "taskType" and
                               k ~= "timesCompleted" and k ~= "completed" and k ~= "rewardQuestID" and
                               k ~= "progressContributionAmount" then
                                print(string.format("  %s = %s", k, tostring(v)))
                            end
                        end
                        print("---")
                    end
                end
                if not found then
                    print("  No matching tasks found in current initiative")
                end
            else
                print("  No initiative info or tasks")
            end
        else
            print("  C_NeighborhoodInitiative not available")
        end
    elseif command == "questreward" then
        -- Debug: check quest reward for rewardQuestID 91024
        local questID = 91024
        print("|cFF2aa198[VE]|r Checking quest reward for ID:", questID)

        -- Try C_QuestLog methods
        if C_QuestLog then
            local rewards = C_QuestLog.GetQuestRewardCurrencies(questID)
            if rewards and #rewards > 0 then
                print("  Currency rewards:")
                for _, reward in ipairs(rewards) do
                    print(string.format("    %s x%d (ID: %d)", reward.name or "?", reward.totalRewardAmount or 0, reward.currencyID or 0))
                end
            else
                print("  No currency rewards from C_QuestLog")
            end
        end

        -- Try GetQuestCurrencyInfo
        if GetNumQuestLogRewardCurrencies then
            local numCurrencies = GetNumQuestLogRewardCurrencies(questID)
            if numCurrencies and numCurrencies > 0 then
                print("  GetNumQuestLogRewardCurrencies:", numCurrencies)
            end
        end
    elseif command == "currencies" then
        -- Debug: scan currencies looking for Community Coupons or housing-related
        print("|cFF2aa198[VE]|r Scanning currencies for housing/community/coupon...")
        local found = 0
        for i = 1, 3000 do
            local info = C_CurrencyInfo.GetCurrencyInfo(i)
            if info and info.name and info.name ~= "" then
                local nameLower = info.name:lower()
                if nameLower:find("community") or nameLower:find("coupon") or
                   nameLower:find("housing") or nameLower:find("endeavor") or
                   nameLower:find("neighborhood") or nameLower:find("initiative") then
                    print(string.format("  ID %d: %s (qty: %d)", i, info.name, info.quantity or 0))
                    found = found + 1
                end
            end
        end
        if found == 0 then
            print("  No matching currencies found. Try /ve allcurrencies for full list.")
        end
    elseif command == "allcurrencies" then
        -- Debug: list all currencies with non-zero quantity
        print("|cFF2aa198[VE]|r Currencies with quantity > 0:")
        for i = 1, 3000 do
            local info = C_CurrencyInfo.GetCurrencyInfo(i)
            if info and info.name and info.name ~= "" and info.quantity and info.quantity > 0 then
                print(string.format("  ID %d: %s (qty: %d)", i, info.name, info.quantity))
            end
        end
    elseif command == "activity" then
        -- Debug: dump activity log data
        -- API Reference: https://warcraft.wiki.gg/wiki/Category:API_systems/NeighborhoodInitiative
        print("|cFF2aa198[VE]|r Checking activity log APIs...")
        if C_NeighborhoodInitiative then
            -- List all available functions
            print("  Available C_NeighborhoodInitiative functions:")
            for k, v in pairs(C_NeighborhoodInitiative) do
                if type(v) == "function" then
                    print(string.format("    %s()", k))
                end
            end
            -- First request the activity log data
            if C_NeighborhoodInitiative.RequestInitiativeActivityLog then
                print("  Calling RequestInitiativeActivityLog()...")
                C_NeighborhoodInitiative.RequestInitiativeActivityLog()
            end
            -- Then get the activity log info
            if C_NeighborhoodInitiative.GetInitiativeActivityLogInfo then
                print("  Calling GetInitiativeActivityLogInfo()...")
                local log = C_NeighborhoodInitiative.GetInitiativeActivityLogInfo()
                if log then
                    print("  Activity log type:", type(log))
                    if type(log) == "table" then
                        -- Check if it's a single object or array
                        if log[1] then
                            print("  Activity log entries:", #log)
                            for i, entry in ipairs(log) do
                                if i <= 10 then -- Limit to first 10
                                    print(string.format("    [%d]", i))
                                    if type(entry) == "table" then
                                        for k, v in pairs(entry) do
                                            print(string.format("      %s = %s", k, tostring(v)))
                                        end
                                    else
                                        print(string.format("      %s", tostring(entry)))
                                    end
                                end
                            end
                        else
                            -- Single object, dump all fields
                            print("  Activity log info fields:")
                            for k, v in pairs(log) do
                                if type(v) == "table" then
                                    print(string.format("    %s = (table with %d entries)", k, #v))
                                    for i, entry in ipairs(v) do
                                        if i <= 5 then
                                            print(string.format("      [%d]", i))
                                            if type(entry) == "table" then
                                                for ek, ev in pairs(entry) do
                                                    print(string.format("        %s = %s", ek, tostring(ev)))
                                                end
                                            else
                                                print(string.format("        %s", tostring(entry)))
                                            end
                                        end
                                    end
                                else
                                    print(string.format("    %s = %s", k, tostring(v)))
                                end
                            end
                        end
                    end
                else
                    print("  GetInitiativeActivityLogInfo returned nil (data may not be loaded yet)")
                    print("  Try: /ve activity again after a moment")
                end
            else
                print("  GetInitiativeActivityLogInfo not found")
            end
        else
            print("  C_NeighborhoodInitiative not available")
        end
    elseif command == "house" then
        -- Debug: dump C_Housing API data
        print("|cFF2aa198[VE]|r Housing API Debug:")
        if not C_Housing then
            print("  C_Housing API not available")
        else
            -- List available functions
            print("  Available C_Housing functions:")
            for k, v in pairs(C_Housing) do
                if type(v) == "function" then
                    print("    " .. k)
                end
            end

            -- Get player houses
            print("\n  Requesting player houses...")
            local success, result = pcall(C_Housing.GetPlayerOwnedHouses)
            if success then
                print("  GetPlayerOwnedHouses called (async - check PLAYER_HOUSE_LIST_UPDATED event)")
            else
                print("  GetPlayerOwnedHouses error: " .. tostring(result))
            end

            -- Try to get max level
            if C_Housing.GetMaxHouseLevel then
                local success2, maxLevel = pcall(C_Housing.GetMaxHouseLevel)
                if success2 then
                    print("  Max House Level: " .. tostring(maxLevel))
                end
            end

            -- Try to get favor thresholds for levels 1-10
            if C_Housing.GetHouseLevelFavorForLevel then
                print("  House Level XP Thresholds:")
                for level = 1, 10 do
                    local success3, xp = pcall(C_Housing.GetHouseLevelFavorForLevel, level)
                    if success3 and xp then
                        print(string.format("    Level %d: %d XP", level, xp))
                    end
                end
            end
        end
    else
        print("|cFF2aa198[VE]|r Commands:")
        print("  /ve - Toggle window")
        print("  /ve debug - Toggle debug mode")
        print("  /ve refresh - Refresh endeavor data")
        print("  /ve dump - Dump current state")
        print("  /ve house - Debug housing API")
        print("  /ve currencies - Scan for housing currencies")
    end
end
