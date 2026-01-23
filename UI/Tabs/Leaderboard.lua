-- ============================================================================
-- Vamoose's Endeavors - Leaderboard Tab
-- Shows neighborhood contribution rankings
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Helper to get current theme colors
local function GetColors()
    return VE.Constants:GetThemeColors()
end

function VE.UI.Tabs:CreateLeaderboard(parent)
    local UI = VE.Constants.UI

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = UI.panelPadding

    -- ========================================================================
    -- LEADERBOARD HEADER
    -- ========================================================================

    local header = VE.UI:CreateSectionHeader(container, "Contribution Leaderboard")
    header:SetPoint("TOPLEFT", padding, -2)
    header:SetPoint("TOPRIGHT", -padding, -2)

    -- ========================================================================
    -- LEADERBOARD LIST (Scrollable)
    -- ========================================================================

    local listContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    listContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    listContainer:SetPoint("BOTTOMRIGHT", -padding, padding)
    listContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.listContainer = listContainer

    -- Apply initial colors
    local function ApplyListContainerColors()
        local C = GetColors()
        listContainer:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.3)
    end
    ApplyListContainerColors()

    local scrollFrame, scrollContent = VE.UI:CreateScrollFrame(listContainer)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    container.scrollContent = scrollContent

    -- Pool of leaderboard rows
    container.rows = {}

    -- ========================================================================
    -- CREATE LEADERBOARD ROW
    -- ========================================================================

    local function CreateLeaderboardRow(parentFrame)
        local C = GetColors()
        local row = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        row:SetHeight(24)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.5)

        -- Rank number
        local rank = row:CreateFontString(nil, "OVERLAY")
        rank:SetPoint("LEFT", 8, 0)
        rank:SetWidth(32)
        rank:SetJustifyH("CENTER")
        rank:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        VE.Theme.ApplyFont(rank, C)
        row.rank = rank

        -- Player name
        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetPoint("LEFT", rank, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", -80, 0)
        name:SetJustifyH("LEFT")
        name:SetTextColor(C.text.r, C.text.g, C.text.b)
        VE.Theme.ApplyFont(name, C)
        row.name = name

        -- Contribution amount
        local amount = row:CreateFontString(nil, "OVERLAY")
        amount:SetPoint("RIGHT", -8, 0)
        amount:SetJustifyH("RIGHT")
        amount:SetTextColor(C.endeavor.r, C.endeavor.g, C.endeavor.b)
        VE.Theme.ApplyFont(amount, C)
        row.amount = amount

        -- Track if this is the current player for hover states
        row.isCurrentPlayer = false

        -- Hover effect (uses fresh colors)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local colors = GetColors()
            if self.isCurrentPlayer then
                self:SetBackdropColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a * 0.25)
            else
                self:SetBackdropColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a * 0.3)
            end
        end)
        row:SetScript("OnLeave", function(self)
            local colors = GetColors()
            if self.isCurrentPlayer then
                self:SetBackdropColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a * 0.15)
            else
                self:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, colors.panel.a * 0.5)
            end
        end)

        function row:SetData(rankNum, playerName, contribution)
            local colors = GetColors()
            self.rank:SetText("#" .. rankNum)
            self.name:SetText(playerName)
            self.amount:SetText(string.format("%.1f", contribution))

            -- Gold/Silver/Bronze colors for top 3, otherwise use text_dim
            if rankNum == 1 then
                self.rank:SetTextColor(colors.gold.r, colors.gold.g, colors.gold.b)
            elseif rankNum == 2 then
                self.rank:SetTextColor(colors.silver.r, colors.silver.g, colors.silver.b)
            elseif rankNum == 3 then
                self.rank:SetTextColor(colors.bronze.r, colors.bronze.g, colors.bronze.b)
            else
                self.rank:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b)
            end
            VE.Theme.ApplyFont(self.rank, colors)

            self.amount:SetTextColor(colors.endeavor.r, colors.endeavor.g, colors.endeavor.b)
            VE.Theme.ApplyFont(self.amount, colors)

            -- Highlight current player
            local currentPlayer = UnitName("player")
            self.isCurrentPlayer = (playerName == currentPlayer)
            if self.isCurrentPlayer then
                self.name:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a)
                self:SetBackdropColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a * 0.15)
            else
                self.name:SetTextColor(colors.text.r, colors.text.g, colors.text.b, colors.text.a)
                self:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, colors.panel.a * 0.5)
            end
            VE.Theme.ApplyFont(self.name, colors)
        end

        return row
    end

    -- ========================================================================
    -- UPDATE FUNCTION
    -- ========================================================================

    -- Loading text
    local loadingColors = GetColors()
    container.loadingText = container.scrollContent:CreateFontString(nil, "OVERLAY")
    container.loadingText:SetPoint("CENTER", container.scrollContent, "CENTER", 0, 0)
    VE.Theme.ApplyFont(container.loadingText, loadingColors)
    container.loadingText:SetText("Loading activity data...")
    container.loadingText:SetTextColor(loadingColors.text_dim.r, loadingColors.text_dim.g, loadingColors.text_dim.b)
    container.loadingText:Hide()

    function container:Update()
        -- Hide all existing rows
        for _, row in ipairs(self.rows) do
            row:Hide()
        end

        -- Get activity log data
        local activityData = VE.EndeavorTracker:GetActivityLogData()
        if not activityData or not activityData.taskActivity then
            -- Show loading or empty state
            if not self.emptyText then
                self.emptyText = self.scrollContent:CreateFontString(nil, "OVERLAY")
                self.emptyText:SetPoint("CENTER", self.scrollContent, "CENTER", 0, 0)
            end

            -- Apply theme color and font to empty text
            local colors = GetColors()
            VE.Theme.ApplyFont(self.emptyText, colors)
            self.emptyText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a)

            if not VE.EndeavorTracker:IsActivityLogLoaded() then
                self.emptyText:SetText("Loading activity data...")
            else
                self.emptyText:SetText("No activity data available.\nVisit your neighborhood to sync.")
            end
            self.emptyText:Show()
            self.scrollContent:SetHeight(100)
            return
        end

        if self.emptyText then
            self.emptyText:Hide()
        end

        -- Aggregate contributions by player
        local contributions = {}
        for _, entry in ipairs(activityData.taskActivity) do
            local playerName = entry.playerName or "Unknown"
            local amt = entry.amount or 0
            contributions[playerName] = (contributions[playerName] or 0) + amt
        end

        -- Sort by contribution (highest first)
        local sorted = {}
        for playerName, amt in pairs(contributions) do
            table.insert(sorted, { name = playerName, amount = amt })
        end
        table.sort(sorted, function(a, b) return a.amount > b.amount end)

        -- Display rows
        local yOffset = 0
        local rowHeight = 24
        local rowSpacing = 2

        for i, data in ipairs(sorted) do
            local row = self.rows[i]
            if not row then
                row = CreateLeaderboardRow(self.scrollContent)
                self.rows[i] = row
            end

            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", 0, -yOffset)
            row:SetData(i, data.name, data.amount)
            row:Show()

            yOffset = yOffset + rowHeight + rowSpacing
        end

        self.scrollContent:SetHeight(yOffset + 10)
    end

    -- Initial update when shown
    container:SetScript("OnShow", function(self)
        -- Request fresh data
        if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestInitiativeActivityLog then
            C_NeighborhoodInitiative.RequestInitiativeActivityLog()
        end
        -- Show loading state immediately
        self:Update()
    end)

    -- Listen for activity log updates
    VE.EventBus:Register("VE_ACTIVITY_LOG_UPDATED", function()
        if container:IsShown() then
            container:Update()
        end
    end)

    -- Listen for theme updates to refresh colors
    VE.EventBus:Register("VE_THEME_UPDATE", function()
        ApplyListContainerColors()
        if container:IsShown() then
            container:Update()
        end
    end)

    return container
end
