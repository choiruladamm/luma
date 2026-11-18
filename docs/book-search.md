---
type: reference
purpose: Describe search within a book and its reading-position behavior.
sections: [Search contract, Index and lifecycle, Query and results, Navigation and reading position, Limits and edge cases]
---

# Book search

## Search contract

Search covers original text across all chapters of the current book, not cached translations. Matching ignores case, accents and straight versus curly apostrophes. See [design](design.md) for the interface.

## Index and lifecycle

`BookSearchIndex.ensureIndexed` fills missing entries chapter by chapter when search opens; work can continue after the sheet closes and resume later. Headings are indexed and scene breaks are skipped. Paragraph changes are indexed by triggers; update and delete triggers issue FTS deletes only for rowids present in `paragraph_fts_docsize`. Restore rebuilds the index because paragraph rowids can change. See [data model](data-model.md) for storage details.

## Query and results

`BookSearchQuery.parse` requires at least two letters or digits and turns input into a phrase with a prefix match on the last word, without exposing FTS syntax. Results are ordered by chapter and paragraph, grouped by chapter and shown with snippets. Search is debounced; stale responses do not replace newer ones. Selecting a result saves the query in per-book recent searches, stored in backed-up settings. They are deduplicated case-insensitively and read as empty if corrupt.

## Navigation and reading position

Selecting a result jumps to its paragraph and opens a navigator for moving between hits across chapters. The prior reading position is held until the reader scrolls at least one screen from the jump. Closing search offers a return to the original position; see [design](design.md) for reader interaction.

## Limits and edge cases

Results are capped at 500, with a count indicating truncation; recent searches are capped at five per book. A hit in a heading omitted from the rendered chapter lands at the chapter start. Search also works for Markdown and single-chapter books.
