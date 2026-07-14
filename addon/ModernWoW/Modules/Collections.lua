-- ModernWoW — Collections Journal (Visual Overhaul v2)
-- Premium icon-grid window with gold border, glow on hover,
-- animated tab switching, scrollable content, quality badge on icons,
-- and a count + search hint in the footer.

ModernWoW.Collections = {}
local COL = ModernWoW.Collections

COL.enabled = true
COL.frame   = nil
COL.tab     = "mounts"

local WIN_W       = 520
local WIN_H       = 410
local ICON_SIZE   = 48
local ICON_PAD    = 5
local ICONS_PER_ROW = 9
local HEADER_H    = 44
local TAB_H       = 28
local FOOTER_H    = 28
local SOLID       = "Interface\\Buttons\\WHITE8X8"
local FONT        = "Fonts\\FRIZQT__.TTF"

-- Gold/blue color theme
local GOLD_R, GOLD_G, GOLD_B = 0.82, 0.65, 0.18

-- ──────────────────────────────────────────────────────────────
-- Backdrop helper
-- ──────────────────────────────────────────────────────────────

local function ApplyBorder(f, br, bg_c, bb, ba, er, eg, eb, ea, edge)
    f:SetBackdrop({
        bgFile   = SOLID,
        edgeFile = SOLID,
        tile = false, tileSize = 0,
        edgeSize = edge or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(br, bg_c, bb, ba)
    f:SetBackdropBorderColor(er, eg, eb, ea)
end

-- ──────────────────────────────────────────────────────────────
-- Tab button builder
-- ──────────────────────────────────────────────────────────────

local function BuildTab(parent, label, index, totalTabs, onClick)
    local tw = math.floor((WIN_W - 20) / totalTabs)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(tw, TAB_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10 + (index - 1) * tw, -HEADER_H)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(SOLID)
    btn._bg = bg

    local line = btn:CreateTexture(nil, "OVERLAY")
    line:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)
    line:SetTexture(SOLID)
    btn._line = line

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(FONT, 11, "OUTLINE")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetShadowOffset(1, -1)
    lbl:SetShadowColor(0, 0, 0, 1)
    btn._lbl = lbl
    btn._label = label

    btn:SetScript("OnClick", function(self)
        onClick(self)
    end)
    btn:SetScript("OnEnter", function(self)
        if not self._active then
            self._bg:SetVertexColor(0.12, 0.12, 0.18, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self._active then
            self._bg:SetVertexColor(0.06, 0.06, 0.10, 1)
        end
    end)

    return btn
end

local function SetTabActive(btn, active)
    btn._active = active
    if active then
        btn._bg:SetVertexColor(0.10, 0.14, 0.28, 1)
        btn._line:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
        btn._lbl:SetText(string.format("|cff%02x%02x%02x%s|r",
            GOLD_R*255, GOLD_G*255, GOLD_B*255, btn._label))
    else
        btn._bg:SetVertexColor(0.06, 0.06, 0.10, 1)
        btn._line:SetVertexColor(0.15, 0.15, 0.22, 1)
        btn._lbl:SetText("|cff888888" .. btn._label .. "|r")
    end
end

-- ──────────────────────────────────────────────────────────────
-- Individual icon button
-- ──────────────────────────────────────────────────────────────

local function CreateIconBtn(parent, slot)
    local col = (slot - 1) % ICONS_PER_ROW
    local row = math.floor((slot - 1) / ICONS_PER_ROW)
    local x   = col * (ICON_SIZE + ICON_PAD) + ICON_PAD
    local y   = -(row * (ICON_SIZE + ICON_PAD) + ICON_PAD)

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Dark icon background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(SOLID)
    bg:SetVertexColor(0.06, 0.06, 0.08, 1)

    -- Icon texture (inset 1px)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     1,  -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1,  1)
    btn.icon = icon

    -- Outer border (default grey)
    local border = CreateFrame("Frame", nil, btn)
    border:SetAllPoints()
    ApplyBorder(border, 0, 0, 0, 0, 0.25, 0.25, 0.30, 1, 1)
    border:SetFrameLevel(btn:GetFrameLevel() + 1)
    btn.border = border

    -- Hover glow (hidden by default)
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetTexture(SOLID)
    glow:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0)
    btn.glow = glow

    -- Bottom name strip
    local nameBar = btn:CreateTexture(nil, "OVERLAY")
    nameBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    nameBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    nameBar:SetHeight(12)
    nameBar:SetTexture(SOLID)
    nameBar:SetVertexColor(0, 0, 0, 0.65)

    -- Hover name label (inside name strip)
    local nameLbl = btn:CreateFontString(nil, "OVERLAY")
    nameLbl:SetFont(FONT, 7, "OUTLINE")
    nameLbl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
    nameLbl:SetWidth(ICON_SIZE - 2)
    nameLbl:SetJustifyH("CENTER")
    nameLbl:SetTextColor(1, 1, 1, 0)  -- invisible until hover
    btn.nameLbl = nameLbl

    btn:SetScript("OnEnter", function(self)
        self.glow:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.25)
        ApplyBorder(self.border, 0, 0, 0, 0, GOLD_R, GOLD_G, GOLD_B, 1, 1)
        self.nameLbl:SetTextColor(1, 1, 1, 1)
        if self.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellId)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.glow:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0)
        ApplyBorder(self.border, 0, 0, 0, 0, 0.25, 0.25, 0.30, 1, 1)
        self.nameLbl:SetTextColor(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        if self.spellId then
            -- Use/summon the mount/pet
            CallCompanion(self.companionType or "MOUNT", self.companionIndex or 1)
        end
    end)

    btn:Hide()
    return btn
