import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/backup.dart';
import '../database/app_database.dart';
import 'file_storage.dart';

/// The stage currently being packed (checked off in the backup sheet).
enum BackupStage { books, database, settings }

/// Represents a finished backup zip waiting to be shared.
///
/// [dispose] deletes its temporary folder.
class BackupFile {
  BackupFile(this._dir, this.file, this.manifest);

  final Directory _dir;
  final File file;
  final BackupManifest manifest;

  String get name => p.basename(file.path);
  int get size => file.lengthSync();

  Future<void> dispose() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}

/// Exports all data into one zip (docs/backup.md): a DB snapshot, the manifest,
/// and the EPUB and cover files.
///
/// API keys are not included; they live in the Keychain, not in the DB.
class BackupService {
  BackupService(this._db, this._storage);

  final AppDatabase _db;
  final FileStorage _storage;

  /// Builds the backup zip, or returns null when cancelled.
  ///
  /// [onStart] fires once after the DB snapshot (the file name and the book and
  /// translation counts are known by then). While zipping, completing [cancel]
  /// kills the zip isolate. With [snapshotOnly] the zip holds just the manifest
  /// and the DB, for cloud backup (book and cover files upload separately,
  /// docs/backup.md, Archive contents and manifest).
  Future<BackupFile?> export({
    bool snapshotOnly = false,
    DateTime? now,
    void Function(String name, BackupManifest manifest)? onStart,
    void Function(BackupStage stage, double fraction)? onProgress,
    Future<void>? cancel,
  }) async {
    final created = now ?? DateTime.now();
    final dir = await Directory.systemTemp.createTemp('luma-backup-');
    try {
      // VACUUM INTO gives a consistent snapshot even while the DB is in use or in WAL mode.
      final snapshot = p.join(dir.path, 'luma.sqlite');
      await _db.customStatement('VACUUM INTO ?', [snapshot]);

      final manifest = BackupManifest(
        appVersion: appVersion,
        schemaVersion: _db.schemaVersion,
        createdAt: created,
        books: await _count(_db.books),
        aiResults: await _count(_db.aiResults),
      );
      final manifestFile = File(p.join(dir.path, 'manifest.json'));
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      final name = backupFileName(created);
      onStart?.call(name, manifest);

      // EPUBs and images are already compressed, so they are stored as-is; the DB and manifest are compressed.
      final entries = <_Entry>[
        if (!snapshotOnly) ...[
          for (final f in await _files(_storage.booksDir))
            (
              path: f.path,
              name: 'books/${p.basename(f.path)}',
              level: 0,
              stage: 0,
            ),
          for (final f in await _files(_storage.coversDir))
            (
              path: f.path,
              name: 'covers/${p.basename(f.path)}',
              level: 0,
              stage: 0,
            ),
        ],
        (path: snapshot, name: 'luma.sqlite', level: 6, stage: 1),
        (path: manifestFile.path, name: 'manifest.json', level: 6, stage: 2),
      ];
      final out = File(p.join(dir.path, name));
      final ok = await _zip(entries, out.path, onProgress, cancel);
      if (!ok) {
        await dir.delete(recursive: true);
        return null;
      }
      await File(snapshot).delete();
      await manifestFile.delete();
      return BackupFile(dir, out, manifest);
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Returns the number of books on the shelf, without taking a snapshot.
  Future<int> bookCount() => _count(_db.books);

  Future<int> _count(TableInfo<Table, Object?> table) async {
    final n = table.actualTableName;
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM $n')
        .getSingle();
    return row.read<int>('n');
  }

  static Future<List<File>> _files(Directory dir) async =>
      !await dir.exists()
            ? const []
            : [
                await for (final e in dir.list())
                  if (e is File) e,
              ]
        ..sort((a, b) => a.path.compareTo(b.path));

  /// Zips in an isolate (EPUBs can be large); returns false when cancelled.
  static Future<bool> _zip(
    List<_Entry> entries,
    String out,
    void Function(BackupStage, double)? onProgress,
    Future<void>? cancel,
  ) async {
    final port = ReceivePort();
    final done = Completer<bool>();
    final isolate = await Isolate.spawn(_zipWorker, (
      port.sendPort,
      entries,
      out,
    ));
    cancel?.then((_) {
      if (done.isCompleted) return;
      isolate.kill(priority: Isolate.immediate);
      done.complete(false);
    });
    port.listen((msg) {
      if (done.isCompleted) return;
      switch (msg) {
        case (int stage, double fraction):
          onProgress?.call(BackupStage.values[stage], fraction);
        case null:
          done.complete(true);
        case String error:
          done.completeError(FileSystemException(error, out));
      }
    });
    try {
      return await done.future;
    } finally {
      port.close();
    }
  }

  static Future<void> _zipWorker((SendPort, List<_Entry>, String) msg) async {
    final (send, entries, out) = msg;
    try {
      final sizes = [for (final e in entries) File(e.path).lengthSync()];
      final total = sizes.fold<int>(0, (a, b) => a + b);
      var written = 0;
      final zip = ZipFileEncoder()..create(out);
      for (final (i, e) in entries.indexed) {
        send.send((e.stage, total == 0 ? 0.0 : written / total));
        await zip.addFile(File(e.path), e.name, e.level);
        written += sizes[i];
      }
      await zip.close();
      send.send((BackupStage.settings.index, 1.0));
      send.send(null);
    } catch (e) {
      send.send('$e');
    }
  }
}

/// A file going into the zip: its real path, its name in the zip, its
/// compression level, and its stage (a [BackupStage] index).
typedef _Entry = ({String path, String name, int level, int stage});

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
  ),
);
