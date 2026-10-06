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
/// keliatan di UI.
Future<ParsedBook> parseInIsolate(
  Uint8List bytes, {
  void Function()? onOutline,
}) async {
  final outline = await Isolate.run(() => parseEpub(bytes));
  onOutline?.call();
  final book = await Isolate.run(() => extractChapters(outline));
  return (
    title: outline.title,
    author: outline.author,
    cover: outline.cover,
    chapters: book.chapters,
    totalChars: book.totalChars,
  );
}

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
  })
  parse;

  /// Lempar [EpubException] kalau file bukan EPUB, rusak, atau ada DRM, dan
  /// [ImportCancelled] kalau [isCancelled] nyala sebelum tahap nyimpen.
  Future<ImportResult> importEpub(
    Uint8List bytes, {
    required String fileName,
    void Function(ImportStage stage)? onStage,
    bool Function()? isCancelled,
  }) async {
    void checkpoint() {
      if (isCancelled?.call() ?? false) throw const ImportCancelled();
    }

    onStage?.call(ImportStage.reading);
    if (p.extension(fileName).toLowerCase() != '.epub') {
      throw EpubException(EpubError.notEpub, fileName);
    }

    final hash = sha256.convert(bytes).toString();
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
      },
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
      final id = await _insert(
        book,
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
