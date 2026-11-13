import type { Db } from "../../db/client";
import { addBytes, storedBytes } from "../../db/user-storage";
import { ApiError } from "../../lib/errors";
import { assertFits, fixedLength, userPrefix } from "../../lib/storage";

/** Nama file buku/cover di app sudah berbasis hash; selain pola ini ditolak. */
export const FILE_NAME = /^[A-Za-z0-9._-]{1,200}$/;

export const filesPrefix = (userId: string) => `${userPrefix(userId)}files/`;

/**
 * Nama yang belum ada di R2. Satu `list` per 1000 objek (bukan HEAD per file:
 * batas 50 subrequest). ponytail: halaman gak dibatasi; kuota 1GB yang membatasi
 * jumlah file, pasang batas kalau kuota naik jauh.
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
 * Simpan satu file. Nama berbasis hash: file yang udah ada gak diunggah ulang
 * (kuota gak dihitung dobel), body-nya dibuang.
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
  assertFits(await storedBytes(db, userId), size, quota);
  await bucket.put(key, fixedLength(body, size));
  await addBytes(db, userId, size);
  return { name, size };
}

export async function getFile(bucket: R2Bucket, userId: string, name: string) {
  const object = await bucket.get(filesPrefix(userId) + name);
  if (!object) throw new ApiError(404, "NOT_FOUND", "File not found");
  return object;
}
