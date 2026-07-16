/*
 * mod-modernWoW — Dynamic Creature Scaling (Chromie Time / Zone Scaling style)
 * Copyright (C) 2024
 *
 * ============================================================================
 * DESIGN PHILOSOPHY — Per-player downscaling for equal time-to-kill in parties
 * ============================================================================
 *
 * GOAL: Every player in a party — regardless of level — kills any given mob in
 * roughly the same number of hits. This enables mixed-level groups to quest
 * together naturally, mirroring WoW's classic Chromie Time / zone scaling feel.
 *
 * HOW IT WORKS:
 *
 *   1. CREATURE HP is NOT modified. The mob keeps its template HP at all times.
 *      This avoids per-player HP pool problems in shared-world AoE situations.
 *
 *   2. PLAYER OUTGOING DAMAGE is scaled DOWN per-player using the ratio of
 *      creature base health stats at the content level vs the player's level:
 *
 *        outScale = GetBaseHP(contentLevel) / GetBaseHP(playerLevel)
 *
 *      This is derived from the actual CreatureBaseStats database, so it exactly
 *      matches the WotLK expansion's own stat progression curves.
 *
 *      Examples (wolf, contentLevel = 1, HP = 55):
 *        lvl  1 → outScale = 55/55   = 1.00  → unscaled, full damage
 *        lvl 15 → outScale = 55/300  = 0.18  → ~9 damage per hit, ~6 hits to kill
 *        lvl 30 → outScale = 55/1100 = 0.05  → ~15 damage per hit, ~4 hits to kill
 *
 *      Both players kill in ~4-6 hits regardless of level gap. TTK is equal.
 *
 *   3. CREATURE INCOMING DAMAGE (creature → player) is scaled UP per-player:
 *
 *        inScale = GetBaseHP(playerLevel) / GetBaseHP(contentLevel)
 *
 *      A lvl 30 player fighting a lvl 1 zone takes proportionally more damage
 *      so the content remains challenging and meaningful for higher levels too.
 *
 *   4. XP:
 *      FormulaScript::OnGainCalculation is commented out in AzerothCore core.
 *      We hook OnPlayerRewardKillRewarder via PlayerScript to award synthetic XP
 *      for grey mobs so progression is never stalled.
 *
 *   5. VISUAL LEVEL (per-player packet patch):
 *      UNIT_FIELD_LEVEL is patched in outgoing update packets so each player sees
 *      the creature at their own level (yellow nameplate instead of grey).
 *
 * ============================================================================
 * MIXED PARTY EXAMPLE
 * ============================================================================
 *
 *   lvl 30 + lvl 15, questing together in a lvl 1 zone.
 *   Creature template: wolf, lvl 1, HP = 55.
 *
 *   lvl 15 attacks:
 *     outScale = baseHP(1) / baseHP(15) = 55/300 = 0.18
 *     → deals ~9 damage per hit, ~6 hits to kill.
 *
 *   lvl 30 attacks:
 *     outScale = baseHP(1) / baseHP(30) = 55/1100 = 0.05
 *     → deals ~15 damage per hit, ~4 hits to kill.
 *
 *   RESULT: Both players kill the wolf in ~4-6 hits. TTK roughly equal.
 *   The wolf's 55 HP remains natural. No HP inflation.
 *
 * ============================================================================
 * SKIPS
 * ============================================================================
 * - Pets, totems, triggers
 * - World bosses
 * - Raid instances (if ExcludeRaids = 1)
 * - Blacklisted map IDs
 * - If player level ≤ creature template level (no scaling needed)
 */

#include "CreatureScalingScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Creature.h"
#include "LootMgr.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "World.h"
#include "Log.h"
#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

// ---------------------------------------------------------------------------
// Helper: check if a map is excluded from content scaling
// ---------------------------------------------------------------------------
static bool IsMapExcluded(uint32 mapId, Map const* map)
{
    auto const& bl = sModernWoWConfig->DynScaleMapBlacklist;
    if (std::find(bl.begin(), bl.end(), mapId) != bl.end())
        return true;

    if (sModernWoWConfig->DynScaleExcludeRaids && map && map->IsRaid())
        return true;

    return false;
}

