-- ============================================================================
-- Vamoose's Endeavors - Store
-- Redux-lite state management with reducers and persistence
-- ============================================================================

VE = VE or {}

-- Default state template
local DEFAULT_STATE = {
    config = {
        debug = false,
        showMinimapButton = true,
        showDashboardButton = true,
        theme = "housingtheme",  -- "dark", "light", "housingtheme", etc.
        fontFamily = "ARIALN",  -- FRIZQT__, ARIALN, skurri, MORPHEUS
        fontScale = 0,  -- -4 to +8 offset applied to all font sizes
        uiScale = 1.0,  -- 0.8 to 1.4 multiplier for entire UI
        bgOpacity = 0.9,  -- 0.3 to 1.0 background transparency
    },
    -- Current endeavor season info
    endeavor = {
        seasonName = "",           -- "Reaching Beyond the Possible"
        seasonEndTime = 0,         -- Unix timestamp when season ends
        daysRemaining = 0,
        currentProgress = 0,       -- Current endeavor progress points
        maxProgress = 0,           -- Max points for full completion
        milestones = {},           -- Array of { threshold, reached }
    },
    -- Endeavor tasks list
    tasks = {},  -- Array of { id, name, description, points, completed, current, max }
    -- Per-character progress tracking
    characters = {
        -- ["CharName-Realm"] = {
        --     name = "CharName",
        --     realm = "Realm",
        --     class = "WARRIOR",
        --     lastUpdated = timestamp,
        --     tasks = { [taskId] = { completed, current, max } }
        -- }
    },
    -- UI state
    ui = {
        selectedCharacter = nil,  -- Currently viewed character key
    },
    -- Housing state (house level, coupons)
    housing = {
        houseGUID = nil,
        level = 0,
        xp = 0,
        xpForNextLevel = 0,
        maxLevel = 50,
        coupons = 0,
        couponsIcon = nil,
    },
    -- Known initiative types (collected over time)
    knownInitiatives = {},  -- {[initiativeID] = {title, firstSeen, lastSeen}}
}

-- Deep copy helper
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

VE.Store = {
    state = DeepCopy(DEFAULT_STATE),
    reducers = {},
    saveTimer = nil,
}

function VE.Store:GetState()
    return self.state
end

function VE.Store:RegisterReducer(action, reducerFn)
    self.reducers[action] = reducerFn
end

function VE.Store:Dispatch(action, payload)
    -- Note: Store dispatch logging removed - too verbose even for debug mode

    local reducer = self.reducers[action]
    if reducer then
        local newState = reducer(self.state, payload)
        if newState then
            self.state = newState
            VE.EventBus:Trigger("VE_STATE_CHANGED", { action = action, state = self.state })
            self:QueueSave()
        end
    else
        if self.state.config.debug then
            print("|cFFdc322f[VE Store]|r No reducer found for:", action)
        end
    end
end

-- ============================================================================
-- SAVEDVARIABLES PERSISTENCE
-- ============================================================================

function VE.Store:LoadFromSavedVariables()
    if not VE_DB then
        VE_DB = {}
    end

    -- Restore config
    if VE_DB.config then
        for key, value in pairs(VE_DB.config) do
            self.state.config[key] = value
        end
    end

    -- Restore character data
    if VE_DB.characters then
        self.state.characters = VE_DB.characters
    end

    -- Restore UI state
    if VE_DB.ui then
        self.state.ui.selectedCharacter = VE_DB.ui.selectedCharacter
    end

    -- Restore known initiatives (account-wide collection)
    if VE_DB.knownInitiatives then
        self.state.knownInitiatives = VE_DB.knownInitiatives
    end

    if self.state.config.debug then
        print("|cFF2aa198[VE Store]|r Loaded state from SavedVariables")
    end
end

function VE.Store:QueueSave()
    if self.saveTimer then
        self.saveTimer:Cancel()
    end
    self.saveTimer = C_Timer.NewTimer(1, function()
        self:SaveToSavedVariables()
    end)
end

function VE.Store:SaveToSavedVariables()
    VE_DB = VE_DB or {}

    -- Save config
    VE_DB.config = {
        debug = self.state.config.debug,
        showMinimapButton = self.state.config.showMinimapButton,
        showDashboardButton = self.state.config.showDashboardButton,
        theme = self.state.config.theme,
        fontFamily = self.state.config.fontFamily,
        fontScale = self.state.config.fontScale,
        uiScale = self.state.config.uiScale,
        bgOpacity = self.state.config.bgOpacity,
    }

    -- Save character data (persistent across sessions)
    VE_DB.characters = self.state.characters

    -- Save UI state
    VE_DB.ui = {
        selectedCharacter = self.state.ui.selectedCharacter,
    }

    -- Save known initiatives (account-wide collection)
    VE_DB.knownInitiatives = self.state.knownInitiatives

    if self.state.config.debug then
        print("|cFF2aa198[VE Store]|r Saved state to SavedVariables")
    end
