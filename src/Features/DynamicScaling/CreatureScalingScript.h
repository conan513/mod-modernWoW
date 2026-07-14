/*
 * mod-modernWoW — Dynamic Creature Scaling
 * Copyright (C) 2024
 *
 * Scales creature level, health, and damage to match the player's level
 * in every zone (except blacklisted maps and raids if configured).
 * Also adjusts XP rewards proportionally.
 */

#ifndef MOD_MODERNWOW_DYNSCALE_H
#define MOD_MODERNWOW_DYNSCALE_H

#include "Creature.h"
#include "Player.h"

void AddModernWoW_DynamicScalingScripts();

#endif // MOD_MODERNWOW_DYNSCALE_H
