import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> add(String title, {DateTime? opened, DateTime? created}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: title,
          hash: Value(title),
          parserVersion: 1,
          totalChars: 1,
          lastOpenedAt: Value(opened),
          createdAt: created == null ? const Value.absent() : Value(created),
        ),
      );

  test('shelf: last opened first, then never-opened newest first', () async {
    await add('Old unopened', created: DateTime(2026, 1, 1));
    await add('New unopened', created: DateTime(2026, 2, 1));
    await add('Opened long ago', opened: DateTime(2026, 3, 1));
    await add('Opened today', opened: DateTime(2026, 10, 7));

    final shelf = await BookRepository(db).watchShelf().first;
    expect(shelf.map((b) => (b.title, b.opened)), [
      ('Opened today', true),
      ('Opened long ago', true),
      ('New unopened', false),
      ('Old unopened', false),
    ]);
  });

  test('shelf stream re-emits when a book is imported or deleted', () async {
    final emissions = BookRepository(db)
        .watchShelf()
        .map((s) => s.map((b) => b.title).toList());
    final expectation = expectLater(
      emissions,
      emitsInOrder([
        <String>[],
        ['Meditations'],
        <String>[],
      ]),
    );
    await pumpEventQueue();
    final id = await add('Meditations');
    await pumpEventQueue();
    await (db.delete(db.books)..where((b) => b.id.equals(id))).go();
    await expectation;
  });
}
