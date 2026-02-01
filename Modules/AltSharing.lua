-- ============================================================================
-- Vamoose's Endeavors - AltSharing
-- Inter-addon communication for grouping neighborhood contributions by player
-- Uses GUILD channel for reliable cross-account messaging between guildmates
-- ============================================================================

VE = VE or {}
VE.AltSharing = {}

local AltSharing = VE.AltSharing
local PREFIX = "VE_ALTS"
local PROTOCOL_VERSION = 1
local BROADCAST_INTERVAL = 300  -- 5 minutes between broadcasts
local MAX_MESSAGE_LENGTH = 255

AltSharing.frame = CreateFrame("Frame")
AltSharing.altToMainLookup = {}  -- Reverse lookup: { [charName] = "Main-Realm" }

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function AltSharing:Initialize()
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if not registered then
        if VE.Store:GetState().config.debug then
            print("|cFFdc322f[VE AltSharing]|r Failed to register addon message prefix")
        end
    end

    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)

    -- Listen for state changes to trigger broadcasts
    VE.EventBus:Register("VE_STATE_CHANGED", function(payload)
        if payload.action == "SET_ALT_SHARING_ENABLED" or
           payload.action == "SET_MAIN_CHARACTER" then
            self:OnConfigChanged()
        end
    end)

    -- Build initial lookup for local grouping
    self:BuildAltToMainLookup()

    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE AltSharing]|r Initialized (GUILD channel)")
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

function AltSharing:OnEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then
            self:OnAddonMessage(message, channel, sender)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, function()
            self:OnEnterWorld()
        end)
    end
end

function AltSharing:OnEnterWorld()
    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE AltSharing]|r OnEnterWorld called")
    end

    -- Clean up stale mappings from ended initiatives
    local currentInitiativeId = self:GetCurrentInitiativeId()
    if currentInitiativeId then
        VE.Store:Dispatch("CLEAR_STALE_MAPPINGS", { activeInitiativeId = currentInitiativeId })
    end

    -- Broadcast to guild if enabled
    self:BroadcastIfEnabled()
end

function AltSharing:OnConfigChanged()
    local state = VE.Store:GetState()
    if state.altSharing.enabled then
        -- Reset rate limit to allow immediate broadcast on config change
        VE.Store:Dispatch("SET_LAST_BROADCAST", { timestamp = 0 })
        self:BroadcastIfEnabled()
    end
end

-- ============================================================================
-- MESSAGE SENDING
-- ============================================================================

function AltSharing:BroadcastIfEnabled()
    local state = VE.Store:GetState()
    local debug = state.config.debug

    if not state.altSharing.enabled then
        if debug then print("|cFF2aa198[VE AltSharing]|r Broadcast skipped: sharing not enabled") end
        return
    end

    if not IsInGuild() then
        if debug then print("|cFF2aa198[VE AltSharing]|r Broadcast skipped: not in guild") end
        return
    end

    -- Rate limit broadcasts
    local now = time()
    if (now - state.altSharing.lastBroadcast) < BROADCAST_INTERVAL then
        if debug then print("|cFF2aa198[VE AltSharing]|r Broadcast skipped: rate limited") end
        return
    end

    local initiativeId = self:GetCurrentInitiativeId() or 0
    local mainChar = self:GetMainCharacterKey()
    local altsStr = self:BuildAltsString()

    -- Format: VERSION^INITIATIVE_ID^MAIN-REALM^ALT1-REALM,ALT2-REALM,...
    local message = string.format("%d^%d^%s^%s",
        PROTOCOL_VERSION, initiativeId, mainChar, altsStr)

    -- Truncate if too long
    if #message > MAX_MESSAGE_LENGTH then
        message = message:sub(1, MAX_MESSAGE_LENGTH)
    end

    local success = C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD")
    VE.Store:Dispatch("SET_LAST_BROADCAST", { timestamp = now })

    if debug then
        print("|cFF2aa198[VE AltSharing]|r Broadcast sent to GUILD (success=" .. tostring(success) .. ")")
        print("|cFF2aa198[VE AltSharing]|r Message:", message:sub(1, 100))
    end
end

function AltSharing:GetMainCharacterKey()
    local state = VE.Store:GetState()
    if state.altSharing.mainCharacter then
        return state.altSharing.mainCharacter
    end
    -- Use current character as pseudo-main
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
    return name .. "-" .. realm
end

function AltSharing:BuildAltsString()
    local alts = {}
    local state = VE.Store:GetState()

    -- Build set of characters with contributions > 0 from activity log
    local hasContribution = {}
    local activityData = VE.EndeavorTracker and VE.EndeavorTracker:GetActivityLogData()
    if activityData and activityData.taskActivity then
        for _, entry in ipairs(activityData.taskActivity) do
            if entry.playerName and (entry.amount or 0) > 0 then
                hasContribution[entry.playerName] = true
            end
        end
    end

    -- Only include characters that have contributed
    for _, charData in pairs(state.characters) do
        if charData.name and charData.realm and hasContribution[charData.name] then
            local realmNormalized = charData.realm:gsub("%s", "")
            table.insert(alts, charData.name .. "-" .. realmNormalized)
        end
    end

    -- Sort alphabetically for consistency
    table.sort(alts)

    return table.concat(alts, ",")
end

-- ============================================================================
-- MESSAGE RECEIVING
-- ============================================================================

