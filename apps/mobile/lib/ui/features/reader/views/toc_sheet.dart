import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';

/// Daftar isi (board 08). Balikin indeks chapter yang dipilih, null kalau
/// ditutup.
Future<int?> showTocSheet(
  BuildContext context, {
  required ReaderBook book,
  required int current,
  required int percent,
}) => showAppSheet<int>(
  context,
  maxHeight: 0.87,
  builder: (_) => _TocSheet(book: book, current: current, percent: percent),
);

class _TocSheet extends StatefulWidget {
  const _TocSheet({
    required this.book,
    required this.current,
    required this.percent,
  });

  final ReaderBook book;
  final int current;
  final int percent;

  @override
  State<_TocSheet> createState() => _TocSheetState();
}

class _TocSheetState extends State<_TocSheet> {
  final _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Buku 60 bab: langsung keliatan bab yang lagi dibaca.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _currentKey.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final chapters = widget.book.chapters;
    final digits = chapters.length.toString().length.clamp(2, 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 10, Space.s4, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          const SheetGrabber(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s3,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.s1,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Daftar isi', style: StabiloType.titleMd),
                      ),
                      Text(
                        '${widget.book.title} · ${chapters.length} bab · '
                        '${widget.percent}% kebaca',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.caption.copyWith(color: c.ink2),
                      ),
                    ],
                  ),
                ),
                CircleButton(
                  semanticLabel: 'Tutup',
                  icon: AppIcons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: Space.s4 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s1,
                children: [
                  for (final (i, ch) in chapters.indexed)
                    _TocRow(
                      key: i == widget.current ? _currentKey : null,
                      number: (i + 1).toString().padLeft(digits, '0'),
                      title: ch.title,
                      current: i == widget.current,
                      onTap: () => Navigator.of(context).pop(i),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TocRow extends StatelessWidget {
  const _TocRow({
    super.key,
    required this.number,
    required this.title,
    required this.current,
    required this.onTap,
  });

  final String number;
  final String title;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final fg = current ? c.onAccent : c.ink;
    return Semantics(
      button: true,
      selected: current,
      child: Material(
        color: current ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(Space.s4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: Space.s2,
              ),
              child: Row(
                spacing: Space.s3,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      number,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: current ? c.onAccent : c.ink2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: StabiloType.label.copyWith(
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (current)
                    Text(
                      'Lagi dibaca',
                      style: StabiloType.micro.copyWith(
                        fontSize: 12,
                        color: fg,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
