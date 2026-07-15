/*
 * mod-modernWoW
 * Copyright (C) 2024
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#include "ModernWoW_Config.h"
#include "Config.h"
#include "Log.h"
#include <sstream>

ModernWoWConfig* ModernWoWConfig::instance()
{
    static ModernWoWConfig instance;
    return &instance;
}

std::vector<uint32> ModernWoWConfig::ParseUInt32List(const std::string& str)
{
    std::vector<uint32> result;
    if (str.empty())
        return result;

    std::istringstream ss(str);
    std::string token;
    while (std::getline(ss, token, ','))
    {
        try
        {
            result.push_back(static_cast<uint32>(std::stoul(token)));
        }
        catch (...) {}
    }
    return result;
}

void ModernWoWConfig::Load()
{
    // General
    Enabled  = sConfigMgr->GetOption<bool>("ModernWoW.Enable", true);
    Announce = sConfigMgr->GetOption<bool>("ModernWoW.Announce", true);

    // Auto-Loot
    AutoLootMode      = sConfigMgr->GetOption<uint8>("ModernWoW.AutoLoot.Enable", 1);
    AutoLootThreshold = sConfigMgr->GetOption<uint8>("ModernWoW.AutoLoot.Threshold", 1);
    AutoLootGold      = sConfigMgr->GetOption<bool>("ModernWoW.AutoLoot.Gold", true);

    // Dynamic Scaling
    DynScaleEnabled     = sConfigMgr->GetOption<bool>("ModernWoW.DynamicScaling.Enable", true);
    DynScaleMode        = sConfigMgr->GetOption<uint8>("ModernWoW.DynamicScaling.Mode", 2);
    DynScaleMinLevel    = sConfigMgr->GetOption<uint8>("ModernWoW.DynamicScaling.MinLevel", 1);
    DynScaleMaxLevel    = sConfigMgr->GetOption<uint8>("ModernWoW.DynamicScaling.MaxLevel", 80);
    DynScaleHealthMult  = sConfigMgr->GetOption<float>("ModernWoW.DynamicScaling.HealthMultiplier", 1.0f);
    DynScaleDamageMult  = sConfigMgr->GetOption<float>("ModernWoW.DynamicScaling.DamageMultiplier", 1.0f);
    DynScaleXP          = sConfigMgr->GetOption<bool>("ModernWoW.DynamicScaling.ScaleXP", true);
    DynScaleLoot        = sConfigMgr->GetOption<bool>("ModernWoW.DynamicScaling.ScaleLoot", true);
    DynScaleExcludeRaids = sConfigMgr->GetOption<bool>("ModernWoW.DynamicScaling.ExcludeRaids", true);

    std::string mapBlacklist = sConfigMgr->GetOption<std::string>("ModernWoW.DynamicScaling.MapBlacklist", "");
    DynScaleMapBlacklist = ParseUInt32List(mapBlacklist);

    // Personal Loot
    PersonalLootMode     = sConfigMgr->GetOption<uint8>("ModernWoW.PersonalLoot.Enable", 1);
    PersonalLootSoloMult = sConfigMgr->GetOption<float>("ModernWoW.PersonalLoot.SoloMultiplier", 1.2f);

    // Spell Queue
    SpellQueueEnabled  = sConfigMgr->GetOption<bool>("ModernWoW.SpellQueue.Enable", true);
    SpellQueueWindowMs = sConfigMgr->GetOption<uint32>("ModernWoW.SpellQueue.WindowMs", 400);

    // World Quests
    WorldQuestsEnabled       = sConfigMgr->GetOption<bool>("ModernWoW.WorldQuests.Enable", true);
    WorldQuestsActiveCount   = sConfigMgr->GetOption<uint32>("ModernWoW.WorldQuests.ActiveCount", 12);
    WorldQuestsDurationHours = sConfigMgr->GetOption<uint32>("ModernWoW.WorldQuests.DurationHours", 24);

    // Catch-Up
    CatchUpEnabled       = sConfigMgr->GetOption<bool>("ModernWoW.CatchUp.Enable", true);
    CatchUpXPMultiplier  = sConfigMgr->GetOption<float>("ModernWoW.CatchUp.XPMultiplier", 2.0f);
    CatchUpBetterLoot    = sConfigMgr->GetOption<bool>("ModernWoW.CatchUp.BetterLoot", true);

    // Instant Mail
    InstantMailEnabled = sConfigMgr->GetOption<bool>("ModernWoW.InstantMail.Enable", true);

    // Quests
    QuestsShowLowLevelAsNormal = sConfigMgr->GetOption<bool>("ModernWoW.Quests.ShowLowLevelAsNormal", true);

    // Guild Perks
    GuildPerksEnabled  = sConfigMgr->GetOption<bool>("ModernWoW.GuildPerks.Enable", true);
    GuildPerksXPBonus  = sConfigMgr->GetOption<uint32>("ModernWoW.GuildPerks.XPBonus", 10);
    GuildPerksCashFlow = sConfigMgr->GetOption<uint32>("ModernWoW.GuildPerks.CashFlow", 5);

    LOG_INFO("module", "mod-modernWoW: Config loaded (AutoLoot={}, DynScale={}, PersonalLoot={}, SpellQueue={}, WorldQuests={}, CatchUp={}, InstantMail={}, GuildPerks={})",
        AutoLootMode, DynScaleEnabled ? 1 : 0, PersonalLootMode,
        SpellQueueEnabled ? 1 : 0, WorldQuestsEnabled ? 1 : 0,
        CatchUpEnabled ? 1 : 0, InstantMailEnabled ? 1 : 0, GuildPerksEnabled ? 1 : 0);
}
