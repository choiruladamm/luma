import { screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

describe("auth", () => {
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
        return HttpResponse.json({ url: "https://accounts.google.com/o/oauth2/v2/auth?x=1", redirect: true });
      }),
    );
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
    const { user } = renderApp("/login");
    await user.click(await screen.findByRole("button", { name: "Masuk pakai Google" }));
    await waitFor(() => expect(assign).toHaveBeenCalledWith("https://accounts.google.com/o/oauth2/v2/auth?x=1"));
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
    server.use(http.post(`${API}/auth/sign-out`, () => ((signedOut = true), HttpResponse.json({ success: true }))));
    const { user, router } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    server.use(http.get(`${API}/auth/get-session`, () => HttpResponse.json(null)));
    await user.click(screen.getByRole("button", { name: "Keluar" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/login"));
    expect(signedOut).toBe(true);
  });

  it("switches the theme from the account menu", async () => {
    const { user } = renderApp("/");
    await user.click(await screen.findByRole("button", { name: "Menu akun: Marcus" }));
    await user.click(screen.getByRole("radio", { name: "Gelap" }));
    expect(screen.getByRole("radio", { name: "Gelap" })).toHaveAttribute("aria-checked", "true");
  });
});
