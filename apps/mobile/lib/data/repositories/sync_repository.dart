import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../database/sync_schema.dart';
import '../services/backend_client.dart';
import '../services/cloud_backup_service.dart';
import '../services/file_storage.dart';
import '../services/sync_service.dart';
import 'auth_repository.dart';
import 'import_repository.dart';
import 'sync_applier.dart';

/// Nama dump buku Markdown di folder file cloud (docs/backend.md, File buku).
String markdownDumpName(String bookKey, int contentRevision) =>
    'md-$bookKey-$contentRevision.json.gz';

/// Top-level: closure di dalam method bisa ikut nangkep objek yang gak bisa
/// dikirim ke isolate.
Future<List<int>> _gzipJson(Object json) =>
    Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(json))));

Future<Map<String, Object?>> _readGzipJson(String path) => Isolate.run(
  () => (jsonDecode(
    utf8.decode(gzip.decode(File(path).readAsBytesSync())),
  ) as Map).cast<String, Object?>(),
);

/// Sync antar device (docs/backend.md): push perubahan lokal (`sync_outbox`),
/// pull perubahan device lain ([SyncApplier]), download + impor buku yang
/// belum ada. Tanpa polling: dipanggil cuma dari pemicu (login, resume,
/// debounce perubahan lokal). Error diam-diam; pemicu berikutnya coba lagi.
class SyncRepository {
  SyncRepository({
    required this._db,
    required this._service,
    required this._files,
    required this._storage,
    required this._auth,
    required this._applier,
    required this._import,
    void Function(SyncDownloads? progress)? onDownloads,
    this._clock = DateTime.now,
  }) : _onDownloads = onDownloads ?? _ignore;

  static void _ignore(SyncDownloads? _) {}

  final AppDatabase _db;
  final SyncService _service;
  final CloudBackupService _files;
  final FileStorage _storage;
  final AuthRepository _auth;
  final SyncApplier _applier;
  final ImportRepository _import;

  /// Progres download buku buat indikator Rak ([syncDownloadsProvider]);
  /// null = gak ada yang lagi di-download.
  final void Function(SyncDownloads? progress) _onDownloads;
  final DateTime Function() _clock;

  /// Jarak minimum sync dari resume.
  static const resumeGap = Duration(minutes: 5);

  /// Batch per pemicu: sync pertama (backfill) dicicil biar satu user gak
  /// ngabisin kuota tulis D1 harian.
  static const maxBatches = 10;

  Future<int>? _running;
  Future<void>? _syncing;
  DateTime? _lastSync;
  DateTime? _pausedUntil;

  /// Pemicu resume: paling cepat [resumeGap] sekali.
  Future<void> syncIfDue() async {
    if (_lastSync case final at? when _clock().difference(at) < resumeGap) {
      return;
    }
    return sync();
  }

