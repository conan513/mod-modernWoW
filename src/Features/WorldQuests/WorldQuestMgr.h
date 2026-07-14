/*
 * mod-modernWoW — World Quest Manager
 * Copyright (C) 2024
 */

#ifndef MOD_MODERNWOW_WORLDQUESTMGR_H
#define MOD_MODERNWOW_WORLDQUESTMGR_H

#include "Common.h"
#include <vector>
#include <unordered_map>

// Represents a single active World Quest slot
struct WorldQuestEntry
{
    uint32 questId;
    uint32 expiresAt;  // Unix timestamp when this WQ expires
};

class WorldQuestMgr
{
public:
    static WorldQuestMgr* instance();

    // Called on server startup — loads active world quests from DB or generates new ones
    void Initialize();

    // Called daily to rotate world quests
    void RefreshWorldQuests();

    // Returns the list of currently active world quests
    std::vector<WorldQuestEntry> const& GetActiveWorldQuests() const { return _activeQuests; }

    // Returns true if the given quest is currently a world quest
    bool IsWorldQuest(uint32 questId) const;

    // Check if a player has completed a world quest today
    bool HasPlayerCompletedToday(ObjectGuid playerGuid, uint32 questId) const;

    // Mark a world quest as completed for a player
    void MarkCompleted(ObjectGuid playerGuid, uint32 questId);

    // Save state to DB
    void SaveToDB();

    // Load state from DB
    void LoadFromDB();

private:
    WorldQuestMgr() = default;

    void GenerateNewWorldQuests();

    std::vector<WorldQuestEntry> _activeQuests;
    std::vector<uint32>          _questPool;  // All eligible quest IDs loaded from DB

    // player GUID low -> set of quest IDs completed today
    std::unordered_map<ObjectGuid::LowType, std::vector<uint32>> _completedToday;

    uint32 _lastRefreshDay = 0;
};

#define sWorldQuestMgr WorldQuestMgr::instance()

#endif // MOD_MODERNWOW_WORLDQUESTMGR_H
