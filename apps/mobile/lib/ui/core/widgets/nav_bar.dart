import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

enum LumaTab {
  rak('Rak', HugeIcons.strokeRoundedLibrary),
  cari('Cari buku', HugeIcons.strokeRoundedSearch01),
  atur('Atur', HugeIcons.strokeRoundedSettings01);

  const LumaTab(this.label, this.icon);

  final String label;
  final List<List<dynamic>> icon;
}

/// Bottom bar (board Komponen · NavBar): pill melayang, tab aktif pill accent
/// + label, tab diem ikon doang. [downloads] = lencana di tab Cari buku.
/// Dipasang lewat `Stack` (bukan `bottomNavigationBar`) biar melayang.
class LumaNavBar extends StatelessWidget {
  const LumaNavBar({
    super.key,
    required this.current,
    required this.onTap,
    this.downloads = 0,
  });

  final LumaTab current;
  final ValueChanged<LumaTab> onTap;
  final int downloads;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Semantics(
      container: true,
      label: 'Navigasi utama',
      child: Container(
        height: Layout.navBar,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(Layout.navBar / 2),
          border: Border.all(color: c.outline, width: Layout.outline),
          boxShadow: Elevation.capsule(c, b),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s1,
          children: [
            for (final tab in LumaTab.values)
              _Tab(
                tab: tab,
                active: tab == current,
                badge: tab == LumaTab.cari ? downloads : 0,
                onTap: () => onTap(tab),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final LumaTab tab;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : Motion.navTab;
    final label = badge > 0 ? '${tab.label}, $badge unduhan jalan' : tab.label;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          height: Layout.navTab,
          // Padding tetap: ikon 20 + 14 kiri-kanan = lingkaran 48, jadi cuma
          // label yang nambah lebar pas aktif. Warna & garis difade dengan
          // rona yang sama (bukan ke Colors.transparent / border null): kalau
          // enggak, kuning nyisa jadi coklat dan garisnya ngecil dulu.
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? c.accent : c.accent.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(Layout.navTab / 2),
            border: Border.all(
              color: active
                  ? c.accentBorder
                  : c.accentBorder.withValues(alpha: 0),
              width: Layout.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppIcon(tab.icon, color: active ? c.onAccent : c.ink2),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: ExcludeSemantics(child: _Badge(badge)),
                    ),
                ],
              ),
              // Label ikut melebar + muncul pas aktif, ngecil + pudar pas
              // pindah, jadi gak ada kapsul kuning kosong yang nyusut.
              TweenAnimationBuilder<double>(
                tween: Tween(end: active ? 1 : 0),
                duration: duration,
                curve: Curves.easeOut,
                builder: (_, t, child) => t == 0
                    ? const SizedBox.shrink()
                    : ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: t,
                          child: Opacity(opacity: t, child: child),
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.s2, right: 4),
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    softWrap: false,
                    style: StabiloType.label.copyWith(
                      fontSize: 14,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: Layout.navBadge,
      constraints: const BoxConstraints(minWidth: Layout.navBadge),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.pink,
        borderRadius: BorderRadius.circular(Layout.navBadge / 2),
        border: Border.all(color: c.outline, width: Layout.outline),
      ),
      child: Text(
        '${math.min(count, 99)}',
        style: StabiloType.micro.copyWith(fontSize: 10, color: c.onPink),
      ),
    );
  }
}
