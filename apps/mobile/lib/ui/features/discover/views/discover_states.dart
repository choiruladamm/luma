import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

/// Kotak muted dengan ikon tile 36, judul, isi, tombol (board 07 / 08).
class DiscoverNotice extends StatelessWidget {
  const DiscoverNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
    this.spinning = false,
  });

  final List<List<dynamic>> icon;
  final String title, body;
  final VoidCallback? onRetry;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s3,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.sheet,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: spinning
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.ink,
                      ),
                    )
                  : AppIcon(icon, size: 18, color: c.ink),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: StabiloType.label),
                  Text(
                    body,
                    style: StabiloType.caption.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.ink2,
                    ),
                  ),
                  if (onRetry case final retry?)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s2),
                      child: Semantics(
                        button: true,
                        child: GestureDetector(
                          onTap: retry,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.s4,
                            ),
                            decoration: BoxDecoration(
                              color: c.sheet,
                              borderRadius: BorderRadius.circular(Radii.full),
                            ),
                            // widthFactor: 1 = selebar teks (alignment melar).
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                context.l10n.meaningTryAgain,
                                style: StabiloType.label.copyWith(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiga baris skeleton (cover 52 muted + dua garis), tanpa animasi.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    Widget bar(double fraction, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: fraction,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        children: [
          for (final (i, w) in [0.7, 0.5, 0.6].indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.track),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                spacing: 14,
                children: [
                  Container(
                    width: 52,
                    height: 78,
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.track, width: Layout.outline),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 9,
                      children: [bar(w, 14), bar(0.45, 12)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ikon tile 64 + judul 19 + isi (board 06 / 09).
class DiscoverEmpty extends StatelessWidget {
  const DiscoverEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final List<List<dynamic>> icon;
  final String title, body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 40, 12, 0),
      child: Column(
        spacing: 10,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: AppIcon(icon, size: 28, color: c.ink),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: StabiloType.titleSm,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: StabiloType.body.copyWith(color: c.ink2),
            ),
          ),
          if (action case final a?)
            Padding(padding: const EdgeInsets.only(top: 6), child: a),
        ],
      ),
    );
  }
}
