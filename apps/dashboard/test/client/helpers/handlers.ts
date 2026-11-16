import { HttpResponse, http } from "msw";
import * as fx from "./fixtures";

export const API = "http://localhost/api";

/** Signed-in admin with data on every screen; tests override per case with server.use(...). */
export const defaultHandlers = () => [
  http.get(`${API}/auth/get-session`, () => HttpResponse.json(fx.admin)),
  http.get(`${API}/overview`, () => HttpResponse.json(fx.overview)),
  http.get(`${API}/users`, () => HttpResponse.json(fx.usersPage([fx.user(1), fx.user(2)]))),
  http.get(`${API}/users/:id`, () => HttpResponse.json(fx.userDetail())),
  http.get(`${API}/invites`, ({ request }) => HttpResponse.json(fx.invitesPage(fx.invites.items, new URL(request.url)))),
];

export const apiError = (status: number, code: string) => HttpResponse.json({ error: { code, message: code } }, { status });
