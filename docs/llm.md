---
type: reference
purpose: Look up the mobile AI provider, wire formats, and book chat retrieval and answer contracts.
sections: [Provider credentials and models, Artinya draft prompt and response contract, Bedahin response contract, Book chat planning and retrieval, Book chat budgets and answer contract]
---

# LLM integration

See [architecture](architecture.md) for request lifecycle, phases, and timers, [design](design.md) for UI and pacing, [data model](data-model.md) for persistence. To run evaluations, see [LLM evaluations](llm-evals.md).

## Provider credentials and models

The app sends inference directly to OpenRouter through `OpenRouterService` using its OpenAI-compatible API at `https://openrouter.ai/api/v1`. The backend issues subsidized keys. See [backend](backend.md) for endpoints and server policy.

- `AiKeyRepository.read` prefers a saved user key (BYOK). A saved key rejected by OpenRouter remains the runtime key until replaced or removed, so AI stops and Settings says so (“AI berhenti sampai key-nya bener…”) instead of promising a free-quota fallback. A newly entered key that fails the Settings rejection check is never saved.
- Without BYOK, concurrent subsidy reads share one in-flight request. The repository reuses a fresh stored key and asks the backend for a new one when the key is missing, within `refreshBefore` of expiration, or rejected. The service's HTTP 401 interceptor marks the rejected key for rotation on the next subsidy read. A failed refresh can still return an unexpired stored key, including one marked rejected. `AI_BANNED` takes precedence and becomes `AiException(AiError.http, status: 403, detail: 'AI_BANNED')`. A backend `NETWORK` error with no usable stored key becomes `AiError.network`. A missing runtime key prevents inference.
- `ai.model` holds the selected model and `defaultAiModel` supplies the default. The BYOK picker uses the public unauthenticated catalog from `ModelCatalogService`. The subsidy picker uses the backend's allowed chat models, with `subsidyModelIds` as its local fallback. Removing BYOK resets an out-of-allowlist selection to the default. Chat completions use the captured model for the attempt.

### Completion transport

All three wire modes post to `/chat/completions`. They start with `reasoning: {"enabled": false}`. An initial HTTP 400 containing `reasoning is mandatory` triggers one resend with `reasoning: {"effort": "minimal", "exclude": true}`. This check operates on the HTTP response to the POST. An SSE error event after the POST opens the stream terminates that stream.

| Mode | Wire format | Invalid output handling |
|---|---|---|
| `explain` | Non-streaming JSON object | Defaults to two attempts when `parseAiReply` rejects returned content. |
| `explainStream` and `breakdownStream` | SSE with plain-text section markers and no JSON response format | `GroupAiStream` falls back to a single non-streaming `explain(attempts: 1)` call if the completed sections fail validation. `BreakdownStream` requests a fresh section stream once if its completed response fails validation. |
| `chatStream` | SSE with JSON object response format and temperature `0` | Planner and selector reject invalid output. Chapter-note batches and the final answer have separate bounded repair paths. |

`SseDecoder` emits complete `data:` lines across chunk boundaries and ignores comments. A stream needs `data: [DONE]` to finish successfully. An early end yields `network` and a provider error event yields `http`. Only nonempty `delta.content` reaches the consumers as text, so first-content and stall timers track visible content deltas. Reasoning, keepalives, and usage events are excluded.

Callers receive typed `AiException` failures. `AiError` distinguishes `noApiKey`, `timeout`, `network`, `http` (with provider status and detail when available), and `invalidResponse`. HTTP 401 signals a rejected key and 402 signals exhausted balance. `subsidyFailureOf` distinguishes subsidy exhaustion from a ban. Transport failures and ordinary HTTP errors do not trigger content repair. Embedding model fallback follows its own rules below.

## Artinya draft prompt and response contract

[The prompt source](../apps/mobile/lib/domain/ai_prompt.dart) defines the shared translation and interpretation task, output instructions, and validators.

- `aiUserPrompt` combines book metadata, preceding context when present, and numbered target paragraphs. `aiSystemPrompt` and `aiStreamSystemPrompt` share the same task. `aiPromptVersion` identifies the contract for cached replies.
- The JSON response has `translations` and `meaning`. `parseAiReply` decodes from the first opening brace to the last closing brace, requires one string per target paragraph, and requires a nonempty meaning. It trims the strings.
- The sectioned response uses a marker per line, `[T1]` through `[Tn]` followed by `[MAKNA]`. `parseAiDraft` projects partial content, skipping text before the first marker and holding an unfinished trailing marker. `parseAiSections` requires exactly those sections in order with nonempty bodies.

