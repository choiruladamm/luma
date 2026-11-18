import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/luma_logo.dart';

/// The title never gets smaller than this because of large text (board Layout
/// rak · the shelf header must not feel cramped).
const _titleFloor = 22.0;

/// Minimum gap between the title and the buttons.
const _titleGap = 16.0;

/// Fits the title in [room] (width left of the buttons, minus the minimum gap):
/// the title shrinks first down to [floor]; if still tight the symbol drops
/// first, never the buttons. [titleWidth] measures the title at a given size.
({double size, bool logo}) fitTitle({
  required double room,
  required double size,
  required double floor,
  required double logo,
  required double logoGap,
  required double Function(double size) titleWidth,
}) {
  final low = floor < size ? floor : size;
  for (var s = size; s >= low; s -= 0.5) {
    if (logo + logoGap + titleWidth(s) <= room) return (size: s, logo: true);
  }
  return (size: low, logo: false);
}

/// Shelf header. [collapse] 0 = large (bar 60, title 28, button 44), 1 = shrunk
/// (bar 44, title 17, symbol 22, button 40, tap area stays 44). Shrinking
/// follows the shelf scroll ([Layout.barShrink]).
class ShelfHeader extends StatelessWidget {
  const ShelfHeader({super.key, this.collapse = 0, required this.onImport});

  final double collapse;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final t = collapse.clamp(0.0, 1.0);
    double lerp(double a, double b) => a + (b - a) * t;
    final logoSize = lerp(28, 22);
    final titleSize = lerp(28, 17);
    final button = lerp(Layout.touch, 40);
    final scaler = MediaQuery.textScalerOf(context);

    TextStyle style(double size) => StabiloType.titleLg.copyWith(
      fontSize: size,
      height: 1.1,
      letterSpacing: -lerp(0.02, 0.01) * size,
      color: context.stabilo.ink,
    );
    double measure(double size) => (TextPainter(
      text: TextSpan(text: context.l10n.shelfYourBookshelf, style: style(size)),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout()).width;

    return SizedBox(
      height: lerp(Layout.topBar, Layout.barMin),
      child: LayoutBuilder(
        builder: (context, box) {
          final buttons = 2 * Layout.touch + Space.s2;
          final logoGap = lerp(Space.s2, 6);
          final fit = fitTitle(
            room: box.maxWidth - buttons - _titleGap,
            size: titleSize,
            floor: _titleFloor,
            logo: logoSize,
            logoGap: logoGap,
            titleWidth: measure,
          );
          return Row(
            children: [
              if (fit.logo) ...[
                Transform.translate(
                  offset: Offset(lerp(-3, -2), 0),
                  child: LumaLogo(size: logoSize),
                ),
                SizedBox(width: logoGap - lerp(3, 2)),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    context.l10n.shelfYourBookshelf,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style(fit.size),
                  ),
                ),
              ),
              const SizedBox(width: _titleGap),
              _Tap(
                onTap: onImport,
                child: CircleButton(
                  semanticLabel: context.l10n.shelfImportEpub,
                  icon: AppIcons.add,
                  primary: true,
                  size: button,
                  onPressed: onImport,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 44 tap area around a button drawn smaller.
class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: Layout.touch,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: IgnorePointer(child: child)),
    ),
  );
}
