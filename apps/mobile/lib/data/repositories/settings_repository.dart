import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_model.dart';
import '../../domain/models/book.dart';
import '../../domain/models/backup.dart';
import '../../domain/models/reader_prefs.dart';
import '../database/app_database.dart';

/// Reads and writes the settings that are included in backups, stored in the
/// key-value `settings` table.
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

  Stream<String> watchLocale() =>
      (_db.select(_db.settings)..where((s) => s.key.equals('app.locale')))
          .watchSingleOrNull()
          .map((row) => row?.value == 'en' ? 'en' : 'id')
          .distinct();

  Future<void> saveLocale(String language) {
    if (language != 'id' && language != 'en') {
      throw ArgumentError.value(language, 'language');
    }
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'app.locale', value: language),
        );
  }

  /// Emits the LLM model chosen in Settings, or [defaultAiModel] if none is chosen.
  Stream<String> watchModel() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_model)))
          .watchSingleOrNull()
          .map((row) => row?.value ?? defaultAiModel)
          .distinct();

  Future<void> saveModel(String id) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: _model, value: id));

  static const _model = 'ai.model';

  static const _chatHint = 'reader.chatHintSeen';
  Future<bool> chatHintSeen() async =>
      (await (_db.select(
        _db.settings,
      )..where((s) => s.key.equals(_chatHint))).getSingleOrNull())?.value ==
      '1';
  Future<void> markChatHintSeen() => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: _chatHint, value: '1'),
      );

  /// Emits the shelf sort order, defaulting to [ShelfSort.lastOpened].
  Stream<ShelfSort> watchShelfSort() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_shelfSort)))
          .watchSingleOrNull()
          .map(
            (row) => ShelfSort.values.firstWhere(
              (s) => s.name == row?.value,
              orElse: () => ShelfSort.lastOpened,
            ),
          )
          .distinct();

  Future<void> saveShelfSort(ShelfSort sort) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: _shelfSort, value: sort.name),
      );

  static const _shelfSort = 'shelf.sort';

  /// Emits the shelf layout (grid or list), defaulting to grid; it never switches automatically.
  Stream<ShelfView> watchShelfView() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_shelfView)))
          .watchSingleOrNull()
          .map(
            (row) => ShelfView.values.firstWhere(
              (v) => v.name == row?.value,
              orElse: () => ShelfView.grid,
            ),
          )
          .distinct();

  Future<void> saveShelfView(ShelfView view) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: _shelfView, value: view.name),
      );

  static const _shelfView = 'shelf.view';

  /// Emits the last backup the user saved successfully, or null if there is none.
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

  /// Emits the time of the last successful cloud backup, or null if there is
  /// none.
  ///
  /// It drives the 24-hour automatic trigger and the Ex libris plate.
  Stream<DateTime?> watchCloudBackupAt() =>
      (_db.select(_db.settings)..where((s) => s.key.equals(_cloudAt)))
          .watchSingleOrNull()
          .map((row) => DateTime.tryParse(row?.value ?? ''));

  /// Records a successful cloud backup; it also counts as the last backup, which keeps the reminder quiet.
  Future<void> saveCloudBackup(LastBackup b) => _db.batch(
    (batch) => batch.insertAllOnConflictUpdate(_db.settings, [
      SettingsCompanion.insert(key: _backupAt, value: b.at.toIso8601String()),
      SettingsCompanion.insert(key: _backupName, value: b.name),
      SettingsCompanion.insert(key: _backupSize, value: '${b.size}'),
      SettingsCompanion.insert(key: _cloudAt, value: b.at.toIso8601String()),
    ]),
  );

  /// Emits when the backup reminder banner was last dismissed.
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
  static const _cloudAt = 'backup.cloudLastAt';

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

/// Aa and theme settings, used by the reading page and the app root (themeMode).
final readerPrefsProvider = StreamProvider<ReaderPrefs>(
  (ref) => ref.watch(settingsRepositoryProvider).watchReaderPrefs(),
);

/// The selected LLM model, read on every OpenRouter call instead of being hardcoded.
final aiModelProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).watchModel(),
);

/// The selected shelf sort order.
final shelfSortProvider = StreamProvider<ShelfSort>(
  (ref) => ref.watch(settingsRepositoryProvider).watchShelfSort(),
);

/// The selected shelf layout.
final shelfViewProvider = StreamProvider<ShelfView>(
  (ref) => ref.watch(settingsRepositoryProvider).watchShelfView(),
);

/// The last backup, shown in Settings and used by the backup reminder.
final lastBackupProvider = StreamProvider<LastBackup?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLastBackup(),
);

/// The last cloud backup, shown on the Ex libris plate.
final cloudBackupAtProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchCloudBackupAt(),
);

final reminderDismissedProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchReminderDismissed(),
);

final appLocaleProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLocale(),
);