## Bedahin response contract

`breakdownSystemPrompt` and `breakdownUserPrompt` in [breakdown_prompt.dart](../apps/mobile/lib/domain/breakdown_prompt.dart) use the Artinya translation and meaning alongside source text, adjacent context, and book metadata. `splitSentences` numbers translated sentences across paragraph boundaries. Update `breakdownPromptVersion` when the prompt or sentence splitting changes, since cached ranges depend on that numbering.

| Block | Body |
|---|---|
| `[BAGIAN K1-K3]` | One range with `Judul:`, `Maksudnya:`, and `Logikanya:`. A single sentence can use `[BAGIAN K1]`. |
| `[ISTILAH]` | Optional pipe-delimited rows with label, exact text from the translation, and explanation. |
| `[NYAMBUNG]` | Optional pipe-delimited rows with a target (`B<n>` or `LANJUT`), title, and explanation. |
| `[PRAKTEK]` | Optional practical application in prose. |

`parseBreakdownDraft` hides incomplete trailing markers and field names. `parseBreakdown` requires one to six consecutive ranges covering every sentence exactly once, with nonempty `Maksudnya:` and `Logikanya:` in each. Malformed optional rows are dropped. Chapter links use the one-based chapter list from the prompt and must refer to another chapter, and `LANJUT` requires a next group. Term text matches case-insensitively against the translation. An unmatched term keeps its explanation without a sentence anchor.

## Book chat planning and retrieval

`ChatContextRepository.prepare` assembles the context for one book revision. `buildChatPrompt` first checks the question, history, source anchors, full quote coverage, and prompt size before any paid chat inference. An active quote uses original book text and can span multiple windows or groups. It must fit in full or preparation fails. History selects trusted earlier turns from the same session and revision, newest first within the byte budget. It sends the retained turns in chronological order. History resolves conversational references. Book evidence comes from sources.

### Planner and scope

`chatPlanSystem` combines English query rewriting and strategy selection. It receives the question, history, active quote if present, book metadata, and `chatTocData` for chapters with text. TOC entries include the chapter ID, original title, any parent section, a leading Roman or Arabic chapter number if recognized, and character count. Reading position helps resolve references such as “this chapter.” When a chapter number remains ambiguous across sections, the app overrides the plan to ask for clarification.

`parseChatQueryPlan` checks that chapter IDs are unique and known, and accepts up to three distinct subqueries. Missing or null `strategy` defaults to `specific`, and omitted or null query and chapter lists default to empty. The main `query` and `needs_clarification` are required. The following branches share the same final answer contract.

| Strategy | Retrieval |
|---|---|
| `chapters` | Reads the requested `chapter_ids`. IDs are required unless the plan asks for clarification. |
| `global` | Reads explicit `chapter_ids` when supplied. Otherwise reads chapters with text minus `skip_ids`. |
| `specific`, `crossChapter`, `correction` | Searches explicit `chapter_ids` when supplied. Otherwise searches chapters with text minus `skip_ids`. An empty `queries` list starts from the main English query. |
| `offTopic` or `needs_clarification` | Skips retrieval. The answer request can proceed with empty evidence. |

### Direct reading and chapter notes

`chatGlobalWindows` builds ordered, nonoverlapping windows of original text, including text outside indexed paragraph groups. Requested chapters go straight into the answer prompt as original text if they fit. Longer reads use budgeted batches to generate notes. `chatGlobalSystem` writes question-specific notes for `chapters`. `chatOverviewSystem` writes question-independent notes for `global`. Adjacent batches can run in parallel and their checkpoints advance in window order. Invalid note batches get at most one repair each, subject to `chatMaxBatchRetries` and the shared budget.

`ChatNotesRepository` reuses completed global chapter notes when the revision, window manifest, and notes policy match. Notes are reusable across answer models. Final reading evidence is packed from the original windows, with priority for windows cited by notes. The prompt carries generated notes and exploration coverage alongside original sources. Generated notes can omit details. Only original source snapshots are citable.

### Concept search and embeddings

