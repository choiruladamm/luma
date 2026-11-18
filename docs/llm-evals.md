---
type: how-to
purpose: Choose an LLM evaluation, maintain its integrity guards, and locate evidence for past runs.
sections: [Choose and run an evaluation, Re-freeze the eval guards, Find preserved evidence]
---

# LLM evaluations

Run the Make targets from the repository root. Fixture and test paths below are relative to `apps/mobile`. For production behavior, see [LLM integration](llm.md).

## Choose and run an evaluation

Start with the narrowest target that answers your question.

| Goal | Target |
|---|---|
| Check fixture isolation, budgets, and citation rules offline | `make chat-spike` |
| Replay development chunking and query retrieval offline | `make chat-retrieval` |
| Replay dense retrieval offline using the complete local embedding cache | `make chat-dense-replay` |
| Build or extend a development embedding cache with paid provider calls | `make chat-dense-live` |
| Smoke-test Artinya and Bedahin against OpenRouter | `make live`, optionally with `m=<model-id>` |
| Exercise the production chat pipeline on a real EPUB fixture | `make chat-agent-live` |
| Exercise a bounded synthetic global scan and explicit continuation | `make chat-adaptive-live`, optionally with `m=<model-id>` |
| Run a frozen held-out or fresh book-level validation | `make chat-heldout-live`, `make chat-validation2-live`, or `make chat-validation3-live` |
| Diagnose the development or already-consumed validation data | `make chat-refine-live` for refinement using cached embeddings, or `make chat-recovery-live` for recovery on validation2 |

Paid targets load `OPENROUTER_API_KEY` from the gitignored root `.env`. The chat targets set their explicit live opt-in flags in the Makefile. Use offline targets for routine checks.

### Run the production chat evaluation

```sh
make chat-agent-live tag=my-run book=discourses.epub cases=0,1 cont=2
make chat-agent-live tag=my-custom-run q='Summarize this book|What is its main argument?' cases=0,1 at=8
```

- `m=` overrides the model. `book=` selects an EPUB from `test/fixtures`. `cases=` selects zero-based question indices. `q=` replaces the built-in questions with a pipe-separated list. Put `>` between messages in a case to exercise follow-ups within the same session.
- `cont=` caps explicit continuations per case. `at=` requests Answer now once the reported number of completed exploration windows reaches that threshold.
- Use a fresh `tag=` for each run. The harness writes `test/fixtures/book_chat_agent_<tag>.json` and uses a tag-specific ledger in `/tmp`.
- `make chat-adaptive-live` uses a synthetic four-chapter book to exercise a partial global answer and continuation to completion. It writes its report to `/tmp/luma-adaptive-*.json`.

### Protect independent validation

Treat a held-out or fresh validation split as consumed once queried. Run only the authorized frozen protocol and record the report in a new output path. The runners refuse to overwrite an existing report. The held-out runner uses `BOOK_CHAT_HELDOUT_REPORT`, and fresh runners use `BOOK_CHAT_VALIDATION2_REPORT` and `BOOK_CHAT_VALIDATION3_REPORT`.

Use development data to tune prompts, retrieval, and thresholds. If results from a consumed split inform a change, use a fresh book-level split for a new independent validation. Refinement and recovery runs supply diagnostics on development or consumed data.

## Re-freeze the eval guards

Re-freeze only the inputs authorized to change. Record the authorized input, the reason for the change, and whether inference changed in the commit message. Preserve the archived protocols and historical result and review files.

1. In `test/fixtures/book_chat_heldout_protocol_v1.json`, update the affected entries in `sourceHashes`. In `book_chat_validation2_protocol.json` and `book_chat_validation3_protocol.json`, update the affected entries in `sha256`. Each key is relative to `apps/mobile`. The verifier hashes UTF-8 text for these maps. Use `(cd apps/mobile && shasum -a 256 path/to/changed-file)` for the tracked UTF-8 files. The validation protocols' separate `binarySha256` entries hash raw fixture bytes. Leave corpus, model, prompt, threshold, and provenance guards in place for a source-map re-freeze.
2. For an authorized lockfile change, use the raw `pubspec.lock` hash for any protocol source-map entries that list it. Separately update the normalized hash in `test/l10n_test.dart`. That test changes only the dependency role of `flutter_localizations` and `intl` from `"direct main"` to `transitive` before hashing. Run this from the repository root to reproduce the digest.

   ```sh
   python3 - <<'PY'
   from hashlib import sha256
   from pathlib import Path
   import re

   lock = Path("apps/mobile/pubspec.lock").read_bytes().decode("utf-8")
   for package in ("flutter_localizations", "intl"):
       role = rf'(^  {package}:\n    dependency: )"direct main"'
       lock, count = re.subn(role, r"\g<1>transitive", lock, flags=re.MULTILINE)
       assert count == 1, package
   print(sha256(lock.encode("utf-8")).hexdigest())
   PY
   ```

3. Compare the resulting diff with the authorized input list. A hash refresh keeps the replay guard aligned with its inputs. Fresh evaluation evidence requires a new run.

## Find preserved evidence

Look under `test/fixtures`.

- `book_chat_eval_manifest.json` identifies the corpus and guards its inputs. The case fixtures distinguish development, held-out, and fresh book-level validation sets.
- `book_chat_spike113/` preserves the original held-out and validation protocols. Active protocols link back to these archived inputs.
- `book_chat_heldout_result_v1.json`, `book_chat_validation2_large_result.json`, and `book_chat_validation3_result.json` record the corresponding runs. Use their companion reviews for semantic findings and the validation2 provider-failures file for provider availability evidence.
- `book_chat_refinement_result_v1.json` and `book_chat_recovery_result.json` record diagnostic runs. `book_chat_agent_*.json` and `book_chat_adaptive_result.json` record production-path and synthetic exploration runs.

Read claims against the run's protocol, model, corpus, and review method. Valid format and gold-range coverage measure different things from semantic support. The held-out semantic review was an assistant review of retrieved sources. The adaptive fixture exercises scan and continuation on one synthetic book. Claims about current model quality, device performance, or cold and warm embedding costs require separate measurements.
