-- ============================================================================
-- Vamoose's Endeavors - EndeavorTracker
-- Fetches and tracks housing endeavor data using C_NeighborhoodInitiative API
-- API Reference: https://warcraft.wiki.gg/wiki/Category:API_systems/NeighborhoodInitiative
-- ============================================================================

VE = VE or {}
VE.EndeavorTracker = {}

local Tracker = VE.EndeavorTracker

-- Frame for event handling
Tracker.frame = CreateFrame("Frame")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Tracker:Initialize()
    -- Register for neighborhood initiative events
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("NEIGHBORHOOD_INITIATIVE_UPDATED")
    self.frame:RegisterEvent("INITIATIVE_TASKS_TRACKED_UPDATED")
    self.frame:RegisterEvent("INITIATIVE_TASKS_TRACKED_LIST_CHANGED")
    self.frame:RegisterEvent("INITIATIVE_ACTIVITY_LOG_UPDATED")
    self.frame:RegisterEvent("INITIATIVE_TASK_COMPLETED")
    self.frame:RegisterEvent("INITIATIVE_COMPLETED")
    self.frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")

    -- Track activity log loading state
    self.activityLogLoaded = false

    -- Track fetch status for UI display
    self.fetchStatus = {
        state = "pending",  -- "pending", "fetching", "loaded", "retrying"
        attempt = 0,
        lastAttempt = nil,
        nextRetry = nil,
    }

    -- Track pending retry timer (to cancel on new fetch)
    self.pendingRetryTimer = nil

    -- Track house list for house selector
    self.houseList = {}
    self.selectedHouseIndex = (VE_DB and VE_DB.selectedHouseIndex) or 1 -- Load saved selection
    self.houseListLoaded = false -- Flag to track if we've received house list

    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)

    -- Listen for state changes to save character progress (debounced)
    VE.EventBus:Register("VE_STATE_CHANGED", function(payload)
        if payload.action == "SET_TASKS" or payload.action == "SET_ENDEAVOR_INFO" then
            -- Debounce character saves - only save once per second max
            if self.saveCharProgressTimer then
                self.saveCharProgressTimer:Cancel()
            end
            self.saveCharProgressTimer = C_Timer.NewTimer(0.5, function()
                self.saveCharProgressTimer = nil
                self:SaveCurrentCharacterProgress()
            end)
        end
    end)

    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE Tracker]|r Initialized with C_NeighborhoodInitiative API")
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

