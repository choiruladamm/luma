import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, delay, http } from "msw";
import { describe, expect, it } from "vitest";
import { overview, usageOverview, user as userRow, usersPage } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { recordRequests } from "../helpers/clock";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("Ringkasan", () => {
  it("shows app usage across users beside OpenRouter's spend", async () => {
    renderApp("/");
    const card = await screen.findByRole("region", { name: "Pemakaian app" });
    expect(await within(card).findByText("Bedahin")).toBeInTheDocument();
    expect(within(card).getByText("Biaya dilaporin app bulan ini")).toBeInTheDocument();
    expect(within(card).getByText(/^OpenRouter: /)).toBeInTheDocument();
    expect(within(card).getByText("3 hari ini · 7 minggu ini")).toBeInTheDocument();
    expect(within(card).getByText("25% dari request")).toBeInTheDocument();
    expect(within(card).getByRole("link", { name: "Boros" })).toHaveAttribute("href", "/users/u2");
    expect(within(card).getByText("4 pembaca")).toBeInTheDocument();
    expect(within(card).getAllByRole("listitem", { name: /^\d+ Nov 2026: / })).toHaveLength(2);
  });

  it("says so when no app reported usage, and retries a failed load", async () => {
    let fail = true;
    server.use(
      http.get(`${API}/overview/usage`, () =>
        fail
          ? apiError(500, "INTERNAL_ERROR")
          : HttpResponse.json(
              usageOverview({ totals: { ...usageOverview().totals, active_users: 0 } }),
            ),
      ),
    );
    const { user } = renderApp("/");
    const card = await screen.findByRole("region", { name: "Pemakaian app" });
    // The query client retries once before the error shows.
    const retry = await within(card).findByRole("button", { name: "Coba lagi" }, { timeout: 3000 });
    fail = false;
    await user.click(retry);
    expect(
      await within(card).findByText("Belum ada laporan pemakaian dari app."),
    ).toBeInTheDocument();
  });

  it("shows the numbers, sync, storage, services, AI spend, and newest users", async () => {
    renderApp("/");
    expect(
      await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48"),
    ).toBeInTheDocument();
    expect(screen.getByText("12.480")).toBeInTheDocument();
    expect(screen.getByText(/sisa 87.520/)).toBeInTheDocument();
    expect(screen.getByText("12% kepakai")).toBeInTheDocument();
    const services = screen.getByRole("heading", { name: "Layanan" }).closest("section")!;
    expect(within(services).getAllByText("Nyala")).toHaveLength(2);
    expect(within(services).getByText("Mati")).toBeInTheDocument();
    expect(screen.getByText(/dari US\$5/)).toBeInTheDocument();
    expect(await screen.findByRole("link", { name: /user1@luma.test/ })).toHaveAttribute(
      "href",
      "/users/u1",
    );
    // Burger/nav counts come from the overview.
    expect(screen.getAllByText("9").length).toBeGreaterThan(0);
  });

  it("says when OpenRouter spend is unavailable", async () => {
    server.use(
      http.get(`${API}/overview`, () =>
        HttpResponse.json({ ...overview, ai: { ...overview.ai, spend_usd: null } }),
      ),
    );
    renderApp("/");
    expect(await screen.findByText(/Angka OpenRouter gagal dimuat/)).toBeInTheDocument();
  });

  it("shows the failed state and recovers on retry", async () => {
    let fail = true;
    server.use(
      http.get(`${API}/overview`, () =>
        fail ? apiError(500, "INTERNAL_ERROR") : HttpResponse.json(overview),
      ),
    );
    const { user } = renderApp("/");
    expect(await screen.findByText("Data gagal dimuat", {}, { timeout: 3000 })).toBeInTheDocument();
    fail = false;
    await user.click(screen.getAllByRole("button", { name: "Coba lagi" })[0]!);
    expect(
      await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48"),
    ).toBeInTheDocument();
  });

  it("refetches on the manual refresh button (no polling)", async () => {
    let calls = 0;
    server.use(http.get(`${API}/overview`, () => (calls++, HttpResponse.json(overview))));
    const { user } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    const before = calls;
    await user.click(screen.getByRole("button", { name: "Muat ulang data" }));
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    expect(calls).toBe(before + 1);
  });

  it("keeps the cached numbers when a refresh fails, and toasts the error", async () => {
    let fail = false;
    server.use(
      http.get(`${API}/overview`, () =>
        fail ? apiError(500, "INTERNAL_ERROR") : HttpResponse.json(overview),
      ),
    );
    const calls = recordRequests("/api/overview");
    const { user, queryClient } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    fail = true;
    await user.click(screen.getByRole("button", { name: "Muat ulang data" }));
    // The failed refresh and its one retry are both over once nothing is fetching.
    await waitFor(() => expect(calls.length).toBeGreaterThanOrEqual(3), { timeout: 3000 });
    await waitFor(() => expect(queryClient.isFetching()).toBe(0), { timeout: 3000 });
    expect(screen.getByRole("alert")).toHaveTextContent("Ada yang salah di server.");
    expect(screen.queryByText("Data gagal dimuat")).toBeNull();
    expect(
      within(screen.getByRole("region", { name: "User terdaftar" })).getByText("48"),
    ).toBeInTheDocument();
  });

  it("shows only the error state when metrics fail on first load, and recent users still render", async () => {
    server.use(http.get(`${API}/overview`, () => apiError(500, "INTERNAL_ERROR")));
    renderApp("/");
    const alert = await screen.findByRole("alert", {}, { timeout: 3000 });
    expect(within(alert).getByText("Data gagal dimuat")).toBeInTheDocument();
    expect(within(alert).getByRole("button", { name: "Coba lagi" })).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "User terdaftar" })).toBeNull();
    expect(screen.queryByRole("heading", { name: "Layanan" })).toBeNull();
    expect(await screen.findByRole("link", { name: /user1@luma.test/ })).toHaveAttribute(
      "href",
      "/users/u1",
    );
  });

  it("shows the loading skeleton for recent users while the list is pending", async () => {
    server.use(
      http.get(`${API}/users`, async () => (await delay("infinite"), HttpResponse.json({}))),
    );
    renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    const recent = (await screen.findByRole("heading", { name: "Baru daftar" })).closest(
      "section",
    )!;
    expect(within(recent).getAllByLabelText("Lagi muat daftar user")[0]).toHaveAttribute(
      "aria-busy",
      "true",
    );
    expect(within(recent).queryByRole("link", { name: /user1@luma.test/ })).toBeNull();
  });

  it("shows an error for recent users alone, and its retry recovers", async () => {
    let fail = true;
    server.use(
      http.get(`${API}/users`, () =>
        fail ? apiError(500, "INTERNAL_ERROR") : HttpResponse.json(usersPage([userRow(1)])),
      ),
    );
    const { user } = renderApp("/");
    const recent = (await screen.findByRole("heading", { name: "Baru daftar" })).closest(
      "section",
    )!;
    const alert = await within(recent).findByRole("alert", {}, { timeout: 3000 });
    expect(within(alert).getByText("Data gagal dimuat")).toBeInTheDocument();
    // Metrics are unaffected.
    expect(
      await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48"),
    ).toBeInTheDocument();
    expect(screen.getAllByRole("alert")).toHaveLength(1);
    fail = false;
    await user.click(within(alert).getByRole("button", { name: "Coba lagi" }));
    expect(
      await within(recent).findByRole("link", { name: /user1@luma.test/ }),
    ).toBeInTheDocument();
    expect(within(recent).queryByRole("alert")).toBeNull();
  });

  it("shows an empty state for recent users when nobody signed up", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json(usersPage([]))));
    renderApp("/");
    const recent = (await screen.findByRole("heading", { name: "Baru daftar" })).closest(
      "section",
    )!;
    expect(
      await within(recent).findByRole("heading", { name: "Belum ada user" }),
    ).toBeInTheDocument();
    expect(within(recent).queryByRole("table")).toBeNull();
    expect(within(recent).queryByRole("alert")).toBeNull();
  });
});
