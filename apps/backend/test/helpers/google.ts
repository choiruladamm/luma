import { env } from "cloudflare:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { HttpResponse, http } from "msw";
import { network } from "../setup";

const GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs";
const KID = "luma-test-kid";

/** The web client ID in the dev env's `GOOGLE_CLIENT_IDS` (the first one). */
export const WEB_CLIENT_ID = env.GOOGLE_CLIENT_IDS.split(",")[0]!.trim();

export type GoogleClaims = Record<string, unknown> & { email?: string; sub?: string };

/**
 * Fake Google: a test RSA-key JWKS in MSW + an RS256 idToken signed by that
 * key. Better Auth verifies it like a real token (iss, aud, exp, signature).
 * Call in every test; handlers are reset automatically after each test.
 */
export async function fakeGoogle() {
  const { privateKey, publicKey } = await generateKeyPair("RS256", { extractable: true });
  const jwk = { ...(await exportJWK(publicKey)), kid: KID, alg: "RS256", use: "sig" };
  let certFetches = 0;
  network.use(
    http.get(GOOGLE_CERTS, () => {
      certFetches++;
      return HttpResponse.json({ keys: [jwk] });
    }),
  );

  /** Signed idToken; `aud` / `iss` / `exp` can be overridden for failure cases. */
  const idToken = async (
    claims: GoogleClaims = {},
    { aud = WEB_CLIENT_ID, iss = "https://accounts.google.com", expiresIn = "10m" } = {},
  ) =>
    new SignJWT({
      email: "adam@gmail.test",
      email_verified: true,
      name: "Adam",
      picture: "https://lh3.googleusercontent.com/a/test",
      ...claims,
    })
      .setProtectedHeader({ alg: "RS256", kid: KID })
      .setSubject(claims.sub ?? `google-${crypto.randomUUID()}`)
      .setIssuer(iss)
      .setAudience(aud)
      .setIssuedAt()
      .setExpirationTime(expiresIn)
      .sign(privateKey);

  return { idToken, certFetches: () => certFetches };
}

/** A different key (not Google's): its signature must be rejected. */
export async function foreignToken(claims: GoogleClaims = {}) {
  const { privateKey } = await generateKeyPair("RS256");
  return new SignJWT({ email: "mallory@gmail.test", email_verified: true, ...claims })
    .setProtectedHeader({ alg: "RS256", kid: KID })
    .setSubject("google-mallory")
    .setIssuer("https://accounts.google.com")
    .setAudience(WEB_CLIENT_ID)
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(privateKey);
}
