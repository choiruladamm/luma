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

/** ISO string → "14 Nov 2026". */
export const formatDate = (iso: string) =>
  new Date(iso).toLocaleDateString(LOCALE, { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });

/** ISO string → "14 Nov 2026 15.30" (UTC, like the server). */
export const formatDateTime = (iso: string) =>
  new Date(iso).toLocaleString(LOCALE, { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" });

/** 0.00676 → "US$0,0068": small AI spend keeps up to 4 decimals. */
export const formatUsd = (usd: number) =>
  usd.toLocaleString(LOCALE, { style: "currency", currency: "USD", maximumFractionDigits: 4 });

export const formatNumber = (n: number) => n.toLocaleString(LOCALE);
