import { screen, waitFor, within } from "@testing-library/react";
import { focusManager } from "@tanstack/react-query";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { admin as fixtureAdmin } from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("auth", () => {
  it("rechecks the session on tab focus only once it's an hour old (that slides it server side)", async () => {
    let calls = 0;
    server.use(
      http.get(`${API}/auth/get-session`, () => (calls++, HttpResponse.json(fixtureAdmin))),
    );
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      renderApp("/");
      expect(
        await screen.findByRole("heading", { name: "Ringkasan", level: 1 }),
      ).toBeInTheDocument();
      expect(calls).toBe(1);
      const refocus = () => {
        focusManager.setFocused(false);
        focusManager.setFocused(true);
      };
      vi.setSystemTime(Date.now() + 30 * 60_000);
      refocus();
      await new Promise((r) => setTimeout(r, 50));
      expect(calls).toBe(1);
      vi.setSystemTime(Date.now() + 31 * 60_000);
      refocus();
      await waitFor(() => expect(calls).toBe(2));
    } finally {
      focusManager.setFocused(undefined);
      vi.useRealTimers();
    }
  });

  it("sends a signed-out visitor to /login", async () => {
    server.use(http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)));
    const { router } = renderApp("/users");
    expect(await screen.findByRole("heading", { name: "Masuk" })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/login");
  });

  it.each([
    ["FORBIDDEN", "Not an admin", "Akun ini bukan admin"],
    ["FORBIDDEN", "Dashboard cannot create accounts", "Akun ini belum terdaftar di Luma"],
    ["state_mismatch", "", "Gagal masuk"],
  ])("explains /login?error=%s (%s)", async (code, detail, title) => {
    server.use(http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)));
    renderApp(`/login?error=${code}&error_description=${encodeURIComponent(detail)}`);
    expect(await screen.findByText(title)).toBeInTheDocument();
  });

  it("starts Google sign-in and follows the URL the worker returns", async () => {
    server.use(
      http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)),
      http.post(`${API}/auth/sign-in/social`, async ({ request }) => {
        expect(await request.json()).toEqual({ provider: "google", callbackURL: "/" });
        return HttpResponse.json({
          url: "https://accounts.google.com/o/oauth2/v2/auth?x=1",
          redirect: true,
        });
      }),
    );
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
    const { user } = renderApp("/login");
    await user.click(await screen.findByRole("button", { name: "Masuk pakai Google" }));
    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith("https://accounts.google.com/o/oauth2/v2/auth?x=1"),
    );
  });

  it("coming back from Google (back/forward cache) the button is usable again", async () => {
    server.use(
      http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)),
      http.post(`${API}/auth/sign-in/social`, () =>
        HttpResponse.json({
          url: "https://accounts.google.com/o/oauth2/v2/auth?x=1",
          redirect: true,
        }),
      ),
    );
    vi.spyOn(window.location, "assign").mockImplementation(() => {});
    const { user } = renderApp(
      "/login?error=FORBIDDEN&error_description=Dashboard+cannot+create+accounts",
    );
    const button = await screen.findByRole("button", { name: "Masuk pakai Google" });
    await user.click(button);
    // Left for Google: the button stays busy so it can't be pressed twice.
    await waitFor(() => expect(button).toHaveAttribute("aria-busy", "true"));
    // Back: the browser restores this page from its back/forward cache.
    window.dispatchEvent(Object.assign(new Event("pageshow"), { persisted: true }));
    await waitFor(() => expect(button).not.toHaveAttribute("aria-busy"));
    expect(button).toBeEnabled();
    expect(screen.getByText("Akun ini belum terdaftar di Luma")).toBeInTheDocument();
  });

  it("sends a signed-in admin from /login to the overview", async () => {
    renderApp("/login");
    expect(await screen.findByRole("heading", { name: "Ringkasan" })).toBeInTheDocument();
  });

  it("shows a retry, not the login page, when the session check fails", async () => {
    server.use(http.get(`${API}/auth/get-session`, () => apiError(429, "RATE_LIMITED")));
    const { router } = renderApp("/");
    expect(await screen.findByText("Sesi gagal dicek")).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/");
  });

  it("goes to /login when an API call answers 401 (session expired)", async () => {
    server.use(http.get(`${API}/overview`, () => apiError(401, "UNAUTHORIZED")));
    const { router } = renderApp("/");
    await waitFor(() => expect(router.state.location.pathname).toBe("/login"));
  });

  it("signs out from the account menu", async () => {
    let signedOut = false;
    server.use(
      http.post(
        `${API}/auth/sign-out`,
        () => ((signedOut = true), HttpResponse.json({ success: true })),
      ),
    );
    const { user, router } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    server.use(http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)));
    await user.click(screen.getByRole("button", { name: "Keluar" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/login"));
    expect(signedOut).toBe(true);
  });

  it("closes the account menu on an outside click and on Esc", async () => {
    const { user } = renderApp("/");
    const trigger = await screen.findByRole("button", { name: "Menu akun: Marcus" });
    await user.click(trigger);
    expect(screen.getByRole("group", { name: "Menu akun" })).toBeInTheDocument();
    // Outside the menu (the page heading), not the scrim: the scrim can't cover the page inside the floating nav.
    await user.click(screen.getByRole("heading", { name: "Ringkasan" }));
    expect(screen.queryByRole("group", { name: "Menu akun" })).toBeNull();
    await user.click(trigger);
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("group", { name: "Menu akun" })).toBeNull();
    expect(trigger).toHaveAttribute("aria-expanded", "false");
  });

  it("switches the theme from the account menu", async () => {
    const { user } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    await user.click(screen.getByRole("radio", { name: "Gelap" }));
    expect(screen.getByRole("radio", { name: "Gelap" })).toHaveAttribute("aria-checked", "true");
  });

  it("switches the language from the account menu without calling the API", async () => {
    const { user } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    let requests = 0;
    const count = () => requests++;
    server.events.on("request:start", count);
    await user.click(screen.getByRole("radio", { name: "English" }));
    expect(await screen.findByRole("radio", { name: "English" })).toHaveAttribute(
      "aria-checked",
      "true",
    );
    expect(screen.getByRole("button", { name: "Account menu: Marcus" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
    await waitFor(() => expect(document.documentElement.lang).toBe("en"));
    expect(JSON.parse(localStorage.getItem("luma-admin-ui")!).state.lang).toBe("en");

    await user.click(screen.getByRole("radio", { name: "Indonesia" }));
    expect(await screen.findByRole("button", { name: "Keluar" })).toBeInTheDocument();
    await waitFor(() => expect(document.documentElement.lang).toBe("id"));
    server.events.removeListener("request:start", count);
    expect(requests).toBe(0);
  });
});
