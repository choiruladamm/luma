import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { invites } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

type Item = (typeof invites.items)[number];

// user-event installs its own clipboard stub; read it back to see what was copied.
const clipboard = () => navigator.clipboard.readText();

describe("Undangan", () => {
  it("counts and filters from one request", async () => {
    let calls = 0;
    server.use(http.get(`${API}/invites`, () => (calls++, HttpResponse.json(invites))));
    const { user } = renderApp("/invites");
    expect(await screen.findByRole("tab", { name: /Semua\s*3/ })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: /Belum dipakai\s*2/ })).toBeInTheDocument();
    await user.click(screen.getByRole("tab", { name: /Udah dipakai\s*1/ }));
    const table = screen.getByRole("table", { name: "Kode undangan" });
    expect(within(table).getAllByRole("row")).toHaveLength(2);
    expect(within(table).getByRole("link", { name: "user1@luma.test" })).toHaveAttribute("href", "/users/u1");
    expect(calls).toBe(1);
  });

  it("creates a code, shows the ticket, and copies it", async () => {
    let items: Item[] = [...invites.items];
    server.use(
      http.get(`${API}/invites`, () => HttpResponse.json({ items })),
      http.post(`${API}/invites`, async ({ request }) => {
        expect(await request.json()).toEqual({ count: 1 });
        items = [{ code: "LUMA-NEWWW-CODE1", usedBy: null, usedAt: null }, ...items];
        return HttpResponse.json({ codes: ["LUMA-NEWWW-CODE1"] }, { status: 201 });
      }),
    );
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Bikin kode" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("LUMA-NEWWW-CODE1")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Salin kode" }));
    expect(await clipboard()).toBe("LUMA-NEWWW-CODE1");
    expect(await within(dialog).findByRole("button", { name: "Udah disalin" })).toBeInTheDocument();
    expect(within(dialog).getByText("Udah disalin ke clipboard")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Selesai" }));
    expect(await screen.findByRole("tab", { name: /Semua\s*4/ })).toBeInTheDocument();
  });

  it("deletes an unused code after confirming", async () => {
    let items: Item[] = [...invites.items];
    const deleted: string[] = [];
    server.use(
      http.get(`${API}/invites`, () => HttpResponse.json({ items })),
      http.delete(`${API}/invites/:code`, ({ params }) => {
        deleted.push(params.code as string);
        items = items.filter((i) => i.code !== params.code);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Hapus LUMA-AAAAA-BBBBB" }));
    await user.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Hapus kode" }));
    await waitFor(() => expect(deleted).toEqual(["LUMA-AAAAA-BBBBB"]));
    expect(await screen.findByText("Kode LUMA-AAAAA-BBBBB dihapus")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Hapus LUMA-EEEEE-FFFFF" })).toBeNull();
  });

  it("shows 409 when the code got used meanwhile", async () => {
    server.use(http.delete(`${API}/invites/:code`, () => apiError(409, "INVITE_CODE_USED")));
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Hapus LUMA-AAAAA-BBBBB" }));
    await user.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Hapus kode" }));
    expect(await screen.findByText("Kode undangan sudah dipakai.")).toBeInTheDocument();
  });

  it("copies a code from its row", async () => {
    const { user } = renderApp("/invites");
    await user.click(await screen.findByRole("button", { name: "Salin LUMA-CCCCC-DDDDD" }));
    expect(await clipboard()).toBe("LUMA-CCCCC-DDDDD");
    expect(await screen.findByText("Kode LUMA-CCCCC-DDDDD disalin")).toBeInTheDocument();
  });

  it("shows the empty state with a create action", async () => {
    server.use(http.get(`${API}/invites`, () => HttpResponse.json({ items: [] })));
    renderApp("/invites");
    expect(await screen.findByText("Belum ada kode undangan")).toBeInTheDocument();
  });

  it("pages through long lists on the client", async () => {
    const many = Array.from({ length: 25 }, (_, i) => ({ code: `LUMA-K${String(i).padStart(4, "0")}-ZZZZZ`, usedBy: null, usedAt: null }));
    server.use(http.get(`${API}/invites`, () => HttpResponse.json({ items: many })));
    const { user } = renderApp("/invites");
    expect(await screen.findByText("Nampilin 20 dari 25")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Muat lagi" }));
    expect(screen.getByText("Nampilin 25 dari 25")).toBeInTheDocument();
  });
});
