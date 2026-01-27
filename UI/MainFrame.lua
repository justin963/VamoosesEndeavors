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
    tabBar:SetPoint("TOPLEFT", 0, -uiConsts.titleBarHeight)
    tabBar:SetPoint("TOPRIGHT", 0, -uiConsts.titleBarHeight)
    frame.tabBar = tabBar

    -- Tab bar background (atlas for Housing Theme)
    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    local Colors = VE.Constants:GetThemeColors()
    if Colors.atlas and Colors.atlas.tabSectionBg then
        tabBarBg:SetAtlas(Colors.atlas.tabSectionBg)
    else
        tabBarBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        tabBarBg:SetVertexColor(0, 0, 0, 0)  -- Transparent for non-atlas themes
    end
    tabBar.bg = tabBarBg
    VE.Theme:Register(tabBar, "TabBar")

    -- Create tab buttons (via factory method with Theme Engine registration)
    local NUM_TABS = 5
    local tabHeight = uiConsts.tabHeight or 24
    local isHousingTheme = Colors.atlas and Colors.atlas.tabSectionBg

    -- Housing theme: full-width tabs; other themes: text-fit tabs
    local tabWidth = isHousingTheme and ((uiConsts.mainWidth / NUM_TABS) + 8) or nil
    local tabSpacing = isHousingTheme and -10 or 2
    local tabPadding = 16  -- Padding on each side of text for non-housing themes

    local endeavorsTabBtn = VE.UI:CreateTabButton(tabBar, "Endeavors")
    if tabWidth then
        endeavorsTabBtn:SetSize(tabWidth, tabHeight)
    else
        endeavorsTabBtn:SetSize((endeavorsTabBtn.label:GetStringWidth() or 50) + tabPadding, tabHeight)
    end
    endeavorsTabBtn:SetPoint("LEFT", 4, 0)

    local leaderboardTabBtn = VE.UI:CreateTabButton(tabBar, "Rankings")
    if tabWidth then
        leaderboardTabBtn:SetSize(tabWidth, tabHeight)
    else
        leaderboardTabBtn:SetSize((leaderboardTabBtn.label:GetStringWidth() or 50) + tabPadding, tabHeight)
    end
    leaderboardTabBtn:SetPoint("LEFT", endeavorsTabBtn, "RIGHT", tabSpacing, 0)

    local activityTabBtn = VE.UI:CreateTabButton(tabBar, "Activity")
    if tabWidth then
        activityTabBtn:SetSize(tabWidth, tabHeight)
    else
        activityTabBtn:SetSize((activityTabBtn.label:GetStringWidth() or 50) + tabPadding, tabHeight)
    end
    activityTabBtn:SetPoint("LEFT", leaderboardTabBtn, "RIGHT", tabSpacing, 0)

    local infoTabBtn = VE.UI:CreateTabButton(tabBar, "Info")
    if tabWidth then
        infoTabBtn:SetSize(tabWidth, tabHeight)
    else
        infoTabBtn:SetSize((infoTabBtn.label:GetStringWidth() or 50) + tabPadding, tabHeight)
    end
    infoTabBtn:SetPoint("LEFT", activityTabBtn, "RIGHT", tabSpacing, 0)

    local configTabBtn = VE.UI:CreateTabButton(tabBar, "Config")
    if tabWidth then
        configTabBtn:SetSize(tabWidth, tabHeight)
    else
        configTabBtn:SetSize((configTabBtn.label:GetStringWidth() or 50) + tabPadding, tabHeight)
    end
    configTabBtn:SetPoint("LEFT", infoTabBtn, "RIGHT", tabSpacing, 0)

    frame.endeavorsTabBtn = endeavorsTabBtn
    frame.leaderboardTabBtn = leaderboardTabBtn
    frame.activityTabBtn = activityTabBtn
    frame.infoTabBtn = infoTabBtn
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
            local houseIcon = "|A:housing-map-plot-occupied-highlight:12:12|a"
            if level >= maxLevel then
                self.houseLevelText:SetText(string.format("%s |cFF%sLv %d|r |cFF%s(Max)|r", houseIcon, accentHex, level, dimHex))
            else
                self.houseLevelText:SetText(string.format("%s |cFF%sLv %d|r |cFF%s%d/%d XP|r", houseIcon, accentHex, level, dimHex, xp, xpForNextLevel))
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
    headerSection:SetHeight(UI.headerSectionHeight)
    local headerOffset = -(UI.titleBarHeight + UI.tabHeight)
    headerSection:SetPoint("TOPLEFT", padding, headerOffset)
    headerSection:SetPoint("TOPRIGHT", -padding, headerOffset)
    frame.headerSection = headerSection

    -- Atlas background will be positioned after rows are created
    local headerBg = headerSection:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAtlas("housing-basic-panel--stone-background")
    headerSection.atlasBg = headerBg
    VE.Theme:Register(headerSection, "HeaderSection")

    -- Season name (top left)
    local seasonName = headerSection:CreateFontString(nil, "OVERLAY")
    seasonName:SetPoint("TOPLEFT", 2, -2)
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

    -- ========================================================================
    -- ROW 1: Dropdown (left), House Level + XP (right) / Fetch Status (right)
    -- ========================================================================
    local dropdownRow = CreateFrame("Frame", nil, headerSection)
    dropdownRow:SetHeight(20)
    dropdownRow:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -4)
    dropdownRow:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -4)

    -- House icon (left side)
    local houseIcon = dropdownRow:CreateTexture(nil, "ARTWORK")
    houseIcon:SetSize(16, 16)
    houseIcon:SetPoint("LEFT", 3, 0)
    houseIcon:SetAtlas("housefinder_main-icon")
    frame.houseIcon = houseIcon

    -- House selector dropdown (after icon) - uses custom styled dropdown
    local houseDropdown = VE.UI:CreateDropdown(dropdownRow, {
        width = 140,
        height = 20,
        onSelect = function(key, data)
            if VE.EndeavorTracker then
                VE.EndeavorTracker:SelectHouse(key)
            end
        end,
    })
    houseDropdown:SetPoint("LEFT", houseIcon, "RIGHT", 4, 0)
    frame.houseDropdown = houseDropdown

    -- House Level display (right side) - shares space with fetch status
    -- Note: houseLevelText uses inline color codes, so we don't register it with HeaderText
    local houseLevelText = dropdownRow:CreateFontString(nil, "OVERLAY")
    houseLevelText:SetPoint("LEFT", houseDropdown, "RIGHT", 8, 0)
    houseLevelText:SetPoint("RIGHT", -4, 0)
    houseLevelText:SetJustifyH("RIGHT")
    VE.Theme.ApplyFont(houseLevelText, C, "small")
    houseLevelText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    houseLevelText:SetText("")
    frame.houseLevelText = houseLevelText

    -- Active neighborhood container
    local activeContainer = CreateFrame("Frame", nil, dropdownRow)
    activeContainer:SetPoint("TOPLEFT", dropdownRow, "BOTTOMLEFT", 0, 0)
    activeContainer:SetSize(165, 20)
    frame.activeContainer = activeContainer

    -- Active neighborhood icon (below dropdown, aligned to left edge)
    local activeIcon = activeContainer:CreateTexture(nil, "ARTWORK")
    activeIcon:SetSize(16, 16)
    activeIcon:SetPoint("LEFT", 3, 0)
    activeIcon:SetAtlas("housing-map-plot-player-house-highlight")
    frame.activeIcon = activeIcon

    -- Active neighborhood text (after icon, width-limited)
    local activeNeighborhoodText = activeContainer:CreateFontString(nil, "OVERLAY")
    activeNeighborhoodText:SetPoint("LEFT", activeIcon, "RIGHT", 4, 0)
    activeNeighborhoodText:SetJustifyH("LEFT")
    activeNeighborhoodText:SetWidth(140)
    activeNeighborhoodText:SetWordWrap(false)
    activeNeighborhoodText:SetNonSpaceWrap(false)
    VE.Theme.ApplyFont(activeNeighborhoodText, C, "small")
    activeNeighborhoodText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    activeNeighborhoodText._colorType = "text_dim"
    VE.Theme:Register(activeNeighborhoodText, "HeaderText")
    frame.activeNeighborhoodText = activeNeighborhoodText

    -- ========================================================================
    -- ROW 2: Coupons (left), Contribution (right)
    -- ========================================================================
    local statsRow = CreateFrame("Frame", nil, headerSection)
    statsRow:SetHeight(16)
    statsRow:SetPoint("TOPLEFT", dropdownRow, "BOTTOMLEFT", -4, -2)
    statsRow:SetPoint("TOPRIGHT", dropdownRow, "BOTTOMRIGHT", -4, -2)

    -- Contribution value (right-most)
    local xpValue = statsRow:CreateFontString(nil, "OVERLAY")
    xpValue:SetPoint("RIGHT", 0, 0)
    VE.Theme.ApplyFont(xpValue, C, "small")
    xpValue:SetTextColor(C.endeavor.r, C.endeavor.g, C.endeavor.b)
    xpValue._colorType = "endeavor"
    VE.Theme:Register(xpValue, "HeaderText")
    frame.xpValue = xpValue

    -- Contribution pip icon
    local contribIcon = statsRow:CreateTexture(nil, "ARTWORK")
    contribIcon:SetSize(14, 14)
    contribIcon:SetPoint("RIGHT", xpValue, "LEFT", -4, 0)
    contribIcon:SetAtlas("housing-dashboard-fillbar-pip-complete")
    frame.contribIcon = contribIcon

    -- House XP text
    local houseXpText = statsRow:CreateFontString(nil, "OVERLAY")
    houseXpText:SetPoint("RIGHT", contribIcon, "LEFT", -12, 0)
    VE.Theme.ApplyFont(houseXpText, C, "small")
    houseXpText:SetTextColor(C.endeavor.r, C.endeavor.g, C.endeavor.b)
    houseXpText._colorType = "endeavor"
    VE.Theme:Register(houseXpText, "HeaderText")
    frame.houseXpText = houseXpText

    -- House XP icon
    local houseXpIcon = statsRow:CreateTexture(nil, "ARTWORK")
    houseXpIcon:SetSize(14, 14)
    houseXpIcon:SetPoint("RIGHT", houseXpText, "LEFT", -4, 0)
    houseXpIcon:SetAtlas("house-reward-increase-arrows")
    houseXpIcon:SetRotation(math.pi / 2) -- 90 degrees counter-clockwise
    frame.houseXpIcon = houseXpIcon

    -- Tooltip hover area for house XP
    local houseXpHover = CreateFrame("Frame", nil, statsRow)
    houseXpHover:SetPoint("LEFT", houseXpIcon, "LEFT", -2, 0)
    houseXpHover:SetPoint("RIGHT", houseXpText, "RIGHT", 2, 0)
    houseXpHover:SetPoint("TOP", houseXpIcon, "TOP", 0, 2)
    houseXpHover:SetPoint("BOTTOM", houseXpIcon, "BOTTOM", 0, -2)
    houseXpHover:EnableMouse(true)
    houseXpHover:SetScript("OnEnter", function(self)
        local colors = VE.Constants:GetThemeColors()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("This is a guess!", colors.accent.r, colors.accent.g, colors.accent.b)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("House XP Earned", 1, 1, 1)
        GameTooltip:AddLine("Estimated total from completed tasks.", 0.7, 0.7, 0.7, true)
        if frame.houseXpCapped then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("You may be capped!", colors.warning.r, colors.warning.g, colors.warning.b)
            GameTooltip:AddLine("XP gains stop after ~1000 per week.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Standard Decay: -20% per run (floor 20%)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Base 50: 50 -> 40 -> 30 -> 20 -> 10", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Accelerated: -25% per run (floor 25%)", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    houseXpHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Coupons count
    local couponsText = statsRow:CreateFontString(nil, "OVERLAY")
    couponsText:SetPoint("RIGHT", houseXpIcon, "LEFT", -12, 0)
    VE.Theme.ApplyFont(couponsText, C, "small")
    couponsText:SetTextColor(C.warning.r, C.warning.g, C.warning.b)
    couponsText._colorType = "warning"
    VE.Theme:Register(couponsText, "HeaderText")
    frame.couponsText = couponsText

    -- Coupons icon
    local couponsIcon = statsRow:CreateTexture(nil, "ARTWORK")
    couponsIcon:SetSize(14, 14)
    couponsIcon:SetPoint("RIGHT", couponsText, "LEFT", -4, 0)
    frame.couponsIcon = couponsIcon

    -- Position header background to cover entire headerSection
    headerBg:SetPoint("TOPLEFT", headerSection, "TOPLEFT", -padding, 0)
    headerBg:SetPoint("BOTTOMRIGHT", statsRow, "BOTTOMRIGHT", padding, -2)

    -- Update house dropdown when house list changes
    function frame:UpdateHouseDropdown(houseList, selectedIndex)
        if houseList and #houseList > 0 then
            -- Build items for the dropdown
            local items = {}
            for i, houseInfo in ipairs(houseList) do
                table.insert(items, {
                    key = i,
                    label = houseInfo.houseName or ("House " .. i),
                })
            end
            self.houseDropdown:SetItems(items)

            -- Set selected house
            local selectedHouse = houseList[selectedIndex or 1]
            local houseName = selectedHouse and selectedHouse.houseName or "Select House"
            self.houseDropdown:SetSelected(selectedIndex or 1, { label = houseName })
        else
            self.houseDropdown:SetItems({})
            self.houseDropdown:SetSelected(nil, { label = "No houses" })
        end
    end

    -- Show which neighborhood is the active endeavor destination
    function frame:UpdateActiveNeighborhood()
        if not C_NeighborhoodInitiative then
            self.activeIcon:Hide()
            self.activeNeighborhoodText:SetText("")
            return
        end

        local activeGUID = C_NeighborhoodInitiative.GetActiveNeighborhood and C_NeighborhoodInitiative.GetActiveNeighborhood()
        if not activeGUID then
            self.activeIcon:Hide()
            self.activeNeighborhoodText:SetText("None")
            return
        end

        -- Find the house name for the active neighborhood
        local activeName = nil
        if VE.EndeavorTracker and VE.EndeavorTracker.houseList then
            for _, houseInfo in ipairs(VE.EndeavorTracker.houseList) do
                if houseInfo.neighborhoodGUID == activeGUID then
                    activeName = houseInfo.houseName or houseInfo.neighborhoodName
                    break
                end
            end
        end

        self.activeIcon:Show()
        local colors = VE.Constants:GetThemeColors()
        local accentHex = string.format("%02x%02x%02x", colors.accent.r*255, colors.accent.g*255, colors.accent.b*255)
        self.activeNeighborhoodText:SetText("|cFF" .. accentHex .. (activeName or "Unknown") .. "|r")
    end

    -- Listen for activity log updates (refresh contribution)
    VE.EventBus:Register("VE_ACTIVITY_LOG_UPDATED", function(payload)
        -- Refresh contribution display (calculated from activity log)
        if frame.UpdateHeader then
            frame:UpdateHeader()
        end
    end)

    -- Listen for house list updates
    VE.EventBus:Register("VE_HOUSE_LIST_UPDATED", function(payload)
        if frame.UpdateHouseDropdown and payload then
            frame:UpdateHouseDropdown(payload.houseList, payload.selectedIndex)
        end
        if frame.UpdateActiveNeighborhood then
            frame:UpdateActiveNeighborhood()
        end
    end)

    -- Listen for active neighborhood changes (from VE button or Blizzard's dashboard)
    VE.EventBus:Register("VE_ACTIVE_NEIGHBORHOOD_CHANGED", function()
        if frame.UpdateActiveNeighborhood then
            frame:UpdateActiveNeighborhood()
        end
    end)

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
        -- Update house dropdown
        if VE.EndeavorTracker then
            frame:UpdateHouseDropdown(VE.EndeavorTracker:GetHouseList(), VE.EndeavorTracker:GetSelectedHouseIndex())
        end
        -- Update active neighborhood display
        frame:UpdateActiveNeighborhood()
    end)

    -- Hide tooltip on hide
    frame:HookScript("OnHide", function()
        if GameTooltip:IsOwned(frame) then
            GameTooltip:Hide()
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
        if activityData and activityData.taskActivity then
            local currentPlayer = UnitName("player")
            local entryCount = 0
            for _, entry in ipairs(activityData.taskActivity) do
                if entry.playerName == currentPlayer then
                    playerContribution = playerContribution + (entry.amount or 0)
                    entryCount = entryCount + 1
                end
            end
        end
        -- Contribution = endeavor progress (from activity log)
        self.xpValue:SetText(string.format("%.1f", playerContribution))

        -- House XP = reward from completed tasks (with DR calculation)
        local houseXpEarned = 0
        if state.tasks and VE.EndeavorTracker then
            for _, task in ipairs(state.tasks) do
                houseXpEarned = houseXpEarned + VE.EndeavorTracker:GetTaskTotalHouseXPEarned(task)
            end
        end
        self.houseXpText:SetText(tostring(houseXpEarned))
        -- Grey out if potentially capped (>1000 XP)
        local colors = VE.Constants:GetThemeColors()
        if houseXpEarned > 1000 then
            self.houseXpText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            self.houseXpText._colorType = "text_dim"  -- Update for theme engine
            self.houseXpCapped = true
        else
            self.houseXpText:SetTextColor(colors.endeavor.r, colors.endeavor.g, colors.endeavor.b)
            self.houseXpText._colorType = "endeavor"  -- Update for theme engine
            self.houseXpCapped = false
        end
    end

    -- ========================================================================
    -- CONTENT CONTAINER (collapsible)
    -- ========================================================================

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 0, -UI.headerContentOffset)
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

    -- Info tab (initiative collection)
    local infoTab = VE.UI.Tabs:CreateInfo(content)
    infoTab:SetAllPoints()
    infoTab:Hide()
    frame.infoTab = infoTab

    -- ========================================================================
    -- TAB SWITCHING
    -- ========================================================================

    local function ShowTab(tabName)
        -- Hide all tabs
        endeavorsTab:Hide()
        leaderboardTab:Hide()
        activityTab:Hide()
        infoTab:Hide()
        configTab:Hide()

        -- Deactivate all buttons
        endeavorsTabBtn:SetActive(false)
        leaderboardTabBtn:SetActive(false)
        activityTabBtn:SetActive(false)
        infoTabBtn:SetActive(false)
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
        elseif tabName == "info" then
            infoTab:Show()
            infoTabBtn:SetActive(true)
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

    infoTabBtn:SetScript("OnClick", function()
        ShowTab("info")
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
        -- Refresh active neighborhood text (uses inline color codes)
        if frame.UpdateActiveNeighborhood then
            frame:UpdateActiveNeighborhood()
        end

        -- Resize tabs based on theme (housing = full-width, others = text-fit)
        local housingTheme = colors.atlas and colors.atlas.tabSectionBg
        local fullTabWidth = housingTheme and ((uiConsts.mainWidth / 5) + 8) or nil
        local spacing = housingTheme and -10 or 2
        local padding = 16

        local tabs = { frame.endeavorsTabBtn, frame.leaderboardTabBtn, frame.activityTabBtn, frame.infoTabBtn, frame.configTabBtn }
        for i, tab in ipairs(tabs) do
            if fullTabWidth then
                tab:SetWidth(fullTabWidth)
            elseif tab.label then
                tab:SetWidth((tab.label:GetStringWidth() or 50) + padding)
            end
            -- Update spacing (skip first tab)
            if i > 1 then
                tab:SetPoint("LEFT", tabs[i-1], "RIGHT", spacing, 0)
            end
        end
    end)

    -- Listen for UI scale changes
    VE.EventBus:Register("VE_UI_SCALE_UPDATE", function()
        local scale = VE.Store:GetState().config.uiScale or 1.0
        frame:SetScale(scale)
    end)

    return frame
end
