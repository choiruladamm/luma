import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/repositories/cloud_backup_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/cloud_backup_service.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/domain/models/backup.dart';

import '../support/backend_fakes.dart';
import 'restore_service_test.dart' show Phone;

class _Auth extends Fake implements AuthRepository {
  _Auth([this.value = 'tok']);

  String? value;

  @override
  Future<String?> token() async => value;
}

/// Worker palsu di memori: cukup buat `/v1/files/*` + `/v1/backups*`.
class _Cloud implements HttpClientAdapter {
  final files = <String, Uint8List>{};
  final backups = <String, (Uint8List, Map<String, Object?>)>{};
  final log = <String>[];

  /// Respons yang dibalas duluan sebelum logika server (mis. 500).
  final queue = <ResponseBody>[];

  /// Request pertama yang diawali ini dibalas 429 sekali.
  String? rateLimitNext;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final method = options.method;
    log.add('$method $path');
    if (queue.isNotEmpty) return queue.removeAt(0);
    if (rateLimitNext case final prefix?
        when '$method $path'.startsWith(prefix)) {
      rateLimitNext = null;
      return json(
        429,
        {
          'error': {'code': 'RATE_LIMITED', 'message': 'Too many requests'},
        },
        headers: {'Retry-After': '60'},
      );
    }
    Future<Uint8List> body() async =>
        Uint8List.fromList([await for (final c in requestStream!) ...c]);
    ResponseBody bytes(Uint8List? b) => b == null
        ? json(404, {
            'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
          })
        : ResponseBody(Stream.value(b), 200);

