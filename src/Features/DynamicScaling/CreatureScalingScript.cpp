/*
 * mod-modernWoW — Dynamic Creature Scaling (Chromie Time / Content Scaling)
 * Copyright (C) 2024
 *
 * ============================================================================
 * DESIGN PHILOSOPHY — miért NEM skálázzuk a creature szintjét?
 * ============================================================================
 *
 * Az eredeti megközelítés (creature szintje = player szintje) alapvetően hibás
 * vegyes szintű party esetén:
 *
 *   Példa: lvl60 + lvl33 bemennek egy lvl15-ös zónába questelni.
 *   - Ha creature-t 60-ra skálázzuk: a lvl33-as számára beteljesíthetetlen
 *   - Ha 33-ra skálázzuk: a lvl60-as mégis one-shot-olja
 *   - Ha 15-re hagyjuk: mindenki trivializálja
 *
 * A HELYES megközelítés (retail Chromie Time / War Within Content Scaling):
 *
 *   A creature MEGTARTJA a zóna eredeti szintjét (template szint).
 *   Ehelyett minden egyes játékos damage-ét KÜLÖN skálázzuk mindkét irányban:
 *
 *   Player → Creature damage:
 *     scale = (creatureBaseLevel / playerLevel)^POWER_EXPONENT
 *     → magasabb szintű játékos kevesebbet üt (mint ha azonos szintű lenne)
 *
 *   Creature → Player damage:
 *     scale = (playerLevel / creatureBaseLevel)^POWER_EXPONENT
 *     → magasabb szintű játékos nagyobb ütéseket kap (HP-arányosan)
 *
 *   XP:
 *     A standard motor nullát adna (grey mob). Felülírjuk, hogy a játékos
 *     szintjéhez arányos XP-t adjon a content completion érzéséhez.
 *
 * EREDMÉNY a vegyes party esetén:
 *   - lvl60 + lvl33, creature lvl15:
 *     - A lvl60 úgy üt és úgy kapja az ütéseket, mintha lvl15-ös lenne
 *     - A lvl33 úgy üt és úgy kapja az ütéseket, mintha lvl15-ös lenne
 *     - Mindenki UGYANOLYAN kihívást tapasztal, mint egy valódi lvl15-ös
 *     - Mindenki kap értelmes XP-t
 *
 * ============================================================================
 * DAMAGE SCALING FORMULA
 * ============================================================================
 *
 * POWER_EXPONENT = 1.5 (tunable via config)
 *
 * Player → Creature:
 *   playerLevel > contentLevel → outScale = (contentLevel/playerLevel)^1.5
 *   playerLevel ≤ contentLevel → outScale = 1.0 (ne buffoljuk az alacsony szintűt)
 *
 * Creature → Player:
 *   playerLevel > contentLevel → inScale = (playerLevel/contentLevel)^1.5
 *   playerLevel ≤ contentLevel → inScale = 1.0
 *
 * contentLevel = a creature template-jének minlevel értéke (zóna szintje)
 *
 * ============================================================================
 * SKIPS
 * ============================================================================
 * - Pets, totems, triggers
 * - World bosses
 * - Raid instance-ok (ha ExcludeRaids = 1)
 * - Blacklistelt map-ek
 * - Ha a player szintje ≤ creature template szintje (nincs mit skálázni)
 */

#include "CreatureScalingScript.h"
#include "ModernWoW_Config.h"
#include "ScriptMgr.h"
#include "Creature.h"
#include "CreatureTemplate.h"
#include "Map.h"
#include "Player.h"
#include "SpellInfo.h"
#include "Log.h"
#include <algorithm>
#include <cmath>

// ---------------------------------------------------------------------------
// Konstans: a damage skálázás kitevője.
// 1.5 = közelíti a retail viselkedést.
// Kisebb érték → lazább skálázás (high-level könnyebben boldogul)
// Nagyobb érték → szigorúbb skálázás (high-level szinte teljesen leszorul)
// ---------------------------------------------------------------------------
static constexpr float SCALE_EXPONENT = 1.5f;

// ---------------------------------------------------------------------------
// Helper: kizárt-e a map a skálázásból?
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
// Helper: visszaadja a creature "content szintjét" (zóna-szint)
// Ez a template minlevel értéke — azt tükrözi, hogy a tervező hány szintűnek
// szánta az adott creature-t a zónában.
// ---------------------------------------------------------------------------
static uint8 GetContentLevel(Creature const* creature)
{
    CreatureTemplate const* tmpl = creature->GetCreatureTemplate();
    if (!tmpl)
        return creature->GetLevel();

    // Ha a template range-es (min/max), a közepét vesszük content szintnek
    uint8 minL = tmpl->minlevel;
    uint8 maxL = tmpl->maxlevel;
    return static_cast<uint8>((static_cast<uint16>(minL) + maxL) / 2);
}

