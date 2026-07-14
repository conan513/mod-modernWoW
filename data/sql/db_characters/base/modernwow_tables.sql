-- mod-modernWoW: Character Database Tables
-- Run once on a fresh install. Safe to re-run (uses IF NOT EXISTS).

-- ============================================================
-- World Quest completions tracking (per player, per day)
-- ============================================================
CREATE TABLE IF NOT EXISTS `modernwow_wq_completions` (
    `player_guid`      INT UNSIGNED NOT NULL,
    `quest_id`         INT UNSIGNED NOT NULL,
    `completed_date`   DATE NOT NULL,
    PRIMARY KEY (`player_guid`, `quest_id`, `completed_date`),
    INDEX `idx_player_date` (`player_guid`, `completed_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-modernWoW: World Quest daily completions';

-- ============================================================
-- Personal Loot: stored per-player loot (optional, for persistence)
-- Not required for basic operation — used for reconnect recovery.
-- ============================================================
CREATE TABLE IF NOT EXISTS `modernwow_personal_loot` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `player_guid`  INT UNSIGNED NOT NULL,
    `creature_guid` BIGINT UNSIGNED NOT NULL,
    `item_id`      INT UNSIGNED NOT NULL,
    `count`        SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    `expires_at`   INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_player` (`player_guid`),
    INDEX `idx_creature` (`creature_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-modernWoW: Personal loot pending pickup';
