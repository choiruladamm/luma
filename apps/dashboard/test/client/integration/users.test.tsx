import { act, screen, waitFor, within } from "@testing-library/react";
import { delay, HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { elapse, fakeClock } from "../helpers/clock";
import { user, usersPage } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("User", () => {
  // The phone sheet's trigger has no aria-expanded; the desktop popover's does.
  const phoneFilter = () =>
    screen
      .getAllByRole("button", { name: "Filter" })
      .find((b) => !b.hasAttribute("aria-expanded"))!;

  it("lists users with status, key, and totals", async () => {
    server.use(
      http.get(`${API}/users`, () =>
        HttpResponse.json(usersPage([user(1, { banned: true }), user(2, { hasAiKey: true })])),
      ),
    );
    renderApp("/users");
    const table = await screen.findByRole("table", { name: "Daftar user" });
    const rows = within(table).getAllByRole("row");
    expect(within(rows[1]!).getByText("Di-ban")).toBeInTheDocument();
    expect(within(rows[2]!).getByText("Kuota gratis")).toBeInTheDocument();
    expect(screen.getByText(/48 user · 1 di-ban/)).toBeInTheDocument();
    expect(screen.getByText("1–2 dari 2")).toBeInTheDocument();
  });

  it("searches with one debounced request and keeps ?q= in the URL", async () => {
    const queries: (string | null)[] = [];
    server.use(
      http.get(`${API}/users`, ({ request }) => {
        const q = new URL(request.url).searchParams.get("q");
        queries.push(q);
        return HttpResponse.json(
          usersPage(q ? [user(7, { email: "sekar@luma.test" })] : [user(1)]),
        );
      }),
    );
    const { user: u, router } = renderApp("/users");
    await screen.findByRole("table", { name: "Daftar user" });
    await u.type(screen.getByRole("searchbox", { name: "Cari email" }), "sekar");
    expect(await screen.findByRole("link", { name: /sekar\s?@\s?luma\.test/ })).toBeInTheDocument();
    expect(router.state.location.search).toBe("?q=sekar");
    expect(queries.filter((q) => q !== null)).toEqual(["sekar"]);
  });

  it("shows the search-empty state with the query", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json(usersPage([]))));
    renderApp("/users?q=budi@");
    expect(await screen.findByText("Gak ada email yang cocok sama “budi@”")).toBeInTheDocument();
  });

  it("shows the no-users state with a link to invites", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json(usersPage([]))));
    renderApp("/users");
    expect(await screen.findByText("Belum ada user")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Ke Undangan/ })).toHaveAttribute("href", "/invites");
  });

  it("rejects a query over 100 characters without calling the API", async () => {
    const queries: string[] = [];
    server.use(
      http.get(
        `${API}/users`,
        ({ request }) => (queries.push(request.url), HttpResponse.json(usersPage([user(1)]))),
      ),
    );
    const { user: u } = renderApp("/users");
    await screen.findByRole("table", { name: "Daftar user" });
    const box = screen.getByRole("searchbox", { name: "Cari email" });
    await u.click(box);
    fakeClock();
    await u.paste("a".repeat(101));
    expect(await screen.findByText("Maksimal 100 karakter")).toBeInTheDocument();
    expect(box).toHaveAccessibleDescription("Maksimal 100 karakter");
    await elapse(400);
    expect(queries.every((q) => !q.includes("aaaa"))).toBe(true);
  });

  it("pages with numbers, keeping ?page= in the URL", async () => {
    const pages: string[] = [];
    server.use(
      http.get(`${API}/users`, ({ request }) => {
        const page = Number(new URL(request.url).searchParams.get("page") ?? "1");
        pages.push(String(page));
        return HttpResponse.json(
          usersPage(page === 3 ? [user(3)] : [user(1), user(2)], { total: 101, page }),
        );
      }),
    );
    const { user: u, router } = renderApp("/users");
    const nav = await screen.findByRole("navigation", { name: "Paginasi" });
    expect(within(nav).getByText("1–50 dari 101")).toBeInTheDocument();
    expect(within(nav).getByRole("button", { name: "Halaman sebelumnya" })).toBeDisabled();
    await u.click(within(nav).getByRole("button", { name: "Halaman 3" }));
    expect(await screen.findByRole("link", { name: /user3@luma.test/ })).toBeInTheDocument();
    expect(router.state.location.search).toBe("?page=3");
    expect(within(nav).getByRole("button", { name: "Halaman 3" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(within(nav).getByRole("button", { name: "Halaman berikutnya" })).toBeDisabled();
    expect(pages).toEqual(["1", "3"]);
  });

  it("keeps a requested page while its answer loads, even if the previous query had fewer pages", async () => {
    server.use(
      http.get(`${API}/users`, async ({ request }) => {
        const p = new URL(request.url).searchParams;
        if (p.get("status") === "banned") return HttpResponse.json(usersPage([user(9)]));
        await delay(100);
        const page = Number(p.get("page") ?? "1");
        return HttpResponse.json(usersPage([user(page)], { total: 101, page }));
      }),
    );
    const { router } = renderApp("/users?status=banned");
    expect(await screen.findByRole("link", { name: /user9@luma.test/ })).toBeInTheDocument();
    // One page of banned users is still on screen (placeholder) while page 3 loads.
    await act(() => router.navigate("/users?page=3"));
    expect(await screen.findByRole("link", { name: /user3@luma.test/ })).toBeInTheDocument();
    expect(router.state.location.search).toBe("?page=3");
  });

  it("filters and sorts through the URL; a change goes back to page 1", async () => {
    const urls: URLSearchParams[] = [];
    server.use(
      http.get(
        `${API}/users`,
        ({ request }) => (
          urls.push(new URL(request.url).searchParams),
          HttpResponse.json(usersPage([user(1)], { total: 120 }))
        ),
      ),
    );
    const { user: u, router } = renderApp("/users?page=2");
    await screen.findByRole("table", { name: "Daftar user" });

    const filter = screen.getByRole("button", { name: /^Filter$/, expanded: false });
    await u.click(filter);
    const status = within(screen.getByRole("dialog", { name: "Filter user" })).getByRole("button", {
      name: /^Status:/,
    });
    // Opening moves focus into the panel; Esc closes it back to the Filter button.
    expect(status).toHaveFocus();
    await u.keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Filter user" })).toBeNull();
    expect(filter).toHaveFocus();
    await u.click(filter);
    await u.click(
      within(screen.getByRole("dialog", { name: "Filter user" })).getByRole("button", {
        name: /^Status:/,
      }),
    );
    await u.click(screen.getByRole("option", { name: "Di-ban" }));
    await waitFor(() => expect(router.state.location.search).toBe("?status=banned"));
    expect(urls.at(-1)?.get("status")).toBe("banned");

    const header = await screen.findByRole("button", { name: /^File/ });
    await u.click(header);
    await waitFor(() => expect(router.state.location.search).toBe("?status=banned&sort=r2"));
    // The header follows the refetched page, which can land after the URL changes.
    await waitFor(() =>
      expect(screen.getByRole("columnheader", { name: /^File/ })).toHaveAttribute(
        "aria-sort",
        "descending",
      ),
    );
    await u.click(screen.getByRole("button", { name: /^File/ }));
    await waitFor(() =>
      expect(router.state.location.search).toBe("?status=banned&sort=r2&dir=asc"),
    );
    expect(urls.at(-1)?.get("dir")).toBe("asc");

    await u.click(screen.getByRole("button", { name: "Hapus filter Status: Di-ban" }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=r2&dir=asc"));

    await u.click(screen.getAllByRole("button", { name: /^Urutkan:/ })[0]!);
    await u.click(screen.getByRole("option", { name: "Terlama daftar" }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=created&dir=asc"));
  });

  it("says when filters match nothing, with a reset", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json(usersPage([]))));
    const { user: u, router } = renderApp("/users?ai=yes");
    expect(await screen.findByText("Gak ada user yang cocok sama filter ini")).toBeInTheDocument();
    const empty = screen.getByText("Gak ada user yang cocok sama filter ini").closest("div")!;
    await u.click(within(empty).getByRole("button", { name: "Reset" }));
    await waitFor(() => expect(router.state.location.search).toBe(""));
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

  it("a failed refresh replaces the cached rows with the error", async () => {
    let fail = false;
    server.use(
      http.get(`${API}/users`, () =>
        fail ? apiError(429, "RATE_LIMITED") : HttpResponse.json(usersPage([user(1)])),
      ),
    );
    const { queryClient } = renderApp("/users");
    await screen.findByRole("table", { name: "Daftar user" });
    fail = true;
    await act(() => queryClient.refetchQueries({ queryKey: ["users"] }));
    expect(await screen.findByRole("alert")).toBeInTheDocument();
    expect(screen.queryByRole("table", { name: "Daftar user" })).toBeNull();
  });

  it("filters that match nothing win over the search-empty state", async () => {
    server.use(http.get(`${API}/users`, () => HttpResponse.json(usersPage([]))));
    renderApp("/users?q=budi&ai=yes");
    expect(
      await screen.findByRole("heading", { name: "Gak ada user yang cocok sama filter ini" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Gak ada email yang cocok sama “budi”")).toBeNull();
  });

  it.each([
    ["", "Terbaru daftar"],
    // Relevance needs a query; without one the list falls back to newest.
    ["?sort=relevance", "Terbaru daftar"],
    ["?q=sekar", "Paling cocok"],
    ["?q=sekar&sort=created&dir=asc", "Terlama daftar"],
    // A header-picked direction the menu doesn't list gets its own label.
    ["?sort=r2&dir=asc", "File (Naik)"],
  ])("sort menu for %s reads %s", async (search, label) => {
    renderApp(`/users${search}`);
    await screen.findByRole("table", { name: "Daftar user" });
    expect(screen.getByRole("button", { name: /^Urutkan:/ })).toHaveTextContent(label);
  });

  it("desktop filter panel: count badge, reset only filters, Esc in a select keeps the panel", async () => {
    const { user: u, router } = renderApp("/users?ai=yes&status=banned&sort=r2");
    await screen.findByRole("table", { name: "Daftar user" });
    const filter = screen.getByRole("button", { name: /^Filter\s*2$/, expanded: false });
    await u.click(filter);
    const panel = screen.getByRole("dialog", { name: "Filter user" });
    await u.click(within(panel).getByRole("button", { name: /^Status:/ }));
    expect(screen.getByRole("listbox")).toBeInTheDocument();
    await u.keyboard("{Escape}");
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(screen.getByRole("dialog", { name: "Filter user" })).toBeInTheDocument();
    await u.click(within(panel).getByRole("button", { name: "Reset semua" }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=r2"));
    // With nothing on, the panel drops its reset.
    expect(within(panel).queryByRole("button", { name: "Reset semua" })).toBeNull();
  });

  it("phone filter sheet: badge, direction per sort, reset clears sort too, done closes", async () => {
    const { user: u, router } = renderApp("/users?ai=yes&sort=r2&dir=asc");
    await screen.findByRole("table", { name: "Daftar user" });
    await u.click(screen.getByRole("button", { name: "Filter (1)" }));
    const sheet = await screen.findByRole("dialog", { name: "Filter user" });
    const dir = within(sheet).getByRole("radiogroup", { name: "Urutkan" });
    expect(within(dir).getByRole("radio", { name: "Naik" })).toBeChecked();
    expect(within(dir).getByRole("radio", { name: "Turun" })).toBeInTheDocument();

    await u.click(within(sheet).getByRole("button", { name: /^Urutkan:/ }));
    await u.click(screen.getByRole("option", { name: "Daftar" }));
    await waitFor(() => expect(router.state.location.search).toBe("?ai=yes&sort=created&dir=asc"));
    expect(within(sheet).getByRole("radio", { name: "Terlama dulu" })).toBeChecked();
    expect(within(sheet).getByRole("radio", { name: "Terbaru dulu" })).toBeInTheDocument();

    await u.click(within(sheet).getByRole("button", { name: "Reset" }));
    await waitFor(() => expect(router.state.location.search).toBe(""));
    await u.click(within(sheet).getByRole("button", { name: "Selesai" }));
    await waitFor(() => expect(screen.queryByRole("dialog", { name: "Filter user" })).toBeNull());
    expect(phoneFilter()).toBeInTheDocument();
  });

  it("phone filter sheet hides the direction while sorting by relevance", async () => {
    const { user: u } = renderApp("/users?q=sekar");
    await screen.findByRole("table", { name: "Daftar user" });
    await u.click(phoneFilter());
    const sheet = await screen.findByRole("dialog", { name: "Filter user" });
    expect(within(sheet).getByRole("button", { name: /^Urutkan:/ })).toHaveTextContent(
      "Paling cocok",
    );
    expect(within(sheet).queryByRole("radiogroup")).toBeNull();
  });
});
