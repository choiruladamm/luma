import { screen } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { afterEach, describe, expect, it, vi } from "vitest";
import { user } from "../helpers/fixtures";
import { API } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

afterEach(() => vi.restoreAllMocks());

describe("error screens", () => {
  it("a bare 401 (Cloudflare Access session expired) reloads the page; the worker's 401 goes to login", async () => {
    const seen: (string | null)[] = [];
    server.use(
      http.get(`${API}/overview`, ({ request }) => (seen.push(request.headers.get("x-requested-with")), new HttpResponse("", { status: 401 }))),
    );
    const { onAccessExpired, router } = renderApp("/");
    await vi.waitFor(() => expect(onAccessExpired).toHaveBeenCalled());
    expect(seen[0]).toBe("XMLHttpRequest");
    expect(router.state.location.pathname).toBe("/");
  });

  it("an unknown address shows 'not found' inside the shell", async () => {
    renderApp("/nope");
    expect(await screen.findByRole("heading", { name: "Halaman gak ditemukan" })).toBeInTheDocument();
    expect(screen.getAllByRole("navigation", { name: "Navigasi admin" }).length).toBeGreaterThan(0);
    expect(screen.getByRole("link", { name: /Ke Ringkasan/ })).toHaveAttribute("href", "/");
  });

  it("a screen that crashes shows the error card in the shell, with reload and details", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    // A malformed page (total missing) used to throw inside the footer and blank the app.
    server.use(http.get(`${API}/users`, () => HttpResponse.json({ items: [user(1)], total: null, page: 1, pageCount: null })));
    renderApp("/users");
    expect(await screen.findByRole("alert")).toHaveTextContent("Ada yang error");
    expect(screen.getByRole("button", { name: "Muat ulang" })).toBeInTheDocument();
    expect(screen.getByText("Detail teknis")).toBeInTheDocument();
    expect(screen.getAllByRole("navigation", { name: "Navigasi admin" }).length).toBeGreaterThan(0);
  });
});
