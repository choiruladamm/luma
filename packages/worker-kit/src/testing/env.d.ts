// The bindings `setupWorkerTests` reads; each Worker's own Env has them too.
declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
