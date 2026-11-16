import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../services/file_storage.dart';
import 'book_repository.dart';

/// Isi HP milik satu akun (docs/backend.md, Sesi & akun).
class LocalDataRepository {
  LocalDataRepository(this._db, this._books, this._files);

  final AppDatabase _db;
  final BookRepository _books;
  final FileStorage _files;

  /// Ganti akun: buku, progres, catatan, hasil AI, chat, dan log AI akun lama
  /// dihapus biar gak kecampur. Pengaturan (bahasa, Aa, model) tetap.
  /// Lewat [BookRepository.delete] per buku supaya cascade + file + index
  /// Cari kata ikut beres.
  Future<void> wipeBooks() async {
    final ids = await (_db.selectOnly(
      _db.books,
    )..addColumns([_db.books.id])).map((r) => r.read(_db.books.id)!).get();
    for (final id in ids) {
      await _books.delete(id, _files);
    }
    await _db.delete(_db.aiCalls).go();
  }
}

final localDataRepositoryProvider = Provider<LocalDataRepository>(
  (ref) => LocalDataRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(bookRepositoryProvider),
    ref.watch(fileStorageProvider),
  ),
);
