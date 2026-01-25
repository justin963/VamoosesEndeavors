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

    local padding = 0  -- Container edge padding (0 for full-bleed atlas backgrounds)

    -- ========================================================================
    -- TASKS HEADER
    -- ========================================================================

    local tasksHeader = VE.UI:CreateSectionHeader(container, "Endeavor Tasks")
    tasksHeader:SetPoint("TOPLEFT", 0, UI.sectionHeaderYOffset)
    tasksHeader:SetPoint("TOPRIGHT", 0, UI.sectionHeaderYOffset)

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

    -- XP sort button (centered over points badge: 32px wide at RIGHT -34, center = -34 - 16 = -50)
    local sortXpBtn = CreateSortButton(tasksHeader, "xp", -50)
    container.sortXpBtn = sortXpBtn

    -- Coupons sort button (centered over coupon badge: 26px wide at RIGHT -4, center = -4 - 13 = -17)
    local sortCouponsBtn = CreateSortButton(tasksHeader, "coupons", -17)
    container.sortCouponsBtn = sortCouponsBtn

    -- Update icons to reflect loaded state
    sortXpBtn:UpdateIcon()
    sortCouponsBtn:UpdateIcon()

    -- ========================================================================
    -- TASKS LIST (Scrollable)
    -- ========================================================================

    local taskListContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    taskListContainer:SetPoint("TOPLEFT", tasksHeader, "BOTTOMLEFT", 4, 0)
    taskListContainer:SetPoint("BOTTOMRIGHT", -padding, padding)
    taskListContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
    })
    container.taskListContainer = taskListContainer

    -- Atlas background support
    local ApplyContainerColors = VE.UI:AddAtlasBackground(taskListContainer)
    ApplyContainerColors()

    local _, scrollContent = VE.UI:CreateScrollFrame(taskListContainer)
    container.scrollContent = scrollContent

    -- Pool of task rows
    container.taskRows = {}

    -- ========================================================================
    -- UPDATE FUNCTION
    -- ========================================================================

    function container:Update(forceUpdate)
        local state = VE.Store:GetState()
        -- Update tasks list only (header is updated by MainFrame)
        self:UpdateTaskList(state.tasks, forceUpdate)
    end

    function container:UpdateTaskList(tasks, forceUpdate)
        -- Skip rebuild if nothing changed (optimization)
        local taskCount = tasks and #tasks or 0
        local fetchState = VE.EndeavorTracker and VE.EndeavorTracker.fetchStatus and VE.EndeavorTracker.fetchStatus.state
        local sortKey = (sortState.column or "none") .. "-" .. (sortState.direction or "none")
        local cacheKey = taskCount .. "-" .. (fetchState or "nil") .. "-" .. sortKey
        if not forceUpdate and self.lastTaskCacheKey and self.lastTaskCacheKey == cacheKey then
            return
        end
        self.lastTaskCacheKey = cacheKey

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
                if self.setActiveButton then self.setActiveButton:Hide() end
            else
                self.emptyText:SetText("No endeavor tasks found.\nThis house is not set as your active endeavor.")
                -- Create button via factory (once)
                if not self.setActiveButton then
                    self.setActiveButton = VE.UI:CreateSetAsActiveButton(self.scrollContent, self.emptyText, {
                        onBeforeClick = function()
                            self.setActiveClicked = true
                            if self.setActiveButton then self.setActiveButton:Hide() end
                            self.emptyText:SetText("Fetching endeavor data...\nThis may take a few seconds.")
                        end
                    })
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

        local yOffset = 2 -- Top padding for first row
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
