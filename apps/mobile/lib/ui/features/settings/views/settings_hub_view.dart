import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/catalog_sync_service.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../l10n/l10n.dart';
import '../../../../routing/router.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/quota.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../view_models/ai_quota_view_model.dart';
import 'ai_shared.dart';
import 'cache_sheet.dart';
import 'display_sheet.dart';
import 'settings_page.dart';

/// Pengaturan · 01 Ringkasan: akun + kuota AI, model AI, 4 tile. Satu layar,
/// tanpa scroll, gak ketutup bar tab melayang.
class SettingsHubView extends ConsumerWidget {
  const SettingsHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = l.localeName;
    final now = DateTime.now();

    final last = ref.watch(lastBackupProvider);
    final cloudAt = ref.watch(cloudBackupAtProvider).value;
    final backupAt = [last.value?.at, cloudAt].nonNulls.fold<DateTime?>(
      null,
      (a, b) => a == null || b.isAfter(a) ? b : a,
    );
    final backupLoaded = last.hasValue;

    final stats = ref.watch(catalogStatsProvider).value;
    final sync = ref.watch(catalogSyncProvider);
    final cache = ref.watch(aiCacheStatsProvider).value;
    final theme =
        ref.watch(readerPrefsProvider).value?.theme ?? AppTheme.system;
    final lang = ref.watch(appLocaleProvider).value ?? 'id';

    final catalogStatus = switch (sync) {
      CatalogSyncDownloading(:final progress) when progress >= 0 =>
        l.settingsHubCatalogDownloading((progress * 100).round()),
      CatalogSyncDownloading() ||
      CatalogSyncChecking() ||
      CatalogSyncImporting() => l.settingsHubCatalogWorking,
      CatalogSyncFailed() => l.settingsHubCatalogFailed,
      _ =>
        stats == null
            ? ' '
            : stats.count == 0
            ? l.settingsHubCatalogNever
            : l.settingsHubCatalogDone,
    };

    final tiles = [
      SettingsTile(
        icon: AppIcons.backup,
        name: l.settingsHubTileBackup,
        attention: backupLoaded && backupAt == null,
        status: !backupLoaded
            ? ' '
            : backupAt == null
            ? l.settingsHubBackupNever
            : lastSeen(backupAt, now, locale: locale),
        onTap: () => context.push(Routes.settingsBackup),
      ),
      SettingsTile(
        icon: HugeIcons.strokeRoundedBook02,
        name: l.settingsHubTileCatalog,
        status: catalogStatus,
        onTap: () => context.push(Routes.settingsCatalog),
      ),
      SettingsTile(
        icon: HugeIcons.strokeRoundedHardDrive,
        name: l.settingsHubTileCache,
        status: cache == null
            ? ' '
            : cache.paragraphs == 0
            ? l.settingsHubCacheEmpty
            : l.settingsHubCacheUsed(fileSize(cache.bytes, locale: locale)),
        onTap: () => showCacheSheet(context),
      ),
      SettingsTile(
        icon: HugeIcons.strokeRoundedPaintBoard,
        name: l.settingsHubTileDisplay,
        status: l.settingsHubDisplayStatus(switch (theme) {
          AppTheme.system => l.aaSystem,
          AppTheme.light => l.aaLight,
          AppTheme.dark => l.aaDark,
        }, lang.toUpperCase()),
        onTap: () => showDisplaySheet(context),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
              child: SizedBox(
                height: Layout.topBar,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text(l.settingsSettings, style: StabiloType.titleLg),
                  ),
                ),
              ),
            ),
            Expanded(
              // ponytail: scroll only as a safety net for tiny screens / big
              // text scale; at board size everything fits.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Layout.margin,
                  0,
                  Layout.margin,
                  SettingsPage.navClearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s3,
                  children: [
                    const _AccountCard(),
                    const _ModelCard(),
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: Text(
                        l.settingsHubMoreSection.toUpperCase(),
                        style: StabiloType.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.65,
                          color: context.stabilo.ink2,
                        ),
                      ),
                    ),
                    IntrinsicHeight(
                      child: Row(
                        spacing: Space.s3,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tiles[0]),
                          Expanded(child: tiles[1]),
                        ],
                      ),
                    ),
                    IntrinsicHeight(
                      child: Row(
                        spacing: Space.s3,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tiles[2]),
                          Expanded(child: tiles[3]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu bergaris tipis yang dipakai akun, model AI, dan tile.
class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.child,
    required this.radius,
    this.padding = const EdgeInsets.all(Space.s4),
    this.onTap,
    this.label,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: c.menuLine),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      child: Material(
        color: c.sheet,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider).value;
    final signedIn = auth?.status == AuthStatus.signedIn;
    final user = auth?.user;
    final name = user?.name ?? '';
    final image = user?.image;
    final source = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    // Kuota dicek paling sering sejam sekali (cache provider).
    if (signedIn) {
      Future.microtask(() => ref.read(aiQuotaProvider.notifier).refresh());
    }
    final meter = signedIn ? quotaMeterData(ref, source: source) : null;

    return _HubCard(
      radius: Radii.lg,
      onTap: () => context.push(Routes.settingsAccount),
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
                  shape: BoxShape.circle,
                  border: Border.all(color: c.outline, width: Layout.outline),
                ),
                child: CircleAvatar(
                  backgroundColor: c.accent,
                  foregroundImage: image == null ? null : NetworkImage(image),
                  child: signedIn && name.isNotEmpty
                      ? Text(
                          name.characters.first.toUpperCase(),
                          style: StabiloType.titleSm.copyWith(
                            color: c.onAccent,
                          ),
                        )
                      : AppIcon(AppIcons.user, size: 22, color: c.onAccent),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      signedIn ? name : l.settingsHubSignedOut,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.label.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      signedIn
                          ? (user?.email ?? '')
                          : l.settingsHubSignedOutNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevron, size: 18, color: c.ink3),
            ],
          ),
          if (meter != null) ...[
            Divider(height: 1, thickness: 1, color: c.menuLine),
            _QuotaRow(data: meter),
          ],
        ],
      ),
    );
  }
}

