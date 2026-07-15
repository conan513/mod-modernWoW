/*
 * mod-modernWoW
 * Copyright (C) 2024
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#include "ScriptMgr.h"
#include "ModernWoW_Config.h"
#include "Log.h"

// Forward declarations for all feature scripts
void AddModernWoW_AutoLootScripts();
void AddModernWoW_DynamicScalingScripts();
void AddModernWoW_PersonalLootScripts();
void AddModernWoW_SpellQueueScripts();
void AddModernWoW_WorldQuestScripts();
void AddModernWoW_CatchUpScripts();
void AddModernWoW_GuildPerksScripts();
void AddModernWoW_CombatPacingScripts();
void AddModernWoW_CommandScripts();

// WorldScript: handles startup config load and announcement
class ModernWoW_WorldScript : public WorldScript
{
public:
    ModernWoW_WorldScript() : WorldScript("ModernWoW_WorldScript") {}

    void OnBeforeConfigLoad(bool /*reload*/) override
    {
        sModernWoWConfig->Load();
    }

    void OnStartup() override
    {
        if (!sModernWoWConfig->Enabled)
            return;

        if (sModernWoWConfig->Announce)
        {
            LOG_INFO("module", "╔═══════════════════════════════════════════╗");
            LOG_INFO("module", "║        mod-modernWoW — Loaded             ║");
            LOG_INFO("module", "╚═══════════════════════════════════════════╝");
        }
    }
};

// Module entry point — called by AzerothCore's module loader
void Addmod_modernWoWScripts()
{
    // Load config eagerly so script registration can evaluate features correctly
    sModernWoWConfig->Load();

    // Register world script first (handles config loading)
    new ModernWoW_WorldScript();

    // Register feature scripts based on config
    // Note: scripts register themselves, config check is inside each script
    AddModernWoW_AutoLootScripts();
    AddModernWoW_DynamicScalingScripts();
    AddModernWoW_PersonalLootScripts();
    AddModernWoW_SpellQueueScripts();
    AddModernWoW_WorldQuestScripts();
    AddModernWoW_CatchUpScripts();
    AddModernWoW_GuildPerksScripts();
    AddModernWoW_CombatPacingScripts();
    AddModernWoW_CommandScripts();
}
