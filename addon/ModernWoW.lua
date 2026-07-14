-- ModernWoW Addon — Main Init
-- Compatible with WoW 3.3.5a (Interface 30300)
-- Communicates with mod-modernWoW server module via addon messages.

ModernWoW = {}
ModernWoW.Version = "1.0.0"
ModernWoW.Prefix  = "MODERNWOW"

-- Default settings
local defaults = {
    autoLoot       = true,
    questTracker   = true,
    modernFrames   = true,
    damageMeter    = true,
    collections    = true,
    minimap        = { minimapPos = 200, hide = false },
}

-- Saved variables (initialized on ADDON_LOADED)
ModernWoWDB     = ModernWoWDB     or {}
ModernWoWCharDB = ModernWoWCharDB or {}

-- ============================================================
-- Utilities
-- ============================================================

function ModernWoW:Print(msg, r, g, b)
    r = r or 0; g = g or 1; b = b or 1
    DEFAULT_CHAT_FRAME:AddMessage("|cff00FFFF[ModernWoW]|r " .. tostring(msg), r, g, b)
end

function ModernWoW:Debug(msg)
    if self.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[MWoW-Debug]|r " .. tostring(msg))
    end
end

function ModernWoW:GetSetting(key)
    if ModernWoWDB[key] ~= nil then
        return ModernWoWDB[key]
    end
    return defaults[key]
end

function ModernWoW:SetSetting(key, value)
    ModernWoWDB[key] = value
end

-- ============================================================
-- Addon message channel (server <-> addon communication)
-- ============================================================

function ModernWoW:SendMessage(msg)
    SendAddonMessage(self.Prefix, msg, "WHISPER", UnitName("player"))
end

local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ModernWoW.Prefix then return end
    if sender ~= UnitName("player") then return end

    -- Parse messages from server: "CMD:DATA"
    local cmd, data = strsplit(":", message, 2)

    if cmd == "WQ_LIST" then
        -- World quest list update from server
        if ModernWoW.QuestTracker then
            ModernWoW.QuestTracker:UpdateWorldQuests(data)
        end
    elseif cmd == "DPS" then
        -- DPS data from server
        if ModernWoW.DamageMeter then
            ModernWoW.DamageMeter:UpdateDPS(data)
        end
    elseif cmd == "PONG" then
        ModernWoW:Debug("Server ping OK")
    end
end

-- ============================================================
-- Event handler
-- ============================================================

local frame = CreateFrame("Frame", "ModernWoWMainFrame")
ModernWoW.mainFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "ModernWoW" then
            -- Initialize saved variables with defaults
            if not ModernWoWDB.initialized then
                for k, v in pairs(defaults) do
                    if ModernWoWDB[k] == nil then
                        ModernWoWDB[k] = v
                    end
                end
                ModernWoWDB.initialized = true
            end
            ModernWoW.db = ModernWoWDB

            -- Register addon message channel
            RegisterAddonMessagePrefix(ModernWoW.Prefix)
        end

    elseif event == "PLAYER_LOGIN" then
        ModernWoW:Print("v" .. ModernWoW.Version .. " loaded. Type |cffFFD700/mwow|r for options.")

        -- Notify server we're online
        C_Timer.After(2, function()
            ModernWoW:SendMessage("HELLO:" .. ModernWoW.Version)
        end)

    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    end
end)

-- ============================================================
-- Slash commands
-- ============================================================

SLASH_MODERNWOW1 = "/modernwow"
SLASH_MODERNWOW2 = "/mwow"

SlashCmdList["MODERNWOW"] = function(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower()
    arg = (arg or ""):lower()

    if cmd == "" or cmd == "help" then
        ModernWoW:Print("Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffFFD700/mwow info|r        — Show addon status")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffFFD700/mwow autoloot|r    — Toggle auto-loot")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffFFD700/mwow frames|r      — Toggle modern unit frames")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffFFD700/mwow tracker|r     — Toggle quest tracker")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffFFD700/mwow meter|r       — Toggle damage meter")

    elseif cmd == "info" then
        ModernWoW:Print("Status:")
        DEFAULT_CHAT_FRAME:AddMessage("  Auto-Loot   : " .. (ModernWoW:GetSetting("autoLoot") and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Quest Tracker: " .. (ModernWoW:GetSetting("questTracker") and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Modern Frames: " .. (ModernWoW:GetSetting("modernFrames") and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Damage Meter : " .. (ModernWoW:GetSetting("damageMeter") and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd == "autoloot" then
        local val = not ModernWoW:GetSetting("autoLoot")
        ModernWoW:SetSetting("autoLoot", val)
        ModernWoW:Print("Auto-Loot: " .. (val and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        if ModernWoW.AutoLoot then ModernWoW.AutoLoot:SetEnabled(val) end

    elseif cmd == "frames" then
        local val = not ModernWoW:GetSetting("modernFrames")
        ModernWoW:SetSetting("modernFrames", val)
        ModernWoW:Print("Modern Unit Frames: " .. (val and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

    elseif cmd == "tracker" then
        local val = not ModernWoW:GetSetting("questTracker")
        ModernWoW:SetSetting("questTracker", val)
        ModernWoW:Print("Quest Tracker: " .. (val and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        if ModernWoW.QuestTracker then ModernWoW.QuestTracker:SetEnabled(val) end

    elseif cmd == "meter" then
        local val = not ModernWoW:GetSetting("damageMeter")
        ModernWoW:SetSetting("damageMeter", val)
        ModernWoW:Print("Damage Meter: " .. (val and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        if ModernWoW.DamageMeter then ModernWoW.DamageMeter:SetEnabled(val) end

    else
        ModernWoW:Print("Unknown command. Type /mwow help")
    end
end
