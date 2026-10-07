import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_model.dart';
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
