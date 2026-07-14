-- ModernWoW — Modern Unit Frames Module
-- Reskins the player, target, focus, and party unit frames to look more modern.
-- Uses texture overrides and custom health/power bar styling.
-- Keeps the default Blizzard layout but improves visual presentation.

ModernWoW.ModernUnitFrames = {}
local MUF = ModernWoW.ModernUnitFrames

MUF.enabled = true

-- ============================================================
-- Color Definitions
-- ============================================================

local CLASS_COLORS = RAID_CLASS_COLORS -- WoW built-in

local POWER_COLORS = {
    [0] = { r = 0.00, g = 0.44, b = 0.87 }, -- Mana (blue)
    [1] = { r = 1.00, g = 0.00, b = 0.00 }, -- Rage (red)
    [2] = { r = 1.00, g = 0.65, b = 0.00 }, -- Focus (orange)
    [3] = { r = 1.00, g = 0.82, b = 0.00 }, -- Energy (yellow)
}

local HEALTH_COLOR_LOW  = { r = 0.80, g = 0.10, b = 0.10 } -- < 25%
local HEALTH_COLOR_MED  = { r = 0.95, g = 0.60, b = 0.10 } -- 25–60%
local HEALTH_COLOR_HIGH = { r = 0.10, g = 0.75, b = 0.20 } -- > 60%

local function GetHealthColor(pct)
    if pct < 0.25 then
        return HEALTH_COLOR_LOW.r, HEALTH_COLOR_LOW.g, HEALTH_COLOR_LOW.b
    elseif pct < 0.60 then
        return HEALTH_COLOR_MED.r, HEALTH_COLOR_MED.g, HEALTH_COLOR_MED.b
    else
        return HEALTH_COLOR_HIGH.r, HEALTH_COLOR_HIGH.g, HEALTH_COLOR_HIGH.b
    end
end

-- ============================================================
-- Apply styling to a StatusBar
-- ============================================================

local solidTexture = "Interface\\Buttons\\WHITE8X8"

local function StyleBar(bar, r, g, b)
    if not bar then return end
    bar:SetStatusBarTexture(solidTexture)
    bar:SetStatusBarColor(r, g, b, 1)
    -- Background
    if bar.bg then
        bar.bg:SetTexture(solidTexture)
        bar.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)
    end
end

-- ============================================================
-- Style a unit frame
-- ============================================================

local function StyleUnitFrame(frame, unitId)
    if not frame or not frame.healthbar then return end

    local healthPct = UnitHealth(unitId) / math.max(1, UnitHealthMax(unitId))
    local r, g, b = GetHealthColor(healthPct)

    -- Override health bar texture + color
    StyleBar(frame.healthbar, r, g, b)

    -- Power bar
    if frame.manabar then
        local powerType = UnitPowerType(unitId)
        local pc = POWER_COLORS[powerType] or POWER_COLORS[0]
        StyleBar(frame.manabar, pc.r, pc.g, pc.b)
    end

    -- Name text color by class
    if frame.name then
        local _, classFile = UnitClass(unitId)
        if classFile and CLASS_COLORS[classFile] then
            local cc = CLASS_COLORS[classFile]
            frame.name:SetTextColor(cc.r, cc.g, cc.b, 1)
        end
    end
end

-- ============================================================
-- Event-driven refresh
-- ============================================================

local ufFrame = CreateFrame("Frame", "MWoW_UnitFrameEvents")

local REFRESH_EVENTS = {
    "PLAYER_LOGIN",
    "UNIT_HEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXHEALTH",
    "UNIT_DISPLAYPOWER",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}

for _, ev in ipairs(REFRESH_EVENTS) do
    ufFrame:RegisterEvent(ev)
end

ufFrame:SetScript("OnEvent", function(self, event, unitId)
    if not MUF.enabled or not ModernWoW:GetSetting("modernFrames") then
        return
    end

    -- Refresh relevant frames
    if not unitId or unitId == "player" then
        StyleUnitFrame(PlayerFrame, "player")
    end
    if not unitId or unitId == "target" then
        StyleUnitFrame(TargetFrame, "target")
    end
    if not unitId or unitId == "focus" then
        if FocusFrame and FocusFrame:IsShown() then
            StyleUnitFrame(FocusFrame, "focus")
        end
    end
    -- Party frames
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf and pf:IsShown() then
            StyleUnitFrame(pf, "party" .. i)
        end
    end
end)

-- ============================================================
-- Portrait: add rounded border effect via texture overlay
-- ============================================================

local function AddPortraitRing(portrait)
    if not portrait or portrait._mwowRing then return end
    local ring = portrait:GetParent():CreateTexture(nil, "OVERLAY")
    ring:SetSize(portrait:GetWidth() + 4, portrait:GetHeight() + 4)
    ring:SetPoint("CENTER", portrait, "CENTER")
    ring:SetTexture("Interface\\CharacterFrame\\UI-Portrait-Border")
    ring:SetVertexColor(0.4, 0.6, 1, 0.8)
    portrait._mwowRing = true
end

-- ============================================================
-- Init on login
-- ============================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    if not MUF.enabled or not ModernWoW:GetSetting("modernFrames") then return end

    -- Apply initial styling
    StyleUnitFrame(PlayerFrame, "player")
    StyleUnitFrame(TargetFrame, "target")

    -- Add portrait rings
    if PlayerFrame.portrait then
        AddPortraitRing(PlayerFrame.portrait)
    end
    if TargetFrame.portrait then
        AddPortraitRing(TargetFrame.portrait)
    end

    ModernWoW:Debug("ModernUnitFrames: Applied styling.")
end)

ModernWoW:Debug("ModernUnitFrames module loaded.")
