import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/repositories/sync_applier.dart';
import 'package:luma/data/repositories/sync_repository.dart';
import 'package:luma/data/services/auth_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/cloud_backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/sync_service.dart';

/// E2E #109 (`make backend-e2e`): client Dart asli push ke Worker lokal
/// (`wrangler dev`, D1/R2 lokal). Tanpa `LUMA_BACKEND_E2E` di-skip.
final _url = Platform.environment['LUMA_BACKEND_E2E'] ?? '';
final _invite = Platform.environment['LUMA_E2E_INVITE'] ?? '';

class _Auth extends Fake implements AuthRepository {
  _Auth(this.value);

  final String value;

  @override
  Future<String?> token() async => value;

  @override
  Future<String?> lastUserId() async => 'e2e';
}

/// [SyncService] asli yang nyatet hasil tiap push.
class _Spy extends SyncService {
  _Spy(super.client);

  final results = <({int seq, int applied})>[];

  @override
  Future<({int seq, int applied})> push(
    String token,
    int schemaVersion,
    List<SyncRecord> records,
  ) async {
    final r = await super.push(token, schemaVersion, records);
    results.add(r);
    return r;
  }
}

/// Satu "device": DB in-memory dengan buku yang sama (hash `e2e`).
class _Device {
  _Device(BackendClient client, String token, this.files)
    : db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ),
      spy = _Spy(client) {
    final storage = FileStorage(files);
    repo = SyncRepository(
      db: db,
      service: spy,
      files: CloudBackupService(client),
      storage: storage,
      auth: _Auth(token),
      applier: SyncApplier(db, storage),
      import: ImportRepository(db, storage),
    );
  }

  final AppDatabase db;
  final _Spy spy;
  final Directory files;
  late final SyncRepository repo;

  Future<void> seed({required int paragraph, required int at}) async {
    await db.customStatement(
      'INSERT INTO books (id, source_type, title, hash, parser_version, '
      "total_chars, created_at) VALUES (1, 'epub', 'Meditations', 'e2e', 9, "
      '100, 1790000000)',
    );
    await db.customStatement(
      'INSERT INTO chapters (id, book_id, sort_order, title, char_offset) '
      "VALUES (10, 1, 4, 'IV', 0)",
    );
    await db.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index) '
      'VALUES (1, 10, $paragraph)',
    );
    // Waktu outbox dipaku biar urutan last-write-wins jelas.
    await db.customStatement('UPDATE sync_outbox SET updated_at = $at');
  }
}

