-- ============================================================================
-- Vamoose's Endeavors - UI Framework
-- Reusable UI components with Solarized theme
-- Uses Theme Registry pattern for live theme switching
-- ============================================================================

VE = VE or {}
VE.UI = {}

-- ============================================================================
-- CENTRALIZED BACKDROP CONSTANTS
-- ============================================================================

local BACKDROP_FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

local BACKDROP_BORDERLESS = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = nil,
    tile = false,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function GetScheme()
    if VE.Theme and VE.Theme.currentScheme then
        return VE.Theme.currentScheme
    end
    return VE.Constants.Colors
end

local function RegisterWidget(widget, widgetType)
    if VE.Theme and VE.Theme.Register then
        VE.Theme:Register(widget, widgetType)
    end
end

-- ============================================================================
-- THEME APPLICATION (Legacy support + Registration)
-- ============================================================================

local function ApplyTheme(frame, themeType)
    if not frame then return end

    local Colors = GetScheme()

    if themeType == "Window" then
        frame:SetBackdrop(BACKDROP_BORDERLESS)
        frame:SetBackdropColor(Colors.bg.r, Colors.bg.g, Colors.bg.b, Colors.bg.a)
        RegisterWidget(frame, "Frame")

    elseif themeType == "Panel" then
        frame:SetBackdrop(BACKDROP_FLAT)
        frame:SetBackdropColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, Colors.panel.a)
        frame:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, Colors.border.a)
        RegisterWidget(frame, "Panel")

    elseif themeType == "Button" then
        frame:SetBackdrop(BACKDROP_FLAT)
        frame:SetBackdropColor(Colors.button_normal.r, Colors.button_normal.g, Colors.button_normal.b, Colors.button_normal.a)
        frame:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, Colors.border.a)

        -- Store scheme reference for hover scripts
        frame._scheme = Colors

        frame:SetScript("OnEnter", function(self)
            local c = self._scheme or GetScheme()
            self:SetBackdropColor(c.button_hover.r, c.button_hover.g, c.button_hover.b, c.button_hover.a)
        end)
        frame:SetScript("OnLeave", function(self)
            local c = self._scheme or GetScheme()
            self:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a)
        end)

        RegisterWidget(frame, "Button")
    end
end

-- ============================================================================
-- MAIN FRAME
-- ============================================================================

