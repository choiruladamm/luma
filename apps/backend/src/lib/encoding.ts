// Helper kecil yang dipakai bareng: base64 buat crypto.subtle, daftar `vars`.

export const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
export const unb64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

/** Daftar dipisah koma dari `vars` (model, client ID): spasi & entri kosong dibuang. */
export const csv = (value: string | undefined) =>
  (value ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

export const DAY_MS = 24 * 60 * 60 * 1000;