    if (method == 'POST' && path == '/v1/files/missing') {
      final names = ((options.data as Map)['names'] as List).cast<String>();
      return json(200, {
        'missing': [
          for (final n in names)
            if (!files.containsKey(n)) n,
        ],
      });
    }
    if (path.startsWith('/v1/files/')) {
      final name = Uri.decodeComponent(path.substring('/v1/files/'.length));
      if (method == 'GET') return bytes(files[name]);
      files[name] = await body();
      return json(200, {'name': name, 'size': files[name]!.length});
    }
    if (method == 'PUT' && path == '/v1/backups') {
      final m = jsonDecode(options.headers['x-backup-manifest'] as String);
      final counts = m['counts'] as Map;
      final id = '2026111${backups.length}T000000Z';
      final info = {
        'id': id,
        'createdAt': DateTime.parse(m['createdAt'] as String)
            .toUtc()
            .toIso8601String(),
        'size': 0,
        'books': counts['books'],
        'aiResults': counts['aiResults'],
        'schemaVersion': m['schemaVersion'],
        'appVersion': m['appVersion'],
      };
      final zip = await body();
      info['size'] = zip.length;
      backups[id] = (zip, info);
      return json(200, info);
    }
    if (path == '/v1/backups') {
      return json(200, {
        'backups': [for (final b in backups.values) b.$2].reversed.toList(),
      });
    }
    if (path.startsWith('/v1/backups/')) {
      return bytes(backups[path.substring('/v1/backups/'.length)]?.$1);
    }
    return json(404, {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  BackendClient client(HttpClientAdapter adapter) => BackendClient(
    baseUrl: 'https://luma.test',
    dio: Dio()..httpClientAdapter = adapter,
    sleep: (_) async {},
  );

  group('CloudBackupService (contract)', () {
    late FakeAdapter adapter;
    late CloudBackupService service;
    late Directory tmp;

    setUp(() async {
      adapter = FakeAdapter();
      service = CloudBackupService(client(adapter));
      tmp = await Directory.systemTemp.createTemp('luma-cloud-test-');
    });
    tearDown(() => tmp.delete(recursive: true));

    Map<String, Object?> request(String name) =>
        contract(name)['request']! as Map<String, Object?>;

    test('files/missing sends names and reads the missing ones', () async {
      final fixture = contract('files-missing');
      adapter.queue.add(fromContract(fixture));
      final names =
          ((request('files-missing')['body']! as Map)['names']! as List)
              .cast<String>();

      expect(await service.missing('tok', names), ['3539482a.jpg']);
      expect(adapter.requests.single.uri.path, '/v1/files/missing');
      expect(adapter.requests.single.data, {'names': names});
    });

    test('files/:name streams the file with its length', () async {
      adapter.queue.add(fromContract(contract('files-put')));
      final file = File('${tmp.path}/3539482a.jpg')..writeAsStringSync('cover');

      await service.uploadFile('tok', file);

      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, request('files-put')['path']);
      expect(req.headers[Headers.contentLengthHeader], 5);
      expect(req.headers['authorization'], 'Bearer tok');
    });

    test('backups: upload sends the manifest header, list parses', () async {
      final put = contract('backups-put');
      adapter.queue
        ..add(fromContract(put))
        ..add(fromContract(contract('backups-list')));
      final zip = File('${tmp.path}/b.zip')..writeAsStringSync('zipbytes');
      final manifest = BackupManifest.fromJson(
        jsonDecode(
          ((put['request']! as Map)['headers']! as Map)['x-backup-manifest']
              as String,
        ),
      );

      final uploaded = await service.uploadSnapshot('tok', zip, manifest);
      final list = await service.list('tok');

      final header = jsonDecode(
        adapter.requests.first.headers['x-backup-manifest'] as String,
      );
      expect(BackupManifest.fromJson(header).books, 12);
      expect(uploaded.books, 12);
      expect(uploaded.aiResults, 185);
      expect(
        list.single.createdAt.toUtc(),
        DateTime.utc(2026, 11, 13, 10, 4, 5),
      );
      expect(list.single.manifest.schemaVersion, 17);
    });

    test('a full quota surfaces as STORAGE_FULL', () async {
      adapter.queue.add(fromContract(contract('error-storage-full')));
      final file = File('${tmp.path}/big.epub')..writeAsStringSync('x');

      await expectLater(
        service.uploadFile('tok', file),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'STORAGE_FULL')
              .having((e) => e.statusCode, 'status', 413),
        ),
      );
    });

    test('an unknown snapshot is a 404', () async {
      adapter.queue.add(fromContract(contract('error-backup-not-found')));

      await expectLater(
        service.downloadSnapshot('tok', '20261113T100405Z', '${tmp.path}/x'),
        throwsA(
          isA<BackendException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });
  });

  group('CloudBackupRepository', () {
    late Phone a;
    late Phone b;
    late _Cloud cloud;
    late DateTime now;
    late List<Duration> sleeps;

    CloudBackupRepository repo(Phone phone, {_Auth? auth}) =>
        CloudBackupRepository(
          service: CloudBackupService(client(cloud)),
          backups: BackupService(phone.db, phone.storage),
          storage: phone.storage,
          settings: SettingsRepository(phone.db),
          auth: auth ?? _Auth(),
          clock: () => now,
          sleep: (d) async => sleeps.add(d),
        );

    setUp(() async {
      a = await Phone.make();
      b = await Phone.make();
      cloud = _Cloud();
      now = DateTime(2026, 11, 13, 9);
      sleeps = [];
      await a.addBook('Walden', translated: true);
      await a.addBook('Emma');
      await b.addBook('Dracula');
    });

    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    test('round trip: backup to the cloud, restore on another phone', () async {
      final expected = await a.dump();
      final stages = <BackupStage>[];

      final last = await repo(a).backup(onProgress: (s, _) => stages.add(s));

      expect(
        cloud.files.keys,
        unorderedEquals(['walden.epub', 'walden.png', 'emma.epub', 'emma.png']),
      );
      expect(cloud.backups, hasLength(1));
      expect(stages.last, BackupStage.settings);
      expect(await SettingsRepository(a.db).watchCloudBackupAt().first, now);
      expect(
        (await SettingsRepository(a.db).watchLastBackup().first)?.name,
        last.name,
      );

      final restore = RestoreService(b.db, b.storage);
      final backups = await repo(b).list();
      final preview = await repo(b).prepareRestore(backups.single, restore);
      expect(preview.manifest.books, 2);
      expect(preview.fileName, backupFileName(backups.single.createdAt));
      await restore.apply(preview);
      b.reopen();

      expect(await b.dump(), expected);
      expect(b.files('books'), a.files('books'));
      expect(b.files('covers'), a.files('covers'));
    });

    test(
      'second backup uploads only new files, restore reuses local ones',
      () async {
        await repo(a).backup();
        cloud.log.clear();
        await a.addBook('Persuasion');

        await repo(a).backup();

        expect(
          cloud.log.where((l) => l.startsWith('PUT /v1/files/')),
          unorderedEquals([
            'PUT /v1/files/persuasion.epub',
            'PUT /v1/files/persuasion.png',
          ]),
        );

        // Phone b already has Emma's files: only the rest get downloaded.
        await b.storage.book('emma.epub').writeAsString('epub of Emma');
        await b.storage.cover('emma.png').writeAsString('cover of Emma');
        cloud.log.clear();
        final restore = RestoreService(b.db, b.storage);
        final latest = (await repo(b).list()).first;
        await restore.apply(await repo(b).prepareRestore(latest, restore));
        b.reopen();

        expect(
          cloud.log.where((l) => l.startsWith('GET /v1/files/')),
          isNot(contains('GET /v1/files/emma.epub')),
        );
        expect(b.files('books'), a.files('books'));
      },
    );

    test('waits out a 429 between uploads and carries on', () async {
      cloud.rateLimitNext = 'PUT /v1/files/';

      await repo(a).backup();

      expect(sleeps, [const Duration(seconds: 60)]);
      expect(cloud.files, hasLength(4));
      expect(cloud.backups, hasLength(1));
    });

    test(
      'automatic backup: signed in, once per 24 h, retry after 1 h',
      () async {
        final auth = _Auth(null);
        final r = repo(a, auth: auth);
        expect(await r.backupIfDue(), isFalse, reason: 'signed out');

        auth.value = 'tok';
        expect(await r.backupIfDue(), isTrue);
        now = now.add(const Duration(hours: 23));
        expect(await r.backupIfDue(), isFalse, reason: 'backed up < 24 h ago');

        now = now.add(const Duration(hours: 2));
        cloud.queue.add(json(500, {}, headers: {'Retry-After': '1'}));
        expect(await r.backupIfDue(), isFalse, reason: 'failed silently');
        now = now.add(const Duration(minutes: 30));
        expect(await r.backupIfDue(), isFalse, reason: 'too soon after a fail');
        now = now.add(const Duration(minutes: 31));
        expect(await r.backupIfDue(), isTrue);
        expect(cloud.backups, hasLength(2));
      },
    );
  });
}
