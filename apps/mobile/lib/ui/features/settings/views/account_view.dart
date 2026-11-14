import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/services/backend_client.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/quota.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_dialogs.dart';
import '../../auth/views/auth_toast.dart';
import '../../auth/views/login_view.dart';
import '../view_models/ai_quota_view_model.dart';
import 'ai_source_section.dart';
import 'settings_page.dart';

/// Pengaturan → Akun (board "Pengaturan · 02 Akun"): profil, kartu kuota AI,
/// Keluar dan Hapus akun.
class AccountView extends ConsumerWidget {
  const AccountView({super.key});

  // Ukuran khusus board Akun.
  static const _avatar = 72.0;
  static const _ring = 84.0;
  static const _ringStroke = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final user = ref.watch(authControllerProvider).value?.user;
    final viaEmail = ref.watch(devLoginProvider);
    final name = user?.name ?? '';
    final image = user?.image;
    return SettingsPage(
      title: l.settingsAccount,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.s1),
          child: Column(
            spacing: Space.s1,
            children: [
              Semantics(
                label: l.settingsAccountPhoto,
                child: Container(
                  width: _avatar,
                  height: _avatar,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.muted,
                    border: Border.all(color: c.outline, width: Layout.outline),
                    image: image == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(image),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: image == null
                      ? Center(
                          child: AppIcon(
                            AppIcons.user,
                            size: 40,
                            color: c.ink2,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: Space.s2),
              Text(
                name,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.titleLg.copyWith(color: c.ink),
              ),
              if (user?.email case final email?)
                Text(
                  email,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: StabiloType.caption.copyWith(color: c.ink2),
                ),
              Text(
                viaEmail ? l.authViaEmail : l.authViaGoogle,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.ink2,
                ),
              ),
            ],
          ),
        ),
        const _QuotaCard(),
        _Card(
          children: [
            _ActionRow(
              icon: AppIcons.logout,
              title: l.authSignOut,
              note: l.settingsAccountSignOutNote,
              onTap: () => _signOut(context, ref),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: Space.s4,
              endIndent: Space.s4,
              color: c.menuLine,
            ),
            _ActionRow(
              icon: AppIcons.delete,
              title: l.authDeleteAccount,
              note: l.settingsAccountDeleteNote,
              color: c.danger,
              onTap: () => _delete(context, ref, user?.email ?? ''),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await showSignOutDialog(context)) return;
    if (!context.mounted) return;
    final message = context.l10n.authToastSignedOut;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    if (messenger.mounted && context.mounted) {
      // Muncul di layar Masuk (tanpa bottom bar).
      showAuthToast(
        context,
        message,
        tone: AuthToastTone.info,
        icon: AppIcons.logout,
        overNav: false,
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final l = context.l10n;
    var failed = false;
    final deleted = await showDeleteAccountDialog(
      context,
      email: email,
      onConfirm: () async {
        try {
          await ref.read(authControllerProvider.notifier).deleteAccount();
          return true;
        } on BackendException {
          failed = true;
          return false;
        }
      },
    );
    if (!context.mounted) return;
    if (deleted) {
      showAuthToast(
        context,
        l.authToastDeleted,
        tone: AuthToastTone.info,
        icon: AppIcons.delete,
        overNav: false,
      );
    } else if (failed) {
      showAuthToast(
        context,
        l.authToastDeleteFailed,
        tone: AuthToastTone.failure,
        actionLabel: l.authTryAgain,
        onAction: () => _delete(context, ref, email),
      );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.menuLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.note,
    required this.onTap,
    this.color,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String note;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final fg = color ?? c.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3 + 2,
        ),
        child: Row(
          spacing: Space.s3,
          children: [
            AppIcon(icon, color: fg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: StabiloType.label.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  Text(
                    note,
                    style: StabiloType.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(AppIcons.chevron, size: 16, color: c.ink3),
          ],
        ),
      ),
    );
  }
}

/// Kartu kuota: cincin + sisa tap + dua kartu mini. State selain "ada data"
/// (loading, gagal, key sendiri, dicabut) jatuh ke [QuotaMeter].
class _QuotaCard extends ConsumerStatefulWidget {
  const _QuotaCard();

  @override
  ConsumerState<_QuotaCard> createState() => _QuotaCardState();
}

class _QuotaCardState extends ConsumerState<_QuotaCard> {
  @override
  void initState() {
    super.initState();
    // Buka halaman = cek kuota, paling sering sejam sekali (cache provider).
    Future.microtask(() {
      if (mounted) ref.read(aiQuotaProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final locale = l.localeName;
    final source = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    final data = quotaMeterData(ref, source: source);
    final usage = ref.watch(aiQuotaProvider).value?.usage;
    const padding = EdgeInsets.all(Space.s4);
    if (data is! QuotaMeterValue || usage == null) {
      return _Card(
        padding: padding,
        children: [QuotaMeter(data: data)],
      );
    }
    final countdown = untilReset(data.now, data.resetsAt);
    final used = (usage.usedTodayUsd / estimatedTapCostUsd).round();
    final tone = data.exhausted ? c.danger : c.ink;
    Widget mini(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 10),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: StabiloType.caption.copyWith(
                fontWeight: FontWeight.w500,
                color: c.ink2,
              ),
            ),
            Text(
              value,
              style: StabiloType.label.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
    return _Card(
      padding: padding,
      children: [
        Semantics(
          container: true,
          child: Row(
            spacing: Space.s4,
            children: [
              SizedBox.square(
                dimension: AccountView._ring,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: data.percent / 100,
                        strokeWidth: AccountView._ringStroke,
                        strokeCap: StrokeCap.round,
                        backgroundColor: c.track,
                        color: tone,
                      ),
                    ),
                    Text(
                      '${data.percent}%',
                      style: StabiloType.titleLg.copyWith(color: tone),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.quotaToday,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      l.quotaTapsLeft(data.tapsLeft),
                      style: StabiloType.titleSm.copyWith(color: tone),
                    ),
                    Text(
                      l.quotaResetAtIn(
                        clockTime(data.resetsAt, locale: locale),
                        l.quotaCountdown(countdown.hours, countdown.minutes),
                      ),
                      style: StabiloType.caption.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s3 + 2),
        Row(
          spacing: Space.s2,
          children: [
            mini(l.settingsAccountUsedToday, l.settingsAccountUsedValue(used)),
            mini(l.settingsAccountDaily, l.settingsAccountDailyValue),
          ],
        ),
      ],
    );
  }
}
