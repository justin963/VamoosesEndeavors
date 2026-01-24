-- ============================================================================
-- Vamoose's Endeavors - Theme Engine
-- Manages theme registry and skinners for live theme switching
-- ============================================================================

VE = VE or {}
VE.Theme = {}

-- Weak table: automatically stops tracking widgets if they are garbage collected
VE.Theme.registry = setmetatable({}, { __mode = "k" })
VE.Theme.currentScheme = nil  -- Set during initialization

-- ============================================================================
-- CENTRALIZED BACKDROP
-- ============================================================================

VE.Theme.BACKDROP_FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

VE.Theme.BACKDROP_BORDERLESS = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = nil,
    tile = false,
}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function VE.Theme:Initialize()
    -- Set initial scheme based on saved config
    local themeKey = "housingtheme"
    if VE.Store and VE.Store.state and VE.Store.state.config then
        themeKey = VE.Store.state.config.theme or "housingtheme"
    elseif VE_DB and VE_DB.config and VE_DB.config.theme then
        themeKey = VE_DB.config.theme or "housingtheme"
    end
    -- Convert key to scheme name using ThemeNames lookup
    local themeName = VE.Constants.ThemeNames[themeKey] or "HousingTheme"
    self.currentScheme = VE.Colors.Schemes[themeName] or VE.Colors.Schemes.HousingTheme

    -- Listen for theme update events
    if VE.EventBus then
        VE.EventBus:Register("VE_THEME_UPDATE", function(payload)
            -- Only change scheme if themeName explicitly provided
            if payload.themeName then
                self.currentScheme = VE.Colors.Schemes[payload.themeName] or VE.Colors.Schemes.SolarizedDark
            end
            self:UpdateAll()
        end)
    end
end

-- ============================================================================
-- UPDATE ALL REGISTERED WIDGETS
-- ============================================================================

function VE.Theme:UpdateAll()
    for widget, widgetType in pairs(self.registry) do
        if self.Skinners[widgetType] then
            self.Skinners[widgetType](widget, self.currentScheme)
        end
    end
end

-- ============================================================================
-- REGISTER WIDGET
-- ============================================================================

function VE.Theme:Register(widget, widgetType)
    self.registry[widget] = widgetType
    -- Apply current theme immediately
    if self.Skinners[widgetType] and self.currentScheme then
        self.Skinners[widgetType](widget, self.currentScheme)
    end
end

-- ============================================================================
-- GET CURRENT SCHEME
-- ============================================================================

function VE.Theme:GetScheme()
    return self.currentScheme or VE.Colors.Schemes.SolarizedDark
end

-- ============================================================================
-- TEXT STYLING HELPERS
-- ============================================================================

local function ApplyTextShadow(fontString, scheme)
    if not fontString or not fontString.SetShadowOffset then return end
    fontString:SetShadowOffset(1, -1)
    if scheme.isLight then
        local r, g, b = fontString:GetTextColor()
        fontString:SetShadowColor(r, g, b, 0.4)
    else
        fontString:SetShadowColor(0, 0, 0, 1)
    end
end

-- Apply font settings + shadow (fontType: "header", "body", or "small")
local function ApplyFont(fontString, scheme, fontType)
    if not fontString or not fontString.SetFont then return end
    fontType = fontType or "body"
    local f = scheme.fonts and scheme.fonts[fontType] or scheme.fonts.body
    if f then
        local fontFile = VE.Constants:GetFontFile()
        local fontScale = 0
        if VE.Store and VE.Store.state and VE.Store.state.config then
            fontScale = VE.Store.state.config.fontScale or 0
        end
        fontString:SetFont(fontFile, f.size + fontScale, f.flags)
    end
    ApplyTextShadow(fontString, scheme)
end

VE.Theme.ApplyTextShadow = ApplyTextShadow
VE.Theme.ApplyFont = ApplyFont

-- Get background opacity multiplier from config
local function GetBgOpacity()
    if VE.Store and VE.Store.state and VE.Store.state.config then
        return VE.Store.state.config.bgOpacity or 0.9
    end
    return 0.9
end
VE.Theme.GetBgOpacity = GetBgOpacity

-- ============================================================================
-- ATLAS TEXTURE HELPERS
-- ============================================================================

-- Apply Atlas background texture to a frame (creates/reuses texture layer)
local function ApplyAtlasBackground(frame, atlasName)
    if not frame or not atlasName then return end
    if not frame._atlasBg then
        frame._atlasBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._atlasBg:SetAllPoints()
    end
    frame._atlasBg:SetAtlas(atlasName, true)
    frame._atlasBg:Show()
end

