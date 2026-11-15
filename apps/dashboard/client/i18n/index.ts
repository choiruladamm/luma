import { type Lang, useUiStore } from "../stores/ui-store";
import { id, type Messages } from "./id";

export type { Messages };
export type I18n = { lang: Lang; locale: string; t: Messages };

// Intl locale per UI language: "1,5 KB" / "14 Nov 2026" vs "1.5 KB" / "Nov 14, 2026".
const LOCALES: Record<Lang, string> = { id: "id-ID", en: "en" };

// One stable object per language, so `useMemo(..., [i18n])` only reruns on a switch.
const bundles: Partial<Record<Lang, I18n>> = { id: { lang: "id", locale: LOCALES.id, t: id } };

/** A saved choice wins; otherwise an English browser gets English and everything else Indonesian. */
export function resolveLang(saved: Lang | null, browser = navigator.language): Lang {
  return saved ?? (browser.toLowerCase().startsWith("en") ? "en" : "id");
}

/**
 * English is its own chunk: a static file, not a Worker request. Await this before showing a
 * language; until it's loaded (or if it fails) the UI stays Indonesian.
 */
export async function loadLang(lang: Lang) {
  if (bundles[lang]) return;
  const { en } = await import("./en");
  bundles.en = { lang: "en", locale: LOCALES.en, t: en };
}

const current = (saved: Lang | null) => bundles[resolveLang(saved)] ?? bundles.id!;

/** Copy + locale for rendering; re-renders the component when the language changes. */
export const useI18n = (): I18n => current(useUiStore((s) => s.lang));

/** Same, outside React (toasts fired from mutation callbacks). */
export const getI18n = (): I18n => current(useUiStore.getState().lang);

/** Switch from the account menu: load first, so the screen never shows missing copy. */
export async function chooseLang(lang: Lang) {
  await loadLang(lang).catch(() => undefined);
  if (bundles[lang]) useUiStore.getState().setLang(lang);
}

/** `<html lang>` follows the language actually shown: set before the first render, then on every switch. */
export const applyLang = (lang: Lang) => {
  document.documentElement.lang = lang;
};
useUiStore.subscribe((s, prev) => {
  if (s.lang !== prev.lang) applyLang(current(s.lang).lang);
});
