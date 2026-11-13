import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/repositories/sync_repository.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/cloud_backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/sync_service.dart';

import '../support/backend_fakes.dart';

class _Auth extends Fake implements AuthRepository {
  String? value = 'tok';

  @override
  Future<String?> token() async => value;
}

/// Worker palsu: `/v1/sync/push` + `/v1/files/*`, simpan semua di memori.
class _Worker implements HttpClientAdapter {
  final pushes = <Map<String, Object?>>[];
  final files = <String, Uint8List>{};
  final log = <String>[];

  /// Dibalas duluan sebelum logika server, per request.
  final queue = <ResponseBody>[];

  /// Jalan di tengah push (sebelum respons): simulasi perubahan lokal.
  Future<void> Function()? duringPush;

  /// Nama file yang upload-nya dibalas 500.
  final failUploads = <String>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    log.add('${options.method} $path');
    if (queue.isNotEmpty) return queue.removeAt(0);
    if (path == '/v1/sync/push') {
      pushes.add((options.data as Map).cast<String, Object?>());
      await duringPush?.call();
      final count = pushes.fold<int>(
        0,
        (n, p) => n + (p['records']! as List).length,
      );
      return json(200, {'seq': count, 'applied': count});
    }
    if (path == '/v1/files/missing') {
      final names = ((options.data as Map)['names'] as List).cast<String>();
      return json(200, {
        'missing': [
          for (final n in names)
            if (!files.containsKey(n)) n,
        ],
      });
    }
    final name = Uri.decodeComponent(path.substring('/v1/files/'.length));
    final body = Uint8List.fromList([
      await for (final c in requestStream!) ...c,
    ]);
    if (failUploads.contains(name)) {
      return json(500, {
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
      });
    }
    files[name] = body;
    return json(200, {'name': name, 'size': body.length});
  }

  @override
  void close({bool force = false}) {}

  List<Map<String, Object?>> get records => [
    for (final p in pushes)
      for (final r in p['records']! as List) (r as Map).cast<String, Object?>(),
  ];
}

