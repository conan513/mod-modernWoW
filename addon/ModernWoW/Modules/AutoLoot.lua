-- ModernWoW — AutoLoot Module
-- Client-side: holds Shift while looting to trigger auto-loot on the WoW 3.3.5 client.
-- Also displays a floating "All looted!" text when done.
--
-- NOTE: The real auto-loot logic runs SERVER-SIDE (mod-modernWoW C++ module).
-- This client module:
--   1. Forces the auto-loot flag on the LOOT frame by simulating a Shift-click
--   2. Shows visual feedback when all loot is collected
--   3. Optionally auto-closes the loot window when empty

ModernWoW.AutoLoot = {}
local AL = ModernWoW.AutoLoot

AL.enabled = true

function AL:SetEnabled(val)
    self.enabled = val
end

-- Hook default LootFrame show to instantly hide if empty (fail-safe)
LootFrame:HookScript("OnShow", function(self)
    if ModernWoW:GetSetting("autoLoot") and AL.enabled then
        if GetNumLootItems() == 0 then
            self:Hide()
            CloseLoot()
        end
    end
end)

-- ============================================================
-- Hook the LootFrame to auto-take all items
-- ============================================================

local function AutoLootAll()
    if not AL.enabled then return end
    if not ModernWoW:GetSetting("autoLoot") then return end

    -- The 3.3.5 client already has auto-loot when Shift is held.
    -- Since the server already auto-loots, the loot window will often be empty.
    -- We still hook here to handle edge cases (quest items, rolls).

    local numItems = GetNumLootItems()
    if numItems == 0 then
        -- Server already looted everything — close immediately
        CloseLoot()
        LootFrame:Hide()
        return
    end

    -- Auto-click all available loot slots
    for i = 1, numItems do
        local lootIcon, lootName, lootQuantity, lootRarity, locked = GetLootSlotInfo(i)
        if lootName and not locked then
            LootSlot(i)
        end
    end
end

-- ============================================================
-- Floating text feedback
-- ============================================================

local feedbackFrame = CreateFrame("Frame", "MWoW_LootFeedback", UIParent)
feedbackFrame:SetSize(200, 30)
feedbackFrame:SetPoint("TOP", UIParent, "TOP", 0, -200)
feedbackFrame:Hide()

local feedbackText = feedbackFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
feedbackText:SetAllPoints()
feedbackText:SetTextColor(1, 0.84, 0, 1) -- gold

local feedbackAnim = feedbackFrame:CreateAnimationGroup()
local moveUp = feedbackAnim:CreateAnimation("Translation")
moveUp:SetOffset(0, 40)
moveUp:SetDuration(1.5)

local fadeOut = feedbackAnim:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(1.5)

feedbackAnim:SetScript("OnFinished", function()
    feedbackFrame:Hide()
end)

local function ShowLootFeedback(text)
    feedbackText:SetText(text)
    feedbackFrame:Show()
    feedbackAnim:Play()
end

-- ============================================================
-- Loot event hooks
-- ============================================================

-- Unregister default LootFrame from LOOT_OPENED to prevent it from flashing/opening
LootFrame:UnregisterEvent("LOOT_OPENED")

local lootFrame = CreateFrame("Frame", "MWoW_AutoLootFrame")
lootFrame:RegisterEvent("LOOT_OPENED")
lootFrame:RegisterEvent("LOOT_CLOSED")
lootFrame:RegisterEvent("LOOT_SLOT_CLEARED")

lootFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_OPENED" then
        local args = {...}
        -- If auto-loot is disabled, immediately open default LootFrame
        if not ModernWoW:GetSetting("autoLoot") or not AL.enabled then
            LootFrame_OnEvent(LootFrame, "LOOT_OPENED", unpack(args))
            return
        end

        -- Auto-loot is enabled:
        -- Small delay so server-side loot packets arrive first
        C_Timer.After(0.05, function()
            local numItems = GetNumLootItems()
            if numItems == 0 then
                -- Server already looted everything — close immediately (no window shown)
                CloseLoot()
                LootFrame:Hide()
                ShowLootFeedback("✓ Looted!")
            else
                -- Try client-side auto-looting for remaining items
                AutoLootAll()

                -- Re-check after client-side looting commands have been sent
                C_Timer.After(0.05, function()
                    local numRemaining = GetNumLootItems()
                    if numRemaining > 0 then
                        -- Remaining items exist (e.g. bags full, roll item, etc.), so show default LootFrame
                        LootFrame_OnEvent(LootFrame, "LOOT_OPENED", unpack(args))
                    else
                        CloseLoot()
                        LootFrame:Hide()
                        ShowLootFeedback("✓ Looted!")
                    end
                end)
            end
        end)

    elseif event == "LOOT_CLOSED" then
        -- Forward to LootFrame if it was shown/registered or let default engine handle it.
        -- LootFrame is still registered for LOOT_CLOSED, so the client engine handles it directly.
        -- No action needed here.

    elseif event == "LOOT_SLOT_CLEARED" then
        -- Check if loot window is now empty
        if ModernWoW:GetSetting("autoLoot") and AL.enabled then
            local numItems = GetNumLootItems()
            if numItems == 0 then
                ShowLootFeedback("✓ Looted!")
                CloseLoot()
                LootFrame:Hide()
            end
        end
    end
end)

-- ============================================================
-- Spell Queue: send spell early to beat latency
-- ============================================================
-- The client sends spell casts during GCD. If the server rejects them
-- (due to GCD not done yet), the server queues them.
-- Nothing special needed client-side beyond using macros like:
--   /cast [@target, exists] Frostbolt
-- which the client re-sends on the next tick.

ModernWoW:Debug("AutoLoot module loaded.")