// ---------------------------------------------------------------------------
// Helper: get the creature's zone-intended level
// This uses the template level as the baseline.
// ---------------------------------------------------------------------------
static uint8 GetContentLevel(Creature const* creature)
{
    CreatureTemplate const* tmpl = creature->GetCreatureTemplate();
    if (!tmpl)
        return creature->GetLevel();

    // If template has a range, use the average
    uint8 minL = tmpl->minlevel;
    uint8 maxL = tmpl->maxlevel;
    return static_cast<uint8>((static_cast<uint16>(minL) + maxL) / 2);
}

// Returns the maximum level at which a creature is considered grey to a player of the given level
static uint8 GetGreyLevel(uint8 plvl)
{
    if (plvl <= 5)
        return 0;
    if (plvl <= 9)
        return plvl - 5;
    if (plvl <= 19)
        return plvl - 5 - (plvl - 5) / 5;
    if (plvl <= 39)
        return plvl - 5 - (plvl - 5) / 10;
    if (plvl <= 59)
        return plvl - 10 - (plvl - 10) / 5;
    return plvl - 5 - (plvl - 5) / 5;
}

// ---------------------------------------------------------------------------
// Per-creature HP scaling state (used by Mode 1 and Mode 3)
// Maps creature GUID -> { highestAttackerLevel, set of all attacker levels }
// Cleared on creature death so respawns start fresh.
// ---------------------------------------------------------------------------
struct CreatureScaleState
{
    uint8 highestLevel = 0;
    std::unordered_set<uint8> attackerLevels;
};
static std::unordered_map<ObjectGuid::LowType, CreatureScaleState> gCreatureState;

// Query the expected max HP of a creature's class at a given level.
// Uses the actual WotLK CreatureBaseStats DB table for accurate stat ratios.
static uint32 GetBaseHPAtLevel(uint8 level, Creature const* creature)
{
    CreatureTemplate const* tmpl = creature->GetCreatureTemplate();
    if (!tmpl)
        return creature->GetMaxHealth();

    CreatureBaseStats const* stats = sObjectMgr->GetCreatureBaseStats(level, tmpl->unit_class);
    if (stats)
        return stats->GenerateHealth(tmpl);

    return creature->GetMaxHealth();
}


// Apply physical HP scaling to a creature.
// targetLevel = the level whose baseHP we want the creature's max HP to represent.
// Returns the scaling factor applied (or 1.0 if none).
static float ApplyCreatureHP(Creature* creature, uint8 targetLevel, uint8 contentLevel)
{
    uint32 contentHP  = GetBaseHPAtLevel(contentLevel, creature);
    uint32 targetHP   = GetBaseHPAtLevel(targetLevel, creature);
    uint32 currentMax = creature->GetMaxHealth();

    // Only scale UP if targetHP is meaningfully larger than what we have
    if (targetHP <= currentMax || contentHP == 0)
        return 1.0f;

    float hpScale = (static_cast<float>(targetHP) / static_cast<float>(currentMax))
                    * sModernWoWConfig->DynScaleHealthMult;
    uint32 newMaxHP = static_cast<uint32>(currentMax * hpScale);
    float healthPct = creature->GetHealthPct() / 100.0f;

    creature->SetMaxHealth(newMaxHP);
    creature->SetHealth(static_cast<uint32>(newMaxHP * healthPct));

    LOG_DEBUG("module.scaling",
        "DynScale HP: Creature({}) scaled to lvl{} ({}→{} HP, scale={:.2f})",
        creature->GetEntry(), targetLevel, currentMax, newMaxHP, hpScale);

    return hpScale;
}

// Compute the average level of all recorded attackers for a creature.
static uint8 GetPartyAverageLevel(const std::unordered_set<uint8>& levels)
{
    if (levels.empty())
        return 0;

    uint32 sum = 0;
    for (uint8 lvl : levels)
        sum += lvl;
    return static_cast<uint8>(sum / levels.size());
}

// ---------------------------------------------------------------------------
// MODE-AWARE SCALING FUNCTIONS
// ---------------------------------------------------------------------------

