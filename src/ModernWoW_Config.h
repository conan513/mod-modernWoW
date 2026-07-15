/*
 * mod-modernWoW
 * Copyright (C) 2024
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

#ifndef MOD_MODERNWOW_CONFIG_H
#define MOD_MODERNWOW_CONFIG_H

#include "Common.h"
#include <string>
#include <vector>

class ModernWoWConfig
{
public:
    static ModernWoWConfig* instance();

    // Loads all config values from the worldserver config
    void Load();

    // General
    bool   Enabled;
    bool   Announce;

    // Auto-Loot
    uint8  AutoLootMode;       // 0=off, 1=all, 2=threshold
    uint8  AutoLootThreshold;  // item quality threshold
    bool   AutoLootGold;

    // Dynamic Scaling
    bool   DynScaleEnabled;
    uint8  DynScaleMinLevel;
    uint8  DynScaleMaxLevel;
    float  DynScaleHealthMult;
    float  DynScaleDamageMult;
    bool   DynScaleXP;
    bool   DynScaleLoot;
    bool   DynScaleExcludeRaids;
    std::vector<uint32> DynScaleMapBlacklist;

    // Personal Loot
    uint8  PersonalLootMode;   // 0=off, 1=all, 2=dungeons only
    float  PersonalLootSoloMult;

    // Spell Queue
    bool   SpellQueueEnabled;
    uint32 SpellQueueWindowMs;

    // World Quests
    bool   WorldQuestsEnabled;
    uint32 WorldQuestsActiveCount;
    uint32 WorldQuestsDurationHours;

    // Catch-Up
    bool   CatchUpEnabled;
    float  CatchUpXPMultiplier;
    bool   CatchUpBetterLoot;

    // Instant Mail
    bool   InstantMailEnabled;

    // Quests
    bool   QuestsShowLowLevelAsNormal;

    // Guild Perks
    bool   GuildPerksEnabled;
    uint32 GuildPerksXPBonus;
    uint32 GuildPerksCashFlow;

private:
    ModernWoWConfig() :
        Enabled(true),
        Announce(true),
        AutoLootMode(1),
        AutoLootThreshold(1),
        AutoLootGold(true),
        DynScaleEnabled(true),
        DynScaleMinLevel(1),
        DynScaleMaxLevel(80),
        DynScaleHealthMult(1.0f),
        DynScaleDamageMult(1.0f),
        DynScaleXP(true),
        DynScaleLoot(true),
        DynScaleExcludeRaids(true),
        PersonalLootMode(1),
        PersonalLootSoloMult(1.2f),
        SpellQueueEnabled(true),
        SpellQueueWindowMs(400),
        WorldQuestsEnabled(true),
        WorldQuestsActiveCount(12),
        WorldQuestsDurationHours(24),
        CatchUpEnabled(true),
        CatchUpXPMultiplier(2.0f),
        CatchUpBetterLoot(true),
        InstantMailEnabled(true),
        QuestsShowLowLevelAsNormal(true),
        GuildPerksEnabled(true),
        GuildPerksXPBonus(10),
        GuildPerksCashFlow(5)
    {}

    // Helper to parse comma-separated uint32 list
    std::vector<uint32> ParseUInt32List(const std::string& str);
};

#define sModernWoWConfig ModernWoWConfig::instance()

#endif // MOD_MODERNWOW_CONFIG_H
