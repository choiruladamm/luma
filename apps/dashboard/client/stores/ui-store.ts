import { create } from "zustand";

/** Cross-screen UI state only. API data lives in the TanStack Query cache, never here. */
type UiState = {
  navOpen: boolean;
  setNavOpen: (open: boolean) => void;
};

export const useUiStore = create<UiState>()((set) => ({
  navOpen: false,
  setNavOpen: (navOpen) => set({ navOpen }),
}));