  /// Login / resume: push dulu, baru pull, lalu download buku yang belum
  /// ada. Satu sync jalan sekaligus.
  Future<void> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    _lastSync = _clock();
    await push();
    if (_pausedUntil case final until? when _clock().isBefore(until)) return;
    final token = await _auth.token();
    if (token == null) return;
    try {
      await _pull(token);
    } on BackendException catch (e) {
      if (e.retryAfter case final wait?) _pausedUntil = _clock().add(wait);
      return;
    }
    await _downloadBooks(token);
  }

  /// Halaman demi halaman dari cursor (`sync.pullSeq`, per user: ganti akun =
  /// mulai dari 0), maks [maxBatches] per pemicu. Abis itu inbox dicoba lagi.
  Future<void> _pull(String token) async {
    final user = await _auth.lastUserId() ?? '';
    var since = await _cursor(user);
    for (var i = 0; i < maxBatches; i++) {
      final page = await _service.pull(token, since);
      await _applier.apply(page.records, cursor: '$user:${page.nextSeq}');
      since = page.nextSeq;
      if (!page.more) break;
    }
    await _applier.retryInbox();
  }

  Future<int> _cursor(String user) async {
    final value = (await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(pullCursorKey))).getSingleOrNull())?.value;
    if (value == null) return 0;
    final i = value.lastIndexOf(':');
    if (i < 0 || value.substring(0, i) != user) return 0;
    return int.tryParse(value.substring(i + 1)) ?? 0;
  }

  /// Buku yang record-nya nunggu di inbox: download dari folder file cloud,
  /// impor, lalu inbox dicoba lagi (metadata + data baca nyusul masuk). Satu
  /// per satu; yang gagal tetap di inbox buat pemicu berikutnya.
  Future<void> _downloadBooks(String token) async {
    final books = await _applier.missingBooks();
    if (books.isEmpty) return;
    try {
      for (final (i, r) in books.indexed) {
        _onDownloads((done: i, total: books.length));
        await _downloadOne(token, r);
      }
    } finally {
      _onDownloads(null);
    }
  }

  Future<void> _downloadOne(String token, PulledRecord r) async {
    try {
      await _downloadBook(token, r.data!);
      // Impor hasil sync bukan perubahan lokal: entri outbox-nya (waktu
      // impor) bakal ngalahin metadata device lain dan ke-push balik.
      await _db.customStatement(
        "DELETE FROM sync_outbox WHERE kind = 'book' AND key = ?",
        [r.key],
      );
      await _applier.retryInbox();
    } on Object {
      // diam-diam: dicoba lagi pemicu berikutnya
    }
  }

  Future<void> _downloadBook(String token, Map<String, Object?> d) async {
    final dir = await Directory.systemTemp.createTemp('luma-sync-');
    try {
      if (d['bookKey'] case final String bookKey) {
        final name = markdownDumpName(bookKey, d['contentRevision']! as int);
        final file = p.join(dir.path, name);
        await _files.downloadFile(token, name, file);
        await _applier.insertMarkdown(await _readGzipJson(file), d);
        return;
      }
      final name = d['fileName']! as String;
      final file = File(p.join(dir.path, name));
      await _files.downloadFile(token, name, file.path);
      if (p.extension(name).toLowerCase() == '.pdf') {
        await _import.importPdf(file.path, fileName: name);
      } else {
        await _import.importEpub(
          await file.readAsBytes(),
          fileName: name,
          sourceId: d['sourceId'] as String?,
          externalId: d['externalId'] as String?,
        );
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Push sampai outbox kosong atau [maxBatches]. Satu push jalan sekaligus.
  /// Balikin jumlah record yang terkirim.
  Future<int> push() =>
      _running ??= _push().whenComplete(() => _running = null);

  Future<int> _push() async {
    if (_pausedUntil case final until? when _clock().isBefore(until)) return 0;
    final token = await _auth.token();
    if (token == null) return 0;
    // Satu putaran cuma ngirim perubahan sebelum mulai, maju lewat cursor:
    // yang berubah selama push nunggu pemicu berikutnya (debounce), yang
    // gagal gak diulang di putaran yang sama.
    final start = (await _db.customSelect('SELECT $sqlNowMs AS t').getSingle())
        .read<int>('t');
    var cursor = (0, '', '');
    var sent = 0;
    try {
      for (var i = 0; i < maxBatches; i++) {
        final batch = await _pushBatch(token, start, cursor);
        if (batch == null) break;
        sent += batch.sent;
        cursor = batch.cursor;
      }
    } on BackendException catch (e) {
      // 429 / 503 saklar darurat: tunggu `Retry-After` sebelum coba lagi.
      if (e.retryAfter case final wait?) _pausedUntil = _clock().add(wait);
    }
    return sent;
  }

  /// Satu batch outbox (≤ [start], setelah [cursor]) → server. null = habis.
  Future<({int sent, (int, String, String) cursor})?> _pushBatch(
    String token,
    int start,
    (int, String, String) cursor,
  ) async {
    final queued = await _db
        .customSelect(
          'SELECT * FROM sync_outbox WHERE updated_at <= ? AND '
          '(updated_at, kind, key) > (?, ?, ?) '
          'ORDER BY updated_at, kind, key LIMIT ${SyncService.maxRecords}',
          variables: [
            Variable(start),
            Variable(cursor.$1),
            Variable(cursor.$2),
            Variable(cursor.$3),
          ],
          readsFrom: {_db.syncOutbox},
        )
        .map((r) => _db.syncOutbox.map(r.data))
        .get();
    if (queued.isEmpty) return null;

    final data = <(String, String), String>{};
    for (final kind in {for (final o in queued) o.kind}) {
      final spec = syncKindsByName[kind];
      if (spec == null) continue;
      final rows = await _db
          .customSelect(
            spec.select,
            variables: [
              Variable(
                jsonEncode([
                  for (final o in queued)
                    if (o.kind == kind) o.key,
                ]),
              ),
            ],
          )
          .get();
      for (final r in rows) {
        data[(kind, r.read<String>('key'))] = r.read<String>('data');
      }
    }

    final records = <SyncRecord>[];
    final done = <SyncOutboxData>[];
    var bytes = 0;
    for (final o in queued) {
      final json = data[(o.kind, o.key)];
      final tombstone = syncKindsByName[o.kind]?.tombstone ?? false;
      final size = utf8.encode(json ?? '').length + o.key.length + 100;
      // Baris anak yang udah kehapus, kind gak dikenal, atau satu record yang
      // sendirian lewat batas body: dibuang, gak bisa dikirim.
      if ((json == null && !tombstone) || size > SyncService.maxBytes) {
        done.add(o);
        continue;
      }
      if (bytes + size > SyncService.maxBytes) break; // sisanya batch berikut
      bytes += size;
      records.add(
        SyncRecord(
          kind: o.kind,
          key: o.key,
          updatedAt: o.updatedAt,
          data: json == null ? null : jsonDecode(json) as Map<String, Object?>,
        ),
      );
      done.add(o);
    }

    if (records.isNotEmpty) {
      await _service.push(token, _db.schemaVersion, records);
    }
    final failed = await _uploadBookFiles(token, records);
    // Hapus yang terkirim, kecuali yang berubah lagi selama push (updatedAt
    // beda) atau file bukunya gagal di-upload (record buku dikirim ulang
    // pemicu berikutnya; server gak nulis ulang data yang sama).
    await _db.customStatement(
      'DELETE FROM sync_outbox WHERE (kind, key, updated_at) IN '
      "(SELECT json_extract(value, '\$[0]'), json_extract(value, '\$[1]'), "
      "json_extract(value, '\$[2]') FROM json_each(?))",
      [
        jsonEncode([
          for (final o in done)
            if (!(o.kind == 'book' && failed.contains(o.key)))
              [o.kind, o.key, o.updatedAt],
        ]),
      ],
    );
    final last = done.last;
    return (
      sent: records.length,
      cursor: (last.updatedAt, last.kind, last.key),
    );
  }

  /// File buku yang belum ada di cloud (file, cover, dump Markdown), biar
  /// device lain bisa download. Balikin kunci buku yang gagal.
  Future<Set<String>> _uploadBookFiles(
    String token,
    List<SyncRecord> records,
  ) async {
    // temp = file dibikin di folder sementara, dihapus habis upload.
    final wanted =
        <String, ({String book, bool temp, Future<File?> Function() file})>{};
    for (final r in records) {
      final d = r.data;
      if (r.kind != 'book' || d == null) continue;
      if (d['fileName'] case final String name) {
        wanted[name] = (
          book: r.key,
          temp: false,
          file: () => _existing(_storage.book(name)),
        );
      }
      if (d['coverName'] case final String name) {
        wanted[name] = (
          book: r.key,
          temp: false,
          file: () => _existing(_storage.cover(name)),
        );
      }
      if (d['bookKey'] case final String bookKey) {
        final name = markdownDumpName(bookKey, d['contentRevision']! as int);
        wanted[name] = (
          book: r.key,
          temp: true,
          file: () => _markdownDump(bookKey, name),
        );
      }
    }
    if (wanted.isEmpty) return const {};

    final names = wanted.keys.toList();
    final List<String> missing;
    try {
      missing = [
        for (var i = 0; i < names.length; i += CloudBackupService.missingBatch)
          ...await _files.missing(
            token,
            names.sublist(
              i,
              (i + CloudBackupService.missingBatch).clamp(0, names.length),
            ),
          ),
      ];
    } on BackendException {
      return {for (final w in wanted.values) w.book};
    }

    final failed = <String>{};
    for (final name in missing) {
      final want = wanted[name]!;
      File? file;
      try {
        file = await want.file();
        if (file != null) await _files.uploadFile(token, file);
      } on Object {
        failed.add(want.book);
      } finally {
        if (file != null && want.temp) {
          await file.parent.delete(recursive: true);
        }
      }
    }
    return failed;
  }

  static Future<File?> _existing(File f) async => await f.exists() ? f : null;

  /// Buku Markdown gak punya file sumber: bab + paragraf (dengan
  /// `groupIndex`) di-dump ke JSON gzip bernama [name] di folder sementara.
  Future<File?> _markdownDump(String bookKey, String name) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.bookKey.equals(bookKey))).getSingleOrNull();
    if (book == null) return null;
    final chapters =
        await (_db.select(_db.chapters)
              ..where((c) => c.bookId.equals(book.id))
              ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
            .get();
    final paragraphs =
        await (_db.select(_db.paragraphs)
              ..where((x) => x.chapterId.isIn([for (final c in chapters) c.id]))
              ..orderBy([(x) => OrderingTerm(expression: x.paragraphIndex)]))
            .get();
    final dump = {
      'format': 'luma-markdown',
      'formatVersion': 1,
      'bookKey': bookKey,
      'contentRevision': book.contentRevision,
      'parserVersion': book.parserVersion,
      'chapters': [
        for (final c in chapters)
          {
            'sortOrder': c.sortOrder,
            'chapterNumber': c.chapterNumber,
            'title': c.title,
            'section': c.section,
            'charOffset': c.charOffset,
            'paragraphs': [
              for (final x in paragraphs)
                if (x.chapterId == c.id)
                  [x.paragraphIndex, x.groupIndex, x.type.name, x.content],
            ],
          },
      ],
    };
    final dir = await Directory.systemTemp.createTemp('luma-md-');
    final file = File(p.join(dir.path, name));
    return file.writeAsBytes(await _gzipJson(dump));
  }
}

