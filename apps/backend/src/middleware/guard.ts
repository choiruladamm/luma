import type { FeatureFlag } from "../env";
import { killSwitch } from "./kill-switch";
import { rateLimit } from "./rate-limit";
import { requireSession } from "./session";

/**
 * Pipeline fitur berkuota (docs/backend.md, Arsitektur kode): saklar darurat →
 * sesi → rate limit per user. Saklar duluan, jadi fitur mati gak nyentuh D1.
 */
export const featureGuard = (flag: FeatureFlag) =>
  [killSwitch(flag), requireSession, rateLimit((c) => `user:${c.get("user").id}`)] as const;
