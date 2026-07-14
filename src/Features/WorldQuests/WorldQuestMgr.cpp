/*
 * mod-modernWoW — World Quest Manager
 * Copyright (C) 2024
 *
 * HOW IT WORKS:
 * 1. A pool of eligible quests is loaded from `modernwow_worldquest_pool` (DB).
 *    These are normal quests tagged as world quest candidates by admins.
 * 2. On server start (and daily reset), N random quests are selected from
 *    the pool and become "active world quests" for the next 24 hours.
 * 3. Players who complete an active world quest get bonus rewards (gold/xp)
 *    on top of the normal quest reward, tracked in `modernwow_wq_completions`.
 * 4. Active world quests are visible to players via the addon's quest tracker.
 *
 * DAILY RESET: The WorldScript::OnUpdate checks every minute if the day has
 * changed and triggers a refresh when needed.
 */

#include "WorldQuestMgr.h"
#include "ModernWoW_Config.h"
#include "DatabaseEnv.h"
#include "QueryResult.h"
#include "Field.h"
#include "GameTime.h"
#include "Random.h"
#include "Log.h"
#include <algorithm>
#include <ctime>
#include <random>

WorldQuestMgr* WorldQuestMgr::instance()
{
    static WorldQuestMgr inst;
    return &inst;
}

void WorldQuestMgr::Initialize()
{
    if (!sModernWoWConfig->WorldQuestsEnabled)
        return;

    // Load quest pool from DB
    QueryResult result = WorldDatabase.Query(
        "SELECT quest_id FROM modernwow_worldquest_pool WHERE enabled = 1");

    if (result)
    {
        do
        {
            Field* fields = result->Fetch();
            _questPool.push_back(fields[0].Get<uint32>());
        } while (result->NextRow());
    }

    LOG_INFO("module", "mod-modernWoW WorldQuests: Loaded {} quests into pool.", _questPool.size());

    LoadFromDB();

    // If no active quests yet, generate them now
    if (_activeQuests.empty())
        GenerateNewWorldQuests();
}

void WorldQuestMgr::GenerateNewWorldQuests()
{
    _activeQuests.clear();

    if (_questPool.empty())
    {
        LOG_WARN("module", "mod-modernWoW WorldQuests: Quest pool is empty! Add entries to modernwow_worldquest_pool.");
        return;
    }

    uint32 count = std::min<uint32>(sModernWoWConfig->WorldQuestsActiveCount,
                                    static_cast<uint32>(_questPool.size()));

    // Shuffle and pick 'count' quests
    std::vector<uint32> pool = _questPool;
    std::shuffle(pool.begin(), pool.end(), std::mt19937{std::random_device{}()});

    uint32 expireTime = static_cast<uint32>(GameTime::GetGameTime().count())
                      + sModernWoWConfig->WorldQuestsDurationHours * 3600;

    for (uint32 i = 0; i < count; ++i)
    {
        WorldQuestEntry entry;
        entry.questId   = pool[i];
        entry.expiresAt = expireTime;
        _activeQuests.push_back(entry);
    }

    LOG_INFO("module", "mod-modernWoW WorldQuests: Generated {} active world quests (expire in {}h).",
        count, sModernWoWConfig->WorldQuestsDurationHours);

    SaveToDB();
}

void WorldQuestMgr::RefreshWorldQuests()
{
    // Clear yesterday's completions
    _completedToday.clear();

    GenerateNewWorldQuests();
}

bool WorldQuestMgr::IsWorldQuest(uint32 questId) const
{
    for (auto const& wq : _activeQuests)
        if (wq.questId == questId)
            return true;
    return false;
}

bool WorldQuestMgr::HasPlayerCompletedToday(ObjectGuid playerGuid, uint32 questId) const
{
    auto it = _completedToday.find(playerGuid.GetCounter());
    if (it == _completedToday.end())
        return false;

    auto const& vec = it->second;
    return std::find(vec.begin(), vec.end(), questId) != vec.end();
}

void WorldQuestMgr::MarkCompleted(ObjectGuid playerGuid, uint32 questId)
{
    _completedToday[playerGuid.GetCounter()].push_back(questId);

    // Persist to DB
    CharacterDatabase.Execute(
        "INSERT IGNORE INTO modernwow_wq_completions (player_guid, quest_id, completed_date) "
        "VALUES ({}, {}, CURDATE())",
        playerGuid.GetCounter(), questId);
}

void WorldQuestMgr::SaveToDB()
{
    // Clear old active quests
    WorldDatabase.Execute("DELETE FROM modernwow_active_worldquests");

    for (auto const& wq : _activeQuests)
    {
        WorldDatabase.Execute(
            "INSERT INTO modernwow_active_worldquests (quest_id, expires_at) VALUES ({}, {})",
            wq.questId, wq.expiresAt);
    }
}

void WorldQuestMgr::LoadFromDB()
{
    uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());

    QueryResult result = WorldDatabase.Query(
        "SELECT quest_id, expires_at FROM modernwow_active_worldquests WHERE expires_at > {}",
        now);

    if (!result)
        return;

    do
    {
        Field* fields = result->Fetch();
        WorldQuestEntry entry;
        entry.questId   = fields[0].Get<uint32>();
        entry.expiresAt = fields[1].Get<uint32>();
        _activeQuests.push_back(entry);
    } while (result->NextRow());

    LOG_INFO("module", "mod-modernWoW WorldQuests: Loaded {} active world quests from DB.", _activeQuests.size());
}
