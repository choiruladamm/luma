import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Navigator hasil Cari kata, nempel di bawah gantiin pill progres (board
/// "Cari kata 6" dan "navigator pas scroll"): `↑ · kata + "1 dari 68 · Bab" ·
/// ↓ | ×`. [compact] (pas lagi scroll): pill 46, cuma "1/68", tanpa kata,
/// lebih sempit. Tap tengah = balik ke daftar hasil.
class SearchNavigator extends StatelessWidget {
  const SearchNavigator({
    super.key,
    required this.word,
    required this.position,
    required this.total,
    this.chapterTitle,
    this.compact = false,
    this.truncated = false,
    required this.onPrevious,
    required this.onNext,
    required this.onList,
    required this.onClose,
  });

  /// Kata yang dicari, apa adanya dari kolom cari.
  final String word;

  /// Hasil yang lagi dibuka, mulai 1.
  final int position;
  final int total;

  /// Bab hasil yang lagi dibuka, di baris kedua ("1 dari 68 · Chapter I").
  final String? chapterTitle;
  final bool compact;

  /// Hasil lebih dari yang ditampilin (500): "dari 500+".
  final bool truncated;

  /// Null = gak ada hasil sebelum / sesudahnya (tombol redup).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onList;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final height = compact
        ? Layout.searchNavCompactHeight
        : Layout.searchNavHeight;
    final count = truncated ? '$total+' : '$total';
    // Tinggi pill tetap (kayak kapsul baca): teks dibatasin biar gak meluap.
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
      ),
      child: _pill(context, c, reduce, height, count),
    );
  }

  Widget _pill(
    BuildContext context,
    StabiloColors c,
    bool reduce,
    double height,
    String count,
  ) {
    return Semantics(
      container: true,
      label: 'Hasil cari',
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(color: c.capsuleLine, width: Layout.outline),
          boxShadow: Elevation.capsule(c, Theme.of(context).brightness),
        ),
        child: AnimatedSize(
          duration: reduce ? Duration.zero : Motion.searchPill,
          curve: Curves.easeOut,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavButton(
                label: 'Hasil sebelumnya',
                icon: AppIcons.up01,
                onTap: onPrevious,
              ),
              Semantics(
                button: true,
                label: 'Balik ke daftar hasil',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onList,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? Space.s2 : Space.s3,
                    ),
                    child: compact
                        ? Text(
                            '$position/$count',
                            style: StabiloType.label.copyWith(
                              fontSize: 13,
                              color: c.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 1,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 140,
                                ),
                                child: Text(
                                  word,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: StabiloType.label.copyWith(
                                    fontSize: 13.5,
                                    height: 1.15,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  chapterTitle == null
                                      ? '$position dari $count'
                                      : '$position dari $count · $chapterTitle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: StabiloType.caption.copyWith(
                                    fontSize: 11.5,
                                    height: 1.15,
                                    fontWeight: FontWeight.w600,
                                    color: c.ink2,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              _NavButton(
                label: 'Hasil berikutnya',
                icon: AppIcons.down01,
                onTap: onNext,
              ),
              Container(
                width: 1,
                height: Layout.searchNavDivider,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: c.menuLine,
              ),
              _NavButton(
                label: 'Keluar dari cari',
                icon: AppIcons.close,
                iconSize: 16,
                onTap: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol bulat [Layout.searchNavButton] (area sentuh 44, bukan visual).
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
  });

  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: Layout.touch,
          height: Layout.touch,
          child: Center(
            child: Container(
              width: Layout.searchNavButton,
              height: Layout.searchNavButton,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
              child: Center(
                child: AppIcon(
                  icon,
                  size: iconSize,
                  color: onTap == null ? c.ink3 : c.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
