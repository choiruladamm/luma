// Aturan merge sync per kind (docs/backend.md, Aturan merge). Murni, tanpa I/O.

export const KINDS = [
  "book",
  "reading_progress",
  "reading_session",
  "ai_result",
  "ai_breakdown",
  "setting",
  "chat_session",
  "chat_turn",
] as const;
export type Kind = (typeof KINDS)[number];

export type Data = Record<string, unknown>;

/** Satu record sync. `updatedAt` = ms epoch (jam device saat perubahan). */
export type SyncRecord = {
  kind: Kind;
  key: string;
  data: Data | null;
  updatedAt: number;
  deleted: boolean;
  schemaVersion: number;
};

const time = (v: unknown) => (typeof v === "string" ? Date.parse(v) : typeof v === "number" ? v : NaN);

/** Nilai waktu paling awal yang terisi (ISO string), null kalau dua-duanya kosong. */
const earliest = (a: unknown, b: unknown) => {
  if (a == null) return b ?? null;
  if (b == null) return a;
  return time(a) <= time(b) ? a : b;
};

const num = (v: unknown) => (typeof v === "number" ? v : 0);

/** `promptVersion` lebih tinggi menang, lalu `createdAt` terbaru. */
function aiWins(incoming: SyncRecord, existing: SyncRecord) {
  if (incoming.deleted || existing.deleted) return incoming.updatedAt > existing.updatedAt;
  const pv = num(incoming.data?.promptVersion) - num(existing.data?.promptVersion);
  if (pv !== 0) return pv > 0;
  return time(incoming.data?.createdAt) > time(existing.data?.createdAt);
}

/** Buku: terbaru menang, tapi `firstOpenedAt`/`finishedAt` paling awal, `readingSeconds` terbesar. */
function mergeBook(incoming: SyncRecord, existing: SyncRecord): SyncRecord {
  const [winner, loser] = incoming.updatedAt > existing.updatedAt ? [incoming, existing] : [existing, incoming];
  if (winner.deleted || loser.deleted || !winner.data || !loser.data) return winner;
  return {
    ...winner,
    data: {
      ...winner.data,
      firstOpenedAt: earliest(winner.data.firstOpenedAt, loser.data.firstOpenedAt),
      finishedAt: earliest(winner.data.finishedAt, loser.data.finishedAt),
      readingSeconds: Math.max(num(winner.data.readingSeconds), num(loser.data.readingSeconds)),
    },
  };
}

function winner(incoming: SyncRecord, existing: SyncRecord): SyncRecord {
  switch (incoming.kind) {
    case "book":
      return mergeBook(incoming, existing);
    case "reading_session":
      return existing; // append-only: sesi yang sama gak berubah
    case "ai_result":
    case "ai_breakdown":
      return aiWins(incoming, existing) ? incoming : existing;
    default:
      return incoming.updatedAt > existing.updatedAt ? incoming : existing;
  }
}

const same = (a: SyncRecord, b: SyncRecord) =>
  a.deleted === b.deleted &&
  a.updatedAt === b.updatedAt &&
  a.schemaVersion === b.schemaVersion &&
  JSON.stringify(a.data) === JSON.stringify(b.data);

/**
 * Hasil merge record masuk terhadap yang udah ada di D1. `null` = gak ada yang
 * ditulis (sama persis, kalah, atau app pengirim lebih lama dari record di server).
 */
export function merge(existing: SyncRecord | undefined, incoming: SyncRecord): SyncRecord | null {
  if (!existing) return incoming;
  if (incoming.schemaVersion < existing.schemaVersion) return null;
  const result = winner(incoming, existing);
  return same(result, existing) ? null : result;
}
