/**
 * Helper login untuk test integrasi: bikin user + sesi langsung di D1 lalu
 * kembalikan header Bearer. Diisi di #199 setelah tabel Better Auth ada.
 */
export async function bearerFor(_userId: string): Promise<Record<string, string>> {
  throw new Error("bearerFor: implemented in #199 (auth)");
}
