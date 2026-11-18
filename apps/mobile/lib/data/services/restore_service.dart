import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/backup.dart';
import '../database/app_database.dart';
import '../repositories/chat_repository.dart';
import '../repositories/chat_context_repository.dart';
import 'chat_lifecycle.dart';
import 'file_storage.dart';

enum RestoreError {
  /// The file is not a zip, or it has no Luma manifest.
  notBackup,

  /// It was made by a Luma with a newer schema than the installed one.
  tooNew,

  /// The manifest is valid but the database inside cannot be opened.
  corrupt,
}

class RestoreException implements Exception {
  const RestoreException(this.error, {this.manifest});

  final RestoreError error;

  /// Set when the manifest was readable, so the UI can show the app version that made it.
  final BackupManifest? manifest;

  @override
  String toString() => 'RestoreException(${error.name})';
}

/// Represents a backup that was extracted and validated and is waiting for confirmation.
class RestorePreview {
  RestorePreview(this.dir, this.fileName, this.manifest);

  final Directory dir;
  final String fileName;
  final BackupManifest manifest;

  Future<void> discard() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Restores from a backup (docs/backup.md).
///
/// It extracts and validates in a temporary folder first, and replaces the old
/// data only when everything checks out. A failure midway moves everything
/// already relocated back.
class RestoreService {
  RestoreService(this._db, this._storage, {this.beforeClose});

  final Future<void> Function()? beforeClose;

  final AppDatabase _db;
  final FileStorage _storage;

  /// Matches `driftDatabase(name: 'luma')`: Documents/luma.sqlite.
  String get _dbPath => p.join(_storage.root.path, 'luma.sqlite');

  Future<int> currentBooks() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM books')
        .getSingle();
    return row.read<int>('n');
  }