function VE.UI:CreateMainFrame(name, title)
    local UI = VE.Constants.UI

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(UI.mainWidth, UI.mainHeight)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    -- Atlas wood frame border (Housing Theme)
    local borderFrame = CreateFrame("Frame", nil, frame)
    borderFrame:SetAllPoints()  -- Align with window edges
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 10)  -- Render on top
    local borderTex = borderFrame:CreateTexture(nil, "OVERLAY")
    borderTex:SetAllPoints()
    borderTex:SetAtlas("housing-wood-frame")
    borderTex:SetAlpha(1)
    borderFrame.tex = borderTex
    frame.borderFrame = borderFrame
    -- Initial visibility based on theme
    local Colors = GetScheme()
    if Colors.atlas and Colors.atlas.windowBorder then
        borderFrame:Show()
    else
        borderFrame:Hide()
    end

    ApplyTheme(frame, "Window")

    -- Title Bar
    local Colors = GetScheme()
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(27)  -- 18 * 1.5 = 27 (50% taller)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop(BACKDROP_BORDERLESS)
    titleBar:SetBackdropColor(0, 0, 0, 0) -- Transparent, atlas provides background

    -- Atlas background for title bar
    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetAtlas("housing-dashboard-fillbar-bar-bg")
    titleBar.atlasBg = titleBg

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("CENTER", 0, 0)
    VE.Theme.ApplyFont(titleText, Colors, "small")
    titleText:SetText(title)
    titleText:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a)
    frame.titleText = titleText
    titleBar.titleText = titleText

    -- Logo texture for Housing Theme (replaces title text)
    local titleLogo = titleBar:CreateTexture(nil, "OVERLAY")
    titleLogo:SetTexture("Interface\\AddOns\\VamoosesEndeavors\\Textures\\title_logo.tga")
    titleLogo:SetSize(180, 60)  -- Aspect ratio ~3:1, logo overlaps but transparent areas invisible
    titleLogo:SetPoint("CENTER", 0, 0)
    titleBar.titleLogo = titleLogo
    -- Set initial visibility based on current theme
    if Colors.atlas and Colors.atlas.titleBarBg then
        titleLogo:Show()
        titleText:Hide()
    else
        titleLogo:Hide()
        titleText:Show()
    end

    -- Register title bar for theming
    RegisterWidget(titleBar, "TitleBar")

    -- Refresh Button (top left, icon only)
    local refreshBtn = CreateFrame("Button", nil, titleBar)
    refreshBtn:SetSize(20, 20)
    refreshBtn:SetPoint("LEFT", 4, 0)
    refreshBtn._scheme = Colors

    local refreshIcon = refreshBtn:CreateTexture(nil, "ARTWORK")
    refreshIcon:SetSize(18, 18)
    refreshIcon:SetPoint("CENTER")
    refreshIcon:SetAtlas("housefinder_neighborhood-party-sync-icon")
    refreshBtn.icon = refreshIcon
    titleBar.refreshBtn = refreshBtn    -- Store for TitleBar skinner to update _scheme

    refreshBtn:SetScript("OnClick", function()
        if VE.EndeavorTracker then
            -- Refresh all endeavor data (handles correct API call order)
            VE.EndeavorTracker:RefreshAll()
        end
        if VE.HousingTracker then
            -- Refresh housing data (coupons, house level)
            VE.HousingTracker:RequestHouseInfo()
            VE.HousingTracker:UpdateCoupons()
        end
        -- Refresh whichever tab is currently shown (after data loads)
        C_Timer.After(0.5, function()
            if VE.MainFrame then
                if VE.MainFrame.endeavorsTab and VE.MainFrame.endeavorsTab:IsShown() then
                    VE.MainFrame.endeavorsTab:Update()
                elseif VE.MainFrame.leaderboardTab and VE.MainFrame.leaderboardTab:IsShown() then
                    VE.MainFrame.leaderboardTab:Update()
                elseif VE.MainFrame.activityTab and VE.MainFrame.activityTab:IsShown() then
                    VE.MainFrame.activityTab:Update()
                end
            end
        end)
    end)

    refreshBtn:SetScript("OnEnter", function(self)
        if self.icon then
            self.icon:SetVertexColor(1, 1, 1, 1)  -- Bright on hover
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Refresh", 1, 1, 1)
        GameTooltip:AddLine("Fetches latest endeavor data and rebuilds all UI elements", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)

    refreshBtn:SetScript("OnLeave", function(self)
        if self.icon then
            self.icon:SetVertexColor(0.7, 0.7, 0.7, 1)  -- Dim when not hovered
        end
        GameTooltip:Hide()
    end)

    -- Set initial dimmed state
    refreshIcon:SetVertexColor(0.7, 0.7, 0.7, 1)

    -- Minimize Button (collapses task list)
    local minimizeBtn = CreateFrame("Button", nil, titleBar)
    minimizeBtn:SetSize(18, 18)
    minimizeBtn:SetPoint("RIGHT", -33, 0)

    local minimizeIcon = minimizeBtn:CreateTexture(nil, "ARTWORK")
    minimizeIcon:SetAllPoints()
    minimizeIcon:SetAtlas("Map-Filter-Button")
    minimizeIcon:SetVertexColor(0.85, 0.85, 0.85, 1)  -- Dimmed when not hovered
    minimizeBtn.icon = minimizeIcon

    frame.isMinimized = false
    frame.expandedHeight = UI.mainHeight

    minimizeBtn:SetScript("OnClick", function()
        frame.isMinimized = not frame.isMinimized
        if frame.isMinimized then
            -- Collapse to header only (title bar + tab bar + header section + stats row + fetch status)
            frame:SetHeight(UI.headerContentOffset)
            -- Hide content area
            if frame.content then
                frame.content:Hide()
            end
        else
            -- Expand to full height
            frame:SetHeight(frame.expandedHeight)
            -- Show content area
            if frame.content then
                frame.content:Show()
            end
        end
    end)

    minimizeBtn:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if frame.isMinimized then
            GameTooltip:AddLine("Expand", 1, 1, 1)
            GameTooltip:AddLine("Show full tracker", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("Swap to Mini-Tracker", 1, 1, 1)
            GameTooltip:AddLine("Collapse to compact view", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)

    minimizeBtn:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
        GameTooltip:Hide()
    end)

    frame.minimizeBtn = minimizeBtn

    -- Theme Toggle Button (next to close)
    local themeBtn = CreateFrame("Button", nil, titleBar)
    themeBtn:SetSize(18, 18)
    themeBtn:SetPoint("RIGHT", -15, 0)

    local themeIcon = themeBtn:CreateTexture(nil, "ARTWORK")
    themeIcon:SetAllPoints()
    themeIcon:SetAtlas("Crosshair_Transmogrify_32")
    themeIcon:SetVertexColor(0.85, 0.85, 0.85, 1)  -- Dimmed when not hovered
    themeBtn.icon = themeIcon
    titleBar.themeIcon = themeIcon  -- Store reference

    -- Update icon (no-op now since it's an atlas)
    local function UpdateThemeIcon()
        -- Atlas icon doesn't need color updates
    end

    -- Helper to get next theme display name
    local function GetNextThemeDisplayName()
        local currentTheme = VE.Constants:GetCurrentTheme()
        local currentIndex = 1
        for i, theme in ipairs(VE.Constants.ThemeOrder) do
            if theme == currentTheme then
                currentIndex = i
                break
            end
        end
        local nextIndex = (currentIndex % #VE.Constants.ThemeOrder) + 1
        local nextTheme = VE.Constants.ThemeOrder[nextIndex]
        return VE.Constants.ThemeDisplayNames[nextTheme] or VE.Constants.ThemeNames[nextTheme] or "Dark"
    end

    -- Helper to show theme tooltip
    local function ShowThemeTooltip(btn)
        local currentTheme = VE.Constants:GetCurrentTheme()
        local currentDisplayName = VE.Constants.ThemeDisplayNames[currentTheme] or currentTheme
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Change Theme", 1, 1, 1)
        GameTooltip:AddLine("Current: " .. currentDisplayName, 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Next: " .. GetNextThemeDisplayName(), 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end

    themeBtn:SetScript("OnClick", function(self)
        local newTheme = VE.Constants:ToggleTheme()
        local themeName = VE.Constants.ThemeNames[newTheme] or "Dark"
        local displayName = VE.Constants.ThemeDisplayNames[newTheme] or themeName

        -- Trigger theme update event (Theme Engine will re-skin all registered widgets)
        if VE.EventBus then
            VE.EventBus:Trigger("VE_THEME_UPDATE", { themeName = themeName })
        end

        UpdateThemeIcon()
        print("|cFF2aa198[VE]|r Theme switched to " .. displayName)

        -- Update tooltip if still hovering
        if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
            ShowThemeTooltip(self)
        end
    end)

    themeBtn:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        ShowThemeTooltip(self)
    end)

    themeBtn:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
        GameTooltip:Hide()
    end)

    frame.themeBtn = themeBtn
    frame.UpdateThemeIcon = UpdateThemeIcon

    -- Close Button (top right) - Housing door icon
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -1, 0)

    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAllPoints()
    closeIcon:SetAtlas("housing-floor-door-inactive")
    closeIcon:SetVertexColor(0.7, 0.7, 0.7, 1)  -- Dimmed when not hovered
    closeBtn.icon = closeIcon
    titleBar.closeIcon = closeIcon  -- Store for TitleBar skinner

    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    closeBtn:SetScript("OnEnter", function(self)
        self.icon:SetAtlas("housing-floor-door")
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Close", 1, 1, 1)
        GameTooltip:Show()
    end)

    closeBtn:SetScript("OnLeave", function(self)
        self.icon:SetAtlas("housing-floor-door-inactive")
        self.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
        GameTooltip:Hide()
    end)

    frame.titleBar = titleBar
    frame.refreshBtn = refreshBtn
    frame.themeBtn = themeBtn
    frame.closeBtn = closeBtn

    return frame
end

-- ============================================================================
-- BUTTON
-- ============================================================================

function VE.UI:CreateButton(parent, text, width, height)
    local Colors = GetScheme()

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 24)
    btn:SetText(text)
    ApplyTheme(btn, "Button")

    local fs = btn:GetFontString()
    if fs then
        VE.Theme.ApplyFont(fs, Colors)
        fs:SetTextColor(Colors.button_text_norm.r, Colors.button_text_norm.g, Colors.button_text_norm.b)
    end

    return btn
