import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/epub_parser.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../domain/luma_markdown.dart';
import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// State alur import (board 13–18).
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
    this.progress = 0,
    this.glide = Motion.progressStep,
  });

  final String fileName;
  final int size;
  final ImportStage stage;

  /// 0–1, asli dari tahapnya, cuma naik. 1 = beres, tinggal nahan sampe batas
  /// minimum loading.
  final double progress;

  /// Lama angka + bar nyusul ke [progress]. Panjang kalau import kecepetan,
  /// biar naiknya halus sampe 100% pas batas minimum.
  final Duration glide;
}

class ImportSuccess extends ImportState {
  const ImportSuccess(this.book);

  final ShelfBook book;
}

class ImportDuplicate extends ImportState {
  const ImportDuplicate(this.book);

  /// Buku yang udah ada di rak.
  final ShelfBook book;
}

class ImportFailed extends ImportState {
  const ImportFailed({required this.fileName, required this.error});

  final String fileName;
  final EpubError error;
}

/// Tujuan import satu bab Markdown. [bookId] null = cari / bikin lewat
/// [bookKey]; [chapter] null = bab terakhir + 1.
typedef MarkdownChoice = ({
  int? bookId,
  String bookKey,
  String bookTitle,
  String? author,
  int? chapter,
  String? chapterTitle,
});

/// File `.md` udah kebaca, nunggu keputusan user. Cuma buat [ImportMarkdownAsk]
/// dan [ImportMarkdownConflict]; [ImportController.submitMarkdown] ambil
/// [parsed] dari sini.
sealed class ImportMarkdownPending extends ImportState {
  const ImportMarkdownPending({required this.fileName, required this.parsed});

  final String fileName;
  final ParsedMarkdown parsed;
}

/// Frontmatter gak lengkap: tampilin sheet "Masuk ke buku mana?". Tebakan
/// ada di [parsed]; [books] = pilihan buku Markdown yang udah ada.
class ImportMarkdownAsk extends ImportMarkdownPending {
  const ImportMarkdownAsk({
    required super.fileName,
    required super.parsed,
    required this.books,
  });

  final List<MarkdownBook> books;
}

/// Nomor bab udah ada di buku tujuan: nanya ganti atau batal.
class ImportMarkdownConflict extends ImportMarkdownPending {
  const ImportMarkdownConflict({
    required super.fileName,
    required super.parsed,
    required this.books,
    required this.choice,
    required this.chapter,
  });

  /// Dibawa biar Batal bisa balik ke [ImportMarkdownAsk].
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

  /// Bab yang barusan masuk, buat tombol "Baca".
  final int chapterId;

  /// Buku baru dibikin / bab lama ditimpa.
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

  /// Kunci frontmatter yang salah + isinya (cuma buat `badFrontmatter`).
  final String? detail, value;
}

/// Teks sheet error Markdown (board 6a–6d).
extension ImportMarkdownFailedCopy on ImportMarkdownFailed {
  ({String title, String body, String chip}) get copy {
    if (error == LumaMarkdownError.empty) {
      return (
        title: 'Filenya kosong nih',
        body:
            'Gak ada teks bacaan di dalamnya, jadi belum ada yang bisa '
            'dimasukin. Cek lagi file-nya, atau pilih file bab yang lain.',
        chip: '$fileName · 0 kata',
      );
    }
    if (error == LumaMarkdownError.badFrontmatter && detail == 'chapter') {
      return (
        title: 'Nomor babnya gak kebaca',
        body:
            'Di bagian atas file ada tulisan nomor bab, tapi bukan angka. '
            'Ganti jadi angka, terus coba lagi. Atau pilih file lain.',
        chip: '$fileName · nomor bab: “$value”',
      );
    }
    if (error == LumaMarkdownError.badFrontmatter) {
      return (
        title: 'Nama bukunya gak valid',
        body:
            'Di bagian atas file ada nama buku, tapi isinya bukan huruf '
            'kecil, angka, atau strip. Ganti jadi kayak atomic-habits, atau '
            'hapus bagian itu biar Luma yang nebak.',
        chip: '$fileName · nama buku: “$value”',
      );
    }
    return (
      title: 'Filenya gak kebaca',
      body:
          'Luma gak bisa baca isi file ini. Coba pilih file lain, atau '
          'simpan ulang filenya dulu.',
      chip: fileName,
    );
  }
}

/// Teks + angka buat daftar buku di sheet "Masuk ke buku mana?".
extension MarkdownBookLabels on MarkdownBook {
  /// "Bab 1, 3, 7".
  String get chaptersLabel {
    if (chapters.isEmpty) return 'Belum ada bab';
    return 'Bab ${chapters.join(', ')}';
  }

  /// Bab terakhir + 1, nomor bawaan kalau file gak nyebut nomor.
  int get nextChapter => chapters.fold(0, (m, n) => n > m ? n : m) + 1;

