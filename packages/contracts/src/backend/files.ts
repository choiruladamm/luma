import { z } from "zod";

/** The app's book/cover file names are hash-based; anything outside this pattern is rejected. */
export const FILE_NAME = /^[A-Za-z0-9._-]{1,200}$/;

/** `POST /v2/files/missing` body. */
export const missingRequest = z.strictObject({
  names: z.array(z.string().regex(FILE_NAME)).max(1000),
});

export const missingResponse = z.strictObject({ missing: z.array(z.string()) });

/** `PUT /v2/files/:name`. */
export const putFileResponse = z.strictObject({ name: z.string(), size: z.number() });
export type StoredFile = z.infer<typeof putFileResponse>;