end

-- ──────────────────────────────────────────────────────────────
-- Main window builder
-- ──────────────────────────────────────────────────────────────

local function BuildWindow()
    local f = CreateFrame("Frame", "MWoW_Collections", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- Outer shadow
    local shadow = CreateFrame("Frame", nil, f)
    shadow:SetPoint("TOPLEFT",     f, "TOPLEFT",     -4,  4)
    shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  4, -4)
    shadow:SetFrameLevel(f:GetFrameLevel() - 1)
    ApplyBorder(shadow, 0, 0, 0, 0.4, 0, 0, 0, 0)

    -- Main background (dark navy)
    local mainBg = f:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetTexture(SOLID)
    mainBg:SetVertexColor(0.04, 0.04, 0.07, 0.97)

    -- Gold outer border
    ApplyBorder(f, 0.04, 0.04, 0.07, 0.97, GOLD_R, GOLD_G, GOLD_B, 1, 1)

    -- ── Header ────────────────────────────────────────────
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)

    local hbg = header:CreateTexture(nil, "ARTWORK")
    hbg:SetAllPoints()
    hbg:SetTexture(SOLID)
    hbg:SetGradientAlpha("VERTICAL",
        0.10, 0.09, 0.04, 1,   -- top: dark gold tint
        0.05, 0.04, 0.08, 1)   -- bottom: navy

    -- Gold top line
    local topLine = header:CreateTexture(nil, "OVERLAY")
    topLine:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    topLine:SetHeight(2)
    topLine:SetTexture(SOLID)
    topLine:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)

    -- Title icon + text
    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 16, "OUTLINE")
    title:SetPoint("LEFT", header, "LEFT", 14, 0)
    title:SetShadowOffset(2, -2)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetText(string.format("|cff%02x%02x%02x📚 Collections|r",
        GOLD_R*255, GOLD_G*255, GOLD_B*255))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetTexture(SOLID)
    closeBg:SetVertexColor(0.50, 0.08, 0.08, 0.85)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLbl:SetFont(FONT, 12, "OUTLINE")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("|cffFFFFFF✕|r")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBg:SetVertexColor(0.80, 0.15, 0.15, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBg:SetVertexColor(0.50, 0.08, 0.08, 0.85) end)

    -- ── Tabs ──────────────────────────────────────────────
    local tabs = {}
    local function OnTabClick(btn)
        for _, t in ipairs(tabs) do SetTabActive(t, t == btn) end
        COL.tab = btn._tabId
        COL:Populate()
    end

    local tabDefs = { { id="mounts", label="🐴  Mounts" }, { id="pets", label="🐾  Companions" } }
    for i, td in ipairs(tabDefs) do
        local t = BuildTab(f, td.label, i, #tabDefs, OnTabClick)
        t._tabId = td.id
        tabs[i] = t
    end
    f.tabs = tabs
    SetTabActive(tabs[1], true)

    -- ── Scroll area ────────────────────────────────────────
    local scrollY = HEADER_H + TAB_H + 4
    local contentH = WIN_H - scrollY - FOOTER_H - 6

    local scroll = CreateFrame("ScrollFrame", "MWoW_CollScroll", f)
    scroll:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -scrollY)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, FOOTER_H + 6)

    -- Scroll background
    local scrollBg = scroll:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints()
    scrollBg:SetTexture(SOLID)
    scrollBg:SetVertexColor(0.03, 0.03, 0.05, 1)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(WIN_W - 16)
    child:SetHeight(2000)
    scroll:SetScrollChild(child)
    f.iconContainer = child

    -- Scrollbar
    local sb = CreateFrame("Slider", "MWoW_CollScrollBar", scroll, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT",    scroll, "TOPRIGHT",    20, -16)
    sb:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 20,  16)
    sb:SetMinMaxValues(0, 1000)
    sb:SetValueStep(20)
    sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(self, val)
        scroll:SetVerticalScroll(val)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = sb:GetValue()
        sb:SetValue(math.max(0, cur - delta * 40))
    end)

    -- ── Footer ─────────────────────────────────────────────
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1, 1)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)

    local fbg = footer:CreateTexture(nil, "ARTWORK")
    fbg:SetAllPoints()
    fbg:SetTexture(SOLID)
    fbg:SetGradientAlpha("VERTICAL",
        0.05, 0.04, 0.08, 1,
        0.08, 0.07, 0.04, 1)

    -- Gold bottom line
    local botLine = footer:CreateTexture(nil, "OVERLAY")
    botLine:SetPoint("BOTTOMLEFT",  footer, "BOTTOMLEFT",  0, 0)
    botLine:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 0)
    botLine:SetHeight(2)
    botLine:SetTexture(SOLID)
    botLine:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)

    local countLbl = footer:CreateFontString(nil, "OVERLAY")
    countLbl:SetFont(FONT, 10, "OUTLINE")
    countLbl:SetPoint("LEFT", footer, "LEFT", 10, 0)
    countLbl:SetShadowOffset(1, -1)
    countLbl:SetShadowColor(0, 0, 0, 1)
    f.countLbl = countLbl

    local hintLbl = footer:CreateFontString(nil, "OVERLAY")
    hintLbl:SetFont(FONT, 8, "OUTLINE")
    hintLbl:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
    hintLbl:SetTextColor(0.45, 0.45, 0.55, 1)
    hintLbl:SetText("Click to summon • Hover for details")

    f.iconPool = {}
    return f
