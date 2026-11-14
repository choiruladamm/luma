import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../../../data/database/app_database.dart';
import '../../../../data/repositories/cloud_backup_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../data/services/restore_service.dart';
import '../../../../domain/models/backup.dart';
import '../../../../l10n/l10n.dart';
import '../../../../routing/router.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../view_models/backup_view_model.dart';
import 'backup_listener.dart';
import 'cloud_restore_sheet.dart';
import 'restore_sheets.dart';
import 'settings_page.dart';

/// Backup & pulihin (board Pengaturan 07): login = backup ke cloud + salinan
/// file; belum login = backup ke file, opsi Cloud ilang.
class BackupView extends ConsumerStatefulWidget {
  const BackupView({super.key});

  @override
  ConsumerState<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends ConsumerState<BackupView> {
  BackupController get _backup => ref.read(backupControllerProvider.notifier);

  bool _restoring = false;

  /// Pulihin (board 28–32): pilih zip → cek di folder sementara → ringkasan
  /// & konfirmasi → ganti data → database dibuka lagi → balik ke Rak.
  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    try {
      while (mounted) {
        final zip = await ref.read(filePickerServiceProvider).pickBackup();
        if (zip == null || !mounted) return;
        final service = ref.read(restoreServiceProvider);
        final name = p.basename(zip.path);
        final RestorePreview preview;
        try {
          preview = await service.inspect(zip);
        } on RestoreException catch (e) {
          if (!mounted) return;
          if (await showRestoreFailed(context, fileName: name, error: e)) {
            continue; // pilih file lain
          }
          return;
        }
        final current = await service.currentBooks();
        if (!mounted) {
          await preview.discard();
          return;
        }
        final ok = await showRestoreSummary(
          context,
          preview: preview,
          currentBooks: current,
        );
        if (!ok || !mounted) {
          await preview.discard();
          return;
        }
        await _apply(service, preview);
        return;
      }
    } finally {
      _restoring = false;
    }
  }

  /// Pulihin dari cloud: pilih snapshot → download & cek → ringkasan yang
  /// sama dengan zip biasa (board 28) → ganti data.
  Future<void> _restoreCloud() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final repo = ref.read(cloudBackupRepositoryProvider);
      final service = ref.read(restoreServiceProvider);
      final picked = await showCloudRestorePicker(
        context,
        load: repo.list,
        prepare: (b) => repo.prepareRestore(b, service),
      );
      if (!mounted) {
        if (picked is RestorePreview) await picked.discard();
        return;
      }
      switch (picked) {
        case RestoreException(:final manifest):
          await showRestoreFailed(
            context,
            fileName: manifest == null
                ? ''
                : backupFileName(manifest.createdAt),
            error: picked,
          );
        case RestorePreview preview:
          final current = await service.currentBooks();
          if (!mounted) return await preview.discard();
          final ok = await showRestoreSummary(
            context,
            preview: preview,
            currentBooks: current,
          );
          if (!ok || !mounted) return await preview.discard();
          await _apply(service, preview);
      }
    } finally {
      _restoring = false;
    }
  }

  Future<void> _apply(RestoreService service, RestorePreview preview) async {
    final stage = ValueNotifier(1);
    final nav = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);
    // Pengaturan ilang pas balik ke Rak; toast-nya lewat navigator root yang
    // tetep ada (masih di bawah ScaffoldMessenger & Theme).
    final app = Navigator.of(context, rootNavigator: true).context;
    showAppSheet<void>(
      context,
      dismissible: false,
      builder: (_) => RestoreProgressSheet(
        name: preview.fileName,
        books: preview.manifest.books,
        stage: stage,
      ),
    );
    var failed = false;
    try {
      await service.apply(preview, onStage: (s) => stage.value = s);
      stage.value = 3;
    } catch (_) {
      failed = true;
      await preview.discard();
    } finally {
      // Database ditutup pas apply: buka lagi (data baru, atau yang lama kalau
      // gagal). Semua provider data ikut dibangun ulang.
      ref.invalidate(appDatabaseProvider);
    }
    nav.pop();
    stage.dispose();
    if (failed) {
      if (mounted) {
        await showRestoreFailed(context, fileName: preview.fileName);
      }
      return;
    }
    // Login = kuota gratis jalan tanpa key; cuma yang belum login perlu diingetin.
    final signedIn =
        ref.read(authControllerProvider).value?.status == AuthStatus.signedIn;
    final noKey =
        !signedIn && await ref.read(apiKeyStoreProvider).read() == null;
    final m = preview.manifest;
    router.go(Routes.home);
    if (!app.mounted) return;
    final c = app.stabilo;
    showToast(
      app,
      app.l10n.settingsYourDataIsBack,
      subtitle: app.l10n.settingsBooksTranslations(m.books, m.aiResults),
      leading: ToastTile(icon: AppIcons.check, bg: c.accent, fg: c.onAccent),
      note: noKey ? app.l10n.settingsApiKeysArenTIncludedIn : null,
      actionLabel: noKey ? app.l10n.settingsAddKey : null,
      onAction: () => router.push(Routes.settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final lastAsync = ref.watch(lastBackupProvider);
    final cloud =
        ref.watch(authControllerProvider).value?.status == AuthStatus.signedIn;
    final note = _noteStyle(c);
    return BackupListener(
      child: SettingsPage(
        title: context.l10n.settingsBackupRestore,
        children: [
          _BackupCard(
            last: lastAsync.value,
            loaded: lastAsync.hasValue,
            cloud: cloud,
            onBackup: cloud ? _backup.startCloud : _backup.start,
            onSaveFile: _backup.start,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s2,
            children: [
              Text(context.l10n.settingsBackupRestoreFrom, style: note),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: context.l10n.settingsBackupFile,
                      icon: HugeIcons.strokeRoundedFolderOpen,
                      height: 48,
                      onPressed: _restore,
                    ),
                  ),
                  if (cloud)
                    Expanded(
                      child: AppButton.secondary(
                        label: context.l10n.settingsBackupCloud,
                        icon: AppIcons.cloudDownload,
                        height: 48,
                        onPressed: _restoreCloud,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: context
                      .l10n
                      .settingsIncludesBooksReadingProgressTranslationsAnd,
                ),
                TextSpan(
                  text: context.l10n.settingsApiKeysArenTIncluded,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: context.l10n.settingsSoAddYoursAgainAfterRestoring,
                ),
              ],
            ),
            style: note,
          ),
        ],
      ),
    );
  }
}

