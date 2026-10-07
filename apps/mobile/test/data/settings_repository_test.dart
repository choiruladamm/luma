import 'package:drift/native.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/ai_model.dart';
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

  test('model: default until picked, then the pick', () async {
    final repo = SettingsRepository(db);
    expect(await repo.watchModel().first, defaultAiModel);
    await repo.saveModel('qwen/qwen3.8-flash');
    expect(await repo.watchModel().first, 'qwen/qwen3.8-flash');
  });

  test('last backup: none until saved, then what was saved', () async {
    final repo = SettingsRepository(db);
    expect(await repo.watchLastBackup().first, isNull);
    final b = (at: DateTime(2026, 10, 6, 21, 30), name: 'x.zip', size: 1234);
    await repo.saveLastBackup(b);
    expect(await repo.watchLastBackup().first, b);
  });

  test('reminder dismissal is remembered', () async {
    final repo = SettingsRepository(db);
    expect(await repo.watchReminderDismissed().first, isNull);
    await repo.dismissReminder(DateTime(2026, 10, 12, 8));
    expect(
      await repo.watchReminderDismissed().first,
      DateTime(2026, 10, 12, 8),
    );
  });
}
