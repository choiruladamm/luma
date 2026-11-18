import 'package:luma/l10n/l10n.dart';

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'book_card.dart';
import 'book_cover.dart';
import 'buttons.dart';
import 'menu.dart';

/// Book long-press menu (board 20 Tekan lama buku): blurred shelf + veil,
/// lifted cover in the middle with its sticker, menu panel below. Tapping
/// outside closes it; the result is null.
Future<T?> showBookMenu<T>(
  BuildContext context, {
  required String title,
  String? author,
  File? coverFile,
  required double progress,
  required bool opened,
  required bool finished,
  required List<AppMenuItem<T>> items,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.bookCloseMenu,
  barrierColor: Colors.transparent,
  transitionDuration: Motion.highlight,
  pageBuilder: (context, animation, _) => _BookMenu<T>(
    animation: animation,
    title: title,
    author: author,
    coverFile: coverFile,
    progress: progress,
    opened: opened,
    finished: finished,
    items: items,
  ),
);

class _BookMenu<T> extends StatelessWidget {
  const _BookMenu({
    required this.animation,
    required this.title,
    required this.author,
    required this.coverFile,
    required this.progress,
    required this.opened,
    required this.finished,
    required this.items,
  });

  final Animation<double> animation;
  final String title;
  final String? author;
  final File? coverFile;
  final double progress;
  final bool opened;
  final bool finished;
  final List<AppMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    // Reduce Motion: fade only, the cover doesn't scale up.
    final still = MediaQuery.disableAnimationsOf(context);
    // Dialog routes have no Material: without this the text gets a yellow underline.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Motion.highlightCurve.transform(animation.value);
          final blur = Layout.bookMenuBlur * t;
          return Stack(
            children: [
              // The veil doesn't catch taps: the route barrier does the closing.
              Positioned.fill(
                child: IgnorePointer(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: ColoredBox(
                      color: Color.lerp(c.veil.withAlpha(0), c.veil, t)!,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: Layout.bookMenuTop,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: still ? 1 : 0.9 + 0.1 * t,
                    child: Column(
                      spacing: Layout.bookMenuGap,
                      children: [
                        _cover(),
                        _Panel<T>(title: title, items: items),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The 3-column card (cover + sticker) is scaled to [Layout.bookMenuCover],
  /// so lines, corners, and sticker grow as on the board.
  Widget _cover() {
    const source = Layout.bookMenuCoverSource;
    const scale = Layout.bookMenuCover / source;
    const stickerDrop = 11.0; // sticker sticks out below the cover
    return Semantics(
      label: title,
      image: true,
      child: SizedBox(
        width: Layout.bookMenuCover,
        height: (source / Layout.coverAspect + stickerDrop) * scale,
        child: Align(
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                BookCover(
                  title: title,
                  author: author,
                  file: coverFile,
                  width: source,
                  shadows: Elevation.lift,
                  progress: finished
                      ? 1
                      : progress > 0
                      ? progress
                      : null,
                ),
                Positioned(
                  right: 6,
                  bottom: -stickerDrop,
                  child: ExcludeSemantics(
                    child: ProgressSticker(
                      progress: progress,
                      opened: opened,
                      finished: finished,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel<T> extends StatelessWidget {
  const _Panel({required this.title, required this.items});

  final String title;
  final List<AppMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    const radius = BorderRadius.all(Radius.circular(Radii.menu));
    return Container(
      width: Layout.bookMenuWidth,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: radius,
        boxShadow: Elevation.menu,
      ),
      // 1px inner border, over the content.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: c.menuLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const Divider(),
            _Row<T>(item),
          ],
        ],
      ),
    );
  }
}

class _Row<T> extends StatelessWidget {
  const _Row(this.item);

  final AppMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final color = item.destructive ? c.danger : c.ink;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(item.value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Layout.bookMenuRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Row(
              spacing: Space.s3,
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: StabiloType.label.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (item.icon != null)
                  AppIcon(item.icon!, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