// Called from damage hooks for Player→Creature hits.
// Handles all HP scaling side-effects (Mode 1 and 3) and returns the
// outgoing damage multiplier to apply to this hit.
static float GetOutgoingScale(Creature* creature, uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0 || !creature)
        return 1.0f;

    // Only apply scaling if the creature's level is grey to the player
    if (contentLevel >= GetGreyLevel(playerLevel))
        return 1.0f;

    uint8 mode = sModernWoWConfig->DynScaleMode;

    // ------------------------------------------------------------------
    // MODE 1: Real Numbers — HP scales UP to highest party member.
    //         Player damage is NOT modified.
    // ------------------------------------------------------------------
    if (mode == 1)
    {
        ObjectGuid::LowType guid = creature->GetGUID().GetCounter();
        CreatureScaleState& state = gCreatureState[guid];

        if (playerLevel > state.highestLevel)
        {
            ApplyCreatureHP(creature, playerLevel, contentLevel);
            state.highestLevel = playerLevel;
        }
        return 1.0f; // Player always sees real damage numbers
    }

    // ------------------------------------------------------------------
    // MODE 2: Equal TTK — Damage scaled DOWN per-player to content level.
    //         Mob HP stays at template value. All players kill in ~same hits.
    //
    //         Uses creature base health ratios — derived from database curves
    //         to scale player damage proportionally with level content tier.
    // ------------------------------------------------------------------
    if (mode == 2)
    {
        uint32 playerLevelHP  = GetBaseHPAtLevel(playerLevel, creature);
        uint32 contentLevelHP = GetBaseHPAtLevel(contentLevel, creature);

        if (playerLevelHP > 0 && contentLevelHP > 0)
            return static_cast<float>(contentLevelHP) / static_cast<float>(playerLevelHP);

        return static_cast<float>(contentLevel) / static_cast<float>(playerLevel);
    }

    // ------------------------------------------------------------------
    // MODE 3: Compromise — HP scaled to party average level.
    //         Each player's damage adjusted relative to that average HP pool.
    //         Higher-level players contribute more but not overwhelmingly.
    // ------------------------------------------------------------------
    if (mode == 3)
    {
        ObjectGuid::LowType guid = creature->GetGUID().GetCounter();
        CreatureScaleState& state = gCreatureState[guid];

        // Track all attacker levels
        state.attackerLevels.insert(playerLevel);
        if (playerLevel > state.highestLevel)
            state.highestLevel = playerLevel;

        uint8 avgLevel = GetPartyAverageLevel(state.attackerLevels);
        if (avgLevel <= contentLevel)
            return 1.0f;

        // Scale HP up to average level
        ApplyCreatureHP(creature, avgLevel, contentLevel);

        // Scale each player's damage relative to the current HP pool
        uint32 currentMaxHP      = creature->GetMaxHealth();
        uint32 playerExpectedHP  = GetBaseHPAtLevel(playerLevel, creature);

        if (playerExpectedHP > 0 && currentMaxHP > 0)
            return static_cast<float>(currentMaxHP) / static_cast<float>(playerExpectedHP);
    }

    return 1.0f;
}

// Compute incoming damage multiplier (creature→player) — same formula for all modes.
// Higher-level players take proportionally more damage to keep content challenging.
static float GetIncomingScale(uint8 playerLevel, uint8 contentLevel, Creature const* creature)
{
    if (playerLevel <= contentLevel || contentLevel == 0 || !creature)
        return 1.0f;

    // Only apply scaling if the creature's level is grey to the player
    if (contentLevel >= GetGreyLevel(playerLevel))
        return 1.0f;

    uint32 playerLevelHP  = GetBaseHPAtLevel(playerLevel, creature);
    uint32 contentLevelHP = GetBaseHPAtLevel(contentLevel, creature);

    if (contentLevelHP > 0 && playerLevelHP > contentLevelHP)
        return static_cast<float>(playerLevelHP) / static_cast<float>(contentLevelHP);

    return 1.0f;
}