end

-- ============================================================================
-- TAB BUTTON
-- ============================================================================

function VE.UI:CreateTabButton(parent, text, options)
    options = options or {}
    local Colors = GetScheme()
    local UI = VE.Constants.UI or {}
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(UI.tabWidth or 90, UI.tabHeight or 24)
    btn:SetBackdrop(BACKDROP_FLAT)

    -- Support icon-only tabs (atlas icons)
    if options.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas(options.icon)
        btn.icon = icon
        btn.iconDefault = options.icon
        btn.iconActive = options.iconActive or options.icon
    else
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER")
        VE.Theme.ApplyFont(label, Colors, "small")
        label:SetText(text)
        btn.label = label
    end

    btn.isActive = false

    function btn:SetActive(active)
        self.isActive = active
        -- Update icon atlas if using icon mode
        if self.icon then
            if active then
                self.icon:SetAtlas(self.iconActive)
            else
                self.icon:SetAtlas(self.iconDefault)
            end
        end
        -- Re-apply theme (the TabButton skinner handles active state)
        if VE.Theme and VE.Theme.Skinners and VE.Theme.Skinners.TabButton then
            VE.Theme.Skinners.TabButton(self, VE.Theme:GetScheme())
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self.isActive then
            local c = self._scheme or GetScheme()
            -- Skip backdrop changes for Atlas themes
            if c.atlas and c.atlas.tabActive then return end
            if self:GetBackdrop() then
                self:SetBackdropColor(c.button_hover.r, c.button_hover.g, c.button_hover.b, c.button_hover.a * 0.6)
            end
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if not self.isActive then
            local c = self._scheme or GetScheme()
            -- Skip backdrop changes for Atlas themes
            if c.atlas and c.atlas.tabActive then return end
            if self:GetBackdrop() then
                self:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a * 0.6)
            end
        end
    end)

    -- Register with theme engine
    RegisterWidget(btn, "TabButton")

    return btn
end

-- ============================================================================
-- PROGRESS BAR
-- ============================================================================

function VE.UI:CreateProgressBar(parent, options)
    options = options or {}
    local width = options.width or 200
    local height = options.height or VE.Constants.UI.progressBarHeight
    local Colors = GetScheme()

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Background texture (Blizzard atlas)
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas(Colors.atlas.fillBarBg)
    container.bg = bg

    -- Fill bar (Blizzard atlas) - centered within bg (25px fill in 34px bg = 2px inset)
    local fill = container:CreateTexture(nil, "ARTWORK")
    fill:SetAtlas(Colors.atlas.fillBarFill)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMLEFT", 2, 3)
    fill:SetWidth(1)
    container.fill = fill

    -- Progress text
    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    VE.Theme.ApplyFont(text, Colors, "small")
    text:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
    container.text = text

    -- Milestone diamonds (if provided)
    container.milestones = {}

    function container:SetProgress(current, max)
        local pct = max > 0 and (current / max) or 0
        pct = math.min(1, math.max(0, pct))

        local fillWidth = math.max(1, (self:GetWidth() - 4) * pct)
        self.fill:SetWidth(fillWidth)
        self.text:SetText(string.format("%d / %d", current, max))
    end

    function container:SetMilestones(milestones, max)
        -- Clear existing
        for _, m in ipairs(self.milestones) do
            m:Hide()
        end
        self.milestones = {}

        if not milestones then return end

        local C = GetScheme()
        local barWidth = self:GetWidth() - 4
        for i, milestone in ipairs(milestones) do
            local pip = self:CreateTexture(nil, "OVERLAY")
            pip:SetSize(VE.Constants.UI.milestoneSize, VE.Constants.UI.milestoneSize)

            local xPos = (milestone.threshold / max) * barWidth
            pip:SetPoint("CENTER", self, "LEFT", xPos + 2, 0)

            -- All themes use Blizzard pip atlases
            if milestone.reached then
                pip:SetAtlas(C.atlas.pipComplete)
            else
                pip:SetAtlas(C.atlas.pipIncomplete)
            end
            pip:SetVertexColor(1, 1, 1, 1)

            table.insert(self.milestones, pip)
        end
    end

    -- Register with theme engine
    RegisterWidget(container, "ProgressBar")

    return container
