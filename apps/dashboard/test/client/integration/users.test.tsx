import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { user } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("User", () => {
  it("lists users with status, key, and totals", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json({ items: [user(1, { banned: true }), user(2, { hasAiKey: true })], nextCursor: null })));
    renderApp("/users");
    const table = await screen.findByRole("table", { name: "Daftar user" });
    const rows = within(table).getAllByRole("row");
    expect(within(rows[1]!).getByText("Di-ban")).toBeInTheDocument();
    expect(within(rows[2]!).getByText("Kuota gratis")).toBeInTheDocument();
    expect(screen.getByText(/48 user · 1 di-ban/)).toBeInTheDocument();
    expect(screen.getByText("Nampilin 2 dari 48")).toBeInTheDocument();
  });

  it("searches by email prefix with one debounced request and keeps ?q= in the URL", async () => {
    const queries: (string | null)[] = [];
    server.use(
      http.get(`${API}/users`, ({ request }) => {
        const q = new URL(request.url).searchParams.get("q");
        queries.push(q);
        return HttpResponse.json({ items: q ? [user(7, { email: "sekar@luma.test" })] : [user(1)], nextCursor: null });
      }),
    );
    const { user: u, router } = renderApp("/users");
    await screen.findByRole("table", { name: "Daftar user" });
    await u.type(screen.getByRole("searchbox", { name: "Cari email" }), "sekar");
    expect(await screen.findByRole("link", { name: /sekar@luma.test/ })).toBeInTheDocument();
    expect(router.state.location.search).toBe("?q=sekar");
    expect(queries.filter((q) => q !== null)).toEqual(["sekar"]);
  });

  it("shows the search-empty state with the query", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json({ items: [], nextCursor: null })));
    renderApp("/users?q=budi@");
    expect(await screen.findByText("Gak ada email yang cocok sama “budi@”")).toBeInTheDocument();
  });

  it("shows the no-users state with a link to invites", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json({ items: [], nextCursor: null })));
    renderApp("/users");
    expect(await screen.findByText("Belum ada user")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Ke Undangan/ })).toHaveAttribute("href", "/invites");
  });

  it("rejects a query over 100 characters without calling the API", async () => {
    const queries: string[] = [];
    server.use(http.get(`${API}/users`, ({ request }) => (queries.push(request.url), HttpResponse.json({ items: [user(1)], nextCursor: null }))));
    const { user: u } = renderApp("/users");
    await screen.findByRole("table", { name: "Daftar user" });
    const box = screen.getByRole("searchbox", { name: "Cari email" });
    await u.click(box);
    await u.paste("a".repeat(101));
    expect(await screen.findByText("Maksimal 100 karakter")).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 400));
    expect(queries.every((q) => !q.includes("aaaa"))).toBe(true);
  });

  it("loads the next page with the cursor", async () => {
    server.use(
      http.get(`${API}/users`, ({ request }) => {
        const cursor = new URL(request.url).searchParams.get("cursor");
        return HttpResponse.json(cursor === "c1" ? { items: [user(3)], nextCursor: null } : { items: [user(1), user(2)], nextCursor: "c1" });
      }),
    );
    const { user: u } = renderApp("/users");
    await u.click(await screen.findByRole("button", { name: "Muat lagi" }));
    expect(await screen.findByRole("link", { name: /user3@luma.test/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Muat lagi" })).toBeNull();
  });

  it("navigates to the detail from a row", async () => {
    const { user: u, router } = renderApp("/users");
    await u.click(await screen.findByRole("link", { name: /user1@luma.test/ }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/users/u1"));
  });

  it("shows the failed state", async () => {
    server.use(http.get(`${API}/users`, () => apiError(500, "INTERNAL_ERROR")));
    renderApp("/users");
    expect(await screen.findByText("Data gagal dimuat", {}, { timeout: 3000 })).toBeInTheDocument();
  });
});
