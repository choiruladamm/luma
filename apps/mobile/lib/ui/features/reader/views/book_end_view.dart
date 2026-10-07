import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/file_storage.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/reader_view_model.dart';

/// Layar akhir buku (board 12 Akhir buku). Dibuka dari kartu bab terakhir.
class BookEndView extends ConsumerWidget {
  const BookEndView({
    super.key,
    required this.book,
    required this.onClose,
    required this.onRestart,
  });

  final ReaderBook book;
  final VoidCallback onClose;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final end = ref.watch(bookEndProvider(book.id)).value;
    final bottom = math.max(MediaQuery.paddingOf(context).bottom, Space.s6);
    return Padding(
      padding: EdgeInsets.fromLTRB(Layout.margin, 0, Layout.margin, bottom),
      child: Column(
        children: [
          SizedBox(
            height: Layout.topBar,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: onClose,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  spacing: Space.s8,
                  children: [
                    _Art(
                      title: book.title,
                      author: end?.author,
                      cover: end?.coverName == null
                          ? null
                          : ref
                                .read(fileStorageProvider)
                                .cover(end!.coverName!),
                    ),
                    Column(
                      spacing: Space.s3,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Bukunya '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.s2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    borderRadius: BorderRadius.circular(
                                      Space.s2,
                                    ),
                                  ),
                                  child: Text(
                                    'kelar!',
                                    style: _hero.copyWith(color: c.onAccent),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: _hero.copyWith(color: c.ink),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            '${book.title} udah lo libas sampe kalimat '
                            'terakhir. Keren sih.',
                            textAlign: TextAlign.center,
                            style: StabiloType.body.copyWith(color: c.ink2),
                          ),
                        ),
                      ],
                    ),
                    if (end != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          _Stat(
                            value: formatReadingTime(end.readingSeconds),
                            label: 'waktu baca',
                          ),
                          _Stat(
                            value: '${end.translated}',
                            label: 'paragraf diartiin',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s2,
            children: [
              AppButton.primary(
                label: 'Balik ke rak, cari buku lain',
                height: 56,
                onPressed: onClose,
              ),
              TextButton(
                onPressed: onRestart,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: c.ink2,
                  textStyle: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Baca ulang dari awal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final _hero = StabiloType.display.copyWith(
    fontSize: 40,
    height: 1.02,
    letterSpacing: -0.035 * 40,
  );
}

/// Cover agak miring di atas tiga coretan stabilo.
class _Art extends StatelessWidget {
  const _Art({required this.title, this.author, this.cover});

  final String title;
  final String? author;
  final File? cover;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final alpha = light ? 1.0 : 0.55;
    const deg = math.pi / 180;

    Widget stroke(
      double left,
      double top,
      double w,
      double h,
      Color color,
      double angle,
    ) => Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle * deg,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(Radii.full),
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: SizedBox(
        width: 240,
        height: 230,
        child: Stack(
          children: [
            stroke(6, 46, 228, 26, c.accent, -8),
            stroke(0, 150, 210, 22, c.pink, 6),
            stroke(160, 96, 74, 18, c.accent, -24),
            Positioned(
              left: 72,
              top: 12,
              child: Transform.rotate(
                angle: 4 * deg,
                child: BookCover(
                  title: title,
                  author: author,
                  file: cover,
                  width: 136,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 14),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          // "6 jam 20 mnt" gak muat di 26: dikecilin, bukan turun baris.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: StabiloType.titleMd.copyWith(
                fontSize: 26,
                letterSpacing: -0.02 * 26,
                color: c.ink,
              ),
            ),
          ),
          Text(label, style: StabiloType.caption.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}
