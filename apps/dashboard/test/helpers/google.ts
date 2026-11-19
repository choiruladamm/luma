import { env } from "cloudflare:test";
import { HttpResponse, http } from "msw";
import { network } from "../setup";

const GOOGLE_TOKEN = "https://oauth2.googleapis.com/token";

const b64url = (value: object) =>
  btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

/**
 * Fake Google code exchange: Better Auth only decodes the idToken after the
 * server-to-server code exchange, so its signature isn't checked here.
 */
export function fakeGoogleToken(claims: { sub: string; email: string }) {
  const idToken = [
    b64url({ alg: "RS256", typ: "JWT" }),
    b64url({
      iss: "https://accounts.google.com",
      aud: env.GOOGLE_CLIENT_ID,
      email_verified: true,
      name: "Admin",
      ...claims,
    }),
    "sig",
  ].join(".");
  network.use(
    http.post(GOOGLE_TOKEN, () =>
      HttpResponse.json({
        access_token: "at",
        id_token: idToken,
        expires_in: 3600,
        token_type: "Bearer",
      }),
    ),
  );
}

export const cookiesFrom = (res: Response) =>
  res.headers.getSetCookie().map((c) => c.split(";")[0]!);