// ---------------------------------------------------------------------------
// Helper: kiszámítja a kifelé irányuló damage skálát egy adott
// player vs content szint arány esetén.
//
// Ha a player magasabb szintű mint a content → visszaadja a csökkentő faktort
// Ha a player alacsonyabb vagy egyenlő → 1.0 (nincs módosítás)
// ---------------------------------------------------------------------------
static float CalcOutgoingScale(uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0)
        return 1.0f;

    float ratio = static_cast<float>(contentLevel) / static_cast<float>(playerLevel);
    return std::pow(ratio, SCALE_EXPONENT);
}

// ---------------------------------------------------------------------------
// Helper: kiszámítja a bejövő damage skálát (creature → player)
//
// Ha a player magasabb szintű → nagyobb ütéseket kap (relatívan)
// Ha alacsonyabb vagy egyenlő → 1.0
// ---------------------------------------------------------------------------
static float CalcIncomingScale(uint8 playerLevel, uint8 contentLevel)
{
    if (playerLevel <= contentLevel || contentLevel == 0)
        return 1.0f;

    float ratio = static_cast<float>(playerLevel) / static_cast<float>(contentLevel);
    return std::pow(ratio, SCALE_EXPONENT);
}

// ---------------------------------------------------------------------------
// Helper: creature-ről meghatározzuk, hogy skálázható-e
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

    // World boss-okat nem skálázzuk
    if (tmpl->rank == CREATURE_ELITE_WORLDBOSS)
        return false;

    Map const* map = creature->GetMap();
    if (IsMapExcluded(creature->GetMapId(), map))
        return false;

    return true;
}

// ---------------------------------------------------------------------------
// UnitScript — a fő skálázási logika a damage hook-okban
//
// Ez a script kezeli MINDKÉT irányt:
//   1. Player → Creature damage csökkentése (ha a player magasabb szintű)
//   2. Creature → Player damage növelése (ha a player magasabb szintű)
//
// Vegyes szintű party esetén:
//   Mindkét játékos SAJÁT szintjéhez képest kapja a skálázást →
//   mindenki ugyanolyan kihívást érez, szinttől függetlenül.
// ---------------------------------------------------------------------------
class ModernWoW_ContentScaleDamageScript : public UnitScript
{
public:
    ModernWoW_ContentScaleDamageScript() : UnitScript("ModernWoW_ContentScaleDamageScript") {}

    // -----------------------------------------------------------------------
    // Melee: Player → Creature (csökkentjük a high-level player damage-ét)
    //        Creature → Player (növeljük a bejövő damage-t a high-level playernek)
    // -----------------------------------------------------------------------
    void ModifyMeleeDamage(Unit* target, Unit* attacker, uint32& damage) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (damage == 0)
            return;

