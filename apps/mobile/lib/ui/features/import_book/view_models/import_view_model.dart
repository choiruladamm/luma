import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/epub_parser.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../data/services/pdf_service.dart';
import '../../../../domain/luma_markdown.dart';
import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// File format being imported via the EPUB/PDF path (progress sheet title).
enum ImportFormat { epub, pdf }

/// Import flow state (boards 13–18).
sealed class ImportState {
  const ImportState();
}

class ImportIdle extends ImportState {
  const ImportIdle();
}

class ImportProcessing extends ImportState {
  const ImportProcessing({
    required this.fileName,
    required this.size,
    required this.stage,
    this.format = ImportFormat.epub,
    this.progress = 0,
    this.glide = Motion.progressStep,
  });

  final String fileName;
  final int size;
  final ImportStage stage;
  final ImportFormat format;

  /// 0–1, real from its stage, only rises. 1 = done, just held until the
  /// minimum loading time.
  final double progress;

  /// How long the number + bar take to catch up to [progress]. Long when the
  /// import is too fast, so it climbs smoothly to 100% at the minimum time.
  final Duration glide;
}

class ImportSuccess extends ImportState {
  const ImportSuccess(this.book, {this.skippedPages = 0});

  final ShelfBook book;

  /// PDF pages without text that were skipped (mixed PDFs only).
  final int skippedPages;
}

class ImportDuplicate extends ImportState {
  const ImportDuplicate(this.book);

  /// The book already on the shelf.
  final ShelfBook book;
}

class ImportFailed extends ImportState {
  const ImportFailed({required this.fileName, required this.error});

  final String fileName;
  final EpubError error;
}

/// PDF import failed ([PdfImportError] is mapped in the sheet, not turned into EpubError).
class ImportPdfFailed extends ImportState {
  const ImportPdfFailed({required this.fileName, required this.error});

  final String fileName;
  final PdfImportError error;
}

/// Destination of a Markdown chapter import. [bookId] null = find / create via
/// [bookKey]; [chapter] null = last chapter + 1.
typedef MarkdownChoice = ({
  int? bookId,
  String bookKey,
  String bookTitle,
  String? author,
  int? chapter,
  String? chapterTitle,
});

/// The `.md` file has been read and awaits the user's decision. Only for
/// [ImportMarkdownAsk] and [ImportMarkdownConflict];
/// [ImportController.submitMarkdown] takes [parsed] from here.
sealed class ImportMarkdownPending extends ImportState {
  const ImportMarkdownPending({required this.fileName, required this.parsed});

  final String fileName;
  final ParsedMarkdown parsed;
}

/// Incomplete frontmatter: shows the "Masuk ke buku mana?" sheet. The guess is
/// in [parsed]; [books] = choices of existing Markdown books.
class ImportMarkdownAsk extends ImportMarkdownPending {
  const ImportMarkdownAsk({
    required super.fileName,
    required super.parsed,
    required this.books,
  });

  final List<MarkdownBook> books;
}

/// The chapter number already exists in the target book: asks replace or cancel.
class ImportMarkdownConflict extends ImportMarkdownPending {
  const ImportMarkdownConflict({
    required super.fileName,
    required super.parsed,
    required this.books,
    required this.choice,
    required this.chapter,
  });

  /// Carried so Batal can return to [ImportMarkdownAsk].
  final List<MarkdownBook> books;
  final MarkdownChoice choice;
  final int chapter;
}

class ImportMarkdownDone extends ImportState {
  const ImportMarkdownDone({
    required this.book,
    required this.chapter,
    required this.chapterId,
    required this.created,
    required this.replaced,
  });

  final ShelfBook book;
  final int chapter;

  /// The chapter that was just imported, for the "Baca" button.
  final int chapterId;

  /// A new book was created / an old chapter was overwritten.
  final bool created, replaced;
}

class ImportMarkdownFailed extends ImportState {
  const ImportMarkdownFailed({
    required this.fileName,
    required this.error,
    this.detail,
    this.value,
  });

  final String fileName;
  final LumaMarkdownError error;

  /// The wrong frontmatter key + its content (only for `badFrontmatter`).
  final String? detail, value;
}

/// Text + numbers for the book list in the "Masuk ke buku mana?" sheet.
extension MarkdownBookLabels on MarkdownBook {
  /// "Bab 1, 3, 7" / "Bab 1–40".

  /// Last chapter + 1, the default number when the file doesn't state one.
  int get nextChapter => chapters.fold(0, (m, n) => n > m ? n : m) + 1;

