import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_search_index.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late BookSearchIndex index;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    index = BookSearchIndex(db);
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

  Future<int> chapter(int bookId, int order) => db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          bookId: bookId,
          sortOrder: order,
          title: 'C$order',
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
          type: type,
          content: text,
        ),
      );

  Future<List<String>> hits(String match) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT p.text FROM paragraph_fts f '
              'JOIN paragraphs p ON p.rowid = f.rowid '
              'WHERE paragraph_fts MATCH ? ORDER BY p.rowid',
              variables: [Variable(match)],
            )
            .get())
      r.read<String>('text'),
  ];

  // Cek internal index aja: sengaja parsial (scene break, buku belum ke-index),
  // jadi gak dibandingin sama isi `paragraphs` (mode rank = 1).
  Future<void> integrity() => db.customStatement(
    "INSERT INTO paragraph_fts(paragraph_fts) VALUES('integrity-check')",
  );

  test('insert indexes paragraphs and headings, skips scene breaks', () async {
    final c = await chapter(await book('a'), 0);
    await para(c, 0, 'Chapter I', type: ParagraphType.heading);
    await para(c, 1, 'Netherfield Park is let at last');
    await para(c, 2, '* * * netherfield', type: ParagraphType.sceneBreak);
    expect(await hits('"netherfield"'), ['Netherfield Park is let at last']);
    expect(await hits('"chapter"'), ['Chapter I']);
    await integrity();
  });

  test('case, accents and curly quotes are ignored', () async {
    final c = await chapter(await book('a'), 0);
    await para(c, 0, 'A Café near Brontë’s house, don’t you think?');
    expect(await hits('"cafe"'), hasLength(1));
    expect(await hits('"CAFÉ"'), hasLength(1));
    expect(await hits('"bronte"*'), hasLength(1));
    expect(await hits('"don\'t"'), hasLength(1));
    expect(await hits('"don’t"'), hasLength(1));
  });

  test('update re-indexes; delete and book cascade remove', () async {
    final id = await book('a');
    final c = await chapter(id, 0);
    await para(c, 0, 'old words here');
    await (db.update(db.paragraphs)..where((p) => p.chapterId.equals(c))).write(
      const ParagraphsCompanion(content: Value('fresh words here')),
    );
    expect(await hits('"old"'), isEmpty);
    expect(await hits('"fresh"'), hasLength(1));
    await (db.delete(db.books)..where((b) => b.id.equals(id))).go();
    expect(await hits('"fresh"'), isEmpty);
    await integrity();
  });

  test('re-import (delete + insert) leaves one hit', () async {
    final c = await chapter(await book('a'), 0);
    await para(c, 0, 'Bingley arrived');
    await (db.delete(db.paragraphs)..where((p) => p.chapterId.equals(c))).go();
    await para(c, 0, 'Bingley arrived');
    expect(await hits('"bingley"'), hasLength(1));
    await integrity();
  });

  test('backfill indexes only the given book, reports progress', () async {
    final a = await book('a');
    final b = await book('b');
    final ca = await chapter(a, 0);
    final ca2 = await chapter(a, 1);
    final cb = await chapter(b, 0);
    // Simulasi baris lama: trigger dimatiin pas insert.
    await db.customStatement('DROP TRIGGER paragraph_fts_ai');
    await para(ca, 0, 'wickham in meryton');
    await para(ca2, 0, 'wickham again');
    await para(cb, 0, 'wickham elsewhere');
    await db.createBookSearchFts();
    expect(await index.isIndexed(a), isFalse);
    expect(await index.isIndexed(b), isFalse);

    final progress = <double>[];
    await index.ensureIndexed(a, onProgress: progress.add);
    expect(progress, [0, 0.5, 1]);
    expect(await index.isIndexed(a), isTrue);
    expect(await index.isIndexed(b), isFalse);
    expect(await hits('"wickham"'), hasLength(2));

    await index.ensureIndexed(a); // idempotent, no duplicate rows
    expect(await hits('"wickham"'), hasLength(2));
    await integrity();
  });

  test('deleting never-indexed rows does not corrupt the index', () async {
    final a = await book('a');
    final b = await book('b');
    final ca = await chapter(a, 0);
    final cb = await chapter(b, 0);
    await db.customStatement('DROP TRIGGER paragraph_fts_ai');
    await para(ca, 0, 'legacy text');
    await db.createBookSearchFts();
    await para(cb, 0, 'modern text');
    await (db.delete(db.books)..where((x) => x.id.equals(a))).go();
    expect(await hits('"modern"'), hasLength(1));
    await integrity();
  });

  test('rebuild realigns the index after rowids shift', () async {
    final c = await chapter(await book('a'), 0);
    await para(c, 0, 'alpha');
    await para(c, 1, 'beta');
    await db.customStatement('UPDATE paragraphs SET rowid = rowid + 10');
    expect(await hits('"alpha"'), isEmpty); // index masih nunjuk rowid lama
    await db.rebuildBookSearchIndex();
    expect(await hits('"alpha"'), ['alpha']);
    expect(await hits('"beta"'), ['beta']);
    await integrity();
  });
}
