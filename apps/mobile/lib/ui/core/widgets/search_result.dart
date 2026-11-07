import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'tag.dart';

/// Header grup per bab di daftar hasil Cari kata: judul, chip "Lagi dibaca"
/// buat bab yang lagi dibaca, jumlah hasil di kanan.
class SearchGroupHeader extends StatelessWidget {
  const SearchGroupHeader({
    super.key,
    required this.title,
    required this.count,
    this.current = false,
  });

  final String title;
  final int count;

  /// Bab yang lagi dibaca (gak dipindah ke atas, cuma dikasih chip).
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, 2),
      child: Row(
        spacing: Space.s2,
        children: [
          // Kiri makan sisa ruang (justify-between): jumlah hasil mentok
          // kanan. Flexible + Spacer bagi sisa 50:50, jumlahnya gak nempel.
          Expanded(
            child: Row(
              spacing: Space.s2,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.label.copyWith(
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
                if (current) const Tag.status('Lagi dibaca'),
              ],
            ),
          ),
          Text(
            '$count hasil',
            style: StabiloType.micro.copyWith(
              fontSize: 12,
              color: c.ink2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu hasil: cuplikan paling banyak 3 baris, kata cocok di-stabilo inline
/// (pengecualian aturan highlight, docs/design.md). [matchStart]/[matchEnd]
/// = posisi di [snippet]; sama-sama 0 = gak ada yang di-stabilo.
class SearchHitTile extends StatelessWidget {
  const SearchHitTile({
    super.key,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    required this.onTap,
  });

  final String snippet;
  final int matchStart;
  final int matchEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final base = StabiloType.readingSheet.copyWith(color: c.ink);
    final hasMatch = matchEnd > matchStart && matchEnd <= snippet.length;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: 10,
          ),
          child: Text.rich(
            TextSpan(
              style: base,
              children: hasMatch
                  ? [
                      TextSpan(text: snippet.substring(0, matchStart)),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: c.highlight,
                            borderRadius: BorderRadius.circular(Radii.xs),
                          ),
                          child: Text(
                            snippet.substring(matchStart, matchEnd),
                            style: base.copyWith(color: c.onHighlight),
                          ),
                        ),
                      ),
                      TextSpan(text: snippet.substring(matchEnd)),
                    ]
                  : [TextSpan(text: snippet)],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
