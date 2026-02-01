-- ============================================================================
-- Vamoose's Endeavors - Config Tab
-- Settings panel for addon configuration
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Helper to get current theme colors
local function GetColors()
    return VE.Constants:GetThemeColors()
end

function VE.UI.Tabs:CreateConfig(parent)
    local UI = VE.Constants.UI

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = 0  -- Container edge padding (0 for full-bleed atlas backgrounds)

    -- ========================================================================
    -- HEADER
    -- ========================================================================

    local header = VE.UI:CreateSectionHeader(container, "Settings")
    header:SetPoint("TOPLEFT", 0, UI.sectionHeaderYOffset)
    header:SetPoint("TOPRIGHT", 0, UI.sectionHeaderYOffset)

    -- ========================================================================
    -- SCROLLABLE SETTINGS CONTAINER
    -- ========================================================================

    local scrollContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    scrollContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    scrollContainer:SetPoint("BOTTOMRIGHT", -padding, padding)
    scrollContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.scrollContainer = scrollContainer

    -- Atlas background support
    local ApplyPanelColors = VE.UI:AddAtlasBackground(scrollContainer)
    ApplyPanelColors()

    local _, scrollContent = VE.UI:CreateScrollFrame(scrollContainer)
    container.scrollContent = scrollContent

    -- Settings panel is now inside scroll content
    local settingsPanel = scrollContent
    container.settingsPanel = settingsPanel

    local yOffset = -12

    -- ========================================================================
    -- DISCORD LINK (at top)
    -- ========================================================================

    local DISCORD_INVITE = "https://discord.gg/RWZaxJaHFP"

    local discordRow = CreateFrame("Frame", nil, settingsPanel)
    discordRow:SetHeight(24)
    discordRow:SetPoint("TOPLEFT", 12, yOffset)
    discordRow:SetPoint("TOPRIGHT", -12, yOffset)

    local discordColors = GetColors()

    -- Discord icon
    local discordIcon = discordRow:CreateTexture(nil, "ARTWORK")
    discordIcon:SetSize(20, 20)
    discordIcon:SetPoint("LEFT", 0, 0)
    discordIcon:SetTexture("Interface\\AddOns\\VamoosesEndeavors\\Textures\\discord")
    discordRow.icon = discordIcon

    -- Discord link edit box (copyable, auto-selects on click)
    local discordEditBox = CreateFrame("EditBox", nil, discordRow, "BackdropTemplate")
    discordEditBox:SetSize(160, 22)
    discordEditBox:SetPoint("LEFT", discordIcon, "RIGHT", 6, 0)
    discordEditBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    discordEditBox:SetBackdropColor(discordColors.panel.r, discordColors.panel.g, discordColors.panel.b, 0.8)
    discordEditBox:SetBackdropBorderColor(0.35, 0.40, 0.98, 0.6)  -- Discord blurple border
    discordEditBox:SetFontObject("GameFontHighlight")
    discordEditBox:SetText(DISCORD_INVITE)
    discordEditBox:SetAutoFocus(false)
    discordEditBox:SetTextInsets(8, 8, 0, 0)
    discordEditBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    discordEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    discordEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    discordRow.editBox = discordEditBox
    container.discordEditBox = discordEditBox

    -- Copy hint
    local discordHint = discordRow:CreateFontString(nil, "OVERLAY")
    discordHint:SetPoint("LEFT", discordEditBox, "RIGHT", 6, 0)
    VE.Theme.ApplyFont(discordHint, discordColors, "small")
    discordHint:SetText("Ctrl+C")
    discordHint:SetTextColor(discordColors.text_dim.r, discordColors.text_dim.g, discordColors.text_dim.b, 0.7)
    discordRow.hint = discordHint
    container.discordHint = discordHint

    yOffset = yOffset - 32

    -- Track checkbox rows for theme updates
    container.checkboxRows = {}

    -- Helper to create a checkbox row
    local function CreateCheckbox(labelText, configKey, description)
        local C = GetColors()
        local row = CreateFrame("Frame", nil, settingsPanel)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 12, yOffset)
        row:SetPoint("TOPRIGHT", -12, yOffset)

        -- Checkbox button
        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("LEFT", 0, 0)

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
        VE.Theme.ApplyFont(label, C)
        label:SetText(labelText)
        label:SetTextColor(C.text.r, C.text.g, C.text.b)
        row.label = label

        -- Description (smaller, dimmer)
        if description then
            local desc = row:CreateFontString(nil, "OVERLAY")
            desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
            VE.Theme.ApplyFont(desc, C, "small")
            desc:SetText(description)
            desc:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
            row:SetHeight(40)
            row.desc = desc
            yOffset = yOffset - 44
        else
            yOffset = yOffset - 28
        end

        -- Get/Set from state
        local state = VE.Store:GetState()
        checkbox:SetChecked(state.config[configKey])

        checkbox:SetScript("OnClick", function(self)
            VE.Store:Dispatch("SET_CONFIG", {
                key = configKey,
                value = self:GetChecked()
            })

            -- Special handling for minimap button
            if configKey == "showMinimapButton" then
                if VE.Minimap then
                    VE.Minimap:UpdateVisibility()
                end
            end

            -- Special handling for dashboard button
            if configKey == "showDashboardButton" then
                if VE.UpdateDashboardButtonVisibility then
                    VE:UpdateDashboardButtonVisibility()
                end
            end
        end)

        row.checkbox = checkbox

        -- Add update function for theme changes
        function row:UpdateColors()
            local colors = GetColors()
            self.label:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(self.label, colors)
            if self.desc then
                self.desc:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
                VE.Theme.ApplyFont(self.desc, colors, "small")
            end
        end

        table.insert(container.checkboxRows, row)
        return row
    end

    -- Minimap Button checkbox
    CreateCheckbox("Show Minimap Button", "showMinimapButton", "Toggle the minimap button visibility")

    -- Dashboard Button checkbox
    CreateCheckbox("Show Dashboard Button", "showDashboardButton", "Toggle the VE button in Housing Dashboard")

    -- Debug Mode checkbox
    CreateCheckbox("Debug Mode", "debug", "Show debug messages in chat")

    -- ========================================================================
    -- ALT SHARING SECTION
    -- ========================================================================

    yOffset = yOffset - 4

    local altSharingHeader = VE.UI:CreateSectionHeader(settingsPanel, "Alt Sharing")
    altSharingHeader:SetPoint("TOPLEFT", 0, yOffset)
    altSharingHeader:SetPoint("TOPRIGHT", 0, yOffset)
    container.altSharingHeader = altSharingHeader

    yOffset = yOffset - 10

    -- Consent checkbox
    local altShareRow = CreateFrame("Frame", nil, settingsPanel)
    altShareRow:SetHeight(50)
    altShareRow:SetPoint("TOPLEFT", 12, yOffset)
    altShareRow:SetPoint("TOPRIGHT", -12, yOffset)

    local altShareColors = GetColors()
    local altShareCheckbox = CreateFrame("CheckButton", nil, altShareRow, "ChatConfigCheckButtonTemplate")
    altShareCheckbox:SetPoint("LEFT", 0, 0)
    altShareCheckbox:SetSize(24, 24)
    altShareCheckbox:SetHitRectInsets(0, -100, 0, 0)

    local altShareLabel = altShareRow:CreateFontString(nil, "OVERLAY")
    altShareLabel:SetPoint("LEFT", altShareCheckbox, "RIGHT", 6, 0)
    VE.Theme.ApplyFont(altShareLabel, altShareColors)
    altShareLabel:SetText("Share my alts with guildmates")
    altShareLabel:SetTextColor(altShareColors.text.r, altShareColors.text.g, altShareColors.text.b)
    altShareRow.label = altShareLabel

    local altShareDesc = altShareRow:CreateFontString(nil, "OVERLAY")
    altShareDesc:SetPoint("TOPLEFT", altShareLabel, "BOTTOMLEFT", 0, -2)
    altShareDesc:SetWidth(240)
    altShareDesc:SetWordWrap(true)
    VE.Theme.ApplyFont(altShareDesc, altShareColors, "small")
    altShareDesc:SetText("Enables grouped leaderboard view with guildmates who also use this addon")
    altShareDesc:SetTextColor(altShareColors.text_dim.r, altShareColors.text_dim.g, altShareColors.text_dim.b)
    altShareRow.desc = altShareDesc

    -- Get/Set from state
    local altShareState = VE.Store:GetState()
    altShareCheckbox:SetChecked(altShareState.altSharing.enabled)

    altShareCheckbox:SetScript("OnClick", function(self)
        VE.Store:Dispatch("SET_ALT_SHARING_ENABLED", { enabled = self:GetChecked() })
    end)

    function altShareRow:UpdateColors()
        local colors = GetColors()
        self.label:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
        VE.Theme.ApplyFont(self.label, colors)
        self.desc:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
        VE.Theme.ApplyFont(self.desc, colors, "small")
    end

    container.altShareRow = altShareRow
    table.insert(container.checkboxRows, altShareRow)

    yOffset = yOffset - 60

    -- Group by account checkbox
    local groupByAccountRow = CreateFrame("Frame", nil, settingsPanel)
    groupByAccountRow:SetHeight(24)
    groupByAccountRow:SetPoint("TOPLEFT", 12, yOffset)
    groupByAccountRow:SetPoint("TOPRIGHT", -12, yOffset)

    local groupByAccountColors = GetColors()
    local groupByAccountCheckbox = CreateFrame("CheckButton", nil, groupByAccountRow, "ChatConfigCheckButtonTemplate")
    groupByAccountCheckbox:SetPoint("LEFT", 0, 0)
    groupByAccountCheckbox:SetSize(24, 24)
    groupByAccountCheckbox:SetHitRectInsets(0, -150, 0, 0)

    local groupByAccountLabel = groupByAccountRow:CreateFontString(nil, "OVERLAY")
    groupByAccountLabel:SetPoint("LEFT", groupByAccountCheckbox, "RIGHT", 6, 0)
    VE.Theme.ApplyFont(groupByAccountLabel, groupByAccountColors)
    groupByAccountLabel:SetText("Group by account in rankings")
    groupByAccountLabel:SetTextColor(groupByAccountColors.text.r, groupByAccountColors.text.g, groupByAccountColors.text.b)
    groupByAccountRow.label = groupByAccountLabel

    -- Get/Set from state
    local groupByAccountState = VE.Store:GetState()
    groupByAccountCheckbox:SetChecked(groupByAccountState.altSharing.groupingMode == "byMain")

    groupByAccountCheckbox:SetScript("OnClick", function(self)
        local newMode = self:GetChecked() and "byMain" or "individual"
        VE.Store:Dispatch("SET_GROUPING_MODE", { mode = newMode })
        VE.EventBus:Trigger("VE_ALT_MAPPING_UPDATED")  -- Update leaderboard button and refresh
    end)

    function groupByAccountRow:UpdateColors()
        local colors = GetColors()
        self.label:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
        VE.Theme.ApplyFont(self.label, colors)
    end

    container.groupByAccountRow = groupByAccountRow
    container.groupByAccountCheckbox = groupByAccountCheckbox
    table.insert(container.checkboxRows, groupByAccountRow)

    yOffset = yOffset - 32

    -- Main Character dropdown
    local mainCharRow = CreateFrame("Frame", nil, settingsPanel)
    mainCharRow:SetHeight(24)
    mainCharRow:SetPoint("TOPLEFT", 12, yOffset)
    mainCharRow:SetPoint("TOPRIGHT", -12, yOffset)

    local mainCharColors = GetColors()
    local mainCharLabel = mainCharRow:CreateFontString(nil, "OVERLAY")
    mainCharLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(mainCharLabel, mainCharColors)
    mainCharLabel:SetText("Main Character")
    mainCharLabel:SetTextColor(mainCharColors.text.r, mainCharColors.text.g, mainCharColors.text.b)
    mainCharRow.label = mainCharLabel

    local mainCharDropdown = VE.UI:CreateDropdown(mainCharRow, {
        width = 140,
        height = 22,
        onSelect = function(key, data)
            local mainChar = key ~= "" and key or nil
            VE.Store:Dispatch("SET_MAIN_CHARACTER", { mainCharacter = mainChar })
            -- Trigger re-broadcast
            if VE.AltSharing and VE.AltSharing.BroadcastIfEnabled then
                VE.AltSharing:BroadcastIfEnabled()
            end
        end
    })
    mainCharDropdown:SetPoint("RIGHT", 0, 0)
    mainCharRow.dropdown = mainCharDropdown

    -- Populate with characters
    local function PopulateMainCharDropdown()
        local items = {{ key = "", label = "(Use current)" }}
        local state = VE.Store:GetState()
        for charKey, charData in pairs(state.characters) do
            if charData.name and charData.realm then
                local realmNorm = charData.realm:gsub("%s", "")
                local fullKey = charData.name .. "-" .. realmNorm
                table.insert(items, { key = fullKey, label = charData.name })
            end
        end
        mainCharDropdown:SetItems(items)

        local currentMain = state.altSharing.mainCharacter
        if currentMain then
            local displayName = currentMain:match("^([^-]+)") or currentMain
            mainCharDropdown:SetSelected(currentMain, { label = displayName })
        else
            mainCharDropdown:SetSelected("", { label = "(Use current)" })
        end
    end
    PopulateMainCharDropdown()

    container.mainCharLabel = mainCharLabel
    container.mainCharDropdown = mainCharDropdown

    yOffset = yOffset - 32

    -- Privacy note
    local privacyNote = settingsPanel:CreateFontString(nil, "OVERLAY")
    privacyNote:SetPoint("TOPLEFT", 12, yOffset)
    privacyNote:SetWidth(290)
    privacyNote:SetWordWrap(true)
    VE.Theme.ApplyFont(privacyNote, mainCharColors, "small")
    privacyNote:SetText("When enabled, your character names are shared with guildmates via hidden addon communication.")
    privacyNote:SetTextColor(mainCharColors.text_dim.r, mainCharColors.text_dim.g, mainCharColors.text_dim.b)
    container.privacyNote = privacyNote

    yOffset = yOffset - 44

    -- ========================================================================
    -- APPEARANCE SECTION
    -- ========================================================================

    local appearanceHeader = VE.UI:CreateSectionHeader(settingsPanel, "Appearance")
    appearanceHeader:SetPoint("TOPLEFT", 0, yOffset)
    appearanceHeader:SetPoint("TOPRIGHT", 0, yOffset)
    container.appearanceHeader = appearanceHeader

    yOffset = yOffset - 20

    local themeRow = CreateFrame("Frame", nil, settingsPanel)
    themeRow:SetHeight(24)
    themeRow:SetPoint("TOPLEFT", 12, yOffset)
    themeRow:SetPoint("TOPRIGHT", -12, yOffset)

    local themeColors = GetColors()
    local themeLabel = themeRow:CreateFontString(nil, "OVERLAY")
    themeLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(themeLabel, themeColors)
    themeLabel:SetText("Theme")
    themeLabel:SetTextColor(themeColors.text.r, themeColors.text.g, themeColors.text.b)
    themeRow.label = themeLabel

    local themeDropdown = VE.UI:CreateDropdown(themeRow, {
        width = 160,
        height = 22,
        onSelect = function(key, data)
            -- Update theme
            VE.Store:Dispatch("SET_CONFIG", { key = "theme", value = key })
            VE.Constants:ApplyTheme()

            -- Trigger theme update event
            local themeName = VE.Constants.ThemeNames[key] or "SolarizedDark"
            VE.EventBus:Trigger("VE_THEME_UPDATE", { themeName = themeName })

            print("|cFF2aa198[VE]|r Theme switched to " .. (data.label or key))
        end
    })
    themeDropdown:SetPoint("RIGHT", 0, 0)
    themeRow.dropdown = themeDropdown

    -- Build theme options from ThemeOrder
    local themeItems = {}
    for _, themeKey in ipairs(VE.Constants.ThemeOrder) do
        table.insert(themeItems, {
            key = themeKey,
            label = VE.Constants.ThemeDisplayNames[themeKey] or themeKey
        })
    end
    themeDropdown:SetItems(themeItems)

    -- Set current theme as selected
    local currentTheme = VE.Constants:GetCurrentTheme()
    local currentDisplayName = VE.Constants.ThemeDisplayNames[currentTheme] or currentTheme
    themeDropdown:SetSelected(currentTheme, { label = currentDisplayName })

    container.themeDropdown = themeDropdown
    container.themeLabel = themeLabel

    yOffset = yOffset - 32

    -- ========================================================================
    -- FONT DROPDOWN
    -- ========================================================================

    local fontRow = CreateFrame("Frame", nil, settingsPanel)
    fontRow:SetHeight(24)
    fontRow:SetPoint("TOPLEFT", 12, yOffset)
    fontRow:SetPoint("TOPRIGHT", -12, yOffset)

    local fontColors = GetColors()
    local fontLabel = fontRow:CreateFontString(nil, "OVERLAY")
    fontLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(fontLabel, fontColors)
    fontLabel:SetText("Font")
    fontLabel:SetTextColor(fontColors.text.r, fontColors.text.g, fontColors.text.b)
    fontRow.label = fontLabel

    local fontDropdown = VE.UI:CreateDropdown(fontRow, {
        width = 160,
        height = 22,
        onSelect = function(key, data)
            VE.Store:Dispatch("SET_CONFIG", { key = "fontFamily", value = key })
            -- Trigger theme update to refresh all fonts
            VE.EventBus:Trigger("VE_THEME_UPDATE", { fontFamily = key })
            print("|cFF2aa198[VE]|r Font changed to " .. (data.label or key))
        end
    })
    fontDropdown:SetPoint("RIGHT", 0, 0)
    fontRow.dropdown = fontDropdown

    -- Build font options
    local fontItems = {}
    for _, fontKey in ipairs(VE.Constants.FontOrder) do
        table.insert(fontItems, {
            key = fontKey,
            label = VE.Constants.FontDisplayNames[fontKey] or fontKey
        })
    end
    fontDropdown:SetItems(fontItems)

    -- Set current font as selected
    local currentFont = VE.Store.state.config.fontFamily or "ARIALN"
    local currentFontName = VE.Constants.FontDisplayNames[currentFont] or currentFont
    fontDropdown:SetSelected(currentFont, { label = currentFontName })

    container.fontDropdown = fontDropdown
    container.fontLabel = fontLabel

    yOffset = yOffset - 32

    -- ========================================================================
    -- FONT SIZE CONTROLS
    -- ========================================================================

    local fontSizeRow = CreateFrame("Frame", nil, settingsPanel)
    fontSizeRow:SetHeight(24)
    fontSizeRow:SetPoint("TOPLEFT", 12, yOffset)
    fontSizeRow:SetPoint("TOPRIGHT", -12, yOffset)

    local fontSizeColors = GetColors()
    local fontSizeLabel = fontSizeRow:CreateFontString(nil, "OVERLAY")
    fontSizeLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(fontSizeLabel, fontSizeColors)
    fontSizeLabel:SetText("Font Size")
    fontSizeLabel:SetTextColor(fontSizeColors.text.r, fontSizeColors.text.g, fontSizeColors.text.b)
    fontSizeRow.label = fontSizeLabel

    -- Increase button (rightmost)
    local fontUpBtn = VE.UI:CreateButton(fontSizeRow, "+", 24, 22)
    fontUpBtn:SetPoint("RIGHT", 0, 0)

    -- Current scale display (left of + button)
    local scaleDisplay = fontSizeRow:CreateFontString(nil, "OVERLAY")
    scaleDisplay:SetPoint("RIGHT", fontUpBtn, "LEFT", -4, 0)
    scaleDisplay:SetWidth(32)
    scaleDisplay:SetJustifyH("CENTER")
    VE.Theme.ApplyFont(scaleDisplay, fontSizeColors)
    local currentScale = VE.Store.state.config.fontScale or 0
    scaleDisplay:SetText(currentScale >= 0 and ("+" .. currentScale) or tostring(currentScale))
    scaleDisplay:SetTextColor(fontSizeColors.accent.r, fontSizeColors.accent.g, fontSizeColors.accent.b)
    fontSizeRow.scaleDisplay = scaleDisplay

    -- Decrease button (left of display)
    local fontDownBtn = VE.UI:CreateButton(fontSizeRow, "-", 24, 22)
    fontDownBtn:SetPoint("RIGHT", scaleDisplay, "LEFT", -4, 0)
    fontDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.fontScale or 0
        local newScale = math.max(current - 2, -4)
        VE.Store:Dispatch("SET_FONT_SCALE", { scale = newScale })
        scaleDisplay:SetText(newScale >= 0 and ("+" .. newScale) or tostring(newScale))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)
    fontUpBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.fontScale or 0
        local newScale = math.min(current + 2, 8)
        VE.Store:Dispatch("SET_FONT_SCALE", { scale = newScale })
        scaleDisplay:SetText(newScale >= 0 and ("+" .. newScale) or tostring(newScale))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)

    container.fontSizeLabel = fontSizeLabel
    container.scaleDisplay = scaleDisplay

    yOffset = yOffset - 32

    -- ========================================================================
    -- UI SCALE CONTROLS
    -- ========================================================================

    local uiScaleRow = CreateFrame("Frame", nil, settingsPanel)
    uiScaleRow:SetHeight(24)
    uiScaleRow:SetPoint("TOPLEFT", 12, yOffset)
    uiScaleRow:SetPoint("TOPRIGHT", -12, yOffset)

    local uiScaleColors = GetColors()
    local uiScaleLabel = uiScaleRow:CreateFontString(nil, "OVERLAY")
    uiScaleLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(uiScaleLabel, uiScaleColors)
    uiScaleLabel:SetText("UI Scale")
    uiScaleLabel:SetTextColor(uiScaleColors.text.r, uiScaleColors.text.g, uiScaleColors.text.b)
    uiScaleRow.label = uiScaleLabel

    -- Increase button (rightmost)
    local uiScaleUpBtn = VE.UI:CreateButton(uiScaleRow, "+", 24, 22)
    uiScaleUpBtn:SetPoint("RIGHT", 0, 0)

    -- Current scale display (left of + button)
    local uiScaleValue = uiScaleRow:CreateFontString(nil, "OVERLAY")
    uiScaleValue:SetPoint("RIGHT", uiScaleUpBtn, "LEFT", -4, 0)
    uiScaleValue:SetWidth(36)
    uiScaleValue:SetJustifyH("CENTER")
    VE.Theme.ApplyFont(uiScaleValue, uiScaleColors)
    local currentUIScale = VE.Store.state.config.uiScale or 1.0
    uiScaleValue:SetText(string.format("%.0f%%", currentUIScale * 100))
    uiScaleValue:SetTextColor(uiScaleColors.accent.r, uiScaleColors.accent.g, uiScaleColors.accent.b)
    uiScaleRow.scaleValue = uiScaleValue

    -- Decrease button (left of display)
    local uiScaleDownBtn = VE.UI:CreateButton(uiScaleRow, "-", 24, 22)
    uiScaleDownBtn:SetPoint("RIGHT", uiScaleValue, "LEFT", -4, 0)
    uiScaleDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.uiScale or 1.0
        local newScale = math.max(current - 0.1, 0.8)
        newScale = math.floor(newScale * 10 + 0.5) / 10  -- Round to 1 decimal
        VE.Store:Dispatch("SET_UI_SCALE", { scale = newScale })
        uiScaleValue:SetText(string.format("%.0f%%", newScale * 100))
        VE.EventBus:Trigger("VE_UI_SCALE_UPDATE", {})
    end)
    uiScaleUpBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.uiScale or 1.0
        local newScale = math.min(current + 0.1, 1.4)
        newScale = math.floor(newScale * 10 + 0.5) / 10  -- Round to 1 decimal
        VE.Store:Dispatch("SET_UI_SCALE", { scale = newScale })
        uiScaleValue:SetText(string.format("%.0f%%", newScale * 100))
        VE.EventBus:Trigger("VE_UI_SCALE_UPDATE", {})
    end)

    container.uiScaleLabel = uiScaleLabel
    container.uiScaleValue = uiScaleValue

    yOffset = yOffset - 32

    -- ========================================================================
    -- TRANSPARENCY CONTROLS
    -- ========================================================================

    local opacityRow = CreateFrame("Frame", nil, settingsPanel)
    opacityRow:SetHeight(24)
    opacityRow:SetPoint("TOPLEFT", 12, yOffset)
    opacityRow:SetPoint("TOPRIGHT", -12, yOffset)

    local opacityColors = GetColors()
    local opacityLabel = opacityRow:CreateFontString(nil, "OVERLAY")
    opacityLabel:SetPoint("LEFT", 0, 0)
    VE.Theme.ApplyFont(opacityLabel, opacityColors)
    opacityLabel:SetText("Transparency")
    opacityLabel:SetTextColor(opacityColors.text.r, opacityColors.text.g, opacityColors.text.b)
    opacityRow.label = opacityLabel

    -- Increase button (rightmost)
    local opacityUpBtn = VE.UI:CreateButton(opacityRow, "+", 24, 22)
    opacityUpBtn:SetPoint("RIGHT", 0, 0)

    -- Current opacity display (left of + button)
    local opacityValue = opacityRow:CreateFontString(nil, "OVERLAY")
    opacityValue:SetPoint("RIGHT", opacityUpBtn, "LEFT", -4, 0)
    opacityValue:SetWidth(36)
    opacityValue:SetJustifyH("CENTER")
    VE.Theme.ApplyFont(opacityValue, opacityColors)
    local currentOpacity = VE.Store.state.config.bgOpacity or 0.9
    opacityValue:SetText(string.format("%.0f%%", currentOpacity * 100))
    opacityValue:SetTextColor(opacityColors.accent.r, opacityColors.accent.g, opacityColors.accent.b)
    opacityRow.opacityValue = opacityValue

    -- Decrease button (left of display)
    local opacityDownBtn = VE.UI:CreateButton(opacityRow, "-", 24, 22)
    opacityDownBtn:SetPoint("RIGHT", opacityValue, "LEFT", -4, 0)
    opacityDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.bgOpacity or 0.9
        local newOpacity = math.max(current - 0.1, 0.3)
        newOpacity = math.floor(newOpacity * 10 + 0.5) / 10
        VE.Store:Dispatch("SET_BG_OPACITY", { opacity = newOpacity })
        opacityValue:SetText(string.format("%.0f%%", newOpacity * 100))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)
    opacityUpBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.bgOpacity or 0.9
        local newOpacity = math.min(current + 0.1, 1.0)
        newOpacity = math.floor(newOpacity * 10 + 0.5) / 10
        VE.Store:Dispatch("SET_BG_OPACITY", { opacity = newOpacity })
        opacityValue:SetText(string.format("%.0f%%", newOpacity * 100))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)

    container.opacityLabel = opacityLabel
    container.opacityValue = opacityValue

    yOffset = yOffset - 20

    -- ========================================================================
    -- VERSION INFO (inside scroll content)
    -- ========================================================================

    local C = GetColors()
    local versionInfo = settingsPanel:CreateFontString(nil, "OVERLAY")
    versionInfo:SetPoint("TOPLEFT", 12, yOffset)
    VE.Theme.ApplyFont(versionInfo, C, "small")
    local version = C_AddOns.GetAddOnMetadata("VamoosesEndeavors", "Version") or "Dev"
    versionInfo:SetText("Version " .. version .. " | C_NeighborhoodInitiative API")
    versionInfo:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    container.versionInfo = versionInfo

    yOffset = yOffset - 14

    -- Font credit
    local fontCredit = settingsPanel:CreateFontString(nil, "OVERLAY")
    fontCredit:SetPoint("TOPLEFT", 12, yOffset)
    VE.Theme.ApplyFont(fontCredit, C, "small")
    fontCredit:SetText("Expressway font by Typodermic Fonts")
    fontCredit:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
    container.fontCredit = fontCredit

    -- Set scroll content height
    yOffset = yOffset - 20
    scrollContent:SetHeight(math.abs(yOffset))

    -- Listen for theme updates to refresh colors
    VE.EventBus:Register("VE_THEME_UPDATE", function()
        ApplyPanelColors()
        local colors = GetColors()
        if container.versionInfo then
            container.versionInfo:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.versionInfo, colors, "small")
        end
        if container.fontCredit then
            container.fontCredit:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.fontCredit, colors, "small")
        end
        for _, row in ipairs(container.checkboxRows) do
            row:UpdateColors()
        end
        if container.themeLabel then
            container.themeLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.themeLabel, colors)
        end
        if container.fontLabel then
            container.fontLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.fontLabel, colors)
        end
        if container.fontSizeLabel then
            container.fontSizeLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.fontSizeLabel, colors)
        end
        if container.scaleDisplay then
            container.scaleDisplay:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b)
            VE.Theme.ApplyFont(container.scaleDisplay, colors)
        end
        if container.uiScaleLabel then
            container.uiScaleLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.uiScaleLabel, colors)
        end
        if container.uiScaleValue then
            container.uiScaleValue:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b)
            VE.Theme.ApplyFont(container.uiScaleValue, colors)
        end
        if container.opacityLabel then
            container.opacityLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.opacityLabel, colors)
        end
        if container.opacityValue then
            container.opacityValue:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b)
            VE.Theme.ApplyFont(container.opacityValue, colors)
        end
        -- Alt sharing section theme updates
        if container.mainCharLabel then
            container.mainCharLabel:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.mainCharLabel, colors)
        end
        if container.privacyNote then
            container.privacyNote:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.privacyNote, colors, "small")
        end
        if container.discordEditBox then
            container.discordEditBox:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, 0.8)
        end
        if container.discordHint then
            container.discordHint:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, 0.7)
            VE.Theme.ApplyFont(container.discordHint, colors, "small")
        end
    end)

    -- Listen for grouping mode changes from leaderboard button
    VE.EventBus:Register("VE_GROUPING_MODE_CHANGED", function()
        if container.groupByAccountCheckbox then
            local state = VE.Store:GetState()
            container.groupByAccountCheckbox:SetChecked(state.altSharing.groupingMode == "byMain")
        end
    end)

    return container
end
