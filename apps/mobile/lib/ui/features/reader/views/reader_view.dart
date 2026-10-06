import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/reader_view_model.dart';

/// Halaman baca (board 03 Baca, 11 Akhir bab). Satu chapter per layar; ujung
/// chapter ada kartu lanjut ke chapter berikutnya.
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView> {
  // Posisi awal & simpan posisi nyusul di #14.
  int _chapter = 0;

  /// Seberapa jauh chapter ini udah di-scroll, 0..1.
  final _fraction = ValueNotifier<double>(0);

  @override
  void dispose() {
    _fraction.dispose();
    super.dispose();
  }

  void _goTo(int chapter) => setState(() {
    _chapter = chapter;
    _fraction.value = 0;
  });

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(readerBookProvider(widget.bookId));
    final c = context.stabilo;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (book) {
          AsyncData(value: final b?) when b.chapters.isNotEmpty => Column(
            children: [
              _TopBar(title: b.title),
              Expanded(
                child: _ChapterText(
                  key: ValueKey(b.chapters[_chapter].id),
                  book: b,
                  index: _chapter,
                  fraction: _fraction,
                  onNext: () => _goTo(_chapter + 1),
                ),
              ),
              _ProgressBar(book: b, index: _chapter, fraction: _fraction),
            ],
          ),
          AsyncLoading() => const _TopBar(title: ''),
          _ => Column(
            children: [
              const _TopBar(title: ''),
              Expanded(
                child: Center(
                  child: Text(
                    'Yah, bukunya gagal kebuka',
                    style: StabiloType.body.copyWith(color: c.ink2),
                  ),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Layout.topBar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: Row(
          spacing: 10,
          children: [
            CircleButton(
              semanticLabel: 'Balik ke rak',
              icon: AppIcons.back,
              onPressed: () => context.pop(),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.label,
              ),
            ),
            // Daftar isi (#17) & Aa (#18) nyusul; sementara mati.
            const Row(
              spacing: Space.s2,
              children: [
                CircleButton(
                  semanticLabel: 'Daftar isi',
                  icon: AppIcons.toc,
                  onPressed: null,
                ),
                CircleButton(
                  semanticLabel: 'Atur tampilan teks',
                  text: 'Aa',
                  onPressed: null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterText extends ConsumerStatefulWidget {
  const _ChapterText({
    super.key,
    required this.book,
    required this.index,
    required this.fraction,
    required this.onNext,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;
  final VoidCallback onNext;

  @override
  ConsumerState<_ChapterText> createState() => _ChapterTextState();
}

class _ChapterTextState extends ConsumerState<_ChapterText> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
  }

  void _track() {
    final p = _scroll.position;
    widget.fraction.value = p.maxScrollExtent <= 0
        ? 1
        : (p.pixels / p.maxScrollExtent).clamp(0, 1).toDouble();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final chapter = widget.book.chapters[widget.index];
    final next = widget.index + 1 < widget.book.chapters.length
        ? widget.book.chapters[widget.index + 1]
        : null;
    final paragraphs = ref.watch(chapterParagraphsProvider(chapter.id));
    final reading = StabiloType.forBrightness(
      StabiloType.reading,
      Theme.of(context).brightness,
    ).copyWith(color: c.ink);
    final gap = reading.fontSize!; // 1em antar paragraf

    final paras = switch (paragraphs) {
      AsyncData(:final value) => _withoutTitleHeading(value, chapter.title),
      _ => const <ReaderParagraph>[],
    };
    // Chapter pendek yang gak perlu di-scroll langsung dianggap kebaca.
    if (paragraphs is AsyncData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _track();
      });
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        Layout.margin,
        Space.s6,
        Layout.margin,
        Space.s2,
      ),
      itemCount: paras.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: _ChapterHeading(
              number: widget.index + 1,
              title: chapter.title,
            ),
          );
        }
        if (i == paras.length + 1) {
          return next == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _ChapterEnd(
                    number: widget.index + 1,
                    next: next,
                    nextNumber: widget.index + 2,
                    total: widget.book.chapters.length,
                    onNext: widget.onNext,
                  ),
                );
        }
        final p = paras[i - 1];
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: switch (p.type) {
            ParagraphType.paragraph => Text(p.text, style: reading),
            ParagraphType.heading => Semantics(
              header: true,
              child: Text(
                p.text,
                style: StabiloType.titleSm.copyWith(color: c.ink),
              ),
            ),
            ParagraphType.sceneBreak => Center(
              child: Text(
                '* * *',
                semanticsLabel: 'Pemisah adegan',
                style: StabiloType.label.copyWith(color: c.ink2),
              ),
            ),
          },
        );
      },
    );
  }

  /// Heading pertama yang isinya sama kayak judul chapter udah ditampilin di
  /// [_ChapterHeading], gak usah dobel.
  static List<ReaderParagraph> _withoutTitleHeading(
    List<ReaderParagraph> paras,
    String title,
  ) {
    String norm(String s) =>
        s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final first = paras.firstOrNull;
    return first != null &&
            first.type == ParagraphType.heading &&
            norm(first.text) == norm(title)
        ? paras.sublist(1)
        : paras;
  }
}

class _ChapterHeading extends StatelessWidget {
  const _ChapterHeading({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Container(
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Text(
            'Bab $number',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: c.onAccent,
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: StabiloType.titleMd.copyWith(color: c.ink),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterEnd extends StatelessWidget {
  const _ChapterEnd({
    required this.number,
    required this.next,
    required this.nextNumber,
    required this.total,
    required this.onNext,
  });

  final int number;
  final ChapterInfo next;
  final int nextNumber;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      container: true,
      label: 'Bab selesai',
      child: Container(
        padding: const EdgeInsets.all(Space.s5),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: light ? c.track : c.muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    AppIcon(AppIcons.check, size: 12, color: c.ink),
                    Text(
                      'Bab $number kelar',
                      style: StabiloType.tag.copyWith(color: c.ink, height: 1),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s1,
              children: [
                Text(
                  'Lanjut ke ${next.title}?',
                  style: StabiloType.titleMd.copyWith(color: c.ink),
                ),
                Text(
                  'Bab $nextNumber dari $total · ±${readingMinutes(next.chars)} menit',
                  style: StabiloType.caption.copyWith(
                    fontSize: 14,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
            AppButton.primary(
              label: 'Lanjut, gas',
              icon: AppIcons.next,
              onPressed: onNext,
            ),
            Center(
              child: TextButton(
                onPressed: () => context.pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, Layout.touch),
                  foregroundColor: c.ink2,
                  textStyle: StabiloType.label.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Udahan dulu, balik ke rak'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.book,
    required this.index,
    required this.fraction,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final chapter = book.chapters[index];
    return Container(
      color: c.canvas,
      padding: EdgeInsets.fromLTRB(
        Layout.margin,
        Space.s3,
        Layout.margin,
        Space.s3 + MediaQuery.paddingOf(context).bottom,
      ),
      child: ValueListenableBuilder(
        valueListenable: fraction,
        builder: (context, f, _) {
          final progress = bookProgress(
            charOffset: chapter.charOffset,
            chapterChars: chapter.chars,
            fraction: f,
            totalChars: book.totalChars,
          );
          final done = f >= 0.999;
          final left = ((1 - f) * chapter.chars).round();
          return Row(
            spacing: Space.s3,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.full),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: c.track,
                    color: c.progressFill,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).floor()}%',
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                done
                    ? 'Bab ${index + 1} beres'
                    : '±${readingMinutes(left)} mnt lagi',
                style: StabiloType.caption.copyWith(color: c.ink2),
              ),
            ],
          );
        },
      ),
    );
  }
}