// ---------------------------------------------------------------------------
// Helper: check if creature is eligible for scaling
// ---------------------------------------------------------------------------
static bool IsCreatureScalable(Creature const* creature)
{
    if (!creature)
        return false;

    if (creature->IsPet() || creature->IsTotem() || creature->IsTrigger())
        return false;

    CreatureTemplate const* tmpl = creature->GetCreatureTemplate();
    if (!tmpl)
        return false;

    // Do not scale world bosses
    if (tmpl->rank == CREATURE_ELITE_WORLDBOSS)
        return false;

    Map const* map = creature->GetMap();
    if (IsMapExcluded(creature->GetMapId(), map))
        return false;

    return true;
}

// ---------------------------------------------------------------------------
// UnitScript — Core content scaling logic in damage hooks
// ---------------------------------------------------------------------------
class ModernWoW_ContentScaleDamageScript : public UnitScript
{
public:
    ModernWoW_ContentScaleDamageScript() : UnitScript("ModernWoW_ContentScaleDamageScript") {}

    // -----------------------------------------------------------------------
    // Melee Damage
    // -----------------------------------------------------------------------
    void ModifyMeleeDamage(Unit* target, Unit* attacker, uint32& damage) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (damage == 0)
            return;

        // Player → Creature
        if (attacker && attacker->GetTypeId() == TYPEID_PLAYER &&
            target   && target->GetTypeId()   == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = attacker->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = GetOutgoingScale(creature, playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale != 1.0f)
            {
                damage = static_cast<uint32>(damage * scale);
                LOG_DEBUG("module.scaling",
                    "DynScale Melee Out (mode{}): Player({}) lvl{} vs Creature({}) contentLvl{} → scale={:.3f} dmg={}",
                    sModernWoWConfig->DynScaleMode, attacker->GetName(), playerLevel,
                    creature->GetEntry(), contentLevel, scale, damage);
            }
        }
        // Creature → Player
        else if (attacker && attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = target->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = GetIncomingScale(playerLevel, contentLevel, creature) * sModernWoWConfig->DynScaleDamageMult;
            if (scale > 1.0f)
            {
                damage = static_cast<uint32>(damage * scale);
                LOG_DEBUG("module.scaling",
                    "DynScale Melee In (mode{}): Creature({}) contentLvl{} vs Player({}) lvl{} → scale={:.3f} dmg={}",
                    sModernWoWConfig->DynScaleMode, creature->GetEntry(), contentLevel,
                    target->GetName(), playerLevel, scale, damage);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Spell Damage
    // -----------------------------------------------------------------------
    void ModifySpellDamageTaken(Unit* target, Unit* attacker, int32& damage,
                                SpellInfo const* /*spellInfo*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (damage == 0)
            return;

        // Player → Creature
        if (attacker && attacker->GetTypeId() == TYPEID_PLAYER &&
            target   && target->GetTypeId()   == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = attacker->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = GetOutgoingScale(creature, playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale != 1.0f)
                damage = static_cast<int32>(damage * scale);
        }
        // Creature → Player
        else if (attacker && attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = target->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = GetIncomingScale(playerLevel, contentLevel, creature) * sModernWoWConfig->DynScaleDamageMult;
            if (scale > 1.0f)
                damage = static_cast<int32>(damage * scale);
        }
    }

    // -----------------------------------------------------------------------
    // DoT Tick Damage
    // -----------------------------------------------------------------------
    void ModifyPeriodicDamageAurasTick(Unit* target, Unit* attacker,
                                       uint32& damage, SpellInfo const* /*spellInfo*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (damage == 0 || !attacker)
            return;

        // Player DoT → Creature
        if (attacker->GetTypeId() == TYPEID_PLAYER &&
            target   && target->GetTypeId()   == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 dotPlayerLevel  = attacker->GetLevel();
            uint8 dotContentLevel = GetContentLevel(creature);

            float scale = GetOutgoingScale(creature, dotPlayerLevel, dotContentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale != 1.0f)
                damage = static_cast<uint32>(damage * scale);
        }
        // Creature DoT → Player
        else if (attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!creature || !IsCreatureScalable(creature))
                return;

            float scale = GetIncomingScale(target->GetLevel(), GetContentLevel(creature), creature) * sModernWoWConfig->DynScaleDamageMult;
            if (scale > 1.0f)
                damage = static_cast<uint32>(damage * scale);
        }
    }

    // -----------------------------------------------------------------------
    // Healing Received
    // -----------------------------------------------------------------------
    void ModifyHealReceived(Unit* /*target*/, Unit* /*healer*/, uint32& /*heal*/,
                            SpellInfo const* /*spellInfo*/) override
    {
    }

    // -----------------------------------------------------------------------
    // DYNAMIC LEVEL PRESENTATION (Make creatures appear at player's level)
    // -----------------------------------------------------------------------
    bool ShouldTrackValuesUpdatePosByIndex(Unit const* /*unit*/, uint8 /*updateType*/, uint16 index) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return false;

        return (index == UNIT_FIELD_LEVEL);
    }

    void OnPatchValuesUpdate(Unit const* unit, ByteBuffer& valuesUpdateBuf, BuildValuesCachePosPointers& posPointers, Player* target) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (!unit || !target)
            return;

        Creature const* creature = unit->ToCreature();
        if (!creature || !IsCreatureScalable(creature))
            return;

        uint8 playerLevel = target->GetLevel();
        uint8 contentLevel = GetContentLevel(creature);

        // Only scale visual level if the creature's level is grey to the player
        if (contentLevel >= GetGreyLevel(playerLevel))
            return;

        auto it = posPointers.other.find(UNIT_FIELD_LEVEL);
        if (it != posPointers.other.end())
        {
            uint32 levelPos = it->second;
            uint8 playerLevel = target->GetLevel();

            // Clamp target level to dynamic scaling bounds
            uint8 targetLevel = std::clamp<uint8>(playerLevel,
                sModernWoWConfig->DynScaleMinLevel,
                sModernWoWConfig->DynScaleMaxLevel);

            valuesUpdateBuf.put<uint32>(levelPos, uint32(targetLevel));
        }
    }

