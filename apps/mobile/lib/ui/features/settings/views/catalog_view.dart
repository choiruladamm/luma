import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/services/catalog_sync_service.dart';
import '../../../../l10n/l10n.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/toast.dart';
import 'settings_page.dart';

/// Pengaturan · Katalog buku (board 08 Katalog): kartu status + tombol yang
/// ikut keadaan (Unduh / Batal / Perbarui / Coba lagi), progres pas ngunduh,
/// dan penjelasan "Buat apa?".
class CatalogView extends ConsumerWidget {
  const CatalogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(catalogSyncProvider, (_, state) {
      if (state is! CatalogSyncUpToDate) return;
      showToast(context, context.l10n.settingsCatalogUpToDate);
      ref.read(catalogSyncProvider.notifier).dismiss();
    });
    final sync = ref.read(catalogSyncProvider.notifier);
    final state = ref.watch(catalogSyncProvider);
    final c = context.stabilo;
    final busy =
        state is CatalogSyncDownloading ||
        state is CatalogSyncChecking ||
        state is CatalogSyncImporting;
    return SettingsPage(
      title: context.l10n.settingsCatalogTitle,
      children: [
        _CatalogCard(
          stats: ref.watch(catalogStatsProvider).value,
          state: state,
          onSync: () => sync.sync(force: true),
          onCancel: sync.cancel,
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text(
            context.l10n.settingsCatalogWhy,
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: c.ink2,
            ),
          ),
        ),
        _Reason(
          icon: HugeIcons.strokeRoundedSearch01,
          title: context.l10n.settingsCatalogWhySearch,
          body: context.l10n.settingsCatalogWhySearchBody,
        ),
        _Reason(
          icon: HugeIcons.strokeRoundedBook02,
          title: context.l10n.settingsCatalogWhyBooks,
          body: context.l10n.settingsCatalogWhyBooksBody,
        ),
        _Reason(
          icon: HugeIcons.strokeRoundedCalendar03,
          title: context.l10n.settingsCatalogWhyWeekly,
          body: context.l10n.settingsCatalogWhyWeeklyBody,
        ),
        if (busy)
          Text(
            context.l10n.settingsCatalogBackgroundNote,
            style: _bodyStyle(c).copyWith(color: c.ink3),
          ),
      ],
    );
  }
}

TextStyle _bodyStyle(StabiloColors c) => StabiloType.caption.copyWith(
  fontSize: 12.5,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: c.ink2,
);

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
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
    if (s.count == 0) return context.l10n.settingsCatalogNotDownloaded;
    final at = s.syncedAt;
    return at == null
        ? context.l10n.settingsCatalogBooks(s.count)
        : context.l10n.settingsCatalogBooksUpdated(
            s.count,
            date(at, locale: context.l10n.localeName),
          );
  }

  String _subtitle(BuildContext context) => switch (state) {
    CatalogSyncIdle() || CatalogSyncUpToDate() => _idleText(context),
    CatalogSyncChecking() => context.l10n.settingsCatalogChecking,
    CatalogSyncDownloading() => context.l10n.settingsCatalogDownloading,
    CatalogSyncImporting() => context.l10n.settingsCatalogPreparing,
    CatalogSyncFailed() => context.l10n.settingsCatalogFailed,
  };

  /// Null = lagi kerja tanpa bisa dibatalin → spinner.
  (String, VoidCallback)? _button(BuildContext context) => switch (state) {
    CatalogSyncIdle() || CatalogSyncUpToDate() => (
      _never
          ? context.l10n.settingsCatalogDownload
          : context.l10n.settingsCatalogUpdate,
      onSync,
    ),
    CatalogSyncFailed() => (context.l10n.settingsCatalogRetry, onSync),
    CatalogSyncDownloading() => (context.l10n.settingsCatalogCancel, onCancel),
    CatalogSyncChecking() || CatalogSyncImporting() => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final button = _button(context);
    final downloading = state is CatalogSyncDownloading
        ? state as CatalogSyncDownloading
        : null;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.menuLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Row(
            spacing: Space.s3,
            children: [
              _Tile(HugeIcons.strokeRoundedBook02, size: 40, iconSize: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      context.l10n.settingsCatalogCardTitle,
                      style: StabiloType.label.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      _subtitle(context),
                      style: _bodyStyle(c).copyWith(
                        color: state is CatalogSyncFailed ? c.danger : c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              if (button case (final label, final onPressed))
                TextButton(
                  onPressed: stats == null ? null : onPressed,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: c.muted,
                    foregroundColor: c.ink,
                    disabledForegroundColor: c.ink3,
                    disabledBackgroundColor: c.muted,
                    shape: const StadiumBorder(),
                    textStyle: StabiloType.label.copyWith(fontSize: 14),
                  ),
                  child: Text(label),
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
          if (downloading != null) ...[
            // ponytail: board juga nunjukin "2,4 dari 5,6 MB · ± 20 detik
            // lagi"; sync cuma ngasih fraksi 0–1, jadi cuma persen + bar.
            if (downloading.progress >= 0)
              Text(
                '${(downloading.progress * 100).round()}%',
                style: StabiloType.display.copyWith(
                  fontSize: 40,
                  height: 1,
                  letterSpacing: -1.6,
                  color: c.ink,
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // Null = server gak kasih panjang → bar berjalan.
                value: downloading.progress < 0 ? null : downloading.progress,
                minHeight: 8,
                color: c.progressFill,
                backgroundColor: c.track,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, {required this.size, required this.iconSize});

  final List<List<dynamic>> icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
      child: Center(
        child: AppIcon(icon, size: iconSize, color: c.ink),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.icon, required this.title, required this.body});

  final List<List<dynamic>> icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s3,
      children: [
        _Tile(icon, size: 34, iconSize: 17),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text(
                title,
                style: StabiloType.label.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(body, style: _bodyStyle(c)),
            ],
          ),
        ),
      ],
    );
  }
}
