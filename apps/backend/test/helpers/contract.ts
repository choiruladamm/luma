import { expect } from "vitest";

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

/**
 * Ubah body fixture kontrak jadi matcher: placeholder `<token>` / `<id>` = string
 * tidak kosong, `<iso>` = waktu ISO 8601 UTC; nilai lain harus sama persis.
 */
export function contractMatcher(value: unknown): unknown {
  if (value === "<token>" || value === "<id>") return expect.stringMatching(/.+/);
  if (value === "<iso>") return expect.stringMatching(ISO);
  if (Array.isArray(value)) return value.map(contractMatcher);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, contractMatcher(v)]));
  }
  return value;
}

type Fixture = { response: { status: number; headers?: Record<string, string>; body: unknown } };

/** Cek status, header, dan body respons terhadap fixture kontrak. */
export async function expectContract(res: Response, fixture: Fixture) {
  expect(res.status).toBe(fixture.response.status);
  for (const [name, value] of Object.entries(fixture.response.headers ?? {})) {
    expect(res.headers.get(name)).toEqual(contractMatcher(value));
  }
  const body = await res.json();
  expect(body).toEqual(contractMatcher(fixture.response.body));
  return body;
}
