import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../services/file_storage.dart';
import 'book_repository.dart';

/// Wipes the data that belongs to one account on this device (docs/backend.md, Authentication and accounts).
class LocalDataRepository {
  LocalDataRepository(this._db, this._books, this._files);

  final AppDatabase _db;
  final BookRepository _books;
  final FileStorage _files;

  /// Deletes the previous account's books, progress, notes, AI results, chats,
  /// and AI call log so accounts don't mix after a switch.
  ///
  /// Settings (language, Aa, model) are kept. Books go through
  /// [BookRepository.delete] one by one so the cascade, the files, and the
  /// word-search index are cleaned up too.
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
