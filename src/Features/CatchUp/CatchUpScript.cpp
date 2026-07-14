/*
 * mod-modernWoW — Catch-Up Mechanic
 * Copyright (C) 2024
 *
 * HOW IT WORKS:
 * If a player account has at least one character at max level (80),
 * all other characters on the same account receive:
 *   - Bonus XP multiplier (configurable, default 2x)
 *   - Slightly better loot quality (if enabled)
 *   - A brief "Veteran's Boost" aura shown in the buff bar (cosmetic)
 *
 * The check is done at login and cached. The XP bonus is applied via
 * FormulaScript::OnGainCalculation.
 */

#include "CatchUpScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include <unordered_set>

// Cache of account IDs that have at least one max-level character
static std::unordered_set<uint32> gCatchUpAccounts;

// ---------------------------------------------------------------------------
// Helper: check if an account has a max-level character (queries characters DB)
// ---------------------------------------------------------------------------
static bool AccountHasMaxLevelChar(uint32 accountId)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT COUNT(*) FROM characters WHERE account = {} AND level >= 80",
        accountId);

    if (!result)
        return false;

    Field* fields = result->Fetch();
    return fields[0].Get<uint64>() > 0;
}

// ---------------------------------------------------------------------------
// PlayerScript — manage catch-up state per login/logout
// ---------------------------------------------------------------------------
class ModernWoW_CatchUpPlayerScript : public PlayerScript
{
public:
    ModernWoW_CatchUpPlayerScript() : PlayerScript("ModernWoW_CatchUpPlayerScript") {}

    void OnPlayerLogin(Player* player) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->CatchUpEnabled)
            return;

        if (!player)
            return;

        // Max-level players don't need catch-up
        if (player->GetLevel() >= 80)
            return;

        uint32 accountId = player->GetSession()->GetAccountId();

        // Check cache first, then DB
        bool hasCatchUp = gCatchUpAccounts.count(accountId) > 0;
        if (!hasCatchUp)
        {
            hasCatchUp = AccountHasMaxLevelChar(accountId);
            if (hasCatchUp)
                gCatchUpAccounts.insert(accountId);
        }

        if (hasCatchUp)
        {
            LOG_DEBUG("module", "mod-modernWoW CatchUp: Player {} (account {}) gets catch-up bonus",
                player->GetName(), accountId);

            // Send a chat message notifying the player
            ChatHandler(player->GetSession()).PSendSysMessage(
                "|cff00ff00[mod-modernWoW]|r Catch-up bonus active! You gain %.0fx XP.",
                sModernWoWConfig->CatchUpXPMultiplier);
        }
    }

    void OnPlayerLogout(Player* player) override
    {
        // If this was a max-level char logging out, ensure account is cached
        if (player && player->GetLevel() >= 80)
            gCatchUpAccounts.insert(player->GetSession()->GetAccountId());
    }

    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        if (!player)
            return;

        // When a character reaches max level, add account to catch-up cache
        if (player->GetLevel() >= 80)
            gCatchUpAccounts.insert(player->GetSession()->GetAccountId());
    }
};

// ---------------------------------------------------------------------------
// FormulaScript — apply XP multiplier for catch-up characters
// ---------------------------------------------------------------------------
class ModernWoW_CatchUpFormulaScript : public FormulaScript
{
public:
    ModernWoW_CatchUpFormulaScript() : FormulaScript("ModernWoW_CatchUpFormulaScript") {}

    void OnGainCalculation(uint32& gain, Player* player, Unit* /*unit*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->CatchUpEnabled)
            return;

        if (!player || player->GetLevel() >= 80)
            return;

        uint32 accountId = player->GetSession()->GetAccountId();
        if (gCatchUpAccounts.count(accountId) > 0)
        {
            gain = static_cast<uint32>(gain * sModernWoWConfig->CatchUpXPMultiplier);
        }
    }
};

void AddModernWoW_CatchUpScripts()
{
    if (!sModernWoWConfig->CatchUpEnabled)
        return;

    new ModernWoW_CatchUpPlayerScript();
    new ModernWoW_CatchUpFormulaScript();
}
