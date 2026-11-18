import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { userDetail } from "../helpers/fixtures";
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
    const ban = vi.fn();
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
});
