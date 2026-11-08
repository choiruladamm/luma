import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';

/// Pembuka bab di awal teks (board 03 Baca + "awal bab, judul panjang"):
/// rata tengah, coretan kuning miring, judul font baca, meta
/// "Bab 4 dari 102 · ±14 mnt". Dipakai buat semua judul, pendek maupun panjang.
class ChapterHeading extends StatelessWidget {
  const ChapterHeading({
    super.key,
    required this.title,
    required this.number,
    required this.total,
    required this.minutes,
    required this.reading,
  });

  final String title;
  final int number;
  final int total;
  final int minutes;

  /// Gaya teks baca sekarang (font dari Aa).
  final TextStyle reading;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Layout.chapterOpenerTop,
        Space.s2,
        Layout.chapterOpenerBottom,
      ),
      child: Column(
        spacing: Layout.chapterOpenerGap,
        children: [
          Transform.rotate(
            angle: Layout.chapterStrokeTilt,
            child: Container(
              width: Layout.chapterStrokeWidth,
              height: Layout.chapterStrokeHeight,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
            ),
          ),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: reading.copyWith(
                fontSize: 23,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.23,
              ),
            ),
          ),
          Text(
            'Bab $number dari $total · ±$minutes mnt',
            style: StabiloType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