  /// Extracts and validates [zip] into a temporary folder and returns a preview.
  ///
  /// [fileName] is the displayed name (defaults to the zip's name). [fill] runs
  /// after the DB passes validation, to complete `books/` and `covers/` in the
  /// extracted folder (cloud restore: the zip holds only the DB).
  Future<RestorePreview> inspect(
    File zip, {
    String? fileName,
    Future<void> Function(Directory dir, AppDatabase snapshot)? fill,
  }) async {
    final dir = await Directory.systemTemp.createTemp('luma-restore-');
    final name = fileName ?? p.basename(zip.path);
    try {
      try {
        await Isolate.run(() => _extract(zip.path, dir.path));
      } catch (_) {
        throw const RestoreException(RestoreError.notBackup);
      }
      final manifestFile = File(p.join(dir.path, 'manifest.json'));
      final BackupManifest manifest;
      try {
        manifest = BackupManifest.fromJson(
          jsonDecode(await manifestFile.readAsString()),
        );
      } catch (_) {
        throw const RestoreException(RestoreError.notBackup);
      }
      if (manifest.schemaVersion > _db.schemaVersion) {
        throw RestoreException(RestoreError.tooNew, manifest: manifest);
      }
      // Open it for real (migrating if it has an older schema) on the temporary
      // copy, so a corrupt database is caught here and not after the swap.
      final db = File(p.join(dir.path, 'luma.sqlite'));
      if (!await db.exists()) {
        throw RestoreException(RestoreError.corrupt, manifest: manifest);
      }
      final check = AppDatabase(NativeDatabase(db));
      try {
        await check.customSelect('SELECT COUNT(*) FROM books').get();
        // VACUUM INTO can shift `paragraphs` rowids, so the Cari kata index is
        // rebuilt on this copy before it is installed.
        await check.rebuildBookSearchIndex();
      } catch (_) {
        await check.close();
        throw RestoreException(RestoreError.corrupt, manifest: manifest);
      }
      try {
        await fill?.call(dir, check);
      } finally {
        await check.close();
      }
      return RestorePreview(dir, name, manifest);
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Replaces all data with the contents of [preview].
  ///
  /// [onStage] reports 1 = books, 2 = progress and translations. This closes the
  /// database; the caller must reopen it (invalidate `appDatabaseProvider`),
  /// whether the restore succeeded or failed.
  Future<void> apply(
    RestorePreview preview, {
    void Function(int stage)? onStage,
  }) async {
    String here(String name) => p.join(_storage.root.path, name);
    String there(String name) => p.join(preview.dir.path, name);
    for (final d in ['books', 'covers']) {
      await Directory(there(d)).create(recursive: true);
    }

    // Close only the SQLite connection so the files can be replaced.
    // `_db.close()` first closes the query streams and waits for every listener
    // to receive "done". A paused listener (Riverpod 3 pauses providers of
    // screens that are covered, e.g. the Rak under Pengaturan) never receives
    // it, which would hang the restore. The streams are disposed anyway when
    // the caller invalidates `appDatabaseProvider`.
    await beforeClose?.call();
    await _db.executor.close();
    final moved = <(String, String)>[];
    Future<void> move(String from, String to) async {
      if (!await FileSystemEntity.isDirectory(from) &&
          !await File(from).exists()) {
        return;
      }
      await _move(from, to);
      moved.add((from, to));
    }

    final dbFiles = [_dbPath, '$_dbPath-wal', '$_dbPath-shm'];
    try {
      onStage?.call(1);
      for (final d in ['books', 'covers']) {
        await move(here(d), here('$d.old'));
      }
      for (final f in dbFiles) {
        await move(f, '$f.old');
      }
      for (final d in ['books', 'covers']) {
        await move(there(d), here(d));
      }
      onStage?.call(2);
      // Required (already checked in inspect): if it is missing the restore fails instead of skipping it.
      await _move(there('luma.sqlite'), _dbPath);
      moved.add((there('luma.sqlite'), _dbPath));
    } catch (_) {
      // Restore the exact previous state, in reverse order.
      for (final (from, to) in moved.reversed) {
        await _move(to, from);
      }
      rethrow;
    }
    for (final old in [
      for (final d in ['books', 'covers']) here('$d.old'),
      for (final f in dbFiles) '$f.old',
    ]) {
      final e = await FileSystemEntity.type(old);
      if (e == FileSystemEntityType.directory) {
        await Directory(old).delete(recursive: true);
      } else if (e == FileSystemEntityType.file) {
        await File(old).delete();
      }
    }
    await preview.discard();
  }

  /// Moves by rename (same volume, fast), or by copy then delete across volumes.
  static Future<void> _move(String from, String to) async {
    final isDir = await FileSystemEntity.isDirectory(from);
    try {
      isDir ? await Directory(from).rename(to) : await File(from).rename(to);
    } on FileSystemException {
      if (!isDir) {
        await File(from).copy(to);
        await File(from).delete();
        return;
      }
      await Directory(to).create(recursive: true);
      await for (final e in Directory(from).list()) {
        if (e is File) await e.copy(p.join(to, p.basename(e.path)));
      }
      await Directory(from).delete(recursive: true);
    }
  }

  /// Extracts only known entries (`manifest.json`, `luma.sqlite`,
  /// `books/<name>`, `covers/<name>`).
  ///
  /// Unusual zip paths (`../`, absolute) are skipped.
  static void _extract(String zipPath, String out) {
    Directory(p.join(out, 'books')).createSync(recursive: true);
    Directory(p.join(out, 'covers')).createSync(recursive: true);
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final f in archive.files) {
        final target = f.isFile ? _target(f.name) : null;
        if (target == null) continue;
        final output = OutputFileStream(p.join(out, target));
        f.writeContent(output);
        output.closeSync();
      }
    } finally {
      input.closeSync();
    }
  }

  static String? _target(String name) {
    if (name == 'manifest.json' || name == 'luma.sqlite') return name;
    final parts = name.split('/');
    final ok =
        parts.length == 2 &&
        (parts[0] == 'books' || parts[0] == 'covers') &&
        parts[1].isNotEmpty &&
        parts[1] != '.' &&
        parts[1] != '..' &&
        !parts[1].contains(r'\');
    return ok ? name : null;
  }
}

final restoreServiceProvider = Provider<RestoreService>((ref) {
  final lifecycle = ref.watch(chatLifecycleProvider);
  final chat = ref.watch(chatRepositoryProvider);
  final context = ref.watch(chatContextRepositoryProvider);
  return RestoreService(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
    beforeClose: () async {
      await lifecycle.close();
      context.dispose();
      chat.dispose();
    },
  );
});
