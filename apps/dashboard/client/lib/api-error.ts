import type { ErrorCode } from "../../worker/lib/errors";

export type ClientErrorCode = ErrorCode | "NETWORK";

const MESSAGES: Record<ClientErrorCode, string> = {
  BAD_REQUEST: "Isian tidak valid.",
  UNAUTHORIZED: "Sesi habis. Masuk lagi.",
  FORBIDDEN: "Akun ini bukan admin.",
  NOT_FOUND: "Data tidak ditemukan.",
  INVITE_CODE_USED: "Kode undangan sudah dipakai.",
  RATE_LIMITED: "Terlalu banyak permintaan. Coba lagi sebentar.",
  INTERNAL_ERROR: "Ada yang salah di server.",
  OPENROUTER_FAILED: "OpenRouter gagal dihubungi. Coba lagi.",
  NETWORK: "Gagal terhubung. Cek koneksi.",
};

/** Error from the dashboard API, with copy ready to show. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ClientErrorCode,
    readonly serverMessage?: string,
  ) {
    super(MESSAGES[code]);
  }
}

/** Turn a failed response (`{"error": {"code", "message"}}`) into an ApiError. */
export async function toApiError(res: Response): Promise<ApiError> {
  const body = (await res.json().catch(() => null)) as { error?: { code?: string; message?: string } } | null;
  const code = body?.error?.code;
  const known = code !== undefined && code in MESSAGES ? (code as ClientErrorCode) : "INTERNAL_ERROR";
  return new ApiError(res.status, known, body?.error?.message);
}

/** Return the JSON of an ok response, throw ApiError otherwise (network failures included). */
export async function unwrap<T>(request: Promise<{ ok: boolean; json(): Promise<T> }>): Promise<T> {
  let res: { ok: boolean; json(): Promise<T> };
  try {
    res = await request;
  } catch {
    throw new ApiError(0, "NETWORK");
  }
  if (!res.ok) throw await toApiError(res as unknown as Response);
  return res.json();
}
