import { z } from "zod";

// Wire shapes of `/v2/auth/*`: Better Auth answers camelCase and the Worker converts at the edge.
// Better Auth endpoints the app uses (`AUTH_PATHS` in apps/backend/src/features/auth/routes.ts).
// Requests carry the invite code in the `x-invite-code` header, not in the body.

export const signUpRequest = z.strictObject({
  name: z.string(),
  email: z.string(),
  password: z.string(),
});

export const signInRequest = z.strictObject({ email: z.string(), password: z.string() });

/** Native Google sign-in: the app sends the Google ID token. */
export const socialSignInRequest = z.strictObject({
  provider: z.literal("google"),
  id_token: z.strictObject({ token: z.string() }),
});

/** Better Auth's user row as the sign-in and sign-up responses return it. */
export const authUser = z.strictObject({
  id: z.string(),
  name: z.string(),
  email: z.string(),
  email_verified: z.boolean(),
  image: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});

export const signUpResponse = z.strictObject({ token: z.string(), user: authUser });

export const signInResponse = z.strictObject({
  redirect: z.literal(false),
  token: z.string(),
  user: authUser,
});

export const signOutResponse = z.strictObject({ success: z.boolean() });
