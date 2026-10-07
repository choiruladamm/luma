import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_model.dart';
import '../../domain/models/backup.dart';
import '../../domain/models/reader_prefs.dart';
import '../database/app_database.dart';

/// Setelan yang ikut backup, di tabel `settings` (key-value).
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<ReaderPrefs> watchReaderPrefs() => _db
      .select(_db.settings)
      .watch()
      .map(
        (rows) =>
            ReaderPrefs.fromSettings({for (final r in rows) r.key: r.value}),
      )
      .distinct();

  /// Model LLM dari Pengaturan; default kalau belum dipilih.
  Stream<String> watchModel() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_model)))
          .watchSingleOrNull()
          .map((row) => row?.value ?? defaultAiModel)
          .distinct();

  Future<void> saveModel(String id) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: _model, value: id));

  static const _model = 'ai.model';

  /// Backup terakhir yang berhasil disimpen user; null = belum pernah.
  Stream<LastBackup?> watchLastBackup() =>
      (_db.select(_db.settings)
            ..where((s) => s.key.isIn([_backupAt, _backupName, _backupSize])))
          .watch()
          .map((rows) {
            final m = {for (final r in rows) r.key: r.value};
            final at = DateTime.tryParse(m[_backupAt] ?? '');
            if (at == null) return null;
            return (
              at: at,
              name: m[_backupName] ?? '',
              size: int.tryParse(m[_backupSize] ?? '') ?? 0,
            );
          });

  Future<void> saveLastBackup(LastBackup b) => _db.batch(
    (batch) => batch.insertAllOnConflictUpdate(_db.settings, [
      SettingsCompanion.insert(key: _backupAt, value: b.at.toIso8601String()),
      SettingsCompanion.insert(key: _backupName, value: b.name),
      SettingsCompanion.insert(key: _backupSize, value: '${b.size}'),
    ]),
  );

  /// Kapan banner pengingat backup terakhir ditutup.
  Stream<DateTime?> watchReminderDismissed() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_dismissed)))
          .watchSingleOrNull()
          .map((row) => DateTime.tryParse(row?.value ?? ''));

  Future<void> dismissReminder(DateTime at) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: _dismissed, value: at.toIso8601String()),
      );

  static const _dismissed = 'backup.reminderDismissedAt';
  static const _backupAt = 'backup.lastAt';
  static const _backupName = 'backup.lastName';
  static const _backupSize = 'backup.lastSize';

  Future<void> saveReaderPrefs(ReaderPrefs prefs) => _db.batch(
    (b) => b.insertAllOnConflictUpdate(_db.settings, [
      for (final MapEntry(:key, :value) in prefs.toSettings().entries)
        SettingsCompanion.insert(key: key, value: value),
    ]),
  );
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Setelan Aa + tema. Dipake halaman baca dan root app (themeMode).
final readerPrefsProvider = StreamProvider<ReaderPrefs>(
  (ref) => ref.watch(settingsRepositoryProvider).watchReaderPrefs(),
);

/// Model LLM yang dipake (dibaca tiap manggil OpenRouter, bukan di-hardcode).
final aiModelProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).watchModel(),
);

/// Backup terakhir (Pengaturan, pengingat backup).
final lastBackupProvider = StreamProvider<LastBackup?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLastBackup(),
);

final reminderDismissedProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchReminderDismissed(),
);
