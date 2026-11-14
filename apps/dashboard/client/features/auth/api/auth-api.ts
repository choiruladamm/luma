// Better Auth endpoints aren't part of AppType (allowlisted in the worker), so plain fetch.
import { ApiError, toApiError } from "../../../lib/api-error";

export type Session = {
  user: { id: string; email: string; name: string; image: string | null };
  session: { expiresAt: string };
} | null;

const authFetch = async (path: string, init?: RequestInit) => {
  let res: Response;
  try {
    res = await fetch(`/api/auth/${path}`, init);
  } catch {
    throw new ApiError(0, "NETWORK");
  }
  if (!res.ok) throw await toApiError(res);
  return res;
};

const postJson = (path: string, body: unknown) =>
  authFetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

/** Current admin session, `null` when signed out. */
export const getSession = async (): Promise<Session> => (await authFetch("get-session")).json();

/** Start Google sign-in: the worker answers with the Google URL; errors come back as /login?error=…. */
export async function signInWithGoogle() {
  const { url } = (await (await postJson("sign-in/social", { provider: "google", callbackURL: "/" })).json()) as {
    url: string;
  };
  window.location.assign(url);
}

export const signOut = async () => {
  await postJson("sign-out", {});
};
