import { z } from "zod";

/**
 * `GET /api/auth/get-session`: `null` when signed out. Better Auth owns this shape and returns
 * more fields than these; the objects are loose and list only what the client reads.
 */
export const sessionResponse = z
  .strictObject({
    user: z.looseObject({
      id: z.string(),
      email: z.string(),
      name: z.string(),
      image: z.string().nullable(),
    }),
    session: z.looseObject({ expiresAt: z.string() }),
  })
  .nullable();
export type Session = z.infer<typeof sessionResponse>;

/** `POST /api/auth/sign-in/social`: the Google URL the SPA navigates to. */
export const socialSignInResponse = z.strictObject({ url: z.string(), redirect: z.boolean() });

/** `POST /api/auth/sign-out`. */
export const signOutResponse = z.strictObject({ success: z.boolean() });
export type SocialSignIn = z.infer<typeof socialSignInResponse>;
