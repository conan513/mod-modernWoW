-- ModernWoW — Modern Unit Frames (Visual Overhaul v2)
-- Fully custom player + target + focus + party frames.
-- Hides the default Blizzard frames and draws new ones from scratch:
--   • Class-colored name with drop shadow
--   • Health bar: gradient green→orange→red based on HP%
--   • Power bar: class resource color
--   • Portrait with glow ring
--   • Level badge in corner
--   • Smooth update animations

ModernWoW.ModernUnitFrames = {}
local MUF = ModernWoW.ModernUnitFrames

MUF.enabled = true

local SOLID    = "Interface\\Buttons\\WHITE8X8"
local FONT     = "Fonts\\FRIZQT__.TTF"

-- ──────────────────────────────────────────────────────────────
-- Color tables
-- ──────────────────────────────────────────────────────────────

local POWER_COLORS = {
    [0] = { 0.00, 0.44, 0.87 }, -- Mana
    [1] = { 1.00, 0.00, 0.08 }, -- Rage
    [2] = { 1.00, 0.60, 0.00 }, -- Focus
    [3] = { 1.00, 0.82, 0.00 }, -- Energy
    [6] = { 0.00, 0.82, 1.00 }, -- Runic Power
}

local function GetPowerColor(unitId)
    local t = UnitPowerType(unitId)
    return unpack(POWER_COLORS[t] or POWER_COLORS[0])
end

local function GetHPGradient(pct)
    -- Full HP  : bright green
    -- 60%      : yellow-green
    -- 30%      : orange
    -- critical : red
    if pct > 0.60 then
        -- lerp green→yellow
        local f = (pct - 0.60) / 0.40
        return 0.10 + (1 - f) * 0.70, 0.80, 0.10, 1
    elseif pct > 0.30 then
        -- lerp yellow→orange
        local f = (pct - 0.30) / 0.30
        return 1.00, 0.20 + f * 0.60, 0.00, 1
    else
        -- red fade
        return 0.90, 0.10, 0.10, 1
    end
end

local function GetClassColor(unitId)
    local _, classFile = UnitClass(unitId)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- ──────────────────────────────────────────────────────────────
-- Low-level helpers
-- ──────────────────────────────────────────────────────────────

