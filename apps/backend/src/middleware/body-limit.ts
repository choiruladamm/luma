import { bodyLimit } from "hono/body-limit";
import { ApiError } from "../lib/errors";

/** Batas body JSON default (sync push maks 1MB). Upload file punya batas sendiri. */
export const JSON_BODY_LIMIT = 1024 * 1024;

/** Ditolak sebelum `JSON.parse` supaya payload besar gak makan CPU. */
export const limitBody = (maxSize = JSON_BODY_LIMIT) =>
  bodyLimit({
    maxSize,
    onError: () => {
      throw new ApiError(413, "PAYLOAD_TOO_LARGE", `Body exceeds ${maxSize} bytes`);
    },
  });
