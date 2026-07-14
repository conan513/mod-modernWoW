-- mod-modernWoW: World Database Tables
-- Run once on a fresh install. Safe to re-run (uses IF NOT EXISTS).

-- ============================================================
-- World Quest Pool — quests eligible to become world quests
-- Admins add entries here. quest_id must exist in quest_template.
-- ============================================================
CREATE TABLE IF NOT EXISTS `modernwow_worldquest_pool` (
    `quest_id`    INT UNSIGNED NOT NULL,
    `enabled`     TINYINT(1) NOT NULL DEFAULT 1,
    `min_level`   TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `max_level`   TINYINT UNSIGNED NOT NULL DEFAULT 80,
    `zone_id`     INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 = any zone',
    `description` VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (`quest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-modernWoW: World Quest eligible quests';

-- ============================================================
-- Active World Quests — currently running WQs (refreshed daily)
-- ============================================================
CREATE TABLE IF NOT EXISTS `modernwow_active_worldquests` (
    `quest_id`    INT UNSIGNED NOT NULL,
    `expires_at`  INT UNSIGNED NOT NULL,
    PRIMARY KEY (`quest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='mod-modernWoW: Currently active World Quests';

-- ============================================================
-- Example seed data: add some well-known quests to the pool
-- These are generic quests available in most WotLK databases.
-- Customize for your server's quest list.
-- ============================================================

-- Uncomment and adjust as needed:
-- INSERT IGNORE INTO `modernwow_worldquest_pool` (quest_id, enabled, min_level, max_level, zone_id, description) VALUES
-- (1234, 1, 70, 80, 4197, 'Example Icecrown Daily'),
-- (5678, 1, 60, 80, 0,    'Example World Event Quest');

-- ============================================================
-- Tip: To find eligible daily quests, run:
-- SELECT q.ID, q.LogTitle, q.QuestLevel FROM quest_template q
-- WHERE q.Flags & 1024 AND q.QuestLevel >= 70
-- ORDER BY q.QuestLevel DESC LIMIT 50;
-- ============================================================
