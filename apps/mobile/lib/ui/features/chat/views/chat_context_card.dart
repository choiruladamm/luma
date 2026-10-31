import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/tag.dart';

class ChatNotice extends StatelessWidget {
  const ChatNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
    decoration: BoxDecoration(
      color: context.stabilo.muted,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        const AppIcon(AppIcons.info),
        Expanded(
          child: Text(
            'Fitur ini masih dalam pengembangan. Jawaban AI bisa keliru, jadi cek sumbernya lewat angka sitasi.',
            style: StabiloType.caption.copyWith(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: context.stabilo.ink2,
            ),
          ),
        ),
      ],
    ),
  );
}

class ChatContextCard extends StatefulWidget {
  const ChatContextCard({
    super.key,
    required this.quote,
    this.onRead,
    this.collapseOn = 0,
    this.typo,
  });
  final ChatQuote quote;

  /// "Buku II · bagian 1".
  String get where {
    final paragraph = 'bagian ${quote.anchors.first.paragraphIndex + 1}';
    final chapter = quote.chapterTitle;
    return chapter == null ? paragraph : '$chapter · $paragraph';
  }

  final VoidCallback? onRead;

  /// Tipografi Aa; kosong = default Aa.
  final ReaderTypography? typo;
  final int collapseOn;
  @override
  State<ChatContextCard> createState() => _ChatContextCardState();
}

class _ChatContextCardState extends State<ChatContextCard> {
  bool _expanded = false;
  @override
  void didUpdateWidget(ChatContextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseOn != widget.collapseOn) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final typo =
        widget.typo ??
        ReaderTypography(const ReaderPrefs(), Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      decoration: BoxDecoration(
        color: context.stabilo.sheet,
        border: Border.all(
          color: context.stabilo.fieldLine,
          width: Layout.outline,
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              spacing: Space.s2,
              children: [
                Expanded(
                  child: Text(
                    widget.where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.stabilo.ink2,
                    ),
                  ),
                ),
                if (widget.onRead != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onRead,
                    child: Semantics(
                      button: true,
                      excludeSemantics: true,
                      label: 'Baca di buku',
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
                        decoration: BoxDecoration(
                          color: context.stabilo.muted,
                          borderRadius: BorderRadius.circular(Radii.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            const AppIcon(AppIcons.book, size: 16),
                            Text(
                              'Baca di buku',
                              style: StabiloType.label.copyWith(
                                fontSize: 12.5,
                                color: context.stabilo.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: _expanded ? 'Ciutkan konteks' : 'Perluas konteks',
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: AppIcon(
                    _expanded ? AppIcons.collapse : AppIcons.expand,
                    color: context.stabilo.ink2,
                  ),
                ),
              ],
            ),
          ),
          if (!_expanded)
            Padding(
              padding: const EdgeInsets.only(right: Space.s2),
              child: Text(
                widget.quote.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typo.compact.copyWith(
                  fontSize: typo.compact.fontSize! * (14.5 / 15.5),
                  color: context.stabilo.ink2,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: Space.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  Text(widget.quote.text, style: typo.compact),
                  if (widget.quote.translation != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.s2,
                      children: [
                        const Tag.section('Terjemahan'),
                        SelectableText(
                          widget.quote.translation!,
                          style: typo.compact,
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
