-- ModernWoW — Collections Module
-- Displays a lightweight Collections Journal window:
-- Mounts, Pets, and a summary panel. Mirrors the modern WoW Collections UI.

ModernWoW.Collections = {}
local COL = ModernWoW.Collections

COL.enabled = true
COL.frame   = nil
COL.tab     = "mounts" -- current tab: "mounts", "pets"

local WIN_W = 500
local WIN_H = 380
local ICON_SIZE = 44
local ICONS_PER_ROW = 9

-- ============================================================
-- Frame creation
-- ============================================================

local function CreateCollectionsFrame()
    local f = CreateFrame("Frame", "MWoW_Collections", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)

    -- Border
    f:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropBorderColor(0.4, 0.6, 1, 0.8)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cffAADDFF📚 Collections|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Tabs
    local tabMounts = CreateFrame("Button", nil, f, "TabButtonTemplate")
    tabMounts:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 4, 0)
    tabMounts:SetText("Mounts")
    tabMounts:SetScript("OnClick", function()
        COL.tab = "mounts"
        COL:Populate()
    end)

    local tabPets = CreateFrame("Button", nil, f, "TabButtonTemplate")
    tabPets:SetPoint("LEFT", tabMounts, "RIGHT", -14, 0)
    tabPets:SetText("Companions")
    tabPets:SetScript("OnClick", function()
        COL.tab = "pets"
        COL:Populate()
    end)

    -- Count label
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    countLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    f.countLabel = countLabel

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", "MWoW_CollScroll", f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(WIN_W - 20, 1000)
    scroll:SetScrollChild(child)
    f.iconContainer = child

    f.icons = {}
    return f
end

-- ============================================================
-- Icon builder
-- ============================================================

local function CreateIcon(parent, index)
    local col = (index - 1) % ICONS_PER_ROW
    local row = math.floor((index - 1) / ICONS_PER_ROW)

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT",
        col * (ICON_SIZE + 4) + 4,
        -(row * (ICON_SIZE + 4) + 4))

    -- Icon texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    btn.tex = tex

    -- Border
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    -- Grey overlay for uncollected
    local grey = btn:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.6)
    btn.greyOverlay = grey

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if self.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellId)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

-- ============================================================
-- Populate icon grid
-- ============================================================

function COL:Populate()
    if not self.frame then return end

    local container = self.frame.iconContainer
    -- Hide all existing icons
    for _, icon in ipairs(self.frame.icons) do
        icon:Hide()
    end

    local items = {}
    if self.tab == "mounts" then
        local numMounts = GetNumCompanions("MOUNT")
        for i = 1, numMounts do
            local creatureID, creatureName, creatureSpellID, icon, active =
                GetCompanionInfo("MOUNT", i)
            items[#items + 1] = {
                name    = creatureName,
                icon    = icon,
                spellId = creatureSpellID,
                owned   = true,
            }
        end
        self.frame.countLabel:SetText(string.format("Mounts: %d", #items))

    elseif self.tab == "pets" then
        local numPets = GetNumCompanions("CRITTER")
        for i = 1, numPets do
            local creatureID, creatureName, creatureSpellID, icon, active =
                GetCompanionInfo("CRITTER", i)
            items[#items + 1] = {
                name    = creatureName,
                icon    = icon,
                spellId = creatureSpellID,
                owned   = true,
            }
        end
        self.frame.countLabel:SetText(string.format("Companions: %d", #items))
    end

    -- Render icons
    for i, item in ipairs(items) do
        if not self.frame.icons[i] then
            self.frame.icons[i] = CreateIcon(container, i)
        end
        local icon = self.frame.icons[i]
        icon.tex:SetTexture(item.icon)
        icon.spellId = item.spellId
        icon.greyOverlay:SetShown(not item.owned)
        icon:Show()
    end

    -- Resize container
    local rows = math.ceil(#items / ICONS_PER_ROW)
    container:SetHeight(math.max(1, rows * (ICON_SIZE + 4) + 4))
end

function COL:Toggle()
    if not self.frame then
        self.frame = CreateCollectionsFrame()
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Populate()
        self.frame:Show()
    end
end

-- ============================================================
-- Slash command binding
-- ============================================================

SLASH_MWOWCOL1 = "/mwowcol"
SLASH_MWOWCOL2 = "/collections"
SlashCmdList["MWOWCOL"] = function()
    COL:Toggle()
end

ModernWoW:Debug("Collections module loaded.")