        // ESET 1: Player ütötte a creature-t
        if (attacker && attacker->GetTypeId() == TYPEID_PLAYER &&
            target  && target->GetTypeId()   == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = attacker->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = CalcOutgoingScale(playerLevel, contentLevel);
            if (scale < 1.0f)
            {
                damage = static_cast<uint32>(damage * scale);
                LOG_DEBUG("module.scaling",
                    "DynScale Melee Out: Player({}) lvl{} vs Creature({}) contentLvl{} → scale={:.3f} dmg={}",
                    attacker->GetName(), playerLevel, creature->GetEntry(), contentLevel, scale, damage);
            }
        }
        // ESET 2: Creature ütötte a playert
        else if (attacker && attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = target->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = CalcIncomingScale(playerLevel, contentLevel);
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
    // Spell damage: ugyanaz a logika mint melee-nél
    // -----------------------------------------------------------------------
    void ModifySpellDamageTaken(Unit* target, Unit* attacker, int32& damage,
                                SpellInfo const* /*spellInfo*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        if (damage == 0)
            return;

        // Player → Creature spell
        if (attacker && attacker->GetTypeId() == TYPEID_PLAYER &&
            target   && target->GetTypeId()   == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = attacker->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = CalcOutgoingScale(playerLevel, contentLevel);
            if (scale < 1.0f)
                damage = static_cast<int32>(damage * scale);
        }
        // Creature → Player spell
        else if (attacker && attacker->GetTypeId() == TYPEID_UNIT &&
                 target   && target->GetTypeId()   == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            uint8 playerLevel  = target->GetLevel();
            uint8 contentLevel = GetContentLevel(creature);

            float scale = CalcIncomingScale(playerLevel, contentLevel);
            if (scale > 1.0f)
                damage = static_cast<int32>(damage * scale);
        }
    }

    // -----------------------------------------------------------------------
    // DoT tick (pl. poison, bleed) — ugyanaz a logika
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
            target  && target->GetTypeId() == TYPEID_UNIT)
        {
            Creature* creature = target->ToCreature();
            if (!IsCreatureScalable(creature))
                return;

            float scale = CalcOutgoingScale(attacker->GetLevel(), GetContentLevel(creature));
            if (scale < 1.0f)
                damage = static_cast<uint32>(damage * scale);
        }
        // Creature DoT → Player
        else if (attacker->GetTypeId() == TYPEID_UNIT &&
                 target && target->GetTypeId() == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            if (!creature)
                return;
            if (!IsCreatureScalable(creature))
                return;

            float scale = CalcIncomingScale(target->GetLevel(), GetContentLevel(creature));
            if (scale > 1.0f)
                damage = static_cast<uint32>(damage * scale);
        }
    }

    // -----------------------------------------------------------------------
    // Healing (opcionális): ha a player magasabb szintű, a heals is arányosan
    // erősebbek. Kissé csökkentjük, hogy ne gyógyítsa ki magát triviálisan.
    // -----------------------------------------------------------------------
    void ModifyHealReceived(Unit* target, Unit* healer, uint32& heal,
                            SpellInfo const* /*spellInfo*/) override
    {
        if (!sModernWoWConfig->Enabled || !sModernWoWConfig->DynScaleEnabled)
            return;

        // Csak player → player healing skálázás (ne csökkentsük saját gyógyulást
        // ha creature-ből jön, pl. potion)
        if (!healer || healer->GetTypeId() != TYPEID_PLAYER)
            return;
        if (!target || target->GetTypeId() != TYPEID_PLAYER)
            return;

        // Nem skálázzuk a self-healt (pl. bandage), mert az nem combat-dependent
        // Kizárólag ha van a közelben aktív, skálázott creature
        // (egyszerűsítés: mindig csökkentjük ha a healer magasabb szintű mint a
        //  zone szintje — de ehhez zone szintet kellene tudni player kontextusból)
        // Egyelőre: healing skálázás kikapcsolva (csak damage-t skálázzuk)
        (void)heal;
    }
};

// ---------------------------------------------------------------------------
// FormulaScript — XP override
//
// Ha a creature template szintje alacsonyabb mint a player szintje mínusz
// grey threshold, a motor 0 XP-t adna. Mi helyette adunk értelmes XP-t,
// arányosan a player szintjéhez, így megmarad a szintlépési progresszió.
//
// Formula: XP = normalXP * (contentLevel / playerLevel) * XP_SCALE_FACTOR
// (normalXP = amit egy saját szintű creature megöléséért kapna)
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

        // Ha a creature már nem grey (player szintjéhez közel), ne avatkozzunk be
        // A grey threshold kb. playerLevel - 8 (szinttől függően változik)
        int32 greyThreshold = static_cast<int32>(playerLevel) - 8;
        if (static_cast<int32>(contentLevel) >= greyThreshold)
            return; // Motor természetesen kezeli

        // Creature grey lenne → override XP
        // Adjuk meg a "content completion" XP-t:
        // Ez arányos a content szintjéhez képesti normál XP-val,
        // de skálázva a player szintjéhez hogy ne legyen elhanyagolható
        if (gain == 0)
        {
            // Compute synthetic XP: kb. 150 XP * playerLevel / 60 * contentFraction
            float contentFraction = static_cast<float>(contentLevel) /
                                    static_cast<float>(playerLevel);
            uint32 syntheticXP = static_cast<uint32>(
                150.0f * static_cast<float>(playerLevel) * contentFraction);
            gain = syntheticXP;

            LOG_DEBUG("module.scaling",
                "DynScale XP: Player({}) lvl{} killed grey creature({}) contentLvl{} → synthetic XP={}",
                player->GetName(), playerLevel, creature->GetEntry(), contentLevel, gain);
        }
    }
};

// ---------------------------------------------------------------------------
// AllCreatureScript — szint megtartása (csak ellenőrzés)
//
// Ebben a megközelítésben NEM változtatjuk meg a creature szintjét.
// A creature a template szintjén marad — csak a damage-et skálázzuk.
//
// KIVÉTEL: Ha a config DynScaleMinLevel beállítja, hogy a creature legalább
// X szintű legyen (pl. a teljesen triviális 1-es szintű critter-ek ne
// akadályozzák az élményt), akkor felülírjuk az alsó határt.
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

        // Csak az abszolút minimumot alkalmazzuk (pl. lvl1 critter-ek ne
        // akadályozzák a damage skálázást szélső esetekben)
        uint8 minAllowed = sModernWoWConfig->DynScaleMinLevel;
        if (level < minAllowed)
            level = minAllowed;

        // Különben: megtartjuk a template szintjét — a damage hook-ok végzik
        // a valódi skálázást per-player alapon.
    }
};

// ---------------------------------------------------------------------------
// Regisztráció
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
