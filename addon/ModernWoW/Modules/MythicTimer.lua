-- ModernWoW Addon — Mythic Plus Timer Module
-- Compatible with WoW 3.3.5a
-- Displays a sleek, modern UI for Mythic Plus timer and objective tracking.

ModernWoW.MythicTimer = {}
local MythicTimer = ModernWoW.MythicTimer

local dungeonBosses = {
    [576] = { "Prince Keleseth", "Skarvald & Dalronn", "Ingvar the Plunderer" }, -- Utgarde Keep
    [578] = { "Svalara Sorrowgrave", "Gortok Palehoof", "Skadi the Ruthless", "King Ymiron" }, -- Utgarde Pinnacle
    [520] = { "Grand Magus Telestra", "Anomalus", "Ormorok the Tree-Shaper", "Keristrasza" }, -- The Nexus
    [518] = { "Drakos the Defiler", "Varos Cloudstrider", "Mage-Lord Urom", "Ley-Guardian Eregos" }, -- The Oculus
    [601] = { "Krik'thir the Gatewatcher", "Hadronox", "Anub'arak" }, -- Azjol-Nerub
    [619] = { "Elder Nadox", "Prince Taldaram", "Jedoga Shadowseeker", "Herald Volazj" }, -- Ahn'kahet: The Old Kingdom
    [600] = { "Trollgore", "Novos the Summoner", "King Dred", "Prophet Tharon'ja" }, -- Drak'Tharon Keep
    [604] = { "Slad'ran", "Moorabi", "Drakkari Colossus", "Gal'darah" }, -- Gundrak
    [599] = { "Krystallus", "Maiden of Grief", "Tribunal of Ages", "Sjonnir the Ironshaper" }, -- Halls of Stone
    [602] = { "Bjarngrim", "Volkhan", "Ionar", "Loken" }, -- Halls of Lightning
    [632] = { "Bronjahm", "Devourer of Souls" }, -- The Forge of Souls
    [658] = { "Forgemaster Garfrost", "Krick and Ick", "Scourgelord Tyrannus" }, -- Pit of Saron
    [668] = { "Falric", "Marwyn", "Lich King Escape" }, -- Halls of Reflection
    [650] = { "Grand Champions", "Eadric the Pure / Confessor Paletress", "The Black Knight" }, -- Trial of the Champion
}

local activeDungeon = nil
local timeLimit = 0
local elapsed = 0
local deaths = 0
local penalty = 15
local isDone = false
local mapId = 0
local mythicLevel = 0
local killedBosses = {}

