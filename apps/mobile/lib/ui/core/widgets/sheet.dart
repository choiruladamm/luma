import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';
import 'edge_fade.dart';

/// Stabilo bottom sheet. Height follows the content, max [maxHeight] × screen.
/// Its content is usually a [SheetFrame].
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxHeight = 0.7,

  /// false = can only be closed with a button in the sheet (e.g. the import process).
  bool dismissible = true,

  /// Transparent when the screen behind paints its own scrim (reading page: the
  /// capsule stays visible above the scrim).
  Color? barrierColor,

  /// Defaults to [dismissible]. false = the sheet handles dragging itself (e.g.
  /// DraggableScrollableSheet).
  bool? enableDrag,

  /// Null = sheet color from the theme. Transparent when the content paints its
  /// own surface.
  Color? backgroundColor,
}) {
  // ponytail: Reduce Motion only shortens the duration; it doesn't yet swap
  // slide → fade as on the board. Switch to a custom fade route if the slide
  // still bothers.
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    // Above the tab bar (AppShell), not inside its branch.
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: dismissible,
    barrierColor: barrierColor,
    backgroundColor: backgroundColor,
    enableDrag: enableDrag ?? dismissible,
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

/// Sheet anatomy (board Komponen 03): grabber, header (title + close),
/// scrolling content, action bar pinned at the bottom.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    this.title,
    this.leading,
    this.closeLabel,
    this.showClose = true,
    required this.children,
    this.actions = const [],
  });

  /// Null = no header (e.g. an error state with its own header).
  final String? title;

  /// To the left of the title, e.g. the "lagi mikir" dot.
  final Widget? leading;
  final String? closeLabel;
  final bool showClose;

  /// Content sections, spaced 16.
  final List<Widget> children;

  /// Buttons at the bottom. Wrap in [Expanded] for flex 1.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // No buttons: content runs to the sheet's bottom edge without fade, final
    // padding = safe area (board EdgeFade, edge-to-edge). With buttons: 20pt
    // fade above the buttons, buttons above the safe area.
    final edge = actions.isEmpty;
    return Padding(
      padding: edge
          ? Layout.sheetPadding.copyWith(bottom: 0)
          : Layout.sheetPadding,
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
                if (showClose)
                  CircleButton(
                    semanticLabel: closeLabel ?? context.l10n.sheetClose,
                    icon: AppIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          Flexible(
            child: EdgeFadeScroll(
              bottom: edge ? EdgeFadeSide.none : EdgeFadeSide.standard,
              child: SingleChildScrollView(
                padding: edge
                    ? EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom,
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s4,
                  children: children,
                ),
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

/// Sheet handle 40 × 5.
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
