import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/data/services/file_picker_service.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/data/services/share_service.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
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

class FakePreview extends RestorePreview {
  FakePreview(BackupManifest m)
    : super(Directory('/tmp/none'), 'luma-backup-20261003-2140.zip', m);

  bool discarded = false;

  @override
  Future<void> discard() async => discarded = true;
}

class FakeRestore extends Fake implements RestoreService {
  FakeRestore(this.preview);

  final FakePreview preview;
  RestoreException? inspectError;
  bool applyFails = false;
  final applied = <RestorePreview>[];

  @override
  Future<RestorePreview> inspect(File zip) async {
    if (inspectError != null) throw inspectError!;
    return preview;
  }

  @override
  Future<int> currentBooks() async => 3;

  @override
  Future<void> apply(
    RestorePreview preview, {
    void Function(int stage)? onStage,
  }) async {
    onStage?.call(1);
    onStage?.call(2);
    if (applyFails) throw const FileSystemException('disk full');
    applied.add(preview);
  }
}

class FakePicker implements FilePickerService {
  final picks = <File?>[];

  @override
  Future<File?> pickBackup() async => picks.isEmpty ? null : picks.removeAt(0);

  @override
  Future<PickedFile?> pickEpub() => throw UnimplementedError();
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

  testWidgets('the default chip sits beside the model name, hugging its text', (
    tester,
  ) async {
    await open(tester);
    final label = tester.getRect(find.text('GLM 5.3 Flash'));
    final chip = tester.getRect(
      find
          .ancestor(
            of: find.text('Default · paling hemat'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(chip.height, 20);
    expect((chip.center.dy - label.center.dy).abs(), lessThan(4)); // same line
    expect(chip.left, greaterThan(label.right)); // after the name
    // Hugs its text (8 + 8 padding), not the whole row.
    final text = tester.getSize(find.text('Default · paling hemat')).width;
    expect(chip.width, closeTo(text + 16, 0.5));
    // The model ID stays under both.
    expect(
      tester.getTopLeft(find.text('z-ai/glm-5.3-flash')).dy,
      greaterThan(label.bottom),
    );
  });

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

  group('key input', () {
    const good = 'sk-or-v1-0123456789abcdef';
    const old = 'sk-or-v1-saved';
    final field = find.byType(TextField);

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 700)); // debounce
      await tester.pumpAndSettle();
    }

    String shown(WidgetTester tester) =>
        tester.widget<TextField>(field).controller!.text;

    testWidgets('a good key is checked, then saved', (tester) async {
      await open(tester);
      openRouter.checked.clear();
      await type(tester, good);
      expect(openRouter.checked, [good]);
      expect(await ApiKeyStore().read(), good);
      expect(find.text('Key-nya jalan'), findsOneWidget);
    });

    testWidgets('text that is not a key is never saved or sent', (
      tester,
    ) async {
      await open(tester);
      openRouter.checked.clear();
      await type(tester, 'halo dunia');
      expect(find.textContaining('bukan API key OpenRouter'), findsOneWidget);
      expect(openRouter.checked, isEmpty);
      expect(await ApiKeyStore().read(), old); // the saved key stays
      expect(find.text('Key-nya jalan'), findsNothing);
    });

    testWidgets('a key OpenRouter refuses is not saved', (tester) async {
      await open(tester);
      openRouter.keyOk = false;
      await type(tester, good);
      expect(find.textContaining('gak disimpen'), findsOneWidget);
      expect(await ApiKeyStore().read(), old);
    });

    testWidgets('offline: a well-formed key is saved anyway', (tester) async {
      await open(tester);
      openRouter.keyOk = null;
      await type(tester, good);
      expect(await ApiKeyStore().read(), good);
      expect(find.text('Key-nya jalan'), findsNothing);
      expect(find.textContaining('gak disimpen'), findsNothing);
    });

    testWidgets('pasted spaces and new lines never reach the field', (
      tester,
    ) async {
      await open(tester);
      await type(tester, '  $good \n');
      expect(shown(tester), good);
      expect(await ApiKeyStore().read(), good);
    });

    testWidgets('the clear button wipes the field and the Keychain', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Hapus API key OpenRouter'));
      await tester.pumpAndSettle();
      expect(shown(tester), isEmpty);
      expect(await ApiKeyStore().read(), isNull);
      expect(find.bySemanticsLabel('Hapus API key OpenRouter'), findsNothing);
      expect(find.text('Key-nya jalan'), findsNothing);
    });

    testWidgets('no clear button while the field is empty', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await open(tester);
      expect(find.bySemanticsLabel('Hapus API key OpenRouter'), findsNothing);
      await tester.enterText(field, good);
      await tester.pump();
      expect(find.bySemanticsLabel('Hapus API key OpenRouter'), findsOneWidget);
    });

