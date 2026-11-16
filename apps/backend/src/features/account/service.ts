import type { Db } from "../../db/client";
import { userPrefix } from "../../lib/storage";
import { deleteUser } from "./repo";

/**
 * Halaman R2 per request hapus akun: tiap halaman = 1 list + 1 delete subrequest,
 * jauh di bawah batas 50 subrequest.
 */
export const DELETE_PAGES_PER_REQUEST = 10;

export type DeleteResult = { status: "deleted" } | { status: "pending" };

/**
 * Hapus semua objek R2 user dulu, baru baris D1 (sesi & akun ikut cascade).
 * Objek kebanyakan → `pending`: user belum dihapus, client panggil lagi.
 */
export async function deleteAccount(db: Db, bucket: R2Bucket, userId: string): Promise<DeleteResult> {
  const prefix = userPrefix(userId);
  for (let page = 0; page < DELETE_PAGES_PER_REQUEST; page++) {
    const listed = await bucket.list({ prefix, limit: 1000 });
    if (listed.objects.length > 0) await bucket.delete(listed.objects.map((o) => o.key));
    if (!listed.truncated) {
      await deleteUser(db, userId);
      return { status: "deleted" };
    }
  }
  return { status: "pending" };
}
