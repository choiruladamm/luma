import type { Db } from "@luma/core/db/client";
import { releaseOnFailure, reserveBytes } from "../../db/user-storage";
import { ApiError } from "../../lib/errors";
import { fixedLength, userPrefix } from "../../lib/storage";

/** The app's book/cover file names are hash-based; anything outside this pattern is rejected. */
export const FILE_NAME = /^[A-Za-z0-9._-]{1,200}$/;

export const filesPrefix = (userId: string) => `${userPrefix(userId)}files/`;

/**
 * Names not yet in R2. One `list` per 1000 objects (not a HEAD per file: the
 * 50-subrequest limit). ponytail: pages are unbounded; the 1 GB quota limits the
 * number of files, add a cap if the quota grows a lot.
 */
export async function missingFiles(bucket: R2Bucket, userId: string, names: string[]) {
  const prefix = filesPrefix(userId);
  const have = new Set<string>();
  let cursor: string | undefined;
  do {
    const page = await bucket.list({ prefix, cursor, limit: 1000 });
    for (const o of page.objects) have.add(o.key.slice(prefix.length));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return [...new Set(names)].filter((n) => !have.has(n));
}

export type StoredFile = { name: string; size: number };

/**
 * Stores one file. Names are hash-based: a file that already exists isn't uploaded
 * again (quota isn't counted twice), and the body is discarded.
 */
export async function putFile(
  db: Db,
  bucket: R2Bucket,
  quota: number,
  userId: string,
  name: string,
  size: number,
  body: ReadableStream | null,
): Promise<StoredFile> {
  const key = filesPrefix(userId) + name;
  const existing = await bucket.head(key);
  if (existing) {
    await body?.cancel();
    return { name, size: existing.size };
  }
  await reserveBytes(db, userId, size, quota);
  await releaseOnFailure(db, userId, size, () => bucket.put(key, fixedLength(body, size)));
  return { name, size };
}

export async function getFile(bucket: R2Bucket, userId: string, name: string) {
  const object = await bucket.get(filesPrefix(userId) + name);
  if (!object) throw new ApiError(404, "NOT_FOUND", "File not found");
  return object;
}
