import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/backup.dart';
import '../database/app_database.dart';
import '../services/backend_client.dart';
import '../services/backup_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/file_storage.dart';
import '../services/restore_service.dart';
import 'auth_repository.dart';
import 'settings_repository.dart';

/// Backup ke R2 (docs/backend.md, Backup cloud): snapshot DB tiap backup,
/// file buku & cover cuma yang belum ada di cloud. Restore = snapshot +
/// file yang belum ada lokal → [RestoreService] yang sama dengan zip biasa.
class CloudBackupRepository {
  CloudBackupRepository({
    required this._service,
    required this._backups,
    required this._storage,
    required this._settings,
    required this._auth,
    this._clock = DateTime.now,
    this._sleep = Future<void>.delayed,
  });

  final CloudBackupService _service;
  final BackupService _backups;
  final FileStorage _storage;
  final SettingsRepository _settings;
  final AuthRepository _auth;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;

  /// Backup otomatis kalau backup cloud terakhir lebih lama dari ini.
  static const autoInterval = Duration(hours: 24);

  /// Gagal → pemicu berikutnya paling cepat setelah jeda ini.
  static const retryGap = Duration(hours: 1);

  /// Batas nunggu `Retry-After` 429 per file (rate limit 60/menit per user).
  static const rateLimitRetries = 5;

  Future<LastBackup>? _running;
  DateTime? _lastAttempt;

  /// Satu backup jalan sekaligus: pemicu kedua dapat future yang sama.
  Future<LastBackup> backup({
    void Function(String name, BackupManifest manifest)? onStart,
    void Function(BackupStage stage, double fraction)? onProgress,
  }) => _running ??= _backup(
    onStart,
    onProgress,
  ).whenComplete(() => _running = null);

  /// Pemicu buka/resume: diam-diam, cuma kalau login dan udah > 24 jam.
  /// true = backup jalan & sukses.
  Future<bool> backupIfDue() async {
    final now = _clock();
    if (_lastAttempt case final at? when now.difference(at) < retryGap) {
      return false;
    }
    if (await _auth.token() == null) return false;
    final last = await _settings.watchCloudBackupAt().first;
    if (last != null && now.difference(last) < autoInterval) return false;
    _lastAttempt = now;
    try {
      await backup();
      return true;
    } on Object {
      return false; // diam-diam; coba lagi resume berikutnya
    }
  }

  Future<LastBackup> _backup(
    void Function(String, BackupManifest)? onStart,
    void Function(BackupStage, double)? onProgress,
  ) async {
    final token = await _token();
    final file = await _backups.export(snapshotOnly: true, onStart: onStart);
    if (file == null) throw StateError('snapshot cancelled');
    try {
      final local = {
        for (final f in [
          ...await _files(_storage.booksDir),
          ...await _files(_storage.coversDir),
        ])
          p.basename(f.path): f,
      };
      final names = local.keys.toList();
      final missing = <String>[
        for (var i = 0; i < names.length; i += CloudBackupService.missingBatch)
          ...await _service.missing(
            token,
            names.sublist(
              i,
              (i + CloudBackupService.missingBatch).clamp(0, names.length),
            ),
          ),
      ];
      final sizes = {for (final n in missing) n: await local[n]!.length()};
      final total = sizes.values.fold(file.size, (a, b) => a + b);
      var done = 0;
      void report(BackupStage stage, int sent) =>
          onProgress?.call(stage, total == 0 ? 1 : (done + sent) / total);

      for (final name in missing) {
        await _rateLimited(
          () => _service.uploadFile(
            token,
            local[name]!,
            onProgress: (sent, _) => report(BackupStage.books, sent),
          ),
        );
        done += sizes[name]!;
      }
      await _rateLimited(
        () => _service.uploadSnapshot(
          token,
          file.file,
          file.manifest,
          onProgress: (sent, _) => report(BackupStage.database, sent),
        ),
      );
      onProgress?.call(BackupStage.settings, 1);
      final last = (at: _clock(), name: file.name, size: file.size);
      await _settings.saveCloudBackup(last);
      return last;
    } finally {
      await file.dispose();
    }
  }

  /// Upload banyak file bisa lewat rate limit per user: tunggu `Retry-After`
  /// lalu lanjut, bukan gagal di tengah.
  Future<T> _rateLimited<T>(Future<T> Function() call) async {
    for (var i = 0; ; i++) {
      try {
        return await call();
      } on BackendException catch (e) {
        if (e.code != 'RATE_LIMITED' || i >= rateLimitRetries) rethrow;
        await _sleep(e.retryAfter ?? const Duration(minutes: 1));
      }
    }
  }

  Future<List<CloudBackup>> list() async => _service.list(await _token());

  /// Download snapshot [backup], lalu cek & lengkapi file buku/cover lewat
  /// [restore]. Hasilnya dipasang pakai [RestoreService.apply] yang biasa.
  Future<RestorePreview> prepareRestore(
    CloudBackup backup,
    RestoreService restore,
  ) async {
    final token = await _token();
    final tmp = await Directory.systemTemp.createTemp('luma-cloud-');
    try {
      final zip = File(p.join(tmp.path, '${backup.id}.zip'));
      await _service.downloadSnapshot(token, backup.id, zip.path);
      return await restore.inspect(
        zip,
        fileName: backupFileName(backup.createdAt),
        fill: (dir, db) => _fill(token, dir, db),
      );
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// File yang dirujuk snapshot: salin dari HP kalau udah ada, sisanya
  /// download. File yang gak ada di cloud (404) dilewatin, kayak zip biasa
  /// yang gak lengkap.
  Future<void> _fill(String token, Directory dir, AppDatabase db) async {
    final target = FileStorage(dir);
    final rows = await db
        .customSelect('SELECT file_name, cover_name FROM books')
        .get();
    final wanted = [
      for (final r in rows) ...[
        if (r.readNullable<String>('file_name') case final n?)
          (target.book(n), _storage.book(n)),
        if (r.readNullable<String>('cover_name') case final n?)
          (target.cover(n), _storage.cover(n)),
      ],
    ];
    for (final (to, here) in wanted) {
      if (await to.exists()) continue;
      if (await here.exists()) {
        await here.copy(to.path);
        continue;
      }
      try {
        await _service.downloadFile(token, p.basename(to.path), to.path);
      } on BackendException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
  }

  Future<String> _token() async =>
      await _auth.token() ??
      (throw const BackendException(
        code: 'UNAUTHORIZED',
        message: 'Sign in required',
        statusCode: 401,
      ));

  static Future<List<File>> _files(Directory dir) async => !await dir.exists()
      ? const []
      : [
          await for (final e in dir.list())
            if (e is File) e,
        ];
}

final cloudBackupRepositoryProvider = Provider<CloudBackupRepository>(
  (ref) => CloudBackupRepository(
    service: ref.watch(cloudBackupServiceProvider),
    backups: ref.watch(backupServiceProvider),
    storage: ref.watch(fileStorageProvider),
    settings: ref.watch(settingsRepositoryProvider),
    auth: ref.watch(authRepositoryProvider),
  ),
);
