-- ============================================================================
-- Vamoose's Endeavors - Endeavors Tab
-- Task list view (header/progress bar are in MainFrame for minimize support)
-- ============================================================================

VE = VE or {}
VE.UI = VE.UI or {}
VE.UI.Tabs = VE.UI.Tabs or {}

-- Cache frequently used values
local ipairs = ipairs
local tsort = table.sort

-- Sort state (persisted)
local sortState = {
    column = nil,
    direction = nil,
}

-- Reusable sorted tasks array (avoids allocation on every sort)
local sortedTasksCache = {}

local function LoadSortState()
    if VE_DB and VE_DB.ui and VE_DB.ui.taskSort then
        sortState.column = VE_DB.ui.taskSort.column
        sortState.direction = VE_DB.ui.taskSort.direction
    end
end

local function SaveSortState()
    VE_DB = VE_DB or {}
    VE_DB.ui = VE_DB.ui or {}
    VE_DB.ui.taskSort = {
        column = sortState.column,
        direction = sortState.direction,
    }
end

-- Compute progress hash that changes when any task's progress changes
local function ComputeProgressHash(tasks)
    if not tasks then return 0 end
    local hash = 0
    for i, task in ipairs(tasks) do
        -- Include index * 1000 to detect task reordering
        hash = hash + i * 1000 + (task.current or 0) + ((task.completed and 500) or 0)
    end
    return hash
end

-- Sort comparator (created once, captures sortState)
local function TaskSortComparator(a, b)
    -- Completed tasks always sort to bottom
    if a.completed ~= b.completed then
        return not a.completed
    end
    -- Within same completion status, sort by selected column
    local valA, valB
    if sortState.column == "xp" then
        valA = a.points or 0
        valB = b.points or 0
    else
        valA = a.couponReward or 0
        valB = b.couponReward or 0
    end
    if sortState.direction == "asc" then
        return valA < valB
    else
        return valA > valB
    end
end

-- Get sorted tasks (reuses cached array to avoid allocation)
local function GetSortedTasks(tasks)
    if not sortState.column or not sortState.direction then
        return tasks
    end
    -- Clear and repopulate cache
    for i = 1, #sortedTasksCache do
        sortedTasksCache[i] = nil
    end
    for i, task in ipairs(tasks) do
        sortedTasksCache[i] = task
    end
    tsort(sortedTasksCache, TaskSortComparator)
    return sortedTasksCache
end