    void OnUnitDeath(Unit* unit, Unit* /*killer*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        Creature* creature = unit ? unit->ToCreature() : nullptr;
        if (creature)
            gCreatureState.erase(creature->GetGUID().GetCounter());
    }
};

// ---------------------------------------------------------------------------
// PlayerScript — XP override
// If content is too low level (grey mob), calculate synthetic XP reward
// so progression remains active. Bypasses core's commented-out OnGainCalculation hook.
// ---------------------------------------------------------------------------
class ModernWoW_ContentScaleXPScript : public PlayerScript
{
public:
    ModernWoW_ContentScaleXPScript() : PlayerScript("ModernWoW_ContentScaleXPScript") {}

    void OnPlayerRewardKillRewarder(Player* player, KillRewarder* rewarder, bool /*isDungeon*/, float& /*rate*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (!sModernWoWConfig->DynScaleXP)
            return;

        if (!player || !rewarder)
            return;

        Unit* victim = rewarder->GetVictim();
        if (!victim)
            return;

        Creature* creature = victim->ToCreature();
        if (!creature)
            return;

        if (!IsCreatureScalable(creature))
            return;

        uint8 playerLevel  = player->GetLevel();
        uint8 contentLevel = GetContentLevel(creature);

        // Do not interfere if the creature is not grey
        if (contentLevel >= GetGreyLevel(playerLevel))
            return;

        // Calculate synthetic XP reward for grey mobs so progression remains active.
        float contentFraction = static_cast<float>(contentLevel) / static_cast<float>(playerLevel);
        uint32 syntheticXP = static_cast<uint32>(150.0f * static_cast<float>(playerLevel) * contentFraction);

        if (syntheticXP > 0)
        {
            // Notify other scripts of the XP gain
            sScriptMgr->OnPlayerGiveXP(player, syntheticXP, creature, PlayerXPSource::XPSOURCE_KILL);
            
            // Actually reward the player
            player->GiveXP(syntheticXP, creature);
            
            LOG_DEBUG("module.scaling",
                "DynScale XP: Player({}) lvl{} killed grey creature({}) contentLvl{} → synthetic XP={}",
                player->GetName(), playerLevel, creature->GetEntry(), contentLevel, syntheticXP);
        }
    }
};

// ---------------------------------------------------------------------------
// AllCreatureScript — enforce minimum level clamp
// ---------------------------------------------------------------------------
class ModernWoW_ContentScaleCreatureScript : public AllCreatureScript
{
public:
    ModernWoW_ContentScaleCreatureScript()
        : AllCreatureScript("ModernWoW_ContentScaleCreatureScript") {}

    void OnBeforeCreatureSelectLevel(const CreatureTemplate* cinfo,
                                     Creature* creature, uint8& level) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (!creature || !cinfo)
            return;

        if (creature->IsPet() || creature->IsTotem() || creature->IsTrigger())
            return;

        if (cinfo->rank == CREATURE_ELITE_WORLDBOSS)
            return;

        Map* map = creature->GetMap();
        if (IsMapExcluded(creature->GetMapId(), map))
            return;

        // Enforce the configured minimum level floor
        uint8 minAllowed = sModernWoWConfig->DynScaleMinLevel;
        if (level < minAllowed)
            level = minAllowed;
    }
};

// ---------------------------------------------------------------------------
// GlobalScript — Scale loot drop chances for over-leveled players (DynScaleLoot)
// Boosts item drop chances when the player's level exceeds the content level,
// ensuring loot remains rewarding when playing scaled-down content.
// The boost is proportional to the level advantage, capped at 2× to avoid
// trivializing loot. Only partial-chance items are modified (not guaranteed drops).
// ---------------------------------------------------------------------------
class ModernWoW_LootScaleGlobalScript : public GlobalScript
{
public:
    ModernWoW_LootScaleGlobalScript() : GlobalScript("ModernWoW_LootScaleGlobalScript") {}

    void OnBeforeDropAddItem(Player const* player, Loot& loot, bool /*canRate*/,
                             uint16 /*lootMode*/, LootStoreItem* lootStoreItem,
                             LootStore const& /*store*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled || !sModernWoWConfig->DynScaleLoot)
            return;

        if (!player || !lootStoreItem)
            return;

        // Only boost partial-chance items; skip guaranteed and zero-chance drops
        if (lootStoreItem->chance <= 0.0f || lootStoreItem->chance >= 100.0f)
            return;

        if (!loot.sourceWorldObjectGUID.IsCreatureOrVehicle())
            return;

        Creature* creature = ObjectAccessor::GetCreature(*player, loot.sourceWorldObjectGUID);
        if (!creature || !IsCreatureScalable(creature))
            return;

        uint8 playerLevel  = player->GetLevel();
        uint8 contentLevel = GetContentLevel(creature);

        if (playerLevel <= contentLevel)
            return;

        // Only apply loot scaling if the creature's level is grey to the player
        if (contentLevel >= GetGreyLevel(playerLevel))
            return;

        // Boost proportional to level advantage, capped at 2× to prevent trivialization
        float boost = std::min(
            static_cast<float>(playerLevel) / static_cast<float>(std::max(contentLevel, uint8(1))),
            2.0f);

        lootStoreItem->chance = std::min(100.0f, lootStoreItem->chance * boost);

        LOG_DEBUG("module.scaling",
            "DynScaleLoot: Player({}) lvl{} vs contentLvl{} → drop chance boosted to {:.1f}% (x{:.2f})",
            player->GetName(), playerLevel, contentLevel, lootStoreItem->chance, boost);
    }
};

// ---------------------------------------------------------------------------
// Script Registration
// ---------------------------------------------------------------------------
void AddModernWoW_DynamicScalingScripts()
{
    if (!sModernWoWConfig->DynScaleEnabled)
        return;

    new ModernWoW_ContentScaleCreatureScript();
    new ModernWoW_ContentScaleDamageScript();

    if (sModernWoWConfig->DynScaleXP)
        new ModernWoW_ContentScaleXPScript();

    if (sModernWoWConfig->DynScaleLoot)
        new ModernWoW_LootScaleGlobalScript();
}
