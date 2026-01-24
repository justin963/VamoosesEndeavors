-- ============================================================================
-- Vamoose's Endeavors - Endeavors Tab
-- Task list view (header/progress bar are in MainFrame for minimize support)
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Helper to get current theme colors
local function GetColors()
    return VE.Constants:GetThemeColors()
end

-- Sort state: nil = none, "asc" = ascending, "desc" = descending
local sortState = {
    column = nil, -- "xp" or "coupons"
    direction = nil,
}

-- Load sort state from SavedVariables
local function LoadSortState()
    if VE_DB and VE_DB.ui and VE_DB.ui.taskSort then
        sortState.column = VE_DB.ui.taskSort.column
        sortState.direction = VE_DB.ui.taskSort.direction
    end
end

-- Save sort state to SavedVariables
local function SaveSortState()
    VE_DB = VE_DB or {}
    VE_DB.ui = VE_DB.ui or {}
    VE_DB.ui.taskSort = {
        column = sortState.column,
        direction = sortState.direction,
    }
end

function VE.UI.Tabs:CreateEndeavors(parent)
    local UI = VE.Constants.UI

    -- Load saved sort state
    LoadSortState()

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = UI.panelPadding

    -- ========================================================================
    -- TASKS HEADER
    -- ========================================================================

    local tasksHeader = VE.UI:CreateSectionHeader(container, "Endeavor Tasks")
    tasksHeader:SetPoint("TOPLEFT", padding, 0)
    tasksHeader:SetPoint("TOPRIGHT", -padding, 0)

    -- Sort buttons on header row (right side)
    local function CreateSortButton(parent, column, xOffset)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(16, 16)
        btn:SetPoint("RIGHT", xOffset, 0)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas("housing-stair-arrow-down-default")
        btn.icon = icon
        btn.column = column

        function btn:UpdateIcon()
            if sortState.column == self.column then
                if sortState.direction == "asc" then
                    self.icon:SetAtlas("housing-stair-arrow-up-highlight")
                else
                    self.icon:SetAtlas("housing-stair-arrow-down-highlight")
                end
            else
                self.icon:SetAtlas("housing-stair-arrow-down-default")
            end
        end

        btn:SetScript("OnClick", function(self)
            if sortState.column == self.column then
                if sortState.direction == "desc" then
                    sortState.direction = "asc"
                elseif sortState.direction == "asc" then
                    sortState.column = nil
                    sortState.direction = nil
                end
            else
                sortState.column = self.column
                sortState.direction = "desc"
            end
            -- Save sort state
            SaveSortState()
            -- Update both buttons
            container.sortXpBtn:UpdateIcon()
            container.sortCouponsBtn:UpdateIcon()
            -- Re-render task list
            container:Update()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local colName = self.column == "xp" and "XP" or "Coupons"
            GameTooltip:AddLine("Sort by " .. colName, 1, 1, 1)
            if sortState.column == self.column then
                local dir = sortState.direction == "asc" and "ascending" or "descending"
                GameTooltip:AddLine("Currently: " .. dir, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return btn
    end

    -- XP sort button (centered over points badge: 32px wide, right edge at -30, center at -46)
    local sortXpBtn = CreateSortButton(tasksHeader, "xp", -38)
    container.sortXpBtn = sortXpBtn

    -- Coupons sort button (centered over coupon badge: 26px wide, right edge at 0, center at -13)
    local sortCouponsBtn = CreateSortButton(tasksHeader, "coupons", -5)
    container.sortCouponsBtn = sortCouponsBtn

    -- Update icons to reflect loaded state
    sortXpBtn:UpdateIcon()
    sortCouponsBtn:UpdateIcon()

    -- ========================================================================
    -- TASKS LIST (Scrollable)
    -- ========================================================================

    local taskListContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    taskListContainer:SetPoint("TOPLEFT", tasksHeader, "BOTTOMLEFT", 0, -2)
    taskListContainer:SetPoint("BOTTOMRIGHT", 0, padding)
    taskListContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.taskListContainer = taskListContainer

    -- Apply container colors
    local function ApplyContainerColors()
        local C = GetColors()
        taskListContainer:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a * 0.3)
    end
    ApplyContainerColors()

    local scrollFrame, scrollContent = VE.UI:CreateScrollFrame(taskListContainer)
    scrollFrame:SetPoint("TOPLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 2)
    container.scrollContent = scrollContent

    -- Pool of task rows
    container.taskRows = {}

    -- ========================================================================
    -- UPDATE FUNCTION
    -- ========================================================================

    function container:Update()
        local state = VE.Store:GetState()
        -- Update tasks list only (header is updated by MainFrame)
        self:UpdateTaskList(state.tasks)
    end

    function container:UpdateTaskList(tasks)
        -- Hide all existing rows
        for _, row in ipairs(self.taskRows) do
            row:Hide()
        end

        if not tasks or #tasks == 0 then
            -- Show empty state with fetch status
            local colors = GetColors()
            if not self.emptyText then
                self.emptyText = self.scrollContent:CreateFontString(nil, "OVERLAY")
                self.emptyText:SetPoint("CENTER", self.scrollContent, "CENTER", 0, 20)
            end
            VE.Theme.ApplyFont(self.emptyText, colors)

            -- Check fetch status to show appropriate message
            local fetchStatus = VE.EndeavorTracker and VE.EndeavorTracker.fetchStatus
            local isFetching = fetchStatus and (fetchStatus.state == "fetching" or fetchStatus.state == "retrying" or fetchStatus.state == "pending")

            if isFetching or self.setActiveClicked then
                self.emptyText:SetText("Fetching endeavor data...\nThis may take a few seconds.")
                -- Hide button while fetching or after clicking set active
                if self.setActiveButton then
                    self.setActiveButton:Hide()
                end
            else
                self.emptyText:SetText("No endeavor tasks found.\nThis house is not set as your active endeavor.")

                -- Create "Set as Active" button if needed
                if not self.setActiveButton then
                    self.setActiveButton = CreateFrame("Button", nil, self.scrollContent, "UIPanelButtonTemplate")
                    self.setActiveButton:SetSize(120, 24)
                    self.setActiveButton:SetPoint("TOP", self.emptyText, "BOTTOM", 0, -12)
                    self.setActiveButton:SetText("Set as Active")
                    self.setActiveButton:SetScript("OnClick", function()
                        self.setActiveClicked = true  -- Prevent button from re-showing
                        if self.setActiveButton then
                            self.setActiveButton:Hide()
                        end
                        self.emptyText:SetText("Fetching endeavor data...\nThis may take a few seconds.")
                        local tracker = VE.EndeavorTracker
                        if tracker then
                            tracker:SetAsActiveEndeavor()
                        end
                    end)
                end
                -- Style button text
                local fs = self.setActiveButton:GetFontString()
                if fs then
                    VE.Theme.ApplyFont(fs, colors)
                end
                self.setActiveButton:Show()
            end

            self.emptyText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a)
            self.emptyText:Show()
            self.scrollContent:SetHeight(100)
            return
        end

        if self.emptyText then
            self.emptyText:Hide()
        end
        if self.setActiveButton then
            self.setActiveButton:Hide()
        end

        -- Apply sorting if active (completed tasks always at bottom)
        local sortedTasks = tasks
        if sortState.column and sortState.direction then
            sortedTasks = {}
            for i, task in ipairs(tasks) do
                sortedTasks[i] = task
            end
            table.sort(sortedTasks, function(a, b)
                -- Completed tasks always sort to bottom
                if a.completed ~= b.completed then
                    return not a.completed
                end
                -- Within same completion status, sort by selected column
                local valA, valB
                if sortState.column == "xp" then
                    valA = a.points or 0
                    valB = b.points or 0
                else -- coupons
                    valA = a.couponReward or 0
                    valB = b.couponReward or 0
                end
                if sortState.direction == "asc" then
                    return valA < valB
                else
                    return valA > valB
                end
            end)
        end

        local yOffset = 0
        local rowHeight = VE.Constants.UI.taskRowHeight
        local rowSpacing = VE.Constants.UI.rowSpacing

        for i, task in ipairs(sortedTasks) do
            -- Get or create row
            local row = self.taskRows[i]
            if not row then
                row = VE.UI:CreateTaskRow(self.scrollContent)
                self.taskRows[i] = row
            end

            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", -2, -yOffset)
            row:SetTask(task)
            row:Show()

            yOffset = yOffset + rowHeight + rowSpacing
        end

        -- Set content height for scrolling
        self.scrollContent:SetHeight(yOffset + 10)
    end

    -- Initial update when shown
    container:SetScript("OnShow", function(self)
        self:Update()
    end)

    -- Listen for theme updates to refresh colors
    VE.EventBus:Register("VE_THEME_UPDATE", function()
        ApplyContainerColors()
        -- Task rows update via their own theme registration
        if container:IsShown() then
            container:Update()
        end
    end)

    -- Reset setActiveClicked flag when house selection changes
    VE.EventBus:Register("VE_HOUSE_SELECTED", function()
        container.setActiveClicked = false
    end)

    return container
end
