-- ============================================================================
-- Vamoose's Endeavors - HousingTracker
-- Tracks house level, XP, and currency via C_Housing API
-- Follows SSoT pattern: all state changes go through Store
-- ============================================================================

VE = VE or {}
VE.HousingTracker = {}

local Tracker = VE.HousingTracker

-- Frame for event handling
Tracker.frame = CreateFrame("Frame")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Tracker:Initialize()
    -- Register for housing events
    self.frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    self.frame:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED")
    self.frame:RegisterEvent("HOUSE_LEVEL_CHANGED")
    self.frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)

    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE Housing]|r Initialized")
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

function Tracker:OnEvent(event, ...)
    local debug = VE.Store:GetState().config.debug

    if event == "PLAYER_HOUSE_LIST_UPDATED" then
        local houseInfoList = ...
        self:OnHouseListUpdated(houseInfoList)

    elseif event == "HOUSE_LEVEL_FAVOR_UPDATED" then
        local houseLevelFavor = ...
        self:OnHouseLevelFavorUpdated(houseLevelFavor)

    elseif event == "HOUSE_LEVEL_CHANGED" then
        if debug then
            print("|cFF2aa198[VE Housing]|r House level changed")
        end
        self:RequestHouseInfo()

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        self:UpdateCoupons()
    end
end

-- ============================================================================
-- HOUSE INFO FETCHING
-- ============================================================================

function Tracker:RequestHouseInfo()
    local debug = VE.Store:GetState().config.debug
    local state = VE.Store:GetState()

    -- If we have a cached houseGUID, request fresh level data for it
    if state.housing.houseGUID and C_Housing and C_Housing.GetCurrentHouseLevelFavor then
        if debug then
            print("|cFF2aa198[VE Housing]|r Requesting fresh level for cached houseGUID")
        end
        pcall(C_Housing.GetCurrentHouseLevelFavor, state.housing.houseGUID)
    end

    -- Always request the house list to pick best house (current neighborhood, active, or first)
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        pcall(C_Housing.GetPlayerOwnedHouses)
    end
end

function Tracker:OnHouseListUpdated(houseInfoList)
    local debug = VE.Store:GetState().config.debug
    local state = VE.Store:GetState()

    if debug then
        print("|cFF2aa198[VE Housing]|r PLAYER_HOUSE_LIST_UPDATED received, " .. (houseInfoList and #houseInfoList or 0) .. " houses")
    end

    if not houseInfoList or #houseInfoList == 0 then return end

    -- Pick best house: prefer current neighborhood, then active neighborhood, then first
    local selectedHouse = nil
    local currentNeighborhoodGUID = C_Housing and C_Housing.GetCurrentNeighborhoodGUID and C_Housing.GetCurrentNeighborhoodGUID()
    local activeNeighborhoodGUID = C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()

    -- First, check if we're in a neighborhood and have a house there
    if currentNeighborhoodGUID then
        for _, houseInfo in ipairs(houseInfoList) do
            if houseInfo.neighborhoodGUID == currentNeighborhoodGUID then
                selectedHouse = houseInfo
                break
            end
        end
    end

    -- Next, check active neighborhood
    if not selectedHouse and activeNeighborhoodGUID then
        for _, houseInfo in ipairs(houseInfoList) do
            if houseInfo.neighborhoodGUID == activeNeighborhoodGUID then
                selectedHouse = houseInfo
                break
            end
        end
    end

    -- Fall back to first house
    if not selectedHouse then
        selectedHouse = houseInfoList[1]
    end

    -- Always update and request fresh level data
    if selectedHouse and selectedHouse.houseGUID then
        VE.Store:Dispatch("SET_HOUSE_GUID", { houseGUID = selectedHouse.houseGUID })
        if C_Housing and C_Housing.GetCurrentHouseLevelFavor then
            if debug then
                print("|cFF2aa198[VE Housing]|r Requesting level for: " .. (selectedHouse.houseName or "?"))
            end
            pcall(C_Housing.GetCurrentHouseLevelFavor, selectedHouse.houseGUID)
        end
    end
end

function Tracker:OnHouseLevelFavorUpdated(houseLevelFavor)
    local debug = VE.Store:GetState().config.debug
    local state = VE.Store:GetState()

    if debug then
        print("|cFF2aa198[VE Housing]|r HOUSE_LEVEL_FAVOR_UPDATED received")
        if houseLevelFavor then
            for k, v in pairs(houseLevelFavor) do
                print(string.format("    %s: %s", k, tostring(v)))
            end
        end
    end

    -- Only process if this is for the house we're tracking
    if houseLevelFavor and state.housing.houseGUID and houseLevelFavor.houseGUID ~= state.housing.houseGUID then
        if debug then
            print("|cFF2aa198[VE Housing]|r Ignoring update for different house")
        end
        return
    end

    if not houseLevelFavor then
        VE.Store:Dispatch("SET_HOUSE_LEVEL", {
            level = 0,
            xp = 0,
            xpForNextLevel = 0,
        })
        return
    end

    local currentLevel = houseLevelFavor.houseLevel or 1
    local currentXP = houseLevelFavor.houseFavor or 0

    -- Get max level
    local maxLevel = 50
    if C_Housing and C_Housing.GetMaxHouseLevel then
        local success, max = pcall(C_Housing.GetMaxHouseLevel)
        if success and max then maxLevel = max end
    end

    -- Get XP needed for next level
    local xpForNextLevel = 0
    if currentLevel < maxLevel and C_Housing and C_Housing.GetHouseLevelFavorForLevel then
        local success, needed = pcall(C_Housing.GetHouseLevelFavorForLevel, currentLevel + 1)
        if success and needed then
            xpForNextLevel = needed
        end
    end

    VE.Store:Dispatch("SET_HOUSE_LEVEL", {
        level = currentLevel,
        xp = currentXP,
        xpForNextLevel = xpForNextLevel,
        maxLevel = maxLevel,
    })
end

-- ============================================================================
-- CURRENCY TRACKING
-- ============================================================================

function Tracker:UpdateCoupons()
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(VE.Constants.CURRENCY_IDS.COMMUNITY_COUPONS)
    if currencyInfo then
        VE.Store:Dispatch("SET_COUPONS", {
            count = currencyInfo.quantity or 0,
            iconID = currencyInfo.iconFileID,
        })
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function Tracker:GetHouseLevel()
    local state = VE.Store:GetState()
    return state.housing.level, state.housing.xp, state.housing.xpForNextLevel
end

function Tracker:GetCoupons()
    local state = VE.Store:GetState()
    return state.housing.coupons, state.housing.couponsIcon
end
