import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import 'reader_capsule.dart';
import '../../../core/widgets/edge_fade.dart';

/// Daftar isi (board 08). Balikin indeks chapter yang dipilih, null kalau
/// ditutup. Sheet-nya mulai di bawah kapsul atas; scrim digambar halaman baca
/// di bawah kapsul, jadi barrier sheet transparan. Tap kapsul (termasuk
/// tombol daftar isi) kena barrier = nutup sheet.
Future<int?> showTocSheet(
  BuildContext context, {
  required ReaderBook book,
  required int current,
  required int percent,
}) {
  final height = MediaQuery.sizeOf(context).height;
  final top =
      MediaQuery.paddingOf(context).top +
      capsuleTopGap +
      capsuleHeight +
      Space.s3;
  return showAppSheet<int>(
    context,
    maxHeight: (height - top) / height,
    barrierColor: Colors.transparent,
    builder: (_) => _TocSheet(book: book, current: current, percent: percent),
  );
}

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
            // Tanpa tombol aksi: list jalan sampe tepi bawah, tanpa fade bawah.
            child: EdgeFadeScroll(
              bottom: EdgeFadeSide.none,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s1,
                  children: [
                    for (final (i, ch) in chapters.indexed)
                      _TocRow(
                        key: i == widget.current ? _currentKey : null,
                        title: ch.title,
                        minutes: readingMinutes(ch.chars),
                        current: i == widget.current,
                        onTap: () => Navigator.of(context).pop(i),
                      ),
                  ],
                ),
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
    required this.title,
    required this.minutes,
    required this.current,
    required this.onTap,
  });

  final String title;
  final int minutes;
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
                  Expanded(
                    child: Text(
                      title,
                      style: StabiloType.label.copyWith(
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  Text(
                    current ? 'Lagi dibaca · ±$minutes mnt' : '±$minutes mnt',
                    style: StabiloType.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                      color: current ? fg : c.ink2,
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
