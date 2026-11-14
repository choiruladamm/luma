import { z } from "zod";

/** Same limits as the worker (`count` 1–20). */
export const createInviteSchema = z.object({
  count: z.number({ error: "Isi jumlah kode" }).int("Harus bilangan bulat").min(1, "Minimal 1").max(20, "Maksimal 20"),
});

export type CreateInvite = z.infer<typeof createInviteSchema>;
