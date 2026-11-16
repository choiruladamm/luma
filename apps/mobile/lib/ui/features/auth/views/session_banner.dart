import 'package:flutter/material.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

/// Board Akun 12: strip abu dengan pita pembatas pink di atas kartu Lanjut
/// baca. App tetap bisa dipakai; × nutup sampai app dibuka lagi.
class SessionExpiredBanner extends StatelessWidget {
  const SessionExpiredBanner({
    super.key,
    required this.onSignIn,
    required this.onClose,
  });

  final VoidCallback onSignIn;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: Space.s5,
            child: ExcludeSemantics(
              child: Container(width: 14, height: 22, color: c.pink),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              28,
              Space.s2,
              Space.s4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s3,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.s1,
                    children: [
                      Text(
                        l.authSessionExpiredTitle,
                        style: StabiloType.titleXs.copyWith(color: c.ink),
                      ),
                      Text(
                        l.authSessionExpiredBody,
                        style: StabiloType.caption.copyWith(color: c.ink2),
                      ),
                      const SizedBox(height: Space.s2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton.primary(
                          label: l.authSignInAgain,
                          height: 40,
                          pill: true,
                          onPressed: onSignIn,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l.authCloseBanner,
                  onPressed: onClose,
                  icon: AppIcon(AppIcons.close, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
