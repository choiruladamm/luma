import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/book.dart';
import '../database/app_database.dart';
import '../services/chapter_extractor.dart';
import '../services/epub_parser.dart';
import '../services/file_storage.dart';

/// Buku hasil parse, tanpa HTML mentah (gak perlu dibawa balik dari isolate).
typedef ParsedBook = ({
  String? title,
  String? author,
  EpubCover? cover,
  List<ParsedChapter> chapters,
  int totalChars,
});

/// [duplicate] = file yang sama udah ada di rak; [bookId] nunjuk ke yang lama.
typedef ImportResult = ({int bookId, bool duplicate});

/// Tahap import, buat checklist & progres di sheet "Lagi ngebongkar EPUB".
enum ImportStage {
  /// Hash + cek dobel.
  reading,

  /// Judul, penulis, cover, daftar bab.
  outline,

  /// Bab → paragraf → grup.
  chapters,

  /// Nyalin file + nulis ke DB.
  saving,
}

/// Dilempar kalau [ImportRepository.importEpub] dibatalin sebelum nulis apa-apa.
class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// Dua isolate biar tahap [ImportStage.outline] → [ImportStage.chapters]
/// keliatan di UI. [onChapters] = progres per chapter dari isolate ke-2.
Future<ParsedBook> parseInIsolate(
  Uint8List bytes, {
  void Function()? onOutline,
  void Function(int done, int total)? onChapters,
}) async {
  final outline = await _parseInIsolate(bytes);
  onOutline?.call();
  final port = ReceivePort();
  final sub = port.listen((m) => onChapters?.call((m as List)[0], m[1]));
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

typedef ParsedChapters = ({List<ParsedChapter> chapters, int totalChars});

// Dua fungsi ini sengaja terpisah: closure isolate nangkep seluruh scope
// tempat dia dibuat, jadi di `parseInIsolate` (yang megang callback UI) bakal
// ikut ngirim callback itu ke isolate dan gagal.
Future<EpubOutline> _parseInIsolate(Uint8List bytes) =>
    Isolate.run(() => parseEpub(bytes));

Future<ParsedChapters> _extractInIsolate(EpubOutline outline, SendPort send) =>
    Isolate.run(
      () => extractChapters(outline, onChapter: (d, t) => send.send([d, t])),
    );

/// Bobot progres 0–1 per tahap: baca file → hash → outline → chapter → simpan.
const _afterRead = 0.05;
const _afterHash = 0.10;
const _afterOutline = 0.30;
const _afterChapters = 0.85;
const _afterFiles = 0.90;
const _beforeDone = 0.99; // 100% dikasih controller, setelah transaksi commit

/// Import EPUB (docs bagian 8, Alur import). Parse dulu sebelum nyalin file,
/// jadi EPUB jelek gak ninggalin apa-apa; gagal setelah nyalin = file dihapus
/// lagi, transaksi DB di-rollback.
class ImportRepository {
  ImportRepository(this._db, this._storage, {this.parse = parseInIsolate});

  final AppDatabase _db;
  final FileStorage _storage;
  final Future<ParsedBook> Function(
    Uint8List bytes, {
    void Function()? onOutline,
    void Function(int done, int total)? onChapters,
  })
  parse;

  /// Lempar [EpubException] kalau file bukan EPUB, rusak, atau ada DRM, dan
  /// [ImportCancelled] kalau [isCancelled] nyala sebelum tahap nyimpen.
  /// [onProgress] = 0–1 asli dari tahapnya, cuma naik, gak pernah sampe 1.
  Future<ImportResult> importEpub(
    Uint8List bytes, {
    required String fileName,
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
    if (existing != null) return (bookId: existing.id, duplicate: true);

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
      );
      return (bookId: id, duplicate: false);
    } catch (_) {
      await _storage.deleteBookFiles(fileName: bookFile, coverName: coverFile);
      rethrow;
    }
  }

  Future<int> _insert(
    ParsedBook book, {
    void Function(double progress)? onProgress,
    required String hash,
    required String fileName,
    required String bookFile,
    required String? coverFile,
  }) => _db.transaction(() async {
    final bookId = await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: book.title ?? p.basenameWithoutExtension(fileName),
            author: Value(book.author),
            fileName: Value(bookFile),
            coverName: Value(coverFile),
            hash: Value(hash),
            parserVersion: parserVersion,
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

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
  ),
);
