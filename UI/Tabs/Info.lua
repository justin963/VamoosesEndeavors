-- ============================================================================
-- Vamoose's Endeavors - Info Tab
-- Displays collected initiative types with collapsible descriptions
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Helper to get current theme colors
local function GetColors()
    return VE.Constants:GetThemeColors()
end

-- Row pool for recycling
local rowPool = {}

function VE.UI.Tabs:CreateInfo(parent)
    local UI = VE.Constants.UI

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = 0

    -- ========================================================================
    -- HEADER
    -- ========================================================================

    local header = VE.UI:CreateSectionHeader(container, "Known Initiatives")
    header:SetPoint("TOPLEFT", 0, UI.sectionHeaderYOffset)
    header:SetPoint("TOPRIGHT", 0, UI.sectionHeaderYOffset)

    -- ========================================================================
    -- SCROLLABLE CONTENT
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

    local scrollFrame, scrollContent = VE.UI:CreateScrollFrame(scrollContainer)
    container.scrollFrame = scrollFrame
    container.scrollContent = scrollContent

    -- Track expanded state per initiative ID
    container.expandedStates = {}
    container.rows = {}

    -- ========================================================================
    -- CREATE INITIATIVE ROW
    -- ========================================================================

    local function CreateInitiativeRow(parentFrame, id, data, yOffset)
        local C = GetColors()
        local isExpanded = container.expandedStates[id] or false

        -- Row container
        local row = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 8, yOffset)
        row:SetPoint("TOPRIGHT", -8, yOffset)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 0.5)
        row:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)
        row.initiativeID = id

        -- Header row (always visible)
        local headerHeight = 24
        local headerRow = CreateFrame("Button", nil, row)
        headerRow:SetHeight(headerHeight)
        headerRow:SetPoint("TOPLEFT", 0, 0)
        headerRow:SetPoint("TOPRIGHT", 0, 0)

        -- Expand/collapse icon
        local expandIcon = headerRow:CreateTexture(nil, "ARTWORK")
        expandIcon:SetSize(12, 12)
        expandIcon:SetPoint("LEFT", 8, 0)
        if isExpanded then
            expandIcon:SetAtlas("common-dropdown-icon-open")
        else
            expandIcon:SetAtlas("common-dropdown-icon-closed")
        end
        row.expandIcon = expandIcon

        -- Initiative title
        local titleText = headerRow:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", expandIcon, "RIGHT", 6, 0)
        titleText:SetPoint("RIGHT", -60, 0)
        titleText:SetJustifyH("LEFT")
        VE.Theme.ApplyFont(titleText, C, "body")
        titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
        titleText:SetText(data.title or "Unknown Initiative")
        titleText._colorType = "text"
        VE.Theme:Register(titleText, "RowText")
        row.titleText = titleText

        -- ID badge (right side)
        local idBadge = headerRow:CreateFontString(nil, "OVERLAY")
        idBadge:SetPoint("RIGHT", -8, 0)
        VE.Theme.ApplyFont(idBadge, C, "small")
        idBadge:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
        idBadge:SetText("ID: " .. id)
        idBadge._colorType = "text_dim"
        VE.Theme:Register(idBadge, "RowText")
        row.idBadge = idBadge

        -- Description container (collapsible)
        local descContainer = CreateFrame("Frame", nil, row)
        descContainer:SetPoint("TOPLEFT", 0, -headerHeight)
        descContainer:SetPoint("TOPRIGHT", 0, -headerHeight)
        row.descContainer = descContainer

        -- Description text
        local descText = descContainer:CreateFontString(nil, "OVERLAY")
        descText:SetPoint("TOPLEFT", 26, -4)
        descText:SetPoint("TOPRIGHT", -8, -4)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        VE.Theme.ApplyFont(descText, C, "small")
        descText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
        local desc = data.description or ""
        if desc == "" then
            desc = "(No description available)"
        end
        descText:SetText(desc)
        descText._colorType = "text_dim"
        VE.Theme:Register(descText, "RowText")
        row.descText = descText

        -- First/last seen dates
        local datesText = descContainer:CreateFontString(nil, "OVERLAY")
        datesText:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -4)
        datesText:SetPoint("TOPRIGHT", descText, "BOTTOMRIGHT", 0, -4)
        datesText:SetJustifyH("LEFT")
        VE.Theme.ApplyFont(datesText, C, "small")
        datesText:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        local firstSeen = data.firstSeen and date("%Y-%m-%d", data.firstSeen) or "?"
        local lastSeen = data.lastSeen and date("%Y-%m-%d", data.lastSeen) or "?"
        datesText:SetText("First seen: " .. firstSeen .. " | Last seen: " .. lastSeen)
        datesText._colorType = "accent"
        VE.Theme:Register(datesText, "RowText")
        row.datesText = datesText

        -- Calculate row height based on expanded state
        local function UpdateRowHeight()
            if isExpanded then
                local descHeight = descText:GetStringHeight() or 14
                local totalDescHeight = descHeight + 4 + 14 + 8  -- desc + gap + dates + bottom padding
                descContainer:SetHeight(totalDescHeight)
                descContainer:Show()
                row:SetHeight(headerHeight + totalDescHeight)
                expandIcon:SetAtlas("common-dropdown-icon-open")
            else
                descContainer:Hide()
                row:SetHeight(headerHeight)
                expandIcon:SetAtlas("common-dropdown-icon-closed")
            end
        end

        -- Click handler for expand/collapse
        headerRow:SetScript("OnClick", function()
            isExpanded = not isExpanded
            container.expandedStates[id] = isExpanded
            UpdateRowHeight()
            -- Refresh the entire panel to recalculate positions
            container:UpdateInfoPanel()
        end)

        -- Hover highlight
        headerRow:SetScript("OnEnter", function()
            row:SetBackdropColor(C.panel.r + 0.05, C.panel.g + 0.05, C.panel.b + 0.05, 0.7)
        end)
        headerRow:SetScript("OnLeave", function()
            row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 0.5)
        end)

        UpdateRowHeight()
        return row
    end

    -- ========================================================================
    -- UPDATE PANEL
    -- ========================================================================

    function container:UpdateInfoPanel()
        local C = GetColors()

        -- Clear existing rows
        for _, row in ipairs(self.rows) do
            row:Hide()
            row:SetParent(nil)
        end
        wipe(self.rows)

        -- Get initiative data from Store
        local knownInitiatives = VE.Store:GetState().knownInitiatives or {}

        -- Count initiatives
        local count = 0
        for _ in pairs(knownInitiatives) do count = count + 1 end

        -- Update header with count
        header.label:SetText("Known Initiatives (" .. count .. ")")

        if count == 0 then
            -- Show empty state message
            local emptyText = scrollContent:CreateFontString(nil, "OVERLAY")
            emptyText:SetPoint("CENTER", 0, 0)
            VE.Theme.ApplyFont(emptyText, C, "body")
            emptyText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
            emptyText:SetText("No initiatives discovered yet.\nPlay the game to collect them!")
            emptyText:SetJustifyH("CENTER")
            table.insert(self.rows, emptyText)
            return
        end

        -- Sort initiatives by ID for consistent display
        local sortedIDs = {}
        for id in pairs(knownInitiatives) do
            table.insert(sortedIDs, id)
        end
        table.sort(sortedIDs)

        -- Create rows
        local yOffset = -8
        local rowSpacing = 4

        for _, id in ipairs(sortedIDs) do
            local data = knownInitiatives[id]
            local row = CreateInitiativeRow(scrollContent, id, data, yOffset)
            table.insert(self.rows, row)
            yOffset = yOffset - row:GetHeight() - rowSpacing
        end

        -- Help text footer
        local helpText = scrollContent:CreateFontString(nil, "OVERLAY")
        helpText:SetPoint("TOPLEFT", 8, yOffset - 12)
        helpText:SetPoint("TOPRIGHT", -8, yOffset - 12)
        helpText:SetJustifyH("CENTER")
        VE.Theme.ApplyFont(helpText, C, "small")
        helpText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b, 0.7)
        helpText:SetText("Help expand this list! Type /ve initiatives and share a screenshot in my Discord.")
        helpText._colorType = "text_dim"
        VE.Theme:Register(helpText, "RowText")
        table.insert(self.rows, helpText)
        yOffset = yOffset - 30

        -- Set scroll content height
        scrollContent:SetHeight(math.abs(yOffset) + 8)
    end

    -- ========================================================================
    -- THEME UPDATE
    -- ========================================================================

    function container:ApplyTheme()
        ApplyPanelColors()
        self:UpdateInfoPanel()
    end

    -- Listen for theme changes
    VE.EventBus:Register("VE_STATE_CHANGED", function(payload)
        if payload.action == "SET_CONFIG" and payload.state.config.theme then
            container:ApplyTheme()
        end
        -- Refresh when initiatives are recorded
        if payload.action == "RECORD_INITIATIVE" then
            if container:IsShown() then
                container:UpdateInfoPanel()
            end
        end
    end)

    -- Refresh on show
    container:SetScript("OnShow", function()
        container:UpdateInfoPanel()
    end)

    return container
end
