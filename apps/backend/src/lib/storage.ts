// Aturan penyimpanan R2 per user, dipakai file buku, backup, dan hapus akun
// (docs/backend.md, Backup cloud). Murni: tanpa D1, tanpa binding.
import { ApiError } from "./errors";

/** Prefix R2 milik satu user. */
export const userPrefix = (userId: string) => `u/${userId}/`;

/** Batas body Workers free; satu file atau satu snapshot gak boleh lewat. */
export const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;

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

/** Kuota per user: `bytes + size ≤ quota`, lewat → 413 STORAGE_FULL. */
export function assertFits(used: number, size: number, quota: number) {
  if (used + size > quota) {
    throw new ApiError(413, "STORAGE_FULL", "Cloud storage is full");
  }
}
