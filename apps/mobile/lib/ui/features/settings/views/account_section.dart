import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/auth_service.dart';
import '../../../../data/services/backend_client.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_dialogs.dart';
import '../../auth/views/auth_toast.dart';
import '../../auth/views/login_view.dart';
import 'ai_source_section.dart';

/// Pengaturan → Akun (board Akun 08): pelat Ex libris, Keluar, Hapus akun.
/// Slot "Sisa kuota AI" dan "Backup terakhir" disembunyiin sampai datanya ada.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider).value;
    if (auth == null || auth.status == AuthStatus.signedOut) {
      return const SizedBox.shrink();
    }
    final user = auth.user;
    final viaEmail = ref.watch(devLoginProvider);
    final cloudAt = ref.watch(cloudBackupAtProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        Text(
          l.settingsAccount,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        _ExLibris(user: user, via: viaEmail ? l.authViaEmail : l.authViaGoogle),
        if (cloudAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l.settingsLastBackup,
                  style: StabiloType.label.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    color: c.ink2,
                  ),
                ),
                Text(
                  lastSeen(cloudAt, DateTime.now(), locale: l.localeName),
                  style: StabiloType.label.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: AppButton.outline(
                label: l.authSignOut,
                icon: AppIcons.logout,
                height: 48,
                onPressed: () => _signOut(context, ref),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _delete(context, ref, user?.email ?? ''),
                icon: AppIcon(AppIcons.delete, size: 18, color: c.danger),
                label: Text(l.authDeleteAccount),
                style: TextButton.styleFrom(
                  foregroundColor: c.danger,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  textStyle: StabiloType.label.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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

/// Pelat Ex libris (board Akun 08 + Kuota AI 02): kartu bergaris, bingkai
/// putus-putus di dalam, foto + nama font baca di tengah, meter kuota di
/// bawah garis putus-putus.
class _ExLibris extends StatelessWidget {
  const _ExLibris({required this.user, required this.via});

  final AuthUser? user;
  final String via;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final name = user?.name ?? '';
    final image = user?.image;
    final dash = c.fieldLine;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.outline, width: Layout.outline),
        boxShadow: Elevation.press(c, Theme.of(context).brightness),
      ),
      child: CustomPaint(
        painter: _Dashed(color: dash, radius: 15),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Column(
                spacing: 4,
                children: [
                  Text(
                    l.authExLibris,
                    style: StabiloType.micro.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 11 * 0.28,
                      color: c.ink2,
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.outline,
                        width: Layout.outline,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: c.accent,
                      foregroundImage: image == null
                          ? null
                          : NetworkImage(image),
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: StabiloType.titleSm.copyWith(color: c.onAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.reading.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (user?.email case final email?)
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13,
                        color: c.ink2,
                      ),
                    ),
                  Text(
                    via,
                    style: StabiloType.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
              CustomPaint(
                painter: _Dashed(color: dash),
                child: const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: AccountQuotaMeter(bare: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Garis putus-putus 1,5: bingkai [radius] di sekeliling, atau (null) garis
/// atas doang.
class _Dashed extends CustomPainter {
  const _Dashed({required this.color, this.radius});

  final Color color;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (radius case final r?) {
      path.addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(r),
        ),
      );
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0);
    }
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.radius != radius;
}
