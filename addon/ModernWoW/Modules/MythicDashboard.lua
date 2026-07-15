-- ModernWoW Addon — Mythic Plus Dashboard / Great Vault UI
-- Compatible with WoW 3.3.5a
-- Displays a premium UI containing weekly best runs, active affixes, and Great Vault reward claiming.

ModernWoW.MythicDashboard = {}
local Dashboard = ModernWoW.MythicDashboard

local bestLevel = 0
local claimed = false
local vaultWeek = 0
local vaultYear = 0
local currentWeek = 0
local currentYear = 0
local weeklyAffixes = "None"

local function CreateDashboardFrame()
    if Dashboard.frame then return end

    local f = CreateFrame("Frame", "ModernWoW_MythicDashboardFrame", UIParent)
    f:SetSize(340, 260)
    
    -- Load saved position or default to center
    local pos = ModernWoWDB.mythicDashboardPos
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        ModernWoWDB.mythicDashboardPos = {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs
        }
    end)

    -- Sleek Premium Backdrop (Glassmorphism style)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.90)
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

    -- Header / Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Great Vault & Mythic Plus")
    f.title = title

    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Weekly Affixes Section
    local affixesHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    affixesHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -45)
    affixesHeader:SetText("Active Weekly Affixes:")
    
    local affixesText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    affixesText:SetPoint("TOPLEFT", affixesHeader, "BOTTOMLEFT", 0, -4)
    affixesText:SetWidth(300)
    affixesText:SetJustifyH("LEFT")
    affixesText:SetText("Loading...")
    f.affixesText = affixesText

    -- Divider
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetSize(300, 1)
    divider:SetPoint("TOPLEFT", affixesText, "BOTTOMLEFT", 0, -12)
    divider:SetTexture(0.3, 0.3, 0.3, 0.5)

    -- Great Vault Section
    local vaultHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vaultHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
    vaultHeader:SetText("Great Vault (Weekly Chest):")

    -- Best Run Text
    local bestRunText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    bestRunText:SetPoint("TOPLEFT", vaultHeader, "BOTTOMLEFT", 0, -8)
    bestRunText:SetText("Weekly Best: None")
    f.bestRunText = bestRunText

    -- Rewards/Description Text
    local descText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descText:SetPoint("TOPLEFT", bestRunText, "BOTTOMLEFT", 0, -6)
    descText:SetWidth(300)
    descText:SetJustifyH("LEFT")
    descText:SetText("Unlock weekly chest rewards by finishing Mythic Plus dungeons.")
    f.descText = descText

    -- Claim Reward Button (Sleek Golden Button)
    local claimBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    claimBtn:SetSize(140, 24)
    claimBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    claimBtn:SetText("Claim Reward")
    claimBtn:SetScript("OnClick", function()
        claimBtn:Disable()
        ModernWoW:SendMessage("M+:CLAIM_VAULT")
    end)
    claimBtn:Hide()
    f.claimBtn = claimBtn

    f:Hide()
    Dashboard.frame = f
end

local function UpdateUI()
    local f = Dashboard.frame
    if not f or not f:IsShown() then return end

    -- Active affixes
    f.affixesText:SetText(weeklyAffixes)

    -- Verify if we have unclaimed past rewards
    local isPastWeek = false
    if vaultYear < currentYear then
        isPastWeek = true
    elseif vaultYear == currentYear and vaultWeek < currentWeek then
        isPastWeek = true
    end

    f.claimBtn:Hide()

    if bestLevel == 0 then
        f.bestRunText:SetText("Weekly Best: |cffff0000None|r")
        f.descText:SetText("Complete at least one Mythic Plus dungeon to earn Great Vault rewards next week!")
    else
        if not isPastWeek then
            -- Current week progress
            f.bestRunText:SetText("Weekly Best: |cff00ff00Level " .. bestLevel .. "|r")
            local badges = bestLevel * 2
            f.descText:SetText("Current reward next week: |cffFFD700" .. badges .. "x Badge of Justice|r.\nCompleted in Week " .. vaultWeek .. ".")
        else
            -- Past week pending claim
            f.bestRunText:SetText("Weekly Best (Week " .. vaultWeek .. "): |cff00ff00Level " .. bestLevel .. "|r")
            if claimed then
                f.descText:SetText("Status: |cff888888Already Claimed.|r")
            else
                local badges = bestLevel * 2
                f.descText:SetText("Status: |cff00ff00REWARD READY!|r\nContents: |cffFFD700" .. badges .. "x Badge of Justice|r.")
                f.claimBtn:Enable()
                f.claimBtn:Show()
            end
        end
    end
end

function Dashboard:Toggle()
    CreateDashboardFrame()
    local f = Dashboard.frame
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        -- Query vault info from server
        ModernWoW:SendMessage("M+:REQ_VAULT")
    end
end

-- Server Event Callbacks
ModernWoW:RegisterCallback("M+", function(data)
    local sub, args = strsplit(":", data, 2)

    if sub == "VAULT_INFO" then
        CreateDashboardFrame()
        -- VAULT_INFO:bestLevel:claimed:vaultWeek:vaultYear:currentWeek:currentYear:weeklyAffixesString
        local lvl, clm, vW, vY, cW, cY, aff = strsplit(":", args, 7)
        
        bestLevel = tonumber(lvl) or 0
        claimed = (tonumber(clm) or 0) == 1
        vaultWeek = tonumber(vW) or 0
        vaultYear = tonumber(vY) or 0
        currentWeek = tonumber(cW) or 0
        currentYear = tonumber(cY) or 0
        weeklyAffixes = aff or "None"

        if weeklyAffixes == "" then weeklyAffixes = "None" end

        UpdateUI()

    elseif sub == "CLAIM_OK" then
        CreateDashboardFrame()
        claimed = true
        UpdateUI()

    elseif sub == "CLAIM_FAIL" then
        CreateDashboardFrame()
        local f = Dashboard.frame
        if f then f.claimBtn:Enable() end
    end
end)
