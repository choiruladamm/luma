import { afterEach, describe, expect, it } from "vitest";
import { toast, useToastStore } from "../../../client/stores/toast-store";
import { applyTheme, useUiStore } from "../../../client/stores/ui-store";

describe("toast store", () => {
  it("keeps one toast at a time and dismisses only the current one", () => {
    toast("Kode disalin");
    const first = useToastStore.getState().toast!;
    toast("Gagal", { tone: "error" });
    const second = useToastStore.getState().toast!;
    expect(second).toMatchObject({ message: "Gagal", tone: "error" });
    useToastStore.getState().dismiss(first.id);
    expect(useToastStore.getState().toast).toBe(second);
    useToastStore.getState().dismiss(second.id);
    expect(useToastStore.getState().toast).toBeNull();
  });
});

describe("ui store", () => {
  afterEach(() => delete document.documentElement.dataset.theme);

  it("sets data-theme for light/dark and removes it for system", () => {
    applyTheme("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");
    applyTheme("system");
    expect(document.documentElement.dataset.theme).toBeUndefined();
  });

  it("persists only the theme choice", () => {
    useUiStore.getState().setTheme("dark");
    useUiStore.getState().setOpenMenu("account");
    expect(JSON.parse(localStorage.getItem("luma-admin-ui")!)).toEqual({ state: { theme: "dark" }, version: 0 });
  });
});
