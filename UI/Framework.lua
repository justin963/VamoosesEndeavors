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

    ApplyTheme(frame, "Window")

    -- Title Bar
    local Colors = GetScheme()
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(18)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop(BACKDROP_BORDERLESS)
    titleBar:SetBackdropColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a * 0.3)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("CENTER", 0, 0)
    VE.Theme.ApplyFont(titleText, Colors, "small")
    titleText:SetText(title)
    titleText:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, Colors.accent.a)
    frame.titleText = titleText
    titleBar.titleText = titleText

    -- Register title bar for theming
    RegisterWidget(titleBar, "TitleBar")

    -- Refresh Button (top left, borderless)
    local refreshBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    refreshBtn:SetSize(50, 18)
    refreshBtn:SetPoint("LEFT", 0, 0)
    refreshBtn:SetBackdrop(BACKDROP_BORDERLESS)
    refreshBtn:SetBackdropColor(Colors.button_normal.r, Colors.button_normal.g, Colors.button_normal.b, Colors.button_normal.a)
    refreshBtn._scheme = Colors

    local refreshText = refreshBtn:CreateFontString(nil, "OVERLAY")
    refreshText:SetPoint("CENTER")
    VE.Theme.ApplyFont(refreshText, Colors, "small")
    refreshText:SetText("Refresh")
    refreshText:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b)
    refreshBtn.text = refreshText
    titleBar.refreshText = refreshText  -- Store for TitleBar skinner
    titleBar.refreshBtn = refreshBtn    -- Store for TitleBar skinner to update _scheme

    refreshBtn:SetScript("OnClick", function()
        if VE.EndeavorTracker then
            -- Refresh endeavor data
            VE.EndeavorTracker:FetchEndeavorData()
            -- Also request activity log refresh
            VE.EndeavorTracker:RequestActivityLog()
        end
        if VE.HousingTracker then
            -- Refresh housing data (coupons, house level)
            VE.HousingTracker:RequestHouseInfo()
            VE.HousingTracker:UpdateCoupons()
        end
        -- Refresh whichever tab is currently shown
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
        local c = self._scheme or GetScheme()
        self:SetBackdropColor(c.button_hover.r, c.button_hover.g, c.button_hover.b, c.button_hover.a)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Refresh", 1, 1, 1)
        GameTooltip:AddLine("Fetches latest endeavor data and rebuilds all UI elements", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)

    refreshBtn:SetScript("OnLeave", function(self)
        local c = self._scheme or GetScheme()
        self:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a)
        GameTooltip:Hide()
    end)

    -- Minimize Button (collapses task list)
    local minimizeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    minimizeBtn:SetSize(16, 16)
    minimizeBtn:SetPoint("RIGHT", -40, 0)
    ApplyTheme(minimizeBtn, "Button")

    local minimizeIcon = minimizeBtn:CreateFontString(nil, "OVERLAY")
    minimizeIcon:SetPoint("CENTER")
    VE.Theme.ApplyFont(minimizeIcon, Colors, "small")
    minimizeIcon:SetText("—")
    minimizeIcon:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b)
    minimizeBtn.icon = minimizeIcon
    titleBar.minimizeIcon = minimizeIcon  -- Store for TitleBar skinner

    frame.isMinimized = false
    frame.expandedHeight = UI.mainHeight

    minimizeBtn:SetScript("OnClick", function()
        frame.isMinimized = not frame.isMinimized
        if frame.isMinimized then
            -- Collapse to header only (title bar + tab bar + header section + stats row)
            frame:SetHeight(106)
            minimizeIcon:SetText("+")
            -- Hide content area
            if frame.content then
                frame.content:Hide()
            end
        else
            -- Expand to full height
            frame:SetHeight(frame.expandedHeight)
            minimizeIcon:SetText("—")
            -- Show content area
            if frame.content then
                frame.content:Show()
            end
        end
    end)

    minimizeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if frame.isMinimized then
            GameTooltip:AddLine("Expand", 1, 1, 1)
            GameTooltip:AddLine("Show task list", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("Minimize", 1, 1, 1)
            GameTooltip:AddLine("Collapse task list", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)

    minimizeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.minimizeBtn = minimizeBtn

    -- Theme Toggle Button (next to close)
    local themeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    themeBtn:SetSize(16, 16)
    themeBtn:SetPoint("RIGHT", -20, 0)
    ApplyTheme(themeBtn, "Button")

    local themeIcon = themeBtn:CreateFontString(nil, "OVERLAY")
    themeIcon:SetPoint("CENTER")
    VE.Theme.ApplyFont(themeIcon, Colors, "small")
    themeBtn.icon = themeIcon
    titleBar.themeIcon = themeIcon  -- Store for TitleBar skinner

    -- Update icon based on current theme
    local function UpdateThemeIcon()
        local c = GetScheme()
        themeIcon:SetText("T")
        themeIcon:SetTextColor(c.accent.r, c.accent.g, c.accent.b)
    end
    UpdateThemeIcon()

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
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Change Theme", 1, 1, 1)
        GameTooltip:AddLine("Next: " .. GetNextThemeDisplayName(), 0.7, 0.7, 0.7, true)
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
        ShowThemeTooltip(self)
    end)

    themeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.themeBtn = themeBtn
    frame.UpdateThemeIcon = UpdateThemeIcon

    -- Close Button (top right)
    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("RIGHT", -2, 0)
    ApplyTheme(closeBtn, "Button")

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetPoint("CENTER")
    VE.Theme.ApplyFont(closeText, Colors, "small")
    closeText:SetText("X")
    closeText:SetTextColor(Colors.error.r, Colors.error.g, Colors.error.b)
    closeBtn.text = closeText
    titleBar.closeText = closeText  -- Store for TitleBar skinner

    closeBtn:SetScript("OnClick", function() frame:Hide() end)

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

