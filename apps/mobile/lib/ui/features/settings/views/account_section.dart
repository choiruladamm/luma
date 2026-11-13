import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/services/auth_service.dart';
import '../../../../data/services/backend_client.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_dialogs.dart';
import '../../auth/views/auth_toast.dart';
import '../../auth/views/login_view.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Text(
          l.settingsAccount,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        _ExLibris(user: user, via: viaEmail ? l.authViaEmail : l.authViaGoogle),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: AppButton.secondary(
                label: l.authSignOut,
                icon: AppIcons.logout,
                onPressed: () => _signOut(context, ref),
              ),
            ),
            Expanded(
              child: AppButton.secondary(
                label: l.authDeleteAccount,
                icon: AppIcons.delete,
                destructive: true,
                onPressed: () => _delete(context, ref, user?.email ?? ''),
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
      showAuthToast(context, message, tone: AuthToastTone.info);
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
      showAuthToast(context, l.authToastDeleted, tone: AuthToastTone.info);
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

/// Pelat Ex libris: foto, nama pakai font baca, email.
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
    return Container(
      padding: const EdgeInsets.all(Space.s5),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
        border: Border.all(color: c.ink, width: 1.5),
      ),
      child: Row(
        spacing: Space.s4,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: c.accent,
            foregroundImage: image == null ? null : NetworkImage(image),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: StabiloType.titleMd.copyWith(color: c.onAccent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  l.authExLibris,
                  style: StabiloType.micro.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: c.ink3,
                  ),
                ),
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: StabiloType.reading.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (user?.email case final email?)
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
                Text(via, style: StabiloType.caption.copyWith(color: c.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