end

-- ============================================================================
-- TASK ROW
-- ============================================================================

function VE.UI:CreateTaskRow(parent, options)
    options = options or {}
    local height = options.height or VE.Constants.UI.taskRowHeight
    local Colors = GetScheme()

    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(height)
    row:SetBackdrop(BACKDROP_BORDERLESS)
    row:SetBackdropColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, Colors.panel.a * 0.5)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Store scheme for hover scripts
    row._scheme = Colors

    -- Checkbox/status indicator
    local status = row:CreateTexture(nil, "ARTWORK")
    status:SetSize(14, 14)
    status:SetPoint("LEFT", 4, 0)  -- 4px left padding
    status:SetTexture("Interface\\COMMON\\Indicator-Gray")
    row.status = status

    -- Repeatable indicator (circular arrow icon - replaces status for repeatable tasks)
    local repeatIcon = row:CreateTexture(nil, "ARTWORK")
    repeatIcon:SetSize(20, 20)
    repeatIcon:SetPoint("LEFT", 1, 0)  -- 4px left padding (-3 + 4 = 1)
    repeatIcon:SetAtlas("UI-RefreshButton")
    repeatIcon:Hide()
    row.repeatIcon = repeatIcon

    -- Counter text inside repeat icon (shows times completed)
    local repeatCount = row:CreateFontString(nil, "OVERLAY")
    repeatCount:SetPoint("CENTER", repeatIcon, "CENTER", 1, 0)
    repeatCount:SetFont(VE.Constants:GetFontFile(), 10, "OUTLINE")
    repeatCount:SetTextColor(Colors.success.r, Colors.success.g, Colors.success.b)
    repeatCount:Hide()
    row.repeatCount = repeatCount

    -- Tracking checkmark (overlays on status/repeat icon when task is pinned)
    local trackMark = row:CreateTexture(nil, "OVERLAY", nil, 7)  -- High sublevel to draw on top
    trackMark:SetSize(14, 14)
    trackMark:SetPoint("LEFT", 4, 0)  -- 4px left padding
    trackMark:SetAtlas("common-icon-checkmark")
    trackMark:SetVertexColor(Colors.success.r, Colors.success.g, Colors.success.b)
    trackMark:Hide()
    row.trackMark = trackMark

    -- Task name (use theme-aware text color)
    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetPoint("LEFT", status, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", -70, 0)
    name:SetJustifyH("LEFT")
    VE.Theme.ApplyFont(name, Colors)
    name:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
    row.name = name

    -- Coupon reward badge (shows +3 coupons)
    local couponBg = CreateFrame("Frame", nil, row, "BackdropTemplate")
    couponBg:SetSize(26, 18)
    couponBg:SetPoint("RIGHT", -4, 0)
    couponBg:SetBackdrop(BACKDROP_FLAT)
    couponBg:SetBackdropColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a * 0.3)
    couponBg:SetBackdropBorderColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a * 0.6)

    local couponText = couponBg:CreateFontString(nil, "OVERLAY")
    couponText:SetPoint("CENTER")
    VE.Theme.ApplyFont(couponText, Colors)
    couponText:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a)
    couponText:SetText("+3")
    row.couponText = couponText
    row.couponBg = couponBg

    -- Points badge
    local pointsBg = CreateFrame("Frame", nil, row, "BackdropTemplate")
    pointsBg:SetSize(32, 24)
    pointsBg:SetPoint("RIGHT", couponBg, "LEFT", -4, 0)
    pointsBg:SetBackdrop(BACKDROP_FLAT)
    pointsBg:SetBackdropColor(Colors.endeavor.r, Colors.endeavor.g, Colors.endeavor.b, Colors.endeavor.a * 0.3)
    pointsBg:SetBackdropBorderColor(Colors.endeavor.r, Colors.endeavor.g, Colors.endeavor.b, Colors.endeavor.a * 0.6)

    local points = pointsBg:CreateFontString(nil, "OVERLAY")
    points:SetPoint("CENTER")
    VE.Theme.ApplyFont(points, Colors)
    points:SetTextColor(Colors.endeavor.r, Colors.endeavor.g, Colors.endeavor.b, Colors.endeavor.a)
    row.points = points
    row.pointsBg = pointsBg

    -- Progress text (for partial completion)
    local progress = row:CreateFontString(nil, "OVERLAY")
    progress:SetPoint("RIGHT", pointsBg, "LEFT", -6, 0)
    VE.Theme.ApplyFont(progress, Colors)
    progress:SetTextColor(Colors.text_dim.r, Colors.text_dim.g, Colors.text_dim.b)
    row.progress = progress

    -- Rank medal indicator (top-left of XP badge)
    local rankMedal = pointsBg:CreateTexture(nil, "OVERLAY", nil, 2)
    rankMedal:SetSize(14, 14)
    rankMedal:SetPoint("TOPLEFT", pointsBg, "TOPLEFT", -4, 4)
    rankMedal:Hide()
    row.rankMedal = rankMedal

    -- Medal atlases by rank
    row.rankMedals = {
        [1] = "challenges-medal-gold",
        [2] = "challenges-medal-silver",
        [3] = "challenges-medal-bronze",
    }

    -- Store rank colors (gold, silver, bronze)
    row.rankColors = {
        [1] = { r = 1.0, g = 0.84, b = 0.0 },   -- Gold
        [2] = { r = 0.75, g = 0.75, b = 0.75 }, -- Silver
        [3] = { r = 0.80, g = 0.50, b = 0.20 }, -- Bronze
    }
    row.rankTints = {
        [1] = { r = 1.0, g = 0.84, b = 0.0, a = 0.15 },   -- Gold tint
        [2] = { r = 0.75, g = 0.75, b = 0.75, a = 0.12 }, -- Silver tint
        [3] = { r = 0.80, g = 0.50, b = 0.20, a = 0.12 }, -- Bronze tint
    }

    -- Update function
    function row:SetTask(task, ranking)
        local C = GetScheme()  -- Re-fetch for current theme
        self.task = task
        self.ranking = ranking  -- Store for tooltip
        self.name:SetText(task.name or "Unknown Task")
        self.points:SetText(tostring(task.points or 0))

        -- Update coupon reward display
        if task.couponReward and task.couponReward > 0 then
            self.couponText:SetText("+" .. task.couponReward)
            self.couponBg:Show()
        else
            self.couponBg:Hide()
        end

        -- Show/hide repeatable icon and adjust name position
        self.name:ClearAllPoints()
        if task.isRepeatable then
            self.status:Hide()
            self.repeatIcon:Show()
            -- Show completion count inside icon
            local count = task.timesCompleted or 0
            if count > 0 then
                self.repeatCount:SetText(tostring(count))
                self.repeatCount:Show()
            else
                self.repeatCount:Hide()
            end
            self.name:SetPoint("LEFT", self.repeatIcon, "RIGHT", 2, 0)
            self.name:SetPoint("RIGHT", -100, 0)
        else
            self.repeatIcon:Hide()
            self.repeatCount:Hide()
            self.status:Show()
            self.name:SetPoint("LEFT", self.status, "RIGHT", 6, 0)
            self.name:SetPoint("RIGHT", -100, 0)

            if task.completed then
                self.status:SetTexture("Interface\\COMMON\\Indicator-Green")
            else
                self.status:SetTexture("Interface\\COMMON\\Indicator-Gray")
            end
        end

        if task.completed then
            self.name:SetTextColor(C.success.r, C.success.g, C.success.b)
            self.progress:SetText("")
        else
            if task.max and task.max > 1 then
                self.progress:SetText(string.format("%d/%d", task.current or 0, task.max))
            else
                self.progress:SetText("")
            end
            self.name:SetTextColor(C.text.r, C.text.g, C.text.b)
        end

        -- Update tracking checkmark
        if task.tracked and not task.completed then
            self.trackMark:Show()
        else
            self.trackMark:Hide()
        end

        -- XP text uses success color for all themes (each theme defines success)
        local pointsColor = C.success

        -- Apply ranking tint and medal for top 3 "next XP" tasks
        if ranking and ranking.rank and ranking.rank >= 1 and ranking.rank <= 3 then
            local rank = ranking.rank
            local tint = self.rankTints[rank]
            -- Store tint for OnLeave to restore
            self._rankTint = tint
            -- Apply background tint
            self:SetBackdropColor(tint.r, tint.g, tint.b, tint.a)
            -- Reset XP text to themed color (in case it was warning before)
            self.points:SetTextColor(pointsColor.r, pointsColor.g, pointsColor.b)
            -- Show medal
            self.rankMedal:SetAtlas(self.rankMedals[rank])
            self.rankMedal:Show()
        else
            -- Hide medal
            self.rankMedal:Hide()
            -- Check if task gives 0 XP (warning highlight)
            local showNoXPWarning = false
            if not task.completed and VE.EndeavorTracker then
                if task.isRepeatable then
                    -- Repeatable: check if API points is 0 OR next completion gives 0 XP
                    local completions = VE.EndeavorTracker:GetAccountCompletionCount(task.id)
                    local nextXP = VE.EndeavorTracker:CalculateNextContribution(task.name, completions)
                    showNoXPWarning = (task.points == 0) or (nextXP == 0)
                elseif not task.isRepeatable then
                    -- Non-repeatable: no warning if not completed (will give XP on first/only completion)
                    showNoXPWarning = false
                end
            end
            if showNoXPWarning then
                -- Apply warning tint for 0 XP tasks (use theme's error color)
                self._isNoXPWarning = true
                self._rankTint = { r = C.error.r, g = C.error.g, b = C.error.b, a = 0.18 }
                self:SetBackdropColor(C.error.r, C.error.g, C.error.b, 0.18)
                -- Also color the XP text to match warning
                self.points:SetTextColor(C.error.r, C.error.g, C.error.b)
            else
                -- Clear warning flag and rank tint, reset to default
                self._isNoXPWarning = false
                self._rankTint = nil
                self:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.5)
                -- Reset XP text to themed color
                self.points:SetTextColor(pointsColor.r, pointsColor.g, pointsColor.b)
            end
        end
    end

    -- Toggle tracking state
    function row:ToggleTracking()
        if not self.task or not self.task.id then return end
        if self.task.completed then return end  -- Can't track completed tasks

        if C_NeighborhoodInitiative then
            if self.task.tracked then
                C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(self.task.id)
                self.task.tracked = false
            else
                C_NeighborhoodInitiative.AddTrackedInitiativeTask(self.task.id)
                self.task.tracked = true
            end
            self.trackMark:SetShown(self.task.tracked)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end

    -- Click handler (shift-click to track)
    row:SetScript("OnClick", function(self, button)
        if IsModifiedClick("QUESTWATCHTOGGLE") then
            self:ToggleTracking()
        end
    end)

    -- Hover effect
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local c = self._scheme or GetScheme()
        self:SetBackdropColor(c.button_hover.r, c.button_hover.g, c.button_hover.b, c.button_hover.a * 0.3)
        if self.task then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.task.name, 1, 1, 1)
            if self.task.description and self.task.description ~= "" then
                GameTooltip:AddLine(self.task.description, nil, nil, nil, true)
            end
            -- Show base endeavor XP
            if self.task.points and self.task.points > 0 then
                GameTooltip:AddLine(string.format("Current House XP reward: %.2f", self.task.points), c.endeavor.r, c.endeavor.g, c.endeavor.b)
            end
            -- Show coupon reward info
            if self.task.couponReward and self.task.couponReward > 0 then
                local label = self.task.isRepeatable and "Base reward" or "Reward"
                GameTooltip:AddLine(label .. ": +" .. self.task.couponReward .. " coupons", c.accent.r, c.accent.g, c.accent.b)
            end
            -- Show times completed for repeatable tasks
            if self.task.isRepeatable and self.task.timesCompleted and self.task.timesCompleted > 0 then
                GameTooltip:AddLine("Completed: " .. self.task.timesCompleted .. " times", 0.5, 0.8, 0.5)
            end
            -- Show next contribution prediction for repeatable tasks
            if self.task.isRepeatable and not self.task.completed and VE.EndeavorTracker then
                -- Show raw API progressContributionAmount (House XP the player receives)
                if self.task.progressContributionAmount and self.task.progressContributionAmount > 0 then
                    GameTooltip:AddLine(string.format("House XP (API): %d", self.task.progressContributionAmount), 0.6, 0.6, 0.6)
                end
                if self.ranking and self.ranking.nextXP then
                    -- Ranked task (top 3) - show with rank label and color
                    local rankLabels = { "Best", "2nd Best", "3rd Best" }
                    local rankColor = self.rankColors[self.ranking.rank] or { r = 1, g = 1, b = 1 }
                    GameTooltip:AddLine(string.format("%s Next Endeavor: +%.3f", rankLabels[self.ranking.rank] or "", self.ranking.nextXP), rankColor.r, rankColor.g, rankColor.b)
                else
                    -- Non-ranked task - calculate on-the-fly
                    local completions = VE.EndeavorTracker:GetAccountCompletionCount(self.task.id)
                    local nextXP = VE.EndeavorTracker:CalculateNextContribution(self.task.name, completions)
                    GameTooltip:AddLine(string.format("Next House XP: +%.3f", nextXP), 0.7, 0.7, 0.7)
                end
            end
            -- Tracking hint
            if not self.task.completed then
                GameTooltip:AddLine(" ")
                if self.task.tracked then
                    GameTooltip:AddLine("Shift-click to untrack", 0.5, 0.5, 0.5)
                else
                    GameTooltip:AddLine("Shift-click to track", 0.5, 0.5, 0.5)
                end
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        local c = self._scheme or GetScheme()
        -- Restore rank tint if present, otherwise default panel color
        if self._rankTint then
            self:SetBackdropColor(self._rankTint.r, self._rankTint.g, self._rankTint.b, self._rankTint.a)
        else
            self:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * 0.5)
        end
        GameTooltip:Hide()
    end)

    -- Register with theme engine
    RegisterWidget(row, "TaskRow")

    return row
