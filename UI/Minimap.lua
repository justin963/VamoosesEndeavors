-- ============================================================================
-- Vamoose's Endeavors - Minimap Button & Addon Compartment
-- ============================================================================

VE = VE or {}
VE.Minimap = {}

local Minimap_Module = VE.Minimap
local minimapButton = nil

-- Minimap shape detection for square minimap addon compatibility
local function IsMinimapSquare()
    if GetMinimapShape then
        local shape = GetMinimapShape()
        return shape == "SQUARE"
    end

    if SexyMapCustomBackdrop or SexyMapSuperTrackerBackground then
        return true
    end
    if BasicMinimapSquare then
        return true
    end

    if Minimap.GetMaskTexture then
        local mask = Minimap:GetMaskTexture()
        if mask and type(mask) == "string" and mask:lower():find("square") then
            return true
        end
    end

    return false
end

-- Calculate position for square minimap
local function GetSquarePosition(angle)
    local rad = math.rad(angle)
    local x = math.cos(rad)
    local y = math.sin(rad)

    local halfSize = 80
    local maxComponent = math.max(math.abs(x), math.abs(y))
    if maxComponent > 0 then
        x = (x / maxComponent) * halfSize
        y = (y / maxComponent) * halfSize
    end

    return x, y
end

-- Calculate position for circular minimap
local function GetCircularPosition(angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * 95
    local y = math.sin(rad) * 95
    return x, y
end

function Minimap_Module:Initialize()
    -- Initialize settings
    VE_DB = VE_DB or {}
    if not VE_DB.minimap then
        VE_DB.minimap = {
            hide = false,
            minimapPos = 200,
            lock = false,
            showMinimapButton = true,
            showInCompartment = true,
        }
    end

    -- Create minimap button
    minimapButton = CreateFrame("Button", "VE_MinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Create icon
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Garrison_Building_Storehouse")
    minimapButton.icon = icon

    -- Create border
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(52, 52)
    overlay:SetPoint("TOPLEFT", 0, 0)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton.overlay = overlay

    -- Click handler
    minimapButton:SetScript("OnClick", function(self, button)
        VE:Toggle()
    end)

    -- Drag handler
    minimapButton:SetScript("OnDragStart", function(self)
        if not VE_DB.minimap.lock then
            self:SetScript("OnUpdate", function(btn)
                Minimap_Module:OnUpdate(btn)
            end)
        end
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF2aa198Vamoose's Endeavors|r", 1, 1, 1)
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Toggle window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFDrag:|r Move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Position the button
    self:UpdatePosition()

    -- Show/hide based on settings
    self:UpdateVisibility()

    -- Register with addon compartment
    self:RegisterCompartment()
end

function Minimap_Module:OnUpdate(btn)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale

    local angle = math.atan2(py - my, px - mx)
    VE_DB.minimap.minimapPos = math.deg(angle)
    self:UpdatePosition()
end

function Minimap_Module:UpdatePosition()
    if not minimapButton then return end

    minimapButton:ClearAllPoints()

    local angle = VE_DB.minimap.minimapPos or 200
    local x, y

    if IsMinimapSquare() then
        x, y = GetSquarePosition(angle)
    else
        x, y = GetCircularPosition(angle)
    end

    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Minimap_Module:UpdateVisibility()
    if not minimapButton then return end

    -- Check both legacy VE_DB.minimap and Store config (config tab uses Store)
    local storeConfig = VE.Store and VE.Store:GetState() and VE.Store:GetState().config
    local showFromConfig = storeConfig and storeConfig.showMinimapButton
    local showFromDB = VE_DB.minimap.showMinimapButton

    -- Hide if either source says to hide, or if legacy hide flag is set
    if VE_DB.minimap.hide or (showFromConfig == false) or (showFromConfig == nil and not showFromDB) then
        minimapButton:Hide()
    else
        minimapButton:Show()
    end
end

function Minimap_Module:Show()
    if minimapButton then
        VE_DB.minimap.hide = false
        VE_DB.minimap.showMinimapButton = true
        -- Also update Store config to keep in sync
        if VE.Store then
            VE.Store:Dispatch("SET_CONFIG", { key = "showMinimapButton", value = true })
        end
        self:UpdateVisibility()
    end
end

function Minimap_Module:Hide()
    if minimapButton then
        VE_DB.minimap.hide = true
        -- Also update Store config to keep in sync
        if VE.Store then
            VE.Store:Dispatch("SET_CONFIG", { key = "showMinimapButton", value = false })
        end
        self:UpdateVisibility()
    end
end

function Minimap_Module:Toggle()
    if minimapButton then
        if minimapButton:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end
end

-- ============================================================================
-- ADDON COMPARTMENT (Minimap Drawer) - Added in Dragonflight
-- ============================================================================

function Minimap_Module:RegisterCompartment()
    if not AddonCompartmentFrame or not AddonCompartmentFrame.RegisterAddon then
        return
    end

    if not VE_DB.minimap.showInCompartment then
        return
    end

    AddonCompartmentFrame:RegisterAddon({
        text = "Vamoose's Endeavors",
        icon = "Interface\\Icons\\Garrison_Building_Storehouse",
        notCheckable = true,
        func = function(btn, arg1, arg2, checked, mouseButton)
            VE:Toggle()
        end,
        funcOnEnter = function(menuItem)
            GameTooltip:SetOwner(menuItem, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFF2aa198Vamoose's Endeavors|r", 1, 1, 1)
            GameTooltip:AddLine("Track Housing Endeavor progress", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFFFFFFFFClick:|r Toggle window", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end,
        funcOnLeave = function()
            GameTooltip:Hide()
        end,
    })
end

function Minimap_Module:IsCompartmentAvailable()
    return AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon
end
