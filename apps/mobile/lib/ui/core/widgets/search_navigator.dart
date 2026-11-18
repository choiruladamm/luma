import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Cari kata result navigator, pinned at the bottom in place of the progress
/// pill (boards "Cari kata 6" and "navigator pas scroll"):
/// `↑ · word + "1 dari 68 · Bab" · ↓ | ×`. [compact] (while scrolling): pill 46,
/// only "1/68", no word, narrower. Tapping the middle returns to the result list.
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

  /// The searched word, as typed in the search field.
  final String word;

  /// The currently open result, starting at 1.
  final int position;
  final int total;

  /// Chapter of the currently open result, on the second line ("1 dari 68 · Chapter I").
  final String? chapterTitle;
  final bool compact;

  /// More results than displayed (500): "dari 500+".
  final bool truncated;

  /// Null = no result before / after (button dimmed).
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
    // Fixed pill height (like the reading capsule): text is bounded so it doesn't overflow.
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
      label: context.l10n.searchSearchResults,
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
                label: context.l10n.searchPreviousResult,
                icon: AppIcons.up01,
                onTap: onPrevious,
              ),
              Semantics(
                button: true,
                label: context.l10n.searchBackToResults,
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
                                      ? context.l10n.searchOf(position, count)
                                      : context.l10n.searchOf2(
                                          position,
                                          count,
                                          chapterTitle!,
                                        ),
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
                label: context.l10n.searchNextResult,
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
                label: context.l10n.searchExitSearch,
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

/// Round [Layout.searchNavButton] button (44 tap area, not visual).
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