local function ApplyBorder(frame, r, g, b, a, edgeSize)
    frame:SetBackdrop({
        bgFile   = SOLID,
        edgeFile = SOLID,
        tile = false, tileSize = 0,
        edgeSize = edgeSize or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(r, g, b, a or 1)
end

-- Fills a texture from left by percentage
local function SetBarFill(bar, pct)
    local maxW = bar._maxW or bar:GetParent():GetWidth()
    bar:SetWidth(math.max(1, maxW * math.min(pct, 1)))
end

-- ──────────────────────────────────────────────────────────────
-- Bar builder — 3 layers: bg, fill (gradient), shine
-- ──────────────────────────────────────────────────────────────

local function BuildBar(parent, w, h, yOffset)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(w, h)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)

    -- Background (dark)
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(SOLID)
    bg:SetVertexColor(0.04, 0.04, 0.06, 1)

    -- Fill texture
    local fill = container:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(w)
    fill._maxW = w
    fill:SetTexture(SOLID)
    container.fill = fill

    -- Top shine stripe
    local shine = container:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    shine:SetHeight(math.max(1, math.floor(h / 3)))
    shine:SetWidth(w)
    shine._maxW = w
    shine:SetTexture(SOLID)
    shine:SetVertexColor(1, 1, 1, 0.10)
    container.shine = shine

    -- Bottom shadow stripe
    local shadow = container:CreateTexture(nil, "OVERLAY")
    shadow:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    shadow:SetHeight(1)
    shadow:SetAllPoints()
    shadow:SetTexture(SOLID)
    shadow:SetVertexColor(0, 0, 0, 0.35)

    -- Inner border (1px)
    ApplyBorder(container, 0, 0, 0, 0.6, 1)

    return container
end

-- ──────────────────────────────────────────────────────────────
-- Build one custom unit frame
-- ──────────────────────────────────────────────────────────────

local FRAME_W    = 220
local FRAME_H    = 50
local BAR_W      = 160
local HP_BAR_H   = 16
local PWR_BAR_H  = 8
local PORTRAIT_S = 44

local function BuildUnitFrame(parent, unitId, anchorFrame, anchorPoint, offX, offY)
    local f = CreateFrame("Frame", "MWoW_UF_" .. unitId, parent)
    f:SetSize(FRAME_W, FRAME_H)
    if anchorFrame then
        f:SetPoint(anchorPoint or "TOPLEFT", anchorFrame, anchorPoint or "TOPLEFT", offX or 0, offY or 0)
    end
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f.unitId = unitId

    -- ── Outer shadow ──────────────────────────────────────
    local shadow = CreateFrame("Frame", nil, f)
    shadow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    shadow:SetFrameLevel(f:GetFrameLevel() - 1)
    ApplyBorder(shadow, 0, 0, 0, 0.45)

    -- ── Main background ────────────────────────────────────
    local mainBg = f:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetTexture(SOLID)
    mainBg:SetVertexColor(0.04, 0.04, 0.07, 0.92)

    -- Colored accent strip on left edge (changes by class)
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    strip:SetWidth(3)
    strip:SetTexture(SOLID)
    f.classStrip = strip

    -- ── Portrait area ────────────────────────────────────
    local portraitFrame = CreateFrame("Frame", nil, f)
    portraitFrame:SetSize(PORTRAIT_S, PORTRAIT_S)
    portraitFrame:SetPoint("LEFT", f, "LEFT", 4, 0)

    local portrait = CreateFrame("PlayerModel", nil, portraitFrame)
    portrait:SetSize(PORTRAIT_S - 4, PORTRAIT_S - 4)
    portrait:SetPoint("CENTER", portraitFrame, "CENTER")
    portrait:SetUnit(unitId)
    f.portrait = portrait

    -- Portrait border (glow ring)
    local pBorder = portraitFrame:CreateTexture(nil, "OVERLAY")
    pBorder:SetAllPoints(portraitFrame)
    pBorder:SetTexture("Interface\\CharacterFrame\\UI-Portrait-Border")
    pBorder:SetVertexColor(0.4, 0.6, 1, 0.85)
    f.portraitBorder = pBorder

    -- ── Text area ────────────────────────────────────────
    local textX = PORTRAIT_S + 8

    -- Unit name
    local nameStr = f:CreateFontString(nil, "OVERLAY")
    nameStr:SetFont(FONT, 10, "OUTLINE")
    nameStr:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -4)
    nameStr:SetWidth(BAR_W - 6)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetShadowOffset(1, -1)
    nameStr:SetShadowColor(0, 0, 0, 1)
    f.nameStr = nameStr

    -- Level badge (right of name)
    local levelStr = f:CreateFontString(nil, "OVERLAY")
    levelStr:SetFont(FONT, 9, "OUTLINE")
    levelStr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    levelStr:SetShadowOffset(1, -1)
    levelStr:SetShadowColor(0, 0, 0, 1)
    f.levelStr = levelStr

    -- ── HP bar ──────────────────────────────────────────
    local hpBar = BuildBar(f, BAR_W, HP_BAR_H, -(FRAME_H - HP_BAR_H - PWR_BAR_H - 4))
    hpBar:ClearAllPoints()
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -18)
    f.hpBar = hpBar

    -- HP text overlay
    local hpText = hpBar:CreateFontString(nil, "OVERLAY")
    hpText:SetFont(FONT, 8, "OUTLINE")
    hpText:SetPoint("CENTER", hpBar, "CENTER")
    hpText:SetShadowOffset(1, -1)
    hpText:SetShadowColor(0, 0, 0, 1)
    f.hpText = hpText

    -- ── Power bar ────────────────────────────────────────
    local pwrBar = BuildBar(f, BAR_W, PWR_BAR_H, 0)
    pwrBar:ClearAllPoints()
    pwrBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -2)
    f.pwrBar = pwrBar

    -- ── Outer frame border ───────────────────────────────
    ApplyBorder(f, 0.18, 0.25, 0.50, 1, 1)

    f:Hide()
    return f
end

-- ──────────────────────────────────────────────────────────────
-- Update an existing frame's data
-- ──────────────────────────────────────────────────────────────

local function UpdateUnitFrame(f)
    local unit = f.unitId
    if not UnitExists(unit) then
        f:Hide()
        return
    end
    f:Show()

    -- Name + class color
    local name = UnitName(unit) or "Unknown"
    local cr, cg, cb = GetClassColor(unit)
    f.classStrip:SetVertexColor(cr, cg, cb, 1)
    f.nameStr:SetText(string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, name))

    -- Level
    local lvl = UnitLevel(unit)
    local lvlColor = (lvl < UnitLevel("player") - 4) and "|cff888888" or "|cffFFD700"
    f.levelStr:SetText(lvlColor .. lvl .. "|r")

    -- Portrait
    if f.portrait.SetUnit then
        f.portrait:SetUnit(unit)
    end

    -- HP bar
    local hp    = UnitHealth(unit)
    local hpMax = math.max(1, UnitHealthMax(unit))
    local hpPct = hp / hpMax
    local hr, hg, hb, _ = GetHPGradient(hpPct)

    f.hpBar.fill:SetVertexColor(hr * 0.7, hg * 0.7, hb * 0.7, 1)
    f.hpBar.shine:SetVertexColor(hr, hg, hb, 0.15)
    SetBarFill(f.hpBar.fill, hpPct)
    SetBarFill(f.hpBar.shine, hpPct)

    if hp >= 1000 then
        f.hpText:SetText(string.format("|cffFFFFFF%.1fk / %.1fk|r", hp/1000, hpMax/1000))
    else
        f.hpText:SetText(string.format("|cffFFFFFF%d / %d|r", hp, hpMax))
    end

    -- Power bar
    local pw    = UnitPower(unit)
    local pwMax = math.max(1, UnitPowerMax(unit))
    local pr, pg, pb = GetPowerColor(unit)
    f.pwrBar.fill:SetVertexColor(pr * 0.7, pg * 0.7, pb * 0.7, 1)
    f.pwrBar.shine:SetVertexColor(pr, pg, pb, 0.15)
    SetBarFill(f.pwrBar.fill, pw / pwMax)
    SetBarFill(f.pwrBar.shine, pw / pwMax)
