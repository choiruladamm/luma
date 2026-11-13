import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/widgets/toast.dart';

/// Warna tab toast akun (board Akun 13): kuning berhasil, abu info, pink gagal.
enum AuthToastTone { success, info, failure }

/// Toast akun: kartu dengan tab warna di kiri. 4 detik; gagal 6 detik.
void showAuthToast(
  BuildContext context,
  String message, {
  AuthToastTone tone = AuthToastTone.success,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final c = context.stabilo;
  final color = switch (tone) {
    AuthToastTone.success => c.accent,
    AuthToastTone.info => c.muted,
    AuthToastTone.failure => c.pink,
  };
  showToast(
    context,
    message,
    leading: ExcludeSemantics(
      child: Container(
        width: 6,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ),
    actionLabel: actionLabel,
    onAction: onAction,
    duration: Duration(seconds: tone == AuthToastTone.failure ? 6 : 4),
  );
}
