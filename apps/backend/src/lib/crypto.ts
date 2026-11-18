// AES-GCM for secret text in D1 (the user's OpenRouter key). The key is the Worker secret
// `AI_KEY_ENC_SECRET` (base64, 32 bytes). Key lost → old keys are unreadable and are
// recreated (rotation), not lost user data.

import { b64, unb64 } from "./encoding";

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

/** Null if the format is wrong, the key differs, or the content was altered (GCM tag fails). */
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
