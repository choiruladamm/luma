import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../database/app_database.dart';

class BookRepository {
  BookRepository(this._db);

  final AppDatabase _db;

  /// Rak: terakhir dibuka dulu, yang belum pernah dibuka urut baru ditambah.
  Stream<List<ShelfBook>> watchShelf() {
    final q = _db.select(_db.books)
      ..orderBy([
        (b) => OrderingTerm(
          expression: b.lastOpenedAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        (b) => OrderingTerm.desc(b.createdAt),
        (b) => OrderingTerm.desc(b.id),
      ]);
    return q.watch().map(
      (rows) => [
        for (final b in rows)
          ShelfBook(
            id: b.id,
            title: b.title,
            author: b.author,
            coverName: b.coverName,
            opened: b.lastOpenedAt != null,
          ),
      ],
    );
  }
}

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);
