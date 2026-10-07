import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/data/services/share_service.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../../../fakes.dart';

class FakeAiResults extends Fake implements AiResultsRepository {
  final stats = StreamController<AiCacheStats>.broadcast();
  int clears = 0;

  @override
  Stream<AiCacheStats> watchStats() => stats.stream;

  @override
  Future<void> clear() async {
    clears++;
    stats.add((paragraphs: 0, bytes: 0));
  }
}

/// A finished backup without touching the disk.
class FakeBackupFile extends BackupFile {
  FakeBackupFile(String name, BackupManifest manifest)
    : super(Directory('/tmp/none'), File('/tmp/none/$name'), manifest);

  @override
  int get size => 13002342; // 12,4 MB

  @override
  Future<void> dispose() async {}
}

class FakeBackup extends Fake implements BackupService {
  /// Holds the backup "running" until completed; error = it fails.
  final release = Completer<void>();
  Object? error;
  bool cancelled = false;

  @override
  Future<BackupFile?> export({
    DateTime? now,
    void Function(String name, BackupManifest manifest)? onStart,
    void Function(BackupStage stage, double fraction)? onProgress,
    Future<void>? cancel,
  }) async {
    final manifest = BackupManifest(
      appVersion: '0.1.0',
      schemaVersion: 3,
      createdAt: DateTime(2026, 10, 6, 21, 30),
      books: 7,
      aiResults: 1240,
    );
    onStart?.call('luma-backup-20261006-2130.zip', manifest);
    onProgress?.call(BackupStage.database, 0.72);
    cancel?.then((_) => cancelled = true);
    await Future.any([release.future, ?cancel]);
    if (cancelled) return null;
    if (error != null) throw error!;
    return FakeBackupFile('luma-backup-20261006-2130.zip', manifest);
  }
}

class FakeShare implements ShareService {
  bool saved = true;
  final shared = <String>[];

  @override
  Future<bool> shareFile(File file, {Rect? origin}) async {
    shared.add(file.path);
    return saved;
  }
}