end

-- ──────────────────────────────────────────────────────────────
-- Populate the grid
-- ──────────────────────────────────────────────────────────────

function COL:Populate()
    if not self.frame then return end

    for _, btn in ipairs(self.frame.iconPool) do btn:Hide() end

    local items = {}
    local compType = (self.tab == "mounts") and "MOUNT" or "CRITTER"
    local num = GetNumCompanions(compType)
    for i = 1, num do
        local _, name, spellId, icon = GetCompanionInfo(compType, i)
        items[#items + 1] = { name = name, icon = icon, spellId = spellId, idx = i }
    end

    -- Count label
    local typeName = (self.tab == "mounts") and "Mounts" or "Companions"
    self.frame.countLbl:SetText(string.format(
        "|cff%02x%02x%02x%s collected:|r |cffFFFFFF%d|r",
        GOLD_R*255, GOLD_G*255, GOLD_B*255, typeName, #items))

    -- Ensure pool is large enough
    for i = #self.frame.iconPool + 1, #items do
        self.frame.iconPool[i] = CreateIconBtn(self.frame.iconContainer, i)
    end

    for i, item in ipairs(items) do
        local btn = self.frame.iconPool[i]
        -- Re-position (in case pool was built before we knew the slot)
        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        btn:SetPoint("TOPLEFT", self.frame.iconContainer, "TOPLEFT",
            col * (ICON_SIZE + ICON_PAD) + ICON_PAD,
            -(row * (ICON_SIZE + ICON_PAD) + ICON_PAD))

        btn.icon:SetTexture(item.icon)
        btn.nameLbl:SetText(item.name or "")
        btn.spellId = item.spellId
        btn.companionType  = compType
        btn.companionIndex = item.idx
        btn:Show()
    end

    -- Resize scroll child
    local rows = math.max(1, math.ceil(#items / ICONS_PER_ROW))
    self.frame.iconContainer:SetHeight(rows * (ICON_SIZE + ICON_PAD) + ICON_PAD)
end

-- ──────────────────────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────────────────────

function COL:Toggle()
    if not self.frame then
        self.frame = BuildWindow()
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Populate()
        self.frame:Show()
        -- Activate correct tab visually
        for _, t in ipairs(self.frame.tabs) do
            SetTabActive(t, t._tabId == self.tab)
        end
    end
end

SLASH_MWOWCOL1 = "/mwowcol"
SLASH_MWOWCOL2 = "/collections"
SlashCmdList["MWOWCOL"] = function()
    COL:Toggle()
end

ModernWoW:Debug("Collections module loaded (v2).")
