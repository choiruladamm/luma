import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Toast (board Komponen 04), ilang sendiri 2,5 detik.
///
/// Cuma [message]: pill di tengah + centang ("Udah disalin, tinggal paste").
/// Ada [subtitle] / [leading] / [actionLabel]: bar lebar ("Sip, udah masuk
/// rak!" · Baca, "Backup kelar, aman!"), tombol kecilnya cuma kalau ada
/// [actionLabel].
void showToast(
  BuildContext context,
  String message, {
  String? subtitle,
  Widget? leading,
  String? actionLabel,
  VoidCallback? onAction,

  /// Baris kedua di bawah garis, tombol aksinya pindah ke sini ("API key gak
  /// ikut backup..." · Isi key).
  String? note,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: actionLabel == null && subtitle == null && leading == null
            ? Center(child: _Toast.pill(message))
            : _Toast.bar(
                message,
                subtitle: subtitle,
                leading: leading,
                actionLabel: actionLabel,
                note: note,
                onAction: () {
                  messenger.hideCurrentSnackBar();
                  onAction?.call();
                },
              ),
        duration: note == null ? Motion.toast : Motion.toastLong,
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

/// Toast pill di atas semua route, buat dari dalem sheet (snackbar-nya
/// ketutup sheet). [bottom] diukur dari tepi bawah layar.
void showOverlayToast(
  BuildContext context,
  String message, {
  double bottom = 102,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: Layout.margin,
      right: Layout.margin,
      bottom: bottom,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Center(child: _Toast.pill(message)),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(Motion.toast, () {
    if (entry.mounted) entry.remove();
  });
}

class _Toast extends StatelessWidget {
  const _Toast.pill(this.message)
    : subtitle = null,
      leading = null,
      actionLabel = null,
      onAction = null,
      note = null,
      pill = true;
  const _Toast.bar(
    this.message, {
    this.actionLabel,
    this.subtitle,
    this.leading,
    this.onAction,
    this.note,
  }) : pill = false;

  final String message;
  final String? subtitle;
  final Widget? leading;
  final String? actionLabel;
  final bool pill;
  final VoidCallback? onAction;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final style = StabiloType.label.copyWith(
      fontWeight: FontWeight.w600,
      color: c.toastInk,
    );
    final rich = leading != null || subtitle != null;
    return Container(
      height: pill ? 48 : (rich ? null : 56),
      constraints: rich ? const BoxConstraints(minHeight: 60) : null,
      padding: pill
          ? const EdgeInsets.fromLTRB(Space.s3, 0, Space.s4, 0)
          : rich
          ? const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s2, Space.s2)
          : const EdgeInsets.fromLTRB(Space.s4, 0, Space.s2, 0),
      decoration: BoxDecoration(
        color: c.toastBg,
        borderRadius: BorderRadius.circular(pill ? Radii.full : Radii.lg),
        boxShadow: Elevation.toast,
      ),
      child: _withNote(
        context,
        Row(
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
            ?leading,
            Flexible(
              fit: pill ? FlexFit.loose : FlexFit.tight,
              child: subtitle == null
                  ? Text(message, style: style)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: style.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.caption.copyWith(
                            color: c.toastInk.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
            ),
            if (actionLabel != null && note == null) _action(c, rich),
          ],
        ),
      ),
    );
  }

  /// Ada [note]: baris utama, garis tipis, terus catatan + tombol aksi.
  Widget _withNote(BuildContext context, Widget main) {
    if (note == null) return main;
    final c = context.stabilo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        main,
        Container(
          padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, 6, 0),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: c.toastInk.withValues(alpha: 0.16)),
            ),
          ),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  note!,
                  style: StabiloType.caption.copyWith(
                    height: 1.35,
                    color: c.toastInk,
                  ),
                ),
              ),
              if (actionLabel != null) _action(c, false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(StabiloColors c, bool rich) => Material(
    color: c.accent,
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onAction,
      child: Container(
        height: rich ? Layout.touch : 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        alignment: Alignment.center,
        child: Text(
          actionLabel!,
          style: StabiloType.label.copyWith(fontSize: 14, color: c.onAccent),
        ),
      ),
    ),
  );
}
