import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/luma_markdown.dart';
import '../../domain/models/book.dart';
import '../../domain/pdf_chapters.dart' as pdf;
import '../../domain/pdf_layout.dart';
import '../database/app_database.dart';
import '../services/chat_lifecycle.dart';
import '../services/chapter_extractor.dart';
import '../services/epub_parser.dart';
import '../services/file_storage.dart';
import '../services/pdf_service.dart';

/// A parsed book without the raw HTML, which doesn't need to travel back from the isolate.
typedef ParsedBook = ({
  String? title,
  String? author,
  EpubCover? cover,
  List<ParsedChapter> chapters,
  int totalChars,
});

/// Result of an import; `duplicate` means the same file is already on the shelf, and `bookId` then points to the existing book.
typedef ImportResult = ({int bookId, bool duplicate});

/// Hasil [ImportRepository.importPdf].
typedef PdfImportResult = ({int bookId, bool duplicate, int skippedPages});

/// Import stages, shown as the checklist and progress in the "Lagi ngebongkar EPUB" sheet.
enum ImportStage {
  /// Hashes the file and checks for duplicates.
  reading,

  /// Reads the title, author, cover, and chapter list.
  outline,

  /// Splits chapters into paragraphs and groups.
  chapters,

  /// Copies the file and writes to the database.
  saving,
}

/// Thrown when [ImportRepository.importEpub] is cancelled before anything is written.
class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// Thrown when chapter [chapter] already exists in book [bookId]; retry with
/// `replace: true` to overwrite it.
class ChapterExists implements Exception {
  const ChapterExists(this.bookId, this.chapter);

  final int bookId;
  final int chapter;

  @override
  String toString() => 'ChapterExists(book $bookId, bab $chapter)';
}

/// Result of a Markdown chapter import; `created` means a new book was created, `replaced` means an existing chapter was overwritten.
typedef MarkdownImportResult = ({
  int bookId,
  int chapterId,
  int chapter,
  bool created,
  bool replaced,
});

/// Parses an EPUB in two isolates so the [ImportStage.outline] to
/// [ImportStage.chapters] transition is visible in the UI.
///
/// [onChapters] reports per-chapter progress from the second isolate.
Future<ParsedBook> parseInIsolate(
  Uint8List bytes, {
  void Function()? onOutline,
  void Function(int done, int total)? onChapters,
}) async {
  final outline = await _parseInIsolate(bytes);
  onOutline?.call();
  final port = ReceivePort();
  final sub = port.listen((m) {
    final msg = m as List<Object?>;
    onChapters?.call(msg[0]! as int, msg[1]! as int);
  });
  final ParsedChapters book;
  try {
    book = await _extractInIsolate(outline, port.sendPort);
  } finally {
    await sub.cancel();
    port.close();
  }
  return (
    title: outline.title,
    author: outline.author,
    cover: outline.cover,
    chapters: book.chapters,
    totalChars: book.totalChars,
  );
}

/// Top-level and separate from importPdf because an isolate closure must not
/// capture UI callbacks.
Future<pdf.PdfLayoutResult> _layoutInIsolate(
  List<List<PdfLine>> pages,
  List<pdf.PdfOutlineEntry> outline,
) => Isolate.run(() => pdf.layoutPdf(pages, outline));

typedef ParsedChapters = ({List<ParsedChapter> chapters, int totalChars});

// These two stay separate on purpose: an isolate closure captures the whole
// scope it was created in, so inside `parseInIsolate` (which holds UI
// callbacks) it would try to send those callbacks to the isolate and fail.
Future<EpubOutline> _parseInIsolate(Uint8List bytes) =>
    Isolate.run(() => parseEpub(bytes));

Future<ParsedChapters> _extractInIsolate(EpubOutline outline, SendPort send) =>
    Isolate.run(
      () => extractChapters(outline, onChapter: (d, t) => send.send([d, t])),
    );

/// Progress weights from 0 to 1 per stage: read file, hash, outline, chapters, save.
const _afterRead = 0.05;
const _afterHash = 0.10;
const _afterOutline = 0.30;
const _afterChapters = 0.85;
const _afterFiles = 0.90;
// The controller reports 100% after the transaction commits.
const _beforeDone = 0.99;

/// Imports EPUB books (docs/architecture.md, Import).
///
/// It parses before copying the file, so a bad EPUB leaves nothing behind. A
/// failure after the copy deletes the file again and rolls back the database
/// transaction.
class ImportRepository {
  ImportRepository(
    this._db,
    this._storage, {
    this.parse = parseInIsolate,
    this.chatLifecycle,
    this.pdfService = const PdfiumService(),
  });

