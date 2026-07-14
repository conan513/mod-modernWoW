/*
 * mod-modernWoW — GM/Admin Commands
 * Copyright (C) 2024
 *
 * Available commands:
 *   .modernwow info             — Shows module status and active features
 *   .modernwow reload           — Reloads config (hot reload)
 *   .modernwow wq list          — Lists active world quests
 *   .modernwow wq refresh       — Forces a world quest refresh (GM only)
 *   .modernwow autoloot on/off  — Toggles auto-loot per player (or global)
 *   .modernwow catchup [player] — Shows catch-up status for a player
 */

#include "ModernWoW_Commands.h"
#include "ModernWoW_Config.h"
#include "WorldQuestMgr.h"
#include "ScriptMgr.h"
#include "ChatCommand.h"
#include "ChatHandler.h"
#include "Player.h"
#include "GameTime.h"
#include "Log.h"
#include <ctime>

using namespace Acore::ChatCommands;

class ModernWoW_CommandScript : public CommandScript
{
public:
    ModernWoW_CommandScript() : CommandScript("ModernWoW_CommandScript") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable wqCommandTable =
        {
            { "list",    HandleWQListCommand,    SEC_PLAYER,        Console::No  },
            { "refresh", HandleWQRefreshCommand, SEC_ADMINISTRATOR, Console::Yes },
        };

        static ChatCommandTable modernWoWCommandTable =
        {
            { "info",     HandleInfoCommand,     SEC_PLAYER,        Console::No  },
            { "reload",   HandleReloadCommand,   SEC_ADMINISTRATOR, Console::Yes },
            { "wq",       wqCommandTable                                         },
            { "autoloot", HandleAutoLootCommand, SEC_PLAYER,        Console::No  },
            { "catchup",  HandleCatchUpCommand,  SEC_MODERATOR,     Console::No  },
        };

        static ChatCommandTable commandTable =
        {
            { "modernwow", modernWoWCommandTable },
            { "mwow",      modernWoWCommandTable }, // short alias
        };

        return commandTable;
    }

    // -----------------------------------------------------------------------
    // .modernwow info
    // -----------------------------------------------------------------------
    static bool HandleInfoCommand(ChatHandler* handler, char const* /*args*/)
    {
        handler->PSendSysMessage("|cff00FFFF[mod-modernWoW]|r Status:");
        handler->PSendSysMessage("  Enabled       : %s", sModernWoWConfig->Enabled     ? "|cff00ff00ON|r" : "|cffff0000OFF|r");
        handler->PSendSysMessage("  Auto-Loot     : %s (mode %u)", sModernWoWConfig->AutoLootMode > 0 ? "|cff00ff00ON|r" : "|cffff0000OFF|r", sModernWoWConfig->AutoLootMode);
        handler->PSendSysMessage("  Dyn.Scaling   : %s", sModernWoWConfig->DynScaleEnabled  ? "|cff00ff00ON|r" : "|cffff0000OFF|r");
        handler->PSendSysMessage("  PersonalLoot  : %s (mode %u)", sModernWoWConfig->PersonalLootMode > 0 ? "|cff00ff00ON|r" : "|cffff0000OFF|r", sModernWoWConfig->PersonalLootMode);
        handler->PSendSysMessage("  SpellQueue    : %s (%ums)", sModernWoWConfig->SpellQueueEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r", sModernWoWConfig->SpellQueueWindowMs);
        handler->PSendSysMessage("  WorldQuests   : %s (%u active)", sModernWoWConfig->WorldQuestsEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r",
            static_cast<uint32>(sWorldQuestMgr->GetActiveWorldQuests().size()));
        handler->PSendSysMessage("  CatchUp       : %s (%.1fx XP)", sModernWoWConfig->CatchUpEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r", sModernWoWConfig->CatchUpXPMultiplier);
        handler->PSendSysMessage("  InstantMail   : %s", sModernWoWConfig->InstantMailEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r");
        handler->PSendSysMessage("  GuildPerks    : %s (+%u%% XP, %u%% CashFlow)", sModernWoWConfig->GuildPerksEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r",
            sModernWoWConfig->GuildPerksXPBonus, sModernWoWConfig->GuildPerksCashFlow);
        return true;
    }

    // -----------------------------------------------------------------------
    // .modernwow reload
    // -----------------------------------------------------------------------
    static bool HandleReloadCommand(ChatHandler* handler, char const* /*args*/)
    {
        sModernWoWConfig->Load();
        handler->PSendSysMessage("|cff00FFFF[mod-modernWoW]|r Config reloaded.");
        return true;
    }

    // -----------------------------------------------------------------------
    // .modernwow wq list
    // -----------------------------------------------------------------------
    static bool HandleWQListCommand(ChatHandler* handler, char const* /*args*/)
    {
        auto const& wqs = sWorldQuestMgr->GetActiveWorldQuests();
        if (wqs.empty())
        {
            handler->SendSysMessage("|cffFFD700[World Quests]|r No active world quests.");
            return true;
        }

        handler->PSendSysMessage("|cffFFD700[World Quests]|r %zu active:", wqs.size());
        uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
        for (auto const& wq : wqs)
        {
            uint32 secsLeft = wq.expiresAt > now ? wq.expiresAt - now : 0;
            uint32 hrsLeft  = secsLeft / 3600;
            handler->PSendSysMessage("  Quest ID %u — expires in %uh", wq.questId, hrsLeft);
        }
        return true;
    }

    // -----------------------------------------------------------------------
    // .modernwow wq refresh
    // -----------------------------------------------------------------------
    static bool HandleWQRefreshCommand(ChatHandler* handler, char const* /*args*/)
    {
        sWorldQuestMgr->RefreshWorldQuests();
        handler->PSendSysMessage("|cffFFD700[World Quests]|r World quests refreshed (%zu active).",
            sWorldQuestMgr->GetActiveWorldQuests().size());
        return true;
    }

    // -----------------------------------------------------------------------
    // .modernwow autoloot [on|off|0|1|2]
    // -----------------------------------------------------------------------
    static bool HandleAutoLootCommand(ChatHandler* handler, char const* args)
    {
        if (!args || !*args)
        {
            handler->PSendSysMessage("Auto-Loot mode: %u (0=off, 1=all, 2=threshold)", sModernWoWConfig->AutoLootMode);
            return true;
        }

        std::string arg(args);
        if (arg == "on" || arg == "1")
            handler->PSendSysMessage("Use |cff00FFFF.reload config|r to apply config changes, or edit the conf file.");
        else if (arg == "off" || arg == "0")
            handler->PSendSysMessage("Use |cff00FFFF.reload config|r to apply config changes, or edit the conf file.");
        else
            handler->SendSysMessage("Usage: .modernwow autoloot [on|off]");

        return true;
    }

    // -----------------------------------------------------------------------
    // .modernwow catchup [player]
    // -----------------------------------------------------------------------
    static bool HandleCatchUpCommand(ChatHandler* handler, char const* args)
    {
        Player* target = handler->getSelectedPlayer();
        if (args && *args)
        {
            target = ObjectAccessor::FindPlayerByName(args);
        }

        if (!target)
        {
            handler->SendSysMessage("Player not found.");
            return false;
        }

        handler->PSendSysMessage("Catch-up status for |cff00ff00%s|r: account %u, level %u",
            target->GetName().c_str(),
            target->GetSession()->GetAccountId(),
            target->GetLevel());

        return true;
    }
};

void AddModernWoW_CommandScripts()
{
    new ModernWoW_CommandScript();
}
