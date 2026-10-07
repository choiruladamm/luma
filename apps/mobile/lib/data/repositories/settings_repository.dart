import 'package:flutter_riverpod/flutter_riverpod.dart';

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
