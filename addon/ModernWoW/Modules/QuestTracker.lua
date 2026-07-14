-- ModernWoW — Quest Tracker Module
-- Modern-style quest tracker that shows active quests, progress bars,
-- and World Quest indicators. Replaces (or supplements) the default WatchFrame.

ModernWoW.QuestTracker = {}
local QT = ModernWoW.QuestTracker

QT.enabled   = true
QT.worldQuests = {} -- list of active WQ quest IDs received from server
QT.frame     = nil

local TRACKER_WIDTH  = 220
local TRACKER_HEIGHT = 400
local ROW_HEIGHT     = 52
local PADDING        = 8
local MAX_QUESTS     = 7

-- ============================================================
-- Frame creation
-- ============================================================

local function CreateTrackerFrame()
    local f = CreateFrame("Frame", "MWoW_QuestTracker", UIParent)
    f:SetSize(TRACKER_WIDTH, TRACKER_HEIGHT)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    -- Header
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -PADDING)
    title:SetText("|cffFFD700Quests|r")

    -- Scroll child for quest rows
    local scroll = CreateFrame("ScrollFrame", "MWoW_QuestScroll", f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(TRACKER_WIDTH, MAX_QUESTS * ROW_HEIGHT)
    scroll:SetScrollChild(child)

    f.questChild = child
    f.questRows  = {}

    return f
end

-- ============================================================
-- Quest row builder
-- ============================================================

local function CreateQuestRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TRACKER_WIDTH - PADDING * 2, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, -(index - 1) * ROW_HEIGHT - PADDING)

    -- Background highlight
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    -- Quest name
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    name:SetWidth(TRACKER_WIDTH - PADDING * 3)
    name:SetJustifyH("LEFT")
    row.nameText = name

    -- Progress bar background
    local barBg = row:CreateTexture(nil, "BACKGROUND")
    barBg:SetSize(TRACKER_WIDTH - PADDING * 3, 8)
    barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    barBg:SetColorTexture(0.2, 0.2, 0.2, 1)

    -- Progress bar fill
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetSize(0, 8)
    bar:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
    bar:SetColorTexture(0.2, 0.8, 0.2, 1)
    row.bar    = bar
    row.barBg  = barBg
    row.barMaxWidth = TRACKER_WIDTH - PADDING * 3

    -- WQ indicator
    local wqTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wqTag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    wqTag:SetTextColor(1, 0.84, 0, 1)
    row.wqTag = wqTag

    row:Hide()
    return row
end

-- ============================================================
-- Update tracker display
-- ============================================================

function QT:Update()
    if not self.enabled or not ModernWoW:GetSetting("questTracker") then
        if self.frame then self.frame:Hide() end
        return
    end

    if not self.frame then
        self.frame = CreateTrackerFrame()
    end

    self.frame:Show()

    local child = self.frame.questChild
    local rows  = self.frame.questRows

    -- Ensure enough rows exist
    while #rows < MAX_QUESTS do
        rows[#rows + 1] = CreateQuestRow(child, #rows + 1)
    end

    -- Hide all rows first
    for _, row in ipairs(rows) do
        row:Hide()
    end

    -- Fill with watched quests
    local rowIdx = 0
    local numWatched = GetNumQuestWatches()
    for i = 1, math.min(numWatched, MAX_QUESTS) do
        local questIdx = GetQuestIndexForWatch(i)
        if questIdx then
            local title, level, tag, suggestedGroup, isHeader, isCollapsed,
                  isComplete, frequency, questID = GetQuestLogTitle(questIdx)

            if title and not isHeader then
                rowIdx = rowIdx + 1
                local row = rows[rowIdx]
                row:Show()

                -- Color by completion state
                local color = isComplete and "|cff00FF00" or "|cffFFFFFF"
                row.nameText:SetText(string.format("%s[%d] %s|r", color, level or 0, title))

                -- Progress bar
                local objectives = GetNumQuestLeaderBoards(questIdx)
                local totalPct = 0
                if objectives > 0 then
                    local completedObj = 0
                    for j = 1, objectives do
                        local text, objType, finished = GetQuestLogLeaderBoard(j, questIdx)
                        if finished then completedObj = completedObj + 1 end
                    end
                    totalPct = completedObj / objectives
                end

                local barW = math.max(0, math.min(1, totalPct)) * row.barMaxWidth
                row.bar:SetWidth(barW)

                -- World Quest tag
                local isWQ = false
                for _, wqId in ipairs(self.worldQuests) do
                    if wqId == questID then isWQ = true; break end
                end
                row.wqTag:SetText(isWQ and "★ WQ" or "")
                row.bar:SetColorTexture(isWQ and 1 or 0.2, 0.8, isWQ and 0 or 0.2, 1)
            end
        end
    end
end

function QT:SetEnabled(val)
    self.enabled = val
    self:Update()
end

function QT:UpdateWorldQuests(data)
    -- data = "questId1,questId2,..." from server
    self.worldQuests = {}
    if data and data ~= "" then
        for id in data:gmatch("%d+") do
            self.worldQuests[#self.worldQuests + 1] = tonumber(id)
        end
    end
    self:Update()
end

-- ============================================================
-- Event hooks
-- ============================================================

local qtFrame = CreateFrame("Frame", "MWoW_QuestTrackerEvents")
qtFrame:RegisterEvent("PLAYER_LOGIN")
qtFrame:RegisterEvent("QUEST_WATCH_UPDATE")
qtFrame:RegisterEvent("QUEST_LOG_UPDATE")
qtFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

qtFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() QT:Update() end)
    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" then
        QT:Update()
    end
end)

ModernWoW:Debug("QuestTracker module loaded.")
