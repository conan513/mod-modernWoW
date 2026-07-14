-- ModernWoW — Damage Meter Module
-- Lightweight client-side damage tracker using combat log events.
-- Also receives server-side DPS data via addon messages (if server module is running).

ModernWoW.DamageMeter = {}
local DM = ModernWoW.DamageMeter

DM.enabled  = true
DM.tracking = {}    -- { [unitName] = { damage = 0, healing = 0, name = "" } }
DM.combatStart = 0
DM.inCombat = false
DM.mode = "damage"  -- "damage" or "healing"

local WIN_W = 200
local WIN_H = 250
local ROW_H = 20
local MAX_ROWS = 10

-- ============================================================
-- Frame creation
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

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetSize(WIN_W, 20)
    titleBar:SetPoint("TOP", f, "TOP", 0, 0)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.3, 0.9)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", titleBar, "CENTER")
    title:SetText("|cffAADDFF⚔ Damage Meter|r")
    f.title = title

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, f)
    resetBtn:SetSize(16, 16)
    resetBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    local resetTex = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetTex:SetText("|cffff4444✕|r")
    resetTex:SetAllPoints()
    resetBtn:SetScript("OnClick", function() DM:Reset() end)

    -- Row frames
    f.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(WIN_W, ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * ROW_H - 22)

        -- Bar background
        local barBg = row:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.15, 0.15, 0.15, 1)

        -- Bar fill
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetSize(0, ROW_H)
        bar:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.bar = bar

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetWidth(WIN_W - 8)
        label:SetJustifyH("LEFT")
        row.label = label

        row:Hide()
        f.rows[i] = row
    end

    -- Total DPS label
    local totalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    totalLabel:SetTextColor(0.7, 0.7, 0.7)
    f.totalLabel = totalLabel

    return f
end

-- ============================================================
-- Data functions
-- ============================================================

function DM:Reset()
    self.tracking  = {}
    self.combatStart = GetTime()
    self:Refresh()
end

function DM:AddDamage(unitName, amount)
    if not self.tracking[unitName] then
        self.tracking[unitName] = { damage = 0, healing = 0, name = unitName }
    end
    self.tracking[unitName].damage = self.tracking[unitName].damage + amount
end

function DM:AddHealing(unitName, amount)
    if not self.tracking[unitName] then
        self.tracking[unitName] = { damage = 0, healing = 0, name = unitName }
    end
    self.tracking[unitName].healing = self.tracking[unitName].healing + amount
end

function DM:Refresh()
    if not self.enabled or not ModernWoW:GetSetting("damageMeter") then
        if self.frame then self.frame:Hide() end
        return
    end

    if not self.frame then
        self.frame = CreateMeterFrame()
    end
    self.frame:Show()

    -- Sort players by damage/healing
    local sorted = {}
    for name, data in pairs(self.tracking) do
        local val = (self.mode == "damage") and data.damage or data.healing
        sorted[#sorted + 1] = { name = name, value = val }
    end
    table.sort(sorted, function(a, b) return a.value > b.value end)

    local maxVal = sorted[1] and sorted[1].value or 1
    local elapsed = math.max(1, GetTime() - self.combatStart)
    local totalVal = 0
    for _, d in ipairs(sorted) do totalVal = totalVal + d.value end

    -- Colors for different players (cycle through)
    local colors = {
        {0.2, 0.6, 1},   -- blue
        {0.2, 1, 0.4},   -- green
        {1, 0.5, 0.1},   -- orange
        {1, 0.2, 0.2},   -- red
        {0.8, 0.2, 1},   -- purple
    }

    for i, row in ipairs(self.frame.rows) do
        local entry = sorted[i]
        if entry and entry.value > 0 then
            local pct  = entry.value / maxVal
            local dps  = entry.value / elapsed
            local col  = colors[((i - 1) % #colors) + 1]

            row.bar:SetWidth(WIN_W * pct)
            row.bar:SetColorTexture(col[1], col[2], col[3], 0.7)
            row.label:SetText(string.format("|cffFFFFFF%s|r  %.0f (%.0f/s)", entry.name, entry.value, dps))
            row:Show()
        else
            row:Hide()
        end
    end

    -- Total label
    local totalDPS = totalVal / elapsed
    self.frame.totalLabel:SetText(string.format("Total: %.0f (%.0f/s)", totalVal, totalDPS))
end

function DM:SetEnabled(val)
    self.enabled = val
    self:Refresh()
end

-- Called from server addon message
function DM:UpdateDPS(data)
    -- data = "PlayerName:12345,AnotherPlayer:9876" (cumulative damage)
    if not data or data == "" then return end
    for entry in data:gmatch("[^,]+") do
        local name, val = strsplit(":", entry)
        if name and val then
            if not self.tracking[name] then
                self.tracking[name] = { damage = 0, healing = 0, name = name }
            end
            self.tracking[name].damage = tonumber(val) or 0
        end
    end
    self:Refresh()
end

-- ============================================================
-- Combat Log parsing (client-side fallback)
-- ============================================================

local dmEvents = CreateFrame("Frame", "MWoW_DamageMeterEvents")
dmEvents:RegisterEvent("PLAYER_REGEN_DISABLED")  -- enter combat
dmEvents:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leave combat
dmEvents:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

dmEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        DM.inCombat = true
        DM.combatStart = GetTime()

    elseif event == "PLAYER_REGEN_ENABLED" then
        DM.inCombat = false
        DM:Refresh()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, hideCaster,
              srcGUID, srcName, srcFlags, srcRaidFlags,
              dstGUID, dstName, dstFlags, dstRaidFlags = CombatLogGetCurrentEventInfo()

        if not srcName then return end

        -- Only track friendly units (party/raid members including player)
        if not bit.band(srcFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) then return end

        if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE"
           or subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE" then
            local amount = select(4, CombatLogGetCurrentEventInfo())  -- won't work simply
            -- Use a simpler approach compatible with 3.3.5:
            local _, _, _, _, _, _, _, _, _, _, amount15 = CombatLogGetCurrentEventInfo()
            local dmg = tonumber(amount15) or 0
            if dmg > 0 then
                DM:AddDamage(srcName, dmg)
                if DM.inCombat then DM:Refresh() end
            end

        elseif subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" then
            local _, _, _, _, _, _, _, _, _, heal = CombatLogGetCurrentEventInfo()
            local healAmt = tonumber(heal) or 0
            if healAmt > 0 then
                DM:AddHealing(srcName, healAmt)
            end
        end
    end
end)

ModernWoW:Debug("DamageMeter module loaded.")
