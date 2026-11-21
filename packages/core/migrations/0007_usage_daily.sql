CREATE TABLE `usage_daily` (
	`user_id` text NOT NULL,
	`day` text NOT NULL,
	`feature` text NOT NULL,
	`model` text NOT NULL,
	`book_key` text NOT NULL,
	`book_title` text,
	`key_source` text NOT NULL,
	`calls` integer NOT NULL,
	`failed` integer NOT NULL,
	`prompt_tokens` integer NOT NULL,
	`completion_tokens` integer NOT NULL,
	`cost_usd` real,
	`reading_seconds` integer NOT NULL,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `day`, `feature`, `model`, `book_key`, `key_source`),
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
ALTER TABLE `user_storage` ADD `usage_day` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `user_storage` ADD `usage_rows` integer DEFAULT 0 NOT NULL;