const LOCALE = "id-ID";

const UNITS = ["B", "KB", "MB", "GB", "TB"];

/** 1536 → "1,5 KB" (1024-based, one decimal from KB up). */
export function formatBytes(bytes: number) {
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toLocaleString(LOCALE, { maximumFractionDigits: unit === 0 ? 0 : 1 })} ${UNITS[unit]}`;
}

// Dates show in the admin's own time zone (the browser's), not UTC.

/** ISO string → "14 Nov 2026". */
export const formatDate = (iso: string) => new Date(iso).toLocaleDateString(LOCALE, { day: "numeric", month: "short", year: "numeric" });

/** ISO string → "14 Nov 2026, 19.42". */
export const formatDateTime = (iso: string) =>
  `${formatDate(iso)}, ${new Date(iso).toLocaleTimeString(LOCALE, { hour: "2-digit", minute: "2-digit" })}`;

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** "Baru aja", "2 mnt lalu", "1 jam lalu", "Kemarin", "3 hari lalu", "2 minggu lalu", then the date. */
export function formatRelative(iso: string | null, now = Date.now()) {
  if (!iso) return "Belum pernah";
  const diff = now - new Date(iso).getTime();
  if (diff < MINUTE) return "Baru aja";
  if (diff < HOUR) return `${Math.floor(diff / MINUTE)} mnt lalu`;
  if (diff < DAY) return `${Math.floor(diff / HOUR)} jam lalu`;
  if (diff < 2 * DAY) return "Kemarin";
  if (diff < 7 * DAY) return `${Math.floor(diff / DAY)} hari lalu`;
  if (diff < 30 * DAY) return `${Math.floor(diff / (7 * DAY))} minggu lalu`;
  return formatDate(iso);
}

/** 0.00676 → "US$0,0068": small AI spend keeps up to 4 decimals. */
export const formatUsd = (usd: number) =>
  usd.toLocaleString(LOCALE, { style: "currency", currency: "USD", maximumFractionDigits: 4 });

export const formatNumber = (n: number) => n.toLocaleString(LOCALE);
