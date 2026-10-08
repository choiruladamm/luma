import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';

import 'migration_test.dart' show v4;

/// One "phone": a real database file in Documents plus books/ and covers/.
class Phone {
  Phone._(this.root, this.storage, this.db);

  final Directory root;
  final FileStorage storage;
  AppDatabase db;

  static Future<Phone> make() async {
    final root = await Directory.systemTemp.createTemp('luma-phone-');
    final storage = FileStorage(root);
    await storage.ensureDirs();
    return Phone._(root, storage, _open(root));
  }

  static AppDatabase _open(Directory root) =>
      AppDatabase(NativeDatabase(File('${root.path}/luma.sqlite')));

  /// What the app does after a restore: open the database file again.
  void reopen() => db = _open(root);

  Future<void> addBook(String title, {bool translated = false}) async {
    final hash = title.toLowerCase();
    final book = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: title,
            fileName: Value('$hash.epub'),
            coverName: Value('$hash.png'),
            hash: Value(hash),
            parserVersion: 1,
            totalChars: 100,
            readingSeconds: const Value(42),
            finishedAt: Value(DateTime(2026, 10, 7, 21)),
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
    await db
        .into(db.paragraphs)
        .insert(
          ParagraphsCompanion.insert(
            chapterId: ch,
            paragraphIndex: 0,
            groupIndex: const Value(0),
            type: ParagraphType.paragraph,
            content: 'Hello $title',
          ),
        );
    await db
        .into(db.readingProgress)
        .insert(
          ReadingProgressCompanion.insert(
            bookId: Value(book),
            chapterId: ch,
            paragraphIndex: 0,
            paragraphOffset: const Value(0.4),
          ),
        );
    // Stats (#42): only kept on the phone, so the backup must carry them.
    await db
        .into(db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: book,
            chapterId: ch,
            startedAt: DateTime(2026, 10, 7, 20),
            seconds: 300,
            startChar: 0,
            endChar: 40,
          ),
        );
    await db
        .into(db.aiCalls)
        .insert(
          AiCallsCompanion.insert(
            bookId: Value(book),
            chapterId: Value(ch),
            groupIndex: const Value(0),
            kind: AiCallKind.group,
            model: 'm',
            promptVersion: 4,
            chars: 11,
            costUsd: const Value(0.0002),
          ),
        );
    if (translated) {
      await db
          .into(db.aiResults)
          .insert(
            AiResultsCompanion.insert(
              chapterId: ch,
              groupIndex: 0,
              translations: '["Halo"]',
              meaning: 'Sapaan.',
              model: 'm',
              openCount: const Value(3),
              lastOpenedAt: Value(DateTime(2026, 10, 7, 21)),
            ),
          );
      await db
          .into(db.aiBreakdowns)
          .insert(
            AiBreakdownsCompanion.insert(
              chapterId: ch,
              groupIndex: 0,
              body: '[BAGIAN K1-K1]\nJudul: S\nMaksudnya: M\nLogikanya: L',
              sourceHash: 'h',
              model: 'm',
              promptVersion: 1,
            ),
          );
    }
    await storage.book('$hash.epub').writeAsString('epub of $title');
    await storage.cover('$hash.png').writeAsString('cover of $title');
  }

  /// Every row of every table, for comparing two phones.
  Future<List<Object>> dump() async => [
    await db.select(db.books).get(),
    await db.select(db.chapters).get(),
    await db.select(db.paragraphs).get(),
    await db.select(db.readingProgress).get(),
    await db.select(db.aiResults).get(),
    await db.select(db.aiBreakdowns).get(),
    await db.select(db.readingSessions).get(),
    await db.select(db.aiCalls).get(),
    await db.select(db.settings).get(),
  ];

  List<String> files(String dir) => [
    for (final f in Directory('${root.path}/$dir').listSync())
      '${f.uri.pathSegments.last}=${File(f.path).readAsStringSync()}',
  ]..sort();

  Future<void> dispose() async {
    await db.close();
    await root.delete(recursive: true);
  }
}