void main() {
  late AppDatabase db;
  late _Worker worker;
  late _Auth auth;
  late Directory tmp;
  late FileStorage storage;
  late DateTime now;
  late SyncRepository repo;

  Future<List<String>> outbox() async => [
    for (final o in await db.select(db.syncOutbox).get()) '${o.kind} ${o.key}',
  ];

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    worker = _Worker();
    auth = _Auth();
    tmp = await Directory.systemTemp.createTemp('luma-sync-test-');
    storage = FileStorage(tmp);
    await storage.ensureDirs();
    now = DateTime.utc(2026, 11, 13, 10);
    final client = BackendClient(
      baseUrl: 'https://luma.test',
      dio: Dio()..httpClientAdapter = worker,
      sleep: (_) async {},
    );
    repo = SyncRepository(
      db: db,
      service: SyncService(client),
      files: CloudBackupService(client),
      storage: storage,
      auth: auth,
      clock: () => now,
    );
    await db.customStatement(
      'INSERT INTO books (id, source_type, title, hash, parser_version, '
      "total_chars) VALUES (1, 'epub', 'Meditations', 'h1', 9, 100)",
    );
    await db.customStatement(
      'INSERT INTO chapters (id, book_id, sort_order, title, char_offset) '
      "VALUES (10, 1, 4, 'IV', 0)",
    );
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('push sends natural keys, then clears the outbox (contract)', () async {
    await db.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index) '
      'VALUES (1, 10, 37)',
    );

    expect(await repo.push(), 2);

    final body = worker.pushes.single;
    final fixture = (contract('sync-push')['request']! as Map)['body']! as Map;
    expect(body.keys, unorderedEquals(fixture.keys));
    expect(body['schemaVersion'], db.schemaVersion);
    final sent = {
      for (final r in worker.records) '${r['kind']} ${r['key']}': r,
    };
    expect(sent.keys, unorderedEquals(['book h1', 'reading_progress h1']));
    // Bentuk record sama dengan fixture kontrak (field data ikut dicek).
    final fixtureBook = (fixture['records']! as List).first as Map;
    expect(sent['book h1']!.keys, unorderedEquals(fixtureBook.keys));
    expect(
      (sent['book h1']!['data']! as Map).keys,
      unorderedEquals((fixtureBook['data']! as Map).keys),
    );
    expect(sent['book h1']!['deleted'], false);
    expect(
      DateTime.parse(sent['book h1']!['updatedAt']! as String).isUtc,
      isTrue,
    );
    expect(await outbox(), isEmpty);
  });

  test('service parses seq from the contract response', () async {
    worker.queue.add(fromContract(contract('sync-push')));
    final result =
        await SyncService(
          BackendClient(
            baseUrl: 'https://luma.test',
            dio: Dio()..httpClientAdapter = worker,
          ),
        ).push('tok', 18, const [
          SyncRecord(kind: 'setting', key: 'k', updatedAt: 0),
        ]);
    expect(result, (seq: 3, applied: 3));
  });

  test('a deleted book goes out as a tombstone', () async {
    await repo.push();
    await db.customStatement('DELETE FROM books WHERE id = 1');

    await repo.push();

    final tomb = worker.pushes.last['records']! as List;
    expect(tomb.single, containsPair('deleted', true));
    expect(tomb.single, containsPair('data', null));
    expect(await outbox(), isEmpty);
  });

  test('a row changed while pushing stays queued for the next push', () async {
    worker.duringPush = () async {
      worker.duringPush = null;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.customStatement("UPDATE books SET title = 'Edited'");
    };

    await repo.push();

    expect(await outbox(), ['book h1']);
    await repo.push();
    expect((worker.records.last['data']! as Map)['title'], 'Edited');
    expect(await outbox(), isEmpty);
  });

  test('big queues go out 500 at a time', () async {
    await db.transaction(() async {
      for (var i = 0; i < 1200; i++) {
        await db.customStatement(
          'INSERT INTO reading_sessions (book_id, chapter_id, started_at, '
          'seconds, start_char, end_char) VALUES (1, 10, ${1790000000 + i}, '
          '30, 0, 10)',
        );
      }
    });

    expect(await repo.push(), 1201);

    expect(
      [for (final p in worker.pushes) (p['records']! as List).length],
      [500, 500, 201],
    );
    expect(await outbox(), isEmpty);
  });

  test('rows that vanished without a tombstone kind are dropped', () async {
    await repo.push();
    await db.customStatement(
      "INSERT INTO sync_outbox VALUES ('ai_result', 'h1/4/99', 1)",
    );
    worker.pushes.clear();

    expect(await repo.push(), 0);
    expect(worker.pushes, isEmpty);
    expect(await outbox(), isEmpty);
  });

  test('signed out: nothing is sent and the queue is kept', () async {
    auth.value = null;
    expect(await repo.push(), 0);
    expect(worker.log, isEmpty);
    expect(await outbox(), ['book h1']);
  });

  test('503 with Retry-After pauses pushes until it passes', () async {
    worker.queue.add(fromContract(contract('error-service-disabled')));

    expect(await repo.push(), 0);
    expect(await outbox(), ['book h1']);

    worker.log.clear();
    now = now.add(const Duration(minutes: 59));
    expect(await repo.push(), 0);
    expect(worker.log, isEmpty);

    now = now.add(const Duration(minutes: 2));
    expect(await repo.push(), 1);
  });

  test('resume pushes at most every 5 minutes', () async {
    await repo.pushIfDue();
    await db.customStatement("UPDATE books SET title = 'x'");
    worker.log.clear();

    now = now.add(const Duration(minutes: 4));
    await repo.pushIfDue();
    expect(worker.log, isEmpty);

    now = now.add(const Duration(minutes: 2));
    await repo.pushIfDue();
    expect(worker.log, contains('POST /v1/sync/push'));
  });

  test('book files and cover upload once alongside the book record', () async {
    await storage.book('h1.epub').writeAsString('epub');
    await storage.cover('h1.jpg').writeAsString('jpg');
    await db.customStatement(
      "UPDATE books SET file_name = 'h1.epub', cover_name = 'h1.jpg'",
    );

    await repo.push();

    expect(worker.files.keys, unorderedEquals(['h1.epub', 'h1.jpg']));
    expect(utf8.decode(worker.files['h1.epub']!), 'epub');

    await db.customStatement("UPDATE books SET title = 'x'");
    worker.log.clear();
    await repo.push();
    expect(worker.log.where((l) => l.startsWith('PUT')), isEmpty);
  });

  test('a failed file upload re-queues the book, not the others', () async {
    await storage.book('h1.epub').writeAsString('epub');
    await db.customStatement("UPDATE books SET file_name = 'h1.epub'");
    await db.customStatement(
      "INSERT INTO settings (key, value) VALUES ('ai.model', 'm')",
    );
    worker.failUploads.add('h1.epub');

    await repo.push();

    expect(await outbox(), ['book h1']);
    worker.failUploads.clear();
    await repo.push();
    expect(worker.files.keys, ['h1.epub']);
    expect(await outbox(), isEmpty);
  });

  test('Markdown books upload a gzip dump of chapters and groups', () async {
    await db.customStatement(
      'INSERT INTO books (id, source_type, title, book_key, parser_version, '
      "total_chars, content_revision) VALUES (2, 'markdown', 'Notes', "
      "'notes', 1, 10, 3)",
    );
    await db.customStatement(
      'INSERT INTO chapters (id, book_id, sort_order, title, char_offset) '
      "VALUES (20, 2, 0, 'I', 0)",
    );
    await db.customStatement(
      'INSERT INTO paragraphs (chapter_id, paragraph_index, group_index, type, '
      "text) VALUES (20, 0, NULL, 'heading', 'I'), "
      "(20, 1, 0, 'paragraph', 'Halo')",
    );

    await repo.push();

    final name = markdownDumpName('notes', 3);
    expect(name, 'md-notes-3.json.gz');
    final dump = jsonDecode(
      utf8.decode(gzip.decode(worker.files[name]!)),
    ) as Map<String, Object?>;
    expect(dump['bookKey'], 'notes');
    expect(dump['contentRevision'], 3);
    final chapter = (dump['chapters']! as List).single as Map;
    expect(chapter['title'], 'I');
    expect(chapter['paragraphs'], [
      [0, null, 'heading', 'I'],
      [1, 0, 'paragraph', 'Halo'],
    ]);
  });
}