  int? get lastChapter => chapters.isEmpty ? null : nextChapter - 1;
}

class ImportController extends Notifier<ImportState> {
  /// Increments on every new / cancelled import; a run whose number fell behind = cancelled.
  int _run = 0;

  @override
  ImportState build() => const ImportIdle();

  /// Opens the file picker, then imports the chosen file.
  Future<void> pick() async {
    if (state is ImportProcessing) return;
    final file = await ref.read(filePickerServiceProvider).pickBook();
    if (file != null) await importFile(file);
  }

  /// `.md` / `.markdown` go through the Markdown path, `.pdf` via its path, the rest EPUB.
  Future<void> importFile(PickedFile file) async {
    final ext = file.name.toLowerCase().split('.').last;
    if (ext == 'md' || ext == 'markdown') return importMarkdownFile(file);
    if (ext == 'pdf') return _importPdf(file);
    return _importEpub(file);
  }

  Future<void> _importEpub(PickedFile file) => _runImport(
    file,
    ImportFormat.epub,
    (repo, onStage, onProgress, isCancelled) async {
      final r = await repo.importEpub(
        await file.read(),
        fileName: file.name,
        onStage: onStage,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      return (bookId: r.bookId, duplicate: r.duplicate, skippedPages: 0);
    },
  );

  Future<void> _importPdf(PickedFile file) {
    final path = file.path;
    // Without a path there's nothing to open; a PDF is never loaded as bytes.
    if (path == null) {
      return _runImport(file, ImportFormat.pdf, (_, _, _, _) async {
        throw const PdfImportException(PdfImportError.io, 'no path');
      });
    }
    return _runImport(
      file,
      ImportFormat.pdf,
      (repo, onStage, onProgress, isCancelled) => repo.importPdf(
        path,
        fileName: file.name,
        onStage: onStage,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  /// EPUB/PDF import path: stage + progress + cancel + result. A run whose
  /// number fell behind (cancelled / overwritten by a new import) doesn't touch
  /// state.
  Future<void> _runImport(
    PickedFile file,
    ImportFormat format,
    Future<PdfImportResult> Function(
      ImportRepository repo,
      void Function(ImportStage) onStage,
      void Function(double) onProgress,
      bool Function() isCancelled,
    )
    go,
  ) async {
    final run = ++_run;
    bool cancelled() => run != _run;
    final clock = Stopwatch()..start();
    var stage = ImportStage.reading;
    var progress = 0.0;
    // The read + hash stage is instant; a duplicate / non-EPUB ends there. The
    // progress sheet shows only after passing that stage, so it doesn't flash
    // before the duplicate / failed sheet.
    var revealed = false;
    void show({Duration glide = Motion.progressStep}) {
      if (!revealed) return;
      state = ImportProcessing(
        fileName: file.name,
        size: file.size,
        stage: stage,
        format: format,
        progress: progress,
        glide: glide,
      );
    }

    ImportState failed(Object error) => switch (error) {
      EpubException(:final error) => ImportFailed(
        fileName: file.name,
        error: error,
      ),
      PdfImportException(:final error) => ImportPdfFailed(
        fileName: file.name,
        error: error,
      ),
      _ when format == ImportFormat.pdf => ImportPdfFailed(
        fileName: file.name,
        error: PdfImportError.corrupt,
      ),
      _ => ImportFailed(fileName: file.name, error: EpubError.corrupt),
    };

    try {
      final result = await go(
        ref.read(importRepositoryProvider),
        (s) {
          if (cancelled()) return;
          stage = s;
          if (s != ImportStage.reading) revealed = true;
          show();
        },
        (p) {
          // Only rises, and only updates on each whole-percent change.
          if (cancelled() || p <= progress) return;
          final wholePercent = (p * 100).floor() > (progress * 100).floor();
          progress = p;
          if (wholePercent) show();
        },
        cancelled,
      );
      // Cancelled while saving: the book still lands on the shelf, the sheet is already closed.
      if (cancelled()) return;
      final book = await ref.read(bookRepositoryProvider).book(result.bookId);
      if (cancelled()) return;
      if (book == null) {
        state = failed(StateError('buku ilang'));
        return;
      }
      // Duplicates aren't held.
      if (result.duplicate) {
        state = ImportDuplicate(book);
        return;
      }
      // Import too fast: the number catches up smoothly to 100% by (minimum −
      // pause), then the pause, then "success". Slow import: only a short
      // catch-up + the pause, no extra holding.
      final left = Motion.importMin - Motion.importSettle - clock.elapsed;
      final glide = left > Motion.progressStep ? left : Motion.progressStep;
      progress = 1;
      show(glide: glide);
      await Future<void>.delayed(glide + Motion.importSettle);
      if (cancelled()) return;
      state = ImportSuccess(book, skippedPages: result.skippedPages);
    } on ImportCancelled {
      // cancel() already returned to idle.
    } catch (e) {
      if (!cancelled()) state = failed(e);
    } finally {
      // The picker's temporary copy is no longer needed (the original file is
      // copied into app storage when the import succeeds).
      if (!cancelled()) {
        unawaited(ref.read(filePickerServiceProvider).clearTemporaryFiles());
      }
    }
  }

  /// Reads + parses `.md`. Complete frontmatter (`book_key` + `chapter`) goes
  /// straight in; otherwise state [ImportMarkdownAsk] for the book picker
  /// sheet.
  Future<void> importMarkdownFile(PickedFile file) async {
    if (state is ImportProcessing) return;
    final ParsedMarkdown md;
    try {
      md = parseLumaMarkdown(
        utf8.decode(await file.read(), allowMalformed: true),
        fileName: file.name,
      );
    } on LumaMarkdownException catch (e) {
      state = ImportMarkdownFailed(
        fileName: file.name,
        error: e.error,
        detail: e.detail,
        value: e.value,
      );
      return;
    } catch (_) {
      state = ImportMarkdownFailed(
        fileName: file.name,
        error: LumaMarkdownError.unreadable,
      );
      return;
    }
    if (md.complete) {
      return _saveMarkdown(file.name, md, const [], (
        bookId: null,
        bookKey: md.bookKey!,
        bookTitle: md.book ?? md.bookKey!,
        author: md.author,
        chapter: md.chapter,
        chapterTitle: md.chapterTitle,
      ));
    }
    state = ImportMarkdownAsk(
      fileName: file.name,
      parsed: md,
      books: await ref.read(bookRepositoryProvider).markdownBooks(),
    );
  }

  /// Saves the chapter per the user's choice. Runs only from
  /// [ImportMarkdownPending]. Duplicate chapter number →
  /// [ImportMarkdownConflict]; [replace] overwrites.
  Future<void> submitMarkdown(
    MarkdownChoice choice, {
    bool replace = false,
  }) async {
    final pending = state;
    if (pending is! ImportMarkdownPending) return;
    final books = switch (pending) {
      ImportMarkdownAsk() => pending.books,
      ImportMarkdownConflict() => pending.books,
    };
    return _saveMarkdown(
      pending.fileName,
      pending.parsed,
      books,
      choice,
      replace: replace,
    );
  }

  Future<void> _saveMarkdown(
    String fileName,
    ParsedMarkdown parsed,
    List<MarkdownBook> books,
    MarkdownChoice choice, {
    bool replace = false,
  }) async {
    try {
      final r = await ref
          .read(importRepositoryProvider)
          .importMarkdown(
            parsed,
            bookId: choice.bookId,
            bookKey: choice.bookKey,
            bookTitle: choice.bookTitle,
            author: choice.author,
            chapter: choice.chapter,
            chapterTitle: choice.chapterTitle,
            replace: replace,
          );
      final book = await ref.read(bookRepositoryProvider).book(r.bookId);
      if (book == null) throw StateError('buku ilang');
      state = ImportMarkdownDone(
        book: book,
        chapter: r.chapter,
        chapterId: r.chapterId,
        created: r.created,
        replaced: r.replaced,
      );
    } on ChapterExists catch (e) {
      state = ImportMarkdownConflict(
        fileName: fileName,
        parsed: parsed,
        books: books,
        choice: choice,
        chapter: e.chapter,
      );
    } catch (_) {
      state = ImportMarkdownFailed(
        fileName: fileName,
        error: LumaMarkdownError.unreadable,
      );
    }
  }

  /// "Batal" in the duplicate chapter dialog: back to the book picker sheet.
  void cancelReplace() {
    final s = state;
    if (s is! ImportMarkdownConflict) return;
    state = ImportMarkdownAsk(
      fileName: s.fileName,
      parsed: s.parsed,
      books: s.books,
    );
  }

  /// "Ganti" in the duplicate chapter dialog.
  Future<void> confirmReplace() {
    final s = state;
    if (s is! ImportMarkdownConflict) return Future.value();
    return submitMarkdown(s.choice, replace: true);
  }

  /// "Batalin" in the progress sheet.
  void cancel() {
    _run++;
    state = const ImportIdle();
  }

  /// The result toast / sheet has been closed.
  void dismiss() => state = const ImportIdle();
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