end

function VE.Store:Flush()
    if self.saveTimer then
        self.saveTimer:Cancel()
        self.saveTimer = nil
    end
    self:SaveToSavedVariables()
end

-- ============================================================================
-- REDUCERS
-- ============================================================================

-- SET_CONFIG: Update a config value
VE.Store:RegisterReducer("SET_CONFIG", function(state, payload)
    local newState = DeepCopy(state)
    if payload.key then
        newState.config[payload.key] = payload.value
    end
    return newState
end)

-- SET_ENDEAVOR_INFO: Update current endeavor season info
VE.Store:RegisterReducer("SET_ENDEAVOR_INFO", function(state, payload)
    local newState = DeepCopy(state)
    newState.endeavor = {
        seasonName = payload.seasonName or state.endeavor.seasonName,
        seasonEndTime = payload.seasonEndTime or state.endeavor.seasonEndTime,
        daysRemaining = payload.daysRemaining or state.endeavor.daysRemaining,
        currentProgress = payload.currentProgress or state.endeavor.currentProgress,
        maxProgress = payload.maxProgress or state.endeavor.maxProgress,
        milestones = payload.milestones or state.endeavor.milestones,
    }
    return newState
end)

-- SET_TASKS: Update the endeavor tasks list
VE.Store:RegisterReducer("SET_TASKS", function(state, payload)
    local newState = DeepCopy(state)
    newState.tasks = payload.tasks or {}
    return newState
end)

-- UPDATE_CHARACTER_PROGRESS: Save current character's task progress
VE.Store:RegisterReducer("UPDATE_CHARACTER_PROGRESS", function(state, payload)
    local newState = DeepCopy(state)
    local charKey = payload.charKey

    newState.characters[charKey] = {
        name = payload.name,
        realm = payload.realm,
        class = payload.class,
        lastUpdated = time(),
        tasks = payload.tasks or {},
    }

    return newState
end)

-- SET_SELECTED_CHARACTER: Change which character is being viewed
VE.Store:RegisterReducer("SET_SELECTED_CHARACTER", function(state, payload)
    local newState = DeepCopy(state)
    newState.ui.selectedCharacter = payload.charKey
    return newState
end)

-- ============================================================================
-- HOUSING REDUCERS
-- ============================================================================

-- SET_HOUSE_GUID: Cache the current house GUID
VE.Store:RegisterReducer("SET_HOUSE_GUID", function(state, payload)
    local newState = DeepCopy(state)
    newState.housing.houseGUID = payload.houseGUID
    return newState
end)

-- SET_HOUSE_LEVEL: Update house level and XP
VE.Store:RegisterReducer("SET_HOUSE_LEVEL", function(state, payload)
    local newState = DeepCopy(state)
    newState.housing.level = payload.level or 0
    newState.housing.xp = payload.xp or 0
    newState.housing.xpForNextLevel = payload.xpForNextLevel or 0
    newState.housing.maxLevel = payload.maxLevel or 50
    return newState
end)

-- SET_COUPONS: Update community coupons count
VE.Store:RegisterReducer("SET_COUPONS", function(state, payload)
    local newState = DeepCopy(state)
    newState.housing.coupons = payload.count or 0
    newState.housing.couponsIcon = payload.iconID
    return newState
end)

-- SET_FONT_SCALE: Update font size offset (-4 to +8)
VE.Store:RegisterReducer("SET_FONT_SCALE", function(state, payload)
    local newState = DeepCopy(state)
    newState.config.fontScale = payload.scale or 0
    return newState
end)

-- SET_UI_SCALE: Update UI scale multiplier (0.8 to 1.4)
VE.Store:RegisterReducer("SET_UI_SCALE", function(state, payload)
    local newState = DeepCopy(state)
    newState.config.uiScale = payload.scale or 1.0
    return newState
end)

-- SET_BG_OPACITY: Update background opacity (0.3 to 1.0)
VE.Store:RegisterReducer("SET_BG_OPACITY", function(state, payload)
    local newState = DeepCopy(state)
    newState.config.bgOpacity = payload.opacity or 0.9
    return newState
end)

-- RECORD_INITIATIVE: Track discovered initiative types
VE.Store:RegisterReducer("RECORD_INITIATIVE", function(state, payload)
    if not payload.initiativeID or payload.initiativeID == 0 then return state end
    local newState = DeepCopy(state)
    local id = payload.initiativeID
    local existing = state.knownInitiatives[id]
    newState.knownInitiatives[id] = {
        title = payload.title or (existing and existing.title) or "Unknown",
        firstSeen = existing and existing.firstSeen or time(),
        lastSeen = time(),
    }
    return newState
end)
