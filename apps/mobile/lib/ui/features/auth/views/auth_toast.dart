import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/toast.dart';

/// Warna tab toast akun (board Akun 13): kuning berhasil, abu info, pink gagal.
enum AuthToastTone { success, info, failure }

/// Toast akun: kartu putih bergaris, tab warna + [icon] di kiri. 4 detik;
/// gagal 6 detik. Kiri-kanan 16; 12 di atas bottom bar, atau 34 dari bawah
/// layar kalau gak ada bar. [overNav]: lihat [toastMargin].
void showAuthToast(
  BuildContext context,
  String message, {
  AuthToastTone tone = AuthToastTone.success,
  List<List<dynamic>>? icon,
  bool? overNav,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _AuthToast(
          message: message,
          tone: tone,
          icon: icon,
          actionLabel: actionLabel,
          onAction: () {
            messenger.hideCurrentSnackBar();
            onAction?.call();
          },
        ),
        duration: Duration(seconds: tone == AuthToastTone.failure ? 6 : 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: toastMargin(
          context,
          overNav: overNav,
          side: Space.s4,
          offBar: 34,
        ),
      ),
    );
}

class _AuthToast extends StatelessWidget {
  const _AuthToast({
    required this.message,
    required this.tone,
    required this.onAction,
    this.icon,
    this.actionLabel,
  });

  final String message;
  final AuthToastTone tone;
  final List<List<dynamic>>? icon;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (tab, fallback) = switch (tone) {
      AuthToastTone.success => (c.accent, AppIcons.checkCircle),
      AuthToastTone.info => (c.muted, AppIcons.info),
      AuthToastTone.failure => (c.pink, AppIcons.alert),
    };
    final line = BorderSide(color: c.outline, width: Layout.outline);
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Space.s4),
        boxShadow: Elevation.press(c, Theme.of(context).brightness),
      ),
      // Garis di atas isi: kalau di `decoration`, tab warna yang di-clip
      // nimpa garis di sudut kiri.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Space.s4),
        border: Border.fromBorderSide(line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 42,
              decoration: BoxDecoration(
                color: tab,
                border: Border(right: line),
              ),
              child: Center(
                child: AppIcon(
                  icon ?? fallback,
                  size: 18,
                  strokeWidth: 1.8,
                  color: switch (tone) {
                    AuthToastTone.success => c.onAccent,
                    AuthToastTone.failure => c.onPink,
                    AuthToastTone.info => c.ink,
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: StabiloType.label.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (actionLabel != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onAction,
                        child: Text(
                          actionLabel!,
                          style: StabiloType.label.copyWith(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                            decoration: TextDecoration.underline,
                          ),
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