function VE.UI.Tabs:CreateEndeavors(parent)
    local UI = VE.Constants.UI
    local rowHeight = UI.taskRowHeight
    local rowSpacing = UI.rowSpacing

    LoadSortState()

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container.taskRows = {}
    container.lastTaskCacheKey = nil

    -- ========================================================================
    -- TASKS HEADER
    -- ========================================================================

    local tasksHeader = VE.UI:CreateSectionHeader(container, "Endeavor Tasks")
    tasksHeader:SetPoint("TOPLEFT", 0, UI.sectionHeaderYOffset)
    tasksHeader:SetPoint("TOPRIGHT", 0, UI.sectionHeaderYOffset)

    -- Sort button factory
    local function CreateSortButton(parentFrame, column, xOffset)
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(16, 16)
        btn:SetPoint("RIGHT", xOffset, 0)
        btn.column = column

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas("housing-stair-arrow-down-default")
        btn.icon = icon

        function btn:UpdateIcon()
            if sortState.column == self.column then
                local atlas = sortState.direction == "asc" and "housing-stair-arrow-up-highlight" or "housing-stair-arrow-down-highlight"
                self.icon:SetAtlas(atlas)
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
            SaveSortState()
            container.sortXpBtn:UpdateIcon()
            container.sortCouponsBtn:UpdateIcon()
            container:Update(true) -- Force update on sort change
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

        btn:SetScript("OnLeave", GameTooltip_Hide)

        return btn
    end

    container.sortXpBtn = CreateSortButton(tasksHeader, "xp", -50)
    container.sortCouponsBtn = CreateSortButton(tasksHeader, "coupons", -17)
    container.sortXpBtn:UpdateIcon()
    container.sortCouponsBtn:UpdateIcon()

    -- ========================================================================
    -- TASKS LIST (Scrollable)
    -- ========================================================================

    local taskListContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    taskListContainer:SetPoint("TOPLEFT", tasksHeader, "BOTTOMLEFT", 4, 0)
    taskListContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    taskListContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    container.taskListContainer = taskListContainer

    local ApplyContainerColors = VE.UI:AddAtlasBackground(taskListContainer)
    ApplyContainerColors()

    local _, scrollContent = VE.UI:CreateScrollFrame(taskListContainer)
    container.scrollContent = scrollContent

    -- Pre-create empty state elements
    local emptyText = scrollContent:CreateFontString(nil, "OVERLAY")
    emptyText:SetPoint("CENTER", scrollContent, "CENTER", 0, 20)
    emptyText:Hide()
    container.emptyText = emptyText

    -- ========================================================================
    -- UPDATE FUNCTIONS
    -- ========================================================================

    function container:Update(forceUpdate)
        local state = VE.Store:GetState()
        self:UpdateTaskList(state.tasks, forceUpdate)
    end

    function container:UpdateTaskList(tasks, forceUpdate)
        local taskCount = tasks and #tasks or 0
        local sortKey = (sortState.column or "0") .. (sortState.direction or "0")
        local progressHash = ComputeProgressHash(tasks)
        local cacheKey = taskCount .. sortKey .. progressHash

        if not forceUpdate and self.lastTaskCacheKey == cacheKey then
            return
        end
        self.lastTaskCacheKey = cacheKey

        -- Hide all rows first
        for i = 1, #self.taskRows do
            self.taskRows[i]:Hide()
        end

        -- Empty state
        if taskCount == 0 then
            self:ShowEmptyState()
            return
        end

        -- Hide empty state
        self.emptyText:Hide()
        if self.setActiveButton then
            self.setActiveButton:Hide()
        end

        -- Get sorted tasks
        local displayTasks = GetSortedTasks(tasks)

        -- Render rows
        local yOffset = 2
        for i, task in ipairs(displayTasks) do
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

        self.scrollContent:SetHeight(yOffset + 10)
    end

    function container:ShowEmptyState()
        local colors = VE.Constants:GetThemeColors()
        VE.Theme.ApplyFont(self.emptyText, colors)

        local fetchStatus = VE.EndeavorTracker and VE.EndeavorTracker.fetchStatus
        local isFetching = fetchStatus and (fetchStatus.state == "fetching" or fetchStatus.state == "retrying" or fetchStatus.state == "pending")
        local isViewingActive = VE.EndeavorTracker and VE.EndeavorTracker:IsViewingActiveNeighborhood()

        if isViewingActive then
            -- Viewing the ACTIVE neighborhood
            if isFetching then
                self.emptyText:SetText("Fetching endeavor data...\nThis may take a few seconds.")
            else
                self.emptyText:SetText("No endeavor tasks available.\nTry refreshing or check back later.")
            end
            if self.setActiveButton then self.setActiveButton:Hide() end
        else
            -- Viewing an INACTIVE neighborhood - show Set as Active button
            self.emptyText:SetText("No endeavor tasks found.\nThis house is not set as your active endeavor.")
            if not self.setActiveButton then
                self.setActiveButton = VE.UI:CreateSetAsActiveButton(self.scrollContent, self.emptyText, {})
            end
            self.setActiveButton:Show()
        end

        self.emptyText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a)
        self.emptyText:Show()
        self.scrollContent:SetHeight(100)
    end

    -- ========================================================================
    -- EVENT HANDLERS
    -- ========================================================================

    container:SetScript("OnShow", function(self)
        if VE.EndeavorTracker then
            VE.EndeavorTracker:FetchEndeavorData()
        end
        self:Update()
    end)

    VE.EventBus:Register("VE_THEME_UPDATE", function()
        ApplyContainerColors()
        if container:IsShown() then
            container:Update(true)
        end
    end)

    return container
end