TextStyle _noteStyle(StabiloColors c) => StabiloType.caption.copyWith(
  fontSize: 12.5,
  height: 1.45,
  fontWeight: FontWeight.w400,
  color: c.ink2,
);

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.last,
    required this.loaded,
    required this.cloud,
    required this.onBackup,
    required this.onSaveFile,
  });

  final LastBackup? last;

  /// Status backup udah kebaca (biar gak sempet nongol "belum pernah").
  final bool loaded;

  /// Login: tombol utama ke cloud + link salinan file.
  final bool cloud;
  final VoidCallback onBackup;
  final VoidCallback onSaveFile;

  /// "Barusan" (< 1 jam), "Hari ini", "Kemarin", "3 hari lalu", ...
  static String when(BuildContext context, DateTime at, DateTime now) {
    if (now.difference(at) < const Duration(hours: 1)) {
      return context.l10n.settingsJustNow;
    }
    final s = ago(at, now, locale: context.l10n.localeName);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = last;
    final never = loaded && b == null;
    final small = _noteStyle(c).copyWith(height: null);
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: Space.s3,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: never ? c.pink : c.muted,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Center(
                  child: AppIcon(
                    never ? AppIcons.alert : AppIcons.cloudUpload,
                    size: 22,
                    color: never ? c.onPink : c.ink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      b == null
                          ? context.l10n.settingsBackupStatus
                          : context.l10n.settingsLastBackup,
                      style: small,
                    ),
                    Text(
                      b != null
                          ? when(context, b.at, DateTime.now())
                          : never
                          ? context.l10n.settingsNoBackupsYet
                          : ' ',
                      style: StabiloType.titleSm.copyWith(
                        fontSize: 18,
                        letterSpacing: -0.18,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      b != null
                          ? '${b.name} · ${fileSize(b.size, locale: context.l10n.localeName)}'
                          : never
                          ? context.l10n.settingsYourDataIsOnlyOnThis
                          : ' ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppButton.primary(
            label: context.l10n.settingsBackUpNow,
            icon: cloud ? AppIcons.cloudUpload : AppIcons.backup,
            onPressed: onBackup,
          ),
          if (cloud)
            Center(
              child: TextButton(
                onPressed: onSaveFile,
                child: Text(
                  context.l10n.settingsBackupSaveToFile,
                  style: StabiloType.label.copyWith(
                    fontSize: 13.5,
                    color: c.ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
