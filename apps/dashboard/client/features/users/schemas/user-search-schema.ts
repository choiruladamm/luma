import { z } from "zod";

/** Same limit as the worker's `q` validation. */
export const userSearchSchema = z.object({ q: z.string().trim().max(100, "Maksimal 100 karakter") });

export type UserSearch = z.infer<typeof userSearchSchema>;
