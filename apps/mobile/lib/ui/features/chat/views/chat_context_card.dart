import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

class ChatNotice extends StatelessWidget {
  const ChatNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s3),
    decoration: BoxDecoration(
      color: context.stabilo.muted,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s2,
      children: [
        const AppIcon(AppIcons.info),
        Expanded(
          child: Text(
            'Fitur ini masih dalam pengembangan. Jawaban AI bisa keliru, jadi cek sumbernya lewat angka sitasi.',
            style: StabiloType.caption.copyWith(color: context.stabilo.ink2),
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
    this.chapterTitle,
    this.onRead,
    this.onRemove,
    this.collapseOn = 0,
  });
  final ChatQuote quote;
  final String? chapterTitle;
  final VoidCallback? onRead, onRemove;
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s3),
    decoration: BoxDecoration(
      color: context.stabilo.muted,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s2,
          children: [
            Text(
              widget.chapterTitle ??
                  'Paragraf ${widget.quote.anchors.first.paragraphIndex + 1}',
              style: StabiloType.caption,
            ),
            if (widget.onRead != null)
              TextButton(
                onPressed: widget.onRead,
                child: const Text('Baca di buku'),
              ),
            CircleButton(
              semanticLabel: _expanded ? 'Ciutkan konteks' : 'Perluas konteks',
              icon: _expanded ? AppIcons.collapse : AppIcons.expand,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            if (widget.onRemove != null)
              CircleButton(
                semanticLabel: 'Lepas kutipan',
                icon: AppIcons.close,
                onPressed: widget.onRemove,
              ),
          ],
        ),
        Text(
          widget.quote.text,
          maxLines: _expanded ? null : 2,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: StabiloType.readingSheet,
        ),
        if (_expanded && widget.quote.translation != null) ...[
          const Text('Terjemahan', style: StabiloType.caption),
          SelectableText(
            widget.quote.translation!,
            style: StabiloType.readingSheet,
          ),
        ],
      ],
    ),
  );
}
