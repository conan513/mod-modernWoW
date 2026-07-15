-- ModernWoW Addon — Mythic Plus Timer Module
-- Compatible with WoW 3.3.5a
-- Displays a sleek, modern UI for Mythic Plus timer, trash objective, and boss tracking.

ModernWoW.MythicTimer = {}
local MythicTimer = ModernWoW.MythicTimer

local dungeonBosses = {
    [576] = { "Prince Keleseth", "Skarvald & Dalronn", "Ingvar the Plunderer" },       -- Utgarde Keep
    [578] = { "Svalara Sorrowgrave", "Gortok Palehoof", "Skadi the Ruthless", "King Ymiron" }, -- Utgarde Pinnacle
    [520] = { "Grand Magus Telestra", "Anomalus", "Ormorok the Tree-Shaper", "Keristrasza" }, -- The Nexus
    [518] = { "Drakos the Defiler", "Varos Cloudstrider", "Mage-Lord Urom", "Ley-Guardian Eregos" }, -- The Oculus
    [601] = { "Krik'thir the Gatewatcher", "Hadronox", "Anub'arak" },                  -- Azjol-Nerub
    [619] = { "Elder Nadox", "Prince Taldaram", "Jedoga Shadowseeker", "Herald Volazj" }, -- Ahn'kahet
    [600] = { "Trollgore", "Novos the Summoner", "King Dred", "Prophet Tharon'ja" },   -- Drak'Tharon Keep
    [604] = { "Slad'ran", "Moorabi", "Drakkari Colossus", "Gal'darah" },               -- Gundrak
    [599] = { "Krystallus", "Maiden of Grief", "Tribunal of Ages", "Sjonnir the Ironshaper" }, -- Halls of Stone
    [602] = { "Bjarngrim", "Volkhan", "Ionar", "Loken" },                              -- Halls of Lightning
    [632] = { "Bronjahm", "Devourer of Souls" },                                        -- The Forge of Souls
    [658] = { "Forgemaster Garfrost", "Krick and Ick", "Scourgelord Tyrannus" },       -- Pit of Saron
    [668] = { "Falric", "Marwyn", "Lich King Escape" },                                 -- Halls of Reflection
    [650] = { "Grand Champions", "Eadric / Paletress", "The Black Knight" },            -- Trial of the Champion
}

local activeDungeon = nil
local timeLimit     = 0
local elapsed       = 0
local deaths        = 0
local penalty       = 15
local isDone        = false
local mapId         = 0
local mythicLevel   = 0
local killedBosses  = {}
local trashPct      = 0     -- 0..100
local keystoneName  = ""    -- e.g. "Utgarde Keep +4"

-- ─── Frame Creation ───────────────────────────────────────────────────────────

