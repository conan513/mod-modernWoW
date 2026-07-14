/*
 * mod-modernWoW — Spell Queue
 * Copyright (C) 2024
 *
 * HOW IT WORKS:
 * In retail WoW, a "spell queue window" allows the next spell to be queued
 * during the last ~400ms of a GCD or cast time. This prevents latency from
 * causing missed casts.
 *
 * AzerothCore already has a basic spell queue via the client's 
 * "missilespeed" mechanic. Here we extend it by:
 *   1. Tracking the last cast-attempt with a timestamp per player
 *   2. In OnPlayerUpdate, if the player just came off GCD/cast and has a
 *      queued spell within the window, we cast it automatically
 *
 * LIMITATION: Full spell queue requires client-side cooperation. This
 * implementation handles the server-side "re-try" window. Players should
 * also use the ModernWoW WoW Addon which sends the spell cast slightly
 * early to compensate for latency.
 */

#include "SpellQueueScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "Spell.h"
#include "SpellInfo.h"
#include "ObjectAccessor.h"
#include "Log.h"
#include <unordered_map>
#include <chrono>

// ---------------------------------------------------------------------------
// Per-player spell queue entry
// ---------------------------------------------------------------------------
struct QueuedSpell
{
    uint32 spellId      = 0;
    ObjectGuid targetGuid;
    uint32 queuedAtMs   = 0; // server time ms when spell was queued
};

static std::unordered_map<ObjectGuid::LowType, QueuedSpell> gSpellQueue;

// ---------------------------------------------------------------------------
// PlayerScript
// ---------------------------------------------------------------------------
class ModernWoW_SpellQueueScript : public PlayerScript
{
public:
    ModernWoW_SpellQueueScript() : PlayerScript("ModernWoW_SpellQueueScript") {}

    // Called every player update tick
    void OnPlayerUpdate(Player* player, uint32 /*diff*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->SpellQueueEnabled)
            return;

        if (!player || !player->IsInWorld())
            return;

        auto queueIt = gSpellQueue.find(player->GetGUID().GetCounter());
        if (queueIt == gSpellQueue.end())
            return;

        QueuedSpell& queued = queueIt->second;
        if (queued.spellId == 0)
            return;

        // Check if the queue window has expired
        uint32 nowMs = getMSTime();
        if (nowMs - queued.queuedAtMs > sModernWoWConfig->SpellQueueWindowMs)
        {
            // Window expired — discard the queued spell
            queued.spellId = 0;
            return;
        }

        // Check if player is now able to cast (not casting, GCD done)
        if (player->IsNonMeleeSpellCast(false))
            return;

        if (player->GetGlobalCooldownMgr().HasGlobalCooldown(player,
            sSpellMgr->GetSpellInfo(queued.spellId)))
            return;

        // Attempt to cast the queued spell
        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(queued.spellId);
        if (!spellInfo)
        {
            queued.spellId = 0;
            return;
        }

        Unit* target = nullptr;
        if (queued.targetGuid)
            target = ObjectAccessor::GetUnit(*player, queued.targetGuid);

        if (!target)
            target = player->GetVictim();

        if (!target && !spellInfo->HasAttribute(SPELL_ATTR0_IS_ABILITY))
        {
            queued.spellId = 0;
            return;
        }

        LOG_DEBUG("module", "mod-modernWoW SpellQueue: Firing queued spell {} for player {}",
            queued.spellId, player->GetName());

        player->CastSpell(target ? target : player, queued.spellId, false);
        queued.spellId = 0;
    }

    // Called when player casts a spell — if they're in GCD, queue it
    void OnPlayerSpellCast(Player* player, Spell* spell, bool skipCheck) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->SpellQueueEnabled)
            return;

        if (!player || !spell || skipCheck)
            return;

        SpellInfo const* spellInfo = spell->GetSpellInfo();
        if (!spellInfo)
            return;

        // Only queue instant casts (channeled / long-cast are handled by the client)
        if (spellInfo->CalcCastTime() > 0)
            return;

        // Check if we're still on GCD
        if (!player->GetGlobalCooldownMgr().HasGlobalCooldown(player, spellInfo))
            return;

        // Queue the spell
        QueuedSpell queued;
        queued.spellId    = spellInfo->Id;
        queued.targetGuid = spell->m_targets.GetUnitTargetGUID();
        queued.queuedAtMs = getMSTime();

        gSpellQueue[player->GetGUID().GetCounter()] = queued;

        LOG_DEBUG("module", "mod-modernWoW SpellQueue: Queued spell {} for player {} (GCD active)",
            spellInfo->Id, player->GetName());
    }

    void OnPlayerLogout(Player* player) override
    {
        gSpellQueue.erase(player->GetGUID().GetCounter());
    }
};

void AddModernWoW_SpellQueueScripts()
{
    if (sModernWoWConfig->SpellQueueEnabled)
        new ModernWoW_SpellQueueScript();
}
