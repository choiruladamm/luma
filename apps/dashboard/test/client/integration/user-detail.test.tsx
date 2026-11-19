import { act, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { overview, userDetail } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("Detail user", () => {
  it("shows profile, sign-in provider, invite, usage, AI quota, devices", async () => {
    renderApp("/users/u1");
    expect(
      await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ }),
    ).toBeInTheDocument();
    expect(screen.getByText("Google")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "LUMA-7KQ2" })).toHaveAttribute("href", "/invites");
    expect(screen.getByText("App Luma 0.3.0")).toBeInTheDocument();
    expect(screen.getAllByText("Kuota AI gratis").length).toBeGreaterThan(0);
    expect(screen.getByText(/key berlaku sampai/)).toBeInTheDocument();
  });

  it("bans after confirming, with the product's copy, then offers unban from the toast", async () => {
    let banned = false;
    const calls: string[] = [];
    server.use(
      http.get(`${API}/users/:id`, () => HttpResponse.json(userDetail({ banned }))),
      http.post(`${API}/users/:id/ban`, ({ request }) => {
        calls.push(`ban ${request.headers.get("content-type")}`);
        banned = true;
        return HttpResponse.json({ banned: true, keyRevoked: true });
      }),
      http.post(`${API}/users/:id/unban`, () => {
        calls.push("unban");
        banned = false;
        return HttpResponse.json({ banned: false });
      }),
    );
    const { user } = renderApp("/users/u1");
    await user.click(await screen.findByRole("button", { name: "Ban user" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("Masuk, backup, dan sync tetap jalan")).toBeInTheDocument();
    expect(within(dialog).queryByText(/gak bisa masuk/)).toBeNull();
    await user.click(within(dialog).getByRole("button", { name: "Ban user" }));
    expect(await screen.findByText("User ini lagi di-ban")).toBeInTheDocument();
    expect(calls).toEqual(["ban application/json"]);
    const toastEl = (await screen.findByText("sekar.ayu@gmail.com di-ban")).closest<HTMLElement>(
      "[role=status]",
    )!;
    await user.click(within(toastEl).getByRole("button", { name: "Buka ban" }));
    await waitFor(() => expect(calls).toContain("unban"));
    await waitFor(() => expect(screen.queryByText("User ini lagi di-ban")).toBeNull());
  });

  it("cancels the ban dialog without calling the API", async () => {
    const ban = vi.fn<() => void>();
    server.use(http.post(`${API}/users/:id/ban`, () => (ban(), HttpResponse.json({}))));
    const { user } = renderApp("/users/u1");
    await user.click(await screen.findByRole("button", { name: "Ban user" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", { name: "Batal" }),
    );
    expect(ban).not.toHaveBeenCalled();
  });

  it("shows OpenRouter's 502 as an error toast and keeps the user active", async () => {
    server.use(http.post(`${API}/users/:id/ban`, () => apiError(502, "OPENROUTER_FAILED")));
    const { user } = renderApp("/users/u1");
    await user.click(await screen.findByRole("button", { name: "Ban user" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", { name: "Ban user" }),
    );
    expect(await screen.findByText("OpenRouter gagal dihubungi. Coba lagi.")).toBeInTheDocument();
    expect(screen.queryByText("User ini lagi di-ban")).toBeNull();
  });

  it("unbans from the banner of a banned user", async () => {
    let banned = true;
    server.use(
      http.get(`${API}/users/:id`, () => HttpResponse.json(userDetail({ banned }))),
      http.post(
        `${API}/users/:id/unban`,
        () => ((banned = false), HttpResponse.json({ banned: false })),
      ),
    );
    const { user } = renderApp("/users/u1");
    await user.click(await screen.findByRole("button", { name: "Buka ban" }));
    await waitFor(() => expect(screen.queryByText("User ini lagi di-ban")).toBeNull());
    expect(screen.getByRole("button", { name: "Ban user" })).toBeInTheDocument();
  });

  it("copies the email", async () => {
    const { user } = renderApp("/users/u1");
    // The loading skeleton shows the same button disabled; wait for the profile.
    await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ });
    // Desktop button + phone icon button share the name; CSS shows one of them.
    await user.click(screen.getAllByRole("button", { name: "Salin email" })[0]!);
    expect(await navigator.clipboard.readText()).toBe("sekar.ayu@gmail.com");
    expect(await screen.findByText("Email disalin")).toBeInTheDocument();
  });

  it("shows a not-found state for an unknown user", async () => {
    server.use(http.get(`${API}/users/:id`, () => apiError(404, "NOT_FOUND")));
    renderApp("/users/gak-ada");
    expect(await screen.findByText("User gak ditemukan")).toBeInTheDocument();
  });

  // The loading skeleton has the same heading; wait for the profile first.
  const aiCard = async () => {
    await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ });
    return screen.getByRole("heading", { level: 2, name: "Kuota AI gratis" }).closest("section")!;
  };

  it("says there is no AI key, with no usage bar or expiry", async () => {
    server.use(
      http.get(`${API}/users/:id`, () =>
        HttpResponse.json(userDetail({ hasAiKey: false, ai: null })),
      ),
    );
    renderApp("/users/u1");
    const card = await aiCard();
    expect(within(card).getByText("Gak pakai")).toBeInTheDocument();
    expect(within(card).getByText(/Belum minta key subsidi/)).toBeInTheDocument();
    expect(within(card).queryByRole("progressbar")).toBeNull();
    expect(within(card).queryByText(/key berlaku sampai/)).toBeNull();
  });

  it("shows the key expiry without a usage bar when OpenRouter usage is unavailable", async () => {
    server.use(
      http.get(`${API}/users/:id`, () =>
        HttpResponse.json(
          userDetail({
            ai: { limit: 0.02, usageDaily: null, expiresAt: "2026-12-14T00:00:00.000Z" },
          }),
        ),
      ),
    );
    renderApp("/users/u1");
    const card = await aiCard();
    expect(within(card).getByText("—")).toBeInTheDocument();
    expect(within(card).getByText(/Pemakaian gagal dimuat dari OpenRouter/)).toBeInTheDocument();
    expect(within(card).getByText(/key berlaku sampai/)).toBeInTheDocument();
    expect(within(card).queryByRole("progressbar")).toBeNull();
    expect(within(card).queryByText(/hari ini dari/)).toBeNull();
  });

  it("shows an empty usage bar for zero usage today", async () => {
    server.use(
      http.get(`${API}/users/:id`, () =>
        HttpResponse.json(
          userDetail({ ai: { limit: 0.02, usageDaily: 0, expiresAt: "2026-12-14T00:00:00.000Z" } }),
        ),
      ),
    );
    renderApp("/users/u1");
    const card = await aiCard();
    expect(
      within(card).getByRole("progressbar", { name: "Pemakaian AI hari ini" }),
    ).toHaveAttribute("aria-valuenow", "0");
    expect(within(card).getByText(/hari ini dari/)).toBeInTheDocument();
    expect(within(card).getByText(/key berlaku sampai/)).toBeInTheDocument();
    expect(within(card).queryByText(/Pemakaian gagal dimuat/)).toBeNull();
  });

  it("shows the file-share bar only once the overview is cached", async () => {
    server.use(http.get(`${API}/overview`, () => HttpResponse.json(overview)));
    renderApp("/users/u1");
    expect(
      await screen.findByRole("progressbar", { name: "Bagian dari semua file di server" }),
    ).toBeInTheDocument();
  });

  it("shows an error state for a server failure, and retry recovers", async () => {
    let fail = true;
    server.use(
      http.get(`${API}/users/:id`, () =>
        fail ? apiError(500, "INTERNAL_ERROR") : HttpResponse.json(userDetail()),
      ),
    );
    const { user } = renderApp("/users/u1");
    const alert = await screen.findByRole("alert", {}, { timeout: 3000 });
    expect(within(alert).getByText("Data gagal dimuat")).toBeInTheDocument();
    expect(screen.queryByText("User gak ditemukan")).toBeNull();
    expect(screen.queryByRole("button", { name: "Ban user" })).toBeNull();
    fail = false;
    await user.click(within(alert).getByRole("button", { name: "Coba lagi" }));
    expect(
      await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  describe("a refresh over cached detail", () => {
    const failNextLoads = (fail: () => Response | undefined) =>
      server.use(http.get(`${API}/users/:id`, () => fail() ?? HttpResponse.json(userDetail())));

    it("keeps the profile and toasts a server failure", async () => {
      let failing = false;
      failNextLoads(() => (failing ? apiError(429, "RATE_LIMITED") : undefined));
      const { queryClient } = renderApp("/users/u1");
      await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ });
      failing = true;
      await act(() => queryClient.refetchQueries());
      expect(await screen.findByRole("alert")).toHaveTextContent(
        "Terlalu banyak permintaan. Coba lagi sebentar.",
      );
      expect(
        screen.getByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ }),
      ).toBeInTheDocument();
      expect(screen.queryByText("Data gagal dimuat")).toBeNull();
    });

    it("switches to not-found when the user is gone", async () => {
      let gone = false;
      failNextLoads(() => (gone ? apiError(404, "NOT_FOUND") : undefined));
      const { queryClient } = renderApp("/users/u1");
      await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ });
      gone = true;
      await act(() => queryClient.refetchQueries());
      expect(await screen.findByText("User gak ditemukan")).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "Ban user" })).toBeNull();
    });
  });
});
