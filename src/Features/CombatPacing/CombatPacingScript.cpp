/*
 * mod-modernWoW — Combat Pacing (Retail-like combat speed)
 * Copyright (C) 2024
 *
 * ============================================================================
 * DESIGN PHILOSOPHY — Shadowlands vs WotLK combat speed
 * ============================================================================
 *
 * The retail WoW (Shadowlands+) combat feel differs from WotLK 3.3.5 in
 * several measurable ways:
 *
 *   SPELL CAST TIMES (base, no talents):
 *     Frostbolt:  WotLK 3.0s  →  Shadowlands 2.0s  (-33%)
 *     Fireball:   WotLK 3.5s  →  Shadowlands 2.25s  (-36%)
 *
 *   HASTE FORMULA (WotLK lvl 80):
 *     32.79 Haste Rating = 1% Haste
 *     New cast time = Base cast time / (1 + Haste%)
 *     New swing time = Base weapon speed / (1 + Haste%)
 *
 *   GCD:
 *     WotLK:       1.5s base, minimum 1.0s (hard client-side cap)
 *     Shadowlands: 1.5s base, minimum 0.75s
 *     → We CANNOT go below 1.0s GCD without a core patch.
 *       The haste bonus will push GCD to 1.0s (WotLK cap).
 *
 * ============================================================================
 * WHAT THIS SCRIPT DOES
 * ============================================================================
 *
 *   1. HASTE RATING INJECTION (login/logout hook)
 *      Injects a flat haste rating bonus to all players via ApplyRatingMod().
 *      Affects: spell cast times, melee swing speed, ranged attack speed, GCD.
 *
 *      Default: 800 rating ≈ +24% haste at lvl 80
 *        → Frostbolt: 3.0s → 2.42s  (or 2.5s talent version → 2.02s)
 *        → 2.6s weapon: 2.6s → 2.10s swing
 *        → GCD: 1.5s → 1.21s (well on the way to 1.0s cap)
 *
 *      Combined with gear haste (~400–600 on typical WotLK gear), total
 *      effective haste can reach 35–45%, giving a very retail-like feel.
 *
 *   2. EXTRA MELEE ATTACK SPEED (login/logout hook)
 *      Applies an additional % speed modifier via ApplyAttackTimePercentMod()
 *      on top of the haste bonus, targeting melee's "swing feel".
 *
 *      Default: 20% extra speed
 *        → 2.6s weapon becomes: 2.6s / 1.20 = 2.17s (then haste on top)
 *        → Combined with 24% haste: 2.17s / 1.24 ≈ 1.75s final swing
 *
 *   3. OUT-OF-COMBAT REGEN BOOST (world config override)
 *      Boosts the natural HP and mana regen rates so players recover quickly
 *      between fights, matching the retail experience of full HP in seconds.
 *      Uses OnAfterConfigLoad to override CONFIG_RATE_HEALTH and
 *      CONFIG_RATE_POWER_MANA, following the same pattern as InstantMail.
 *
 * ============================================================================
 * LIMITATIONS
 * ============================================================================
 * - GCD minimum is 1.0s in WotLK client (cannot be reduced by a module alone)
 * - Cast time reduction cannot make a spell faster than server tick rate
 * - Haste injected via ApplyRatingMod is stat-based, so it appears on the
 *   character sheet as bonus haste rating (no fake buff bar entry needed)
 */

#include "CombatPacingScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Player.h"
#include "Chat.h"
#include "World.h"
#include "Log.h"
#include <unordered_set>

// ---------------------------------------------------------------------------
// Track which players have had combat pacing applied so we can safely
// remove it on logout without double-removal.
// ---------------------------------------------------------------------------
static std::unordered_set<ObjectGuid::LowType> gPacingApplied;

