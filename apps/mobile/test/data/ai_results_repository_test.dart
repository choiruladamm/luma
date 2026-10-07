import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
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

  test(
    'stats count translated paragraphs and text size; clear empties',
    () async {
      final book = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              sourceType: SourceType.epub,
              title: 'Walden',
              parserVersion: 1,
              totalChars: 1,
            ),
          );
      final ch = await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: book,
              sortOrder: 0,
              title: 'I',
              charOffset: 0,
            ),
          );
      // Group 0 = paragraphs 0 and 1, group 1 = paragraph 2.
      for (final (i, g) in [(0, 0), (1, 0), (2, 1)]) {
        await db
            .into(db.paragraphs)
            .insert(
              ParagraphsCompanion.insert(
                chapterId: ch,
                paragraphIndex: i,
                groupIndex: Value(g),
                type: ParagraphType.paragraph,
                content: 'p$i',
              ),
            );
      }
      final repo = AiResultsRepository(db);
      expect(await repo.watchStats().first, (paragraphs: 0, bytes: 0));

      await db
          .into(db.aiResults)
          .insert(
            AiResultsCompanion.insert(
              chapterId: ch,
              groupIndex: 0,
              translations: '["a","b"]', // 9 bytes
              meaning: 'é', // 2 bytes in UTF-8
              model: 'm',
            ),
          );
      expect(await repo.watchStats().first, (paragraphs: 2, bytes: 11));

      await repo.clear();
      expect(await repo.watchStats().first, (paragraphs: 0, bytes: 0));
    },
  );
}
