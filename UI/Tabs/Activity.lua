-- ============================================================================
-- Vamoose's Endeavors - Activity Tab
-- Shows top 5 activities and recent activity feed
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Helper to get current theme colors
local function GetColors()
    return VE.Constants:GetThemeColors()
end

function VE.UI.Tabs:CreateActivity(parent)
    local UI = VE.Constants.UI

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = UI.panelPadding

    -- ========================================================================
    -- TOP ACTIVITIES SECTION
    -- ========================================================================

    local topHeader = VE.UI:CreateSectionHeader(container, "Top 5 Tasks")
    topHeader:SetPoint("TOPLEFT", padding, -2)
    topHeader:SetPoint("TOPRIGHT", -padding, -2)

    local topContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    topContainer:SetPoint("TOPLEFT", topHeader, "BOTTOMLEFT", 0, -2)
    topContainer:SetPoint("TOPRIGHT", topHeader, "BOTTOMRIGHT", 0, -2)
    topContainer:SetHeight(130) -- 5 rows x 24 + padding
    topContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.topContainer = topContainer

    -- ========================================================================
    -- ACTIVITY FEED SECTION
    -- ========================================================================

    local feedHeader = VE.UI:CreateSectionHeader(container, "Recent Activity")
    feedHeader:SetPoint("TOPLEFT", topContainer, "BOTTOMLEFT", 0, -6)
    feedHeader:SetPoint("TOPRIGHT", topContainer, "BOTTOMRIGHT", 0, -6)

    local feedContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    feedContainer:SetPoint("TOPLEFT", feedHeader, "BOTTOMLEFT", 0, -2)
    feedContainer:SetPoint("BOTTOMRIGHT", -padding, padding)
    feedContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.feedContainer = feedContainer

    -- Apply container colors
    local function ApplyContainerColors()
        local C = GetColors()
        topContainer:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.3)
        feedContainer:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.3)
    end
    ApplyContainerColors()

    local scrollFrame, scrollContent = VE.UI:CreateScrollFrame(feedContainer)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    container.scrollContent = scrollContent

    -- Pool for top task rows
    container.topRows = {}

    -- Pool for feed rows
    container.feedRows = {}

    -- ========================================================================
    -- CREATE TOP TASK ROW
    -- ========================================================================

    local function CreateTopTaskRow(parentFrame)
        local C = GetColors()
        local row = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        row:SetHeight(24)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.5)

        -- Rank
        local rank = row:CreateFontString(nil, "OVERLAY")
        rank:SetPoint("LEFT", 8, 0)
        rank:SetWidth(24)
        rank:SetJustifyH("CENTER")
        rank:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        VE.Theme.ApplyFont(rank, C)
        row.rank = rank

        -- Task name
        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetPoint("LEFT", rank, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", -80, 0)
        name:SetJustifyH("LEFT")
        name:SetTextColor(C.text.r, C.text.g, C.text.b)
        VE.Theme.ApplyFont(name, C)
        row.name = name

        -- Completion count
        local count = row:CreateFontString(nil, "OVERLAY")
        count:SetPoint("RIGHT", -8, 0)
        count:SetJustifyH("RIGHT")
        count:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        VE.Theme.ApplyFont(count, C)
        row.count = count

        function row:SetData(rankNum, taskName, completions)
            local colors = GetColors()
            self.rank:SetText("#" .. rankNum)
            self.name:SetText(taskName)
            self.count:SetText(completions .. "x")

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

            self.name:SetTextColor(colors.text.r, colors.text.g, colors.text.b, colors.text.a)
            VE.Theme.ApplyFont(self.name, colors)

            self.count:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a)
            VE.Theme.ApplyFont(self.count, colors)

            self:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, colors.panel.a * 0.5)
        end

        return row
    end

    -- ========================================================================
    -- CREATE FEED ROW
    -- ========================================================================

    local function CreateFeedRow(parentFrame)
        local C = GetColors()
        local row = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        row:SetHeight(20)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.3)

        -- Time ago
        local timeText = row:CreateFontString(nil, "OVERLAY")
        timeText:SetPoint("LEFT", 6, 0)
        timeText:SetWidth(40)
        timeText:SetJustifyH("LEFT")
        timeText:SetTextColor(C.text_dim.r, C.text_dim.g, C.text_dim.b)
        VE.Theme.ApplyFont(timeText, C)
        row.timeText = timeText

        -- Player name
        local playerName = row:CreateFontString(nil, "OVERLAY")
        playerName:SetPoint("LEFT", timeText, "RIGHT", 4, 0)
        playerName:SetWidth(70)
        playerName:SetJustifyH("LEFT")
        playerName:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        VE.Theme.ApplyFont(playerName, C)
        row.playerName = playerName

        -- Task name
        local taskName = row:CreateFontString(nil, "OVERLAY")
        taskName:SetPoint("LEFT", playerName, "RIGHT", 4, 0)
        taskName:SetPoint("RIGHT", -40, 0)
        taskName:SetJustifyH("LEFT")
        taskName:SetTextColor(C.text.r, C.text.g, C.text.b)
        VE.Theme.ApplyFont(taskName, C)
        row.taskName = taskName

        -- Amount
        local amount = row:CreateFontString(nil, "OVERLAY")
        amount:SetPoint("RIGHT", -6, 0)
        amount:SetJustifyH("RIGHT")
        amount:SetTextColor(C.endeavor.r, C.endeavor.g, C.endeavor.b)
        VE.Theme.ApplyFont(amount, C)
        row.amount = amount

        function row:SetData(entry)
            local colors = GetColors()

            -- Format time ago
            local timeAgo = ""
            if entry.completionTime then
                local now = time()
                local diff = now - entry.completionTime
                if diff < 60 then
                    timeAgo = "<1m"
                elseif diff < 3600 then
                    timeAgo = math.floor(diff / 60) .. "m"
                elseif diff < 86400 then
                    timeAgo = math.floor(diff / 3600) .. "h"
                else
                    timeAgo = math.floor(diff / 86400) .. "d"
                end
            end

            self.timeText:SetText(timeAgo)
            self.playerName:SetText(entry.playerName or "Unknown")
            self.taskName:SetText(entry.taskName or "Unknown Task")
            self.amount:SetText(string.format("+%.1f", entry.amount or 0))

            -- Apply theme colors + fonts
            self.timeText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a)
            VE.Theme.ApplyFont(self.timeText, colors)

            self.taskName:SetTextColor(colors.text.r, colors.text.g, colors.text.b, colors.text.a)
            VE.Theme.ApplyFont(self.taskName, colors)

            self.amount:SetTextColor(colors.endeavor.r, colors.endeavor.g, colors.endeavor.b, colors.endeavor.a)
            VE.Theme.ApplyFont(self.amount, colors)

            self:SetBackdropColor(colors.panel.r, colors.panel.g, colors.panel.b, colors.panel.a * 0.3)

            -- Highlight current player
            local currentPlayer = UnitName("player")
            if entry.playerName == currentPlayer then
                self.playerName:SetTextColor(colors.success.r, colors.success.g, colors.success.b, colors.success.a)
            else
                self.playerName:SetTextColor(colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a)
            end
            VE.Theme.ApplyFont(self.playerName, colors)
        end

        return row
    end

    -- ========================================================================
    -- UPDATE FUNCTION
    -- ========================================================================

    function container:Update()
        -- Hide all existing rows
        for _, row in ipairs(self.topRows) do
            row:Hide()
        end
        for _, row in ipairs(self.feedRows) do
            row:Hide()
        end

        -- Get activity log data
        local activityData = VE.EndeavorTracker:GetActivityLogData()
        if not activityData or not activityData.taskActivity or #activityData.taskActivity == 0 then
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

        -- ====================================================================
        -- TOP 5 TASKS
        -- ====================================================================

        -- Aggregate completions by task
        local taskCounts = {}
        for _, entry in ipairs(activityData.taskActivity) do
            local taskName = entry.taskName or "Unknown"
            taskCounts[taskName] = (taskCounts[taskName] or 0) + 1
        end

        -- Sort by count (highest first)
        local sortedTasks = {}
        for taskName, taskCount in pairs(taskCounts) do
            table.insert(sortedTasks, { name = taskName, count = taskCount })
        end
        table.sort(sortedTasks, function(a, b) return a.count > b.count end)

        -- Display top 5
        local yOffset = 2
        local rowHeight = 24
        local rowSpacing = 2

        for i = 1, math.min(5, #sortedTasks) do
            local data = sortedTasks[i]
            local row = self.topRows[i]
            if not row then
                row = CreateTopTaskRow(self.topContainer)
                self.topRows[i] = row
            end

            row:SetPoint("TOPLEFT", 2, -yOffset)
            row:SetPoint("TOPRIGHT", -2, -yOffset)
            row:SetData(i, data.name, data.count)
            row:Show()

            yOffset = yOffset + rowHeight + rowSpacing
        end

        -- ====================================================================
        -- ACTIVITY FEED (most recent first)
        -- ====================================================================

        -- Sort by completionTime (most recent first)
        local sortedActivity = {}
        for _, entry in ipairs(activityData.taskActivity) do
            table.insert(sortedActivity, entry)
        end
        table.sort(sortedActivity, function(a, b)
            return (a.completionTime or 0) > (b.completionTime or 0)
        end)

        -- Display feed
        yOffset = 0
        rowHeight = 20
        rowSpacing = 1

        for i, entry in ipairs(sortedActivity) do
            local row = self.feedRows[i]
            if not row then
                row = CreateFeedRow(self.scrollContent)
                self.feedRows[i] = row
            end

            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", 0, -yOffset)
            row:SetData(entry)
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
        ApplyContainerColors()
        if container:IsShown() then
            container:Update()
        end
    end)

    return container
end
