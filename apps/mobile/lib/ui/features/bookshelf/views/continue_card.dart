import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_card.dart';
import '../../../core/widgets/book_cover.dart';

/// Kartu "Lanjut baca yuk" di atas rak (board Komponen Buku · ContinueCard).
/// Terang: kartu accent + outline. Gelap: kartu muted, accent cuma di kicker
/// & progres.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.book,
    this.coverFile,
    required this.onTap,
  });

  final ShelfBook book;
  final File? coverFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final ink = light ? c.onAccent : c.ink;
    final percent = bookSticker(
      progress: book.progress,
      opened: true,
      finished: false,
    );
    return Semantics(
      button: true,
      label: 'Lanjut baca ${book.title}, $percent',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.s3 + 2),
          decoration: BoxDecoration(
            color: light ? c.accent : c.muted,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: light ? c.outline : c.muted,
              width: Layout.outline,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              spacing: Space.s3 + 2,
              children: [
                BookCover(
                  title: book.title,
                  author: book.author,
                  file: coverFile,
                  width: 72,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.s1,
                        children: [
                          Text(
                            'Lanjut baca yuk →',
                            style: StabiloType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: light ? c.onAccent : c.accent,
                            ),
                          ),
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: StabiloType.titleSm.copyWith(
                              fontSize: 21,
                              height: 1.08,
                              letterSpacing: -0.02 * 21,
                              color: ink,
                            ),
                          ),
                          Text(
                            'Bab ${book.chapter} dari ${book.chapterCount}',
                            style: StabiloType.caption.copyWith(
                              fontSize: 14,
                              height: 1.2,
                              color: c.continueInk2,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: Space.s2,
                        children: [
                          Expanded(child: _Bar(book.progress)),
                          Text(
                            percent,
                            style: StabiloType.caption.copyWith(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _Bar extends StatelessWidget {
  const _Bar(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: c.continueTrack,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: math.max(8, box.maxWidth * progress.clamp(0, 1)),
            decoration: BoxDecoration(
              color: c.progressFill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
