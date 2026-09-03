CREATE TABLE IF NOT EXISTS `character_racial_selection` (
    `guid` INT UNSIGNED NOT NULL,
    `spell` INT UNSIGNED NOT NULL,
    `category` VARCHAR(16) NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`guid`, `spell`),
    KEY `idx_character_racial_selection_category` (`guid`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
