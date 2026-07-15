/*
 * mod-modernWoW — Guild Perks
 * Copyright (C) 2024
 *
 * HOW IT WORKS:
 * A simplified version of the retail Guild Perk system:
 *
 *  1. GUILD XP BONUS — Guild members receive a flat % XP bonus
 *     (applied via FormulaScript::OnGainCalculation).
 *
 *  2. CASH FLOW — A percentage of looted gold is automatically deposited
 *     to the guild bank (applied via PlayerScript::OnPlayerBeforeLootMoney).
 *
 *  3. FAST TRACK (future) — Reduced durability loss for guild members.
 *
 * Both perks are always active (no guild level requirement) but can be
 * individually configured. This is intentionally simple — a full guild
 * leveling system would require significant additional work.
 *
 * INSTANT MAIL: Also handled here since it is a single-line config change
 * achieved by zeroing the mail delivery time in the WorldScript startup via
 * sWorld config, which is the cleanest approach.
 */

#include "GuildPerksScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "LootMgr.h"
#include "Mail.h"
#include "World.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include <mutex>
#include <unordered_map>

// ---------------------------------------------------------------------------
// CashFlow accumulator — instead of one DB transaction per loot event,
// we accumulate gold in-memory and flush every 30 seconds.
// Key: guildId  |  Value: copper amount pending deposit
// ---------------------------------------------------------------------------
static std::unordered_map<uint32, uint32> gPendingCashFlow;
static std::mutex gCashFlowMutex;

static void FlushCashFlow()
{
    std::unordered_map<uint32, uint32> snapshot;

    // Grab and clear under lock, then write outside the lock
    {
        std::lock_guard<std::mutex> lock(gCashFlowMutex);
        if (gPendingCashFlow.empty())
            return;
        snapshot = std::move(gPendingCashFlow);
        gPendingCashFlow.clear();
    }

    for (auto const& [guildId, copper] : snapshot)
    {
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (!guild)
            continue;

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        (void)guild->ModifyBankMoney(trans, copper, true);
        CharacterDatabase.CommitTransaction(trans);

        LOG_DEBUG("module", "mod-modernWoW GuildPerks: CashFlow flush — deposited {} copper to guild {}",
            copper, guildId);
    }
}

// ---------------------------------------------------------------------------
// FormulaScript — Guild XP Bonus
// ---------------------------------------------------------------------------
class ModernWoW_GuildPerksFormulaScript : public FormulaScript
{
public:
    ModernWoW_GuildPerksFormulaScript() : FormulaScript("ModernWoW_GuildPerksFormulaScript") {}

    void OnGainCalculation(uint32& gain, Player* player, Unit* /*unit*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->GuildPerksEnabled)
            return;

        if (!player || sModernWoWConfig->GuildPerksXPBonus == 0)
            return;

        // Only apply for guild members
        if (!player->GetGuildId())
            return;

        float bonus = 1.0f + (sModernWoWConfig->GuildPerksXPBonus / 100.0f);
        gain = static_cast<uint32>(gain * bonus);
    }
};

// ---------------------------------------------------------------------------
// PlayerScript — Cash Flow (gold percentage to guild bank on loot)
// Accumulates gold in-memory; actual DB write happens every 30 s via WorldScript.
// ---------------------------------------------------------------------------
class ModernWoW_GuildPerksPlayerScript : public PlayerScript
{
public:
    ModernWoW_GuildPerksPlayerScript() : PlayerScript("ModernWoW_GuildPerksPlayerScript") {}

    void OnPlayerBeforeLootMoney(Player* player, Loot* loot) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->GuildPerksEnabled)
            return;

        if (!player || !loot || sModernWoWConfig->GuildPerksCashFlow == 0)
            return;

        uint32 guildId = player->GetGuildId();
        if (!guildId)
            return;

        if (loot->gold == 0)
            return;

        // Calculate cash flow amount
        uint32 cashFlow = static_cast<uint32>(loot->gold * sModernWoWConfig->GuildPerksCashFlow / 100.0f);
        if (cashFlow == 0)
            return;

        // Accumulate in-memory — NO DB hit here
        {
            std::lock_guard<std::mutex> lock(gCashFlowMutex);
            gPendingCashFlow[guildId] += cashFlow;
        }

        LOG_DEBUG("module", "mod-modernWoW GuildPerks: CashFlow +{} copper queued for guild {} (player {})",
            cashFlow, guildId, player->GetName());
    }
};

// ---------------------------------------------------------------------------
// WorldScript — CashFlow flush timer (every 30 seconds)
// ---------------------------------------------------------------------------
class ModernWoW_GuildPerksCashFlowWorldScript : public WorldScript
{
public:
    ModernWoW_GuildPerksCashFlowWorldScript() : WorldScript("ModernWoW_GuildPerksCashFlowWorldScript") {}

    void OnUpdate(uint32 diff) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->GuildPerksEnabled)
            return;

        if (sModernWoWConfig->GuildPerksCashFlow == 0)
            return;

        _flushTimer += diff;
        if (_flushTimer < FLUSH_INTERVAL_MS)
            return;

        _flushTimer = 0;
        FlushCashFlow();
    }

private:
    static constexpr uint32 FLUSH_INTERVAL_MS = 30000; // 30 seconds
    uint32 _flushTimer = 0;
};

// ---------------------------------------------------------------------------
// WorldScript — Global Config Overrides (Instant Mail & Low-Level Quests)
// ---------------------------------------------------------------------------
class ModernWoW_GlobalOverridesWorldScript : public WorldScript
{
public:
    ModernWoW_GlobalOverridesWorldScript() : WorldScript("ModernWoW_GlobalOverridesWorldScript") {}

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        if (!sModernWoWConfig->Enabled)
            return;

        // Override the global mail delivery delay to 0
        if (sModernWoWConfig->InstantMailEnabled)
        {
            sWorld->setIntConfig(CONFIG_MAIL_DELIVERY_DELAY, 0);
            LOG_DEBUG("module", "mod-modernWoW: Mail delivery delay set to 0.");
        }

        // Override the low level quest hide difference to 99 so they show as normal gold quests
        if (sModernWoWConfig->QuestsShowLowLevelAsNormal)
        {
            sWorld->setIntConfig(CONFIG_QUEST_LOW_LEVEL_HIDE_DIFF, 99);
            LOG_DEBUG("module", "mod-modernWoW: Low level quest hide difference set to 99.");
        }
    }
};

void AddModernWoW_GuildPerksScripts()
{
    if (sModernWoWConfig->GuildPerksEnabled)
    {
        if (sModernWoWConfig->GuildPerksXPBonus > 0)
            new ModernWoW_GuildPerksFormulaScript();

        if (sModernWoWConfig->GuildPerksCashFlow > 0)
        {
            new ModernWoW_GuildPerksPlayerScript();
            new ModernWoW_GuildPerksCashFlowWorldScript();
        }
    }

    if (sModernWoWConfig->InstantMailEnabled || sModernWoWConfig->QuestsShowLowLevelAsNormal)
        new ModernWoW_GlobalOverridesWorldScript();
}
