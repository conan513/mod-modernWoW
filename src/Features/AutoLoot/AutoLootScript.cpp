/*
 * mod-modernWoW — Auto-Loot Feature
 * Copyright (C) 2024
 *
 * Automatically loots all items (or below-threshold items) from a corpse
 * when the loot window is opened. Mirrors modern WoW's auto-loot behavior.
 *
 * Uses OnPlayerBeforeSendLoot hook to trigger item pickup before the loot
 * window packet is sent to the client.
 */

#include "AutoLootScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "LootMgr.h"
#include "Log.h"

class ModernWoW_AutoLootScript : public PlayerScript
{
public:
    ModernWoW_AutoLootScript() : PlayerScript("ModernWoW_AutoLootScript") {}

    // Called just before the loot packet is sent to the player.
    // At this point, loot->items is fully populated.
    void OnPlayerBeforeSendLoot(Player* player, ObjectGuid /*lootGuid*/, Loot* loot) override
    {
        if (!sModernWoWConfig->Enabled || sModernWoWConfig->AutoLootMode == 0)
            return;

        if (!loot || !player)
            return;

        // Don't auto-loot in pickpocketing or disenchanting contexts
        if (loot->loot_type == LOOT_PICKPOCKETING ||
            loot->loot_type == LOOT_DISENCHANTING ||
            loot->loot_type == LOOT_PROSPECTING ||
            loot->loot_type == LOOT_MILLING)
            return;

        // --- Auto-loot gold ---
        if (sModernWoWConfig->AutoLootGold && loot->gold > 0)
        {
            player->ModifyMoney(loot->gold);
            player->UpdateAchievementCriteria(ACHIEVEMENT_CRITERIA_TYPE_LOOT_MONEY, loot->gold);
            loot->gold = 0;
        }

        // --- Auto-loot items ---
        // We iterate over the loot slots by index. StoreLootItem handles all
        // permission and duplicate checks internally.
        uint8 maxSlot = static_cast<uint8>(loot->items.size());
        for (uint8 slot = 0; slot < maxSlot; ++slot)
        {
            LootItem& lootItem = loot->items[slot];

            // Skip already looted items
            if (lootItem.is_looted)
                continue;

            // Skip blocked (roll pending) items
            if (lootItem.is_blocked)
                continue;

            // In threshold mode, only auto-loot items below the quality threshold
            if (sModernWoWConfig->AutoLootMode == 2)
            {
                ItemTemplate const* proto = sObjectMgr->GetItemTemplate(lootItem.itemid);
                if (proto && proto->Quality > sModernWoWConfig->AutoLootThreshold)
                    continue;
            }

            // Check if the player is allowed to loot this item
            if (!lootItem.AllowedForPlayer(player, loot->sourceWorldObjectGUID))
                continue;

            // Attempt to store the item
            InventoryResult msg;
            player->StoreLootItem(slot, loot, msg);
            // StoreLootItem handles all notifications and DB updates internally
        }
    }
};

void AddModernWoW_AutoLootScripts()
{
    if (sModernWoWConfig->AutoLootMode > 0)
        new ModernWoW_AutoLootScript();
}
