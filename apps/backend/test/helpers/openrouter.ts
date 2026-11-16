import { HttpResponse, http } from "msw";
import { OPENROUTER_API } from "../../src/clients/openrouter";
import { network } from "../setup";

export type FakeKey = {
  key: string;
  hash: string;
  limit: number;
  usageDaily: number;
  workspaceId: string;
  expiresAt: string;
};

/**
 * OpenRouter management API palsu di memori (bentuk respons dari spike #200).
 * Panggil di tiap test; handler direset otomatis setelah test.
 */
export function fakeOpenRouter() {
  const keys = new Map<string, FakeKey>();
  const calls: string[] = [];
  let seq = 0;

  network.use(
    http.post(`${OPENROUTER_API}/keys`, async ({ request }) => {
      calls.push("POST /keys");
      const body = (await request.json()) as Record<string, unknown>;
      const n = ++seq;
      const key: FakeKey = {
        key: `sk-or-v1-fake-${n}`,
        hash: `hash-${n}`,
        limit: body.limit as number,
        usageDaily: 0,
        workspaceId: body.workspace_id as string,
        expiresAt: body.expires_at as string,
      };
      keys.set(key.hash, key);
      return HttpResponse.json({ data: { hash: key.hash, limit: key.limit }, key: key.key }, { status: 201 });
    }),
    http.patch(`${OPENROUTER_API}/keys/:hash`, async ({ params, request }) => {
      calls.push(`PATCH /keys/${params.hash}`);
      const key = keys.get(params.hash as string);
      if (!key) return HttpResponse.json({ error: { code: 404 } }, { status: 404 });
      key.limit = ((await request.json()) as { limit: number }).limit;
      return HttpResponse.json({ data: { hash: key.hash, limit: key.limit } });
    }),
    http.get(`${OPENROUTER_API}/keys/:hash`, ({ params }) => {
      calls.push(`GET /keys/${params.hash}`);
      const key = keys.get(params.hash as string);
      if (!key) return HttpResponse.json({ error: { code: 404 } }, { status: 404 });
      return HttpResponse.json({
        data: {
          hash: key.hash,
          limit: key.limit,
          limit_remaining: Math.max(0, key.limit - key.usageDaily),
          usage_daily: key.usageDaily,
        },
      });
    }),
    http.delete(`${OPENROUTER_API}/keys/:hash`, ({ params }) => {
      calls.push(`DELETE /keys/${params.hash}`);
      const existed = keys.delete(params.hash as string);
      return existed
        ? HttpResponse.json({ deleted: true })
        : HttpResponse.json({ error: { code: 404 } }, { status: 404 });
    }),
  );

  return { keys, calls };
}
