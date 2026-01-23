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

function VE.UI.Tabs:CreateEndeavors(parent)
    local UI = VE.Constants.UI

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local padding = UI.panelPadding

    -- ========================================================================
    -- TASKS HEADER
    -- ========================================================================

    local tasksHeader = VE.UI:CreateSectionHeader(container, "Endeavor Tasks")
    tasksHeader:SetPoint("TOPLEFT", padding, 0)
    tasksHeader:SetPoint("TOPRIGHT", -padding, 0)

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
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 2)
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
            -- Show empty state
            local colors = GetColors()
            if not self.emptyText then
                self.emptyText = self.scrollContent:CreateFontString(nil, "OVERLAY")
                self.emptyText:SetPoint("CENTER", self.scrollContent, "CENTER", 0, 0)
            end
            VE.Theme.ApplyFont(self.emptyText, colors)
            self.emptyText:SetText("No endeavor tasks found.\nOpen the Housing Dashboard to sync data.")
            self.emptyText:SetTextColor(colors.text_dim.r, colors.text_dim.g, colors.text_dim.b, colors.text_dim.a)
            self.emptyText:Show()
            self.scrollContent:SetHeight(100)
            return
        end

        if self.emptyText then
            self.emptyText:Hide()
        end

        local yOffset = 0
        local rowHeight = VE.Constants.UI.taskRowHeight
        local rowSpacing = VE.Constants.UI.rowSpacing

        for i, task in ipairs(tasks) do
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

    return container
end
