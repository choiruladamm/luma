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
          padding: active
              ? const EdgeInsets.only(left: 14, right: 18)
              : EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: Layout.navTab),
          decoration: BoxDecoration(
            color: active ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(Layout.navTab / 2),
            border: active
                ? Border.all(color: c.accentBorder, width: Layout.outline)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.s2,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppIcon(
                    tab.icon,
                    size: active ? 21 : Layout.icon,
                    color: active ? c.onAccent : c.ink2,
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: ExcludeSemantics(child: _Badge(badge)),
                    ),
                ],
              ),
              if (active)
                Text(
                  tab.label,
                  style: StabiloType.label.copyWith(
                    fontSize: 14,
                    color: c.onAccent,
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
