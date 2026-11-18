import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/l10n.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';

/// Frame of a Settings detail page: back button + title, scrolling content with
/// room above the floating tab bar at the bottom (board "Pengaturan · 02–10").
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  /// Height of the floating tab bar + its bottom gap (board: padding-bottom 110).
  static const navClearance = 110.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
              child: SizedBox(
                height: Layout.topBar,
                child: Row(
                  spacing: Space.s3,
                  children: [
                    CircleButton(
                      semanticLabel: context.l10n.settingsBack,
                      icon: AppIcons.back,
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: StabiloType.titleLg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: EdgeFadeScroll(
                bottom: EdgeFadeSide.none,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Layout.margin,
                    Space.s3,
                    Layout.margin,
                    navClearance,
                  ),
                  children: [
                    for (final c in children) ...[
                      c,
                      const SizedBox(height: Space.s3),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
