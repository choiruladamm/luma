import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'book_card.dart';
import 'book_cover.dart';
import 'buttons.dart';
import 'tag.dart';

/// Baris buku di tampilan list (board "Rak · tampilan list"): cover mini
/// 48×72, judul 1 baris, penulis, progres. State-nya sama kayak [BookCard]:
/// progres, "Baru", "Kelar!", lagi diimport. Tinggi [Layout.rowHeight].
class BookRow extends StatelessWidget {
  const BookRow({
    super.key,
    required this.title,
    this.author,
    this.coverFile,
    required this.progress,
    required this.opened,
    required this.finished,
    this.onTap,
    this.onLongPress,
  }) : importing = false;

  /// Lagi diimport: nama file dulu, belum bisa di-tap / ditekan lama.
  const BookRow.importing({super.key, required String fileName})
    : title = fileName,
      author = null,
      coverFile = null,
      progress = 0,
      opened = false,
      finished = false,
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
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool importing;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final row = SizedBox(
      height: Layout.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          spacing: Space.s3 + 2,
          children: [
            importing
                ? const _ImportingCover()
                : BookCover(
                    title: title,
                    author: author,
                    file: coverFile,
                    width: 48,
                  ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Baris dikunci 84: teks gak ikut Dynamic Type.
                  Text(
                    title,
                    textScaler: TextScaler.noScaling,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.label.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 17,
                    child: Text(
                      author ?? '',
                      textScaler: TextScaler.noScaling,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        height: 17 / 13,
                        color: c.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(height: 22, child: _status(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (importing) {
      return Semantics(label: 'Lagi diimport $title', child: row);
    }
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      onLongPress: onLongPress,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTap = onTap,
              ),
          // Sama kayak kartu grid: tahan 350 ms.
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 350),
                ),
                (r) => r.onLongPress = () {
                  HapticFeedback.mediumImpact();
                  onLongPress?.call();
                },
              ),
        },
        child: row,
      ),
    );
  }

  Widget _status(BuildContext context) {
    final c = context.stabilo;
    if (importing) {
      return Row(
        spacing: 5,
        children: [
          AppIcon(AppIcons.loading, size: 13, color: c.ink2),
          Text(
            'Lagi diproses',
            textScaler: TextScaler.noScaling,
            style: StabiloType.caption.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
              color: c.ink2,
            ),
          ),
        ],
      );
    }
    if (!opened && !finished) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Tag.status('Baru', tone: TagTone.pink),
      );
    }
    final label = bookSticker(
      progress: progress,
      opened: opened,
      finished: finished,
    );
    return Row(
      spacing: Space.s2,
      children: [
        Expanded(child: _Bar(finished ? 1 : progress)),
        if (finished)
          const Tag.status('Kelar!', tone: TagTone.accent, icon: AppIcons.check)
        else
          SizedBox(
            width: 34,
            child: Text(
              label,
              textAlign: TextAlign.right,
              textScaler: TextScaler.noScaling,
              style: StabiloType.micro.copyWith(color: c.ink, height: 1),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: c.track,
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: box.maxWidth * progress.clamp(0, 1) < 4
                ? 4
                : box.maxWidth * progress.clamp(0, 1),
            decoration: BoxDecoration(
              color: c.progressFill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kotak putus-putus 48×72 selama import.
class _ImportingCover extends StatelessWidget {
  const _ImportingCover();

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return CustomPaint(
      foregroundPainter: DashedBorder(color: c.ink3, radius: 8),
      child: Container(
        width: 48,
        height: 72,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: AppIcon(AppIcons.loading, color: c.ink2)),
      ),
    );
  }
}
