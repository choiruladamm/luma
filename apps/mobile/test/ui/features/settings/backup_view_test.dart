import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/cloud_backup_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/cloud_backup_service.dart';
import 'package:luma/data/services/file_picker_service.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/data/services/share_service.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/auth/view_models/auth_view_model.dart';
import 'package:luma/ui/features/settings/views/backup_view.dart';

import '../../../fakes.dart';

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
    bool snapshotOnly = false,
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
  Future<RestorePreview> inspect(
    File zip, {
    String? fileName,
    Future<void> Function(Directory dir, AppDatabase snapshot)? fill,
  }) async {
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

class SignedIn extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(AuthStatus.signedIn);
}

/// Cloud backup without a backend: [release] finishes the upload.
class FakeCloud extends Fake implements CloudBackupRepository {
  final release = Completer<void>();
  Object? error;
  final backups = <CloudBackup>[];
  final prepared = <String>[];
  RestorePreview? preview;

  @override
  Future<LastBackup> backup({
    void Function(String name, BackupManifest manifest)? onStart,
    void Function(BackupStage stage, double fraction)? onProgress,
  }) async {
    onStart?.call(
      'luma-backup-20261113-0812.zip',
      BackupManifest(
        appVersion: '0.3.0',
        schemaVersion: 17,
        createdAt: DateTime(2026, 11, 13, 8, 12),
        books: 3,
        aiResults: 50,
      ),
    );
    onProgress?.call(BackupStage.books, 0.4);
    await release.future;
    if (error != null) throw error!;
    return (
      at: DateTime.now(),
      name: 'luma-backup-20261113-0812.zip',
      size: 15352134,
    );
  }

  @override
  Future<List<CloudBackup>> list() async => backups;

  @override
  Future<RestorePreview> prepareRestore(
    CloudBackup backup,
    RestoreService restore,
  ) async {
    prepared.add(backup.id);
    return preview!;
  }
}

class FakePicker implements FilePickerService {
  final picks = <File?>[];

  @override
  Future<File?> pickBackup() async => picks.isEmpty ? null : picks.removeAt(0);

  @override
  Future<PickedFile?> pickBook() => throw UnimplementedError();

  @override
  Future<void> clearTemporaryFiles() async {}
}

