---
paths: ["apps/**/*.dart", "apps/**/*.ts", "apps/**/*.tsx", "apps/**/*.jsonc", "apps/**/*.sh", "scripts/**"]
---

# Code comments

Comments are English, written as complete sentences. Default to no comment: add one only when a reader can't learn the fact from the code, names, or types.

## Write

- **Doc comments** on APIs a caller must understand: `///` in Dart, `/** */` in TypeScript. The first sentence is a summary in its own paragraph, third person ("Returns the cached user, or null before the first sync."). Skip it when the name and signature already say it.
- Dart: link symbols as `[name]`. TypeScript: no types in `@param` / `@returns`; the signature has them.
- `//` explains **why**: a hidden constraint, an invariant, a unit, an ordering requirement, a platform quirk, a workaround (link the upstream issue or doc).
- Open work: `TODO(#N): what is missing`. A deliberate simplification: `ponytail: what was simplified, its ceiling, the upgrade path`.
- Evidence the code can't show may cite its source: `spike #34: 30/30 valid`.
- A rule that lives in a doc and isn't visible from the file: cite `docs/<file>.md, <Section>` (`make docs-check` verifies it). The comment still has to make sense without opening the doc.
- Quote Indonesian UI copy verbatim when the comment is about that exact string ("Bentar, lagi mikir..."); everything else is English.

## Leave out

- What the next line does ("// Fetch the user"). Rename or extract instead.
- History: "added for", "changed from", "used to", "now", "removed", "old". The commit message holds it.
- Issue or PR numbers outside the `TODO(#N)` and evidence cases above.
- Commented-out code, author or date tags, decorative banners.

## Examples

```dart
// Bad: narrates the code.
// Ambil user dulu terus simpen.
// Bad: history and issue number.
// Changed from 5 to 10 for #123.

// Good: the constraint behind the number.
// Three retries at most: each attempt is a paid request.

/// Bad: restates `User? cachedUser()`.
/// Gets the user.

/// Good: says what the signature can't.
/// Returns the cached user, or null before the first sync completes.
```

## Frozen files

Files hashed by the chat eval guards (listed under `frozen` in `hygiene.toml`) change only together with a re-freeze: see `docs/llm-evals.md`, Re-freeze the eval guards.

When you edit a file, fix or delete the comments your change made stale. `scripts/hygiene_check.py` (a Claude hook on every edit, the pre-commit hook, and CI via `scripts/hygiene`) flags non-English comments, history phrasing, and stray issue numbers.