end

-- ============================================================================
-- DROPDOWN / CHARACTER SELECTOR
-- ============================================================================

function VE.UI:CreateDropdown(parent, options)
    options = options or {}
    local width = options.width or 150
    local height = options.height or VE.Constants.UI.charSelectorHeight
    local Colors = GetScheme()

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width, height)
    container:SetBackdrop(BACKDROP_FLAT)
    container:SetBackdropColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, Colors.panel.a)
    container:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, Colors.border.a)

    -- Selected text
    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -20, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    VE.Theme.ApplyFont(text, Colors, "small")
    text:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
    container.text = text

    -- Arrow icon
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetAtlas("housing-floor-arrow-down-pressed")

    -- Dropdown menu (hidden by default)
    local menu = CreateFrame("Frame", nil, container, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -1)
    menu:SetPoint("TOPRIGHT", container, "BOTTOMRIGHT", 0, -1)
    menu:SetBackdrop(BACKDROP_FLAT)
    menu:SetBackdropColor(Colors.bg.r, Colors.bg.g, Colors.bg.b, Colors.bg.a)
    menu:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, Colors.border.a)
    menu:SetFrameStrata("TOOLTIP")
    menu:Hide()
    container.menu = menu

    local menuItems = {}
    container.menuItems = menuItems
    container.selectedKey = nil
    container.onSelect = options.onSelect

    function container:SetItems(items)
        -- Clear existing
        for _, item in ipairs(self.menuItems) do
            item:Hide()
            item:SetParent(nil)
        end
        self.menuItems = {}

        local yOffset = -2
        local itemHeight = 20

        for _, itemData in ipairs(items) do
            local item = CreateFrame("Button", nil, self.menu)
            item:SetHeight(itemHeight)
            item:SetPoint("TOPLEFT", 2, yOffset)
            item:SetPoint("TOPRIGHT", -2, yOffset)

            local itemText = item:CreateFontString(nil, "OVERLAY")
            itemText:SetPoint("LEFT", 6, 0)
            VE.Theme.ApplyFont(itemText, Colors, "small")
            itemText:SetText(itemData.label or itemData.key)
            itemText:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
            item.text = itemText

            item.key = itemData.key
            item.data = itemData

            item:SetScript("OnClick", function(self)
                container:SetSelected(self.key, self.data)
                container.menu:Hide()
                if container.onSelect then
                    container.onSelect(self.key, self.data)
                end
            end)

            item:SetScript("OnEnter", function(self)
                local C = VE.Constants:GetThemeColors()
                self.text:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
            end)
            item:SetScript("OnLeave", function(self)
                local C = VE.Constants:GetThemeColors()
                self.text:SetTextColor(C.text.r, C.text.g, C.text.b)
            end)

            table.insert(self.menuItems, item)
            yOffset = yOffset - itemHeight
        end

        -- Calculate menu width to fit longest item
        local maxTextWidth = width - 4 -- minimum = container width minus borders
        for _, item in ipairs(self.menuItems) do
            local textWidth = item.text:GetStringWidth() + 16 -- padding for text
            if textWidth > maxTextWidth then
                maxTextWidth = textWidth
            end
        end

        -- Clear right anchor and set explicit width for menu
        self.menu:ClearAllPoints()
        self.menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
        self.menu:SetWidth(maxTextWidth)
        self.menu:SetHeight(math.abs(yOffset) + 4)
    end

    function container:SetSelected(key, data)
        self.selectedKey = key
        if data and data.label then
            self.text:SetText(data.label)
        else
            self.text:SetText(key or "")
        end
    end

    function container:GetSelected()
        return self.selectedKey
    end

    -- Toggle menu on click
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
        else
            self.menu:Show()
        end
    end)

    -- Close menu when clicking elsewhere
    menu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)

    -- Register with theme engine
    RegisterWidget(container, "Dropdown")

    return container
