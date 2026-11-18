---
type: reference
purpose: Describe Luma Markdown and direct PDF import behavior.
sections: [Luma Markdown format, Markdown import behavior, PDF import, Non-content filtering, Limits]
---

# Import formats

## Luma Markdown format

One `.md` file represents one chapter. Optional frontmatter begins and ends with `---` and consists of `key: value` lines. Recognized keys are `luma`, `book_key`, `book`, `author`, `chapter` and `chapter_title`; `luma` is ignored. `book_key` must contain lowercase ASCII letters or digits separated by single hyphens, and `chapter` must parse as an integer. The opening delimiter must be on the first line; a malformed header is read as body.

```markdown
---
book_key: example-book
book: Example Book
author: Example Author
chapter: 1
chapter_title: Beginning
---

# Beginning

The story begins here.
```

Without complete frontmatter, the importer suggests metadata from headings and the filename. Chapter numbers are recognized after `bab`, `chapter`, `chap` or `ch` with optional spaces, underscores or hyphens, in filename tokens such as `bab3`, `chapter-07` and `ch12`, not `ch` inside a word. The recognized token is stripped from the fallback filename-derived book title. The first `#` heading or filename suggests the book title; the first heading suggests the chapter title, with `Bab N` as the final fallback. See the [import guide](import-guide.md) for preparation.

Blank lines separate paragraphs; consecutive lines join. Headings from `#` through `######` and scene breaks such as `---`, `* * *`, `***` and `___` are retained as structure, lists become paragraphs, and inline Markdown formatting is stripped to text. Images, tables and code blocks are discarded. A file without a reading paragraph fails.

## Markdown import behavior

When `book_key` and `chapter` are present, import proceeds without the selection sheet; otherwise the reader can choose a Markdown book or create one and adjust the suggested metadata. Non-Markdown books, including EPUB and PDF, are not Markdown import targets. The destination is found by selected book ID or `book_key`; a new key creates a Markdown book. Insert or replacement runs in one transaction. Missing chapter numbers use the largest existing number plus one; chapter order, offsets and total characters are recalculated in chapter-number order. Existing chapter numbers require confirmation before replacement. Replacement retains the chapter identity but removes old paragraphs and chapter AI results and resets progress in that chapter. Groups and book offsets are recalculated. Markdown source files are not stored; their content is in the database. Content changes coordinate with `ChatLifecycle`; see [architecture](architecture.md).

## PDF import

`ImportRepository.importPdf` checks for duplicates and extracts text and structure before copying the original PDF into app storage. Textless pages are skipped when sufficient text remains; scanned or empty files fail. Locked PDFs fail without a password prompt. The importer derives chapters from outline or layout and uses a rendered first page for the cover when available.

PDF chapters and paragraphs carry their own parser version (`pdfParserVersion`), separate from EPUB.

## Non-content filtering

`chapter_extractor.dart` skips EPUB chapters without reading paragraphs and sections dominated by links, such as tables of contents or indexes. It filters by structure rather than title, preserving other content such as introductions and appendices. PDF extraction also filters detected non-content.

An EPUB chapter is dropped when it isn't content or when its link text exceeds 60% of its text (`extractChapters`); Gutenberg header, footer, and boilerplate blocks (`pg-boilerplate`) are skipped.

## Limits

PDF extraction depends on layout and can misread complex columns, tables or scanned pages. Markdown imports plain text rather than preserving visual formatting. DRM-protected files cannot be parsed.
