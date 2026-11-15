import { screen, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { overview } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("Ringkasan", () => {
  it("shows the numbers, sync, storage, services, AI spend, and newest users", async () => {
    renderApp("/");
    expect(await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48")).toBeInTheDocument();
    expect(screen.getByText("12.480")).toBeInTheDocument();
    expect(screen.getByText(/sisa 87.520/)).toBeInTheDocument();
    expect(screen.getByText("12% kepakai")).toBeInTheDocument();
    const services = screen.getByRole("heading", { name: "Layanan" }).closest("section")!;
    expect(within(services).getAllByText("Nyala")).toHaveLength(2);
    expect(within(services).getByText("Mati")).toBeInTheDocument();
    expect(screen.getByText(/dari US\$5/)).toBeInTheDocument();
    expect(await screen.findByRole("link", { name: /user1@luma.test/ })).toHaveAttribute("href", "/users/u1");
    // Burger/nav counts come from the overview.
    expect(screen.getAllByText("9").length).toBeGreaterThan(0);
  });

  it("says when OpenRouter spend is unavailable", async () => {
    server.use(http.get(`${API}/overview`, () => HttpResponse.json({ ...overview, ai: { ...overview.ai, spendUsd: null } })));
    renderApp("/");
    expect(await screen.findByText(/Angka OpenRouter gagal dimuat/)).toBeInTheDocument();
  });

  it("shows the failed state and recovers on retry", async () => {
    let fail = true;
    server.use(http.get(`${API}/overview`, () => (fail ? apiError(500, "INTERNAL_ERROR") : HttpResponse.json(overview))));
    const { user } = renderApp("/");
    expect(await screen.findByText("Data gagal dimuat", {}, { timeout: 3000 })).toBeInTheDocument();
    fail = false;
    await user.click(screen.getAllByRole("button", { name: "Coba lagi" })[0]!);
    expect(await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48")).toBeInTheDocument();
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
});