void main() {
  late FakeSettings settings;
  late FakeAiResults cache;
  late FakeOpenRouter openRouter;
  late FakeBackup backup;
  late FakeShare share;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    AiCacheStats stats = (paragraphs: 1240, bytes: 3355443),
    bool? keyOk = true,
    LastBackup? lastBackup,
  }) async {
    openRouter = FakeOpenRouter()..keyOk = keyOk;
    backup = FakeBackup();
    share = FakeShare();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = FakeSettings()..lastBackup = lastBackup;
    cache = FakeAiResults();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          aiResultsRepositoryProvider.overrideWithValue(cache),
          // Secure storage goes in-memory via setMockInitialValues.
          apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
          openRouterServiceProvider.overrideWithValue(openRouter),
          backupServiceProvider.overrideWithValue(backup),
          shareServiceProvider.overrideWithValue(share),
        ],
        child: MaterialApp(theme: stabiloTheme(b), home: const SettingsView()),
      ),
    );
    await tester.pump();
    cache.stats.add(stats);
    await tester.pumpAndSettle();
  }

  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'openrouter_api_key': 'sk-or-v1-saved',
    }),
  );

  for (final b in Brightness.values) {
    testWidgets('shows key (hidden), models, cache ($b)', (tester) async {
      await open(tester, b: b);
      expect(find.text('Pengaturan'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'sk-or-v1-saved');
      expect(field.obscureText, isTrue);
      for (final m in aiModels) {
        expect(find.text(m.label), findsOneWidget);
        expect(find.text(m.id), findsOneWidget);
      }
      expect(find.text('Default · paling hemat'), findsOneWidget);
      expect(find.text('1.240 paragraf · 3,2 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('header stays put; the list runs to the bottom edge', (
    tester,
  ) async {
    await open(tester);
    final fade = tester.widget<EdgeFadeScroll>(find.byType(EdgeFadeScroll));
    expect(fade.top, EdgeFadeSide.standard);
    expect(fade.bottom, EdgeFadeSide.none);
    expect(
      find.descendant(
        of: find.byType(EdgeFadeScroll),
        matching: find.text('Pengaturan'),
      ),
      findsNothing,
    );
  });

  testWidgets('typing a key saves it to the Keychain', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'sk-or-v1-new');
    await tester.pump();
    expect(await ApiKeyStore().read(), 'sk-or-v1-new');
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(await ApiKeyStore().read(), isNull);
  });

  testWidgets('picking a model saves it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Qwen 3.8 Flash'));
    await tester.pumpAndSettle();
    expect(settings.model, 'qwen/qwen3.8-flash');
  });

  testWidgets('clearing the cache asks first', (tester) async {
    await open(tester);
    await tester.tap(find.text('Hapus cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(cache.clears, 0);

    await tester.tap(find.text('Hapus cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(cache.clears, 1);
    expect(find.text('0 paragraf · 0 KB'), findsOneWidget);
  });

  testWidgets('nothing to clear: button is off', (tester) async {
    await open(tester, stats: (paragraphs: 0, bytes: 0));
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Hapus cache'),
    );
    expect(button.onPressed, isNull);
  });

  group('key status', () {
    const keychain =
        'Disimpen di Keychain iPhone, gak dikirim ke mana-mana selain '
        'OpenRouter.';

    testWidgets('a key OpenRouter accepts: "Key-nya jalan"', (tester) async {
      await open(tester);
      expect(find.text('Key-nya jalan'), findsOneWidget);
      expect(find.text('Disimpen di Keychain'), findsOneWidget);
      expect(openRouter.checked, ['sk-or-v1-saved']);
    });

    testWidgets('a rejected key says so', (tester) async {
      await open(tester, keyOk: false);
      expect(find.text('Key-nya ditolak OpenRouter'), findsOneWidget);
    });

    testWidgets('offline: just where it is kept', (tester) async {
      await open(tester, keyOk: null);
      expect(find.text(keychain), findsOneWidget);
      expect(find.text('Key-nya jalan'), findsNothing);
    });

    testWidgets('typing checks once, after a pause', (tester) async {
      await open(tester);
      openRouter.checked.clear();
      for (final k in ['sk-1', 'sk-12', 'sk-123']) {
        await tester.enterText(find.byType(TextField), k);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(openRouter.checked, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(openRouter.checked, ['sk-123']);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text(keychain), findsOneWidget); // no key, no check
    });
  });

  group('backup', () {
    Future<void> tapBackup(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Backup sekarang'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Backup sekarang'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('never backed up says so', (tester) async {
      await open(tester);
      expect(find.text('Belum pernah backup'), findsOneWidget);
      expect(find.text('Data lo cuma ada di HP ini doang'), findsOneWidget);
    });

    testWidgets('shows when, name and size of the last backup', (tester) async {
      final at = DateTime.now().subtract(const Duration(days: 3, hours: 1));
      await open(
        tester,
        lastBackup: (at: at, name: 'luma-backup-x.zip', size: 12688179),
      );
      expect(find.text('Backup terakhir'), findsOneWidget);
      expect(find.text('3 hari lalu'), findsOneWidget);
      expect(find.text('luma-backup-x.zip · 12,1 MB'), findsOneWidget);
    });

    testWidgets('wrap up, share, saved: toast and the card updates', (
      tester,
    ) async {
      await open(tester);
      await tapBackup(tester);
      expect(find.text('Lagi ngebungkus backup...'), findsOneWidget);
      expect(find.text('luma-backup-20261006-2130.zip'), findsOneWidget);
      expect(find.text('7 buku + progres bacanya'), findsOneWidget);
      expect(find.text('1.240 terjemahan'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);

      backup.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Lagi ngebungkus backup...'), findsNothing);
      expect(share.shared, hasLength(1));
      expect(find.text('Backup kelar, aman!'), findsOneWidget);
      expect(
        find.text('12,4 MB · luma-backup-20261006-2130.zip'),
        findsOneWidget,
      );
      expect(settings.lastBackup!.name, 'luma-backup-20261006-2130.zip');
      expect(find.text('Barusan'), findsOneWidget);
    });

    testWidgets('share sheet closed without saving: nothing recorded', (
      tester,
    ) async {
      await open(tester);
      share.saved = false;
      await tapBackup(tester);
      backup.release.complete();
      await tester.pumpAndSettle();
      expect(share.shared, hasLength(1));
      expect(settings.lastBackup, isNull);
      expect(find.text('Backup kelar, aman!'), findsNothing);
    });

    testWidgets('"Batalin" stops it, nothing shared', (tester) async {
      await open(tester);
      await tapBackup(tester);
      await tester.tap(find.text('Batalin'));
      await tester.pumpAndSettle();
      expect(backup.cancelled, isTrue);
      expect(find.text('Lagi ngebungkus backup...'), findsNothing);
      expect(share.shared, isEmpty);
    });

    testWidgets('a failure says so', (tester) async {
      await open(tester);
      backup.error = const FileSystemException('disk full');
      await tapBackup(tester);
      backup.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Yah, backup gagal'), findsOneWidget);
      expect(settings.lastBackup, isNull);
    });
  });
}
