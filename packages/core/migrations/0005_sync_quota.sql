ALTER TABLE `user_storage` ADD `sync_bytes` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `user_storage` ADD `sync_day` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `user_storage` ADD `sync_rows` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
-- Isi ukuran sync user yang udah punya record (sama dengan rumus di features/sync/service.ts).
UPDATE `user_storage` SET `sync_bytes` = (
  SELECT coalesce(sum(length(`key`) + coalesce(length(`data`), 0)), 0)
  FROM `records` WHERE `records`.`user_id` = `user_storage`.`user_id`
);
