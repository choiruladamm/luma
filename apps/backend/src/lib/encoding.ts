// Small shared helpers: base64 for crypto.subtle, `vars` lists.

export const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
export const unb64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

/** A comma-separated list from `vars` (models, client IDs): whitespace and empty entries are dropped. */
export const csv = (value: string | undefined) =>
  (value ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

export const DAY_MS = 24 * 60 * 60 * 1000;
