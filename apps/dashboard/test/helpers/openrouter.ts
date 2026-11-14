import { HttpResponse, http } from "msw";
import { OPENROUTER_API } from "../../../backend/src/clients/openrouter";
import { network } from "../setup";

/**
 * OpenRouter management API palsu (GET/DELETE /keys/:hash, bentuk respons sama
 * dengan backend). `fail` → semua panggilan 500. Handler direset tiap test.
 */
export function fakeOpenRouter({ keys = [] as string[], fail = false, usageDaily = 0.004 } = {}) {
  const live = new Set(keys);
  const calls: string[] = [];
  network.use(
    http.get(`${OPENROUTER_API}/keys/:hash`, ({ params }) => {
      calls.push(`GET ${params.hash}`);
      if (fail) return HttpResponse.json({}, { status: 500 });
      if (!live.has(params.hash as string)) return HttpResponse.json({ error: { code: 404 } }, { status: 404 });
      return HttpResponse.json({ data: { hash: params.hash, limit: 0.02, limit_remaining: 0.016, usage_daily: usageDaily } });
    }),
    http.delete(`${OPENROUTER_API}/keys/:hash`, ({ params }) => {
      calls.push(`DELETE ${params.hash}`);
      if (fail) return HttpResponse.json({}, { status: 500 });
      const existed = live.delete(params.hash as string);
      return existed ? HttpResponse.json({ deleted: true }) : HttpResponse.json({ error: { code: 404 } }, { status: 404 });
    }),
  );
  return { live, calls };
}
