import { OPENROUTER_API } from "../../../../backend/src/clients/openrouter";

type ActivityRow = { date: string; usage: number };

/**
 * Workspace spend for the current UTC month from `GET /activity` (1 subrequest). It counts
 * deleted keys too (unlike summing live keys), but only completed UTC days, so it runs a day
 * behind. ponytail: the endpoint covers the last 30 days; on day 31 the 1st drops out. Add a
 * per-day query if that matters.
 */
export async function monthSpendUsd(managementKey: string, workspaceId: string, now: Date) {
  const res = await fetch(`${OPENROUTER_API}/activity?workspace_id=${encodeURIComponent(workspaceId)}`, {
    headers: { authorization: `Bearer ${managementKey}` },
  });
  if (!res.ok) throw new Error(`OpenRouter GET /activity: ${res.status}`);
  const month = now.toISOString().slice(0, 7);
  const { data } = (await res.json()) as { data: ActivityRow[] };
  return data.filter((r) => r.date.startsWith(month)).reduce((sum, r) => sum + r.usage, 0);
}
