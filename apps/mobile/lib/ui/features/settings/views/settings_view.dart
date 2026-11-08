import 'dart:async';

import '../../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../data/database/app_database.dart';
import '../../../../data/repositories/ai_breakdowns_repository.dart';
import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/catalog_sync_service.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../data/services/restore_service.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../../domain/models/backup.dart';
import '../../../../routing/router.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/dialog.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/field.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/backup_view_model.dart';
import '../view_models/settings_view_model.dart';
import 'backup_listener.dart';
import 'restore_sheets.dart';

/// Pengaturan app (board 23 Pengaturan app): API key, model AI, cache
/// terjemahan. Bagian Backup & pulihin nyusul di #24–#26.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _key = TextEditingController();

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
    final noKey = await ref.read(apiKeyStoreProvider).read() == null;
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
  void initState() {
    super.initState();
    ref.read(apiKeyStoreProvider).read().then((key) {
      if (mounted && _key.text.isEmpty) _key.text = key ?? '';
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  ApiKeyEntry get _entry => ref.read(apiKeyEntryProvider.notifier);

  Future<void> _clearCache() async {
    final ok = await showConfirmDialog(
      context,
      title: context.l10n.settingsDeleteTranslationCache,
      message: context.l10n.settingsAllSavedTranslationsWillBeDeleted,
      confirmLabel: context.l10n.bookClear,
    );
    if (!ok) return;
    await ref.read(aiResultsRepositoryProvider).clear();
    await ref.read(aiBreakdownsRepositoryProvider).clear();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(aiModelProvider).value ?? defaultAiModel;
    final cache = ref.watch(aiCacheStatsProvider).value;
    ref.listen(catalogSyncProvider, (_, state) {
      if (state is! CatalogSyncUpToDate) return;
      showToast(context, context.l10n.settingsYourCatalogIsAlreadyUpTo);
      ref.read(catalogSyncProvider.notifier).dismiss();
    });
    final catalogSync = ref.read(catalogSyncProvider.notifier);
    return BackupListener(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header nempel; isi di bawahnya mudar pas lewat (board EdgeFade).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
                child: SizedBox(
                  height: Layout.topBar,
                  child: Row(
                    spacing: Space.s3,
                    children: [
                      // Tab Atur gak punya balik; cuma pas di-push dari
                      // layar baca / chat.
                      if (Navigator.canPop(context))
                        CircleButton(
                          semanticLabel: context.l10n.settingsBack,
                          icon: AppIcons.back,
                          onPressed: () => context.pop(),
                        ),
                      Semantics(
                        header: true,
                        child: Text(
                          context.l10n.settingsSettings,
                          style: StabiloType.titleLg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: EdgeFadeScroll(
                  // Bawah edge-to-edge, padding akhir = safe area.
                  bottom: EdgeFadeSide.none,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      Layout.margin,
                      22,
                      Layout.margin,
                      MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      _LanguagePicker(),
                      const SizedBox(height: 22),
                      AppField(
                        label: context.l10n.settingsOpenrouterApiKey,
                        controller: _key,
                        secret: true,
                        // Spasi / baris baru ikut ke-paste dari mana-mana:
                        // dibuang di sini, key gak pernah mengandungnya.
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        onChanged: _entry.edit,
                        onClear: () {
                          _key.clear();
                          _entry.clear();
                        },
                      ),
                      const SizedBox(height: Space.s2),
                      _KeyStatus(status: ref.watch(apiKeyEntryProvider)),
                      const SizedBox(height: 22),
                      _Section(
                        label: context.l10n.settingsAiModel,
                        note: context
                            .l10n
                            .settingsChargesComeFromYourOpenrouterAccount,
                        child: _ModelPicker(
                          selected: model,
                          onSelect: (id) => ref
                              .read(settingsRepositoryProvider)
                              .saveModel(id),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _Section(
                        label: context.l10n.settingsBackupRestore,
                        note: const _BackupNote(),
                        child: _BackupCard(
                          last: ref.watch(lastBackupProvider).value,
                          loaded: ref.watch(lastBackupProvider).hasValue,
                          onBackup: _backup.start,
                          onRestore: _restore,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _Section(
                        label: context.l10n.settingsBookCatalog,
                        note: context
                            .l10n
                            .settingsAroundProjectGutenbergBooksToSearch,
                        child: _CatalogRow(
                          stats: ref.watch(catalogStatsProvider).value,
                          state: ref.watch(catalogSyncProvider),
                          onSync: () => catalogSync.sync(force: true),
                          onCancel: catalogSync.cancel,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _Section(
                        label: context.l10n.settingsStorage,
                        child: _CacheRow(stats: cache, onClear: _clearCache),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Di bawah field key. Key diterima OpenRouter: "Key-nya jalan". Bukan bentuk
/// key, atau ditolak: pesan merah dan keynya gak disimpen. Selain itu (belum
/// ada / lagi ngecek / offline) cuma penjelasan tempat nyimpennya.
class _KeyStatus extends StatelessWidget {
  const _KeyStatus({required this.status});

  final KeyStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final small = StabiloType.caption.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: c.ink2,
    );
    final label = StabiloType.caption.copyWith(fontWeight: FontWeight.w600);
    Widget error(String text) =>
        Text(text, style: label.copyWith(color: c.danger));
    return switch (status) {
      KeyStatus.idle => Text(
        context.l10n.settingsStoredSecurelyOnYourDeviceKeychain,
        style: small,
      ),
      KeyStatus.badFormat => error(
        context.l10n.settingsThatSNotAnOpenrouterApi,
      ),
      KeyStatus.refused => error(
        context.l10n.settingsOpenrouterRejectedTheKeySoIt,
      ),
      KeyStatus.checking || KeyStatus.rejected || KeyStatus.valid => Row(
        children: [
          Expanded(
            child: switch (status) {
              KeyStatus.checking => Text(
                context.l10n.settingsHangOnChecking,
                style: small,
              ),
              KeyStatus.valid => Row(
                spacing: 6,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(AppIcons.check, size: 11, color: c.onAccent),
                  ),
                  Text(
                    context.l10n.settingsYourKeyWorks,
                    style: label.copyWith(color: c.ink),
                  ),
                ],
              ),
              _ => error(context.l10n.settingsOpenrouterRejectedYourKey),
            },
          ),
          Text(context.l10n.settingsStoredSecurelyOnYourDevice, style: small),
        ],
      ),
    };
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, this.note, required this.child});

  final String label;

  /// String atau widget (teks ber-bold) di bawah isi.
  final Object? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Text(
          label,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        child,
        if (note case final Widget w)
          w
        else if (note case final String text)
          Text(text, style: _noteStyle(c)),
      ],
    );
  }
}

TextStyle _noteStyle(StabiloColors c) => StabiloType.caption.copyWith(
  fontSize: 12.5,
  height: 1.45,
  fontWeight: FontWeight.w400,
  color: c.ink2,
);

class _BackupNote extends StatelessWidget {
  const _BackupNote();

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Text.rich(
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
          TextSpan(text: context.l10n.settingsSoAddYoursAgainAfterRestoring),
        ],
      ),
      style: _noteStyle(c),
    );
  }
}

/// BackupCard (board 23 Pengaturan, Komponen 04): kapan terakhir backup +
/// tombol "Backup sekarang".
class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.last,
    required this.loaded,
    required this.onBackup,
    required this.onRestore,
  });

  final LastBackup? last;

  /// Status backup udah kebaca (biar gak sempet nongol "belum pernah").
  final bool loaded;
  final VoidCallback onBackup;
  final VoidCallback onRestore;

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
                    never ? AppIcons.alert : AppIcons.backup,
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
            icon: AppIcons.backup,
            onPressed: onBackup,
          ),
          AppButton.secondary(
            label: context.l10n.settingsRestoreFromBackup,
            icon: AppIcons.restore,
            height: 48,
            onPressed: onRestore,
          ),
        ],
      ),
    );
  }
}

