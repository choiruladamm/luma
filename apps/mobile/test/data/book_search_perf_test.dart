import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_search_index.dart';
import 'package:luma/data/repositories/book_search_repository.dart';
import 'package:luma/domain/models/book.dart';

/// Buku besar sintetis: 150 bab × 100 paragraf ≈ 15 000 paragraf, ±1,5 MB.
/// Ngejaga janji "nyarinya langsung kilat" (docs/book-search.md).
void main() {
  late AppDatabase db;
  late int bookId;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    bookId = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Big',
            hash: const Value('big'),
            parserVersion: 1,
            totalChars: 1,
          ),
        );
    final rnd = Random(7);
    const words = [
      'the',
      'and',
      'of',
      'to',
      'in',
      'a',
      'he',
      'she',
      'was',
      'that',
      'house',
      'garden',
      'letter',
      'morning',
      'father',
      'river',
      'quiet',
    ];
    // Satu transaksi per bab, trigger ikut jalan (jalur import beneran).
    for (var c = 0; c < 150; c++) {
      final chapter = await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: bookId,
              sortOrder: c,
              title: 'Chapter $c',
              charOffset: c * 1000,
            ),
          );
      await db.batch(
        (b) => b.insertAll(db.paragraphs, [
          for (var i = 0; i < 100; i++)
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: i,
              type: ParagraphType.paragraph,
              content:
                  '${List.generate(30, (_) => words[rnd.nextInt(words.length)]).join(' ')}'
                  '${c == 99 && i == 50 ? ' zanzibar' : ''}.',
            ),
        ]),
      );
    }
  });
  tearDown(() => db.close());

  Future<Duration> timed(Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    return watch.elapsed;
  }

  test(
    'rare word, common word and phrase stay fast on 15 000 paragraphs',
    () async {
      final repo = BookSearchRepository(db);
      final rare = await timed(() async {
        final r = await repo.search(bookId, 'zanzibar');
        expect(r.total, 1);
        expect(r.chapters.single.title, 'Chapter 99');
      });
      late int commonTotal;
      final common = await timed(() async {
        final r = await repo.search(bookId, 'the');
        commonTotal = r.total;
        expect(r.shown, 500); // capped
        expect(r.truncated, isTrue);
      });
      final phrase = await timed(() async {
        expect(
          (await repo.search(bookId, 'quiet river')).total,
          greaterThan(0),
        );
      });
      // ignore: avoid_print
      print(
        'search 15k paragraphs: rare ${rare.inMilliseconds} ms, '
        '"the" ($commonTotal hits) ${common.inMilliseconds} ms, '
        'phrase ${phrase.inMilliseconds} ms',
      );
      // Longgar (CI/laptop lambat) tapi jauh di bawah "terasa".
      expect(rare, lessThan(const Duration(milliseconds: 250)));
      expect(common, lessThan(const Duration(milliseconds: 1000)));
      expect(phrase, lessThan(const Duration(milliseconds: 500)));
    },
  );

  test('backfilling a 150-chapter book yields between chapters', () async {
    await db.customStatement('DELETE FROM paragraph_fts');
    await db.rebuildBookSearchIndex(); // reset ke kondisi tanpa index
    await db.customStatement(
      "INSERT INTO paragraph_fts(paragraph_fts) VALUES('delete-all')",
    );
    final index = BookSearchIndex(db);
    expect(await index.isIndexed(bookId), isFalse);
    var steps = 0;
    final took = await timed(
      () => index.ensureIndexed(bookId, onProgress: (_, _) => steps++),
    );
    // ignore: avoid_print
    print('backfill 15k paragraphs: ${took.inMilliseconds} ms, $steps steps');
    expect(steps, 151); // 0 + satu per bab: UI dapet giliran di sela
    expect(await index.isIndexed(bookId), isTrue);
    expect(
      (await BookSearchRepository(db).search(bookId, 'zanzibar')).total,
      1,
    );
  });

  test('two backfills at once never duplicate rows', () async {
    await db.customStatement(
      "INSERT INTO paragraph_fts(paragraph_fts) VALUES('delete-all')",
    );
    final index = BookSearchIndex(db);
    await Future.wait([
      index.ensureIndexed(bookId),
      index.ensureIndexed(bookId),
    ]);
    expect(
      (await BookSearchRepository(db).search(bookId, 'zanzibar')).total,
      1,
    );
    final rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM paragraph_fts_docsize')
        .getSingle();
    expect(rows.read<int>('n'), 15000);
  });
}