/// Cincin kuota + teks; state tanpa angka (memuat, gagal, key sendiri,
/// dicabut) ikut teks yang sama dengan meter kuota lama.
class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.data});

  final QuotaMeterData data;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final locale = l.localeName;
    final small = StabiloType.caption.copyWith(fontSize: 13, color: c.ink2);
    final big = StabiloType.label.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: c.ink,
    );

    final (
      Widget ring,
      String title,
      String value,
      String note,
    ) = switch (data) {
      final QuotaMeterValue v => (
        _Ring(
          fraction: v.percent / 100,
          color: v.exhausted
              ? c.danger
              : v.low
              ? c.pink
              : c.ink,
          label: '${v.percent}%',
        ),
        l.quotaToday,
        v.exhausted ? l.quotaUsedUp : l.quotaTapsLeft(v.tapsLeft),
        l.settingsHubQuotaReset(clockTime(v.resetsAt, locale: locale), () {
          final left = untilReset(v.now, v.resetsAt);
          return l.quotaCountdown(left.hours, left.minutes);
        }()),
      ),
      QuotaMeterOwnKey() => (
        _Ring(fraction: 0, color: c.ink, icon: AppIcons.key),
        l.quotaSource,
        l.quotaOwnKey,
        l.quotaOwnKeyNote,
      ),
      QuotaMeterRevoked() => (
        _Ring(fraction: 0, color: c.danger, icon: AppIcons.lock),
        l.quotaFree,
        l.quotaRevoked,
        l.quotaRevokedNote,
      ),
      QuotaMeterFailed() => (
        _Ring(fraction: 0, color: c.ink, label: '—'),
        l.quotaToday,
        '—',
        l.quotaLoadFailed,
      ),
      QuotaMeterLoading() => (
        _Ring(fraction: 0, color: c.ink, label: '…'),
        l.quotaToday,
        ' ',
        l.quotaLoading,
      ),
    };

    return Row(
      spacing: Space.s4,
      children: [
        ring,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: small.copyWith(fontWeight: FontWeight.w500)),
              Text(value, style: big),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.fraction,
    required this.color,
    this.label,
    this.icon,
  });

  static const _size = 68.0;
  static const _stroke = 7.0;

  final double fraction;
  final Color color;
  final String? label;
  final List<List<dynamic>>? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: fraction.clamp(0, 1),
          track: c.track,
          color: color,
        ),
        child: Center(
          child: icon != null
              ? AppIcon(icon!, size: 24, color: color)
              : Text(
                  label ?? '',
                  style: StabiloType.label.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.color,
  });

  final double fraction;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_Ring._stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _Ring._stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.color != color;
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final source = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    final id = ref.watch(aiModelProvider).value ?? defaultAiModel;
    final label = aiModels.where((m) => m.id == id).firstOrNull?.label ?? id;

    Future<void> change() async {
      final picked = await showModelPickerSheet(
        context,
        source: source,
        current: id,
        onUseOwnKey: () {
          ref.read(ownKeyRequestProvider.notifier).request();
          context.push(Routes.settingsAi);
        },
      );
      if (picked != null) {
        await ref.read(settingsRepositoryProvider).saveModel(picked);
      }
    }

    return _HubCard(
      radius: Radii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: Space.s3,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.muted,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    HugeIcons.strokeRoundedSparkles,
                    size: 18,
                    color: c.ink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      source == AiSource.subsidy
                          ? l.settingsHubModelFree
                          : l.settingsHubModelOwn,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.label.copyWith(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      id == defaultAiModel ? l.settingsHubModelDefault(id) : id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.mono.copyWith(
                        fontSize: 11.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: _PillButton(
                  label: l.settingsHubChangeModel,
                  onTap: change,
                ),
              ),
              Expanded(
                child: _PillButton(
                  label: l.settingsHubManageAi,
                  trailing: AppIcons.chevron,
                  onTap: () => context.push(Routes.settingsAi),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.trailing});

  final String label;
  final VoidCallback onTap;
  final List<List<dynamic>>? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: Material(
        color: c.muted,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.label.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                if (trailing != null)
                  AppIcon(trailing!, size: 16, color: c.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tile ringkasan (board "Tile ringkasan"): ikon + nama + tombol bulat "›",
/// satu baris status di bawah. [attention] = titik pink di sebelah nama.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.name,
    required this.status,
    required this.onTap,
    this.attention = false,
  });

  final List<List<dynamic>> icon;
  final String name;
  final String status;
  final VoidCallback onTap;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return _HubCard(
      radius: Radii.menu,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: onTap,
      label: '$name, ${status.trim()}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 6,
              children: [
                AppIcon(icon, size: 15, color: c.ink2),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                ),
                if (attention)
                  Container(
                    key: const ValueKey('attention-dot'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.pink,
                      shape: BoxShape.circle,
                    ),
                  ),
                const Spacer(),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(AppIcons.chevron, size: 14, color: c.ink),
                  ),
                ),
              ],
            ),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.label.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
