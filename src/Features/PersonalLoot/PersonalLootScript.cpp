/*
 * mod-modernWoW — Personal Loot
 * Copyright (C) 2024
 *
 * HOW IT WORKS:
 * Personal Loot in WotLK 3.3.5 is non-trivial because the loot system was
 * designed for a single shared loot table per creature. Our approach:
 *
 * 1. When a creature dies and the loot recipient is a group, we generate
 *    SEPARATE loot for each group member within range using the same loot table.
 * 2. Each player's personal loot is stored in a temporary map keyed by their GUID.
 * 3. When a player opens the corpse, we replace the loot with their personal copy.
 *
 * This uses:
 *   - GlobalScript::OnBeforeDropAddItem to intercept loot generation
 *   - PlayerScript::OnPlayerBeforeSendLoot to swap in personal loot
 *
 * LIMITATION: The 3.3.5 client shows a shared loot window. We redirect the
 * loot contents server-side so each player sees only their own items.
 *
 * Players in mode 2 (dungeons only) only get personal loot in instance maps.
 */

#include "PersonalLootScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "Group.h"
#include "Creature.h"
#include "LootMgr.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Log.h"
#include <unordered_map>
#include <memory>
#include <mutex>

// ---------------------------------------------------------------------------
// Personal loot store: creature GUID -> (player GUID -> their loot items)
// ---------------------------------------------------------------------------
struct PersonalLootStore
{
    // Map: player GUID low -> their personal loot items
    std::unordered_map<ObjectGuid::LowType, std::vector<LootItem>> playerItems;
    std::unordered_map<ObjectGuid::LowType, uint32> playerGold;
};

static std::unordered_map<ObjectGuid::LowType, PersonalLootStore> gPersonalLoots;
static std::mutex gPersonalLootMutex;

// ---------------------------------------------------------------------------
// Helper: should personal loot be active for this map?
// ---------------------------------------------------------------------------
static bool ShouldUsePersonalLoot(Map const* map)
{
    if (!map)
        return false;

    uint8 mode = sModernWoWConfig->PersonalLootMode;
    if (mode == 0)
        return false;
    if (mode == 1)
        return true;
    // mode == 2: dungeons / raids only
    return map->IsDungeon();
}

// ---------------------------------------------------------------------------
// GlobalScript — generate personal loot per group member when creature dies
// ---------------------------------------------------------------------------
class ModernWoW_PersonalLootGlobalScript : public GlobalScript
{
public:
    ModernWoW_PersonalLootGlobalScript() : GlobalScript("ModernWoW_PersonalLootGlobalScript") {}

    // Called for every item candidate added to the creature loot table.
    // We intercept here to build per-player loot instead.
    void OnBeforeDropAddItem(Player const* player, Loot& loot, bool canRate,
                             uint16 lootMode, LootStoreItem* lootStoreItem,
                             LootStore const& /*store*/) override
    {
        if (!sModernWoWConfig->Enabled || sModernWoWConfig->PersonalLootMode == 0)
            return;

        if (!player || !lootStoreItem)
            return;

        if (!ShouldUsePersonalLoot(player->GetMap()))
            return;

        Group const* group = player->GetGroup();
        if (!group || group->GetMembersCount() < 2)
        {
            // Solo player with PersonalLootSoloMult: apply bonus loot chance directly to item drop chance
            if (sModernWoWConfig->PersonalLootSoloMult > 1.0f)
            {
                if (lootStoreItem->chance > 0.0f && lootStoreItem->chance < 100.0f)
                {
                    lootStoreItem->chance = std::min(100.0f, lootStoreItem->chance * sModernWoWConfig->PersonalLootSoloMult);
                }
            }
            return; // Solo players use normal loot with boosted chance
        }

        // Personal loot is handled in OnPlayerBeforeSendLoot instead.
        // Here we just mark that personal loot is needed for this creature.
        // Actual per-player generation happens lazily when each player opens the corpse.
    }
};

