---
type: how-to
purpose: Prepare photos or PDFs as Luma Markdown and import them.
sections: [Convert photos, Convert a PDF, Import chapters]
---

# Prepare a book for Markdown import

## Convert photos

1. Photograph or scan the pages of one chapter, in order.
2. Transcribe them or ask a vision tool to transcribe exactly, without paraphrasing or translation. Join paragraphs and words split across pages, remove page headers and numbers, and mark unreadable text rather than guessing.
3. Save one `.md` file per chapter. Use blank lines between paragraphs, `##` for subheadings and `***` for scene breaks. Check the text against the photos.

## Convert a PDF

You can import a PDF directly; see [PDF import](import-formats.md#pdf-import). To prepare Markdown instead, convert the PDF with an OCR or PDF-to-Markdown tool, then split its output into one file per chapter. Review repeated headers, broken words, reading order and OCR errors.

## Import chapters

Give chapter files names such as `bab-1-book-name.md` and `bab-2-book-name.md`, or add frontmatter using the same `book_key` and a distinct `chapter` number to each file. The [format reference](import-formats.md#luma-markdown-format) describes the keys. Select each file in Luma's import picker, confirm the suggested book and chapter when asked, and confirm replacement if the chapter already exists.
