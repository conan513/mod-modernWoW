# Changelog — mod-modernWoW

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Dynamic per-player content scaling (Chromie Time simulation)
- Auto-loot with configurable range and quality filters
- Personal loot system — each player gets their own drops
- Spell queue window (400ms) for smoother ability usage
- World Quests system with SQL-driven quest pools
- Catch-up XP system for lower-level players in a group
- Guild Perks: XP bonus, mount speed, faster resurrection
- GM commands: `.modernwow`, `.modernwow reload`, `.modernwow status`
- Client-side addon: Damage Meter, Collections Journal, Modern Unit Frames
- Per-player creature level display (creatures always shown as yellow)
- Quest giver scaling: higher-level players see lower-level quests

### Changed
- Creature scaling rewritten to use per-player damage modifier
  instead of global level override — mixed-level parties now work correctly

### Fixed
- Creature scaling no longer makes mobs trivial for lower-level party members