end

-- ============================================================================
-- SECTION HEADER
-- ============================================================================

function VE.UI:CreateSectionHeader(parent, text)
    local Colors = GetScheme()

    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(18)

    -- Background texture (atlas for Housing Theme)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if Colors.atlas and Colors.atlas.sectionHeaderBg then
        bg:SetAtlas(Colors.atlas.sectionHeaderBg)
    else
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, 0.3)
    end
    header.bg = bg

    -- Border for non-atlas themes (1px edge)
    local border = header:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(Colors.border.r, Colors.border.g, Colors.border.b, 0.5)
    header.border = border

    -- Inner background (slightly inset for border effect)
    local innerBg = header:CreateTexture(nil, "ARTWORK", nil, -1)
    innerBg:SetPoint("TOPLEFT", 1, -1)
    innerBg:SetPoint("BOTTOMRIGHT", -1, 1)
    innerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerBg:SetVertexColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, 0.3)
    header.innerBg = innerBg

    -- Hide border elements for atlas themes
    if Colors.atlas and Colors.atlas.sectionHeaderBg then
        border:Hide()
        innerBg:Hide()
    end

    -- Drop shadow (rendered behind main label)
    local shadow = header:CreateFontString(nil, "ARTWORK")
    shadow:SetPoint("CENTER", 1, 1)  -- Offset down-right for shadow effect
    shadow:SetJustifyH("CENTER")
    VE.Theme.ApplyFont(shadow, Colors, "small")
    shadow:SetText(text)
    shadow:SetTextColor(0, 0, 0, 0.6)  -- Black with transparency
    header.shadow = shadow

    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", 0, 2)  -- 2px higher
    label:SetJustifyH("CENTER")
    VE.Theme.ApplyFont(label, Colors, "small")
    label:SetText(text)
    label:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b)
    header.label = label

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(8)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", -4, 0)
    line:SetAtlas("housing-bulletinboard-list-header-decorative-line")
    line:Hide()  -- Hidden by default (centered text doesn't use line)
    header.line = line

    -- Decorative foliage (Housing Theme only) - spills below header
    -- Layer order: BACKGROUND (bg) → BORDER (foliage) → OVERLAY (text/icons)
    local foliageLeft = header:CreateTexture(nil, "BORDER")
    foliageLeft:SetAtlas("housing-decorative-foliage-left")
    foliageLeft:SetPoint("BOTTOMLEFT", 0, -8)  -- Anchor at bottom, spills down
    foliageLeft:SetSize(32, 32)
    header.foliageLeft = foliageLeft

    local foliageRight = header:CreateTexture(nil, "BORDER")
    foliageRight:SetAtlas("housing-decorative-foliage-right")
    foliageRight:SetPoint("BOTTOMRIGHT", 0, -8)  -- Anchor at bottom, spills down
    foliageRight:SetSize(32, 32)
    header.foliageRight = foliageRight

    -- Only show foliage for Housing Theme
    if not (Colors.atlas and Colors.atlas.sectionHeaderBg) then
        foliageLeft:Hide()
        foliageRight:Hide()
    end

    -- Register with theme engine
    RegisterWidget(header, "SectionHeader")

    return header
end

-- ============================================================================
-- ATLAS BACKGROUND HELPER
-- ============================================================================

-- Adds atlas background support to a BackdropTemplate frame
-- Returns a function to apply colors based on current theme
function VE.UI:AddAtlasBackground(frame)
    local atlasBg = frame:CreateTexture(nil, "BACKGROUND")
    atlasBg:SetAllPoints()
    frame.atlasBg = atlasBg

    -- Return the apply function
    return function(opacityMultiplier)
        local C = GetScheme()
        opacityMultiplier = opacityMultiplier or 0.3
        if C.atlas and C.atlas.taskListBg then
            frame:SetBackdrop(nil)
            atlasBg:SetAtlas(C.atlas.taskListBg)
            atlasBg:SetAlpha(1)
            atlasBg:Show()
        else
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            frame:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * opacityMultiplier)
            atlasBg:Hide()
        end
    end
