-- ============================================================================
-- Vamoose's Endeavors - MainFrame
-- Main window creation and management with tab switching
-- ============================================================================

VE = VE or {}

-- ============================================================================
-- WINDOW POSITION PERSISTENCE
-- ============================================================================

local function SaveWindowPosition(frame)
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    VE_DB = VE_DB or {}
    VE_DB.windowPos = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
    }
end

local function RestoreWindowPosition(frame)
    if not frame then return end
    if VE_DB and VE_DB.windowPos then
        local pos = VE_DB.windowPos
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
end

-- ============================================================================
-- MAIN WINDOW CREATION
-- ============================================================================

function VE:CreateMainWindow()
    if self.MainFrame then return self.MainFrame end

    local version = C_AddOns.GetAddOnMetadata("VamoosesEndeavors", "Version") or "Dev"
    local frame = VE.UI:CreateMainFrame("VE_MainFrame", "Vamoose's Endeavors v" .. version)
    frame:Hide()

    -- Restore saved position
    RestoreWindowPosition(frame)

    -- Apply saved UI scale
    local uiScale = VE.Store:GetState().config.uiScale or 1.0
    frame:SetScale(uiScale)

    -- Save position on drag stop
    frame:HookScript("OnDragStop", function(self)
        SaveWindowPosition(self)
    end)

    -- ========================================================================
    -- TAB BAR
    -- ========================================================================

    local tabBar = CreateFrame("Frame", nil, frame)
    local uiConsts = VE.Constants.UI or {}
    tabBar:SetHeight(uiConsts.tabHeight or 24)
    tabBar:SetPoint("TOPLEFT", 0, -16)
    tabBar:SetPoint("TOPRIGHT", 0, -16)
    frame.tabBar = tabBar

    -- Create tab buttons (via factory method with Theme Engine registration)
    -- Calculate equal tab width: (window width - 2 * padding) / num tabs
    local PADDING = 4
    local NUM_TABS = 4
    local tabWidth = math.floor((uiConsts.mainWidth - (2 * PADDING)) / NUM_TABS)

    local endeavorsTabBtn = VE.UI:CreateTabButton(tabBar, "Endeavors")
    endeavorsTabBtn:SetSize(tabWidth, uiConsts.tabHeight or 24)
    endeavorsTabBtn:SetPoint("LEFT", PADDING, 0)

    local leaderboardTabBtn = VE.UI:CreateTabButton(tabBar, "Rankings")
    leaderboardTabBtn:SetSize(tabWidth, uiConsts.tabHeight or 24)
    leaderboardTabBtn:SetPoint("LEFT", endeavorsTabBtn, "RIGHT", 0, 0)

    local activityTabBtn = VE.UI:CreateTabButton(tabBar, "Activity")
    activityTabBtn:SetSize(tabWidth, uiConsts.tabHeight or 24)
    activityTabBtn:SetPoint("LEFT", leaderboardTabBtn, "RIGHT", 0, 0)

    local configTabBtn = VE.UI:CreateTabButton(tabBar, "Config")
    configTabBtn:SetSize(tabWidth, uiConsts.tabHeight or 24)
    configTabBtn:SetPoint("LEFT", activityTabBtn, "RIGHT", 0, 0)

    frame.endeavorsTabBtn = endeavorsTabBtn
    frame.leaderboardTabBtn = leaderboardTabBtn
    frame.activityTabBtn = activityTabBtn
    frame.configTabBtn = configTabBtn

    -- Update housing display (coupons + house level) from Store
    function frame:UpdateHousingDisplay()
        local state = VE.Store:GetState()
        local housing = state.housing
        local C = VE.Constants:GetThemeColors()

        -- Update coupons
        if housing.coupons and housing.coupons > 0 then
            if housing.couponsIcon then
                self.couponsIcon:SetTexture(housing.couponsIcon)
            end
            self.couponsText:SetText(housing.coupons)
            self.couponsIcon:Show()
            self.couponsText:Show()
        else
            -- Fallback to direct API call if Store not populated yet
            local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(VE.Constants.CURRENCY_IDS.COMMUNITY_COUPONS)
            if currencyInfo and currencyInfo.quantity then
                self.couponsIcon:SetTexture(currencyInfo.iconFileID)
                self.couponsText:SetText(currencyInfo.quantity)
                self.couponsIcon:Show()
                self.couponsText:Show()
            else
                self.couponsIcon:Hide()
                self.couponsText:Hide()
            end
        end

        -- Update house level
        local level = housing.level or 0
        local xp = housing.xp or 0
        local xpForNextLevel = housing.xpForNextLevel or 0
        local maxLevel = housing.maxLevel or 50

        if level > 0 then
            -- Generate hex from RGB for current theme colors
            local accentHex = string.format("%02x%02x%02x", math.floor(C.accent.r * 255), math.floor(C.accent.g * 255), math.floor(C.accent.b * 255))
            local dimHex = string.format("%02x%02x%02x", math.floor(C.text_dim.r * 255), math.floor(C.text_dim.g * 255), math.floor(C.text_dim.b * 255))
            if level >= maxLevel then
                self.houseLevelText:SetText(string.format("|cFF%sHouse|r |cFF%sLv %d|r |cFF%s(Max)|r", dimHex, accentHex, level, dimHex))
            else
                self.houseLevelText:SetText(string.format("|cFF%sHouse|r |cFF%sLv %d|r |cFF%s%d/%d XP|r", dimHex, accentHex, level, dimHex, xp, xpForNextLevel))
            end
        else
            self.houseLevelText:SetText("")
        end
    end

    -- Legacy alias for UpdateCoupons
    frame.UpdateCoupons = frame.UpdateHousingDisplay

    -- ========================================================================
    -- PERSISTENT HEADER (always visible, even when minimized)
    -- ========================================================================

    local UI = VE.Constants.UI
    local C = VE.Constants.Colors
    local padding = UI.panelPadding

    local headerSection = CreateFrame("Frame", nil, frame)
    headerSection:SetHeight(54)
    headerSection:SetPoint("TOPLEFT", padding, -38)
    headerSection:SetPoint("TOPRIGHT", -padding, -38)
    frame.headerSection = headerSection

    -- Season name (top left)
    local seasonName = headerSection:CreateFontString(nil, "OVERLAY")
    seasonName:SetPoint("TOPLEFT", 0, -2)
    VE.Theme.ApplyFont(seasonName, C)
    seasonName:SetTextColor(C.text.r, C.text.g, C.text.b)
    seasonName._colorType = "text"
    VE.Theme:Register(seasonName, "HeaderText")
    frame.seasonName = seasonName

    -- Days remaining (top right)
    local daysRemaining = headerSection:CreateFontString(nil, "OVERLAY")
    daysRemaining:SetPoint("TOPRIGHT", 0, -2)
    VE.Theme.ApplyFont(daysRemaining, C, "small")
    daysRemaining:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    daysRemaining._colorType = "text_dim"
    VE.Theme:Register(daysRemaining, "HeaderText")
    frame.daysRemaining = daysRemaining

    -- Progress bar (full width, below season name)
    local progressBar = VE.UI:CreateProgressBar(headerSection, {
        width = 100,
        height = UI.progressBarHeight,
    })
    progressBar:SetPoint("TOPLEFT", seasonName, "BOTTOMLEFT", 0, -4)
    progressBar:SetPoint("TOPRIGHT", 0, 0)
    frame.progressBar = progressBar

    -- Stats row below progress bar (coupons + house level)
    local statsRow = CreateFrame("Frame", nil, headerSection)
    statsRow:SetHeight(16)
    statsRow:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -4)
    statsRow:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -4)

    -- Coupons icon (left side)
    local couponsIcon = statsRow:CreateTexture(nil, "ARTWORK")
    couponsIcon:SetSize(14, 14)
    couponsIcon:SetPoint("LEFT", 0, 0)
    frame.couponsIcon = couponsIcon

    -- Coupons count
    local couponsText = statsRow:CreateFontString(nil, "OVERLAY")
    couponsText:SetPoint("LEFT", couponsIcon, "RIGHT", 4, 0)
    VE.Theme.ApplyFont(couponsText, C, "small")
    couponsText:SetTextColor(C.warning.r, C.warning.g, C.warning.b)
    couponsText._colorType = "warning"
    VE.Theme:Register(couponsText, "HeaderText")
    frame.couponsText = couponsText

    -- Character contribution label (after coupons)
    local xpLabel = statsRow:CreateFontString(nil, "OVERLAY")
    xpLabel:SetPoint("LEFT", couponsText, "RIGHT", 16, 0)
    VE.Theme.ApplyFont(xpLabel, C, "small")
    xpLabel:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    xpLabel:SetText("Contribution:")
    xpLabel._colorType = "text_dim"
    VE.Theme:Register(xpLabel, "HeaderText")
    frame.xpLabel = xpLabel

    -- XP earned value
    local xpValue = statsRow:CreateFontString(nil, "OVERLAY")
    xpValue:SetPoint("LEFT", xpLabel, "RIGHT", 4, 0)
    VE.Theme.ApplyFont(xpValue, C, "small")
    xpValue:SetTextColor(C.endeavor.r, C.endeavor.g, C.endeavor.b)
    xpValue._colorType = "endeavor"
    VE.Theme:Register(xpValue, "HeaderText")
    frame.xpValue = xpValue

    -- House Level display (right side of stats row)
    -- Note: houseLevelText uses inline color codes, so we don't register it with HeaderText
    -- Its colors are updated in UpdateHousingDisplay() using current theme colors
    local houseLevelText = statsRow:CreateFontString(nil, "OVERLAY")
    houseLevelText:SetPoint("RIGHT", 0, 0)
    VE.Theme.ApplyFont(houseLevelText, C, "small")
    houseLevelText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    houseLevelText:SetText("")
    frame.houseLevelText = houseLevelText

    -- Request fresh data on show
    frame:HookScript("OnShow", function()
        -- Request housing data via HousingTracker module
        if VE.HousingTracker then
            VE.HousingTracker:RequestHouseInfo()
            VE.HousingTracker:UpdateCoupons()
        end
        -- Request endeavor data for immediate refresh
        if VE.EndeavorTracker then
            VE.EndeavorTracker:FetchEndeavorData()
        end
    end)

    -- Update header function
    function frame:UpdateHeader()
        local state = VE.Store:GetState()

        self.seasonName:SetText(state.endeavor.seasonName or "Housing Endeavors")

        if state.endeavor.daysRemaining and state.endeavor.daysRemaining > 0 then
            self.daysRemaining:SetText(state.endeavor.daysRemaining .. " Days Remaining")
        else
            self.daysRemaining:SetText("")
        end

        self.progressBar:SetProgress(
            state.endeavor.currentProgress or 0,
            state.endeavor.maxProgress or 100
        )
        self.progressBar:SetMilestones(
            state.endeavor.milestones,
            state.endeavor.maxProgress or 100
        )

        -- Update contribution display (from activity log for current player)
        local playerContribution = 0
        local activityData = VE.EndeavorTracker:GetActivityLogData()
        local debug = VE.Store:GetState().config.debug
        if activityData and activityData.taskActivity then
            local currentPlayer = UnitName("player")
            local entryCount = 0
            for _, entry in ipairs(activityData.taskActivity) do
                if entry.playerName == currentPlayer then
                    playerContribution = playerContribution + (entry.amount or 0)
                    entryCount = entryCount + 1
                    if debug then
                        print(string.format("|cFF2aa198[VE Contrib]|r %s: +%.1f (%s)",
                            entry.taskName or "?", entry.amount or 0, entry.playerName or "?"))
                    end
                end
            end
            if debug and entryCount > 0 then
                print(string.format("|cFF2aa198[VE Contrib]|r Total: %.1f from %d entries", playerContribution, entryCount))
            end
        end
        self.xpValue:SetText(string.format("%.1f", playerContribution))
    end

    -- ========================================================================
    -- CONTENT CONTAINER (collapsible)
    -- ========================================================================

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 0, -92)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.content = content

    -- ========================================================================
    -- TAB PANELS
    -- ========================================================================

    -- Endeavors tab (main view)
    local endeavorsTab = VE.UI.Tabs:CreateEndeavors(content)
    endeavorsTab:SetAllPoints()
    frame.endeavorsTab = endeavorsTab

    -- Leaderboard tab
    local leaderboardTab = VE.UI.Tabs:CreateLeaderboard(content)
    leaderboardTab:SetAllPoints()
    leaderboardTab:Hide()
    frame.leaderboardTab = leaderboardTab

    -- Activity tab
    local activityTab = VE.UI.Tabs:CreateActivity(content)
    activityTab:SetAllPoints()
    activityTab:Hide()
    frame.activityTab = activityTab

    -- Config tab (settings)
    local configTab = VE.UI.Tabs:CreateConfig(content)
    configTab:SetAllPoints()
    configTab:Hide()
    frame.configTab = configTab

    -- ========================================================================
    -- TAB SWITCHING
    -- ========================================================================

    local function ShowTab(tabName)
        -- Hide all tabs
        endeavorsTab:Hide()
        leaderboardTab:Hide()
        activityTab:Hide()
        configTab:Hide()

        -- Deactivate all buttons
        endeavorsTabBtn:SetActive(false)
        leaderboardTabBtn:SetActive(false)
        activityTabBtn:SetActive(false)
        configTabBtn:SetActive(false)

        -- Show selected tab
        if tabName == "endeavors" then
            endeavorsTab:Show()
            endeavorsTabBtn:SetActive(true)
            VE:RefreshUI()
        elseif tabName == "leaderboard" then
            leaderboardTab:Show()
            leaderboardTabBtn:SetActive(true)
        elseif tabName == "activity" then
            activityTab:Show()
            activityTabBtn:SetActive(true)
        elseif tabName == "config" then
            configTab:Show()
            configTabBtn:SetActive(true)
        end
    end

    endeavorsTabBtn:SetScript("OnClick", function()
        ShowTab("endeavors")
    end)

    leaderboardTabBtn:SetScript("OnClick", function()
        ShowTab("leaderboard")
    end)

    activityTabBtn:SetScript("OnClick", function()
        ShowTab("activity")
    end)

    configTabBtn:SetScript("OnClick", function()
        ShowTab("config")
    end)

    -- Default to endeavors tab
    ShowTab("endeavors")

    -- Initial updates
    frame:UpdateHousingDisplay()
    frame:UpdateHeader()

    frame.ShowTab = ShowTab

    self.MainFrame = frame

    -- Listen for state changes to refresh UI
    VE.EventBus:Register("VE_STATE_CHANGED", function(payload)
        if not frame:IsShown() then return end

        -- Always update housing display on any state change
        if payload.action == "SET_HOUSE_LEVEL" or payload.action == "SET_COUPONS" then
            frame:UpdateHousingDisplay()
        end

        -- Update header (progress bar) when endeavor info changes
        if payload.action == "SET_ENDEAVOR_INFO" or payload.action == "SET_TASKS" then
            frame:UpdateHeader()
        end

        -- Refresh endeavors tab if visible
        if endeavorsTab:IsShown() then
            VE:RefreshUI()
        end
    end)

    -- Listen for theme updates
    -- Note: Most theming is handled by Theme Engine via registered widgets
    -- We only need to update houseLevelText here because it uses inline color codes
    VE.EventBus:Register("VE_THEME_UPDATE", function()
        local colors = VE.Constants:GetThemeColors()
        VE.Theme.ApplyFont(frame.houseLevelText, colors, "small")
        frame:UpdateHousingDisplay()
    end)

    -- Listen for UI scale changes
    VE.EventBus:Register("VE_UI_SCALE_UPDATE", function()
        local scale = VE.Store:GetState().config.uiScale or 1.0
        frame:SetScale(scale)
    end)

    return frame
end
