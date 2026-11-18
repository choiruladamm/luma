import { bodyLimit } from "hono/body-limit";
import { ApiError } from "../lib/errors";

/** Default JSON body limit (sync push max 1MB). File uploads have their own limit. */
export const JSON_BODY_LIMIT = 1024 * 1024;

/** Rejected before `JSON.parse` so a large payload doesn't burn CPU. */
export const limitBody = (maxSize = JSON_BODY_LIMIT) =>
  bodyLimit({
    maxSize,
    onError: () => {
      throw new ApiError(413, "PAYLOAD_TOO_LARGE", `Body exceeds ${maxSize} bytes`);
    },
  });