local function CreateTimerFrame()
    if MythicTimer.frame then return end

    local f = CreateFrame("Frame", "ModernWoW_MythicTimerFrame", UIParent)
    f:SetSize(224, 220)

    local pos = ModernWoWDB.mythicTimerPos
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -100, 100)
    end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        ModernWoWDB.mythicTimerPos = { point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
    end)

    -- Backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.80)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

    -- Title (dungeon name + M+ level)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT",  f, "TOPLEFT",  10, -10)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    title:SetJustifyH("CENTER")
    title:SetText("Mythic Plus")
    f.title = title

    -- Timer text (large)
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    timeText:SetPoint("TOP", title, "BOTTOM", 0, -6)
    timeText:SetText("00:00")
    f.timeText = timeText

    -- ── Timer progress bar ────────────────────────────────────────────────
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(200, 12)
    bar:SetPoint("TOP", timeText, "BOTTOM", 0, -5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9)
    local barBG = bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints(true)
    barBG:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBG:SetVertexColor(0.1, 0.1, 0.1, 0.5)
    f.bar = bar

    -- Deaths text
    local deathsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathsText:SetPoint("TOP", bar, "BOTTOM", 0, -5)
    deathsText:SetTextColor(1, 0.3, 0.3)
    deathsText:SetText("No deaths")
    f.deathsText = deathsText

    -- ── Divider ───────────────────────────────────────────────────────────
    local div1 = f:CreateTexture(nil, "ARTWORK")
    div1:SetSize(200, 1)
    div1:SetPoint("TOP", deathsText, "BOTTOM", 0, -5)
    div1:SetTexture(0.3, 0.3, 0.3, 0.5)

    -- ── Trash Progress label ──────────────────────────────────────────────
    local trashLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trashLabel:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -5)
    trashLabel:SetText("Enemies Defeated:")
    f.trashLabel = trashLabel

    local trashPctText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trashPctText:SetPoint("TOPRIGHT", div1, "BOTTOMRIGHT", 0, -5)
    trashPctText:SetText("0%")
    f.trashPctText = trashPctText

    -- ── Trash progress bar ────────────────────────────────────────────────
    local trashBar = CreateFrame("StatusBar", nil, f)
    trashBar:SetSize(200, 9)
    trashBar:SetPoint("TOP", trashLabel, "BOTTOM", 0, -3)
    trashBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    trashBar:SetStatusBarColor(0.4, 0.7, 1.0, 0.9)
    trashBar:SetMinMaxValues(0, 100)
    trashBar:SetValue(0)
    local trashBarBG = trashBar:CreateTexture(nil, "BACKGROUND")
    trashBarBG:SetAllPoints(true)
    trashBarBG:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    trashBarBG:SetVertexColor(0.1, 0.1, 0.1, 0.5)
    f.trashBar = trashBar

    -- ── Divider ───────────────────────────────────────────────────────────
    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetSize(200, 1)
    div2:SetPoint("TOP", trashBar, "BOTTOM", 0, -5)
    div2:SetTexture(0.3, 0.3, 0.3, 0.5)

    -- Boss list container
    local bossContainer = CreateFrame("Frame", nil, f)
    bossContainer:SetSize(200, 80)
    bossContainer:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -4)
    f.bossContainer = bossContainer
    f.bossLines = {}

    f:Hide()
    MythicTimer.frame = f
end

-- ─── Helper Functions ─────────────────────────────────────────────────────────

local function FormatTime(seconds)
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function UpdateUI()
    local f = MythicTimer.frame
    if not f or not f:IsShown() then return end

    -- Timer
    local totalElapsed = elapsed + (deaths * penalty)
    local remaining    = timeLimit - totalElapsed
    if remaining < 0 then remaining = 0 end

    f.timeText:SetText(FormatTime(remaining) .. " / " .. FormatTime(timeLimit))
    f.bar:SetMinMaxValues(0, timeLimit)
    f.bar:SetValue(math.max(0, timeLimit - totalElapsed))

    -- Timer bar color: green > yellow > red
    local pct = (timeLimit > 0) and (remaining / timeLimit) or 0
    if pct > 0.40 then
        f.bar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9)
    elseif pct > 0.15 then
        f.bar:SetStatusBarColor(0.9, 0.7, 0.1, 0.9)
    else
        f.bar:SetStatusBarColor(0.9, 0.1, 0.1, 0.9)
    end

    -- Deaths
    if deaths > 0 then
        f.deathsText:SetText("Deaths: " .. deaths .. "  (+" .. FormatTime(deaths * penalty) .. ")")
    else
        f.deathsText:SetText("No deaths")
    end

    -- Trash bar
    f.trashBar:SetValue(trashPct)
    f.trashPctText:SetText(trashPct .. "%")
    if trashPct >= 100 then
        f.trashBar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9)   -- green when done
        f.trashPctText:SetTextColor(0.1, 0.9, 0.1)
    else
        f.trashBar:SetStatusBarColor(0.4, 0.7, 1.0, 0.9)   -- blue while in progress
        f.trashPctText:SetTextColor(1, 1, 1)
    end

    -- Boss list
    for _, line in ipairs(f.bossLines) do line:Hide() end
    local bosses = dungeonBosses[mapId]
    if bosses then
        for i, bossName in ipairs(bosses) do
            local line = f.bossLines[i]
            if not line then
                line = f.bossContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                line:SetPoint("TOPLEFT",  f.bossContainer, "TOPLEFT",  10, -(i - 1) * 14)
                line:SetPoint("TOPRIGHT", f.bossContainer, "TOPRIGHT", -10, -(i - 1) * 14)
                line:SetJustifyH("LEFT")
                f.bossLines[i] = line
            end
            if killedBosses[bossName] or killedBosses[i] then
                line:SetText("|cff00ff00[X] " .. bossName .. "|r")
            else
                line:SetText("|cffaaaaaa[  ] " .. bossName .. "|r")
            end
            line:Show()
        end
    else
        local count = 0
        for _ in pairs(killedBosses) do count = count + 1 end
        local line = f.bossLines[1]
        if not line then
            line = f.bossContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            line:SetPoint("TOPLEFT", f.bossContainer, "TOPLEFT", 10, 0)
            f.bossLines[1] = line
        end
        line:SetText("Bosses defeated: " .. count)
        line:Show()
    end
