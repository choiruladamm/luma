import { z } from "zod/mini";

/** Same limit as the worker's `q` validation. zod/mini: the full zod build was ~2/3 of the Users chunk. */
export const userSearchSchema = z.object({ q: z.string().check(z.trim(), z.maxLength(100, "Maksimal 100 karakter")) });

export type UserSearch = z.infer<typeof userSearchSchema>;
