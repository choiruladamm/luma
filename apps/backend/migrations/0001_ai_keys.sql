CREATE TABLE `ai_keys` (
	`user_id` text PRIMARY KEY NOT NULL,
	`key_hash` text NOT NULL,
	`key_enc` text NOT NULL,
	`limit_usd` real NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
ALTER TABLE `users` ADD `banned` integer DEFAULT false;