end

-- ─── Ticker ───────────────────────────────────────────────────────────────────

local ticker = nil
local function StartTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(1, function()
        if not isDone then
            elapsed = elapsed + 1
            UpdateUI()
        end
    end)
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

-- ─── Server Event Callbacks ───────────────────────────────────────────────────

ModernWoW:RegisterCallback("M+", function(data)
    CreateTimerFrame()
    local f = MythicTimer.frame

    local sub, args = strsplit(":", data, 2)

    if sub == "START" then
        -- START:mapId:timeLimit:mythicLevel:deaths:penaltyOnDeath
        local map, limit, lvl, dths, pen = strsplit(":", args, 5)
        mapId       = tonumber(map)   or 0
        timeLimit   = tonumber(limit) or 0
        mythicLevel = tonumber(lvl)   or 0
        deaths      = tonumber(dths)  or 0
        penalty     = tonumber(pen)   or 15
        elapsed     = 0
        isDone      = false
        killedBosses = {}
        trashPct    = 0

        local mapName = GetRealZoneText() or "Dungeon"
        f.title:SetText(mapName .. " |cffFFD700+" .. mythicLevel .. "|r")
        f:Show()
        StartTicker()
        UpdateUI()

    elseif sub == "TIME" then
        -- TIME:elapsedSeconds:deaths
        local el, dths = strsplit(":", args, 2)
        elapsed = tonumber(el)   or elapsed
        deaths  = tonumber(dths) or deaths
        UpdateUI()

    elseif sub == "TRASH" then
        -- TRASH:pct (0-100)
        trashPct = tonumber(args) or 0
        UpdateUI()

    elseif sub == "BOSS" then
        -- BOSS:entry  (creature entry)
        local entry = tonumber(args)
        if entry then
            killedBosses[entry] = true
            -- Also try to match by name if we have the boss list
            local bosses = dungeonBosses[mapId]
            if bosses then
                -- Mark sequentially (first unmatched index)
                for i, name in ipairs(bosses) do
                    if not killedBosses[i] then
                        killedBosses[i] = true
                        killedBosses[name] = true
                        break
                    end
                end
            end
        end
        UpdateUI()

    elseif sub == "KEYSTONE" then
        -- KEYSTONE:mapId:level:mapName
        local kMapId, kLevel, kName = strsplit(":", args, 3)
        keystoneName = (kName or "Dungeon") .. " +" .. (kLevel or "?")
        -- Update title if the frame is visible and dungeon matches
        if f:IsShown() then
            local mapName = GetRealZoneText() or "Dungeon"
            f.title:SetText(mapName .. " |cffFFD700+" .. mythicLevel .. "|r")
        end

    elseif sub == "END" then
        -- END:totalTime:beaten
        local total, beaten = strsplit(":", args, 2)
        elapsed = tonumber(total) or elapsed
        isDone  = true
        trashPct = 100
        StopTicker()
        UpdateUI()

        local beatenVal = tonumber(beaten) or 0
        if beatenVal == 1 then
            f.timeText:SetText("|cff00ff00Beat the Timer!|r")
            f.bar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9)
        else
            f.timeText:SetText("|cffff0000Timer Expired|r")
            f.bar:SetStatusBarColor(0.5, 0.5, 0.5, 0.9)
        end

    elseif sub == "RESET" then
        f:Hide()
        StopTicker()
        trashPct = 0
        isDone   = false
    end
end)

-- ─── Auto-Hide on Zone Change ─────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local inInstance, instanceType = IsInInstance()
        if not inInstance or instanceType ~= "party" then
            if MythicTimer.frame then
                MythicTimer.frame:Hide()
                StopTicker()
            end
            trashPct = 0
            isDone   = false
        end
    end
end)
