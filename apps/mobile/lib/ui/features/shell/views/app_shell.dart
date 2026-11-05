import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../discover/view_models/download_queue_view_model.dart';
import '../../discover/views/download_chip.dart';
import '../view_models/tab_reselect.dart';

/// Rak · Cari buku · Atur di bawah [LumaNavBar] melayang (board Komponen ·
/// NavBar). Konten tab dapet ruang bawah [Layout.navSpace] lewat padding
/// MediaQuery, jadi list tiap tab gak perlu tau soal bar. Bar ke-hide pas
/// keyboard naik; layar baca & detail buku ada di luar shell.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// true kalau [context] ada di tab yang lagi keliatan (atau di luar shell).
  /// Tab lain tetep hidup di IndexedStack, jadi listener global (backup,
  /// import) cuma boleh jalan di tab ini.
  static bool isVisible(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell == null) return true;
    final active = shell.route.branches[shell.currentIndex].routes.first;
    return active is GoRoute &&
        GoRouterState.of(context).fullPath == active.path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            // Lapisan ini di atas semua Scaffold: tanpa Material, Text-nya
            // jatuh ke gaya darurat Flutter (garis bawah kuning).
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