function Tracker:OnEvent(event, ...)
    local debug = VE.Store:GetState().config.debug

    if event == "PLAYER_ENTERING_WORLD" then
        -- Initialize housing system first (like Blizzard's dashboard does)
        -- This triggers PLAYER_HOUSE_LIST_UPDATED which handles the actual data fetch
        -- DON'T call FetchEndeavorData here - wait for PLAYER_HOUSE_LIST_UPDATED to set neighborhood context first
        C_Timer.After(2, function()
            if C_Housing and C_Housing.GetPlayerOwnedHouses then
                if debug then
                    print("|cFF2aa198[VE Tracker]|r Requesting player house list to initialize housing system...")
                end
                -- This will trigger PLAYER_HOUSE_LIST_UPDATED which does the proper API sequence
                C_Housing.GetPlayerOwnedHouses()
            end
        end)

    elseif event == "NEIGHBORHOOD_INITIATIVE_UPDATED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r NEIGHBORHOOD_INITIATIVE_UPDATED")
        end
        self:QueueDataRefresh()

    elseif event == "INITIATIVE_TASKS_TRACKED_UPDATED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Tracked tasks updated")
        end
        self:QueueDataRefresh()
        self:RefreshTrackedTasks()

    elseif event == "INITIATIVE_TASKS_TRACKED_LIST_CHANGED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Task tracking list changed")
        end
        self:RefreshTrackedTasks()

    elseif event == "INITIATIVE_ACTIVITY_LOG_UPDATED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Activity log updated")
        end
        self.activityLogLoaded = true
        self.activityLogLastUpdated = time()
        VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED", { timestamp = self.activityLogLastUpdated })
        self:QueueDataRefresh()

    elseif event == "INITIATIVE_TASK_COMPLETED" then
        local taskName = ...
        if debug then
            print("|cFF2aa198[VE Tracker]|r Task completed: " .. tostring(taskName))
        end
        self:QueueDataRefresh()

    elseif event == "INITIATIVE_COMPLETED" then
        local initiativeTitle = ...
        if debug then
            print("|cFF2aa198[VE Tracker]|r Initiative completed: " .. tostring(initiativeTitle))
        end
        self:FetchEndeavorData(true)

    elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
        -- House list loaded - extract neighborhood and set viewing context (CRITICAL for API to work)
        local houseInfoList = ...
        if debug then
            print("|cFF2aa198[VE Tracker]|r House list updated with " .. (houseInfoList and #houseInfoList or 0) .. " houses")
        end

        -- Store house list for UI dropdown
        self.houseList = houseInfoList or {}
        self.houseListLoaded = true

        -- Preserve user's dropdown selection if still valid
        local selectedIndex = self.selectedHouseIndex
        local neighborhoodGUID = nil

        -- If user manually changed selection in last 2 seconds, respect their choice
        local recentManualSelection = self.lastManualSelectionTime and (GetTime() - self.lastManualSelectionTime) < 2

        -- Check if current selection is still valid (index within bounds and house exists)
        if selectedIndex and houseInfoList and selectedIndex >= 1 and selectedIndex <= #houseInfoList then
            neighborhoodGUID = houseInfoList[selectedIndex].neighborhoodGUID
            -- Selection still valid, keep it
        elseif recentManualSelection then
            -- User just changed selection, don't auto-select even if index seems invalid
            -- (might be a race condition with house list update)
            if debug then
                print("|cFF2aa198[VE Tracker]|r Preserving recent manual selection despite house list update")
            end
            return
        else
            -- Need to auto-select: use same priority as Blizzard
            selectedIndex = 1

            -- Priority 1: Current neighborhood (if player is physically in one)
            local currentNeighborhood = C_Housing and C_Housing.GetCurrentNeighborhoodGUID and C_Housing.GetCurrentNeighborhoodGUID()
            if currentNeighborhood and houseInfoList then
                for i, houseInfo in ipairs(houseInfoList) do
                    if houseInfo.neighborhoodGUID == currentNeighborhood then
                        neighborhoodGUID = currentNeighborhood
                        selectedIndex = i
                        break
                    end
                end
            end

            -- Priority 2: Active neighborhood (if we have a house there)
            if not neighborhoodGUID then
                local activeNeighborhood = C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()
                if activeNeighborhood and houseInfoList then
                    for i, houseInfo in ipairs(houseInfoList) do
                        if houseInfo.neighborhoodGUID == activeNeighborhood then
                            neighborhoodGUID = activeNeighborhood
                            selectedIndex = i
                            break
                        end
                    end
                end
            end

            -- Priority 3: First house in the list (fallback)
            if not neighborhoodGUID and houseInfoList and #houseInfoList > 0 then
                neighborhoodGUID = houseInfoList[1].neighborhoodGUID
                selectedIndex = 1
            end

            self.selectedHouseIndex = selectedIndex
            -- Persist new selection
            VE_DB = VE_DB or {}
            VE_DB.selectedHouseIndex = selectedIndex
        end

        -- Update house GUID and request fresh level data for the selected house
        local selectedHouseInfo = houseInfoList and houseInfoList[selectedIndex]
        if selectedHouseInfo and selectedHouseInfo.houseGUID then
            VE.Store:Dispatch("SET_HOUSE_GUID", { houseGUID = selectedHouseInfo.houseGUID })
            if C_Housing and C_Housing.GetCurrentHouseLevelFavor then
                pcall(C_Housing.GetCurrentHouseLevelFavor, selectedHouseInfo.houseGUID)
            end
        end

        -- Notify UI about house list update
        VE.EventBus:Trigger("VE_HOUSE_LIST_UPDATED", { houseList = self.houseList, selectedIndex = selectedIndex })

        -- Set viewing neighborhood and request data (must set context first like Blizzard dashboard)
        if C_NeighborhoodInitiative and neighborhoodGUID then
            C_NeighborhoodInitiative.SetViewingNeighborhood(neighborhoodGUID)
            C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
            self:RequestActivityLog()
        end

    end
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================

function Tracker:UpdateFetchStatus(state, attempt, nextRetryTime)
    local prevState = self.fetchStatus.state
    self.fetchStatus.state = state
    self.fetchStatus.attempt = attempt or self.fetchStatus.attempt
    self.fetchStatus.lastAttempt = time()
    self.fetchStatus.nextRetry = nextRetryTime
    -- Only fire event if state actually changed (prevents spam on repeated "loaded" calls)
    if prevState ~= state then
        VE.EventBus:Trigger("VE_FETCH_STATUS_CHANGED", self.fetchStatus)
    end
end

-- ============================================================================
-- HELPER FUNCTIONS (Architecture: extracted for clarity per AI guidelines)
-- ============================================================================

function Tracker:GetViewingNeighborhoodGUID()
    if self.houseList and self.selectedHouseIndex and self.houseList[self.selectedHouseIndex] then
        return self.houseList[self.selectedHouseIndex].neighborhoodGUID
    end
    return nil
end

function Tracker:IsViewingActiveNeighborhood()
    if not C_NeighborhoodInitiative then return false end
    local activeGUID = C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()
    local viewingGUID = self:GetViewingNeighborhoodGUID()
    -- If we can't determine, assume NOT active (shows Set as Active button, which is safer)
    if not activeGUID or not viewingGUID then return false end
    return activeGUID == viewingGUID
end

-- Consolidated data refresh - debounces multiple event triggers into single fetch
function Tracker:QueueDataRefresh()
    if self.pendingRefreshTimer then
        self.pendingRefreshTimer:Cancel()
    end
    self.pendingRefreshTimer = C_Timer.NewTimer(0.3, function()
        self.pendingRefreshTimer = nil
        -- FetchEndeavorData internally decides whether to request fresh data or use cache
        self:FetchEndeavorData()
        if VE.RefreshUI then
            VE:RefreshUI()
        end
    end)
end

function Tracker:ClearEndeavorData()
    self:UpdateFetchStatus("loaded", 0, nil)
    VE.Store:Dispatch("SET_ENDEAVOR_INFO", {
        seasonName = "Not Active Endeavor",
        daysRemaining = 0,
        currentProgress = 0,
        maxProgress = 0,
        milestones = {},
    })
    VE.Store:Dispatch("SET_TASKS", { tasks = {} })
    self.activityLogLoaded = false
    VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED", { timestamp = nil })
end

function Tracker:ValidateRequirements()
    if not C_NeighborhoodInitiative then return "api_unavailable" end
    if not C_NeighborhoodInitiative.IsInitiativeEnabled() then return "disabled" end
    if not C_NeighborhoodInitiative.PlayerMeetsRequiredLevel() then return "low_level" end
    if not C_NeighborhoodInitiative.PlayerHasInitiativeAccess() then return "no_access" end
    return "ok"
end

-- ============================================================================
-- DATA FETCHING (Main)
-- ============================================================================

function Tracker:FetchEndeavorData(_, attempt)
    local debug = VE.Store:GetState().config.debug
    attempt = attempt or 0 -- 0 = manual/event-triggered, 1+ = auto-retry attempts

    -- Debounce: skip entirely if fetched within last 1 second (unless retry attempt)
    local now = GetTime()
    if attempt == 0 and self.lastFetchTime and (now - self.lastFetchTime) < 1 then
        return
    end
    self.lastFetchTime = now

    -- Determine if we should request fresh data (prevents infinite loop)
    -- Skip request if we requested within last 2 seconds
    local skipRequest = self.lastRequestTime and (now - self.lastRequestTime) < 2

    -- Cancel any pending retry timer (prevents stale retries from interfering)
    if self.pendingRetryTimer then
        self.pendingRetryTimer:Cancel()
        self.pendingRetryTimer = nil
    end

    if debug then
        print("|cFF2aa198[VE Tracker]|r Fetching endeavor data..." .. (attempt > 0 and " (attempt " .. attempt .. ")" or "") .. (skipRequest and " (cached)" or " (fresh)"))
    end

    -- Update fetch status
    self:UpdateFetchStatus(attempt > 0 and "retrying" or "fetching", attempt, nil)

    -- Check if the API exists
    if not C_NeighborhoodInitiative then
        if debug then
            print("|cFFdc322f[VE Tracker]|r C_NeighborhoodInitiative API not available")
        end
        self:LoadPlaceholderData()
        return
    end

    -- Check if initiatives are enabled
    if not C_NeighborhoodInitiative.IsInitiativeEnabled() then
        if debug then
            print("|cFFdc322f[VE Tracker]|r Initiatives not enabled")
        end
        self:LoadPlaceholderData()
        return
    end

    -- Check player level requirement
    if not C_NeighborhoodInitiative.PlayerMeetsRequiredLevel() then
        local reqLevel = C_NeighborhoodInitiative.GetRequiredLevel()
        if debug then
            print("|cFFdc322f[VE Tracker]|r Player does not meet required level:", reqLevel)
        end
        self:LoadPlaceholderData()
        return
    end

    -- Check if player has initiative access
    if not C_NeighborhoodInitiative.PlayerHasInitiativeAccess() then
        if debug then
            print("|cFFdc322f[VE Tracker]|r Player does not have initiative access")
        end
        self:LoadPlaceholderData()
        return
    end

    -- Request fresh data if we haven't recently (prevents infinite loop from event chain)
    -- Don't change viewing neighborhood here - only SelectHouse should do that (respects Blizzard dashboard)
    if not skipRequest then
        self.lastRequestTime = now
        C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
    end

    -- Get the initiative info
    local initiativeInfo = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo()

    if not initiativeInfo or not initiativeInfo.isLoaded then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Initiative data not loaded yet, waiting...")
        end
        -- Retry up to 3 times at 10s intervals, then rely on 60s auto-refresh
        -- Only retry if we have house list loaded (ensures SetViewingNeighborhood was called)
        if self.houseListLoaded and attempt >= 0 and attempt < 3 then
            local nextRetry = time() + 10
            self:UpdateFetchStatus("retrying", attempt + 1, nextRetry)
            if debug then
                print("|cFF2aa198[VE Tracker]|r Scheduling retry " .. (attempt + 1) .. "/3 in 10s...")
            end
            -- Cancel any existing retry timer before creating new one
            if self.pendingRetryTimer then
                self.pendingRetryTimer:Cancel()
            end
            self.pendingRetryTimer = C_Timer.NewTimer(10, function()
                self.pendingRetryTimer = nil
                -- Just re-request data, don't change viewing neighborhood (respects Blizzard dashboard)
                C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
                self:RequestActivityLog()
            end)
        end
        return
    end

    -- Data loaded successfully
    self:UpdateFetchStatus("loaded", attempt, nil)

    -- Get the active endeavor neighborhood
    local activeGUID = C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()
    local dataGUID = initiativeInfo.neighborhoodGUID

    -- Detect if active neighborhood changed (e.g., from Blizzard's dashboard)
    if activeGUID and activeGUID ~= self.lastKnownActiveGUID then
        self.lastKnownActiveGUID = activeGUID
        VE.EventBus:Trigger("VE_ACTIVE_NEIGHBORHOOD_CHANGED")
    end

    -- Sync dropdown if Blizzard's dashboard changed the viewing neighborhood
    if dataGUID and self.houseList then
        local selectedGUID = self.selectedHouseIndex and self.houseList[self.selectedHouseIndex]
                             and self.houseList[self.selectedHouseIndex].neighborhoodGUID
        if dataGUID ~= selectedGUID then
            -- Find which house matches the data we received and sync dropdown
            for i, houseInfo in ipairs(self.houseList) do
                if houseInfo.neighborhoodGUID == dataGUID then
                    if debug then
                        print("|cFF2aa198[VE Tracker]|r Syncing dropdown to match Blizzard's selection: house " .. i)
                    end
                    self.selectedHouseIndex = i
                    VE_DB = VE_DB or {}
                    VE_DB.selectedHouseIndex = i
                    VE.EventBus:Trigger("VE_HOUSE_LIST_UPDATED", { houseList = self.houseList, selectedIndex = i })
                    break
                end
            end
        end
    end

    -- ALWAYS check: If viewing a non-active neighborhood, clear data and return
    if dataGUID and activeGUID and dataGUID ~= activeGUID then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Viewing non-active neighborhood (" .. tostring(dataGUID) .. " != " .. tostring(activeGUID) .. "), clearing data")
        end
        self:UpdateFetchStatus("loaded", 0, nil)  -- Mark as loaded so UI shows button, not "fetching"
        VE.Store:Dispatch("SET_ENDEAVOR_INFO", {
            seasonName = "Not Active Endeavor",
            daysRemaining = 0,
            currentProgress = 0,
            maxProgress = 0,
            milestones = {},
        })
        VE.Store:Dispatch("SET_TASKS", { tasks = {} })
        self.activityLogLoaded = false
        VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED", { timestamp = nil })
        return
    end

    if initiativeInfo.initiativeID == 0 then
        if debug then
            print("|cFF2aa198[VE Tracker]|r No active initiative (choosing phase)")
        end
        VE.Store:Dispatch("SET_ENDEAVOR_INFO", {
            seasonName = "No Active Endeavor",
            daysRemaining = 0,
            currentProgress = 0,
            maxProgress = 0,
            milestones = {},
        })
        VE.Store:Dispatch("SET_TASKS", { tasks = {} })
        return
    end

    -- Process initiative info
    self:ProcessInitiativeInfo(initiativeInfo)
end

-- ============================================================================
-- DATA PROCESSING
-- ============================================================================

function Tracker:ProcessInitiativeInfo(info)
    -- Calculate days remaining from duration (seconds)
    local daysRemaining = 0
    if info.duration and info.duration > 0 then
        daysRemaining = math.ceil(info.duration / 86400)  -- 86400 seconds per day
    end

    -- Process milestones
    local milestones = {}
    local maxProgress = 0
    if info.milestones then
        for _, milestone in ipairs(info.milestones) do
            local threshold = milestone.requiredContributionAmount or 0
            -- Use highest milestone threshold as max
            maxProgress = math.max(maxProgress, threshold)
            table.insert(milestones, {
                threshold = threshold,
                reached = (info.currentProgress or 0) >= threshold,
                rewards = milestone.rewards,
            })
        end
    end
    -- Fallback to progressRequired if no milestones
    if maxProgress == 0 then
        maxProgress = info.progressRequired or 100
    end

    -- Dispatch endeavor info
    VE.Store:Dispatch("SET_ENDEAVOR_INFO", {
        seasonName = info.title or "Unknown Endeavor",
        seasonEndTime = info.duration and (time() + info.duration) or 0,
        daysRemaining = daysRemaining,
        currentProgress = info.currentProgress or 0,
        maxProgress = maxProgress,
        milestones = milestones,
        description = info.description,
        initiativeID = info.initiativeID,
    })

    -- Record initiative for collection (builds database over time)
    if info.initiativeID and info.initiativeID > 0 and info.title then
        VE.Store:Dispatch("RECORD_INITIATIVE", {
            initiativeID = info.initiativeID,
            title = info.title,
            description = info.description,
        })
    end

    -- Process tasks
    local tasks = {}
    if info.tasks then
        for _, task in ipairs(info.tasks) do
            -- Skip subtasks (superseded tasks) - they're children of other tasks
            if not task.supersedes or task.supersedes == 0 then
                -- taskType: 0=Single, 1=RepeatableFinite, 2=RepeatableInfinite
                local isRepeatable = task.taskType and task.taskType > 0
                table.insert(tasks, {
                    id = task.ID,
                    name = task.taskName,
                    description = task.description or "",
                    points = task.progressContributionAmount or 0,
                    completed = task.completed or false,
                    current = self:GetTaskProgress(task),
                    max = self:GetTaskMax(task),
                    taskType = task.taskType,
                    tracked = task.tracked or false,
                    sortOrder = task.sortOrder or 999,
                    requirementsList = task.requirementsList,
                    timesCompleted = task.timesCompleted,
                    isRepeatable = isRepeatable,
                    rewardQuestID = task.rewardQuestID,
                    couponReward = self:GetTaskCouponReward(task),
                })
            end
        end

        -- Sort tasks: incomplete first, then by sortOrder
        table.sort(tasks, function(a, b)
            if a.completed ~= b.completed then
                return not a.completed
            end
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        end)
    end

    VE.Store:Dispatch("SET_TASKS", { tasks = tasks })

    -- Save character progress
    self:SaveCurrentCharacterProgress()
end

-- Extract current progress from task requirements
function Tracker:GetTaskProgress(task)
    if task.requirementsList and #task.requirementsList > 0 then
        local req = task.requirementsList[1]
        -- Try to parse "X / Y" format from requirementText
        if req.requirementText then
            local current = req.requirementText:match("(%d+)%s*/%s*%d+")
            if current then
                return tonumber(current) or 0
            end
        end
    end
    return task.completed and 1 or 0
end

-- Extract max value from task requirements
function Tracker:GetTaskMax(task)
    if task.requirementsList and #task.requirementsList > 0 then
        local req = task.requirementsList[1]
        if req.requirementText then
            local max = req.requirementText:match("%d+%s*/%s*(%d+)")
            if max then
                return tonumber(max) or 1
            end
        end
    end
    return 1
end

-- Get coupon reward amount from task's rewardQuestID
-- Formula: API returns base reward, actual reward = base - timesCompleted
function Tracker:GetTaskCouponReward(task)
    if not task.rewardQuestID or task.rewardQuestID == 0 then
        return 0
    end

    -- Use C_QuestLog to get currency rewards for the quest
    if C_QuestLog and C_QuestLog.GetQuestRewardCurrencies then
        local rewards = C_QuestLog.GetQuestRewardCurrencies(task.rewardQuestID)
        if rewards then
            for _, reward in ipairs(rewards) do
                -- Community Coupons currency
                local couponID = VE.Constants and VE.Constants.CURRENCY_IDS and VE.Constants.CURRENCY_IDS.COMMUNITY_COUPONS or 3363
                if reward.currencyID == couponID then
                    -- Return API value directly - DR is server-side, not exposed in API
                    -- This shows base reward; actual may be less for repeated completions
                    return reward.totalRewardAmount or 0
                end
            end
        end
    end

    return 0
end

-- House XP diminishing returns: Progressive DR that increases each completion
-- Formula: factor_n = 0.96 - 0.10 * n where n is completion number (2+)
-- Progression from base 50: 50 → 38 (×0.76) → 25 (×0.66) → 14 (×0.56) → 10 (floor)
-- Floor of 10 XP minimum per completion
local HOUSE_XP_MIN_FLOOR = 10

-- Known base values by task name pattern (from fresh house data)
local TASK_BASE_VALUES = {
    -- Base 50 tasks
    ["Weekly"] = 50, ["Good Neighbor"] = 50, ["Daily Quests"] = 50,
    ["Froststone"] = 50, ["War Creche"] = 50, ["Lumber"] = 50,
    -- Base 25 tasks
    ["Pet Battle"] = 25, ["Forbidden Hoard"] = 25, ["Sealed Scrolls"] = 25,
    ["Vault Doors"] = 25, ["Kill Rares"] = 25, ["Gather"] = 25, ["Creatures"] = 25,
    -- Special tasks
    ["Profession Rare"] = 150,
    -- Base 10 tasks
    ["Skyriding"] = 10, ["Delves"] = 10, ["Mythic"] = 10, ["Raids"] = 10,
    ["Honor"] = 10, ["World Quests"] = 10,
}

-- Try to find base value from task name using known patterns
local function GetTaskBaseValue(taskName)
    if not taskName then return nil end
    local name = taskName:lower()
    for pattern, base in pairs(TASK_BASE_VALUES) do
        if name:find(pattern:lower()) then
            return base
        end
    end
    return nil
end

-- Debug dump of task XP data for analysis
function Tracker:DumpTaskXPData()
    local state = VE.Store:GetState()
    if not state or not state.tasks then
        print("|cFFdc322f[VE XP Dump]|r No tasks loaded")
        return
    end
    print("|cFF2aa198[VE XP Dump]|r === Task XP Data ===")
    local totalEarned = 0
    for _, task in ipairs(state.tasks) do
        local completions = task.timesCompleted or 0
        if task.completed then completions = completions + 1 end
        local earned = self:GetTaskTotalHouseXPEarned(task)
        local base = GetTaskBaseValue(task.name) or (task.progressContributionAmount or task.points or 0)
        local repLabel = task.isRepeatable and "REP" or "ONE"
        print(string.format("  [%s] %s: base=%d, current=%d, comps=%d, earned=%d",
            repLabel,
            task.name or "?",
            base,
            task.progressContributionAmount or task.points or 0,
            completions,
            earned))
        totalEarned = totalEarned + earned
    end
    print("|cFF2aa198[VE XP Dump]|r Total earned: " .. totalEarned)
    print("|cFF2aa198[VE XP Dump]|r === End ===")
end

-- Calculate total house XP earned from task completions
-- Repeatable tasks: sum of base + progressive DR-reduced subsequent completions
-- Non-repeatable tasks: base value once only (regardless of timesCompleted)
function Tracker:GetTaskTotalHouseXPEarned(task)
    local completions = task.timesCompleted or 0
    if task.completed then
        completions = completions + 1
    end

    if completions == 0 then
        return 0
    end

    -- Get base value from known table or use current reward value
    local base = GetTaskBaseValue(task.name)
    if not base then
        base = task.progressContributionAmount or task.points or 0
    end

    -- Non-repeatable tasks: count base value once only
    if not task.isRepeatable then
        return base
    end

    -- Repeatable tasks: sum with progressive DR
    -- Formula: factor_n = 0.96 - 0.10 * n (applied to previous reward)
    -- Progression: 50 → 38 (×0.76) → 25 (×0.66) → 14 (×0.56) → 10 (floor)
    local total = base  -- First completion gets full base
    local reward = base

    for n = 2, completions do
        local factor = 0.96 - 0.10 * n  -- n=2: 0.76, n=3: 0.66, n=4: 0.56...
        factor = math.max(factor, 0.10) -- Don't go below 10% factor
        reward = math.floor(reward * factor)
        reward = math.max(reward, HOUSE_XP_MIN_FLOOR)
        total = total + reward
    end

    return math.floor(total + 0.5)
end

-- Refresh tracked tasks status
function Tracker:RefreshTrackedTasks()
    if not C_NeighborhoodInitiative then return end

    local trackedInfo = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
    if not trackedInfo or not trackedInfo.trackedIDs then return end

    local state = VE.Store:GetState()
    local tasks = state.tasks

    -- Update tracked status
    for _, task in ipairs(tasks) do
        task.tracked = tContains(trackedInfo.trackedIDs, task.id)
    end

    VE.Store:Dispatch("SET_TASKS", { tasks = tasks })
end

-- ============================================================================
-- PLACEHOLDER DATA (Fallback when API unavailable)
-- ============================================================================

function Tracker:LoadPlaceholderData()
    -- Placeholder endeavor info based on screenshot
    VE.Store:Dispatch("SET_ENDEAVOR_INFO", {
        seasonName = "Reaching Beyond the Possible",
        daysRemaining = 40,
        currentProgress = 185,
        maxProgress = 500,
        milestones = {
            { threshold = 100, reached = true },
            { threshold = 200, reached = false },
            { threshold = 350, reached = false },
            { threshold = 500, reached = false },
        },
    })

    -- Placeholder tasks based on screenshot
    -- taskType: 0=Single, 1=RepeatableFinite, 2=RepeatableInfinite
    local placeholderTasks = {
        {
            id = 1,
            name = "Home: Complete Weekly Neighborhood Quests",
            description = "Complete weekly quests in your neighborhood",
            points = 50,
            completed = false,
            current = 0,
            max = 1,
            isRepeatable = false,
        },
        {
            id = 2,
            name = "Home: Be a Good Neighbor",
            description = "Help your neighbors with various tasks",
            points = 50,
            completed = false,
            current = 0,
            max = 1,
            isRepeatable = false,
        },
        {
            id = 3,
            name = "Daily Quests",
            description = "Complete daily quests",
            points = 50,
            completed = true,
            current = 1,
            max = 1,
            isRepeatable = true,  -- Repeatable task
        },
        {
            id = 4,
            name = "Skyriding Races",
            description = "Complete skyriding races",
            points = 10,
            completed = false,
            current = 2,
            max = 5,
            isRepeatable = true,  -- Repeatable task
        },
        {
            id = 5,
            name = "Complete a Pet Battle World Quest",
            description = "Win a pet battle world quest",
            points = 25,
            completed = false,
            current = 0,
            max = 1,
            isRepeatable = true,  -- Repeatable task
        },
        {
            id = 6,
            name = "Kill Creatures",
            description = "Defeat creatures in the world",
            points = 10,
            completed = false,
            current = 47,
            max = 100,
            isRepeatable = true,  -- Repeatable task
        },
        {
            id = 7,
            name = "Kill a Profession Rare",
            description = "Defeat a rare creature related to professions",
            points = 25,
            completed = true,
            current = 1,
            max = 1,
            isRepeatable = true,  -- Repeatable task
        },
        {
            id = 8,
            name = "Kill Rares",
            description = "Defeat rare creatures",
            points = 15,
            completed = false,
            current = 3,
            max = 5,
            isRepeatable = true,  -- Repeatable task
        },
    }

    VE.Store:Dispatch("SET_TASKS", { tasks = placeholderTasks })
end

-- ============================================================================
-- CHARACTER PROGRESS
-- ============================================================================

function Tracker:SaveCurrentCharacterProgress()
    local charKey = VE:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    local _, class = UnitClass("player")

    local state = VE.Store:GetState()
    local taskProgress = {}

    -- Build progress map from current tasks
    for _, task in ipairs(state.tasks) do
        taskProgress[task.id] = {
            completed = task.completed,
            current = task.current,
            max = task.max,
        }
    end

    VE.Store:Dispatch("UPDATE_CHARACTER_PROGRESS", {
        charKey = charKey,
        name = name,
        realm = realm,
        class = class,
        tasks = taskProgress,
        endeavorInfo = {
            seasonName = state.endeavor.seasonName,
            currentProgress = state.endeavor.currentProgress,
            maxProgress = state.endeavor.maxProgress,
        },
    })
end

-- Get list of all tracked characters
function Tracker:GetTrackedCharacters()
    local state = VE.Store:GetState()
    local characters = {}
    if not state.characters then return characters end

    for charKey, charData in pairs(state.characters) do
        table.insert(characters, {
            key = charKey,
            name = charData.name,
            realm = charData.realm,
            class = charData.class,
            lastUpdated = charData.lastUpdated,
        })
    end

    -- Sort by name
    table.sort(characters, function(a, b)
        return a.name < b.name
    end)

    return characters
end

-- Get progress for a specific character
function Tracker:GetCharacterProgress(charKey)
    local state = VE.Store:GetState()
    return state.characters[charKey]
end

-- ============================================================================
-- TASK TRACKING API WRAPPERS
-- ============================================================================

function Tracker:TrackTask(taskID)
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.AddTrackedInitiativeTask then
        C_NeighborhoodInitiative.AddTrackedInitiativeTask(taskID)
    end
end

function Tracker:UntrackTask(taskID)
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
        C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(taskID)
    end
end

function Tracker:GetTaskLink(taskID)
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetInitiativeTaskChatLink then
        return C_NeighborhoodInitiative.GetInitiativeTaskChatLink(taskID)
    end
    return nil
end

-- ============================================================================
-- ACTIVITY LOG DATA
-- ============================================================================

function Tracker:GetActivityLogData()
    if not C_NeighborhoodInitiative then return nil end
    if not C_NeighborhoodInitiative.GetInitiativeActivityLogInfo then return nil end

    local logInfo = C_NeighborhoodInitiative.GetInitiativeActivityLogInfo()
    return logInfo
end

function Tracker:RequestActivityLog()
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestInitiativeActivityLog then
        C_NeighborhoodInitiative.RequestInitiativeActivityLog()
    end
end

function Tracker:IsActivityLogLoaded()
    return self.activityLogLoaded
end

-- Manual refresh - ensures correct API call order for all data
function Tracker:RefreshAll()
    local debug = VE.Store:GetState().config.debug

    -- Cancel any pending retry timer
    if self.pendingRetryTimer then
        self.pendingRetryTimer:Cancel()
        self.pendingRetryTimer = nil
    end

    -- Update status
    self:UpdateFetchStatus("fetching", 0, nil)

    if not C_NeighborhoodInitiative then
        if debug then
            print("|cFFdc322f[VE Tracker]|r RefreshAll: C_NeighborhoodInitiative not available")
        end
        return
    end

    -- Request fresh data for current viewing neighborhood (don't change viewing context - respects Blizzard dashboard)
    if debug then
        print("|cFF2aa198[VE Tracker]|r RefreshAll: Requesting data for current viewing neighborhood")
    end
    C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
    self:RequestActivityLog()
end

-- ============================================================================
-- HOUSE SELECTION
-- ============================================================================

function Tracker:SelectHouse(index)
    if not self.houseList or #self.houseList == 0 then return end
    if index < 1 or index > #self.houseList then return end

    local houseInfo = self.houseList[index]
    if not houseInfo or not houseInfo.neighborhoodGUID then return end

    -- Cancel any pending retry from previous selection
    if self.pendingRetryTimer then
        self.pendingRetryTimer:Cancel()
        self.pendingRetryTimer = nil
    end

    self.selectedHouseIndex = index
    self.lastManualSelectionTime = GetTime()  -- Track when user manually changed selection
    -- Persist selection to SavedVariables
    VE_DB = VE_DB or {}
    VE_DB.selectedHouseIndex = index
    local debug = VE.Store:GetState().config.debug

    if debug then
        print("|cFF2aa198[VE Tracker]|r Selecting house: " .. (houseInfo.houseName or "Unknown") .. " in neighborhood " .. tostring(houseInfo.neighborhoodGUID))
    end

    -- Update status to show we're fetching
    self:UpdateFetchStatus("fetching", 0, nil)

    -- Clear old data immediately when switching houses
    VE.Store:Dispatch("SET_TASKS", { tasks = {} })
    self.activityLogLoaded = false
    VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED", { timestamp = nil })

    -- Update house GUID and request fresh level data for the selected house
    if houseInfo.houseGUID then
        VE.Store:Dispatch("SET_HOUSE_GUID", { houseGUID = houseInfo.houseGUID })
        if C_Housing and C_Housing.GetCurrentHouseLevelFavor then
            pcall(C_Housing.GetCurrentHouseLevelFavor, houseInfo.houseGUID)
        end
    end

    -- Only set viewing context (not active) - user must click "Set as Active" button
    if C_NeighborhoodInitiative then
        C_NeighborhoodInitiative.SetViewingNeighborhood(houseInfo.neighborhoodGUID)
        C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
        self:RequestActivityLog()

        if debug then
            print("|cFF2aa198[VE Tracker]|r Called SetViewingNeighborhood and RequestNeighborhoodInitiativeInfo (not active yet)")
        end
    end
end

-- Set the currently selected house as the active endeavor
function Tracker:SetAsActiveEndeavor()
    if not self.selectedHouseIndex or not self.houseList then return end
    local houseInfo = self.houseList[self.selectedHouseIndex]
    if not houseInfo or not houseInfo.neighborhoodGUID then return end

    local debug = VE.Store:GetState().config.debug

    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.SetActiveNeighborhood then
        C_NeighborhoodInitiative.SetActiveNeighborhood(houseInfo.neighborhoodGUID)

        if debug then
            print("|cFF2aa198[VE Tracker]|r Set active neighborhood: " .. tostring(houseInfo.neighborhoodGUID))
        end

        -- Notify user in chat
        print("|cFF2aa198[VE]|r Active Endeavor switched to |cFFffd700" .. (houseInfo.houseName or "Unknown") .. "|r. |cFFcb4b16All task progress/XP now applies to this house.|r")

        -- Notify UI that active neighborhood changed
        VE.EventBus:Trigger("VE_ACTIVE_NEIGHBORHOOD_CHANGED")

        -- Refresh data now that it's active
        self:UpdateFetchStatus("fetching", 0, nil)
        C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
        self:RequestActivityLog()
    end
end

function Tracker:GetHouseList()
    return self.houseList or {}
end

function Tracker:GetSelectedHouseIndex()
    return self.selectedHouseIndex or 1
end
