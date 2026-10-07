import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/reader_view_model.dart';
import 'book_end_view.dart';
import 'toc_sheet.dart';

/// Halaman baca (board 03 Baca, 11 Akhir bab, 12 Akhir buku). Satu chapter per
/// layar; ujung chapter ada kartu lanjut ke chapter berikutnya, ujung bab
/// terakhir ke layar akhir buku.
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with WidgetsBindingObserver {
  late final ReadingProgressRepository _progress;

  /// Null sampai posisi tersimpan kebaca.
  int? _chapter;
  int? _chapterId;

  /// Paragraf paling atas yang keliatan; ini yang disimpen.
  int _paragraph = 0;

  /// Paragraf yang dituju pas buku dibuka lagi.
  int? _restoreTo;

  /// Seberapa jauh chapter ini udah di-scroll, 0..1.
  final _fraction = ValueNotifier<double>(0);

  /// Lagi nampilin layar akhir buku.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(readingProgressRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _progress.markOpened(widget.bookId).ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS bisa matiin app kapan aja pas di background.
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void dispose() {
    _save();
    WidgetsBinding.instance.removeObserver(this);
    _fraction.dispose();
    super.dispose();
  }

  void _save() {
    final chapterId = _chapterId;
    if (chapterId == null) return;
    _progress.save(widget.bookId, (
      chapterId: chapterId,
      paragraphIndex: _paragraph,
    )).ignore();
  }

  void _goTo(ReaderBook book, int chapter) => setState(() {
    _finished = false;
    _chapter = chapter;
    _chapterId = book.chapters[chapter].id;
    _paragraph = 0;
    _restoreTo = null;
    _fraction.value = 0;
    _save();
  });

  Future<void> _openToc(ReaderBook book) async {
    final i = _chapter!;
    final ch = book.chapters[i];
    final percent =
        (bookProgress(
                  charOffset: ch.charOffset,
                  chapterChars: ch.chars,
                  fraction: _fraction.value,
                  totalChars: book.totalChars,
                ) *
                100)
            .floor();
    final picked = await showTocSheet(
      context,
      book: book,
      current: i,
      percent: percent,
    );
    if (picked != null && picked != _chapter && mounted) _goTo(book, picked);
  }

  /// Sekali aja: buka di chapter & paragraf tersimpan (atau bab 1).
  void _start(ReaderBook book, ReadingPosition? saved) {
    final i = saved == null
        ? -1
        : book.chapters.indexWhere((c) => c.id == saved.chapterId);
    _chapter = i < 0 ? 0 : i;
    _chapterId = book.chapters[_chapter!].id;
    _paragraph = i < 0 ? 0 : saved!.paragraphIndex;
    _restoreTo = i < 0 ? null : saved!.paragraphIndex;
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(readerBookProvider(widget.bookId));
    final saved = ref.watch(readingPositionProvider(widget.bookId));
    final c = context.stabilo;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch ((book, saved)) {
          (AsyncData(value: final b?), AsyncData(value: final pos))
              when b.chapters.isNotEmpty =>
            () {
              if (_chapter == null) _start(b, pos);
              final i = _chapter!;
              if (_finished) {
                return BookEndView(
                  book: b,
                  onClose: () => context.pop(),
                  onRestart: () => _goTo(b, 0),
                );
              }
              return Column(
                children: [
                  _TopBar(title: b.title, onToc: () => _openToc(b)),
                  Expanded(
                    child: _ChapterText(
                      key: ValueKey(b.chapters[i].id),
                      book: b,
                      index: i,
                      fraction: _fraction,
                      restoreTo: _restoreTo,
                      onPosition: (p) {
                        _paragraph = p;
                        _save();
                      },
                      onNext: i + 1 < b.chapters.length
                          ? () => _goTo(b, i + 1)
                          : () => setState(() => _finished = true),
                    ),
                  ),
                  _ProgressBar(book: b, index: i, fraction: _fraction),
                ],
              );
            }(),
          (AsyncLoading(), _) ||
          (_, AsyncLoading()) => const _TopBar(title: ''),
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
  const _TopBar({required this.title, this.onToc});

  final String title;

  /// Null = daftar isi belum bisa dibuka (buku belum kebaca).
  final VoidCallback? onToc;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Layout.topBar,
      // Sama kayak header rak (board Baca pake 16; disamain biar tombolnya
      // sejajar sama rak & tepi teks bacaan).
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
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
            Row(
              spacing: Space.s2,
              children: [
                CircleButton(
                  semanticLabel: 'Daftar isi',
                  icon: AppIcons.toc,
                  onPressed: onToc,
                ),
                // Aa nyusul di #18; sementara mati.
                const CircleButton(
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
    required this.restoreTo,
    required this.onPosition,
    required this.onNext,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;

  /// Indeks paragraf yang langsung dituju pas kebuka (posisi tersimpan).
  final int? restoreTo;

  /// Paragraf paling atas yang keliatan, tiap scroll berhenti.
  final ValueChanged<int> onPosition;
  final VoidCallback onNext;

  @override
  ConsumerState<_ChapterText> createState() => _ChapterTextState();
}

class _ChapterTextState extends ConsumerState<_ChapterText> {
  final _scroll = ScrollController();

  /// Satu key per paragraf (indeks paragraf di DB) buat ngukur & lompat.
  // ponytail: satu chapter dirender utuh (Column), bukan lazy. Aman buat
  // chapter ratusan paragraf; ganti ke list yang bisa lompat ke item kalau
  // ada buku dengan chapter raksasa yang kerasa berat.
  final _keys = <int, GlobalKey>{};
  bool _restored = false;

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

  /// Paragraf pertama yang bawahnya masih di bawah tepi atas area baca.
  int? _firstVisible(List<ReaderParagraph> paras) {
    final area = context.findRenderObject() as RenderBox?;
    if (area == null || !area.hasSize) return null;
    final top = area.localToGlobal(Offset.zero).dy;
    for (final p in paras) {
      final box =
          _keys[p.index]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy + box.size.height > top + 1) {
        return p.index;
      }
    }
    return null;
  }

  void _restore() {
    final target = _keys[widget.restoreTo]?.currentContext;
    if (target != null) Scrollable.ensureVisible(target);
    if (_scroll.hasClients) _track();
    // Baru keliatan setelah di posisi yang bener (lihat AnimatedOpacity).
    setState(() => _restored = true);
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
    final loaded = paragraphs is AsyncData;
    final paras = switch (paragraphs) {
      AsyncData(:final value) => _withoutTitleHeading(value, chapter.title),
      _ => const <ReaderParagraph>[],
    };

    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        // Lompat ke posisi tersimpan sekali; chapter pendek yang gak perlu
        // di-scroll langsung dianggap kebaca.
        _restored ? _track() : _restore();
      });
    }

    // Isi disembunyiin sampe teksnya kebaca & udah lompat ke posisi
    // tersimpan, terus fade in. Tanpa ini keliatan kedip: mulai dari atas,
    // lompat ke tengah, kartu akhir bab nongol duluan.
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.contentFade;
    return AnimatedOpacity(
      opacity: _restored ? 1 : 0,
      duration: fade,
      curve: Curves.easeOut,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          final p = _firstVisible(paras);
          if (p != null) widget.onPosition(p);
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            Layout.margin,
            Space.s6,
            Layout.margin,
            Space.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: _ChapterHeading(
                  number: widget.index + 1,
                  title: chapter.title,
                ),
              ),
              for (final p in paras)
                Padding(
                  key: _keys.putIfAbsent(p.index, GlobalKey.new),
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
                ),
              // Kartu akhir bab baru muncul bareng teks, biar gak nongol di atas
              // terus kedorong ke bawah.
              if (loaded)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _ChapterEnd(
                    chapterId: chapter.id,
                    number: widget.index + 1,
                    next: next,
                    nextNumber: widget.index + 2,
                    total: widget.book.chapters.length,
                    onNext: widget.onNext,
                  ),
                ),
            ],
          ),
        ),
      ),
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

class _ChapterEnd extends ConsumerWidget {
  const _ChapterEnd({
    required this.chapterId,
    required this.number,
    required this.next,
    required this.nextNumber,
    required this.total,
    required this.onNext,
  });

  final int chapterId;
  final int number;

  /// Null = ini bab terakhir; tombolnya ke layar akhir buku.
  final ChapterInfo? next;
  final int nextNumber;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final translated = ref.watch(chapterTranslatedProvider(chapterId)).value;
    final next = this.next;
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
            Row(
              spacing: Space.s2,
              children: [
                Container(
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
                        style: StabiloType.tag.copyWith(
                          color: c.ink,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (translated != null && translated > 0)
                  Text(
                    '$translated paragraf diterjemahin',
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s1,
              children: [
                Text(
                  next == null
                      ? 'Itu tadi bab terakhir!'
                      : 'Lanjut ke ${next.title}?',
                  style: StabiloType.titleMd.copyWith(color: c.ink),
                ),
                Text(
                  next == null
                      ? 'Bukunya kelar, tinggal satu tap lagi'
                      : 'Bab $nextNumber dari $total · ±${readingMinutes(next.chars)} menit',
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
