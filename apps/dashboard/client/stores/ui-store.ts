import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

export type ThemePref = "light" | "dark" | "system";
export type Lang = "id" | "en";
export type OpenMenu = "account" | "search" | null;

/** Cross-screen UI state only. API data lives in the TanStack Query cache, never here. */
type UiState = {
  theme: ThemePref;
  setTheme: (theme: ThemePref) => void;
  /** `null` = never chosen: follow the browser (client/i18n, resolveLang). */
  lang: Lang | null;
  setLang: (lang: Lang) => void;
  /** Only one header menu open at a time (account or mobile nav). */
  openMenu: OpenMenu;
  setOpenMenu: (menu: OpenMenu) => void;
};

export const useUiStore = create<UiState>()(
  persist(
    (set) => ({
      theme: "system",
      setTheme: (theme) => set({ theme }),
      lang: null,
      setLang: (lang) => set({ lang }),
      openMenu: null,
      setOpenMenu: (openMenu) => set({ openMenu }),
    }),
    // Only the theme and language choices survive a reload; menus always start closed.
    { name: "luma-admin-ui", storage: createJSONStorage(() => localStorage), partialize: (s) => ({ theme: s.theme, lang: s.lang }) },
  ),
);

/** `data-theme` on <html>: none for "system" so the CSS media query decides. */
export function applyTheme(theme: ThemePref) {
  if (theme === "system") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = theme;
}