// ---------------------------------------------------------------------------
// Apply or remove all combat pacing modifiers for a player.
// ---------------------------------------------------------------------------
static void ApplyCombatPacing(Player* player, bool apply)
{
    if (!player)
        return;

    ObjectGuid::LowType guid = player->GetGUID().GetCounter();

    // Guard: don't apply twice, don't remove if not applied
    if (apply && gPacingApplied.count(guid))
        return;
    if (!apply && !gPacingApplied.count(guid))
        return;

    if (apply)
        gPacingApplied.insert(guid);
    else
        gPacingApplied.erase(guid);

    // -----------------------------------------------------------------------
    // 1. Haste Rating Injection — affects GCD, cast speed, melee & ranged swing
    //
    //    At lvl 80: 32.79 rating = 1% haste
    //    800 rating ≈ +24.4% haste
    //
    //    ApplyRatingMod() feeds into the existing WotLK haste system, so
    //    the engine automatically recalculates all dependent stats (cast
    //    speed, swing timer, GCD) whenever stats are updated.
    // -----------------------------------------------------------------------
    int32 hasteRating = sModernWoWConfig->CombatPacingHasteRating;
    if (hasteRating > 0)
    {
        player->ApplyRatingMod(CR_HASTE_MELEE,   hasteRating, apply);
        player->ApplyRatingMod(CR_HASTE_SPELL,   hasteRating, apply);
        player->ApplyRatingMod(CR_HASTE_RANGED,  hasteRating, apply);

        LOG_DEBUG("module.combatpacing",
            "CombatPacing: {} haste rating {} for player {}",
            apply ? "Applied" : "Removed", hasteRating, player->GetName());
    }

    // -----------------------------------------------------------------------
    // 2. Extra Melee Attack Speed — direct % modifier on swing timers
    //
    //    ApplyAttackTimePercentMod(type, pct, apply):
    //      pct > 0 with apply=true  → attack speed increases (swing time falls)
    //      pct > 0 with apply=false → reverses the speed increase
    //
    //    Example with MeleeSpeedPct = 20.0f:
    //      2.6s weapon + 24% haste → 2.10s
    //      + 20% extra speed       → 2.10s / 1.20 ≈ 1.75s final swing time
    // -----------------------------------------------------------------------
    float meleeSpeedPct = sModernWoWConfig->CombatPacingMeleeSpeedPct;
    if (meleeSpeedPct > 0.0f)
    {
        player->ApplyAttackTimePercentMod(BASE_ATTACK,   meleeSpeedPct, apply);
        player->ApplyAttackTimePercentMod(OFF_ATTACK,    meleeSpeedPct, apply);
        player->ApplyAttackTimePercentMod(RANGED_ATTACK, meleeSpeedPct, apply);

        LOG_DEBUG("module.combatpacing",
            "CombatPacing: {} {:.1f}% melee speed modifier for player {}",
            apply ? "Applied" : "Removed", meleeSpeedPct, player->GetName());
    }
}

// ---------------------------------------------------------------------------
// PlayerScript — Apply/remove combat pacing on login and logout
// ---------------------------------------------------------------------------
class ModernWoW_CombatPacingPlayerScript : public PlayerScript
{
public:
    ModernWoW_CombatPacingPlayerScript() : PlayerScript("ModernWoW_CombatPacingPlayerScript") {}

    void OnPlayerLogin(Player* player) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->CombatPacingEnabled)
            return;

        ApplyCombatPacing(player, true);

        // Notify player if announce is on
        if (sModernWoWConfig->Announce)
        {
            ChatHandler(player->GetSession()).PSendSysMessage(
                "|cff00FFFF[mod-modernWoW]|r Combat Pacing active: "
                "|cffFFD700+%d|r Haste Rating, |cffFFD700+%.0f%%|r Melee Speed.",
                sModernWoWConfig->CombatPacingHasteRating,
                sModernWoWConfig->CombatPacingMeleeSpeedPct);
        }
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!player)
            return;

        // Always attempt removal regardless of config state (config may have
        // changed since login; we must clean up what was applied).
        ApplyCombatPacing(player, false);
    }
};

// ---------------------------------------------------------------------------
// WorldScript — Override OOC regen rates on config load
//
// Same pattern as the InstantMail and LowLevelQuest overrides in
// GuildPerksScript.cpp: override world configs in OnAfterConfigLoad so
// the values persist through reloads.
//
// CONFIG_RATE_HEALTH:      multiplier for natural HP regeneration
// CONFIG_RATE_POWER_MANA:  multiplier for natural mana regeneration
//
// Retail WoW feel: full HP in ~5 seconds out of combat.
// Default multipliers: 5× HP regen, 3× mana regen.
// (Players with more HP scale better from the 5× than those with little HP.)
// ---------------------------------------------------------------------------
class ModernWoW_CombatPacingWorldScript : public WorldScript
{
public:
    ModernWoW_CombatPacingWorldScript() : WorldScript("ModernWoW_CombatPacingWorldScript") {}

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->CombatPacingEnabled)
            return;

        float healthMult = sModernWoWConfig->CombatPacingOOCHealthMult;
        float manaMult   = sModernWoWConfig->CombatPacingOOCManaMult;

        if (healthMult > 0.0f)
        {
            sWorld->setFloatConfig(CONFIG_RATE_HEALTH, healthMult);
            LOG_DEBUG("module.combatpacing",
                "CombatPacing: HP regen rate set to {:.1f}x", healthMult);
        }

        if (manaMult > 0.0f)
        {
            sWorld->setFloatConfig(CONFIG_RATE_POWER_MANA, manaMult);
            LOG_DEBUG("module.combatpacing",
                "CombatPacing: Mana regen rate set to {:.1f}x", manaMult);
        }
    }
};

// ---------------------------------------------------------------------------
// Script Registration
// ---------------------------------------------------------------------------
void AddModernWoW_CombatPacingScripts()
{
    if (!sModernWoWConfig->CombatPacingEnabled)
        return;

    new ModernWoW_CombatPacingPlayerScript();
    new ModernWoW_CombatPacingWorldScript();
}
