import { eq, sql } from "drizzle-orm";
import type { Db } from "../../db/client";
import { userStorage } from "../../db/schema";
import { ApiError } from "../../lib/errors";
import { userPrefix } from "../account/service";

/** Nama file buku/cover di app sudah berbasis hash; selain pola ini ditolak. */
export const FILE_NAME = /^[A-Za-z0-9._-]{1,200}$/;

/** Batas body Workers free; satu file atau satu snapshot gak boleh lewat. */
export const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;

export const filesPrefix = (userId: string) => `${userPrefix(userId)}files/`;

/** `Content-Length` wajib (R2 butuh panjang pasti, kuota dicek sebelum upload). */
export function uploadSize(header: string | undefined): number {
  const size = Number(header);
  if (!header || !Number.isSafeInteger(size) || size < 0) {
    throw new ApiError(400, "BAD_REQUEST", "Content-Length required");
  }
  if (size > MAX_UPLOAD_BYTES) {
    throw new ApiError(413, "PAYLOAD_TOO_LARGE", `Body exceeds ${MAX_UPLOAD_BYTES} bytes`);
  }
  return size;
}

/**
 * Body request dijamin sepanjang `size`: R2 butuh panjang pasti, dan klien yang
 * bohong soal `Content-Length` bikin upload gagal, bukan lolos kuota.
 */
export const fixedLength = (body: ReadableStream | null, size: number) =>
  (body ?? new Response("").body!).pipeThrough(new FixedLengthStream(size));

export async function storedBytes(db: Db, userId: string): Promise<number> {
  const [row] = await db
    .select({ bytes: userStorage.bytes })
    .from(userStorage)
    .where(eq(userStorage.userId, userId));
  return row?.bytes ?? 0;
}

/** Kuota per user: `bytes + size ≤ quota`, lewat → 413 STORAGE_FULL. */
export function assertFits(used: number, size: number, quota: number) {
  if (used + size > quota) {
    throw new ApiError(413, "STORAGE_FULL", "Cloud storage is full");
  }
}

export const addBytes = (db: Db, userId: string, delta: number) =>
  db
    .insert(userStorage)
    .values({ userId, bytes: Math.max(0, delta) })
    .onConflictDoUpdate({
      target: userStorage.userId,
      set: { bytes: sql`max(0, ${userStorage.bytes} + ${delta})` },
    });

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
