/*
 * mod-modernWoW — World Quest Scripts
 * Copyright (C) 2024
 *
 * Hooks into the quest completion system to grant bonus rewards for
 * active world quests, and into the WorldScript to handle daily resets.
 */

#include "WorldQuestScript.h"
#include "WorldQuestMgr.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "Quest.h"
#include "ChatHandler.h"
#include "GameTime.h"
#include "Log.h"
#include <ctime>

// ---------------------------------------------------------------------------
// PlayerScript — bonus reward on world quest completion
// ---------------------------------------------------------------------------
class ModernWoW_WorldQuestPlayerScript : public PlayerScript
{
public:
    ModernWoW_WorldQuestPlayerScript() : PlayerScript("ModernWoW_WorldQuestPlayerScript") {}

    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->WorldQuestsEnabled)
            return;

        if (!player || !quest)
            return;

        uint32 questId = quest->GetQuestId();
        if (!sWorldQuestMgr->IsWorldQuest(questId))
            return;

        if (sWorldQuestMgr->HasPlayerCompletedToday(player->GetGUID(), questId))
            return;

        sWorldQuestMgr->MarkCompleted(player->GetGUID(), questId);

        // Grant bonus rewards (gold + XP proportional to player level)
        uint32 bonusGold = player->GetLevel() * 100 * 10; // level * 1 gold base
        uint32 bonusXP   = player->GetLevel() * 500;

        player->ModifyMoney(bonusGold);
        player->GiveXP(bonusXP, nullptr);

        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cffFFD700[World Quest]|r |cff00FF00%s|r completed! Bonus: +%u gold, +%u XP.",
            quest->GetTitle().c_str(),
            bonusGold / 10000,
            bonusXP);

        LOG_DEBUG("module", "mod-modernWoW WorldQuest: Player {} completed WQ {} (bonus +{}g +{}xp)",
            player->GetName(), questId, bonusGold, bonusXP);
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->WorldQuestsEnabled)
            return;

        if (!player)
            return;

        auto const& wqs = sWorldQuestMgr->GetActiveWorldQuests();
        if (wqs.empty())
            return;

        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cffFFD700[World Quests]|r %zu active world quests available today! "
            "Complete them for bonus gold and XP.", wqs.size());
    }
};

// ---------------------------------------------------------------------------
// WorldScript — daily reset timer
// ---------------------------------------------------------------------------
class ModernWoW_WorldQuestWorldScript : public WorldScript
{
public:
    ModernWoW_WorldQuestWorldScript() : WorldScript("ModernWoW_WorldQuestWorldScript") {}

    void OnStartup() override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->WorldQuestsEnabled)
            return;

        sWorldQuestMgr->Initialize();
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->WorldQuestsEnabled)
            return;

        // Check for daily reset every real minute (reduce overhead)
        static uint32 checkTimer = 0;
        checkTimer += 1000; // diff is in ms but we call this once per update
        if (checkTimer < 60000)
            return;
        checkTimer = 0;

        // Get current day number
        time_t now = GameTime::GetGameTime().count();
        struct tm* tmNow = localtime(&now);
        uint32 currentDay = tmNow->tm_yday + (tmNow->tm_year * 365);

        // Compare to the day we last refreshed
        static uint32 lastDay = 0;
        if (lastDay == 0)
        {
            lastDay = currentDay;
            return;
        }

        if (currentDay != lastDay)
        {
            lastDay = currentDay;
            LOG_INFO("module", "mod-modernWoW WorldQuests: Daily reset — refreshing world quests.");
            sWorldQuestMgr->RefreshWorldQuests();
        }
    }
};

void AddModernWoW_WorldQuestScripts()
{
    if (!sModernWoWConfig->WorldQuestsEnabled)
        return;

    new ModernWoW_WorldQuestPlayerScript();
    new ModernWoW_WorldQuestWorldScript();
}
