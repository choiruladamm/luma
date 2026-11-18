import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../core/widgets/toast.dart';
import '../../discover/view_models/download_queue_view_model.dart';
import '../../discover/views/download_chip.dart';
import '../view_models/tab_reselect.dart';

/// Rak · Cari buku · Atur under the floating [LumaNavBar] (board Komponen ·
/// NavBar). Tab content gets [Layout.navSpace] of bottom room via MediaQuery
/// padding, so each tab's list needn't know about the bar. The bar hides when
/// the keyboard rises; the reading screen & book detail are outside the shell.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// true if [context] is in the currently visible tab (or outside the shell).
  /// Other tabs stay alive in the IndexedStack, so global listeners (backup,
  /// import) may only run in this tab.
  static bool isVisible(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell == null) return true;
    final active = shell.route.branches[shell.currentIndex].routes.first;
    return active is GoRoute &&
        GoRouterState.of(context).fullPath == active.path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    navBarRoute = ModalRoute.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final bottom = math.max(Layout.navBottom, media.padding.bottom);
    final current = LumaTab.values[shell.currentIndex];
    final downloads = ref.watch(
      downloadQueueProvider.select((q) => q.where((i) => !i.finished).length),
    );
    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: keyboard ? media.padding.bottom : Layout.navSpace,
            ),
          ),
          child: shell,
        ),
        if (!keyboard)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            // This layer is above every Scaffold: without Material, the Text falls back
            // to Flutter's emergency style (yellow underline).
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: Layout.navChipGap,
                children: [
                  const DownloadChip(),
                  LumaNavBar(
                    current: current,
                    downloads: downloads,
                    onTap: (tab) {
                      if (tab == current) {
                        ref.read(tabReselectProvider.notifier).bump(tab);
                      }
                      shell.goBranch(
                        tab.index,
                        initialLocation: tab == current,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