    testWidgets('emptying the field by hand deletes the key too', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(field, '');
      await tester.pump();
      expect(await ApiKeyStore().read(), isNull);
    });
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
      for (final k in [
        'sk-or-v1-aaaaaaa1',
        'sk-or-v1-aaaaaa12',
        'sk-or-v1-aaaaa123',
      ]) {
        await tester.enterText(find.byType(TextField), k);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(openRouter.checked, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(openRouter.checked, ['sk-or-v1-aaaaa123']);

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

  group('restore', () {
    late FakeRestore restore;
    late FakePicker picker;

    /// Settings over the shelf, like in the app, so going home is visible.
    Future<void> openFromShelf(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manifest = BackupManifest(
        appVersion: '0.1.0',
        schemaVersion: 3,
        createdAt: DateTime(2026, 10, 3, 21, 40),
        books: 7,
        aiResults: 1240,
      );
      restore = FakeRestore(FakePreview(manifest));
      picker = FakePicker()
        ..picks.add(File('/tmp/luma-backup-20261003-2140.zip'));
      final cache = FakeAiResults();
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Center(child: Text('RAK'))),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, _) => const SettingsView(),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(FakeSettings()),
            aiResultsRepositoryProvider.overrideWithValue(cache),
            apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
            openRouterServiceProvider.overrideWithValue(FakeOpenRouter()),
            restoreServiceProvider.overrideWithValue(restore),
            filePickerServiceProvider.overrideWithValue(picker),
          ],
          child: MaterialApp.router(
            theme: stabiloTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      cache.stats.add((paragraphs: 0, bytes: 0));
      await tester.pumpAndSettle();
    }

    Future<void> tapRestore(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Pulihin dari backup'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Pulihin dari backup'));
      await tester.pumpAndSettle();
    }

    testWidgets('summary, the tick, then everything back on the shelf', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({}); // fresh phone, no key
      await openFromShelf(tester);
      await tapRestore(tester);

      expect(find.text('Pulihin dari backup ini?'), findsOneWidget);
      expect(find.text('luma-backup-20261003-2140.zip'), findsOneWidget);
      expect(
        find.text('Dibikin 3 Okt 2026, 21.40 · Luma 0.1.0'),
        findsOneWidget,
      );
      expect(find.text('7'), findsOneWidget);
      expect(find.text('1.240'), findsOneWidget);
      expect(find.textContaining('(3 buku)'), findsOneWidget);

      AppButton go() => tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Ganti & pulihin'),
      );
      expect(go().onPressed, isNull); // not until ticked
      await tester.tap(find.text('Iya, gua ngerti. Ganti aja semuanya.'));
      await tester.pump();
      expect(go().onPressed, isNotNull);
      await tester.tap(find.text('Ganti & pulihin'));
      await tester.pumpAndSettle();

      expect(restore.applied, hasLength(1));
      expect(find.text('RAK'), findsOneWidget);
      expect(find.text('Sip, data lo udah balik!'), findsOneWidget);
      expect(find.text('7 buku · 1.240 terjemahan'), findsOneWidget);
      expect(
        find.text(
          'API key gak ikut backup, isi ulang dulu biar bisa nerjemahin.',
        ),
        findsOneWidget,
      );
      expect(find.text('Isi key'), findsOneWidget);
    });

    testWidgets('a key already there: no reminder', (tester) async {
      await openFromShelf(tester); // setUp saved a key
      await tapRestore(tester);
      await tester.tap(find.text('Iya, gua ngerti. Ganti aja semuanya.'));
      await tester.pump();
      await tester.tap(find.text('Ganti & pulihin'));
      await tester.pumpAndSettle();
      expect(find.text('Sip, data lo udah balik!'), findsOneWidget);
      expect(find.text('Isi key'), findsNothing);
    });

    testWidgets('"Batal": nothing replaced, the extracted copy removed', (
      tester,
    ) async {
      await openFromShelf(tester);
      await tapRestore(tester);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(restore.applied, isEmpty);
      expect(restore.preview.discarded, isTrue);
      expect(find.text('RAK'), findsNothing);
    });

    testWidgets('not a backup: says so, "Pilih file lain" opens the picker', (
      tester,
    ) async {
      await openFromShelf(tester);
      restore.inspectError = const RestoreException(RestoreError.notBackup);
      await tapRestore(tester);
      expect(find.text('Ini bukan backup Luma'), findsOneWidget);
      expect(find.text('luma-backup-20261003-2140.zip'), findsOneWidget);
      expect(
        find.text('Tenang, data yang sekarang gak diapa-apain.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pilih file lain'));
      await tester.pumpAndSettle();
      expect(picker.picks, isEmpty); // asked again (and cancelled)
      expect(find.text('Ini bukan backup Luma'), findsNothing);
    });

    testWidgets('made by a newer Luma: names both versions', (tester) async {
      await openFromShelf(tester);
      restore.inspectError = RestoreException(
        RestoreError.tooNew,
        manifest: BackupManifest(
          appVersion: '0.3.0',
          schemaVersion: 9,
          createdAt: DateTime(2026, 11, 20),
          books: 1,
          aiResults: 0,
        ),
      );
      await tapRestore(tester);
      expect(find.text('Backup-nya dari Luma yang lebih baru'), findsOneWidget);
      expect(find.textContaining('dibikin pake Luma 0.3.0'), findsOneWidget);
      expect(find.textContaining('keinstall masih 0.1.0'), findsOneWidget);
      expect(
        find.text('luma-backup-20261003-2140.zip · v0.3.0'),
        findsOneWidget,
      );
    });

    testWidgets('swapping fails: says the old data is back', (tester) async {
      await openFromShelf(tester);
      restore.applyFails = true;
      await tapRestore(tester);
      await tester.tap(find.text('Iya, gua ngerti. Ganti aja semuanya.'));
      await tester.pump();
      await tester.tap(find.text('Ganti & pulihin'));
      await tester.pumpAndSettle();
      expect(find.text('Yah, gagal mulihin'), findsOneWidget);
      expect(find.text('RAK'), findsNothing);
      expect(restore.preview.discarded, isTrue);
    });
  });
}
