import { z } from "zod";

export const sessionUser = z.strictObject({
  id: z.string(),
  name: z.string(),
  email: z.string(),
  image: z.string().nullable(),
});
export type SessionUser = z.infer<typeof sessionUser>;

/** `GET /v1/me`. */
export const meResponse = z.strictObject({ user: sessionUser });

/** `DELETE /v1/me`: `pending` (202) means R2 still holds objects and the client calls again. */
export const deleteResponse = z.strictObject({ status: z.enum(["deleted", "pending"]) });
export type DeleteResult = z.infer<typeof deleteResponse>;
