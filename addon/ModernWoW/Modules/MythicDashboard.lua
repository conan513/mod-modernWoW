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
local activeKeystoneName = "None"   -- e.g. "Utgarde Keep +4"

local function CreateDashboardFrame()
    if Dashboard.frame then return end

    local f = CreateFrame("Frame", "ModernWoW_MythicDashboardFrame", UIParent)
    f:SetSize(340, 290)

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
        ModernWoWDB.mythicDashboardPos = { point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
    end)

    -- Backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.90)
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Great Vault & Mythic Plus")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- ── Active Keystone row ──────────────────────────────────────────────
    local ksHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ksHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -42)
    ksHeader:SetText("Your Active Keystone:")

    local ksText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ksText:SetPoint("TOPLEFT", ksHeader, "BOTTOMLEFT", 0, -3)
    ksText:SetWidth(300)
    ksText:SetJustifyH("LEFT")
    ksText:SetText("|cffFFD700None|r")
    f.ksText = ksText

    -- Divider
    local div1 = f:CreateTexture(nil, "ARTWORK")
    div1:SetSize(300, 1)
    div1:SetPoint("TOPLEFT", ksText, "BOTTOMLEFT", 0, -8)
    div1:SetTexture(0.3, 0.3, 0.3, 0.5)

    -- Weekly Affixes
    local affixesHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    affixesHeader:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -8)
    affixesHeader:SetText("Active Weekly Affixes:")

    local affixesText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    affixesText:SetPoint("TOPLEFT", affixesHeader, "BOTTOMLEFT", 0, -4)
    affixesText:SetWidth(300)
    affixesText:SetJustifyH("LEFT")
    affixesText:SetText("Loading...")
    f.affixesText = affixesText

    -- Divider
    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetSize(300, 1)
    div2:SetPoint("TOPLEFT", affixesText, "BOTTOMLEFT", 0, -8)
    div2:SetTexture(0.3, 0.3, 0.3, 0.5)

    -- Great Vault section
    local vaultHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vaultHeader:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -8)
    vaultHeader:SetText("Great Vault (Weekly Chest):")

    local bestRunText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    bestRunText:SetPoint("TOPLEFT", vaultHeader, "BOTTOMLEFT", 0, -6)
    bestRunText:SetText("Weekly Best: None")
    f.bestRunText = bestRunText

    local descText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descText:SetPoint("TOPLEFT", bestRunText, "BOTTOMLEFT", 0, -5)
    descText:SetWidth(300)
    descText:SetJustifyH("LEFT")
    descText:SetText("Unlock weekly chest rewards by finishing Mythic Plus dungeons.")
    f.descText = descText

    local claimBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    claimBtn:SetSize(140, 24)
    claimBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
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

    -- Active keystone
    if f.ksText then
        if activeKeystoneName and activeKeystoneName ~= "None" and activeKeystoneName ~= "" then
            f.ksText:SetText("|cffFFD700" .. activeKeystoneName .. "|r")
        else
            f.ksText:SetText("|cffaaaaaa(no keystone)|r")
        end
    end

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
            f.bestRunText:SetText("Weekly Best: |cff00ff00Level " .. bestLevel .. "|r")
            local badges = bestLevel * 2
            f.descText:SetText("Reward next week: |cffFFD700" .. badges .. "x Badge of Justice|r (Week " .. vaultWeek .. ").")
        else
            f.bestRunText:SetText("Best (Week " .. vaultWeek .. "): |cff00ff00Level " .. bestLevel .. "|r")
            if claimed then
                f.descText:SetText("Status: |cff888888Already Claimed.|r")
            else
                local badges = bestLevel * 2
                f.descText:SetText("Status: |cff00ff00REWARD READY!|r  |cffFFD700" .. badges .. "x Badge of Justice|r")
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
        -- Query vault info and keystone status from server
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

        bestLevel   = tonumber(lvl) or 0
        claimed     = (tonumber(clm) or 0) == 1
        vaultWeek   = tonumber(vW)  or 0
        vaultYear   = tonumber(vY)  or 0
        currentWeek = tonumber(cW)  or 0
        currentYear = tonumber(cY)  or 0
        weeklyAffixes = (aff and aff ~= "") and aff or "None"

        UpdateUI()

    elseif sub == "KEYSTONE" then
        -- KEYSTONE:mapId:level:mapName  (sent on login, dungeon start, and upgrade)
        CreateDashboardFrame()
        local kMapId, kLevel, kName = strsplit(":", args, 3)
        if kName and kLevel then
            activeKeystoneName = kName .. " +" .. kLevel
        end
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
