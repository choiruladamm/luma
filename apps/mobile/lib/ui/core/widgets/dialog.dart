import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Dialog konfirmasi buat aksi yang gak bisa dibalikin (board Komponen 04).
/// `true` = dikonfirmasi; ditutup / Batal = `false`.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Batal',
  bool destructive = true,

  /// Tile ikon di atas judul (board Konfirmasi hapus).
  List<List<dynamic>>? icon,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.stabilo;
      void close(bool v) => Navigator.of(context).pop(v);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.all(Space.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s2,
              children: [
                if (icon != null)
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(bottom: Space.s1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: destructive ? c.dangerSoft : c.muted,
                      borderRadius: BorderRadius.circular(Radii.sm + Space.s1),
                    ),
                    child: AppIcon(
                      icon,
                      size: 24,
                      color: destructive ? c.danger : c.ink,
                    ),
                  ),
                Semantics(
                  header: true,
                  child: Text(title, style: StabiloType.titleSm),
                ),
                Text(message, style: StabiloType.body.copyWith(color: c.ink2)),
                const SizedBox(height: Space.s1),
                Row(
                  spacing: Space.s2,
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: cancelLabel,
                        height: 48,
                        onPressed: () => close(false),
                      ),
                    ),
                    Expanded(
                      child: destructive
                          ? AppButton.danger(
                              label: confirmLabel,
                              onPressed: () => close(true),
                            )
                          : AppButton.primary(
                              label: confirmLabel,
                              height: 48,
                              onPressed: () => close(true),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}
