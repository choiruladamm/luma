import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Confirmation dialog for irreversible actions (board Komponen 04).
/// `true` = confirmed; dismissed / Batal = `false`.
///
/// With [icon] the size follows board 22 Konfirmasi hapus: screen width minus
/// 32 margin, corner 26, title 22, button 50.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = true,

  /// Icon tile above the title (board Konfirmasi hapus).
  List<List<dynamic>>? icon,

  /// When set, the confirm button becomes a spinner until the Future completes,
  /// Batal is disabled, and the dialog doesn't close itself: the caller closes
  /// it (e.g. along with the sheet below) once the result is in.
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
                      // Own size, pinned left: in a Column(stretch) a Container without Align
                      // stretches to the dialog width.
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
                            label: cancelLabel ?? context.l10n.dialogCancel,
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