void main() {
  late Phone a;
  late Phone b;

  setUp(() async {
    a = await Phone.make();
    b = await Phone.make();
    await a.addBook('Walden', translated: true);
    await a.addBook('Emma');
    await a.db
        .into(a.db.settings)
        .insert(SettingsCompanion.insert(key: 'ai.model', value: 'x/y'));
    await b.addBook('Dracula'); // what's on the phone before restoring
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  Future<File> backupOf(Phone phone) async {
    final backup = (await BackupService(phone.db, phone.storage).export())!;
    addTearDown(backup.dispose);
    return backup.file;
  }

  test('round trip: export, restore onto another phone, same data', () async {
    final zip = await backupOf(a);
    final service = RestoreService(b.db, b.storage);
    expect(await service.currentBooks(), 1);

    final preview = await service.inspect(zip);
    expect(preview.manifest.books, 2);
    expect(preview.manifest.aiResults, 1);
    final stages = <int>[];
    await service.apply(preview, onStage: stages.add);
    expect(stages, [1, 2]);
    expect(preview.dir.existsSync(), isFalse);

    b.reopen();
    expect(await b.dump(), await a.dump());
    // Not empty == empty: the stats really came across.
    expect(await b.db.select(b.db.readingSessions).get(), hasLength(2));
    expect(await b.db.select(b.db.aiCalls).get(), hasLength(2));
    final walden = await (b.db.select(
      b.db.books,
    )..where((x) => x.title.equals('Walden'))).getSingle();
    expect(walden.finishedAt, DateTime(2026, 10, 7, 21));
    expect((await b.db.select(b.db.aiResults).getSingle()).openCount, 3);
    expect(await b.db.select(b.db.aiBreakdowns).get(), hasLength(1));
    expect(b.files('books'), a.files('books'));
    expect(b.files('covers'), a.files('covers'));
    // Nothing of the old data or the swap left behind.
    expect(
      b.root.listSync().map(
        (e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last,
      ),
      unorderedEquals(['luma.sqlite', 'books', 'covers']),
    );
  });

  test(
    'closing the database twice is fine (provider dispose after restore)',
    () async {
      final zip = await backupOf(a);
      final service = RestoreService(b.db, b.storage);
      await service.apply(await service.inspect(zip));
      await b.db.close(); // appDatabaseProvider's onDispose does this again
    },
  );

  Matcher fails(RestoreError e) =>
      throwsA(isA<RestoreException>().having((x) => x.error, 'error', e));

  Future<File> zipOf(Map<String, List<int>> files) async {
    final dir = await Directory.systemTemp.createTemp('luma-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final archive = Archive();
    for (final MapEntry(:key, :value) in files.entries) {
      archive.add(ArchiveFile.bytes(key, value));
    }
    return File('${dir.path}/x.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('not a zip, or a zip that is not a Luma backup', () async {
    final service = RestoreService(b.db, b.storage);
    final dir = await Directory.systemTemp.createTemp('luma-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final junk = File('${dir.path}/junk.zip')..writeAsStringSync('hello');
    await expectLater(service.inspect(junk), fails(RestoreError.notBackup));
    await expectLater(
      service.inspect(await zipOf({'notes.txt': utf8.encode('hi')})),
      fails(RestoreError.notBackup),
    );
    await expectLater(
      service.inspect(
        await zipOf({'manifest.json': utf8.encode('{"format": "other"}')}),
      ),
      fails(RestoreError.notBackup),
    );
  });

  Map<String, Object> manifest({int schema = 1}) => {
    'format': 'luma-backup',
    'formatVersion': 1,
    'appVersion': '0.3.0',
    'schemaVersion': schema,
    'createdAt': '2026-11-20T10:00:00+07:00',
    'counts': {'books': 1, 'aiResults': 0},
  };

  test('made by a newer Luma: refused, version reported', () async {
    final zip = await zipOf({
      'manifest.json': utf8.encode(jsonEncode(manifest(schema: 99))),
    });
    await expectLater(
      RestoreService(b.db, b.storage).inspect(zip),
      throwsA(
        isA<RestoreException>()
            .having((e) => e.error, 'error', RestoreError.tooNew)
            .having((e) => e.manifest?.appVersion, 'version', '0.3.0'),
      ),
    );
  });

  test('a broken database inside is caught before anything changes', () async {
    final zip = await zipOf({
      'manifest.json': utf8.encode(jsonEncode(manifest())),
      'luma.sqlite': utf8.encode('definitely not sqlite'),
    });
    await expectLater(
      RestoreService(b.db, b.storage).inspect(zip),
      fails(RestoreError.corrupt),
    );
    expect(await RestoreService(b.db, b.storage).currentBooks(), 1);
  });

  test('odd paths in the zip are never written outside', () async {
    final real = await backupOf(a);
    final archive = ZipDecoder().decodeBytes(real.readAsBytesSync());
    archive.add(ArchiveFile.bytes('../escape.txt', utf8.encode('x')));
    archive.add(ArchiveFile.bytes('books/../../evil.epub', utf8.encode('x')));
    final dir = await Directory.systemTemp.createTemp('luma-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final zip = File('${dir.path}/odd.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final preview = await RestoreService(b.db, b.storage).inspect(zip);
    addTearDown(preview.discard);
    expect(File('${preview.dir.parent.path}/escape.txt').existsSync(), isFalse);
    expect(
      Directory('${preview.dir.path}/books')
          .listSync()
          .map((e) => e.uri.pathSegments.last),
      unorderedEquals(['emma.epub', 'walden.epub']),
    );
  });

  test('a failure half way puts the old data back', () async {
    final zip = await backupOf(a);
    final service = RestoreService(b.db, b.storage);
    final preview = await service.inspect(zip);
    final before = await b.dump();
    final booksBefore = b.files('books');
    // The new database goes missing: the last step fails after the books
    // were already swapped.
    File('${preview.dir.path}/luma.sqlite').deleteSync();

    await expectLater(
      service.apply(preview),
      throwsA(isA<FileSystemException>()),
    );
    await preview.discard();

    b.reopen();
    expect(await b.dump(), before);
    expect(b.files('books'), booksBefore);
  });

  test(
    'a backup from schema 4 restores: old data kept, stats start empty',
    () async {
      final dir = await Directory.systemTemp.createTemp('luma-v4-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/luma.sqlite');
      final old = NativeDatabase(
        file,
        setup: (raw) {
          for (final sql in v4) {
            raw.execute(sql);
          }
          raw.execute(
            "INSERT INTO books (source_type, title, hash, parser_version, "
            "total_chars, reading_seconds) "
            "VALUES ('epub', 'Meditations', 'm', 1, 100, 600)",
          );
          raw.execute(
            "INSERT INTO chapters (book_id, sort_order, title, char_offset) "
            "VALUES (1, 0, 'I', 0)",
          );
          raw.execute(
            'INSERT INTO ai_results (chapter_id, group_index, translations, '
            "meaning, model, prompt_version) VALUES (1, 0, '[\"a\"]', 'm', 'x', 4)",
          );
        },
      );
      await old.ensureOpen(_Schema4());
      await old.close();
      final zip = await zipOf({
        'manifest.json': utf8.encode(jsonEncode(manifest(schema: 4))),
        'luma.sqlite': file.readAsBytesSync(),
      });

      final service = RestoreService(b.db, b.storage);
      await service.apply(await service.inspect(zip));
      b.reopen();

      final book = await b.db.select(b.db.books).getSingle();
      expect(book.title, 'Meditations');
      expect(book.readingSeconds, 600);
      expect(book.finishedAt, isNull);
      final cached = await b.db.select(b.db.aiResults).getSingle();
      expect(cached.promptVersion, 4);
      expect(cached.openCount, 0);
      expect(await b.db.select(b.db.readingSessions).get(), isEmpty);
      expect(await b.db.select(b.db.aiCalls).get(), isEmpty);
    },
  );
}

/// Opens a raw database at user_version 4 without any migration.
class _Schema4 implements QueryExecutorUser {
  @override
  int get schemaVersion => 4;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
