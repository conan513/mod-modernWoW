-- ModernWoW — Damage Meter Module (Visual Overhaul v2)
-- Multi-layer bar design, gradient fills, animated transitions,
-- class-color support, glow border, and header with combat timer.

ModernWoW.DamageMeter = {}
local DM = ModernWoW.DamageMeter

DM.enabled    = true
DM.tracking   = {}
DM.combatStart = 0
DM.inCombat   = false
DM.mode       = "damage"  -- "damage" or "healing"

local WIN_W   = 240
local WIN_H   = 280
local ROW_H   = 22
local MAX_ROWS = 10
local HEADER_H = 28
local FOOTER_H = 20

local SOLID = "Interface\\Buttons\\WHITE8X8"

-- ============================================================
-- Class colors (WotLK RAID_CLASS_COLORS fallback)
-- ============================================================

local PLAYER_COLORS = {
    { r=0.00, g=0.44, b=0.87 }, -- blue
    { r=0.20, g=0.85, b=0.30 }, -- green
    { r=1.00, g=0.50, b=0.10 }, -- orange
    { r=0.80, g=0.15, b=0.85 }, -- purple
    { r=0.90, g=0.20, b=0.20 }, -- red
    { r=0.10, g=0.80, b=0.80 }, -- cyan
}

local function GetPlayerColor(index)
    -- Try class color first
    local classFile = select(2, UnitClass("player"))  -- fallback
    -- Cycle through palette for multi-player support
    local c = PLAYER_COLORS[((index - 1) % #PLAYER_COLORS) + 1]
    return c.r, c.g, c.b
end

-- ============================================================
-- Helper: create a styled backdrop container
-- ============================================================

local function ApplyBackdrop(frame, r, g, b, a, er, eg, eb, ea)
    frame:SetBackdrop({
        bgFile   = SOLID,
        edgeFile = SOLID,
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(r or 0, g or 0, b or 0, a or 0.85)
    frame:SetBackdropBorderColor(er or 1, eg or 1, eb or 1, ea or 1)
end

-- ============================================================
-- Row builder — multi-layer gradient bar
-- ============================================================

local function BuildRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - 2, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -(HEADER_H + (index - 1) * ROW_H))

    -- Dark bar background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(SOLID)
    bg:SetVertexColor(0.08, 0.08, 0.10, 1)
    row.bg = bg

    -- Bar fill (left-anchored, width set dynamically)
    local fill = row:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", row, "LEFT", 0, 0)
    fill:SetHeight(ROW_H)
    fill:SetWidth(1)
    fill:SetTexture(SOLID)
    row.fill = fill

    -- Bright edge highlight on bar top (shimmer stripe)
    local shine = row:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    shine:SetHeight(math.floor(ROW_H * 0.35))
    shine:SetWidth(1)
    shine:SetTexture(SOLID)
    shine:SetVertexColor(1, 1, 1, 0.12)
    row.shine = shine

    -- Separator line at bottom
    local sep = row:CreateTexture(nil, "OVERLAY")
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetTexture(SOLID)
    sep:SetVertexColor(0, 0, 0, 0.6)

    -- Rank number
    local rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("LEFT", row, "LEFT", 4, 0)
    rank:SetWidth(14)
    rank:SetJustifyH("LEFT")
    rank:SetShadowOffset(1, -1)
    rank:SetShadowColor(0, 0, 0, 1)
    row.rank = rank

    -- Player name
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetWidth(WIN_W - 100)
    name:SetJustifyH("LEFT")
    name:SetShadowOffset(1, -1)
    name:SetShadowColor(0, 0, 0, 1)
    row.nameLabel = name

    -- DPS value (right-aligned)
    local dps = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dps:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    dps:SetWidth(80)
    dps:SetJustifyH("RIGHT")
    dps:SetShadowOffset(1, -1)
    dps:SetShadowColor(0, 0, 0, 1)
    row.dpsLabel = dps

    row:Hide()
    return row
end

-- ============================================================
-- Main frame construction
-- ============================================================

local function CreateMeterFrame()
    local f = CreateFrame("Frame", "MWoW_DamageMeter", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("MEDIUM")

    -- Outer glow shadow (2px larger, dark)
    local shadow = CreateFrame("Frame", nil, f)
    shadow:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    ApplyBackdrop(shadow, 0, 0, 0, 0.5, 0, 0, 0, 0)
    shadow:SetFrameLevel(f:GetFrameLevel() - 1)

    -- Main body background
    local body = f:CreateTexture(nil, "BACKGROUND")
    body:SetAllPoints()
    body:SetTexture(SOLID)
    body:SetVertexColor(0.04, 0.04, 0.07, 0.93)

    -- Thin colored outer border
    ApplyBackdrop(f, 0.04, 0.04, 0.07, 0.93, 0.25, 0.45, 0.85, 1)

    -- ── Header ──────────────────────────────────────────────
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetSize(WIN_W - 2, HEADER_H)

    local hbg = header:CreateTexture(nil, "ARTWORK")
    hbg:SetAllPoints()
    hbg:SetTexture(SOLID)
    hbg:SetGradientAlpha("VERTICAL",
        0.12, 0.22, 0.55, 1,   -- top: medium blue
        0.06, 0.10, 0.28, 1)   -- bottom: dark blue

    -- Header glow line at top
    local hline = header:CreateTexture(nil, "OVERLAY")
    hline:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    hline:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    hline:SetHeight(1)
    hline:SetTexture(SOLID)
    hline:SetVertexColor(0.40, 0.65, 1.0, 0.9)

    -- Title text
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText("|cffAADDFF⚔|r |cffFFFFFFDamage Meter|r")
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)

    -- Mode toggle (Dmg / Heal)
    local modeBtn = CreateFrame("Button", nil, header)
    modeBtn:SetSize(40, 16)
    modeBtn:SetPoint("RIGHT", header, "RIGHT", -28, 0)
    local modeTex = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeTex:SetText("|cff88FF88Heal|r")
    modeTex:SetAllPoints()
    modeBtn:SetScript("OnClick", function()
        if DM.mode == "damage" then
            DM.mode = "healing"
            modeTex:SetText("|cffFF8888Dmg|r")
        else
            DM.mode = "damage"
            modeTex:SetText("|cff88FF88Heal|r")
        end
        DM:Refresh()
    end)

    -- Reset / close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, -1)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTex:SetText("|cffDD4444✕|r")
    closeTex:SetAllPoints()
    closeBtn:SetScript("OnClick", function()
        DM:Reset()
    end)
    closeBtn:SetScript("OnEnter", function() closeTex:SetText("|cffFF6666✕|r") end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetText("|cffDD4444✕|r") end)

    -- ── Rows ─────────────────────────────────────────────────
    f.rows = {}
    for i = 1, MAX_ROWS do
        f.rows[i] = BuildRow(f, i)
    end

    -- ── Footer ───────────────────────────────────────────────
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    footer:SetSize(WIN_W - 2, FOOTER_H)

    local fbg = footer:CreateTexture(nil, "ARTWORK")
    fbg:SetAllPoints()
    fbg:SetTexture(SOLID)
    fbg:SetGradientAlpha("VERTICAL",
        0.04, 0.06, 0.16, 1,
        0.08, 0.12, 0.26, 1)

    local totalLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("CENTER", footer, "CENTER")
    totalLabel:SetTextColor(0.60, 0.75, 1.00, 1)
    totalLabel:SetShadowOffset(1, -1)
    totalLabel:SetShadowColor(0, 0, 0, 1)
    f.totalLabel = totalLabel

    f:SetHeight(HEADER_H + MAX_ROWS * ROW_H + FOOTER_H + 2)

    return f
end

-- ============================================================
-- Data management
-- ============================================================

function DM:Reset()
    self.tracking   = {}
    self.combatStart = GetTime()
    self:Refresh()
end

function DM:AddDamage(unitName, amount)
    if not self.tracking[unitName] then
        self.tracking[unitName] = { damage = 0, healing = 0 }
    end
    self.tracking[unitName].damage = self.tracking[unitName].damage + amount
end

function DM:AddHealing(unitName, amount)
    if not self.tracking[unitName] then
        self.tracking[unitName] = { damage = 0, healing = 0 }
    end
    self.tracking[unitName].healing = self.tracking[unitName].healing + amount
end

-- ============================================================
-- Refresh / render
-- ============================================================

function DM:Refresh()
    if not self.enabled or not ModernWoW:GetSetting("damageMeter") then
        if self.frame then self.frame:Hide() end
        return
    end
    if not self.frame then
        self.frame = CreateMeterFrame()
    end
    self.frame:Show()

    local sorted = {}
    for name, data in pairs(self.tracking) do
        local val = (self.mode == "damage") and data.damage or data.healing
        sorted[#sorted + 1] = { name = name, value = val }
    end
    table.sort(sorted, function(a, b) return a.value > b.value end)

    local maxVal  = sorted[1] and sorted[1].value or 1
    local elapsed = math.max(1, GetTime() - self.combatStart)
    local totalVal = 0
    for _, d in ipairs(sorted) do totalVal = totalVal + d.value end

    local visibleRows = 0
    for i, row in ipairs(self.frame.rows) do
        local entry = sorted[i]
        if entry and entry.value > 0 then
            local pct = entry.value / maxVal
            local dps = entry.value / elapsed
            local r, g, b = GetPlayerColor(i)

            -- Resize fill bar
            local fillW = math.max(1, math.floor((WIN_W - 2) * pct))
            row.fill:SetWidth(fillW)
            row.fill:SetVertexColor(r * 0.6, g * 0.6, b * 0.6, 0.85)
            row.shine:SetWidth(fillW)

            -- Rank
            row.rank:SetText(string.format("|cff%02x%02x%02x%d|r",
                r * 255, g * 255, b * 255, i))

            -- Name (class colored if possible)
            row.nameLabel:SetText(string.format("|cff%02x%02x%02x%s|r",
                r * 255, g * 255, b * 255, entry.name))

            -- DPS value
            if dps >= 1000 then
                row.dpsLabel:SetText(string.format("|cffFFFFFF%.1fk|r", dps / 1000))
            else
                row.dpsLabel:SetText(string.format("|cffFFFFFF%.0f|r", dps))
            end

            row:Show()
            visibleRows = visibleRows + 1
        else
            row:Hide()
        end
    end

    -- Shrink the frame to fit visible rows
    local newH = HEADER_H + math.max(1, visibleRows) * ROW_H + FOOTER_H + 2
    self.frame:SetHeight(newH)

    -- Footer total
    local totalDPS = totalVal / elapsed
    local timeStr  = string.format("%d:%02d", math.floor(elapsed / 60), elapsed % 60)
    self.frame.totalLabel:SetText(string.format(
        "|cff88AAFFTOTAL|r |cffFFFFFF%.0f|r  |cff88AAFF(%s)|r",
        totalVal, timeStr))
end

function DM:SetEnabled(val)
    self.enabled = val
    self:Refresh()
end

-- Called via addon message from server
function DM:UpdateDPS(data)
    if not data or data == "" then return end
    for entry in data:gmatch("[^,]+") do
        local name, val = strsplit(":", entry)
        if name and val then
            if not self.tracking[name] then
                self.tracking[name] = { damage = 0, healing = 0 }
            end
            self.tracking[name].damage = tonumber(val) or 0
        end
    end
    self:Refresh()
end

-- ============================================================
-- Combat log event registration
-- ============================================================

local dmEvents = CreateFrame("Frame", "MWoW_DamageMeterEvents")
dmEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
dmEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
dmEvents:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

dmEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        DM.inCombat    = true
        DM.combatStart = GetTime()

    elseif event == "PLAYER_REGEN_ENABLED" then
        DM.inCombat = false
        DM:Refresh()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, srcName, srcFlags =
            CombatLogGetCurrentEventInfo()
        if not srcName then return end

        -- Only friendly sources (party / raid / player)
        if not bit.band(srcFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) then
            return
        end

        if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE"
           or subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE" then
            -- Amount is field 15 in 3.3.5 CombatLog
            local args = { CombatLogGetCurrentEventInfo() }
            local dmg  = tonumber(args[15]) or 0
            if dmg > 0 then
                DM:AddDamage(srcName, dmg)
                if DM.inCombat then DM:Refresh() end
            end

        elseif subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" then
            local args = { CombatLogGetCurrentEventInfo() }
            local heal = tonumber(args[13]) or 0
            if heal > 0 then DM:AddHealing(srcName, heal) end
        end
    end
end)

ModernWoW:Debug("DamageMeter module loaded (v2).")
