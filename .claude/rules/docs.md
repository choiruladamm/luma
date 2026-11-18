---
paths: ["docs/**", "README.md"]
---

# Writing docs

`docs/` describes how the system works **now**, in English. `make docs-check` enforces the structure below; run it after every docs edit.

## Front matter and sections

Every doc starts with front matter, and its `##` headings must match `sections` exactly, in order:

```markdown
---
type: reference          # reference | explanation | how-to | index
purpose: One sentence: what this doc answers and for whom.
sections: [Overview, Request pipeline, Errors]
---

# Title
```

- To add or rename a section, change `sections` and the heading together, and update every code comment that cites the old name (`docs/<file>.md, <Section>`; `make docs-check` lists them).
- `reference`: facts to look up (contracts, rules, limits). `explanation`: how and why the parts fit. `how-to`: steps for one task. Mix only reference + explanation; procedures go in a how-to doc or a skill.

## Where a fact goes

| Fact | Home |
|---|---|
| Mobile layers, code map, runtime flows, platform gotchas | `architecture.md` |
| UI rules, components, gestures, motion, copy tone | `design.md` (values stay in tokens, layout in the boards) |
| Drift tables, identity, revisions | `data-model.md` |
| Worker API, auth, AI subsidy, files, D1 schema | `backend.md` |
| Sync records, merge, cursors, quotas | `sync-protocol.md` |
| Free-tier rules and per-action request budgets | `budgets.md` |
| One-time provisioning and console setup | `operations.md`; routine deploys: the `backend-deploy` skill |
| AI provider, prompts' contracts, chat retrieval | `llm.md`; running evals and re-freezing guards: `llm-evals.md` |
| A feature's own contract | its feature doc (`book-search.md`, `discover.md`, `import-formats.md`, …) |
| Contributor conventions, commands, test rules | the app's `CLAUDE.md` |
| Plans, ideas, progress, status, decisions in flight | GitHub issues, never `docs/` |

One fact lives in one place; elsewhere, link to it. Name code symbols (`SyncRepository.syncIfDue`, `Layout.followGap`) instead of copying their values.

## Editing

- Edit the existing sentence in place so the doc stays current. A changed value replaces the old one.
- Headings carry no issue numbers, dates, or version stamps. Body text links an issue only for open work (`(#N)`).
- Quote Indonesian UI copy verbatim from the ARB files, and keep wire literals, error codes, and file-format keywords as they are. Everything else is English.
- A new doc gets front matter, a row in `docs/README.md`, and a line in the table above.
- Keep each doc under 400 lines; split by type or topic before it grows past that.
