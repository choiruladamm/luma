/**
 * Wraps D1 and counts statements that actually run: each statement executed on its own,
 * each statement inside a batch, and `exec`. Counting `prepare` would overcount, since
 * drizzle prepares a parameterless batch statement twice.
 */
export function countingD1(d1: D1Database) {
  let queries = 0;
  const RUNS = ["run", "all", "first", "raw"] as const;
  const counted = (stmt: D1PreparedStatement): D1PreparedStatement => {
    const s = stmt as unknown as Record<string, (...a: unknown[]) => unknown>;
    for (const name of RUNS) {
      const original = s[name]!.bind(stmt);
      s[name] = (...a) => (queries++, original(...a));
    }
    const bind = s.bind!.bind(stmt);
    s.bind = (...a) => counted(bind(...a) as D1PreparedStatement);
    return stmt;
  };
  const db = new Proxy(d1, {
    get(target, prop) {
      const value = Reflect.get(target, prop, target);
      if (typeof value !== "function") return value;
      if (prop === "prepare") return (sql: string) => counted(target.prepare(sql));
      if (prop === "batch")
        return (stmts: D1PreparedStatement[]) => ((queries += stmts.length), target.batch(stmts));
      if (prop === "exec") return (sql: string) => (queries++, target.exec(sql));
      return value.bind(target);
    },
  });
  return { db, count: () => queries };
}
