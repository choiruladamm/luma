import { act, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { elapse, fakeClock } from "../helpers/clock";
import { invites, invitesPage } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

type Item = (typeof invites.items)[number];

// user-event installs its own clipboard stub; read it back to see what was copied.
const clipboard = () => navigator.clipboard.readText();

describe("Undangan", () => {
  it("counts per status tab; picking a tab asks the worker for that status", async () => {
    const statuses: (string | null)[] = [];
    server.use(
      http.get(
        `${API}/invites`,
        ({ request }) => (
          statuses.push(new URL(request.url).searchParams.get("status")),
          HttpResponse.json(invitesPage(invites.items, new URL(request.url)))
        ),
      ),
    );
    const { user } = renderApp("/invites");
    expect((await screen.findAllByRole("tab", { name: /Semua\s*3/ }))[0]!).toHaveAttribute(
      "aria-selected",
      "true",
    );
    expect(screen.getAllByRole("tab", { name: /Belum dipakai\s*2/ })[0]!).toBeInTheDocument();
    await user.click(screen.getAllByRole("tab", { name: /Udah dipakai\s*1/ })[0]!);
    await waitFor(() =>
      expect(
        within(screen.getByRole("table", { name: "Kode undangan" })).getAllByRole("row"),
      ).toHaveLength(2),
    );
    const table = screen.getByRole("table", { name: "Kode undangan" });
    expect(within(table).getByRole("link", { name: "user1@luma.test" })).toHaveAttribute(
      "href",
      "/users/u1",
    );
    expect(statuses).toEqual([null, "used"]);
  });

  it("creates a code, shows the ticket, and copies it", async () => {
    let items: Item[] = [...invites.items];
    server.use(
      http.get(`${API}/invites`, ({ request }) =>
        HttpResponse.json(invitesPage(items, new URL(request.url))),
      ),
      http.post(`${API}/invites`, async ({ request }) => {
        expect(await request.json()).toEqual({ count: 1 });
        items = [
          {
            code: "LUMA-NEWWW-CODE1",
            createdAt: "2026-11-15T03:00:00.000Z",
            usedBy: null,
            usedAt: null,
          },
          ...items,
        ];
        return HttpResponse.json(
          { codes: ["LUMA-NEWWW-CODE1"], createdAt: "2026-11-15T03:00:00.000Z" },
          { status: 201 },
        );
      }),
    );
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Bikin kode" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("LUMA-NEWWW-CODE1")).toBeInTheDocument();
    // The stored date from the worker, not the browser clock.
    expect(within(dialog).getByText(/^Dibuat 15 Nov 2026/)).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Salin kode" }));
    expect(await clipboard()).toBe("LUMA-NEWWW-CODE1");
    expect(await within(dialog).findByRole("button", { name: "Udah disalin" })).toBeInTheDocument();
    expect(within(dialog).getByText("Udah disalin ke clipboard")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Selesai" }));
    expect((await screen.findAllByRole("tab", { name: /Semua\s*4/ }))[0]!).toBeInTheDocument();
  });

  it("deletes an unused code after confirming", async () => {
    let items: Item[] = [...invites.items];
    const deleted: string[] = [];
    server.use(
      http.get(`${API}/invites`, ({ request }) =>
        HttpResponse.json(invitesPage(items, new URL(request.url))),
      ),
      http.delete(`${API}/invites/:code`, ({ params }) => {
        deleted.push(params.code as string);
        items = items.filter((i) => i.code !== params.code);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Hapus LUMA-AAAAA-BBBBB" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", { name: "Hapus kode" }),
    );
    await waitFor(() => expect(deleted).toEqual(["LUMA-AAAAA-BBBBB"]));
    expect(await screen.findByText("Kode LUMA-AAAAA-BBBBB dihapus")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Hapus LUMA-EEEEE-FFFFF" })).toBeNull();
  });

  it("shows 409 when the code got used meanwhile", async () => {
    server.use(http.delete(`${API}/invites/:code`, () => apiError(409, "INVITE_CODE_USED")));
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Hapus LUMA-AAAAA-BBBBB" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", { name: "Hapus kode" }),
    );
    expect(await screen.findByText("Kode undangan sudah dipakai.")).toBeInTheDocument();
  });

  it("copies a code from its row", async () => {
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Salin LUMA-CCCCC-DDDDD" }));
    expect(await clipboard()).toBe("LUMA-CCCCC-DDDDD");
    expect(await screen.findByText("Kode LUMA-CCCCC-DDDDD disalin")).toBeInTheDocument();
  });

  it("shows when each code was made (— for codes from before it was recorded) and sorts by it", async () => {
    const { user, router } = renderApp("/invites");
    const table = await screen.findByRole("table", { name: "Kode undangan" });
    const cells = (code: string) =>
      within(within(table).getByText(code).closest("tr")!)
        .getAllByRole("cell")
        .map((c) => c.textContent);
    expect(cells("LUMA-AAAAA-BBBBB")[1]).toBe("14 Nov 2026");
    expect(cells("LUMA-CCCCC-DDDDD")[1]).toBe("—");
    await user.click(screen.getByRole("button", { name: /^Dibuat/ }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=createdAt"));
    await user.click(screen.getByRole("button", { name: /^Urutkan:/ }));
    await user.click(screen.getByRole("option", { name: "Terlama dibuat" }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=createdAt&dir=asc"));
  });

  it("shows the empty state with a create action", async () => {
    server.use(
      http.get(`${API}/invites`, ({ request }) =>
        HttpResponse.json(invitesPage([], new URL(request.url))),
      ),
    );
    renderApp("/invites");
    expect(await screen.findByText("Belum ada kode undangan")).toBeInTheDocument();
  });

  it("pages with numbers through the worker, keeping ?page= in the URL", async () => {
    const many = Array.from({ length: 25 }, (_, i) => ({
      code: `LUMA-K${String(i).padStart(4, "0")}-ZZZZZ`,
      createdAt: null,
      usedBy: null,
      usedAt: null,
    }));
    server.use(
      http.get(`${API}/invites`, ({ request }) =>
        HttpResponse.json(invitesPage(many, new URL(request.url))),
      ),
    );
    const { user, router } = renderApp("/invites");
    expect(await screen.findByText("1–20 dari 25")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Halaman 2" }));
    expect(await screen.findByText("21–25 dari 25")).toBeInTheDocument();
    expect(router.state.location.search).toBe("?page=2");
  });

  it("search field follows links and back, and a pending draft can't overwrite the navigation", async () => {
    const { user, router } = renderApp("/invites");
    const box = await screen.findByRole("searchbox", { name: "Cari kode atau email" });
    await user.type(box, "eeeee");
    await waitFor(() => expect(router.state.location.search).toBe("?q=eeeee"));

    fakeClock();
    await user.type(box, "zzz");
    await act(() => router.navigate("/invites?q=aaaaa"));
    await waitFor(() => expect(box).toHaveValue("aaaaa"));
    // Past the 300ms debounce: the dropped "eeeeezzz" draft never reaches the URL.
    await elapse(400);
    expect(router.state.location.search).toBe("?q=aaaaa");
    expect(box).toHaveValue("aaaaa");

    await act(() => router.navigate(-1));
    await waitFor(() => expect(box).toHaveValue("eeeee"));
    expect(router.state.location.search).toBe("?q=eeeee");
  });

  it("searches (debounced, in the URL), filters by used-within, and sorts through the worker", async () => {
    const queries: URLSearchParams[] = [];
    server.use(
      http.get(
        `${API}/invites`,
        ({ request }) => (
          queries.push(new URL(request.url).searchParams),
          HttpResponse.json(invitesPage(invites.items, new URL(request.url)))
        ),
      ),
    );
    const { user, router } = renderApp("/invites");
    const box = await screen.findByRole("searchbox", { name: "Cari kode atau email" });
    await user.type(box, "eeeee-ff");
    await waitFor(() => expect(router.state.location.search).toBe("?q=eeeee-ff"));
    // The previous list stays up while the search loads (keepPreviousData): wait for it to go.
    await waitFor(() => expect(screen.queryByText("LUMA-AAAAA-BBBBB")).toBeNull());
    expect(screen.getAllByText("LUMA-EEEEE-FFFFF")).not.toHaveLength(0);
    expect(queries.filter((q) => q.get("q")).map((q) => q.get("q"))).toEqual(["eeeee-ff"]);
    await user.clear(box);
    await user.type(box, "nobody");
    expect(
      await screen.findByText("Gak ada kode atau email yang cocok sama “nobody”"),
    ).toBeInTheDocument();
    await user.clear(box);
    await waitFor(() => expect(router.state.location.search).toBe(""));

    // "Used within" selects the Used tab; the Unused tab clears it.
    await user.click(screen.getByRole("button", { name: /^Dipakai dalam:/ }));
    await user.click(screen.getByRole("option", { name: "7 hari" }));
    await waitFor(() => expect(router.state.location.search).toBe("?status=used&usedWithin=7d"));
    await user.click(screen.getAllByRole("tab", { name: /Belum dipakai/ })[0]!);
    await waitFor(() => expect(router.state.location.search).toBe("?status=unused"));

    await user.click(screen.getAllByRole("tab", { name: /Semua/ })[0]!);
    await user.click(await screen.findByRole("button", { name: /^Kode/ }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=code"));
    // The header follows the refetched page, which can land after the URL changes.
    await waitFor(() =>
      expect(screen.getByRole("columnheader", { name: /^Kode/ })).toHaveAttribute(
        "aria-sort",
        "descending",
      ),
    );
    await user.click(screen.getByRole("button", { name: /^Urutkan:/ }));
    await user.click(screen.getByRole("option", { name: "Terlama dipakai" }));
    await waitFor(() => expect(router.state.location.search).toBe("?sort=usedAt&dir=asc"));
  });
});
