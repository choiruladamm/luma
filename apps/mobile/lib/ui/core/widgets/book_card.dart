import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/markdown_shelf.dart';
import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'book_cover.dart';
import 'buttons.dart';

/// Stiker di pojok cover (board "Kartu buku · anatomi & state").
///
/// - belum pernah dibuka → "Baru" (pink)
/// - [finished] → "Kelar!" (kuning + centang)
/// - [chapters] (buku Markdown) → "N bab" gantiin persen
/// - selain itu → persen, dibulatin ke bawah, 0,4% tetep 1%, maks 99%
String bookSticker({
  required double progress,
  required bool opened,
  required bool finished,
  int? chapters,
}) {
  if (finished) return 'Kelar!';
  if (!opened) return 'Baru';
  if (chapters != null) return '$chapters bab';
  if (progress <= 0) return '0%';
  return '${math.min(99, math.max(1, (progress * 100).floor()))}%';
}

/// Tile buku di rak: cover + pita progres + stiker, judul + penulis di bawah.
/// Tinggi = lebar × 1,5 + 67. Tahan 350 ms = cincin stabilo + haptic, lepas =
/// [onLongPress] (menu buku).
class BookCard extends StatefulWidget {
  const BookCard({
    super.key,
    required this.title,
    this.author,
    this.coverFile,
    required this.progress,
    required this.opened,
    required this.finished,
    this.markdown,
    this.onTap,
    this.onLongPress,
  }) : importing = false;

  /// Lagi diimport: nama file dulu, belum bisa di-tap / ditekan lama.
  const BookCard.importing({super.key, required String fileName})
    : title = fileName,
      author = null,
      coverFile = null,
      progress = 0,
      opened = false,
      finished = false,
      markdown = null,
      onTap = null,
      onLongPress = null,
      importing = true;

  final String title;
  final String? author;
  final File? coverFile;

  /// 0..1.
  final double progress;
  final bool opened;
  final bool finished;

  /// Buku Markdown: strip bab + "N bab" gantiin pita dan persen.
  final MarkdownShelf? markdown;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool importing;

  static double heightFor(double width) => width / Layout.coverAspect + 67;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _pressed = false;

  void _press(bool down) => setState(() => _pressed = down);

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final card = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _ring(w, widget.importing ? _ImportingCover(w) : _cover(w)),
                Positioned(right: 6, bottom: -11, child: _sticker(context)),
              ],
            ),
            const SizedBox(height: Space.s4),
            SizedBox(
              height: 51,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    textScaler: TextScaler.noScaling, // blok dikunci 51
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: c.ink,
                    ),
                  ),
                  if (widget.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.author!,
                      textScaler: TextScaler.noScaling,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 12,
                        height: 16 / 12,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

        if (widget.importing) {
          return Semantics(label: 'Lagi diimport ${widget.title}', child: card);
        }
        return Semantics(
          button: true,
          label: widget.markdown?.semanticLabel(widget.title) ?? widget.title,
          // Buku Markdown: satu label utuh, strip + chip gak dibaca terpisah.
          excludeSemantics: widget.markdown != null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (r) => r.onTap = widget.onTap,
                  ),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 350),
                    ),
                    (r) => r
                      ..onLongPressStart = (_) {
                        HapticFeedback.mediumImpact();
                        _press(true);
                      }
                      ..onLongPressEnd = (_) {
                        _press(false);
                        widget.onLongPress?.call();
                      }
                      ..onLongPressCancel = () => _press(false),
                  ),
            },
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              alignment: Alignment.topCenter,
              duration: Motion.highlight,
              curve: Motion.highlightCurve,
              child: card,
            ),
          ),
        );
      },
    );
  }

  Widget _cover(double w) => BookCover(
    title: widget.title,
    author: widget.author,
    file: widget.coverFile,
    width: w,
    chapters: widget.markdown,
    progress: widget.markdown != null
        ? null
        : widget.finished
        ? 1
        : widget.progress > 0
        ? widget.progress
        : null,
  );

  /// Cincin stabilo pas ditekan lama: 3 accent + 1,5 outline di luar cover.
  Widget _ring(double w, Widget cover) {
    if (!_pressed) return cover;
    final c = context.stabilo;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BookCover.radiusFor(w)),
        boxShadow: [
          BoxShadow(color: c.outline, spreadRadius: 3 + Layout.outline),
          BoxShadow(color: c.accent, spreadRadius: 3),
        ],
      ),
      child: cover,
    );
  }

  Widget _sticker(BuildContext context) {
    if (widget.importing) {
      final c = context.stabilo;
      return _StickerBox(
        bg: c.muted,
        width: 26,
        child: AppIcon(AppIcons.loading, size: 14, color: c.ink2),
      );
    }
    return ProgressSticker(
      progress: widget.progress,
      opened: widget.opened,
      finished: widget.finished,
      chapters: widget.markdown?.count,
    );
  }
}

/// Stiker [bookSticker] di pojok cover: dipake kartu rak dan menu tekan lama.
class ProgressSticker extends StatelessWidget {
  const ProgressSticker({
    super.key,
    required this.progress,
    required this.opened,
    required this.finished,
    this.chapters,
  });

  final double progress;
  final bool opened;
  final bool finished;

  /// Jumlah bab buku Markdown; null = EPUB.
  final int? chapters;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final label = bookSticker(
      progress: progress,
      opened: opened,
      finished: finished,
      chapters: chapters,
    );
    final (bg, fg) = switch (label) {
      'Kelar!' => (c.accent, c.onAccent),
      'Baru' => (c.pink, c.onPink),
      _ => (c.sheet, c.ink),
    };
    return _StickerBox(
      bg: bg,
      shadow: light,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s1,
        children: [
          if (finished) AppIcon(AppIcons.check, size: 12, color: fg),
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: StabiloType.micro.copyWith(color: fg, height: 1),
          ),
        ],
      ),
    );
  }
}

class _StickerBox extends StatelessWidget {
  const _StickerBox({
    required this.bg,
    required this.child,
    this.width,
    this.shadow = false,
  });

  final Color bg;
  final Widget child;
  final double? width;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: 22,
      width: width,
      padding: width == null
          ? const EdgeInsets.symmetric(horizontal: Space.s2)
          : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: c.outline, width: Layout.outline),
        boxShadow: shadow
            ? [BoxShadow(color: c.outline, offset: const Offset(0, 1.5))]
            : null,
      ),
      child: child,
    );
  }
}

/// Kotak putus-putus "Lagi diproses" selama import.
class _ImportingCover extends StatelessWidget {
  const _ImportingCover(this.width);

  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return CustomPaint(
      foregroundPainter: DashedBorder(
        color: c.ink3,
        radius: BookCover.radiusFor(width),
      ),
      child: Container(
        width: width,
        height: width / Layout.coverAspect,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(BookCover.radiusFor(width)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Space.s2,
          children: [
            AppIcon(AppIcons.loading, color: c.ink2),
            Text(
              'Lagi diproses',
              style: StabiloType.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Garis putus-putus 1,5 di sekeliling kotak bersudut [radius] (cover yang
/// lagi diimport).
class DashedBorder extends CustomPainter {
  const DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0, gap = 4.0, half = Layout.outline / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = Layout.outline;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            half,
            half,
            size.width - 2 * half,
            size.height - 2 * half,
          ),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorder old) =>
      old.color != color || old.radius != radius;
}