- `chatChunks` indexes each short paragraph group as one chunk. For an oversized group, it splits the group into individual paragraphs first, then windows any oversized paragraph. Windows are at most 1,800 UTF-16 code units with a target overlap of 200 within a paragraph, using word boundaries where possible and preserving surrogate pairs.
- Search combines dense ranks for the original query and English subqueries with BM25 ranks for the subqueries using reciprocal rank fusion. The index covers the book. Candidate selection applies the chapter scope and preserves pinned quote sources even outside that scope.
- `chatSelectionSystem` selects evidence and can request `missing_queries`. Selections accumulate across rounds. The loop takes up to three fresh subqueries per round, checks the per-turn and continuation-chain query caps, and stops when the answer reserve runs low or consecutive selections stagnate. It adds adjacent windows if space remains.
- The embedding index uses Qwen3 Embedding 8B first. The separate `text-embedding-3-large` space is a fallback for eligible transport or provider failures (timeout, eligible network failures, HTTP 404, 408, 429, and 5xx). Auth, balance, invalid input, cancellation, and certificate failures propagate. Documents and queries use the same model space for each ranking. See [data model](data-model.md) for index identity and storage.

### Retry and continuation

Explicit retry uses the current Settings model and `chatPromptVersion` for a new attempt of the same turn. `ChatRepository.retry` discards the exploration checkpoint if either differs from the previous attempt. Continue creates a new turn and budget from the latest eligible checkpoint. `continueExploration` requires the same model and the current prompt version. See [architecture](architecture.md) for attempt lifecycle and recovery.

## Book chat budgets and answer contract

`ChatBudget` shares one token budget and deadline across planning, selection, chapter notes, final answer, and their repairs. It reserves estimated input tokens plus maximum output before dispatch. Input uses a conservative UTF-8 byte estimate. Reported SSE usage replaces the reservation when available, while missing usage leaves the reservation in place. The ledger tracks embedding request count and bytes separately. These are dispatch limits and estimates of usage.

`ChatContextRepository._modelInfo` caches successful context-window lookups by model. Missing metadata uses `chatFallbackContextTokens` and reports `contextFromProvider: false`. Request capacity is constrained by the model window, `chatContextMargin`, remaining tokens, and `chatRequestInputBytes`. Exploration uses `chatAnswerReserveTokens` and `chatAnswerReserveTime` to leave room for the answer. `buildChatPrompt` and `OpenRouterService.chatStream` also enforce their respective input limits.

### Final answer

`chatAnswerSystemPrompt` requests a JSON object containing `status` and `parts`. Each part carries `layout`, `kind`, `text`, and `source_ids`. The prompt asks for a direct answer in casual Indonesian and allows inline `**bold**` and `*italic*`.

- Status values are `answered`, `partial`, `clarify`, and `off_topic`. The parser also reads legacy `not_found` and the earlier `claims` plus `note` schema.
- The current format requires one to 32 parts. A `book` part requires source IDs. An `interpretation` may cite sources. `external` and `conversation` carry no citations. Missing or null `source_ids` is treated as an empty list, so it still fails for `book`. IDs must be unique within each part and resolve to the sources frozen for that attempt.
- Layout values are `paragraph`, `item`, `bullet`, and `quote`. Missing or unknown layout and a `quote` layout on any kind other than `book` fall back to `paragraph`.
- If exploration is incomplete, `PreparedChat.stream` forces the validated result to `partial` and appends a `conversation` part with coverage calculated by the app. It rejects a result that would exceed the part limit after the addition.

Sources carry original excerpts and anchors identifying the book revision, chapter, paragraph, UTF-16 range, and paragraph hash. Before the answer request and as citations become available, `PreparedChat` checks that the attempt and frozen sources are still valid. Valid source IDs establish provenance to the supplied snapshots. Semantic support still depends on how the answer uses those excerpts.

### Provisional decoding and repair

`ChatAnswerDecoder` collects the raw JSON for final validation. `ChatPreviewDecoder` incrementally projects `parts[].text` with its own 48,000-byte cap, tighter than `chatPromptBytes` for the raw response. Incomplete escapes and Unicode are held until complete. Complete preview parts use the same part validator as the final answer. Invalid provisional structure or an exceeded preview cap stops decoding and removes provisional citations. Reopened drafts expose text only and are excluded from trusted history.

After a completed stream, `PreparedChat.stream` can send the rejected output and validation reason back to the same model up to `chatMaxRepairs` times. Each repair reserves budget again and keeps the cumulative raw draft append-only. Only the final validated frame supplies an answer. If format repair is exhausted, the attempt ends with `invalidResponse`. The phase is `cut` when raw output exists and `failed` when it is empty.