-- Apply Atlas header bar to a frame's title bar area
local function ApplyAtlasHeader(titleBar, atlasName)
    if not titleBar or not atlasName then return end
    if not titleBar._atlasHeader then
        titleBar._atlasHeader = titleBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        titleBar._atlasHeader:SetAllPoints()
    end
    titleBar._atlasHeader:SetAtlas(atlasName, true)
    titleBar._atlasHeader:Show()
end

-- Hide Atlas textures (for switching to non-Atlas themes)
local function HideAtlasTextures(frame)
    if frame._atlasBg then frame._atlasBg:Hide() end
    if frame._atlasHeader then frame._atlasHeader:Hide() end
end

VE.Theme.ApplyAtlasBackground = ApplyAtlasBackground
VE.Theme.ApplyAtlasHeader = ApplyAtlasHeader
VE.Theme.HideAtlasTextures = HideAtlasTextures

-- ============================================================================
-- SKINNERS (Pure functions that apply colors to widgets)
-- ============================================================================

VE.Theme.Skinners = {

    -- Window/Frame skinner (Atlas-aware)
    Frame = function(f, c)
        -- Handle Atlas textures if theme has them
        if c.atlas and c.atlas.background then
            ApplyAtlasBackground(f, c.atlas.background)
            -- Still apply border color but make backdrop mostly transparent
            if f:GetBackdrop() then
                f:SetBackdropColor(0, 0, 0, 0) -- Transparent, let Atlas show through
                f:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
            end
        else
            -- Standard color-based backdrop
            HideAtlasTextures(f)
            if f:GetBackdrop() then
                local opacity = GetBgOpacity()
                f:SetBackdropColor(c.bg.r, c.bg.g, c.bg.b, c.bg.a * opacity)
                f:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
            end
        end
        if f.title then
            f.title:SetTextColor(c.text_header.r, c.text_header.g, c.text_header.b, c.text_header.a)
            ApplyFont(f.title, c)
        end
    end,

    -- Panel skinner
    Panel = function(f, c)
        if f:GetBackdrop() then
            local opacity = GetBgOpacity()
            f:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * opacity)
            f:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
        end
    end,

    -- Button skinner
    Button = function(b, c)
        if b:GetBackdrop() then
            b:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a)
            b:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
        end
        if b.bg then
            b.bg:SetColorTexture(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a)
        end
        -- Text
        local fs = b:GetFontString()
        if fs then
            fs:SetTextColor(c.button_text_norm.r, c.button_text_norm.g, c.button_text_norm.b, c.button_text_norm.a)
            ApplyFont(fs, c)
        end
        -- Hover texture
        if b.hoverTex then
            b.hoverTex:SetColorTexture(c.button_hover.r, c.button_hover.g, c.button_hover.b, c.button_hover.a)
        end
        -- Store colors for hover scripts
        b._scheme = c
    end,

    -- Text/Label skinner
    Text = function(fs, c)
        if fs.isHeader then
            fs:SetTextColor(c.text_header.r, c.text_header.g, c.text_header.b, c.text_header.a)
        else
            fs:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
        end
        ApplyFont(fs, c)
    end,

    -- Section Header skinner
    SectionHeader = function(f, c)
        if f.label then
            f.label:SetTextColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a)
            ApplyFont(f.label, c)
        end
        if f.line then
            f.line:SetVertexColor(c.text_dim.r, c.text_dim.g, c.text_dim.b, c.text_dim.a * 0.5)
        end
    end,

    -- Progress Bar skinner
    ProgressBar = function(f, c)
        if f:GetBackdrop() then
            local opacity = GetBgOpacity()
            f:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * opacity)
            f:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
        end
        if f.fill then
            f.fill:SetVertexColor(c.endeavor.r, c.endeavor.g, c.endeavor.b, c.endeavor.a)
        end
        if f.text then
            f.text:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
            ApplyFont(f.text, c)
        end
    end,

    -- Task Row skinner (Atlas-aware for XP badges)
    TaskRow = function(f, c)
        if f:GetBackdrop() then
            local opacity = GetBgOpacity()
            f:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * 0.5 * opacity)
        end
        if f.name then
            f.name:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
            ApplyFont(f.name, c)
        end
        if f.progress then
            f.progress:SetTextColor(c.text_dim.r, c.text_dim.g, c.text_dim.b, c.text_dim.a)
            ApplyFont(f.progress, c)
        end
        if f.points then
            -- Use success color (green) for Atlas theme, endeavor for others
            local pointsColor = (c.atlas and c.atlas.xpBanner) and c.success or c.endeavor
            if pointsColor then
                f.points:SetTextColor(pointsColor.r, pointsColor.g, pointsColor.b, pointsColor.a)
            end
            ApplyFont(f.points, c)
        end
        -- Points badge with Atlas support
        if f.pointsBg then
            if c.atlas and c.atlas.xpBanner then
                -- Create atlas texture at BACKGROUND layer
                if not f.pointsBg._atlasBanner then
                    f.pointsBg._atlasBanner = f.pointsBg:CreateTexture(nil, "BACKGROUND")
                    f.pointsBg._atlasBanner:SetAllPoints()
                end
                -- Remove backdrop entirely so atlas shows
                f.pointsBg:SetBackdrop(nil)
                local success = f.pointsBg._atlasBanner:SetAtlas(c.atlas.xpBanner, true)
                if not success then
                    f.pointsBg._atlasBanner:SetColorTexture(0.2, 0.5, 0.2, 0.8)
                end
                f.pointsBg._atlasBanner:Show()
            else
                -- Standard color-based badge
                if f.pointsBg._atlasBanner then f.pointsBg._atlasBanner:Hide() end
                -- Restore backdrop if needed
                if not f.pointsBg:GetBackdrop() then
                    f.pointsBg:SetBackdrop(VE.Theme.BACKDROP_FLAT)
                end
                f.pointsBg:SetBackdropColor(c.endeavor.r, c.endeavor.g, c.endeavor.b, c.endeavor.a * 0.3)
                f.pointsBg:SetBackdropBorderColor(c.endeavor.r, c.endeavor.g, c.endeavor.b, c.endeavor.a * 0.6)
            end
        end
        if f.couponText then
            f.couponText:SetTextColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a)
            ApplyFont(f.couponText, c)
        end
        if f.couponBg and f.couponBg.GetBackdrop and f.couponBg:GetBackdrop() then
            f.couponBg:SetBackdropColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a * 0.3)
            f.couponBg:SetBackdropBorderColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a * 0.6)
        end
        -- Store colors for hover scripts
        f._scheme = c
    end,

    -- Dropdown skinner
    Dropdown = function(f, c)
        if f:GetBackdrop() then
            local opacity = GetBgOpacity()
            f:SetBackdropColor(c.panel.r, c.panel.g, c.panel.b, c.panel.a * opacity)
            f:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
        end
        if f.text then
            f.text:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
            ApplyFont(f.text, c)
        end
        if f.menu and f.menu.GetBackdrop and f.menu:GetBackdrop() then
            f.menu:SetBackdropColor(c.bg.r, c.bg.g, c.bg.b, c.bg.a)
            f.menu:SetBackdropBorderColor(c.border.r, c.border.g, c.border.b, c.border.a)
        end
    end,

    -- Scroll Frame skinner
    ScrollFrame = function(f, c)
        local scrollBar = f.ScrollBar
        if scrollBar then
            local thumb = scrollBar:GetThumbTexture()
            if thumb then
                thumb:SetVertexColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a)
            end
        end
    end,

    -- Checkbox skinner
    Checkbox = function(f, c)
        if f.boxBg then
            f.boxBg:SetColorTexture(c.panel.r, c.panel.g, c.panel.b, c.panel.a)
        end
        if f.text then
            f.text:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
            ApplyFont(f.text, c)
        end
    end,

    -- Title Bar skinner (borderless, Atlas-aware)
    TitleBar = function(f, c)
        -- Handle Atlas header texture if theme has it
        if c.atlas and c.atlas.headerBar then
            ApplyAtlasHeader(f, c.atlas.headerBar)
            if f:GetBackdrop() then
                f:SetBackdropColor(0, 0, 0, 0) -- Transparent, let Atlas show through
            end
        else
            HideAtlasTextures(f)
            if f:GetBackdrop() then
                f:SetBackdropColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a * 0.3)
            end
        end
        -- For Atlas themes, use text_header (gold) instead of accent for title
        local titleColor = (c.atlas and c.atlas.headerBar) and c.text_header or c.accent
        if f.titleText then
            f.titleText:SetTextColor(titleColor.r, titleColor.g, titleColor.b, titleColor.a)
            ApplyFont(f.titleText, c)
        end
        -- Refresh button (update _scheme for hover scripts)
        if f.refreshBtn then
            f.refreshBtn._scheme = c
            f.refreshBtn:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a)
        end
        -- Title bar button texts (use titleColor for Atlas themes)
        if f.refreshText then
            f.refreshText:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
            ApplyFont(f.refreshText, c)
        end
        if f.minimizeIcon then
            f.minimizeIcon:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
            ApplyFont(f.minimizeIcon, c)
        end
        -- themeIcon and closeIcon are atlas textures, no color update needed
    end,

    -- Tab Button skinner (Atlas-aware with 3-part left/center/right)
    TabButton = function(btn, c)
        local CAP_WIDTH = 12 -- Width of left/right tab edge caps
        -- Handle Atlas textures for tabs if theme has them
        if c.atlas and c.atlas.tabActive and c.atlas.tabInactive then
            -- Create 3-part atlas textures: left cap, center (stretched), right cap
            if not btn._atlasTabLeft then
                btn._atlasTabLeft = btn:CreateTexture(nil, "BACKGROUND")
                btn._atlasTabLeft:SetPoint("TOPLEFT", 0, 0)
                btn._atlasTabLeft:SetPoint("BOTTOMLEFT", 0, 0)
                btn._atlasTabLeft:SetWidth(CAP_WIDTH)
            end
            if not btn._atlasTabCenter then
                btn._atlasTabCenter = btn:CreateTexture(nil, "BACKGROUND")
                btn._atlasTabCenter:SetPoint("TOPLEFT", btn._atlasTabLeft, "TOPRIGHT", 0, 0)
                btn._atlasTabCenter:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -CAP_WIDTH, 0)
            end
            if not btn._atlasTabRight then
                btn._atlasTabRight = btn:CreateTexture(nil, "BACKGROUND")
                btn._atlasTabRight:SetPoint("TOPRIGHT", 0, 0)
                btn._atlasTabRight:SetPoint("BOTTOMRIGHT", 0, 0)
                btn._atlasTabRight:SetWidth(CAP_WIDTH)
            end
            -- Hide any existing bottom line
            if btn._bottomLine then btn._bottomLine:Hide() end
            -- Hide backdrop completely
            btn:SetBackdrop(nil)
            -- Set appropriate atlases based on active state
            local leftAtlas = btn.isActive and c.atlas.tabActiveLeft or c.atlas.tabInactiveLeft
            local centerAtlas = btn.isActive and c.atlas.tabActive or c.atlas.tabInactive
            local rightAtlas = btn.isActive and c.atlas.tabActiveRight or c.atlas.tabInactiveRight
            btn._atlasTabLeft:SetAtlas(leftAtlas or centerAtlas, true)
            btn._atlasTabCenter:SetAtlas(centerAtlas, true)
            btn._atlasTabRight:SetAtlas(rightAtlas or centerAtlas, true)
            -- Flip vertically (Blizzard tabs are upside-down relative to our layout)
            btn._atlasTabLeft:SetTexCoord(0, 1, 1, 0)
            btn._atlasTabCenter:SetTexCoord(0, 1, 1, 0)
            btn._atlasTabRight:SetTexCoord(0, 1, 1, 0)
            btn._atlasTabLeft:Show()
            btn._atlasTabCenter:Show()
            btn._atlasTabRight:Show()
            if btn.label then
                local textColor = btn.isActive and c.text_header or c.text
                btn.label:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a)
            end
        else
            -- Standard color-based tabs - hide atlas textures and restore backdrop
            if btn._atlasTabLeft then btn._atlasTabLeft:Hide() end
            if btn._atlasTabCenter then btn._atlasTabCenter:Hide() end
            if btn._atlasTabRight then btn._atlasTabRight:Hide() end
            if btn._bottomLine then btn._bottomLine:Hide() end
            if not btn:GetBackdrop() then
                btn:SetBackdrop(VE.Theme.BACKDROP_FLAT)
            end
            if btn.isActive then
                btn:SetBackdropColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a * 0.4)
                btn:SetBackdropBorderColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a * 0.8)
                if btn.label then
                    btn.label:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
                end
            else
                btn:SetBackdropColor(c.button_normal.r, c.button_normal.g, c.button_normal.b, c.button_normal.a * 0.6)
                btn:SetBackdropBorderColor(c.text_dim.r, c.text_dim.g, c.text_dim.b, c.text_dim.a * 0.5)
                if btn.label then
                    btn.label:SetTextColor(c.text_dim.r, c.text_dim.g, c.text_dim.b, c.text_dim.a)
                end
            end
        end
        if btn.label then
            ApplyFont(btn.label, c)
        end
        btn._scheme = c
    end,

    -- Header Text skinner (for seasonName, daysRemaining, etc.)
    HeaderText = function(fs, c)
        local colorType = fs._colorType or "text"
        if colorType == "text" then
            fs:SetTextColor(c.text.r, c.text.g, c.text.b, c.text.a)
        elseif colorType == "text_dim" then
            fs:SetTextColor(c.text_dim.r, c.text_dim.g, c.text_dim.b, c.text_dim.a)
        elseif colorType == "warning" then
            fs:SetTextColor(c.warning.r, c.warning.g, c.warning.b, c.warning.a)
        elseif colorType == "endeavor" then
            fs:SetTextColor(c.endeavor.r, c.endeavor.g, c.endeavor.b, c.endeavor.a)
        elseif colorType == "accent" then
            fs:SetTextColor(c.accent.r, c.accent.g, c.accent.b, c.accent.a)
        end
        ApplyFont(fs, c)
    end,
}
