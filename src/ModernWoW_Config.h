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
    ModernWoWConfig() = default;

    // Helper to parse comma-separated uint32 list
    std::vector<uint32> ParseUInt32List(const std::string& str);
};

#define sModernWoWConfig ModernWoWConfig::instance()

#endif // MOD_MODERNWOW_CONFIG_H
