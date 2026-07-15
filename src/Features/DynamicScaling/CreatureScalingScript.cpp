/*
 * mod-modernWoW — Dynamic Creature Scaling (Chromie Time / Content Scaling)
 * Copyright (C) 2024
 *
 * ============================================================================
 * DESIGN PHILOSOPHY — why we DO NOT scale the creature's actual level in the world
 * ============================================================================
 *
 * The old approach (creature level = player level) is fundamentally broken
 * in mixed-level groups:
 *
 *   Example: lvl 60 + lvl 33 questing together in a lvl 15 zone.
 *   - If creature scales to 60: impossible for the lvl 33 player.
 *   - If creature scales to 33: the lvl 60 player one-shots it.
 *   - If creature stays at 15: both players trivialize the content.
 *
 * The CORRECT approach (Retail content scaling / Chromie Time):
 *
 *   The creature keeps its zone-intended template level (template level).
 *   Instead, we scale the damage of each player INDIVIDUALLY in both directions:
 *
 *   Player → Creature damage:
 *     scale = (creatureBaseLevel / playerLevel)^POWER_EXPONENT
 *     → higher-level player deals less damage (as if downscaled to the zone level)
 *
 *   Creature → Player damage:
 *     scale = (playerLevel / creatureBaseLevel)^POWER_EXPONENT
 *     → higher-level player takes more damage (proportionally to their health pool)
 *
 *   XP:
 *     The standard engine would award 0 XP for a grey mob. We override this
 *     to calculate a synthetic XP reward so progression remains active.
 *
 *   Dynamic Level Presentation (Visual level override):
 *     We patch the UNIT_FIELD_LEVEL value in serialized update packets so that
 *     each player sees the creature at their own level. This keeps target frames
 *     and nameplates yellow (matching the player's level) instead of grey.
 *
 * MIXED PARTY RESULT:
 *   - lvl 60 + lvl 33, creature lvl 15:
 *     - The lvl 60 player deals and takes damage as if they were lvl 15.
 *     - The lvl 33 player deals and takes damage as if they were lvl 15.
 *     - Both players experience the SAME relative challenge.
 *     - Both players receive appropriate XP rewards.
 *
 * ============================================================================
 * DAMAGE SCALING FORMULA
 * ============================================================================
 *
 * POWER_EXPONENT = 1.5 (tunable via config)
 *
 * Player → Creature:
 *   playerLevel > contentLevel → outScale = (contentLevel/playerLevel)^1.5
 *   playerLevel ≤ contentLevel → outScale = 1.0 (do not buff lower-level players)
 *
 * Creature → Player:
 *   playerLevel > contentLevel → inScale = (playerLevel/contentLevel)^1.5
 *   playerLevel ≤ contentLevel → inScale = 1.0
 *
 * contentLevel = the creature template's minlevel (zone-intended level)
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
#include "Map.h"
#include "Player.h"
#include "SpellInfo.h"
#include "Log.h"
#include <algorithm>
#include <cmath>
#include <unordered_set>

// ---------------------------------------------------------------------------
// Tuning constant: damage scaling exponent.
// 1.5 matches the approximate feel of retail scaling.
// Lower value  → looser scaling (high-level players have an advantage)
// Higher value → stricter scaling (forces closer parity to zone intended stats)
// ---------------------------------------------------------------------------
static constexpr float SCALE_EXPONENT = 1.5f;

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

// ---------------------------------------------------------------------------
// Helper: calculate outgoing damage scale factor (player -> creature)
// ---------------------------------------------------------------------------
static float CalcOutgoingScale(uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0)
        return 1.0f;

    float ratio = static_cast<float>(contentLevel) / static_cast<float>(playerLevel);
    return std::pow(ratio, SCALE_EXPONENT);
}

// ---------------------------------------------------------------------------
// Helper: calculate incoming damage scale factor (creature -> player)
// ---------------------------------------------------------------------------
static float CalcIncomingScale(uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0)
        return 1.0f;

    float ratio = static_cast<float>(playerLevel) / static_cast<float>(contentLevel);
    return std::pow(ratio, SCALE_EXPONENT);
}

// ---------------------------------------------------------------------------
// HP scaling state: tracks which creature GUIDs already had their HP scaled
// for the current life. Cleared on death so respawns start fresh.
// ---------------------------------------------------------------------------
static std::unordered_set<ObjectGuid::LowType> gScaledCreatures;

// Scale creature max HP on the first damaging hit from a higher-level player.
// Uses the same power-law formula as the damage scaler so HP and damage are
// in balance: the fight duration feels the same regardless of player level.
static void ScaleCreatureHP(Creature* creature, uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0)
        return;

    ObjectGuid::LowType guid = creature->GetGUID().GetCounter();
    if (gScaledCreatures.count(guid))
        return; // Already scaled for this life

    gScaledCreatures.insert(guid);

    float hpScale = std::pow(
        static_cast<float>(playerLevel) / static_cast<float>(contentLevel),
        SCALE_EXPONENT
    ) * sModernWoWConfig->DynScaleHealthMult;

    // Safety clamp — avoid absurd HP values at extreme level gaps
    hpScale = std::clamp(hpScale, 1.0f, 50.0f);

    uint32 baseMaxHP  = creature->GetMaxHealth();
    uint32 newMaxHP   = static_cast<uint32>(baseMaxHP * hpScale);
    float  currentPct = creature->GetHealthPct() / 100.0f;

    creature->SetMaxHealth(newMaxHP);
    creature->SetHealth(static_cast<uint32>(newMaxHP * currentPct));

    LOG_DEBUG("module.scaling",
        "DynScale HP: Creature({}) contentLvl{} vs Player lvl{} → scale={:.2f} baseHP={} newMaxHP={}",
        creature->GetEntry(), contentLevel, playerLevel, hpScale, baseMaxHP, newMaxHP);
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

            // Scale HP on first hit so the fight duration matches the damage reduction
            ScaleCreatureHP(creature, playerLevel, contentLevel);

            float scale = CalcOutgoingScale(playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale < 1.0f)
            {
                damage = static_cast<uint32>(damage * scale);
                LOG_DEBUG("module.scaling",
                    "DynScale Melee Out: Player({}) lvl{} vs Creature({}) contentLvl{} → scale={:.3f} dmg={}",
                    attacker->GetName(), playerLevel, creature->GetEntry(), contentLevel, scale, damage);
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

            float scale = CalcIncomingScale(playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale > 1.0f)
            {
                damage = static_cast<uint32>(damage * scale);
                LOG_DEBUG("module.scaling",
                    "DynScale Melee In: Creature({}) contentLvl{} vs Player({}) lvl{} → scale={:.3f} dmg={}",
                    creature->GetEntry(), contentLevel, target->GetName(), playerLevel, scale, damage);
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

            ScaleCreatureHP(creature, playerLevel, contentLevel);

            float scale = CalcOutgoingScale(playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale < 1.0f)
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

            float scale = CalcIncomingScale(playerLevel, contentLevel) * sModernWoWConfig->DynScaleDamageMult;
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

            ScaleCreatureHP(creature, dotPlayerLevel, dotContentLevel);

            float scale = CalcOutgoingScale(dotPlayerLevel, dotContentLevel) * sModernWoWConfig->DynScaleDamageMult;
            if (scale < 1.0f)
                damage = static_cast<uint32>(damage * scale);
        }
        // Creature DoT → Player
        else if (attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!creature || !IsCreatureScalable(creature))
                return;

            float scale = CalcIncomingScale(target->GetLevel(), GetContentLevel(creature)) * sModernWoWConfig->DynScaleDamageMult;
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
    // -----------------------------------------------------------------------
    // Cleanup: remove creature from gScaledCreatures on death and evade.
    //
    // Death:  engine resets HP to template on respawn — clear so the NEXT
    //         player to attack will rescale from the fresh template value.
    // Evade:  engine regenerates the creature back to its current max HP
    //         (which is already scaled), so we DO NOT clear on evade.
    //         The creature keeps its scaled HP while alive; only death resets it.
    // -----------------------------------------------------------------------
    void OnUnitDeath(Unit* unit, Unit* /*killer*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        Creature* creature = unit ? unit->ToCreature() : nullptr;
        if (creature)
            gScaledCreatures.erase(creature->GetGUID().GetCounter());
    }
};

// ---------------------------------------------------------------------------
// FormulaScript — XP override
// If content is too low level (grey mob), calculate synthetic XP reward
// so progression remains active.
// ---------------------------------------------------------------------------
class ModernWoW_ContentScaleXPScript : public FormulaScript
{
public:
    ModernWoW_ContentScaleXPScript() : FormulaScript("ModernWoW_ContentScaleXPScript") {}

    void OnGainCalculation(uint32& gain, Player* player, Unit* unit) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (!sModernWoWConfig->DynScaleXP)
            return;

        if (!player || !unit)
            return;

        Creature* creature = unit->ToCreature();
        if (!creature)
            return;

        if (!IsCreatureScalable(creature))
            return;

        uint8 playerLevel  = player->GetLevel();
        uint8 contentLevel = GetContentLevel(creature);

        // Do not interfere if the creature is not grey (e.g. within 8 levels)
        int32 greyThreshold = static_cast<int32>(playerLevel) - 8;
        if (static_cast<int32>(contentLevel) >= greyThreshold)
            return;

        // Force synthetic XP for grey mobs to preserve leveling flow
        if (gain == 0)
        {
            float contentFraction = static_cast<float>(contentLevel) / static_cast<float>(playerLevel);
            uint32 syntheticXP = static_cast<uint32>(150.0f * static_cast<float>(playerLevel) * contentFraction);
            gain = syntheticXP;

            LOG_DEBUG("module.scaling",
                "DynScale XP: Player({}) lvl{} killed grey creature({}) contentLvl{} → synthetic XP={}",
                player->GetName(), playerLevel, creature->GetEntry(), contentLevel, gain);
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
}