function AltSharing:OnAddonMessage(message, channel, sender)
    -- Don't process our own messages
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)")
    if senderName == myName then return end

    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE AltSharing]|r Received from:", sender, "channel:", channel)
    end

    -- Parse message: VERSION^INITIATIVE_ID^MAIN-REALM^ALT1-REALM,ALT2-REALM,...
    local version, initiativeId, mainChar, altsStr = message:match("^(%d+)%^(%d+)%^([^^]+)%^(.*)$")
    if not version then return end

    version = tonumber(version)
    initiativeId = tonumber(initiativeId)

    if version > PROTOCOL_VERSION then return end -- Future version, ignore

    -- Parse alts
    local alts = {}
    if altsStr and #altsStr > 0 then
        for alt in altsStr:gmatch("[^,]+") do
            table.insert(alts, alt)
        end
    end

    -- Store mapping
    VE.Store:Dispatch("UPDATE_RECEIVED_MAPPING", {
        mainCharacter = mainChar,
        alts = alts,
        initiativeId = initiativeId,
    })

    -- Rebuild reverse lookup
    self:BuildAltToMainLookup()

    -- Notify leaderboard to update
    VE.EventBus:Trigger("VE_ALT_MAPPING_UPDATED")

    if VE.Store:GetState().config.debug then
        print("|cFF2aa198[VE AltSharing]|r Stored mapping from", mainChar, "with", #alts, "alts:")
        if #alts > 0 then
            -- Show alts in batches to avoid chat spam
            local altList = table.concat(alts, ", ")
            print("|cFF2aa198[VE AltSharing]|r   Alts:", altList:sub(1, 200))
        end
    end
end

-- ============================================================================
-- GROUPING UTILITIES
-- ============================================================================

function AltSharing:BuildAltToMainLookup()
    self.altToMainLookup = {}
    local state = VE.Store:GetState()

    -- Add received mappings (name-only keys for activity log matching)
    for mainChar, data in pairs(state.altSharing.receivedMappings) do
        local mainName = mainChar:match("^([^-]+)")
        if mainName then
            self.altToMainLookup[mainName] = mainChar
        end
        for _, altKey in ipairs(data.alts or {}) do
            local altName = altKey:match("^([^-]+)")
            if altName then
                self.altToMainLookup[altName] = mainChar
            end
        end
    end

    -- Always add our own alts for local grouping (independent of sharing)
    local ourMain = self:GetMainCharacterKey()
    local ourMainName = ourMain:match("^([^-]+)")
    if ourMainName then
        self.altToMainLookup[ourMainName] = ourMain
    end
    -- Add from VE_DB.myCharacters (all logged-in characters)
    local myChars = VE_DB and VE_DB.myCharacters or {}
    for charName, _ in pairs(myChars) do
        self.altToMainLookup[charName] = ourMain
    end
    -- Also add from state.characters (has more detail)
    for charKey, charData in pairs(state.characters) do
        if charData.name then
            self.altToMainLookup[charData.name] = ourMain
        end
    end
end

-- Resolve a character name to their main (name-only lookup for activity log)
function AltSharing:ResolveToMain(charName)
    return self.altToMainLookup[charName] or charName
end

-- Apply grouping to contribution data
-- Returns: grouped contributions table, groupedNames table (maps main -> list of char names)
function AltSharing:GroupContributions(contributions)
    local state = VE.Store:GetState()
    if state.altSharing.groupingMode ~= "byMain" then
        return contributions, nil
    end

    -- Rebuild lookup to ensure it's current
    self:BuildAltToMainLookup()

    if state.config.debug then
        local lookupCount = 0
        for _ in pairs(self.altToMainLookup) do lookupCount = lookupCount + 1 end
        print("|cFF2aa198[VE AltSharing]|r GroupContributions called, lookup has", lookupCount, "entries")
    end

    local grouped = {}
    local groupedNames = {}  -- { [displayName] = { "Char1", "Char2", ... } }

    for charName, amount in pairs(contributions) do
        local mainKey = self:ResolveToMain(charName)
        -- Use just the name part for display if it's a full key
        local displayName = mainKey:match("^([^-]+)") or mainKey
        grouped[displayName] = (grouped[displayName] or 0) + amount

        -- Track which characters are in this group
        if not groupedNames[displayName] then
            groupedNames[displayName] = {}
        end
        -- Add char if not already in list
        local found = false
        for _, name in ipairs(groupedNames[displayName]) do
            if name == charName then found = true break end
        end
        if not found then
            table.insert(groupedNames[displayName], charName)
        end
    end

    -- Sort each group's names: main first, then alts alphabetically
    for mainName, names in pairs(groupedNames) do
        table.sort(names, function(a, b)
            -- Main character comes first
            if a == mainName then return true end
            if b == mainName then return false end
            -- Otherwise alphabetical
            return a < b
        end)
    end

    if VE.Store:GetState().config.debug then
        local groupCount = 0
        for displayName, names in pairs(groupedNames) do
            groupCount = groupCount + 1
            if #names > 1 then
                print("|cFF2aa198[VE AltSharing]|r Group '" .. displayName .. "': " .. table.concat(names, ", "))
            end
        end
        print("|cFF2aa198[VE AltSharing]|r Grouped into", groupCount, "entries")
    end

    return grouped, groupedNames
end

-- ============================================================================
-- HELPERS
-- ============================================================================

function AltSharing:GetCurrentInitiativeId()
    if VE.EndeavorTracker and VE.EndeavorTracker.GetCurrentInitiativeId then
        return VE.EndeavorTracker:GetCurrentInitiativeId()
    end
    -- Fallback: try to get from API directly
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo then
        local info = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo()
        if info and info.initiativeID and info.initiativeID > 0 then
            return info.initiativeID
        end
    end
    return nil
end
