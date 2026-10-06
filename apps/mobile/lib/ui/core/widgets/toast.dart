import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Toast (board Komponen 04), ilang sendiri 2,5 detik.
///
/// Tanpa [actionLabel]: pill di tengah + centang ("Udah disalin, tinggal
/// paste"). Dengan action: bar lebar + tombol kecil ("Sip! ... udah masuk
/// rak" · Baca).
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: actionLabel == null
            ? Center(child: _Toast.pill(message))
            : _Toast.bar(
                message,
                actionLabel: actionLabel,
                onAction: () {
                  messenger.hideCurrentSnackBar();
                  onAction?.call();
                },
              ),
        duration: Motion.toast,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(
          Layout.margin,
          0,
          Layout.margin,
          Space.s6,
        ),
      ),
    );
}

class _Toast extends StatelessWidget {
  const _Toast.pill(this.message) : actionLabel = null, onAction = null;
  const _Toast.bar(this.message, {required this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final style = StabiloType.label.copyWith(
      fontWeight: FontWeight.w600,
      color: c.toastInk,
    );
    final pill = actionLabel == null;
    return Container(
      height: pill ? 48 : 56,
      padding: pill
          ? const EdgeInsets.fromLTRB(Space.s3, 0, Space.s4, 0)
          : const EdgeInsets.fromLTRB(Space.s4, 0, Space.s2, 0),
      decoration: BoxDecoration(
        color: c.toastBg,
        borderRadius: BorderRadius.circular(pill ? Radii.full : Radii.lg),
        boxShadow: Elevation.toast,
      ),
      child: Row(
        mainAxisSize: pill ? MainAxisSize.min : MainAxisSize.max,
        spacing: Space.s3,
        children: [
          if (pill)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              child: AppIcon(AppIcons.check, size: 14, color: c.onAccent),
            ),
          Flexible(
            fit: pill ? FlexFit.loose : FlexFit.tight,
            child: Text(message, style: style),
          ),
          if (!pill)
            Material(
              color: c.accent,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onAction,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  alignment: Alignment.center,
                  child: Text(
                    actionLabel!,
                    style: StabiloType.label.copyWith(
                      fontSize: 14,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
