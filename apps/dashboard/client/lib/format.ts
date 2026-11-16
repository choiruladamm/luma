import type { I18n } from "../i18n";

// Every formatter takes the UI locale explicitly (`useI18n().locale`): "1,5 KB" in Indonesian,
// "1.5 KB" in English. Dates show in the admin's own time zone (the browser's), not UTC.

const UNITS = ["B", "KB", "MB", "GB", "TB"];

/** 1536 → "1,5 KB" (1024-based, one decimal from KB up). */
export function formatBytes(bytes: number, locale: string) {
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toLocaleString(locale, { maximumFractionDigits: unit === 0 ? 0 : 1 })} ${UNITS[unit]}`;
}

/** ISO string → "14 Nov 2026" / "Nov 14, 2026". */
export const formatDate = (iso: string, locale: string) =>
  new Date(iso).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });

/** ISO string → "14 Nov 2026, 19.42" / "Nov 14, 2026, 7:42 PM". */
export const formatDateTime = (iso: string, locale: string) =>
  `${formatDate(iso, locale)}, ${new Date(iso).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" })}`;

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * "Baru aja", "2 mnt lalu", "1 jam lalu", "Kemarin", "3 hari lalu", "2 minggu lalu", then the
 * date. Own copy rather than Intl.RelativeTimeFormat, whose "2 menit yang lalu" isn't the board's.
 */
export function formatRelative(iso: string | null, { t, locale }: Pick<I18n, "t" | "locale">, now = Date.now()) {
  if (!iso) return t.time.never;
  const diff = now - new Date(iso).getTime();
  if (diff < MINUTE) return t.time.justNow;
  if (diff < HOUR) return t.time.minutes(Math.floor(diff / MINUTE));
  if (diff < DAY) return t.time.hours(Math.floor(diff / HOUR));
  if (diff < 2 * DAY) return t.time.yesterday;
  if (diff < 7 * DAY) return t.time.days(Math.floor(diff / DAY));
  if (diff < 30 * DAY) return t.time.weeks(Math.floor(diff / (7 * DAY)));
  return formatDate(iso, locale);
}

/** 0.00676 → "US$0,0068" / "$0.0068": small AI spend keeps up to 4 decimals. */
export const formatUsd = (usd: number, locale: string) =>
  usd.toLocaleString(locale, { style: "currency", currency: "USD", maximumFractionDigits: 4 });

export const formatNumber = (n: number, locale: string) => n.toLocaleString(locale);