  final PdfService pdfService;

  final ChatLifecycle? chatLifecycle;

  final AppDatabase _db;
  final FileStorage _storage;
  final Future<ParsedBook> Function(
    Uint8List bytes, {
    void Function()? onOutline,
    void Function(int done, int total)? onChapters,
  })
  parse;

  /// Fills `chapters.section` for EPUB books imported before schema 11.
  ///
  /// Reparses the stored file (local and free), matches chapters by count and
  /// title, then fills the section and a fuller TOC title. On a mismatch or a
  /// missing file every section is set to '' so the work isn't repeated on
  /// each open. Paragraphs are left untouched.
  Future<void> backfillSections(int bookId) async {
    final rows =
        await (_db.select(_db.chapters)
              ..where((c) => c.bookId.equals(bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    if (rows.isEmpty || rows.every((c) => c.section != null)) return;
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    List<ParsedChapter>? parsed;
    if (book != null &&
        book.sourceType == SourceType.epub &&
        book.fileName != null &&
        book.parserVersion == parserVersion) {
      final file = _storage.book(book.fileName!);
      if (await file.exists()) {
        try {
          parsed = (await parse(await file.readAsBytes())).chapters;
        } on Exception {
          parsed = null;
        }
      }
    }
    bool aligned(ParsedChapter c, Chapter row) =>
        c.title == row.title ||
        c.title.toLowerCase().startsWith(row.title.toLowerCase());
    final ok =
        parsed != null &&
        parsed.length == rows.length &&
        [for (final (i, c) in parsed.indexed) aligned(c, rows[i])]
            .every((m) => m);
    await _db.transaction(() async {
      for (final (i, row) in rows.indexed) {
        final c = ok ? parsed![i] : null;
        await (_db.update(
          _db.chapters,
        )..where((x) => x.id.equals(row.id))).write(
          ChaptersCompanion(
            section: Value(c?.section ?? ''),
            title: c != null && c.title != row.title
                ? Value(c.title)
                : const Value.absent(),
          ),
        );
      }
    });
  }

  /// Imports an EPUB file and returns its book id.
  ///
  /// Throws [EpubException] if the file isn't an EPUB, is corrupt, or has DRM,
  /// and [ImportCancelled] if [isCancelled] turns true before the saving
  /// stage. [onProgress] reports the stage's real 0-1 progress; it only goes
  /// up and never reaches 1. [sourceId] and [externalId] identify the external
  /// catalog entry when the EPUB was downloaded (docs/discover.md); a
  /// duplicate that lacks that identity gets it attached.
  Future<ImportResult> importEpub(
    Uint8List bytes, {
    required String fileName,
    String? sourceId,
    String? externalId,
    void Function(ImportStage stage)? onStage,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void checkpoint() {
      if (isCancelled?.call() ?? false) throw const ImportCancelled();
    }

    onStage?.call(ImportStage.reading);
    if (p.extension(fileName).toLowerCase() != '.epub') {
      throw EpubException(EpubError.notEpub, fileName);
    }

    onProgress?.call(_afterRead);
    final hash = sha256.convert(bytes).toString();
    onProgress?.call(_afterHash);
    final existing = await (_db.select(
      _db.books,
    )..where((b) => b.hash.equals(hash))).getSingleOrNull();
    if (existing != null) {
      if (existing.sourceId == null && sourceId != null) {
        await (_db.update(
          _db.books,
        )..where((b) => b.id.equals(existing.id))).write(
          BooksCompanion(
            sourceId: Value(sourceId),
            externalId: Value(externalId),
          ),
        );
      }
      return (bookId: existing.id, duplicate: true);
    }

    checkpoint();
    onStage?.call(ImportStage.outline);
    final book = await parse(
      bytes,
      onOutline: () {
        checkpoint();
        onStage?.call(ImportStage.chapters);
        onProgress?.call(_afterOutline);
      },
      onChapters: (done, total) => onProgress?.call(
        _afterOutline +
            (_afterChapters - _afterOutline) * (total == 0 ? 1 : done / total),
      ),
    );
    if (book.chapters.isEmpty) {
      throw const EpubException(EpubError.corrupt, 'no readable chapters');
    }
    checkpoint();
    onStage?.call(ImportStage.saving);

    final bookFile = '$hash.epub';
    final coverFile = book.cover == null
        ? null
        : '$hash.${book.cover!.extension}';
    try {
      await _storage.writeBook(bookFile, bytes);
      if (coverFile != null) {
        await _storage.writeCover(coverFile, book.cover!.bytes);
      }
      onProgress?.call(_afterFiles);
      final id = await _insert(
        book,
        onProgress: onProgress,
        hash: hash,
        fileName: fileName,
        bookFile: bookFile,
        coverFile: coverFile,
        sourceId: sourceId,
        externalId: externalId,
      );
      return (bookId: id, duplicate: false);
    } catch (_) {
      await _storage.deleteBookFiles(fileName: bookFile, coverName: coverFile);
      rethrow;
    }
  }

  /// Imports a PDF directly (docs/import-formats.md, PDF import).
  ///
  /// Follows the [importEpub] pattern: the layout runs before the file is
  /// copied, so a bad PDF leaves nothing behind, and a failure after the copy
  /// deletes the newly written file and rolls back the database transaction.
  /// The file at [path] is read by path, so it never sits fully in memory.
  ///
  /// Throws [PdfImportException] (password, scan, corrupt, not a PDF, empty,
  /// IO) and [ImportCancelled] if [isCancelled] turns true before the saving
  /// stage. `skippedPages` counts the pages without text in a mixed PDF, which
  /// are skipped.
  Future<PdfImportResult> importPdf(
    String path, {
    required String fileName,
    void Function(ImportStage stage)? onStage,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void checkpoint() {
      if (isCancelled?.call() ?? false) throw const ImportCancelled();
    }

    onStage?.call(ImportStage.reading);
    if (p.extension(fileName).toLowerCase() != '.pdf') {
      throw PdfImportException(PdfImportError.notPdf, fileName);
    }
    onProgress?.call(_afterRead);
    final String hash;
    try {
      hash = (await sha256.bind(File(path).openRead()).first).toString();
    } on FileSystemException catch (e) {
      throw PdfImportException(PdfImportError.io, e.message);
    }
    onProgress?.call(_afterHash);
    final existing = await (_db.select(
      _db.books,
    )..where((b) => b.hash.equals(hash))).getSingleOrNull();
    if (existing != null) {
      return (bookId: existing.id, duplicate: true, skippedPages: 0);
    }

    checkpoint();
    onStage?.call(ImportStage.outline);
    final raw = await pdfService.extract(
      path,
      onOpened: () {
        checkpoint();
        onStage?.call(ImportStage.chapters);
        onProgress?.call(_afterOutline);
      },
      onPage: (done, total) {
        checkpoint();
        onProgress?.call(
          _afterOutline +
              (_afterChapters - _afterOutline) *
                  0.5 *
                  (total == 0 ? 1 : done / total),
        );
      },
    );
    final empty = raw.pages.where((lines) => lines.isEmpty).length;
    if (raw.pageCount == 0) {
      throw const PdfImportException(PdfImportError.empty, 'no pages');
    }
    // Empty pages are only evidence of a scan, not proof; the user-facing copy stays cautious.
    if (empty * 2 > raw.pageCount) {
      throw PdfImportException(
        PdfImportError.scan,
        '$empty/${raw.pageCount} pages without text',
      );
    }
    checkpoint();
    final laid = await _layoutInIsolate(raw.pages, raw.outline);
    onProgress?.call(_afterChapters);
    if (laid.chapters.isEmpty) {
      throw const PdfImportException(PdfImportError.empty, 'no readable text');
    }
    checkpoint();
    onStage?.call(ImportStage.saving);

    final book = (
      title: laid.heading ?? _titleFromFileName(fileName),
      author: null,
      cover: raw.cover,
      chapters: [
        for (final c in laid.chapters)
          ParsedChapter(
            title: c.title,
            section: c.section,
            paragraphs: c.paragraphs,
            groups: c.groups,
            charOffset: c.charOffset,
          ),
      ],
      totalChars: laid.totalChars,
    );
    final bookFile = '$hash.pdf';
    final coverFile = raw.cover == null
        ? null
        : '$hash.${raw.cover!.extension}';
    // Files that existed before this import aren't ours, so the rollback must
    // not delete them.
    final hadBook = await _storage.book(bookFile).exists();
    final hadCover =
        coverFile != null && await _storage.cover(coverFile).exists();
    try {
      try {
        await _storage.book(bookFile).parent.create(recursive: true);
        await File(path).copy(_storage.book(bookFile).path);
        if (coverFile != null) {
          await _storage.writeCover(coverFile, raw.cover!.bytes);
        }
      } on FileSystemException catch (e) {
        throw PdfImportException(PdfImportError.io, e.message);
      }
      onProgress?.call(_afterFiles);
      final id = await _insert(
        book,
        onProgress: onProgress,
        hash: hash,
        fileName: fileName,
        bookFile: bookFile,
        coverFile: coverFile,
        sourceType: SourceType.pdf,
      );
      return (bookId: id, duplicate: false, skippedPages: empty);
    } catch (_) {
      await _storage.deleteBookFiles(
        fileName: hadBook ? null : bookFile,
        coverName: hadCover ? null : coverFile,
      );
      rethrow;
    }
  }

  /// Imports one Luma Markdown chapter (docs/import-formats.md, Markdown import behavior).
  ///
  /// The target book is [bookId] if given, otherwise the book whose `book_key`
  /// equals [bookKey]; if neither exists a new book is created with
  /// [bookTitle] and [author]. A null [chapter] means the last chapter plus 1.
  ///
  /// Throws [ChapterExists] if that chapter number exists and [replace] is
  /// off. Replacing happens in place (the chapter id stays): the chapter's
  /// paragraphs and AI results are dropped, but its reading sessions and
  /// stats survive.
  Future<MarkdownImportResult> importMarkdown(
    ParsedMarkdown md, {
    int? bookId,
    required String bookKey,
    required String bookTitle,
    String? author,
    int? chapter,
    String? chapterTitle,
    bool replace = false,
  }) async {
    final existing =
        await (_db.select(_db.books)..where(
              (b) => bookId != null
                  ? b.id.equals(bookId)
                  : b.bookKey.equals(bookKey),
            ))
            .getSingleOrNull();
    Future<MarkdownImportResult> change() => _importMarkdown(
      md,
      bookId: bookId,
      bookKey: bookKey,
      bookTitle: bookTitle,
      author: author,
      chapter: chapter,
      chapterTitle: chapterTitle,
      replace: replace,
    );
    if (existing != null && chatLifecycle != null) {
      return chatLifecycle!.changeContent(existing.id, change);
    }
    return change();
  }

  Future<MarkdownImportResult> _importMarkdown(
    ParsedMarkdown md, {
    int? bookId,
    required String bookKey,
    required String bookTitle,
    String? author,
    int? chapter,
    String? chapterTitle,
    required bool replace,
  }) => _db.transaction(() async {
    final byId = bookId != null;
    final existing =
        await (_db.select(_db.books)..where(
              (b) => byId ? b.id.equals(bookId) : b.bookKey.equals(bookKey),
            ))
            .getSingleOrNull();
    if (existing != null && existing.sourceType != SourceType.markdown) {
      throw ArgumentError.value(existing.id, 'bookId', 'bukan buku Markdown');
    }
    if (byId && existing == null) {
      throw ArgumentError.value(bookId, 'bookId', 'gak ada');
    }

    final id =
        existing?.id ??
        await _db
            .into(_db.books)
            .insert(
              BooksCompanion.insert(
                sourceType: SourceType.markdown,
                bookKey: Value(bookKey),
                title: bookTitle,
                author: Value(author),
                parserVersion: parserVersion,
                totalChars: 0,
              ),
            );

    final chapters = await (_db.select(
      _db.chapters,
    )..where((c) => c.bookId.equals(id))).get();
    final number =
        chapter ??
        chapters.fold<int>(
              0,
              (m, c) => (c.chapterNumber ?? 0) > m ? c.chapterNumber! : m,
            ) +
            1;
    final old = chapters.where((c) => c.chapterNumber == number).firstOrNull;
    if (old != null && !replace) throw ChapterExists(id, number);

    final title = chapterTitle ?? md.chapterTitle ?? 'Bab $number';
    final int chapterId;
    if (old == null) {
      chapterId = await _db
          .into(_db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: id,
              sortOrder: chapters.length, // Renumbered in _renumber.
              chapterNumber: Value(number),
              title: title,
              charOffset: 0,
            ),
          );
    } else {
      chapterId = old.id;
      for (final t in ['paragraphs', 'ai_results', 'ai_breakdowns']) {
        await _db.customStatement('DELETE FROM $t WHERE chapter_id = ?', [
          chapterId,
        ]);
      }
      await (_db.update(_db.chapters)..where((c) => c.id.equals(chapterId)))
          .write(ChaptersCompanion(title: Value(title)));
      // The old paragraph indexes don't apply to the new content.
      await (_db.update(
        _db.readingProgress,
      )..where((r) => r.chapterId.equals(chapterId))).write(
        const ReadingProgressCompanion(
          paragraphIndex: Value(0),
          paragraphOffset: Value(0),
        ),
      );
    }

    await _db.batch(
      (b) => b.insertAll(_db.paragraphs, [
        for (final (i, para) in md.paragraphs.indexed)
          ParagraphsCompanion.insert(
            chapterId: chapterId,
            paragraphIndex: i,
            groupIndex: Value(md.groups[i]),
            type: para.type,
            content: para.text,
          ),
      ]),
    );
    await _renumber(id);
    if (existing != null) await _db.contentChanged(id);
    return (
      bookId: id,
      chapterId: chapterId,
      chapter: number,
      created: existing == null,
      replaced: old != null,
    );
  });

  /// Recomputes the display order from chapter numbers, plus each chapter's
  /// `charOffset` and `books.totalChars`, because chapters can arrive out of
  /// order.
  // ponytail: chapter length comes from SQL LENGTH (per character), not Dart
  // String.length (per UTF-16 unit); they differ only for emoji, which doesn't
  // affect the percentage.
  Future<void> _renumber(int bookId) async {
    final rows = await _db
        .customSelect(
          'SELECT c.id, COALESCE(SUM(LENGTH(p.text)), 0) AS n '
          'FROM chapters c LEFT JOIN paragraphs p ON p.chapter_id = c.id '
          'WHERE c.book_id = ? GROUP BY c.id '
          'ORDER BY c.chapter_number, c.id',
          variables: [Variable(bookId)],
        )
        .get();
    var offset = 0;
    for (final (order, r) in rows.indexed) {
      await (_db.update(
        _db.chapters,
      )..where((c) => c.id.equals(r.read('id')))).write(
        ChaptersCompanion(sortOrder: Value(order), charOffset: Value(offset)),
      );
      offset += r.read<int>('n');
    }
    await (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(totalChars: Value(offset)),
    );
  }

  Future<int> _insert(
    ParsedBook book, {
    void Function(double progress)? onProgress,
    required String hash,
    required String fileName,
    required String bookFile,
    required String? coverFile,
    String? sourceId,
    String? externalId,
    SourceType sourceType = SourceType.epub,
    int version = parserVersion,
  }) => _db.transaction(() async {
    final bookId = await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: sourceType,
            title: book.title ?? p.basenameWithoutExtension(fileName),
            author: Value(book.author),
            fileName: Value(bookFile),
            coverName: Value(coverFile),
            hash: Value(hash),
            sourceId: Value(sourceId),
            externalId: Value(externalId),
            parserVersion: version,
            totalChars: book.totalChars,
          ),
        );
    for (final (order, chapter) in book.chapters.indexed) {
      final chapterId = await _db
          .into(_db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: bookId,
              sortOrder: order,
              title: chapter.title,
              section: Value(chapter.section ?? ''),
              charOffset: chapter.charOffset,
            ),
          );
      await _db.batch(
        (b) => b.insertAll(_db.paragraphs, [
          for (final (i, para) in chapter.paragraphs.indexed)
            ParagraphsCompanion.insert(
              chapterId: chapterId,
              paragraphIndex: i,
              groupIndex: Value(chapter.groups[i]),
              type: para.type,
              content: para.text,
            ),
        ]),
      );
      onProgress?.call(
        _afterFiles +
            (_beforeDone - _afterFiles) * (order + 1) / book.chapters.length,
      );
    }
    return bookId;
  });
}

/// Derives a title from a file name, e.g. "my_book__v2 (z-lib).pdf" becomes
/// "my book v2".
///
/// Used for PDFs without a readable title. Underscores, doubled spaces, and
/// download-source suffixes are dropped.
String _titleFromFileName(String fileName) {
  final t = p
      .basenameWithoutExtension(fileName)
      .replaceAll('_', ' ')
      .replaceAll(
        RegExp(
          r'\s*\((?:z-?lib(?:\.org)?|1lib|pdfdrive[^)]*)\)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.isEmpty ? p.basenameWithoutExtension(fileName) : t;
}

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
    chatLifecycle: ref.watch(chatLifecycleProvider),
    pdfService: ref.watch(pdfServiceProvider),
  ),
);

/// Backfills chapter sections when a book chat opens; tests without a database override it.
final chapterSectionBackfillProvider = Provider<Future<void> Function(int)>(
  (ref) =>
      (bookId) => ref.read(importRepositoryProvider).backfillSections(bookId),
);