-- Create the UI Frame
local function CreateTimerFrame()
    if MythicTimer.frame then return end

    local f = CreateFrame("Frame", "ModernWoW_MythicTimerFrame", UIParent)
    f:SetSize(220, 180)
    
    -- Load saved position or default to right center
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
        ModernWoWDB.mythicTimerPos = {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs
        }
    end)

    -- Sleek Premium Backdrop (Glassmorphism-like)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

    -- Header / Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    title:SetJustifyH("CENTER")
    title:SetText("Mythic Plus")
    f.title = title

    -- Time Remaining Text
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    timeText:SetPoint("TOP", title, "BOTTOM", 0, -8)
    timeText:SetText("00:00")
    f.timeText = timeText

    -- Progress Bar Frame
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(200, 12)
    bar:SetPoint("TOP", timeText, "BOTTOM", 0, -6)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9)
    
    local barBG = bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints(true)
    barBG:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBG:SetStatusBarColor(0.1, 0.1, 0.1, 0.5)
    
    f.bar = bar

    -- Deaths & Penalty Text
    local deathsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathsText:SetPoint("TOP", bar, "BOTTOM", 0, -6)
    deathsText:SetTextColor(1, 0.2, 0.2)
    deathsText:SetText("Deaths: 0")
    f.deathsText = deathsText

    -- Bosses Container
    local bossContainer = CreateFrame("Frame", nil, f)
    bossContainer:SetSize(200, 80)
    bossContainer:SetPoint("TOPLEFT", deathsText, "BOTTOMLEFT", 0, -6)
    f.bossContainer = bossContainer
    f.bossLines = {}

    f:Hide()
    MythicTimer.frame = f
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function UpdateUI()
    local f = MythicTimer.frame
    if not f or not f:IsShown() then return end

    -- Timer update logic
    local totalElapsed = elapsed + (deaths * penalty)
    local remaining = timeLimit - totalElapsed

    if remaining < 0 then
        remaining = 0
    end

    f.timeText:SetText(FormatTime(remaining) .. " / " .. FormatTime(timeLimit))
    f.bar:SetMinMaxValues(0, timeLimit)
    f.bar:SetValue(timeLimit - totalElapsed)

    -- Status bar colors based on remaining percentage
    local pct = remaining / timeLimit
    if pct > 0.4 then
        f.bar:SetStatusBarColor(0.1, 0.8, 0.1, 0.9) -- Green
    elseif pct > 0.15 then
        f.bar:SetStatusBarColor(0.9, 0.7, 0.1, 0.9) -- Yellow
    else
        f.bar:SetStatusBarColor(0.9, 0.1, 0.1, 0.9) -- Red
    end

    -- Deaths count
    if deaths > 0 then
        f.deathsText:SetText("Deaths: " .. deaths .. " (+" .. FormatTime(deaths * penalty) .. ")")
    else
        f.deathsText:SetText("No deaths")
    end

    -- Update boss objectives list
    local bosses = dungeonBosses[mapId]
    for i, line in ipairs(f.bossLines) do
        line:Hide()
    end

    if bosses then
        for i, bossName in ipairs(bosses) do
            local line = f.bossLines[i]
            if not line then
                line = f.bossContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                line:SetPoint("TOPLEFT", f.bossContainer, "TOPLEFT", 10, -(i - 1) * 14)
                line:SetPoint("TOPRIGHT", f.bossContainer, "TOPRIGHT", -10, -(i - 1) * 14)
                line:SetJustifyH("LEFT")
                f.bossLines[i] = line
            end

            local isKilled = killedBosses[bossName] or killedBosses[i]
            if isKilled then
                line:SetText("|cff00ff00[X] " .. bossName .. "|r")
            else
                line:SetText("|cffaaaaaa[  ] " .. bossName .. "|r")
            end
            line:Show()
        end
    else
        -- Fallback: list dynamic boss kills
        local count = 0
        for name, _ in pairs(killedBosses) do
            count = count + 1
        end
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

-- Ticker script to increment elapsed time
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
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Server Event Callbacks
ModernWoW:RegisterCallback("M+", function(data)
    CreateTimerFrame()
    local f = MythicTimer.frame

    -- Message subcommands
    local sub, args = strsplit(":", data, 2)

    if sub == "START" then
        -- START:mapId:timeLimit:mythicLevel:deaths:penaltyOnDeath
        local map, limit, lvl, dths, pen = strsplit(":", args)
        mapId = tonumber(map) or 0
        timeLimit = tonumber(limit) or 0
        mythicLevel = tonumber(lvl) or 0
        deaths = tonumber(dths) or 0
        penalty = tonumber(pen) or 15
        elapsed = 0
        isDone = false
        killedBosses = {}

        local mapName = GetRealZoneText() or "Dungeon"
        f.title:SetText(mapName .. " +" .. mythicLevel)
        f:Show()
        StartTicker()
        UpdateUI()

    elseif sub == "TIME" then
        -- TIME:elapsedSeconds:deaths
        local el, dths = strsplit(":", args)
        elapsed = tonumber(el) or elapsed
        deaths = tonumber(dths) or deaths
        UpdateUI()

    elseif sub == "BOSS" then
        -- BOSS:bossIndexOrName
        local bossName = args
        killedBosses[bossName] = true
        
        -- Check if it matches index (e.g. boss index from 1)
        local idx = tonumber(bossName)
        if idx then
            killedBosses[idx] = true
            local bosses = dungeonBosses[mapId]
            if bosses and bosses[idx] then
                killedBosses[bosses[idx]] = true
            end
        end
        UpdateUI()

    elseif sub == "END" then
        -- END:totalTime:beaten
        local total, beaten = strsplit(":", args)
        elapsed = tonumber(total) or elapsed
        isDone = true
        StopTicker()
        
        local beatenVal = tonumber(beaten) or 0
        if beatenVal == 1 then
            f.timeText:SetText("|cff00ff00Beat the Timer!|r")
        else
            f.timeText:SetText("|cffff0000Timer Expired|r")
        end

    elseif sub == "RESET" then
        f:Hide()
        StopTicker()
    end
end)

-- Auto-hide frame when leaving instances or loading new zones
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
        end
    end
end)