end

-- ============================================================================
-- SCROLL FRAME
-- ============================================================================

function VE.UI:CreateScrollFrame(parent)
    local Colors = GetScheme()

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 2)  -- -6 right inset leaves room for 8px scrollbar flush with container edge

    -- Style scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetWidth(8)

        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            if Colors.atlas and Colors.atlas.scrollThumb then
                thumb:SetAtlas(Colors.atlas.scrollThumb)
                thumb:SetVertexColor(1, 1, 1, 1)
            else
                thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
                thumb:SetVertexColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, 1)
            end
            thumb:SetSize(8, 40)
        end
        scrollBar.thumb = thumb  -- Store reference for theming

        -- Hide buttons
        if scrollBar.ScrollUpButton then
            scrollBar.ScrollUpButton:SetAlpha(0)
            scrollBar.ScrollUpButton:EnableMouse(false)
        end
        if scrollBar.ScrollDownButton then
            scrollBar.ScrollDownButton:SetAlpha(0)
            scrollBar.ScrollDownButton:EnableMouse(false)
        end
    end

    -- Content container
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1) -- Will be updated
    scrollFrame:SetScrollChild(content)
    scrollFrame.content = content

    -- Register with theme engine
    RegisterWidget(scrollFrame, "ScrollFrame")

    return scrollFrame, content
