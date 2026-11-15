import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { renderApp } from "../helpers/render";

// Pretend to be a phone: every "max-width" query matches (the tab bar is CSS-hidden on desktop,
// but the scroll lock asks matchMedia itself).
const phone = () =>
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query) => ({ matches: query.includes("max-width"), media: query, addEventListener: () => {}, removeEventListener: () => {} }) as unknown as MediaQueryList,
  );

afterEach(() => {
  vi.restoreAllMocks();
  document.documentElement.style.overflow = "";
});

describe("phone navigation", () => {
  it("bottom tab bar: icons, labels, counts, and the current screen", async () => {
    const { user, router } = renderApp("/");
    const bars = await screen.findAllByRole("navigation", { name: "Navigasi admin" });
    const tabBar = bars.at(-1)!;
    expect(await within(tabBar).findByText("48")).toBeInTheDocument();
    expect(within(tabBar).getByRole("link", { name: /Ringkasan/ })).toHaveAttribute("aria-current", "page");
    await user.click(within(tabBar).getByRole("link", { name: /Undangan/ }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/invites"));
    expect(within(tabBar).getByRole("link", { name: /Undangan/ })).toHaveAttribute("aria-current", "page");
  });

  it("search mode swaps the header row and locks the page scroll until closed", async () => {
    phone();
    const { user } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Buka pencarian" }));
    expect(document.activeElement).toHaveAttribute("role", "combobox");
    expect(screen.getAllByRole("combobox", { name: "Cari email user" })).toHaveLength(2);
    expect(document.documentElement.style.overflow).toBe("hidden");
    await user.click(screen.getAllByRole("button", { name: "Tutup pencarian" })[0]!);
    expect(document.documentElement.style.overflow).toBe("");
  });

  it("the account menu locks the page scroll on a phone", async () => {
    phone();
    const { user } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    expect(document.documentElement.style.overflow).toBe("hidden");
    await user.click(screen.getByRole("button", { name: "Tutup menu" }));
    expect(document.documentElement.style.overflow).toBe("");
  });
});