/// RadioRow (board Komponen 04): titik kuning + nama + model ID mono.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Column(
        children: [
          for (final (i, m) in aiModels.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.menuLine),
            _ModelRow(
              model: m,
              selected: m.id == selected,
              onTap: () => onSelect(m.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: model.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: 10,
            ),
            child: Row(
              spacing: Space.s3,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.accent : null,
                    border: Border.all(
                      color: selected ? c.accentBorder : c.fieldLine,
                      width: Layout.outline,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.onAccent,
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            model.label,
                            style: StabiloType.label.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          if (model.id == defaultAiModel)
                            // Selebar teksnya, sebaris sama nama (board 23). Pake
                            // `alignment` di Container bakal bikin dia melebar
                            // sepenuh baris dan turun ke bawah nama.
                            Container(
                              height: 20,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.s2,
                              ),
                              decoration: BoxDecoration(
                                color: c.muted,
                                borderRadius: BorderRadius.circular(Radii.full),
                              ),
                              child: Align(
                                widthFactor: 1,
                                child: Text(
                                  context.l10n.settingsDefaultMostAccurate,
                                  style: StabiloType.micro.copyWith(
                                    height: 1,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        model.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.mono.copyWith(
                          fontSize: 12,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SettingsRow cache: jumlah paragraf + ukuran, tombol hapus warna danger.
class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.stats, required this.onClear});

  final AiCacheStats? stats;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final empty = stats == null || stats!.paragraphs == 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(Space.s4, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  context.l10n.settingsTranslationCache,
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  stats == null
                      ? ' '
                      : context.l10n.settingsParagraphs(
                          stats!.paragraphs,
                          fileSize(
                            stats!.bytes,
                            locale: context.l10n.localeName,
                          ),
                        ),
                  style: StabiloType.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          ),
          _RowButton(
            label: context.l10n.settingsClearCache,
            danger: true,
            onPressed: empty ? null : onClear,
          ),
        ],
      ),
    );
  }
}

/// Tombol pil di ujung kanan SettingsRow.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, Layout.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        backgroundColor: c.muted,
        foregroundColor: danger ? c.danger : c.ink,
        disabledForegroundColor: c.ink3,
        disabledBackgroundColor: c.muted,
        shape: const StadiumBorder(),
        textStyle: StabiloType.label.copyWith(fontSize: 14),
      ),
      child: Text(label),
    );
  }
}

