import type { Messages } from "../i18n";

/** The app's AI feature names; product names, so the same in every language. */
export const FEATURE_NAMES: Record<string, string> = {
  group: "Artinya",
  breakdown: "Bedahin",
  chat: "Ngobrolin",
};

/** Who paid for the calls: `own` (BYOK), `subsidy`, or `""` before it was recorded. */
export function keySourceLabel(source: string, t: Messages) {
  if (source === "own") return t.usage.keyOwn;
  if (source === "subsidy") return t.usage.keySubsidy;
  return t.usage.keyUnknown;
}