  int? get lastChapter => chapters.isEmpty ? null : nextChapter - 1;
}

class ImportController extends Notifier<ImportState> {
  /// Naik tiap import baru / dibatalin; run yang nomornya ketinggalan = batal.
  int _run = 0;

  @override
  ImportState build() => const ImportIdle();

  /// Buka file picker, terus import file yang dipilih.
  Future<void> pick() async {
    if (state is ImportProcessing) return;
    final file = await ref.read(filePickerServiceProvider).pickBook();
    if (file != null) await importFile(file);
  }

  /// `.md` / `.markdown` lewat jalur Markdown, sisanya EPUB.
  Future<void> importFile(PickedFile file) async {
    final ext = file.name.toLowerCase().split('.').last;
    if (ext == 'md' || ext == 'markdown') return importMarkdownFile(file);
    return _importEpub(file);
  }

  Future<void> _importEpub(PickedFile file) async {
    final run = ++_run;
    bool cancelled() => run != _run;
    final clock = Stopwatch()..start();
    var stage = ImportStage.reading;
    var progress = 0.0;
    // Tahap baca + hash sekejap; duplikat / bukan EPUB selesai di situ. Proses
    // baru ditampilin pas lewat tahap itu, biar sheet proses gak kedip dulu
    // sebelum sheet duplikat / gagal.
    var revealed = false;
    void show({Duration glide = Motion.progressStep}) {
      if (!revealed) return;
      state = ImportProcessing(
        fileName: file.name,
        size: file.size,
        stage: stage,
        progress: progress,
        glide: glide,
      );
    }

    try {
      final result = await ref
          .read(importRepositoryProvider)
          .importEpub(
            await file.read(),
            fileName: file.name,
            onStage: (s) {
              if (cancelled()) return;
              stage = s;
              if (s != ImportStage.reading) revealed = true;
              show();
            },
            onProgress: (p) {
              // Cuma naik, dan cuma update tiap ganti persen bulat.
              if (cancelled() || p <= progress) return;
              final wholePercent = (p * 100).floor() > (progress * 100).floor();
              progress = p;
              if (wholePercent) show();
            },
            isCancelled: cancelled,
          );
      // Batal pas lagi nyimpen: bukunya tetep masuk rak, sheet-nya udah tutup.
      if (cancelled()) return;
      final book = await ref.read(bookRepositoryProvider).book(result.bookId);
      if (cancelled()) return;
      if (book == null) {
        state = ImportFailed(fileName: file.name, error: EpubError.corrupt);
        return;
      }
      // Duplikat gak ditahan.
      if (result.duplicate) {
        state = ImportDuplicate(book);
        return;
      }
      // Import kecepetan: angka nyusul halus ke 100% sampe (batas minimum −
      // jeda), terus jeda, baru "berhasil". Import lambat: cuma nyusul
      // sebentar + jeda, gak ada tambahan nahan.
      final left = Motion.importMin - Motion.importSettle - clock.elapsed;
      final glide = left > Motion.progressStep ? left : Motion.progressStep;
      progress = 1;
      show(glide: glide);
      await Future<void>.delayed(glide + Motion.importSettle);
      if (cancelled()) return;
      state = ImportSuccess(book);
    } on ImportCancelled {
      // cancel() udah ngembaliin ke idle.
    } on EpubException catch (e) {
      if (!cancelled()) {
        state = ImportFailed(fileName: file.name, error: e.error);
      }
    } catch (_) {
      if (!cancelled()) {
        state = ImportFailed(fileName: file.name, error: EpubError.corrupt);
      }
    }
  }

  /// Baca + parse `.md`. Frontmatter lengkap (`book_key` + `chapter`) langsung
  /// masuk; kalau enggak, state [ImportMarkdownAsk] buat sheet pilih buku.
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

  /// Simpan bab sesuai pilihan user. Cuma jalan dari [ImportMarkdownPending].
  /// Nomor bab dobel → [ImportMarkdownConflict]; [replace] nimpa.
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

  /// "Batal" di dialog bab dobel: balik ke sheet pilih buku.
  void cancelReplace() {
    final s = state;
    if (s is! ImportMarkdownConflict) return;
    state = ImportMarkdownAsk(
      fileName: s.fileName,
      parsed: s.parsed,
      books: s.books,
    );
  }

  /// "Ganti" di dialog bab dobel.
  Future<void> confirmReplace() {
    final s = state;
    if (s is! ImportMarkdownConflict) return Future.value();
    return submitMarkdown(s.choice, replace: true);
  }

  /// "Batalin" di sheet proses.
  void cancel() {
    _run++;
    state = const ImportIdle();
  }

  /// Toast / sheet hasil udah ditutup.
  void dismiss() => state = const ImportIdle();
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
