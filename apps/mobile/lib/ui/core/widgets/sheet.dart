import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Bottom sheet Stabilo. Tinggi ngikutin isi, maks [maxHeight] × layar.
/// Isinya biasanya [SheetFrame].
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxHeight = 0.7,

  /// false = cuma bisa ditutup lewat tombol di sheet (mis. proses import).
  bool dismissible = true,
}) {
  // ponytail: "Kurangi gerakan" cuma motong durasi, belum ganti slide → fade
  // kayak board. Ganti ke route fade sendiri kalau slide-nya masih ganggu.
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeight,
    ),
    sheetAnimationStyle: reduced
        ? const AnimationStyle(
            duration: Motion.reducedFade,
            reverseDuration: Motion.reducedFade,
          )
        : const AnimationStyle(
            duration: Motion.sheetOpen,
            curve: Motion.sheetOpenCurve,
            reverseDuration: Motion.sheetClose,
            reverseCurve: Motion.sheetCloseCurve,
          ),
    builder: builder,
  );
}

/// Anatomi sheet (board Komponen 03): grabber, header (judul + tutup), isi
/// yang scroll, action bar yang nempel di bawah.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    this.title,
    this.leading,
    this.closeLabel = 'Tutup',
    required this.children,
    this.actions = const [],
  });

  /// Null = tanpa header (mis. state error yang punya header sendiri).
  final String? title;

  /// Di kiri judul, mis. titik "lagi mikir".
  final Widget? leading;
  final String closeLabel;

  /// Section isi, jaraknya 16.
  final List<Widget> children;

  /// Tombol di bawah. Bungkus pake [Expanded] buat yang flex 1.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Layout.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s4,
        children: [
          const SheetGrabber(),
          if (title != null)
            Row(
              spacing: Space.s3,
              children: [
                ?leading,
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title!, style: StabiloType.titleMd),
                  ),
                ),
                CircleButton(
                  semanticLabel: closeLabel,
                  icon: AppIcons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s4,
                children: children,
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Row(spacing: Space.s2, children: actions),
            ),
        ],
      ),
    );
  }
}

/// Gagang sheet 40 × 5.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: context.stabilo.grabber,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
    ),
  );
}