end

-- ============================================================================
-- SET AS ACTIVE BUTTON (for non-active house state)
-- ============================================================================

function VE.UI:CreateSetAsActiveButton(parent, anchorTo, options)
    options = options or {}
    local Colors = GetScheme()
    local UI = VE.Constants.UI

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(UI.setActiveButtonWidth, UI.setActiveButtonHeight)
    btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, UI.setActiveButtonOffset)
    btn:SetText("Set as Active")

    btn:SetScript("OnClick", function()
        if options.onBeforeClick then
            options.onBeforeClick()
        end
        local tracker = VE.EndeavorTracker
        if tracker then
            tracker:SetAsActiveEndeavor()
        end
    end)

    -- Apply font styling
    local fs = btn:GetFontString()
    if fs and VE.Theme and VE.Theme.ApplyFont then
        VE.Theme.ApplyFont(fs, Colors)
    end

    RegisterWidget(btn, "Button")
    return btn
end

-- ============================================================================
-- EMPTY STATE VIEW (for tabs with no data)
-- ============================================================================

function VE.UI:CreateEmptyStateView(parent, options)
    options = options or {}
    local Colors = GetScheme()

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    -- Empty text
    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", 0, 20)
    if VE.Theme and VE.Theme.ApplyFont then
        VE.Theme.ApplyFont(text, Colors)
    end
    text:SetText(options.message or "No data available.")
    container.text = text
    RegisterWidget(text, "Text")

    -- Optional Set as Active button
    if options.showSetActiveButton then
        local btn = self:CreateSetAsActiveButton(container, text, {
            onBeforeClick = options.onSetActiveClick
        })
        container.button = btn
    end

    function container:SetMessage(msg)
        self.text:SetText(msg)
    end

    function container:ShowButton()
        if self.button then self.button:Show() end
    end

    function container:HideButton()
        if self.button then self.button:Hide() end
    end

    return container
end

-- ============================================================================
-- UTILITY: Color code for text
-- ============================================================================

function VE.UI:ColorCode(colorName)
    local Colors = GetScheme()
    local color = Colors[colorName]
    if color then
        if color.hex then
            return "|cFF" .. color.hex
        else
            -- Generate hex from RGB
            local hex = string.format("%02x%02x%02x", math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255))
            return "|cFF" .. hex
        end
    end
    return "|cFFffffff"
end

-- ============================================================================
-- CSV EXPORT WINDOW
-- ============================================================================

function VE.UI:ShowCSVExportWindow(csvText, rowCount)
    local Colors = GetScheme()

    -- Reuse existing window or create new
    if not VE.csvExportWindow then
        local window = CreateFrame("Frame", "VE_CSVExportWindow", UIParent, "BackdropTemplate")
        window:SetSize(500, 400)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetClampedToScreen(true)

        -- Title bar
        local titleBar = CreateFrame("Frame", nil, window)
        titleBar:SetHeight(24)
        titleBar:SetPoint("TOPLEFT", 0, 0)
        titleBar:SetPoint("TOPRIGHT", 0, 0)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

        local titleText = titleBar:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", 10, 0)
        titleText:SetFont(STANDARD_TEXT_FONT, 12, "")
        window.titleText = titleText

        -- Close button
        local closeBtn = CreateFrame("Button", nil, titleBar)
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("RIGHT", -4, 0)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() window:Hide() end)

        -- Instructions
        local instructions = window:CreateFontString(nil, "OVERLAY")
        instructions:SetPoint("TOPLEFT", 10, -30)
        instructions:SetFont(STANDARD_TEXT_FONT, 10, "")
        instructions:SetText("Select all (Ctrl+A) and copy (Ctrl+C) to paste into Excel or a text file:")
        window.instructions = instructions

        -- Scroll frame for edit box
        local scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 10, -50)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

        -- Edit box (copyable text)
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(440)
        editBox:EnableMouse(true)
        editBox:SetScript("OnEscapePressed", function() window:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        window.editBox = editBox

        VE.csvExportWindow = window
    end

    local window = VE.csvExportWindow

    -- Apply current theme colors
    window:SetBackdropColor(Colors.bg.r, Colors.bg.g, Colors.bg.b, 0.98)
    window:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, 1)
    window.titleText:SetText("Activity Export (" .. rowCount .. " entries)")
    window.titleText:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
    window.instructions:SetTextColor(Colors.text_dim.r, Colors.text_dim.g, Colors.text_dim.b)

    -- Set the CSV content
    window.editBox:SetText(csvText)
    window.editBox:HighlightText()
    window.editBox:SetFocus()

    window:Show()
end
