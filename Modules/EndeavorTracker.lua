-- ============================================================================
-- Vamoose's Endeavors - EndeavorTracker
-- Fetches and tracks housing endeavor data using C_NeighborhoodInitiative API
-- API Reference: https://warcraft.wiki.gg/wiki/Category:API_systems/NeighborhoodInitiative
-- ============================================================================

VE = VE or {}
VE.EndeavorTracker = {}

local Tracker = VE.EndeavorTracker

-- ============================================================================
-- ONLY HARDCODED CONFIG VALUE
-- ============================================================================
local COMPLETIONS_TO_FLOOR = 5  -- Standard tasks reach floor at run 5

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

    -- Task XP cache (from activity log) - maps taskID -> { amount, completionTime }
    self.taskXPCache = {}

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

    -- Per-task learned decay rules (simplified decay system)
    self.taskRules = {}

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

    -- Listen for coupon gains to refresh task display with actual values
    VE.EventBus:Register("VE_COUPON_GAINED", function(payload)
        -- Always refresh to show updated values (even if correlation failed)
        C_Timer.After(0.1, function()
            VE.EndeavorTracker:FetchEndeavorData()
        end)
    end)

    -- Load previously learned formula values from SavedVariables
    self:LoadLearnedValues()

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
        -- Register current character for account-wide tracking (used by GetAccountCompletionCount)
        VE_DB = VE_DB or {}
        VE_DB.myCharacters = VE_DB.myCharacters or {}
        local charName = UnitName("player")
        if charName then VE_DB.myCharacters[charName] = true end

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
        self:BuildTaskXPCache()  -- Rebuild XP cache from activity log
        self:BuildTaskRulesFromLog()  -- Learn per-task decay rules
        VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED", { timestamp = self.activityLogLastUpdated })
        self:QueueDataRefresh()

    elseif event == "INITIATIVE_TASK_COMPLETED" then
        local taskName = ...
        if debug then
            print("|cFF2aa198[VE Tracker]|r Task completed: |cFFFFD100" .. tostring(taskName) .. "|r")
        end
        -- Look up task info from current state
        local taskID, isRepeatable = nil, false
        local state = VE.Store:GetState()
        if state and state.tasks then
            for _, task in ipairs(state.tasks) do
                if task.name == taskName then
                    taskID = task.id
                    isRepeatable = task.isRepeatable or false
                    break
                end
            end
        end
        -- Store pending task for coupon correlation (CURRENCY_DISPLAY_UPDATE fires after this)
        VE._pendingTaskCompletion = {
            taskName = taskName,
            taskID = taskID,
            isRepeatable = isRepeatable,
            timestamp = time(),
        }
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

        -- On login, always prefer active neighborhood over saved selection
        -- (user may have changed active house since last session)
        local activeNeighborhood = C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()
        local savedSelectionMatchesActive = false
        if selectedIndex and houseInfoList and selectedIndex >= 1 and selectedIndex <= #houseInfoList then
            savedSelectionMatchesActive = houseInfoList[selectedIndex].neighborhoodGUID == activeNeighborhood
        end

        -- Check if current selection is still valid AND matches active (or no active endeavor)
        if selectedIndex and houseInfoList and selectedIndex >= 1 and selectedIndex <= #houseInfoList
           and (savedSelectionMatchesActive or not activeNeighborhood or recentManualSelection) then
            neighborhoodGUID = houseInfoList[selectedIndex].neighborhoodGUID
            -- Selection still valid and matches active (or user manually selected), keep it
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
            if not neighborhoodGUID and activeNeighborhood and houseInfoList then
                for i, houseInfo in ipairs(houseInfoList) do
                    if houseInfo.neighborhoodGUID == activeNeighborhood then
                        neighborhoodGUID = activeNeighborhood
                        selectedIndex = i
                        break
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
    local hasMissingCoupons = false
    if info.tasks then
        for _, task in ipairs(info.tasks) do
            -- Skip subtasks (superseded tasks) - they're children of other tasks
            if not task.supersedes or task.supersedes == 0 then
                -- taskType: 0=Single, 1=RepeatableFinite, 2=RepeatableInfinite
                local isRepeatable = task.taskType and task.taskType > 0
                local couponReward, couponBase = self:GetTaskCouponReward(task)
                if couponReward == nil then
                    hasMissingCoupons = true
                    couponReward = 0  -- Default to 0 for display
                    couponBase = 0
                end
                table.insert(tasks, {
                    id = task.ID,
                    name = task.taskName,
                    description = task.description or "",
                    points = task.progressContributionAmount or 0,
                    progressContributionAmount = task.progressContributionAmount or 0,  -- API value (decayed)
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
                    couponReward = couponReward,  -- Actual (tracked) or base if no tracking
                    couponBase = couponBase or couponReward,  -- Base reward for tooltip
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

    -- If coupon data wasn't ready, schedule a retry
    if hasMissingCoupons and not self._couponRetryScheduled then
        self._couponRetryScheduled = true
        C_Timer.After(2, function()
            self._couponRetryScheduled = false
            VE.EndeavorTracker:FetchEndeavorData()  -- Re-process to get coupon data
        end)
    end

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
-- Returns: actual (or base if no tracking), base (for tooltip)
-- actual comes from tracked CURRENCY_DISPLAY_UPDATE data
-- base comes from quest reward API
function Tracker:GetTaskCouponReward(task)
    local taskName = task.taskName or task.name
    local base = 0

    if not task.rewardQuestID or task.rewardQuestID == 0 then
        return 0, 0
    end

    -- Get base reward from API
    if C_QuestLog and C_QuestLog.GetQuestRewardCurrencies then
        local rewards = C_QuestLog.GetQuestRewardCurrencies(task.rewardQuestID)
        if rewards then
            for _, reward in ipairs(rewards) do
                local couponID = VE.Constants and VE.Constants.CURRENCY_IDS and VE.Constants.CURRENCY_IDS.COMMUNITY_COUPONS or 3363
                if reward.currencyID == couponID then
                    base = reward.totalRewardAmount or 0
                    break
                end
            end
        else
            -- rewards is nil - API not ready yet
            return nil, nil
        end
    end

    -- Check for tracked actual reward (from CURRENCY_DISPLAY_UPDATE correlation)
    -- History is stored as array: { {amount, timestamp, character}, ... }
    -- Clear old format (single number) if found
    VE_DB = VE_DB or {}
    local history = VE_DB.taskActualCoupons and VE_DB.taskActualCoupons[taskName]
    if history and type(history) ~= "table" then
        VE_DB.taskActualCoupons[taskName] = nil  -- Clear old format
        history = nil
    end
    local actual = history and #history > 0 and history[#history].amount

    -- Return actual (or base if no tracking), and base for tooltip
    return actual or base, base
end

-- Debug dump of task XP data for analysis
function Tracker:DumpTaskXPData()
    local state = VE.Store:GetState()
    if not state or not state.tasks then
        print("|cFFdc322f[VE XP Dump]|r No tasks loaded")
        return
    end
    print("|cFF2aa198[VE XP Dump]|r === Task XP Data (from activity log) ===")
    local totalEarned = 0
    for _, task in ipairs(state.tasks) do
        local earned = self:GetTaskTotalHouseXPEarned(task)
        local repLabel = task.isRepeatable and "REP" or "ONE"
        print(string.format("  [%s] %s: apiContrib=%d, earned=%.1f",
            repLabel,
            task.name or "?",
            task.progressContributionAmount or 0,
            earned))
        totalEarned = totalEarned + earned
    end
    print("|cFF2aa198[VE XP Dump]|r Total earned: " .. string.format("%.1f", totalEarned))
    print("|cFF2aa198[VE XP Dump]|r === End ===")
end

-- Scale constants for House XP calculation
-- Blizzard changed the scale on Jan 29, 2026 (hotfix to address community feedback)
-- Scale = baseScale / rosterSize, where baseScale changed from ~1.0 to ~2.325
local SCALE_CHANGE_CUTOFF = 1769620000  -- ~Jan 28, 2026 17:00 UTC (hotfix deployed between 11:23 and 21:07 UTC)
local OLD_SCALE = 0.04   -- Pre-Jan 29 scale (historical, won't change)
local PRE_JAN29_CAP = 1000  -- Weekly cap before Jan 29 hotfix
local POST_JAN29_CAP = 2250  -- Weekly cap after Jan 29 hotfix

-- Non-repeatable tasks have fixed XP values (don't use scale calculation)
local NON_REPEATABLE_XP = {
    ["Kill a Profession Rare"] = 150,  -- 2x multiplier
    ["Home: Complete Weekly Neighborhood Quests"] = 50,
    ["Champion a Faction Envoy"] = 10,
}

-- Get scale that was active at a given time
-- Pre-cutoff: hardcoded 0.04 (historical)
-- Post-cutoff: dynamic from API via GetAbsoluteScale()
function Tracker:GetScaleAtTime(_, targetTime)
    if targetTime < SCALE_CHANGE_CUTOFF then
        return OLD_SCALE
    else
        return self:GetAbsoluteScale()  -- Live from API
    end
end

-- Calculate total house XP earned from activity log for a specific task
function Tracker:GetTaskTotalHouseXPEarned(task)
    local logInfo = self:GetActivityLogData()
    if not logInfo or not logInfo.taskActivity then return 0 end

    VE_DB = VE_DB or {}
    local myChars = VE_DB.myCharacters or {}

    local total = 0
    for _, entry in ipairs(logInfo.taskActivity) do
        if entry.taskName == task.name and myChars[entry.playerName] then
            -- Check for non-repeatable tasks with fixed XP
            local fixedXP = NON_REPEATABLE_XP[entry.taskName]
            local xp
            if fixedXP then
                xp = fixedXP
            else
                local contribution = entry.amount or 0
                local entryTime = entry.completionTime or 0
                local scale = self:GetScaleAtTime(nil, entryTime)
                xp = (scale > 0) and (contribution / scale) or 0
            end
            total = total + xp
        end
    end

    return total
end

-- Calculate TOTAL house XP earned from activity log (account-wide, all tasks)
-- Applies pre-Jan 29 cap (1000 XP) to combined pre-hotfix earnings
-- Returns: total, breakdown table {preRaw, preCapped, post, preCap, postCap}
function Tracker:GetTotalHouseXPEarned()
    local logInfo = self:GetActivityLogData()
    if not logInfo or not logInfo.taskActivity then
        return 0, { preRaw = 0, preCapped = 0, post = 0, preCap = PRE_JAN29_CAP, postCap = POST_JAN29_CAP }
    end

    VE_DB = VE_DB or {}
    local myChars = VE_DB.myCharacters or {}

    local preJan29Total = 0
    local postJan29Total = 0

    for _, entry in ipairs(logInfo.taskActivity) do
        if myChars[entry.playerName] then
            local contribution = entry.amount or 0
            local entryTime = entry.completionTime or 0

            -- Check for non-repeatable tasks with fixed XP
            local fixedXP = NON_REPEATABLE_XP[entry.taskName]
            local xp
            if fixedXP then
                xp = fixedXP
            else
                local scale = self:GetScaleAtTime(nil, entryTime)
                if scale > 0 then
                    xp = contribution / scale
                else
                    xp = 0
                end
            end

            if entryTime < SCALE_CHANGE_CUTOFF then
                preJan29Total = preJan29Total + xp
            else
                postJan29Total = postJan29Total + xp
            end
        end
    end

    -- Apply caps:
    -- Pre-Jan29: capped at 1000 (old cap, historical)
    -- Post-Jan29: cumulative total (pre + post) capped at 2250
    local cappedPreJan29 = math.min(preJan29Total, PRE_JAN29_CAP)
    local remainingCap = POST_JAN29_CAP - cappedPreJan29  -- How much more can be earned
    local cappedPostJan29 = math.min(postJan29Total, remainingCap)

    local breakdown = {
        preRaw = preJan29Total,
        preCapped = cappedPreJan29,
        post = cappedPostJan29,  -- Post earnings (cumulative shown in tooltip)
        preCap = PRE_JAN29_CAP,
        postCap = POST_JAN29_CAP,
    }

    return cappedPreJan29 + cappedPostJan29, breakdown
end

-- Clear cached scale timeline (call on house switch or relearn)
function Tracker:ClearScaleTimelineCache()
    self._scaleTimeline = nil
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

-- Build task XP cache from activity log (entry.amount = actual XP earned)
-- Also builds per-player cache for current character lookup
function Tracker:BuildTaskXPCache()
    self.taskXPCache = {}
    self.taskXPByPlayer = {}  -- taskID -> playerName -> { amount, completionTime }
    local logInfo = self:GetActivityLogData()
    if logInfo and logInfo.taskActivity then
        for _, entry in ipairs(logInfo.taskActivity) do
            local taskId = entry.taskID
            local amount = entry.amount
            local playerName = entry.playerName
            local completionTime = entry.completionTime or 0
            if taskId and amount then
                -- Global cache: most recent completion's XP value
                if not self.taskXPCache[taskId] or completionTime > (self.taskXPCache[taskId].completionTime or 0) then
                    self.taskXPCache[taskId] = {
                        amount = amount,
                        completionTime = completionTime,
                    }
                end
                -- Per-player cache: most recent completion per player
                if playerName then
                    self.taskXPByPlayer[taskId] = self.taskXPByPlayer[taskId] or {}
                    if not self.taskXPByPlayer[taskId][playerName] or completionTime > (self.taskXPByPlayer[taskId][playerName].completionTime or 0) then
                        self.taskXPByPlayer[taskId][playerName] = {
                            amount = amount,
                            completionTime = completionTime,
                        }
                    end
                end
            end
        end
    end
    return self.taskXPCache
end

-- Get actual earned XP from activity log cache (nil if never completed)
function Tracker:GetTaskXP(taskID)
    if not self.taskXPCache then
        self:BuildTaskXPCache()
    end
    local cached = self.taskXPCache[taskID]
    return cached and cached.amount or nil
end

-- Get actual earned XP for current player only (nil if current char hasn't completed)
function Tracker:GetTaskXPForCurrentPlayer(taskID)
    if not self.taskXPByPlayer then
        self:BuildTaskXPCache()
    end
    local playerName = UnitName("player")
    local taskData = self.taskXPByPlayer[taskID]
    if taskData and taskData[playerName] then
        return taskData[playerName].amount
    end
    return nil
end

-- Count completions for current player from activity log
function Tracker:GetPlayerCompletionCount(taskID)
    local logInfo = self:GetActivityLogData()
    if not logInfo or not logInfo.taskActivity then return 0 end
    local playerName = UnitName("player")
    local count = 0
    for _, entry in ipairs(logInfo.taskActivity) do
        if entry.taskID == taskID and entry.playerName == playerName then
            count = count + 1
        end
    end
    return count
end

-- Count completions across ALL of the user's characters (account-wide)
-- DR is account-based, so we sum completions from all alts in VE_DB.myCharacters
function Tracker:GetAccountCompletionCount(taskID)
    local logInfo = self:GetActivityLogData()
    if not logInfo or not logInfo.taskActivity then return 0 end

    -- Get list of user's characters (populated on login from Leaderboard/Activity tabs)
    VE_DB = VE_DB or {}
    local myChars = VE_DB.myCharacters or {}

    local count = 0
    for _, entry in ipairs(logInfo.taskActivity) do
        if entry.taskID == taskID and myChars[entry.playerName] then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- SELF-LEARNING XP FORMULA SYSTEM
-- Learns scale from observed floor task data (most accurate method)
-- Rebuilds fresh from activity log each session (no persistence needed)
-- ============================================================================

-- Count roster size from activity log
function Tracker:GetRosterSize()
    local logInfo = self:GetActivityLogData()
    local rosterSize = 0
    if logInfo and logInfo.taskActivity then
        local chars = {}
        for _, entry in ipairs(logInfo.taskActivity) do
            if entry.playerName then
                chars[entry.playerName] = true
            end
        end
        for _ in pairs(chars) do rosterSize = rosterSize + 1 end
    end
    return rosterSize
end

-- Reset learned task rules (triggers re-learning from activity log)
function Tracker:ResetTaskRules()
    self.taskRules = {}
    -- Clean up legacy SavedVariables data
    if VE_DB then
        VE_DB.taskRules = nil
        VE_DB.learnedFormula = nil
        VE_DB.formulaCheckpoint = nil
    end
end

-- Load learned values on init
function Tracker:LoadLearnedValues()
    -- taskRules rebuilt from activity log on INITIATIVE_ACTIVITY_LOG_UPDATED - no persistence needed
    self.taskRules = {}
    -- Clean up legacy SavedVariables data
    if VE_DB then
        VE_DB.learnedFormula = nil
        VE_DB.taskRules = nil
        VE_DB.formulaCheckpoint = nil
    end
end

-- Save/Load per-task rules removed - rebuilt fresh from activity log each time

-- ============================================================================
-- PER-TASK DECAY LEARNING (Simplified System)
-- Each task learns its own decay rate and floor from observed completions
-- ============================================================================

-- Build task rules from activity log
-- Simplified approach: for floor tasks (timesCompleted >= 5), use most recent entry as floor XP
function Tracker:BuildTaskRulesFromLog()
    local logInfo = self:GetActivityLogData()
    if not logInfo or not logInfo.taskActivity then return end

    local debug = VE.Store:GetState().config.debug
    if debug then
        print("|cFF2aa198[VE TaskRules]|r Building rules from activity log...")
    end

    -- Start fresh
    self.taskRules = {}

    -- Group by taskName, keeping only the most recent entry
    local recentByTask = {}
    for _, entry in ipairs(logInfo.taskActivity) do
        local task = entry.taskName
        local amount = entry.amount
        local completionTime = entry.completionTime or 0
        if task and amount and amount > 0 then
            if not recentByTask[task] or completionTime > recentByTask[task].time then
                recentByTask[task] = { amount = amount, time = completionTime }
            end
        end
    end

    -- For floor tasks (per API), use most recent entry as floor XP
    local tasks = VE.Store:GetState().tasks or {}
    local floorCount = 0
    for _, task in ipairs(tasks) do
        if (task.timesCompleted or 0) >= COMPLETIONS_TO_FLOOR then
            local recent = recentByTask[task.name]
            if recent then
                self.taskRules[task.name] = {
                    atFloor = true,
                    floorXP = recent.amount,
                    floorXPTime = recent.time,
                }
                floorCount = floorCount + 1
                if debug then
                    print(string.format("  %s: floorXP=%.3f", task.name, recent.amount))
                end
            end
        end
    end

    if debug then
        print("|cFF2aa198[VE TaskRules]|r Learned floor XP for " .. floorCount .. " tasks")
    end
end

-- Show per-task learned rules (/ve rules command)
function Tracker:ShowTaskRules(filterTask)
    print("|cFF2aa198[VE TaskRules]|r === Per-Task Rules ===")

    local scale = self:GetAbsoluteScale()
    local rosterSize = self:GetRosterSize()
    print(string.format("  Scale: |cFF268bd2%.5f|r | Roster: %d chars", scale, rosterSize))

    if not self.taskRules or not next(self.taskRules) then
        print("  No rules learned yet. Complete some tasks to learn rules.")
        return
    end

    local count = 0
    for taskName, rules in pairs(self.taskRules) do
        if not filterTask or taskName:lower():find(filterTask:lower()) then
            count = count + 1
            local pattern = rules.pattern and string.format(" |cFF6c71c4[%s]|r", rules.pattern) or ""

            -- Get calculated values from API
            local task = self:GetTaskByName(taskName)
            local currentContrib = task and task.progressContributionAmount or 0
            local timesCompleted = task and task.timesCompleted or 0
            -- Determine floor status from API, not historical activity log
            local isAtFloor = timesCompleted >= COMPLETIONS_TO_FLOOR
            local status = isAtFloor and "|cFF859900(at floor)|r" or "|cFFcb4b16(decaying)|r"
            local baseContrib = self:GetBaseTaskContribution(taskName)
            local calcFloorXP = self:CalculateFloorXP(taskName)
            local nextXP = self:CalculateNextContribution(taskName)

            print(string.format("  |cFFb58900%s|r%s %s", taskName, pattern, status))
            print(string.format("    API: current=|cFF93a1a1%d|r timesCompleted=|cFF93a1a1%d|r",
                currentContrib, timesCompleted))
            print(string.format("    Calc: base=|cFF859900%d|r floorXP=|cFF859900%.3f|r nextXP=|cFF859900%.3f|r",
                baseContrib, calcFloorXP, nextXP))
            if rules.floorXP and rules.floorXP > 0 then
                print(string.format("    Observed: floorXP=|cFF268bd2%.3f|r", rules.floorXP))
            end
        end
    end

    if count == 0 then
        print("  No matching tasks found for filter: " .. (filterTask or ""))
    else
        print(string.format("|cFF2aa198[VE TaskRules]|r %d task(s) shown", count))
    end
end

-- Refresh learned values (call on activity log update)
function Tracker:RefreshLearnedValues()
    self:BuildTaskRulesFromLog()
    -- Clear cached scale so it re-derives from fresh floor data
    self.cachedAbsoluteScale = nil
end

-- Derive scale from floor task observations
-- Formula: scale = floorXP / progressContributionAmount
-- Both values are at floor decay level, so they align perfectly
function Tracker:GetAbsoluteScale()
    if self.cachedAbsoluteScale then
        return self.cachedAbsoluteScale
    end

    local tasks = VE.Store:GetState().tasks or {}

    -- Find any floor task with observed floorXP
    for _, task in ipairs(tasks) do
        if (task.timesCompleted or 0) >= COMPLETIONS_TO_FLOOR then
            local rules = self.taskRules and self.taskRules[task.name]
            if rules and rules.floorXP and rules.floorXP > 0 then
                local apiContrib = task.progressContributionAmount or 0
                if apiContrib > 0 then
                    self.cachedAbsoluteScale = rules.floorXP / apiContrib
                    return self.cachedAbsoluteScale
                end
            end
        end
    end

    -- Cold start fallback: tier 1 baseline (~0.04), will self-correct once floor data exists
    return 0.04
end


-- Debug command: show learned values (/ve validate)
function Tracker:ValidateFormulaConfig()
    print("|cFF2aa198[VE Validate]|r === XP Formula ===")

    -- Scale derived from floor tasks
    local scale = self:GetAbsoluteScale()
    local isLearned = self.cachedAbsoluteScale ~= nil
    local source = isLearned and "|cFF859900(from floor task)|r" or "|cFFcb4b16(fallback)|r"
    print(string.format("  Scale: |cFF268bd2%.5f|r %s", scale, source))

    -- Per-task rules summary
    local ruleCount = 0
    local atFloorCount = 0
    if self.taskRules then
        for _, rules in pairs(self.taskRules) do
            ruleCount = ruleCount + 1
            if rules.atFloor then atFloorCount = atFloorCount + 1 end
        end
    end
    print(string.format("  Tasks: %d learned, %d at floor", ruleCount, atFloorCount))

    -- Formula explanation
    print("  Formula: nextXP = progressContrib × scale")
    print("  Use '/ve rules' for per-task details")

    print("|cFF2aa198[VE Validate]|r === End ===")
end

-- Debug: Show current scale factor and derivation (/ve scale)
function Tracker:ShowScaleDebug()
    print("|cFF2aa198[VE Scale]|r === Scale Debug ===")

    -- Get roster size
    local rosterSize = self:GetRosterSize()
    print(string.format("  Roster size: |cFF268bd2%d|r characters", rosterSize))

    -- Check if we have a cached scale
    local hadCached = self.cachedAbsoluteScale ~= nil
    local scale = self:GetAbsoluteScale()
    local source = hadCached and "(cached)" or (self.cachedAbsoluteScale and "(derived from floor task)" or "(fallback)")
    print(string.format("  Scale factor: |cFF268bd2%.6f|r %s", scale, source))

    -- Find which floor task we derived scale from (exclude zero-floor tasks)
    local tasks = VE.Store:GetState().tasks or {}
    local floorTasks = {}
    for _, task in ipairs(tasks) do
        if (task.timesCompleted or 0) >= COMPLETIONS_TO_FLOOR then
            local rules = self.taskRules and self.taskRules[task.name]
            local apiContrib = task.progressContributionAmount or 0
            if rules and rules.floorXP and rules.floorXP > 0 and apiContrib > 0 then
                table.insert(floorTasks, {
                    name = task.name,
                    floorXP = rules.floorXP,
                    apiContrib = apiContrib,
                    derivedScale = rules.floorXP / apiContrib
                })
            end
        end
    end

    if #floorTasks > 0 then
        print("  |cFF859900Floor tasks used for scale derivation:|r")
        for _, ft in ipairs(floorTasks) do
            print(string.format("    %s: floorXP=%.2f / apiContrib=%d = %.6f",
                ft.name, ft.floorXP, ft.apiContrib, ft.derivedScale))
        end
    else
        print("  |cFFcb4b16No floor tasks available - using fallback scale|r")
    end

    print("|cFF2aa198[VE Scale]|r === End ===")
end

-- Debug: Dump all fields from activity log entries (/ve dumplog)
function Tracker:DumpActivityLogFields()
    local logInfo = self:GetActivityLogData()
    if not logInfo then
        print("|cFF2aa198[VE DumpLog]|r No activity log data available")
        return
    end

    print("|cFF2aa198[VE DumpLog]|r === Activity Log Structure ===")

    -- Dump top-level logInfo fields
    print("  |cFF268bd2Top-level logInfo fields:|r")
    for key, value in pairs(logInfo) do
        local valType = type(value)
        if valType == "table" then
            print(string.format("    %s = [table with %d entries]", key, #value > 0 and #value or 0))
        else
            print(string.format("    %s = %s (%s)", key, tostring(value), valType))
        end
    end

    -- Dump first entry's fields
    if logInfo.taskActivity and #logInfo.taskActivity > 0 then
        local entry = logInfo.taskActivity[1]
        print("  |cFF268bd2Entry fields (from first entry):|r")
        local fields = {}
        for key in pairs(entry) do
            table.insert(fields, key)
        end
        table.sort(fields)
        for _, key in ipairs(fields) do
            local value = entry[key]
            local valType = type(value)
            if valType == "table" then
                print(string.format("    %s = [table]", key))
            else
                print(string.format("    %s = %s (%s)", key, tostring(value), valType))
            end
        end
        print(string.format("  |cFF859900Total entries: %d|r", #logInfo.taskActivity))
    else
        print("  No taskActivity entries found")
    end

    print("|cFF2aa198[VE DumpLog]|r === End ===")
end

-- Look up task object from current initiative by name
function Tracker:GetTaskByName(taskName)
    if not taskName then return nil end
    local state = VE.Store:GetState()
    if state and state.tasks then
        for _, task in ipairs(state.tasks) do
            if task.name == taskName then
                return task
            end
        end
    end
    return nil
end

-- Get current contribution (decayed value from API progressContributionAmount)
-- This is what you'd earn on NEXT completion, pre-scale
function Tracker:GetCurrentContribution(task)
    if type(task) == "string" then
        task = self:GetTaskByName(task)
    end
    if not task then return 0 end
    return task.progressContributionAmount or 0
end

-- Get times completed for a task
function Tracker:GetTimesCompleted(task)
    if type(task) == "string" then
        task = self:GetTaskByName(task)
    end
    if not task then return 0 end
    return task.timesCompleted or 0
end

-- Calculate BaseTaskContribution by working backwards from current decayed value
-- BaseTaskContribution = progressContributionAmount / currentDecayMultiplier
function Tracker:GetBaseTaskContribution(task)
    if type(task) == "string" then
        task = self:GetTaskByName(task)
    end
    if not task then return 0 end

    local currentContribution = task.progressContributionAmount or 0
    if currentContribution == 0 then return 0 end

    local timesCompleted = task.timesCompleted or 0
    local nextRun = math.min(timesCompleted + 1, COMPLETIONS_TO_FLOOR)
    local currentDecay = self:GetDecayMultiplier(nextRun)

    return currentContribution / currentDecay
end

-- LEGACY: GetTaskInfo returns currentContribution as 'base' for backwards compatibility
-- TODO: Update callers to use GetCurrentContribution directly
function Tracker:GetTaskInfo(task)
    local currentContribution = self:GetCurrentContribution(task)
    return { base = currentContribution }
end

-- ============================================================================
-- CONTRIBUTION-BASED FORMULA (for Best Next Endeavor ranking)
-- Uses COMPLETIONS_TO_FLOOR as only hardcoded config value
-- ============================================================================

-- Calculate decay multiplier using formula derived from COMPLETIONS_TO_FLOOR
-- @param run: Which run this is (1 = first, 2 = second, etc.)
-- @return multiplier (0.0 to 1.0)
function Tracker:GetDecayMultiplier(run)
    if run < 1 then run = 1 end
    local floorPct = 1 / COMPLETIONS_TO_FLOOR  -- 0.20 for standard
    local decayRate = (1 - floorPct) / (COMPLETIONS_TO_FLOOR - 1)  -- 0.20 for standard
    return math.max(floorPct, 1 - decayRate * (run - 1))
end

-- Calculate next contribution using absolute scale (for rankings/tooltips)
-- Formula: NextContribution = progressContributionAmount × AbsoluteScale
-- progressContributionAmount is ALREADY DECAYED (changes with completions: 25→20→etc)
function Tracker:CalculateNextContribution(taskName, _completions)
    local task = self:GetTaskByName(taskName)
    if not task then return 0 end

    local timesCompleted = task.timesCompleted or 0
    local isAtFloor = timesCompleted >= COMPLETIONS_TO_FLOOR

    -- At floor: use observed floor XP directly (already has scale baked in)
    if isAtFloor then
        local rules = self.taskRules and self.taskRules[taskName]
        if rules and rules.floorXP and rules.floorXP > 0 then
            return rules.floorXP
        end
    end

    -- progressContributionAmount already has decay - just apply scale
    local apiContrib = task.progressContributionAmount or 0
    local absoluteScale = self:GetAbsoluteScale()
    return apiContrib * absoluteScale
end

-- Calculate floor XP for a task (what you'd earn at floor)
function Tracker:CalculateFloorXP(taskName)
    -- If we have observed floor XP, use it directly (from activity log)
    local rules = self.taskRules and self.taskRules[taskName]
    if rules and rules.floorXP and rules.floorXP > 0 then
        return rules.floorXP
    end

    -- No observed floor XP - can't calculate without reference point
    return 0
end

-- Calculate first run XP for a task (what you'd earn on first completion)
function Tracker:CalculateFirstRunXP(taskName)
    -- Derive from observed floor: firstRun = floor / floorPct = floor * 5
    local floorXP = self:CalculateFloorXP(taskName)
    if floorXP > 0 then
        return floorXP * COMPLETIONS_TO_FLOOR  -- floorXP / 0.20 = floorXP * 5
    end

    -- No observed data - can't calculate
    return 0
end

-- Get task rankings by next contribution value for current player
-- Returns: { [taskID] = { rank=1-3, nextXP=amount } } for top 3 only
function Tracker:GetTaskRankings()
    local tasks = VE.Store:GetState().tasks or {}
    local rankings = {}

    -- Build list of { taskID, nextXP, taskName } for incomplete repeatable tasks
    local taskList = {}
    for _, task in ipairs(tasks) do
        if task.isRepeatable and task.id and not task.completed then
            -- Use ACCOUNT-WIDE completions since DR is account-based
            local completions = self:GetAccountCompletionCount(task.id)
            -- Use contribution formula (with roster scale) for ranking
            local nextXP = self:CalculateNextContribution(task.name, completions)
            if nextXP > 0 then
                table.insert(taskList, {
                    id = task.id,
                    nextXP = nextXP,
                    name = task.name,
                    completions = completions,
                })
            end
        end
    end

    -- Sort by nextXP descending
    table.sort(taskList, function(a, b) return a.nextXP > b.nextXP end)

    -- Assign ranks with tie handling (tasks with same XP share rank)
    local currentRank = 0
    local lastXP = nil
    for _, task in ipairs(taskList) do
        -- New rank only if XP is different (using small epsilon for float comparison)
        if not lastXP or math.abs(task.nextXP - lastXP) > 0.0001 then
            currentRank = currentRank + 1
            lastXP = task.nextXP
        end
        -- Only include ranks 1-3 (gold/silver/bronze)
        if currentRank <= 3 then
            rankings[task.id] = {
                rank = currentRank,
                nextXP = task.nextXP,
                completions = task.completions,
            }
        else
            break  -- Stop once we've passed bronze
        end
    end

    return rankings
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
    self.cachedAbsoluteScale = nil  -- Clear scale cache - each house has different roster size
    self.taskRules = {}             -- Clear task rules - will rebuild from new house's activity log
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