void main() {
  late BackendClient client;
  late String token;
  late Directory tmp;

  setUpAll(() async {
    if (_url.isEmpty) return; // test di-skip, jangan daftar akun
    client = BackendClient(baseUrl: _url, sleep: (_) async {});
    final session = await AuthService(client).signUpEmail(
      name: 'E2E',
      email: 'e2e-${DateTime.now().microsecondsSinceEpoch}@luma.test',
      password: 'rahasia-banget-123',
      inviteCode: _invite,
    );
    token = session.token;
    tmp = await Directory.systemTemp.createTemp('luma-e2e-');
  });

  tearDownAll(() async {
    if (_url.isNotEmpty) await tmp.delete(recursive: true);
  });

  test(
    'two devices push the same book; newer progress wins, re-push is free',
    () async {
      final a = _Device(client, token, tmp);
      final b = _Device(client, token, tmp);
      addTearDown(a.db.close);
      addTearDown(b.db.close);
      await a.seed(paragraph: 37, at: 1790000020000);
      await b.seed(paragraph: 5, at: 1790000010000);

      expect(await a.repo.push(), 2);
      expect(a.spy.results.single.applied, 2);

      // B lebih lama: buku sama persis & posisi kalah → server gak nulis.
      expect(await b.repo.push(), 2);
      expect(b.spy.results.single, (seq: 2, applied: 0));

      // B baca lagi (lebih baru) → menang.
      await b.db.customStatement(
        'UPDATE reading_progress SET paragraph_index = 50',
      );
      await b.repo.push();
      expect(b.spy.results.last, (seq: 3, applied: 1));

      // Hapus buku di A → tombstone diterima.
      await a.db.customStatement('DELETE FROM books');
      await a.repo.push();
      expect(a.spy.results.last.applied, 1);
    },
    skip: _url.isEmpty ? 'set LUMA_BACKEND_E2E (make backend-e2e)' : false,
  );

  test(
    'a big backfill and a Markdown book go through the real limits',
    () async {
      final c = _Device(client, token, tmp);
      addTearDown(c.db.close);
      await c.seed(paragraph: 1, at: 1790000030000);
      await c.db.transaction(() async {
        for (var i = 0; i < 1200; i++) {
          await c.db.customStatement(
            'INSERT INTO ai_results (chapter_id, group_index, translations, '
            "meaning, model, prompt_version) VALUES (10, $i, "
            "'[\"${'terjemahan ' * 40}\"]', '${'makna ' * 60}', 'm', 3)",
          );
        }
      });
      await c.db.customStatement(
        'INSERT INTO books (id, source_type, title, book_key, parser_version, '
        "total_chars) VALUES (2, 'markdown', 'Notes', 'e2e-notes', 1, 10)",
      );

      final sent = await c.repo.push();

      expect(sent, 1203); // 2 buku + posisi + 1200 hasil AI
      expect(c.spy.results.length, greaterThan(2)); // dibatasi 500 & ±900KB
      expect(await c.db.select(c.db.syncOutbox).get(), isEmpty);
      final missing = await CloudBackupService(client)
          .missing(token, [markdownDumpName('e2e-notes', 1)]);
      expect(missing, isEmpty);
    },
    skip: _url.isEmpty ? 'set LUMA_BACKEND_E2E (make backend-e2e)' : false,
  );

  test('A imports and reads, B pulls: same book once, same data, newer schema held', () async {
    // Akun baru: data akun tes lain gak ikut kecampur.
    final session = await AuthService(client).signUpEmail(
      name: 'E2E pull',
      email: 'e2e-pull-${DateTime.now().microsecondsSinceEpoch}@luma.test',
      password: 'rahasia-banget-123',
      inviteCode: Platform.environment['LUMA_E2E_INVITE2'] ?? '',
    );
    final aDir = await tmp.createTemp('a-');
    final bDir = await tmp.createTemp('b-');
    final a = _Device(client, session.token, aDir);
    final b = _Device(client, session.token, bDir);
    addTearDown(a.db.close);
    addTearDown(b.db.close);
    await FileStorage(aDir).ensureDirs();
    await FileStorage(bDir).ensureDirs();

    final imported = await ImportRepository(a.db, FileStorage(aDir)).importEpub(
      await File('test/fixtures/alice-in-wonderland.epub').readAsBytes(),
      fileName: 'alice-in-wonderland.epub',
    );
    final chapter =
        (await a.db
                .customSelect(
                  'SELECT id FROM chapters WHERE book_id = ? ORDER BY sort_order '
                  'LIMIT 1 OFFSET 1',
                  variables: [Variable(imported.bookId)],
                )
                .getSingle())
            .read<int>('id');
    await a.db.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index) '
      'VALUES (?, ?, 4)',
      [imported.bookId, chapter],
    );
    await a.db.customStatement(
      'INSERT INTO ai_results (chapter_id, group_index, translations, '
      "meaning, model, prompt_version) VALUES (?, 1, '[\"t\"]', 'm', 'x', 3)",
      [chapter],
    );
    await a.repo.push();
    // Record dari app versi lebih baru: B harus nahan, bukan nerapin.
    await SyncService(client).push(session.token, a.db.schemaVersion + 1, [
      const SyncRecord(
        kind: 'setting',
        key: 'ai.model',
        updatedAt: 1790000000000,
        data: {'value': 'future/model'},
      ),
    ]);

    await b.repo.sync();
    await b.repo.sync(); // kedua kalinya: buku gak dobel

    expect(await b.db.select(b.db.books).get(), hasLength(1));
    expect(
      (await b.db.select(b.db.readingProgress).getSingle()).paragraphIndex,
      4,
    );
    expect(await b.db.select(b.db.aiResults).get(), hasLength(1));
    final held = await b.db.select(b.db.syncInbox).getSingle();
    expect((held.kind, held.key), ('setting', 'ai.model'));
    expect(
      await b.db.select(b.db.settings).get(),
      isNot(contains(predicate<Setting>((s) => s.value == 'future/model'))),
    );
  }, skip: _url.isEmpty ? 'set LUMA_BACKEND_E2E (make backend-e2e)' : false);
}
