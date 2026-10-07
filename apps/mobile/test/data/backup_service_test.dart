import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late FileStorage storage;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma-test-');
    storage = FileStorage(root);
    await storage.ensureDirs();

    final book = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Walden',
            fileName: const Value('abc.epub'),
            coverName: const Value('abc.png'),
            hash: const Value('abc'),
            parserVersion: 1,
            totalChars: 10,
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
        .into(db.aiResults)
        .insert(
          AiResultsCompanion.insert(
            chapterId: ch,
            groupIndex: 0,
            translations: '["Satu."]',
            meaning: 'M.',
            model: 'm',
          ),
        );
    await db
        .into(db.settings)
        .insert(SettingsCompanion.insert(key: 'ai.model', value: 'x/y'));
    await storage.book('abc.epub').writeAsBytes(List.filled(5000, 7));
    await storage.cover('abc.png').writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('zip holds manifest, a working DB snapshot, books and covers', () async {
    String? started;
    final stages = <BackupStage>{};
    final backup = (await BackupService(db, storage).export(
      now: DateTime(2026, 10, 6, 21, 30),
      onStart: (name, _) => started = name,
      onProgress: (stage, _) => stages.add(stage),
    ))!;
    addTearDown(backup.dispose);

    expect(backup.name, 'luma-backup-20261006-2130.zip');
    expect(started, backup.name);
    expect(stages, BackupStage.values.toSet());
    expect(backup.size, greaterThan(0));

    final zip = ZipDecoder().decodeBytes(await backup.file.readAsBytes());
    expect(zip.files.map((f) => f.name).toSet(), {
      'books/abc.epub',
      'covers/abc.png',
      'luma.sqlite',
      'manifest.json',
    });
    expect(zip.findFile('books/abc.epub')!.content, hasLength(5000));

    final manifest = jsonDecode(
      utf8.decode(zip.findFile('manifest.json')!.content),
    ) as Map<String, Object?>;
    expect(manifest['format'], 'luma-backup');
    expect(manifest['formatVersion'], 1);
    expect(manifest['appVersion'], appVersion);
    expect(manifest['schemaVersion'], db.schemaVersion);
    expect(manifest['counts'], {'books': 1, 'aiResults': 1});
    expect(manifest['createdAt'], startsWith('2026-10-06T21:30:00'));

    // The snapshot is a real database with the same data.
    final dir = await Directory.systemTemp.createTemp('luma-restore-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/luma.sqlite')
      ..writeAsBytesSync(zip.findFile('luma.sqlite')!.content);
    final copy = AppDatabase(NativeDatabase(file));
    addTearDown(copy.close);
    expect((await copy.select(copy.books).getSingle()).title, 'Walden');
    expect(await copy.select(copy.aiResults).get(), hasLength(1));
    expect((await copy.select(copy.settings).getSingle()).value, 'x/y');
  });

  test('dispose removes the temporary zip', () async {
    final backup = (await BackupService(db, storage).export())!;
    final dir = backup.file.parent;
    await backup.dispose();
    expect(dir.existsSync(), isFalse);
  });

  test('cancel: nothing left behind', () async {
    final before = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('luma-backup-'))
        .length;
    final backup = await BackupService(
      db,
      storage,
    ).export(cancel: Future.value());
    expect(backup, isNull);
    final after = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('luma-backup-'))
        .length;
    expect(after, before);
  });
}