void main() {
  late FakeSettings settings;
  late FakeBackup backup;
  late FakeShare share;
  late FakeRestore restore;
  late FakePicker picker;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    LastBackup? lastBackup,
    FakeCloud? cloud,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backup = FakeBackup();
    share = FakeShare();
    settings = FakeSettings()..lastBackup = lastBackup;
    restore = FakeRestore(
      FakePreview(
        BackupManifest(
          appVersion: '0.1.0',
          schemaVersion: 3,
          createdAt: DateTime(2026, 10, 3, 21, 40),
          books: 7,
          aiResults: 1240,
        ),
      ),
    );
    picker = FakePicker()
      ..picks.add(File('/tmp/luma-backup-20261003-2140.zip'));
    cloud?.preview = restore.preview;
    final router = GoRouter(
      initialLocation: '/settings/backup',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Center(child: Text('RAK'))),
          routes: [
            GoRoute(
              path: 'settings/backup',
              builder: (_, _) => const BackupView(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
          backupServiceProvider.overrideWithValue(backup),
          shareServiceProvider.overrideWithValue(share),
          restoreServiceProvider.overrideWithValue(restore),
          filePickerServiceProvider.overrideWithValue(picker),
          if (cloud != null) ...[
            authControllerProvider.overrideWith(SignedIn.new),
            cloudBackupRepositoryProvider.overrideWithValue(cloud),
          ],
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'openrouter_api_key': 'sk-or-v1-saved',
    }),
  );

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> confirmRestore(WidgetTester tester) async {
    await tester.tap(find.text('Iya, gua ngerti. Ganti aja semuanya.'));
    await tester.pump();
    await tester.tap(find.text('Ganti & pulihin'));
    await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets('renders in ${b.name}: title and note', (tester) async {
      await open(tester, b: b);
      expect(find.text('Backup & pulihin'), findsOneWidget);
      expect(
        find.textContaining('API key gak ikut', findRichText: true),
        findsOneWidget,
      );
    });
  }

  group('status card', () {
    testWidgets('never backed up says so', (tester) async {
      await open(tester);
      expect(find.text('Belum pernah backup'), findsOneWidget);
      expect(find.text('Data lo cuma ada di HP ini doang'), findsOneWidget);
    });

    testWidgets('recent backup says Barusan', (tester) async {
      await open(
        tester,
        lastBackup: (
          at: DateTime.now(),
          name: 'luma-backup-x.luma',
          size: 12688179,
        ),
      );
      expect(find.text('Barusan'), findsOneWidget);
      expect(find.text('luma-backup-x.luma · 12,1 MB'), findsOneWidget);
    });

    testWidgets('old backup shows days ago, name and size', (tester) async {
      final now = DateTime.now();
      await open(
        tester,
        lastBackup: (
          at: DateTime(now.year, now.month, now.day - 3, 12),
          name: 'luma-backup-x.zip',
          size: 12688179,
        ),
      );
      expect(find.text('Backup terakhir'), findsOneWidget);
      expect(find.text('3 hari lalu'), findsOneWidget);
      expect(find.text('luma-backup-x.zip · 12,1 MB'), findsOneWidget);
    });
  });

  group('signed out', () {
    testWidgets('file only: no cloud options', (tester) async {
      await open(tester);
      expect(find.text('Backup sekarang'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Cloud'), findsNothing);
      expect(find.text('Simpen salinan ke file'), findsNothing);
    });

    testWidgets('Backup sekarang wraps, shares, updates the card', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Backup sekarang');
      expect(find.text('Lagi ngebungkus backup...'), findsOneWidget);
      backup.release.complete();
      await tester.pumpAndSettle();
      expect(share.shared, hasLength(1));
      expect(find.text('Backup kelar, aman!'), findsOneWidget);
      expect(settings.lastBackup!.name, 'luma-backup-20261006-2130.zip');
      expect(find.text('Barusan'), findsOneWidget);
    });

    testWidgets('a failure says so', (tester) async {
      await open(tester);
      backup.error = const FileSystemException('disk full');
      await tap(tester, 'Backup sekarang');
      backup.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Yah, backup gagal'), findsOneWidget);
      expect(settings.lastBackup, isNull);
    });
  });

  group('signed in', () {
    testWidgets('Backup sekarang goes to the cloud, no share sheet', (
      tester,
    ) async {
      final cloud = FakeCloud();
      await open(tester, cloud: cloud);
      expect(find.text('Cloud'), findsOneWidget);
      await tap(tester, 'Backup sekarang');
      expect(find.text('Lagi ngebungkus backup...'), findsOneWidget);
      cloud.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Backup kelar, aman!'), findsOneWidget);
      expect(share.shared, isEmpty);
    });

    testWidgets('"Simpen salinan ke file" exports a file', (tester) async {
      await open(tester, cloud: FakeCloud());
      await tap(tester, 'Simpen salinan ke file');
      backup.release.complete();
      await tester.pumpAndSettle();
      expect(share.shared, hasLength(1));
    });

    testWidgets('a full cloud says so', (tester) async {
      final cloud = FakeCloud()
        ..error = const BackendException(
          code: 'STORAGE_FULL',
          message: 'Cloud storage is full',
          statusCode: 413,
        );
      await open(tester, cloud: cloud);
      await tap(tester, 'Backup sekarang');
      cloud.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Penyimpanan cloud lo udah penuh'), findsOneWidget);
    });

    testWidgets('restore from cloud: pick, same summary, data back', (
      tester,
    ) async {
      final cloud = FakeCloud()
        ..backups.add(
          CloudBackup(
            id: '20261113T011200Z',
            createdAt: DateTime.now().copyWith(hour: 8, minute: 12),
            size: 15352134,
            books: 7,
            aiResults: 1240,
            schemaVersion: 17,
            appVersion: '0.3.0',
          ),
        );
      await open(tester, cloud: cloud);
      await tap(tester, 'Cloud');
      await tester.pumpAndSettle();
      expect(find.text('Pilih backup cloud'), findsOneWidget);
      await tester.tap(find.text('Hari ini, 08.12'));
      await tester.pumpAndSettle();
      expect(cloud.prepared, ['20261113T011200Z']);
      await confirmRestore(tester);
      expect(restore.applied, hasLength(1));
      expect(find.text('RAK'), findsOneWidget);
      expect(find.text('Sip, data lo udah balik!'), findsOneWidget);
      expect(find.text('Isi key'), findsNothing);
    });

    testWidgets('restore from cloud with nothing there says so', (
      tester,
    ) async {
      await open(tester, cloud: FakeCloud());
      await tap(tester, 'Cloud');
      await tester.pumpAndSettle();
      expect(
        find.text('Belum ada backup di cloud. Tekan "Backup ke cloud" dulu.'),
        findsOneWidget,
      );
    });
  });

  group('restore from file', () {
    Future<void> tapRestore(WidgetTester tester) async {
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
    }

    testWidgets('summary, tick, then everything back on the shelf', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({}); // fresh phone, no key
      await open(tester);
      await tapRestore(tester);
      expect(find.text('Pulihin dari backup ini?'), findsOneWidget);
      expect(find.textContaining('(3 buku)'), findsOneWidget);
      AppButton go() => tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Ganti & pulihin'),
      );
      expect(go().onPressed, isNull); // not until ticked
      await confirmRestore(tester);
      expect(restore.applied, hasLength(1));
      expect(find.text('RAK'), findsOneWidget);
      expect(find.text('7 buku · 1.240 terjemahan'), findsOneWidget);
      expect(find.text('Isi key'), findsOneWidget);
    });

    testWidgets('"Batal": nothing replaced, the extracted copy removed', (
      tester,
    ) async {
      await open(tester);
      await tapRestore(tester);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(restore.applied, isEmpty);
      expect(restore.preview.discarded, isTrue);
      expect(find.text('RAK'), findsNothing);
    });

    testWidgets('not a backup: says so, "Pilih file lain" asks again', (
      tester,
    ) async {
      await open(tester);
      restore.inspectError = const RestoreException(RestoreError.notBackup);
      await tapRestore(tester);
      expect(find.text('Ini bukan backup Luma'), findsOneWidget);
      await tester.tap(find.text('Pilih file lain'));
      await tester.pumpAndSettle();
      expect(picker.picks, isEmpty);
      expect(find.text('Ini bukan backup Luma'), findsNothing);
    });

    testWidgets('swapping fails: says the old data is back', (tester) async {
      await open(tester);
      restore.applyFails = true;
      await tapRestore(tester);
      await confirmRestore(tester);
      expect(find.text('Yah, gagal mulihin'), findsOneWidget);
      expect(find.text('RAK'), findsNothing);
      expect(restore.preview.discarded, isTrue);
    });
  });
}
