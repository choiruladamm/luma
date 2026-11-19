/** Skip rule: a predicate over the dot path of a key, or a list of path patterns where `*` matches any one segment (array index or key). */
export type Skip = ((path: string) => boolean) | readonly string[];

const matches = (pattern: string, path: string[]) => {
  const parts = pattern.split(".");
  return parts.length === path.length && parts.every((p, i) => p === "*" || p === path[i]);
};

const shouldSkip = (skip: Skip | undefined, path: string[]) =>
  !skip
    ? false
    : typeof skip === "function"
      ? skip(path.join("."))
      : skip.some((p) => matches(p, path));

/**
 * `createdAt` → `created_at`, `r2Bytes` → `r2_bytes`, `callbackURL` → `callback_url`.
 * A boundary is lower/digit → upper, or the last upper of an acronym before a capitalized word
 * (`URLPath` → `url_path`). Digits stay attached to the word before them (`new7d` is unchanged).
 */
export const snakeKey = (key: string) =>
  key
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z])([A-Z][a-z])/g, "$1_$2")
    .toLowerCase();

/**
 * `created_at` → `createdAt`. Inverts `snakeKey` except for acronyms (`callback_url` →
 * `callbackUrl`). Leading underscores are part of the name, not a word boundary (`_id`, `__proto__`).
 */
export const camelKey = (key: string) =>
  key.replace(/(?<=[^_])_([a-z0-9])/g, (_, c: string) => c.toUpperCase());

function convert(
  value: unknown,
  key: (k: string) => string,
  skip: Skip | undefined,
  path: string[],
): unknown {
  if (Array.isArray(value)) return value.map((v, i) => convert(v, key, skip, [...path, String(i)]));
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([k, v]) => {
      const at = [...path, k];
      return [key(k), shouldSkip(skip, at) ? v : convert(v, key, skip, at)];
    }),
  );
}

/**
 * Deep-converts the keys of a plain JSON value to snake_case; values are untouched. `skip` names
 * keys (by their path in the input, e.g. `records.*.data`) whose value is passed through as is.
 */
export const toSnake = (value: unknown, skip?: Skip) => convert(value, snakeKey, skip, []);

/** Deep-converts the keys of a plain JSON value to camelCase. Same `skip` rules as `toSnake`. */
export const toCamel = (value: unknown, skip?: Skip) => convert(value, camelKey, skip, []);

/**
 * Converts a JSON response's body keys to snake_case, keeping status and headers (minus
 * content-length). Non-JSON, empty, and malformed bodies pass through. For libraries that answer
 * camelCase.
 */
export async function snakeJson(res: Response): Promise<Response> {
  if (!res.headers.get("content-type")?.includes("application/json")) return res;
  let body: unknown;
  try {
    body = JSON.parse(await res.clone().text());
  } catch {
    // Empty or malformed despite its content type: not ours to repair.
    return res;
  }
  const headers = new Headers(res.headers);
  headers.delete("content-length");
  return new Response(JSON.stringify(toSnake(body)), {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}
