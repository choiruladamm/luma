import { create } from "zustand";

export type Toast = {
  id: number;
  message: string;
  tone: "success" | "error" | "info";
  action?: { label: string; onClick: () => void };
};

type ToastState = {
  toast: Toast | null;
  show: (toast: Omit<Toast, "id">) => void;
  dismiss: (id: number) => void;
};

let seq = 0;

/** One toast at a time (komponen 2, Toast): a new one replaces the current one. */
export const useToastStore = create<ToastState>()((set) => ({
  toast: null,
  show: (toast) => set({ toast: { ...toast, id: ++seq } }),
  dismiss: (id) => set((s) => (s.toast?.id === id ? { toast: null } : s)),
}));

export const toast = (message: string, extra: Partial<Omit<Toast, "id" | "message">> = {}) =>
  useToastStore.getState().show({ message, tone: "success", ...extra });
