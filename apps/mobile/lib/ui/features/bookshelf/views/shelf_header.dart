import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/luma_logo.dart';

const _title = 'Rak buku lo';

/// Judul gak pernah lebih kecil dari ini gara-gara teks gede (board Layout
/// rak · header rak gak boleh sesak).
const _titleFloor = 22.0;

/// Jarak minimum antara judul dan tombol.
const _titleGap = 16.0;

/// Muat-muatin judul di [room] (lebar di kiri tombol, udah dikurangin jarak
/// minimum): judul nyusut dulu sampe [floor], kalau masih mepet simbol ilang
/// duluan, tombol gak pernah. [titleWidth] ngukur judul di ukuran tertentu.
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

/// Header rak. [collapse] 0 = gede (bar 60, judul 28, tombol 44), 1 = nyusut
/// (bar 44, judul 17, simbol 22, tombol 40, area tap tetep 44). Nyusutnya
/// ngikutin scroll rak ([Layout.barShrink]).
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
      text: TextSpan(text: _title, style: style(size)),
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
                    _title,
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
                  semanticLabel: 'Import EPUB',
                  icon: AppIcons.add,
                  primary: true,
                  size: button,
                  onPressed: onImport,
                ),
              ),
              const SizedBox(width: Space.s2),
              _Tap(
                onTap: () => context.push(Routes.settings),
                child: CircleButton(
                  semanticLabel: 'Pengaturan app',
                  icon: AppIcons.settings,
                  size: button,
                  onPressed: () => context.push(Routes.settings),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Area tap 44 di sekitar tombol yang digambar lebih kecil.
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