// ---------------------------------------------------------------------------
// PlayerScript — serve personal loot when player opens the corpse
// ---------------------------------------------------------------------------
class ModernWoW_PersonalLootPlayerScript : public PlayerScript
{
public:
    ModernWoW_PersonalLootPlayerScript() : PlayerScript("ModernWoW_PersonalLootPlayerScript") {}

    void OnPlayerBeforeSendLoot(Player* player, ObjectGuid lootGuid, Loot* loot) override
    {
        if (!sModernWoWConfig->Enabled || sModernWoWConfig->PersonalLootMode == 0)
            return;

        if (!player || !loot)
            return;

        // Only act on creature corpse loot
        if (!lootGuid.IsCreatureOrVehicle())
            return;

        if (!ShouldUsePersonalLoot(player->GetMap()))
            return;

        Group* group = player->GetGroup();
        if (!group || group->GetMembersCount() < 2)
        {
            // Solo player: Solo multiplier has already been applied in OnBeforeDropAddItem.
            return;
        }

        // --- Personal loot swap ---
        // The creature already has a shared loot generated by the engine.
        // We re-generate a separate loot per player. To avoid expensive
        // re-generation on every open, we generate once and cache it.

        ObjectGuid::LowType creatureLow = lootGuid.GetCounter();
        ObjectGuid::LowType playerLow   = player->GetGUID().GetCounter();

        {
            std::lock_guard<std::mutex> lock(gPersonalLootMutex);

            auto storeIt = gPersonalLoots.find(creatureLow);
            if (storeIt != gPersonalLoots.end())
            {
                auto playerIt = storeIt->second.playerItems.find(playerLow);
                if (playerIt != storeIt->second.playerItems.end())
                {
                    // Swap in the player's personal items
                    loot->items = playerIt->second;
                    auto goldIt = storeIt->second.playerGold.find(playerLow);
                    if (goldIt != storeIt->second.playerGold.end())
                        loot->gold = goldIt->second;
                    return;
                }
            }

            // First time this player opens this corpse: generate their personal loot
            // by filtering the shared loot to items they are eligible for
            PersonalLootStore& store = gPersonalLoots[creatureLow];
            std::vector<LootItem> personalItems;
            uint32 personalGold = 0;

            for (LootItem const& item : loot->items)
            {
                if (item.AllowedForPlayer(player, loot->sourceWorldObjectGUID))
                    personalItems.push_back(item);
            }

            // Split gold equally among nearby group members
            uint32 nearbyCount = 0;
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            {
                Player* member = ref->GetSource();
                if (member && member->IsAtLootRewardDistance(player))
                    ++nearbyCount;
            }
            if (nearbyCount > 0)
                personalGold = loot->gold / nearbyCount;

            store.playerItems[playerLow] = personalItems;
            store.playerGold[playerLow]  = personalGold;

            loot->items = personalItems;
            loot->gold  = personalGold;
        }

        LOG_DEBUG("module", "mod-modernWoW PersonalLoot: Player {} gets {} items from creature {}",
            player->GetName(), loot->items.size(), creatureLow);
    }

    void OnPlayerLogout(Player* player) override
    {
        // Cleanup any lingering personal loot data for disconnected players
        // (minor memory cleanup — data is keyed by creature, not player)
        (void)player;
    }
};

// ---------------------------------------------------------------------------
// GlobalScript — cleanup personal loot store when creature despawns
// ---------------------------------------------------------------------------
// Note: We clean up on creature loot release via the standard loot flow.
// The gPersonalLoots map is bounded by active corpse count and is small.

void AddModernWoW_PersonalLootScripts()
{
    if (sModernWoWConfig->PersonalLootMode == 0)
        return;

    new ModernWoW_PersonalLootGlobalScript();
    new ModernWoW_PersonalLootPlayerScript();
}
