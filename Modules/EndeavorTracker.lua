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
    self.frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    -- Additional events for task progress detection
    self.frame:RegisterEvent("QUEST_LOG_UPDATE")
    self.frame:RegisterEvent("CRITERIA_UPDATE")

    -- Track activity log loading state
    self.activityLogLoaded = false

    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)

    -- Listen for state changes to save character progress
    VE.EventBus:Register("VE_STATE_CHANGED", function(payload)
        if payload.action == "SET_TASKS" or payload.action == "SET_ENDEAVOR_INFO" then
            self:SaveCurrentCharacterProgress()
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
        -- Delay initial fetch to let housing systems initialize
        C_Timer.After(2, function()
            self:FetchEndeavorData()
            -- Also request activity log so leaderboard/activity tabs have data ready
            self:RequestActivityLog()
        end)

    elseif event == "NEIGHBORHOOD_INITIATIVE_UPDATED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r NEIGHBORHOOD_INITIATIVE_UPDATED")
        end
        -- Pass true to skip requesting data again (we already have it from the event)
        self:FetchEndeavorData(true)
        -- Refresh UI to update task display
        if VE.RefreshUI then
            VE:RefreshUI()
        end

    elseif event == "INITIATIVE_TASKS_TRACKED_UPDATED" or
           event == "INITIATIVE_TASKS_TRACKED_LIST_CHANGED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Task tracking updated")
        end
        self:RefreshTrackedTasks()

    elseif event == "INITIATIVE_ACTIVITY_LOG_UPDATED" then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Activity log updated")
        end
        self.activityLogLoaded = true
        -- Notify UI to refresh activity/leaderboard tabs
        VE.EventBus:Trigger("VE_ACTIVITY_LOG_UPDATED")

    elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
        -- House list changed, might need to refresh
        if debug then
            print("|cFF2aa198[VE Tracker]|r House list updated")
        end

    elseif event == "QUEST_LOG_UPDATE" or event == "CRITERIA_UPDATE" then
        -- These events can indicate task progress changes
        -- Throttle to avoid excessive API calls (max once per 2 seconds)
        if not self.lastProgressCheck or (GetTime() - self.lastProgressCheck) > 2 then
            self.lastProgressCheck = GetTime()
            if debug then
                print("|cFF2aa198[VE Tracker]|r Progress event detected, refreshing...")
            end
            self:FetchEndeavorData()
        end
    end
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================

function Tracker:FetchEndeavorData(skipRequest)
    local debug = VE.Store:GetState().config.debug

    if debug then
        print("|cFF2aa198[VE Tracker]|r Fetching endeavor data...")
    end

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

    -- Only request fresh data if not triggered by the event (prevents infinite loop)
    if not skipRequest then
        C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo()
    end

    -- Get the initiative info
    local initiativeInfo = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo()

    if not initiativeInfo or not initiativeInfo.isLoaded then
        if debug then
            print("|cFF2aa198[VE Tracker]|r Initiative data not loaded yet, waiting...")
        end
        -- Data will come via NEIGHBORHOOD_INITIATIVE_UPDATED event
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
    local debug = VE.Store:GetState().config.debug

    if debug then
        print("|cFF2aa198[VE Tracker]|r Processing initiative:", info.title)
    end

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
                -- Currency ID 3363 is Community Coupons
                if reward.currencyID == 3363 then
                    local baseReward = reward.totalRewardAmount or 0
                    local timesCompleted = task.timesCompleted or 0
                    -- Actual reward = base - timesCompleted (minimum 1)
                    local actualReward = math.max(1, baseReward - timesCompleted)
                    return actualReward
                end
            end
        end
    end

    return 0
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