/// SettingsRow katalog Gutenberg (#169): status sync + satu tombol yang
/// ikut keadaannya (Unduh / Perbarui / Batal / Coba lagi). Board belum ada,
/// ikut pola `_CacheRow`.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.stats,
    required this.state,
    required this.onSync,
    required this.onCancel,
  });

  /// Null = belum kebaca dari DB.
  final CatalogStats? stats;
  final CatalogSyncState state;
  final VoidCallback onSync;
  final VoidCallback onCancel;

  bool get _never => stats != null && stats!.count == 0;

  String _idleText(BuildContext context) {
    final s = stats;
    if (s == null) return ' ';
    if (s.count == 0) return context.l10n.settingsNotDownloadedMb;
    final when = s.syncedAt == null
        ? ''
        : context.l10n.settingsUpdated(
            date(s.syncedAt!, locale: context.l10n.localeName),
          );
    return context.l10n.settingsBooks(when, s.count);
  }

  String _subtitle(BuildContext context) => switch (state) {
    CatalogSyncIdle() || CatalogSyncUpToDate() => _idleText(context),
    CatalogSyncChecking() => context.l10n.settingsCheckingForUpdates,
    CatalogSyncDownloading(:final progress) =>
      progress < 0
          ? context.l10n.settingsDownloading
          : context.l10n.settingsDownloading2((progress * 100).round()),
    CatalogSyncImporting() => context.l10n.settingsPreparingCatalog,
    CatalogSyncFailed() => context.l10n.settingsFailedKeepingThePreviousCatalog,
  };

  /// Null = lagi kerja tanpa bisa dibatalin → spinner.
  (String, VoidCallback)? _button(BuildContext context) => switch (state) {
    CatalogSyncIdle() || CatalogSyncUpToDate() => (
      _never ? context.l10n.settingsDownload : context.l10n.settingsUpdate,
      onSync,
    ),
    CatalogSyncFailed() => (context.l10n.meaningTryAgain, onSync),
    CatalogSyncDownloading() => (context.l10n.dialogCancel, onCancel),
    CatalogSyncChecking() || CatalogSyncImporting() => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final button = _button(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(Space.s4, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  context.l10n.settingsGutenbergCatalog,
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  _subtitle(context),
                  style: StabiloType.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: state is CatalogSyncFailed ? c.danger : c.ink2,
                  ),
                ),
              ],
            ),
          ),
          if (button case (final label, final onPressed))
            _RowButton(
              label: label,
              onPressed: stats == null ? null : onPressed,
            )
          else
            SizedBox(
              width: Layout.touch,
              height: Layout.touch,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends ConsumerState<_LanguagePicker> {
  bool _saving = false;

  Future<void> _select(String language) async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).saveLocale(language);
    } catch (_) {
      if (mounted) showToast(context, context.l10n.languageSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLocaleProvider).value ?? 'id';
    return _Section(
      label: context.l10n.interfaceLanguage,
      note: context.l10n.interfaceLanguageNote,
      child: Wrap(
        spacing: Space.s2,
        children: [
          for (final option in const [
            ('id', 'Bahasa Indonesia'),
            ('en', 'English'),
          ])
            ChoiceChip(
              label: Text(option.$2),
              selected: language == option.$1,
              onSelected: _saving ? null : (_) => _select(option.$1),
            ),
        ],
      ),
    );
  }
}
