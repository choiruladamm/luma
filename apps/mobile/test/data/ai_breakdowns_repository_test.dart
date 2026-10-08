import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/ai_breakdowns_repository.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late AiResultsRepository results;
  late AiBreakdownsRepository repo;
  late int ch;
  late GroupRef g0;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    results = AiResultsRepository(db);
    repo = AiBreakdownsRepository(db, results);
    final book = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'The Enchiridion',
            author: const Value('Epictetus'),
            parserVersion: 1,
            totalChars: 1,
          ),
        );
    // Inserted out of order: the chapter list follows sortOrder.
    final ids = <String, int>{};
    for (final (title, order) in [('V', 1), ('I', 0), ('XXIV', 2)]) {
      ids[title] = await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: book,
              sortOrder: order,
              title: title,
              charOffset: 0,
            ),
          );
    }
    ch = ids['V']!;
    g0 = (chapterId: ch, groupIndex: 0);
    // p0 = heading (not context), group 0 = p1 + p2, group 1 = p3.
    for (final (i, group) in [(0, null), (1, 0), (2, 0), (3, 1)]) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: ch,
              paragraphIndex: i,
              groupIndex: Value(group),
              type: i == 0 ? ParagraphType.heading : ParagraphType.paragraph,
              content: 'p$i',
            ),
          );
    }
  });
  tearDown(() => db.close());

  Future<void> translate(GroupRef group, List<String> t) => results.save(
    group,
    AiReply(translations: t, meaning: 'M'),
    model: 'x',
  );

  test('input: needs the quick meaning first', () async {
    expect(await repo.input(g0), isNull);
  });

  test(
    'input: book, chapters by sortOrder, translations, next group',
    () async {
      await translate(g0, ['Satu.', 'Dua.']);
      final input = (await repo.input(g0))!;
      expect(input.book.title, 'The Enchiridion');
      expect(input.book.chapter, 'V');
      expect(input.chapters, ['I', 'V', 'XXIV']);
      expect(input.chapter, 2);
      expect(input.context, isEmpty); // headings are not context
      expect(input.original, ['p1', 'p2']);
      expect(input.translations, ['Satu.', 'Dua.']);
      expect(input.meaning, 'M');
      expect(input.next, ['p3']);

      // Last group of the chapter: no next.
      final g1 = (chapterId: ch, groupIndex: 1);
      await translate(g1, ['Tiga.']);
      expect((await repo.input(g1))!.next, isEmpty);
    },
  );

  test(
    'find / sections follow the prompt version and the translation',
    () async {
      await translate(g0, ['Satu.', 'Dua.']);
      final hash = breakdownSourceHash(['Satu.', 'Dua.']);
      expect(await repo.find(g0, hash), isNull);
      expect(await repo.sections(g0), 0);

      await repo.save(
        g0,
        body: '[BAGIAN K1]\nx\n[BAGIAN K2]\ny',
        sourceHash: hash,
        model: 'x',
      );
      expect(await repo.find(g0, hash), startsWith('[BAGIAN K1]'));
      expect(await repo.sections(g0), 2);

      // Overwrite, not a second row.
      await repo.save(g0, body: 'B2', sourceHash: hash, model: 'x');
      expect(await repo.find(g0, hash), 'B2');
      expect(await db.select(db.aiBreakdowns).get(), hasLength(1));

      // Retranslated: the sentence ranges no longer apply.
      await translate(g0, ['Satu lagi.', 'Dua.']);
      expect(
        await repo.find(g0, breakdownSourceHash(['Satu lagi.', 'Dua.'])),
        isNull,
      );
      expect(await repo.sections(g0), 0);

      // An older prompt version counts as missing.
      await translate(g0, ['Satu.', 'Dua.']);
      await (db.update(db.aiBreakdowns))
          .write(const AiBreakdownsCompanion(promptVersion: Value(0)));
      expect(await repo.find(g0, hash), isNull);
      expect(await repo.sections(g0), 0);
    },
  );

  test('clear empties; deleting the book takes them along', () async {
    final hash = breakdownSourceHash(['a']);
    await repo.save(g0, body: 'B', sourceHash: hash, model: 'x');
    await repo.clear();
    expect(await db.select(db.aiBreakdowns).get(), isEmpty);

    await repo.save(g0, body: 'B', sourceHash: hash, model: 'x');
    await db.delete(db.books).go();
    expect(await db.select(db.aiBreakdowns).get(), isEmpty);
  });

  test('a stale quick translation leaves no input', () async {
    await translate(g0, ['Satu.', 'Dua.']);
    await (db.update(db.aiResults)).write(
      const AiResultsCompanion(promptVersion: Value(aiPromptVersion - 1)),
    );
    expect(await repo.input(g0), isNull);
  });
}
