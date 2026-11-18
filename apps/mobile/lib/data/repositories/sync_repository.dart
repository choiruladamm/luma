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

/// Returns the name of a Markdown book dump in the cloud file folder (docs/sync-protocol.md, Book files and Markdown dumps).
String markdownDumpName(String bookKey, int contentRevision) =>
    'md-$bookKey-$contentRevision.json.gz';

/// Top-level because a closure inside a method could capture objects that
/// can't be sent to an isolate.
Future<List<int>> _gzipJson(Object json) =>
    Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(json))));

Future<Map<String, Object?>> _readGzipJson(String path) => Isolate.run(
  () => (jsonDecode(
    utf8.decode(gzip.decode(File(path).readAsBytesSync())),
  ) as Map).cast<String, Object?>(),
);

/// Syncs between devices (docs/sync-protocol.md, Push and pull).
///
/// Pushes local changes (`sync_outbox`), pulls changes from other devices
/// ([SyncApplier]), and downloads and imports books that are missing. There is
/// no polling: it runs only from triggers (login, resume, debounced local
/// changes). Errors are swallowed; the next trigger retries.
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

  /// Reports book download progress for the shelf indicator
  /// ([syncDownloadsProvider]); null means nothing is downloading.
  final void Function(SyncDownloads? progress) _onDownloads;
  final DateTime Function() _clock;

  /// Minimum gap between syncs triggered by resume.
  static const resumeGap = Duration(minutes: 5);

  /// Batches per trigger. The first sync (backfill) is spread over several
  /// triggers so one user can't use up the daily D1 write quota.
  static const maxBatches = 10;

  Future<int>? _running;
  Future<void>? _syncing;
  DateTime? _lastSync;
  DateTime? _pausedUntil;

  /// Resume trigger; syncs at most once per [resumeGap].
  Future<void> syncIfDue() async {
    if (_lastSync case final at? when _clock().difference(at) < resumeGap) {
      return;
    }
    return sync();
  }

  /// Syncs on login or resume: pushes first, then pulls, then downloads the
  /// missing books. Only one sync runs at a time.
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

  /// Pulls page by page from the cursor (`sync.pullSeq`, kept per user, so an
  /// account switch starts from 0), at most [maxBatches] per trigger, then
  /// retries the inbox.
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

  /// Downloads the books whose records wait in the inbox from the cloud file
  /// folder, imports them, then retries the inbox so the metadata and reading
  /// data follow.
  ///
  /// Books go one at a time; a failed one stays in the inbox for the next
  /// trigger.
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
      // A sync-driven import isn't a local change: its outbox entry (stamped
      // with the import time) would beat the other device's metadata and get
      // pushed back.
      await _db.customStatement(
        "DELETE FROM sync_outbox WHERE kind = 'book' AND key = ?",
        [r.key],
      );
      await _applier.retryInbox();
    } on Object {
      // Swallowed: the next trigger retries.
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

  /// Pushes until the outbox is empty or [maxBatches] is reached, and returns
  /// the number of records sent.
  ///
  /// Only one push runs at a time.
  Future<int> push() =>
      _running ??= _push().whenComplete(() => _running = null);

  Future<int> _push() async {
    if (_pausedUntil case final until? when _clock().isBefore(until)) return 0;
    final token = await _auth.token();
    if (token == null) return 0;
    // One round sends only the changes that existed when it started, advancing
    // by cursor: changes made during the push wait for the next trigger
    // (debounce), and a failed record isn't retried in the same round.
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
      // 429 or a 503 kill switch: wait for `Retry-After` before retrying.
      if (e.retryAfter case final wait?) _pausedUntil = _clock().add(wait);
    }
    return sent;
  }

  /// Sends one outbox batch (entries up to [start], after [cursor]) to the
  /// server, or returns null when the outbox is exhausted.
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
      // A child row that was already deleted, an unknown kind, or a single
      // record that alone exceeds the body limit: drop it, it can't be sent.
      if ((json == null && !tombstone) || size > SyncService.maxBytes) {
        done.add(o);
        continue;
      }
      // The rest goes in the next batch.
      if (bytes + size > SyncService.maxBytes) break;
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
    // Delete what was sent, except entries that changed again during the push
    // (different updatedAt) or whose book file failed to upload (the next
    // trigger resends the book record; the server doesn't rewrite identical
    // data).
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

  /// Uploads the book files that aren't in the cloud yet (file, cover,
  /// Markdown dump) so other devices can download them.
  ///
  /// Returns the keys of the books that failed.
  Future<Set<String>> _uploadBookFiles(
    String token,
    List<SyncRecord> records,
  ) async {
    // temp means the file was created in a temporary folder and is deleted after the upload.
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

  /// Dumps a Markdown book to a gzipped JSON file named [name] in a temporary
  /// folder.
  ///
  /// Markdown books have no source file, so the chapters and paragraphs (with
  /// `groupIndex`) are dumped instead.
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

/// Emits an event whenever a synced table changes through Drift.
///
/// The outbox is filled by SQLite triggers that Drift streams can't see, so
/// this listens to the source tables instead.
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

/// Progress of sync-driven book downloads: [done] out of [total] waiting books.
typedef SyncDownloads = ({int done, int total});

class SyncDownloadsNotifier extends Notifier<SyncDownloads?> {
  @override
  SyncDownloads? build() => null;

  // ignore: use_setters_to_change_properties
  void set(SyncDownloads? progress) => state = progress;
}

/// Drives the "Nyinkronin 3/12 buku" indicator on the shelf; null means no download is running.
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