/// Event tiap tabel yang di-sync berubah lewat Drift. Outbox diisi trigger
/// SQLite yang gak keliatan stream Drift, jadi yang didengerin tabel asalnya.
final syncChangesProvider = Provider<Stream<void>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final synced = {for (final k in syncKinds) k.table};
  return db.tableUpdates(
    TableUpdateQuery.onAllTables([
      for (final t in db.allTables)
        if (synced.contains(t.actualTableName)) t,
    ]),
  );
});

/// Download buku hasil sync: [done] dari [total] buku yang nunggu.
typedef SyncDownloads = ({int done, int total});

class SyncDownloadsNotifier extends Notifier<SyncDownloads?> {
  @override
  SyncDownloads? build() => null;

  // ignore: use_setters_to_change_properties
  void set(SyncDownloads? progress) => state = progress;
}

/// Indikator "Nyinkronin 3/12 buku" di Rak. null = gak ada download.
final syncDownloadsProvider =
    NotifierProvider<SyncDownloadsNotifier, SyncDownloads?>(
      SyncDownloadsNotifier.new,
    );

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepository(
    db: ref.watch(appDatabaseProvider),
    service: ref.watch(syncServiceProvider),
    files: ref.watch(cloudBackupServiceProvider),
    storage: ref.watch(fileStorageProvider),
    auth: ref.watch(authRepositoryProvider),
    applier: ref.watch(syncApplierProvider),
    import: ref.watch(importRepositoryProvider),
    onDownloads: (p) => ref.read(syncDownloadsProvider.notifier).set(p),
  ),
);
