CREATE TABLE `user_storage` (
	`user_id` text PRIMARY KEY NOT NULL,
	`bytes` integer DEFAULT 0 NOT NULL,
	`seq` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
