import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/data/repositories/book_search_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/book_search.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late BookSearchRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = BookSearchRepository(db);
  });
  tearDown(() => db.close());

  Future<int> book(String hash) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: 'B $hash',
          hash: Value(hash),
          parserVersion: 1,
          totalChars: 1,
        ),
      );

  Future<int> chapter(int bookId, int order, String title) => db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          bookId: bookId,
          sortOrder: order,
          title: title,
          charOffset: 0,
        ),
      );

  Future<void> para(
    int chapterId,
    int i,
    String text, {
    ParagraphType type = ParagraphType.paragraph,
  }) => db
      .into(db.paragraphs)
      .insert(
        ParagraphsCompanion.insert(
          chapterId: chapterId,
          paragraphIndex: i,
          groupIndex: type == ParagraphType.paragraph
              ? Value(i)
              : const Value(null),
          type: type,
          content: text,
        ),
      );

  test('hits come per chapter in book order, then paragraph order', () async {
    final id = await book('a');
    // Sengaja dimasukin kebalik: urutan baca ditentuin sort_order, bukan id.
    final c2 = await chapter(id, 1, 'Chapter II');
    final c1 = await chapter(id, 0, 'Chapter I');
    await para(c2, 0, 'Bingley called on Mr. Bennet.');
    await para(c1, 3, 'Then Bingley left.');
    await para(c1, 1, 'Bingley is rich.');
    await para(c1, 2, 'Nobody here.');

    final r = await repo.search(id, 'bingley');
    expect(r.total, 3);
    expect(r.chapterCount, 2);
    expect(r.truncated, isFalse);
    expect([for (final c in r.chapters) c.title], ['Chapter I', 'Chapter II']);
    expect([for (final h in r.chapters[0].hits) h.paragraphIndex], [1, 3]);
    final h = r.chapters[0].hits.first;
    expect(h.snippet.substring(h.matchStart, h.matchEnd), 'Bingley');
    expect(h.groupIndex, 1);
  });

  test('only the asked book is searched', () async {
    final a = await book('a');
    final b = await book('b');
    await para(await chapter(a, 0, 'I'), 0, 'Darcy in A');
    await para(await chapter(b, 0, 'I'), 0, 'Darcy in B');
    expect((await repo.search(a, 'darcy')).total, 1);
    expect(
      (await repo.search(b, 'darcy')).chapters.single.hits.single.snippet,
      'Darcy in B',
    );
  });

  test('case, accents, curly quotes; phrase must be adjacent', () async {
    final id = await book('a');
    final c = await chapter(id, 0, 'I');
    await para(c, 0, 'A Café by Brontë’s house, don’t you think?');
    await para(c, 1, 'The café was far from the house.');
    expect((await repo.search(id, 'CAFE')).total, 2);
    expect((await repo.search(id, 'bronte')).total, 1);
    expect((await repo.search(id, "don't")).total, 1);
    expect((await repo.search(id, 'café by')).total, 1);
    expect((await repo.search(id, 'café house')).total, 0);
  });

  test('short, empty and hostile queries never throw', () async {
    final id = await book('a');
    await para(await chapter(id, 0, 'I'), 0, 'Hello world');
    for (final q in ['', ' ', 'h', '"', '*', 'a OR', 'NEAR(', '-x']) {
      expect((await repo.search(id, q)).chapters, isEmpty, reason: q);
    }
    expect((await repo.search(id, 'hel')).total, 1); // prefix
    expect((await repo.search(id, '"hel')).total, 1); // kutip dibuang
    expect((await repo.search(id, '"hello" OR zzz')).total, 0);
  });

  test('scene breaks are not found, headings are', () async {
    final id = await book('a');
    final c = await chapter(id, 0, 'I');
    await para(c, 0, 'CHAPTER ONE', type: ParagraphType.heading);
    await para(c, 1, 'chapter one * * *', type: ParagraphType.sceneBreak);
    final r = await repo.search(id, 'chapter one');
    expect(r.total, 1);
    expect(r.chapters.single.hits.single.groupIndex, isNull);
  });

  test('over 500 hits: first 500 shown, real totals reported', () async {
    final id = await book('a');
    for (var ch = 0; ch < 3; ch++) {
      final c = await chapter(id, ch, 'C$ch');
      for (var i = 0; i < 200; i++) {
        await para(c, i, 'the quick fox $i');
      }
    }
    final r = await repo.search(id, 'quick fox');
    expect(r.shown, bookSearchMaxHits);
    expect(r.total, 600);
    expect(r.chapterCount, 3);
    expect(r.truncated, isTrue);
    expect(r.chapters.last.hits.last.paragraphIndex, 99); // 200+200+100
  });

  test('recents: newest first, deduped, max 5, only real queries', () async {
    final id = await book('a');
    expect(await repo.recentSearches(id), isEmpty);
    for (final q in ['one', 'two', 'three', 'four', 'five', 'six']) {
      await repo.saveRecent(id, q);
    }
    expect(await repo.recentSearches(id), [
      'six',
      'five',
      'four',
      'three',
      'two',
    ]);
    await repo.saveRecent(id, 'FOUR');
    expect((await repo.recentSearches(id)).first, 'FOUR');
    expect(
      (await repo.recentSearches(id)).where((q) => q.toLowerCase() == 'four'),
      hasLength(1),
    );
    await repo.saveRecent(id, 'x'); // terlalu pendek
    expect((await repo.recentSearches(id)).first, 'FOUR');
  });

  test('recents are per book; clear empties one book', () async {
    final a = await book('a');
    final b = await book('b');
    await repo.saveRecent(a, 'alpha');
    await repo.saveRecent(b, 'beta');
    await repo.clearRecents(a);
    expect(await repo.recentSearches(a), isEmpty);
    expect(await repo.recentSearches(b), ['beta']);
  });

  test('a corrupt recents value reads as empty', () async {
    final id = await book('a');
    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(
            key: bookSearchRecentKey(id),
            value: '{not json',
          ),
        );
    expect(await repo.recentSearches(id), isEmpty);
  });

  test('deleting the book drops its recents', () async {
    final id = await book('a');
    await repo.saveRecent(id, 'alpha');
    await BookRepository(db).delete(id, FileStorage(await _tmp()));
    expect(await db.select(db.settings).get(), isEmpty);
  });
}

Future<Directory> _tmp() async {
  final d = await Directory.systemTemp.createTemp('luma-search-');
  addTearDown(() => d.delete(recursive: true));
  return d;
}
