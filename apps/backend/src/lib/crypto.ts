// AES-GCM untuk teks rahasia di D1 (key OpenRouter user). Kunci = secret Worker
// `AI_KEY_ENC_SECRET` (base64 32 byte). Kunci hilang → key lama gak kebaca dan
// dibuat ulang (rotasi), bukan kehilangan data user.

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

const importKey = (secret: string) =>
  crypto.subtle.importKey("raw", unb64(secret), "AES-GCM", false, ["encrypt", "decrypt"]);

/** Format `v1.<iv b64>.<ciphertext b64>`. */
export async function encryptText(secret: string, plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await importKey(secret),
    new TextEncoder().encode(plain),
  );
  return ["v1", b64(iv), b64(new Uint8Array(cipher))].join(".");
}

/** Null kalau format salah, kunci beda, atau isi diubah (tag GCM gagal). */
export async function decryptText(secret: string, sealed: string): Promise<string | null> {
  const [version, iv, cipher] = sealed.split(".");
  if (version !== "v1" || !iv || !cipher) return null;
  try {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: unb64(iv) },
      await importKey(secret),
      unb64(cipher),
    );
    return new TextDecoder().decode(plain);
  } catch {
    return null;
  }
}
