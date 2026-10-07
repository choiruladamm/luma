import 'package:drift/native.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/reader_prefs.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  test('starts at defaults, emits what was saved', () async {
    final repo = SettingsRepository(db);
    final emissions = repo.watchReaderPrefs();
    final expectation = expectLater(
      emissions,
      emitsInOrder([
        const ReaderPrefs(),
        const ReaderPrefs(sizeStep: 5, theme: AppTheme.dark),
      ]),
    );
    await pumpEventQueue();
    await repo.saveReaderPrefs(
      const ReaderPrefs(sizeStep: 5, theme: AppTheme.dark),
    );
    await expectation;
  });

  test('saving again overwrites, one row per key', () async {
    final repo = SettingsRepository(db);
    await repo.saveReaderPrefs(const ReaderPrefs(sizeStep: 1));
    await repo.saveReaderPrefs(const ReaderPrefs(sizeStep: 2));
    expect(await repo.watchReaderPrefs().first, const ReaderPrefs(sizeStep: 2));
    final rows = await db.select(db.settings).get();
    expect(rows.where((r) => r.key == 'reader.size'), hasLength(1));
  });
}