function VE.UI:CreateTabButton(parent, text)
    local Colors = GetScheme()
    local UI = VE.Constants.UI or {}
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(UI.tabWidth or 90, UI.tabHeight or 24)
    btn:SetBackdrop(BACKDROP_FLAT)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    VE.Theme.ApplyFont(label, Colors, "small")
    label:SetText(text)
    btn.label = label

    btn.isActive = false

    function btn:SetActive(active)
        self.isActive = active
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

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width, height)
    container:SetBackdrop(BACKDROP_FLAT)
    container:SetBackdropColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, Colors.panel.a)
    container:SetBackdropBorderColor(Colors.border.r, Colors.border.g, Colors.border.b, Colors.border.a)

    -- Fill bar
    local fill = container:CreateTexture(nil, "ARTWORK")
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetVertexColor(Colors.endeavor.r, Colors.endeavor.g, Colors.endeavor.b, Colors.endeavor.a)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMLEFT", 2, 2)
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
            local diamond = self:CreateTexture(nil, "OVERLAY")
            diamond:SetSize(VE.Constants.UI.milestoneSize, VE.Constants.UI.milestoneSize)
            diamond:SetTexture("Interface\\COMMON\\Indicator-Yellow")

            local xPos = (milestone.threshold / max) * barWidth
            diamond:SetPoint("CENTER", self, "LEFT", xPos + 2, 0)

            if milestone.reached then
                diamond:SetVertexColor(C.success.r, C.success.g, C.success.b, C.success.a)
            else
                diamond:SetVertexColor(C.text_dim.r, C.text_dim.g, C.text_dim.b, C.text_dim.a)
            end

            table.insert(self.milestones, diamond)
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

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(height)
    row:SetBackdrop(BACKDROP_BORDERLESS)
    row:SetBackdropColor(Colors.panel.r, Colors.panel.g, Colors.panel.b, Colors.panel.a * 0.5)

    -- Store scheme for hover scripts
    row._scheme = Colors

    -- Checkbox/status indicator
    local status = row:CreateTexture(nil, "ARTWORK")
    status:SetSize(14, 14)
    status:SetPoint("LEFT", 0, 0)
    status:SetTexture("Interface\\COMMON\\Indicator-Gray")
    row.status = status

    -- Repeatable indicator (circular arrow icon - replaces status for repeatable tasks)
    local repeatIcon = row:CreateTexture(nil, "ARTWORK")
    repeatIcon:SetSize(14, 14)
    repeatIcon:SetPoint("LEFT", 0, 0)
    repeatIcon:SetAtlas("UI-RefreshButton")
    repeatIcon:Hide()
    row.repeatIcon = repeatIcon

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
    couponBg:SetSize(26, 16)
    couponBg:SetPoint("RIGHT", 0, 0)
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
    pointsBg:SetSize(32, 16)
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

    -- Update function
    function row:SetTask(task)
        local C = GetScheme()  -- Re-fetch for current theme
        self.task = task
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
            self.name:SetPoint("LEFT", self.repeatIcon, "RIGHT", 4, 0)
            self.name:SetPoint("RIGHT", -100, 0)
        else
            self.repeatIcon:Hide()
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
    end

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
            -- Show times completed for repeatable tasks
            if self.task.isRepeatable and self.task.timesCompleted then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Completed: " .. self.task.timesCompleted .. " times", 0.5, 0.8, 0.5)
            end
            -- Show coupon reward info
            if self.task.couponReward and self.task.couponReward > 0 then
                GameTooltip:AddLine("Next reward: +" .. self.task.couponReward .. " coupons", c.accent.r, c.accent.g, c.accent.b)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        local c = self._scheme or GetScheme()
        self:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * 0.5)
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
    VE.Theme.ApplyFont(text, Colors, "small")
    text:SetTextColor(Colors.text.r, Colors.text.g, Colors.text.b)
    container.text = text

    -- Arrow
    local arrow = container:CreateFontString(nil, "OVERLAY")
    arrow:SetPoint("RIGHT", -6, 0)
    VE.Theme.ApplyFont(arrow, Colors, "small")
    arrow:SetText("v")
    arrow:SetTextColor(Colors.text_dim.r, Colors.text_dim.g, Colors.text_dim.b)

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

    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(label, Colors, "small")
    label:SetText(text)
    label:SetTextColor(Colors.accent.r, Colors.accent.g, Colors.accent.b)
    header.label = label

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", 0, 0)
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    line:SetVertexColor(Colors.text_dim.r, Colors.text_dim.g, Colors.text_dim.b, Colors.text_dim.a * 0.5)
    header.line = line

    -- Register with theme engine
    RegisterWidget(header, "SectionHeader")

    return header
end

-- ============================================================================
-- SCROLL FRAME
-- ============================================================================

function VE.UI:CreateScrollFrame(parent)
    local Colors = GetScheme()

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -1, 0)

    -- Style scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetWidth(8)

        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
            thumb:SetVertexColor(Colors.accent.r, Colors.accent.g, Colors.accent.b, 1)
            thumb:SetSize(6, 40)
        end

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
