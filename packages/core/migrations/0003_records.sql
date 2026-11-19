CREATE TABLE `records` (
	`user_id` text NOT NULL,
	`kind` text NOT NULL,
	`key` text NOT NULL,
	`data` text,
	`updated_at` integer NOT NULL,
	`deleted` integer DEFAULT false NOT NULL,
	`schema_version` integer NOT NULL,
	`seq` integer NOT NULL,
	PRIMARY KEY(`user_id`, `kind`, `key`),
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
