import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Dialog konfirmasi buat aksi yang gak bisa dibalikin (board Komponen 04).
/// `true` = dikonfirmasi; ditutup / Batal = `false`.
///
/// Dengan [icon] ukurannya ngikut board 22 Konfirmasi hapus: selebar layar
/// dikurangi margin 32, sudut 26, judul 22, tombol 50.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Batal',
  bool destructive = true,

  /// Tile ikon di atas judul (board Konfirmasi hapus).
  List<List<dynamic>>? icon,

  /// Ada = tombol konfirmasi jadi spinner sampai Future-nya selesai, Batal
  /// mati, dan dialog gak nutup sendiri: pemanggil yang nutup (mis. ikut
  /// nutup sheet di bawahnya) begitu hasilnya ada.
  Future<void> Function()? onConfirm,
}) async {
  var loading = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.stabilo;
        void close(bool v) => Navigator.of(context).pop(v);
        Future<void> confirm() async {
          if (onConfirm == null) return close(true);
          setState(() => loading = true);
          await onConfirm();
        }

        final tall = icon != null;
        final buttonHeight = tall ? 50.0 : 48.0;
        return PopScope(
          canPop: !loading,
          child: Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: tall ? Space.s8 : Space.s10,
              vertical: Space.s6,
            ),
            shape: tall
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.dialogIcon),
                  )
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tall ? double.infinity : 300,
              ),
              child: Padding(
                padding: tall
                    ? const EdgeInsets.fromLTRB(
                        Space.s5,
                        Space.s6,
                        Space.s5,
                        Space.s4 + Space.s1 / 2,
                      )
                    : const EdgeInsets.all(Space.s5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: tall ? 10 : Space.s2,
                  children: [
                    if (icon != null)
                      // Ukuran sendiri, nempel kiri: di Column(stretch) Container
                      // tanpa Align ikut melebar ke lebar dialog.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Space.s1),
                          child: Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: destructive ? c.dangerSoft : c.muted,
                              borderRadius: BorderRadius.circular(Radii.field),
                            ),
                            child: AppIcon(
                              icon,
                              size: 24,
                              color: destructive ? c.danger : c.ink,
                            ),
                          ),
                        ),
                      ),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: tall
                            ? StabiloType.titleSm.copyWith(
                                fontSize: 22,
                                height: 1.2,
                                letterSpacing: -0.02 * 22,
                              )
                            : StabiloType.titleSm,
                      ),
                    ),
                    Text(
                      message,
                      style: StabiloType.body.copyWith(
                        fontSize: tall ? 15 : null,
                        height: tall ? 1.5 : null,
                        color: c.ink2,
                      ),
                    ),
                    const SizedBox(height: Space.s1),
                    Row(
                      spacing: Space.s2,
                      children: [
                        Expanded(
                          child: AppButton.secondary(
                            label: cancelLabel,
                            height: buttonHeight,
                            onPressed: loading ? null : () => close(false),
                          ),
                        ),
                        Expanded(
                          child: destructive
                              ? AppButton.danger(
                                  label: confirmLabel,
                                  height: buttonHeight,
                                  loading: loading,
                                  onPressed: confirm,
                                )
                              : AppButton.primary(
                                  label: confirmLabel,
                                  height: buttonHeight,
                                  loading: loading,
                                  onPressed: confirm,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  return ok ?? false;
}
