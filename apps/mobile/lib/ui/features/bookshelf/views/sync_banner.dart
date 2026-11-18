import 'package:flutter/material.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';

/// "Nyinkronin 3/12 buku" above Rak while books from another device download
/// (docs/sync-protocol.md, Book files and Markdown dumps). No board: anatomy of
/// the "Nyiapin katalog buku" card in Cari buku (`DiscoverNotice`): spinner +
/// book count in the title. Can't be dismissed; disappears on its own when the
/// download finishes.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.done, required this.total});

  /// Books already done (succeeded or skipped) out of [total].
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final title = l.bookshelfSyncingBooks((done + 1).clamp(1, total), total);
    return Semantics(
      container: true,
      liveRegion: true,
      label: title,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
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
                child: SizedBox.square(
                  dimension: 18,
                  // Spins continuously: the count is already in the title, and an empty ring
                  // on the first book looks stuck.
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.ink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title, style: StabiloType.label),
                    Text(
                      l.bookshelfSyncingBody,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