end

-- ──────────────────────────────────────────────────────────────
-- Frame pool & positions
-- ──────────────────────────────────────────────────────────────

MUF.frames = {}

local UNIT_LAYOUT = {
    { unit = "player", point = "TOPLEFT",  parent = UIParent, x =  20, y = -20 },
    { unit = "target", point = "TOPRIGHT", parent = UIParent, x = -20, y = -20 },
    { unit = "focus",  point = "TOPLEFT",  parent = UIParent, x =  20, y = -90 },
}

local function InitFrames()
    -- Hide the default Blizzard player / target frames
    PlayerFrame:Hide()
    PlayerFrame:UnregisterAllEvents()
    TargetFrame:Hide()
    TargetFrame:UnregisterAllEvents()
    if FocusFrame then
        FocusFrame:Hide()
        FocusFrame:UnregisterAllEvents()
    end
    -- Hide party frames (they will be replaced separately if needed)

    for _, layout in ipairs(UNIT_LAYOUT) do
        local f = BuildUnitFrame(
            layout.parent or UIParent,
            layout.unit,
            layout.parent or UIParent,
            layout.point,
            layout.x, layout.y
        )
        MUF.frames[layout.unit] = f
    end

    -- Party frames
    for i = 1, 4 do
        local unitId = "party" .. i
        local f = BuildUnitFrame(UIParent, unitId, UIParent, "TOPLEFT", 20, -20 - i * (FRAME_H + 6))
        MUF.frames[unitId] = f
    end
end

local function RefreshAll()
    if not MUF.enabled or not ModernWoW:GetSetting("modernFrames") then return end
    for _, f in pairs(MUF.frames) do
        UpdateUnitFrame(f)
    end
end

-- ──────────────────────────────────────────────────────────────
-- Event registration
-- ──────────────────────────────────────────────────────────────

local ufEvents = CreateFrame("Frame", "MWoW_UnitFrameEvents")

ufEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
ufEvents:RegisterEvent("PLAYER_LOGIN")
ufEvents:RegisterEvent("UNIT_HEALTH")
ufEvents:RegisterEvent("UNIT_POWER_UPDATE")
ufEvents:RegisterEvent("UNIT_MAXHEALTH")
ufEvents:RegisterEvent("UNIT_DISPLAYPOWER")
ufEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
ufEvents:RegisterEvent("PLAYER_FOCUS_CHANGED")
ufEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
ufEvents:RegisterEvent("PARTY_MEMBERS_CHANGED")

ufEvents:SetScript("OnEvent", function(self, event, unitId)
    if not MUF.enabled or not ModernWoW:GetSetting("modernFrames") then return end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        -- Defer init to make sure Blizzard frames exist
        C_Timer_After = C_Timer_After or function(t, fn) fn() end
        local ticker = 0
        local checkFrame = CreateFrame("Frame")
        checkFrame:SetScript("OnUpdate", function(this, elapsed)
            ticker = ticker + elapsed
            if ticker > 0.5 then
                this:SetScript("OnUpdate", nil)
                if not MUF._initialized then
                    MUF._initialized = true
                    InitFrames()
                end
                RefreshAll()
            end
        end)
        return
    end

    -- Per-unit refresh
    if unitId then
        local f = MUF.frames[unitId]
        if f then UpdateUnitFrame(f) end
    else
        RefreshAll()
    end
end)

-- Periodic update ticker for smooth animations
local ticker = CreateFrame("Frame")
local tickElapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    if not MUF.enabled then return end
    tickElapsed = tickElapsed + elapsed
    if tickElapsed > 0.15 then -- ~6 fps for HP bar
        tickElapsed = 0
        for _, f in pairs(MUF.frames) do
            if f:IsShown() then UpdateUnitFrame(f) end
        end
    end
end)

function MUF:SetEnabled(val)
    self.enabled = val
    if not val then
        -- Restore Blizzard frames
        PlayerFrame:Show()
        PlayerFrame:RegisterEvent("UNIT_HEALTH")
        TargetFrame:Show()
        TargetFrame:RegisterEvent("UNIT_HEALTH")
        for _, f in pairs(MUF.frames) do f:Hide() end
    else
        RefreshAll()
    end
end

ModernWoW:Debug("ModernUnitFrames module loaded (v2).")
