import type { Db } from "../../db/client";
import { userPrefix } from "../../lib/storage";
import { deleteUser } from "./repo";

/**
 * R2 pages per account-deletion request: each page = 1 list + 1 delete subrequest,
 * far below the 50-subrequest limit.
 */
export const DELETE_PAGES_PER_REQUEST = 10;

export type DeleteResult = { status: "deleted" } | { status: "pending" };

/**
 * Deletes all of the user's R2 objects first, then the D1 row (sessions and accounts cascade).
 * Too many objects → `pending`: the user is not deleted yet, the client calls again.
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
