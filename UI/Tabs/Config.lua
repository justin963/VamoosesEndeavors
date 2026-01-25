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
    -- THEME DROPDOWN
    -- ========================================================================

    yOffset = yOffset - 12  -- Extra spacing before theme section

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

    -- Decrease button (aligned with dropdown left edge)
    local fontDownBtn = VE.UI:CreateButton(fontSizeRow, "-", 24, 22)
    fontDownBtn:SetPoint("RIGHT", -136, 0)

    -- Current scale display (centered between buttons)
    local scaleDisplay = fontSizeRow:CreateFontString(nil, "OVERLAY")
    scaleDisplay:SetPoint("CENTER", fontSizeRow, "RIGHT", -80, 0)
    VE.Theme.ApplyFont(scaleDisplay, fontSizeColors)
    local currentScale = VE.Store.state.config.fontScale or 0
    scaleDisplay:SetText(currentScale >= 0 and ("+" .. currentScale) or tostring(currentScale))
    scaleDisplay:SetTextColor(fontSizeColors.accent.r, fontSizeColors.accent.g, fontSizeColors.accent.b)
    fontSizeRow.scaleDisplay = scaleDisplay
    fontDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.fontScale or 0
        local newScale = math.max(current - 2, -4)
        VE.Store:Dispatch("SET_FONT_SCALE", { scale = newScale })
        scaleDisplay:SetText(newScale >= 0 and ("+" .. newScale) or tostring(newScale))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)

    -- Increase button
    local fontUpBtn = VE.UI:CreateButton(fontSizeRow, "+", 24, 22)
    fontUpBtn:SetPoint("RIGHT", 0, 0)
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

    -- Decrease button (aligned with dropdown left edge)
    local uiScaleDownBtn = VE.UI:CreateButton(uiScaleRow, "-", 24, 22)
    uiScaleDownBtn:SetPoint("RIGHT", -136, 0)

    -- Current scale display (centered between buttons)
    local uiScaleValue = uiScaleRow:CreateFontString(nil, "OVERLAY")
    uiScaleValue:SetPoint("CENTER", uiScaleRow, "RIGHT", -80, 0)
    VE.Theme.ApplyFont(uiScaleValue, uiScaleColors)
    local currentUIScale = VE.Store.state.config.uiScale or 1.0
    uiScaleValue:SetText(string.format("%.0f%%", currentUIScale * 100))
    uiScaleValue:SetTextColor(uiScaleColors.accent.r, uiScaleColors.accent.g, uiScaleColors.accent.b)
    uiScaleRow.scaleValue = uiScaleValue
    uiScaleDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.uiScale or 1.0
        local newScale = math.max(current - 0.1, 0.8)
        newScale = math.floor(newScale * 10 + 0.5) / 10  -- Round to 1 decimal
        VE.Store:Dispatch("SET_UI_SCALE", { scale = newScale })
        uiScaleValue:SetText(string.format("%.0f%%", newScale * 100))
        VE.EventBus:Trigger("VE_UI_SCALE_UPDATE", {})
    end)

    -- Increase button
    local uiScaleUpBtn = VE.UI:CreateButton(uiScaleRow, "+", 24, 22)
    uiScaleUpBtn:SetPoint("RIGHT", 0, 0)
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

    -- Decrease button (more transparent)
    local opacityDownBtn = VE.UI:CreateButton(opacityRow, "-", 24, 22)
    opacityDownBtn:SetPoint("RIGHT", -136, 0)

    -- Current opacity display (centered between buttons)
    local opacityValue = opacityRow:CreateFontString(nil, "OVERLAY")
    opacityValue:SetPoint("CENTER", opacityRow, "RIGHT", -80, 0)
    VE.Theme.ApplyFont(opacityValue, opacityColors)
    local currentOpacity = VE.Store.state.config.bgOpacity or 0.9
    opacityValue:SetText(string.format("%.0f%%", currentOpacity * 100))
    opacityValue:SetTextColor(opacityColors.accent.r, opacityColors.accent.g, opacityColors.accent.b)
    opacityRow.opacityValue = opacityValue

    opacityDownBtn:SetScript("OnClick", function()
        local current = VE.Store:GetState().config.bgOpacity or 0.9
        local newOpacity = math.max(current - 0.1, 0.3)
        newOpacity = math.floor(newOpacity * 10 + 0.5) / 10
        VE.Store:Dispatch("SET_BG_OPACITY", { opacity = newOpacity })
        opacityValue:SetText(string.format("%.0f%%", newOpacity * 100))
        VE.EventBus:Trigger("VE_THEME_UPDATE", {})
    end)

    -- Increase button (more opaque)
    local opacityUpBtn = VE.UI:CreateButton(opacityRow, "+", 24, 22)
    opacityUpBtn:SetPoint("RIGHT", 0, 0)
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

    yOffset = yOffset - 36

    -- ========================================================================
    -- HOUSE XP FORMULA INFO
    -- ========================================================================

    local formulaHeader = VE.UI:CreateSectionHeader(settingsPanel, "House XP Formula (Guess!)")
    formulaHeader:SetPoint("TOPLEFT", 0, yOffset)
    formulaHeader:SetPoint("TOPRIGHT", 0, yOffset)
    container.formulaHeader = formulaHeader

    yOffset = yOffset - 20

    local formulaC = GetColors()

    -- Formula explanation
    local formulaText = settingsPanel:CreateFontString(nil, "OVERLAY")
    formulaText:SetPoint("TOPLEFT", 12, yOffset)
    formulaText:SetJustifyH("LEFT")
    VE.Theme.ApplyFont(formulaText, formulaC, "small")
    formulaText:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    formulaText:SetText("Progressive DR: factor = 0.96 - 0.10 * n")
    container.formulaText = formulaText

    yOffset = yOffset - 14

    local formulaExample = settingsPanel:CreateFontString(nil, "OVERLAY")
    formulaExample:SetPoint("TOPLEFT", 12, yOffset)
    formulaExample:SetJustifyH("LEFT")
    VE.Theme.ApplyFont(formulaExample, formulaC, "small")
    formulaExample:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    formulaExample:SetText("n=2: x0.76, n=3: x0.66, n=4: x0.56...")
    container.formulaExample = formulaExample

    yOffset = yOffset - 18

    -- Base values header
    local baseHeader = settingsPanel:CreateFontString(nil, "OVERLAY")
    baseHeader:SetPoint("TOPLEFT", 12, yOffset)
    VE.Theme.ApplyFont(baseHeader, formulaC, "small")
    baseHeader:SetTextColor(formulaC.text.r, formulaC.text.g, formulaC.text.b)
    baseHeader:SetText("Known Base Values:")
    container.baseHeader = baseHeader

    yOffset = yOffset - 14

    -- Base 50 tasks
    local base50 = settingsPanel:CreateFontString(nil, "OVERLAY")
    base50:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base50, formulaC, "small")
    base50:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base50:SetText("|cFFb58900Base 50:|r Weekly, Good Neighbor,")
    container.base50 = base50

    yOffset = yOffset - 12

    local base50b = settingsPanel:CreateFontString(nil, "OVERLAY")
    base50b:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base50b, formulaC, "small")
    base50b:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base50b:SetText("Daily, Froststone, War Creche, Lumber")
    container.base50b = base50b

    yOffset = yOffset - 14

    -- Base 25 tasks
    local base25 = settingsPanel:CreateFontString(nil, "OVERLAY")
    base25:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base25, formulaC, "small")
    base25:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base25:SetText("|cFF859900Base 25:|r Pet Battle, Hoard, Scrolls,")
    container.base25 = base25

    yOffset = yOffset - 12

    local base25b = settingsPanel:CreateFontString(nil, "OVERLAY")
    base25b:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base25b, formulaC, "small")
    base25b:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base25b:SetText("Vault Doors, Kill Rares, Gather, Creatures")
    container.base25b = base25b

    yOffset = yOffset - 14

    -- Base 150 tasks
    local base150 = settingsPanel:CreateFontString(nil, "OVERLAY")
    base150:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base150, formulaC, "small")
    base150:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base150:SetText("|cFFdc322fBase 150:|r Profession Rare")
    container.base150 = base150

    yOffset = yOffset - 14

    -- Base 10 tasks
    local base10 = settingsPanel:CreateFontString(nil, "OVERLAY")
    base10:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(base10, formulaC, "small")
    base10:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    base10:SetText("|cFF6c71c4Base 10:|r Skyriding, Delves, M+, Raids")
    container.base10 = base10

    yOffset = yOffset - 18

    -- Example progression
    local progHeader = settingsPanel:CreateFontString(nil, "OVERLAY")
    progHeader:SetPoint("TOPLEFT", 12, yOffset)
    VE.Theme.ApplyFont(progHeader, formulaC, "small")
    progHeader:SetTextColor(formulaC.text.r, formulaC.text.g, formulaC.text.b)
    progHeader:SetText("Example (Base 50):")
    container.progHeader = progHeader

    yOffset = yOffset - 14

    local progExample = settingsPanel:CreateFontString(nil, "OVERLAY")
    progExample:SetPoint("TOPLEFT", 20, yOffset)
    VE.Theme.ApplyFont(progExample, formulaC, "small")
    progExample:SetTextColor(formulaC.text_dim.r, formulaC.text_dim.g, formulaC.text_dim.b)
    progExample:SetText("50 -> 38 -> 25 -> 14 -> 10 (floor)")
    container.progExample = progExample

    yOffset = yOffset - 24

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
        if container.discordEditBox then
            container.discordEditBox:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, 0.8)
        end
        if container.discordHint then
            container.discordHint:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, 0.7)
            VE.Theme.ApplyFont(container.discordHint, colors, "small")
        end
        -- Formula section theme updates
        if container.formulaText then
            container.formulaText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.formulaText, colors, "small")
        end
        if container.formulaExample then
            container.formulaExample:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.formulaExample, colors, "small")
        end
        if container.baseHeader then
            container.baseHeader:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.baseHeader, colors, "small")
        end
        if container.base50 then
            container.base50:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base50, colors, "small")
        end
        if container.base50b then
            container.base50b:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base50b, colors, "small")
        end
        if container.base25 then
            container.base25:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base25, colors, "small")
        end
        if container.base25b then
            container.base25b:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base25b, colors, "small")
        end
        if container.base150 then
            container.base150:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base150, colors, "small")
        end
        if container.base10 then
            container.base10:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.base10, colors, "small")
        end
        if container.progHeader then
            container.progHeader:SetTextColor(colors.text.r, colors.text.g, colors.text.b)
            VE.Theme.ApplyFont(container.progHeader, colors, "small")
        end
        if container.progExample then
            container.progExample:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            VE.Theme.ApplyFont(container.progExample, colors, "small")
        end
    end)

    return container
end
