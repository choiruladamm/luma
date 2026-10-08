import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/backup.dart';
import '../database/app_database.dart';
import 'file_storage.dart';

enum RestoreError {
  /// Bukan zip / gak ada manifest Luma.
  notBackup,

  /// Dibikin Luma dengan schema lebih baru dari yang keinstall.
  tooNew,

  /// Manifest-nya bener tapi database di dalemnya gak bisa dibuka.
  corrupt,
}

class RestoreException implements Exception {
  const RestoreException(this.error, {this.manifest});

  final RestoreError error;

  /// Ada kalau manifest-nya kebaca (buat nampilin versi app-nya).
  final BackupManifest? manifest;

  @override
  String toString() => 'RestoreException(${error.name})';
}

/// Backup yang udah diekstrak & dicek, nunggu dikonfirmasi.
class RestorePreview {
  RestorePreview(this.dir, this.fileName, this.manifest);

  final Directory dir;
  final String fileName;
  final BackupManifest manifest;

  Future<void> discard() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Pulihin dari backup (docs/backup.md): ekstrak & cek dulu di folder
/// sementara, data lama baru diganti kalau semuanya beres. Gagal di tengah
/// jalan → semua yang udah dipindah dibalikin.
class RestoreService {
  RestoreService(this._db, this._storage);

  final AppDatabase _db;
  final FileStorage _storage;

  /// Sama kayak `driftDatabase(name: 'luma')`: Documents/luma.sqlite.
  String get _dbPath => p.join(_storage.root.path, 'luma.sqlite');

  Future<int> currentBooks() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM books')
        .getSingle();
    return row.read<int>('n');
  }

  Future<RestorePreview> inspect(File zip) async {
    final dir = await Directory.systemTemp.createTemp('luma-restore-');
    final fileName = p.basename(zip.path);
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
      // Buka beneran (sekalian migrasi kalau dari schema lama) di salinan
      // sementara; database rusak ketauan di sini, bukan abis diganti.
      final db = File(p.join(dir.path, 'luma.sqlite'));
      if (!await db.exists()) {
        throw RestoreException(RestoreError.corrupt, manifest: manifest);
      }
      final check = AppDatabase(NativeDatabase(db));
      try {
        await check.customSelect('SELECT COUNT(*) FROM books').get();
      } catch (_) {
        throw RestoreException(RestoreError.corrupt, manifest: manifest);
      } finally {
        await check.close();
      }
      return RestorePreview(dir, fileName, manifest);
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Ganti semua data pake isi [preview]. [onStage]: 1 = buku, 2 = progres
  /// & terjemahan. Database ditutup di sini; yang manggil wajib ngebuka lagi
  /// (invalidate `appDatabaseProvider`), sukses ataupun gagal.
  Future<void> apply(
    RestorePreview preview, {
    void Function(int stage)? onStage,
  }) async {
    String here(String name) => p.join(_storage.root.path, name);
    String there(String name) => p.join(preview.dir.path, name);
    for (final d in ['books', 'covers']) {
      await Directory(there(d)).create(recursive: true);
    }

    // Cuma koneksi SQLite-nya yang ditutup, biar filenya bisa diganti.
    // `_db.close()` nutup stream query dulu dan nunggu tiap listener nerima
    // "done": listener yang di-pause (Riverpod 3 nge-pause provider layar
    // yang ketutup, mis. Rak di bawah Pengaturan) gak pernah nerima, jadi
    // restore nyangkut. Stream-nya ikut kebuang pas pemanggil invalidate
    // `appDatabaseProvider`.
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
      // Wajib ada (udah dicek di inspect): ilang = gagal, bukan dilewatin.
      await _move(there('luma.sqlite'), _dbPath);
      moved.add((there('luma.sqlite'), _dbPath));
    } catch (_) {
      // Balikin persis kayak sebelumnya, urutan kebalik.
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

  /// Rename (satu volume, cepet); beda volume → salin terus hapus.
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

  /// Cuma file yang dikenal yang diekstrak (`manifest.json`, `luma.sqlite`,
  /// `books/<nama>`, `covers/<nama>`); path aneh di zip (`../`, absolut)
  /// dilewatin.
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

final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
  ),
);
