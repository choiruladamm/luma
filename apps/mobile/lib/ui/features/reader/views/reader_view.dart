import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../routing/router.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/widgets/toast.dart';
import '../../chat/view_models/chat_entry.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../view_models/reader_view_model.dart';
import '../../../../domain/book_search.dart';
import '../../../../domain/models/book_search.dart';
import 'aa_sheet.dart';
import 'book_search_sheet.dart';
import 'reader_menu.dart';
import 'book_end_view.dart';
import 'meaning_sheet.dart';
import 'reader_capsule.dart';
import 'toc_sheet.dart';
import 'chapter_text.dart';
import 'reader_overlay.dart';
import 'reader_system_ui.dart';
import 'reader_types.dart';

/// Halaman baca (board 03 Baca, 11 Akhir bab, 12 Akhir buku). Satu chapter per
/// layar; ujung chapter ada kartu lanjut ke chapter berikutnya, ujung bab
/// terakhir ke layar akhir buku.
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({
    super.key,
    required this.bookId,
    this.sourceVisit,
    this.sourceOriginalPosition,
    this.onContinueReading,
  });

  final int bookId;

  /// Verified source visit: rendering/navigation only, never reading activity.
  final ChatSource? sourceVisit;
  final ReadingPosition? sourceOriginalPosition;
  final VoidCallback? onContinueReading;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ReadingProgressRepository _progress;
  late final _now = ref.read(readerNowProvider);
  late final _clock = ReadingClock(_now());
  late final _chrome = ReaderChrome(vsync: this);
  late final _ui = ReaderSystemUi(
    isVisit: widget.sourceVisit != null,
    barsShown: () => _chrome.visible.value || !_prefs.hideStatusBar,
    offReader: () => _offReader > 0,
    mounted: () => mounted,
  );

  /// Setelan Aa terakhir (status bar, garis progres, gaya teks).
  ReaderPrefs _prefs = const ReaderPrefs();

  /// Null sampai posisi tersimpan kebaca.
  int? _chapter;
  int? _chapterId;

  /// Paragraf paling atas yang keliatan + bagiannya yang udah lewat garis
  /// atas; ini yang disimpen.
  Spot _spot = (index: 0, offset: 0);

  /// Titik yang dituju pas buku dibuka lagi.
  Spot? _restoreTo;

  /// Nulis posisi ke DB nunggu scroll diem bentar, bukan tiap scroll.
  Timer? _saveLater;
  static const _saveDelay = Duration(milliseconds: 500);

  /// Seberapa jauh chapter ini udah di-scroll, 0..1.
  final _fraction = ValueNotifier<double>(0);

  /// Buku yang lagi dibaca, buat ngubah [_fraction] jadi posisi karakter.
  ReaderBook? _book;

  /// Posisi karakter (absolut di buku) waktu terakhir waktu baca disimpen:
  /// awal potongan sesi berikutnya. Null sampai posisi pertama kebaca.
  int? _lastChar;

  /// Lagi nampilin layar akhir buku.
  bool _finished = false;

  /// Sheet dari kapsul (daftar isi / Aa) lagi kebuka: kapsul atas tetep
  /// keliatan di atas scrim, tombolnya kuning. [_lastSheet] nentuin warna
  /// scrim, termasuk pas lagi fade out.
  bool _sheetOpen = false;
  ReaderSheet _lastSheet = ReaderSheet.toc;

  /// Teks bab yang lagi tampil; diganti tiap pindah bab.
  var _text = GlobalKey<ChapterTextState>();

  /// Grup yang lagi dibuka di sheet Artinya.
  int? _openGroup;

  /// Mode Cari kata (docs/book-search.md): hasil yang dibuka lewat sheet.
  /// Null = gak lagi nyari.
  SearchMode? _search;

  /// Abis lompat dari hasil, posisi baca gak ikut pindah sampe user scroll
  /// 1 layar dari situ ([_onSearchRead]).
  bool _jumpHeld = false;

  /// User lagi scroll: navigator hasil ngecil, balik penuh
  /// [Motion.searchRegrow] abis berhenti.
  final _scrolling = ValueNotifier<bool>(false);
  Timer? _regrow;

  /// Posisi scroll daftar hasil di sheet, diinget pas balik dari navigator.
  double _listOffset = 0;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(readingProgressRepositoryProvider);
    if (widget.sourceVisit == null) _clock.resume(_now());
    WidgetsBinding.instance.addObserver(this);
    if (widget.sourceVisit == null) {
      _progress.markOpened(widget.bookId).ignore();
    }
    _chrome.visible.addListener(_ui.sync);
    _fraction.addListener(_anchor);
    _ui.attach();
  }

  int _offReader = 0;
  bool _openingChat = false;
  Future<void> _pendingSave = Future.value();
  Timer? _chatHintTimer;
  bool _chatHintChecked = false, _chatHintVisible = false;

  void _showChatHintOnce() {
    if (_chatHintChecked || widget.sourceVisit != null) return;
    _chatHintChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final settings = ref.read(settingsRepositoryProvider);
        if (await settings.chatHintSeen() || !mounted || _offReader > 0) return;
        await settings.markChatHintSeen();
        if (!mounted || _offReader > 0) return;
        setState(() => _chatHintVisible = true);
        _chatHintTimer = Timer(Motion.capsuleIntro, () {
          if (mounted) setState(() => _chatHintVisible = false);
        });
      } catch (_) {
        // A failed hint must not prevent the book from opening.
      }
    });
  }

  /// Posisi pertama yang kebaca (buku kebuka di titik tersimpan) = awal
  /// potongan sesi pertama.
  void _anchor() => _lastChar ??= _charNow();

  /// Posisi karakter sekarang; null sebelum bukunya kebaca.
  int? _charNow() {
    final book = _book, i = _chapter;
    if (book == null || i == null) return null;
    final ch = book.chapters[i];
    return charPosition(
      charOffset: ch.charOffset,
      chapterChars: ch.chars,
      fraction: _fraction.value,
    );
  }

  /// Layar lain (Bedahin, Pengaturan) bukan layar baca: di Android bar
  /// sistem tampil selama di sana, balik ngikutin kapsul sesudahnya.
  Future<T?> _pushOffReader<T>(String route, {Object? extra}) async {
    _saveLater?.cancel();
    _clock.pause(_now());
    _offReader++;
    try {
      await _save(force: true);
      if (!mounted) return null;
      _ui.edgeToEdge();
      final result = await context.push<T>(route, extra: extra);
      if (result == ReaderReturn.reading &&
          mounted &&
          widget.sourceVisit == null) {
        final saved = await _progress.load(widget.bookId);
        if (saved != null &&
            mounted &&
            _book != null &&
            (saved.chapterId != _chapterId ||
                saved.paragraphIndex != _spot.index ||
                saved.paragraphOffset != _spot.offset)) {
          setState(() {
            _chapter = null;
            _start(_book!, saved);
            _text = GlobalKey();
            _lastChar = null;
            _finished = false;
            _chrome.show();
          });
        }
      }
      return result;
    } finally {
      // Wait for the router to remove the outgoing page before unwinding a sheet.
      await WidgetsBinding.instance.endOfFrame;
      _offReader--;
      if (mounted && _offReader == 0) {
        if (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          if (widget.sourceVisit == null) _clock.resume(_now());
        }
        _ui.sync();
      }
    }
  }

  ChatLaunchContext? _chatContext() {
    final book = _book, chapter = _chapterId;
    if (book == null || chapter == null) return null;
    return ChatLaunchContext(
      book: (bookId: book.id, contentRevision: book.contentRevision),
      returnPosition: (
        chapterId: chapter,
        paragraphIndex: _spot.index,
        paragraphOffset: _spot.offset,
      ),
    );
  }

  Future<ReaderReturn?> _openChat({
    GroupRef? group,
    String? translation,
  }) async {
    if (_openingChat || widget.sourceVisit != null) return null;
    if (group == null) _text.currentState?.stopAndReportPosition();
    final initial = _chatContext();
    if (initial == null) return null;
    // Tanpa setState: tombol Ngobrol gak boleh kedip abu pas layar pindah.
    _openingChat = true;
    try {
      ChatQuote? quote;
      if (group != null) {
        final source = await ref.read(
          chatEntryQuoteProvider((bookId: widget.bookId, group: group)).future,
        );
        if (source.anchors.any((a) => a.book != initial.book)) {
          throw const FormatException('Isi buku berubah');
        }
        quote = ChatQuote(
          anchors: source.anchors,
          translation: translation,
          chapterTitle: source.chapterTitle,
        );
      }
      if (!mounted) return null;
      final launch = ChatLaunchContext(
        book: initial.book,
        returnPosition: initial.returnPosition,
        origin: group == null
            ? ChatLaunchOrigin.reader
            : ChatLaunchOrigin.meaning,
        quote: quote,
      );
      return await _pushOffReader<ReaderReturn>(
        Routes.chat(widget.bookId),
        extra: launch,
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          'Obrolan belum bisa dibuka. Coba buka ulang bukunya.',
        );
      }
      return null;
    } finally {
      _openingChat = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_offReader == 0 && widget.sourceVisit == null) _clock.resume(_now());
      return;
    }
    _clock.pause(_now());
    // OS bisa matiin app kapan aja pas di background: simpen sekarang.
    _saveLater?.cancel();
    _save().ignore();
  }

  @override
  void dispose() {
    _saveLater?.cancel();
    _chatHintTimer?.cancel();
    _regrow?.cancel();
    _scrolling.dispose();
    _save().ignore();
    WidgetsBinding.instance.removeObserver(this);
    _ui.release();
    _chrome.dispose();
    _fraction.dispose();
    super.dispose();
  }

  /// Waktu baca aktif sejak simpan terakhir → total buku + satu potongan sesi
  /// di bab dan posisi sekarang. Pindah bab harus manggil ini SEBELUM state
  /// bab diganti, biar potongannya masuk ke bab yang bener dan lompatan lewat
  /// daftar isi gak ikut keitung sebagai karakter terbaca.
  Future<void> _flushReading() async {
    if (widget.sourceVisit != null) return;
    final now = _now();
    final seconds = _clock.take(now);
    if (seconds <= 0) return;
    final chapterId = _chapterId, end = _charNow();
    final span = chapterId == null || end == null
        ? null
        : (chapterId: chapterId, startChar: _lastChar ?? end, endChar: end);
    if (end != null) _lastChar = end;
    await _progress.addReadingTime(widget.bookId, seconds, at: now, span: span);
  }

  Future<void> _save({bool force = false}) {
    if (widget.sourceVisit != null || _offReader > 0 && !force) {
      return Future.value();
    }
    final chapterId = _chapterId;
    final position = (
      chapterId: chapterId ?? 0,
      paragraphIndex: _spot.index,
      paragraphOffset: _spot.offset,
    );
    // Abis lompat dari hasil cari: waktu baca tetep dicatat, posisi nggak.
    final hold = _jumpHeld && !force;
    final previous = _pendingSave;
    final reading = _flushReading();
    return _pendingSave = () async {
      await Future.wait([previous, reading]);
      if (chapterId != null && !hold) {
        await _progress.save(widget.bookId, position);
      }
    }();
  }

  void _goTo(ReaderBook book, int chapter) {
    _flushReading().ignore(); // masih di bab lama
    setState(() {
      _text = GlobalKey();
      _chrome.show(); // awal bab
      _finished = false;
      _chapter = chapter;
      _chapterId = book.chapters[chapter].id;
      _lastChar = book.chapters[chapter].charOffset;
      _jumpHeld = false;
      _spot = (index: 0, offset: 0);
      _restoreTo = null;
      _fraction.value = 0;
      _saveLater?.cancel();
      _save().ignore();
    });
  }

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
    final picked = await _withSheet(
      ReaderSheet.toc,
      () => showTocSheet(context, book: book, current: i, percent: percent),
    );
    if (picked != null && picked != _chapter && mounted) _goTo(book, picked);
  }

  /// Menu ⋯: Cari kata (atau "Lihat hasil" pas lagi mode cari) / Atur
  /// tampilan. Layar diredupin tipis, ⋯ kuning.
  Future<void> _openMenu(ReaderBook book) async {
    final action = await _withSheet(
      ReaderSheet.menu,
      () => showReaderMenu(context, resultsFor: _search?.raw),
    );
    if (!mounted) return;
    switch (action) {
      case ReaderMenuAction.search || ReaderMenuAction.results:
        await _openSearch(book);
      case ReaderMenuAction.display:
        await _withSheet(ReaderSheet.aa, () => showAaSheet(context));
      case null:
    }
  }

  /// Sheet Cari kata. Pas lagi mode cari kebuka dengan kata + posisi daftar
  /// yang sama. Hasil yang di-tap → [_enterSearch].
  Future<void> _openSearch(ReaderBook book) async {
    final mode = _search;
    if (mode == null) _listOffset = 0;
    final pick = await showBookSearchSheet(
      context,
      bookId: book.id,
      currentChapterId: _chapterId,
      initialQuery: mode?.raw,
      initialScrollOffset: mode == null ? 0 : _listOffset,
      onScrollOffset: (o) => _listOffset = o,
    );
    if (pick != null && mounted) _enterSearch(book, pick);
  }

  /// Hasil di-tap: mode cari nyala, lompat ke situ. Posisi sebelum nyari
  /// (buat "Balik ke posisi tadi?") dicatat sekali, bukan tiap ganti kata.
  void _enterSearch(ReaderBook book, BookSearchPick pick) {
    final query = BookSearchQuery.parse(pick.query);
    final chapterId = _chapterId;
    if (query == null || chapterId == null) return;
    final hits = [
      for (final c in pick.result.chapters)
        for (final h in c.hits) (hit: h, chapter: c.title),
    ];
    final i = hits.indexWhere(
      (e) =>
          e.hit.chapterId == pick.hit.chapterId &&
          e.hit.paragraphIndex == pick.hit.paragraphIndex,
    );
    if (i < 0) return;
    final back =
        _search?.back ??
        (
          chapterId: chapterId,
          paragraphIndex: _spot.index,
          paragraphOffset: _spot.offset,
        );
    _search = SearchMode(
      raw: pick.query,
      query: query,
      hits: hits,
      truncated: pick.result.truncated,
      back: back,
    );
    _jumpToHit(book, i);
  }

  /// Lompat ke hasil ke-[i]: paragrafnya ke ±⅓ tinggi layar, kedip, kata
  /// cocok di-stabilo. Bab lain = pindah bab dulu. Posisi baca ditahan.
  void _jumpToHit(ReaderBook book, int i) {
    final mode = _search;
    if (mode == null) return;
    final hit = mode.hits[i].hit;
    final target = book.chapters.indexWhere((c) => c.id == hit.chapterId);
    if (target < 0) return;
    _regrow?.cancel();
    _scrolling.value = false;
    _saveLater?.cancel();
    _flushReading().ignore(); // waktu baca ke tempat lama, bukan loncatannya
    _lastChar = null;
    _jumpHeld = true;
    setState(() {
      mode.index = i;
      if (target == _chapter) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _text.currentState?.jumpToParagraph(hit.paragraphIndex);
        });
      } else {
        _text = GlobalKey();
        _chapter = target;
        _chapterId = hit.chapterId;
        _spot = (index: hit.paragraphIndex, offset: 0);
        _restoreTo = _spot;
        _fraction.value = 0;
        _finished = false;
      }
    });
  }

  void _stepSearch(ReaderBook book, int delta) {
    final mode = _search;
    if (mode == null) return;
    final i = mode.index + delta;
    if (i >= 0 && i < mode.hits.length) _jumpToHit(book, i);
  }

  /// × di navigator: keluar mode cari, tawarin balik ke posisi sebelum nyari.
  void _closeSearch() {
    final mode = _search;
    if (mode == null) return;
    _regrow?.cancel();
    _scrolling.value = false;
    setState(() => _search = null);
    final back = mode.back;
    if (back == null) return;
    showToast(
      context,
      'Balik ke posisi tadi?',
      actionLabel: 'Balik',
      duration: Motion.searchToast,
      onAction: () => _returnTo(back),
    );
  }

  /// "Balik": ke posisi sebelum nyari, lanjut baca biasa dari situ.
  void _returnTo(ReadingPosition back) {
    final book = _book;
    if (book == null || !mounted) return;
    final i = book.chapters.indexWhere((c) => c.id == back.chapterId);
    if (i < 0) return;
    _flushReading().ignore();
    setState(() {
      _text = GlobalKey();
      _chapter = i;
      _chapterId = back.chapterId;
      _spot = (index: back.paragraphIndex, offset: back.paragraphOffset);
      _restoreTo = _spot;
      _fraction.value = 0;
      _lastChar = null;
      _finished = false;
      _jumpHeld = false;
      _saveLater?.cancel();
    });
    _save().ignore();
  }

  /// Scroll jari mulai / berhenti: navigator ngecil / balik penuh.
  void _onScrollActive(bool active) {
    if (_search == null) return;
    _regrow?.cancel();
    if (active) {
      _scrolling.value = true;
    } else {
      _regrow = Timer(Motion.searchRegrow, () => _scrolling.value = false);
    }
  }

  /// User udah scroll 1 layar dari hasil: sekarang baru itu posisi bacanya.
  void _onSearchRead() {
    if (!_jumpHeld) return;
    _jumpHeld = false;
    _save().ignore();
  }

  /// Tap paragraf → sheet Artinya buat grupnya. Kapsul ngumpet, halaman naik
  /// barengan sheet. Ditutup: kalau udah pake "Lanjut", halaman diem di grup
  /// terakhir; kalau cuma satu grup, balik ke posisi sebelum sheet dibuka.
  Future<void> _openMeaning(ReaderParagraph p) async {
    if (widget.sourceVisit != null) return;
    final g = p.groupIndex;
    final text = _text.currentState;
    final chapterId = _chapterId;
    if (g == null || text == null || chapterId == null) return;
    _chrome.hide();
    final before = text.pixels;
    final screen = MediaQuery.sizeOf(context).height;
    var sheetTop = screen;
    var opened = 1;
    final group = ValueNotifier<GroupRef>((
      chapterId: chapterId,
      groupIndex: g,
    ));
    setState(() => _openGroup = g);

    await showMeaningSheet(
      context,
      group: group,
      hasNext: (r) => text.groupAfter(r.groupIndex) != null,
      onNext: () {
        final next = text.groupAfter(group.value.groupIndex);
        if (next == null) return;
        opened++;
        group.value = (chapterId: chapterId, groupIndex: next);
        setState(() => _openGroup = next);
        // Abis highlight pindah & keukur, grup berikutnya naik ke atas sheet.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await text.unpinGroup(animate: false);
          await text.showGroupAbove(next, sheetTop);
          text.pinGroup(next, sheetTop);
        });
      },
      onHeight: (h) {
        sheetTop = screen - h;
        unawaited(() async {
          await text.showGroupAtTop(group.value.groupIndex);
          text.pinGroup(group.value.groupIndex, sheetTop);
        }());
      },
      onProgress: (t) => text.followProgress(t, sheetTop),
      // Overlay langsung dibuang pas sheet mulai turun: yang kebuka di bawah
      // sheet itu card halaman asli, dan dua versi teks gak boleh numpuk.
      onClosing: () => unawaited(text.unpinGroup(animate: false)),
      onSettings: () {
        Navigator.of(context).pop();
        unawaited(_pushOffReader<void>(Routes.settings));
      },
      // Sheet tetep di bawah layar Bedahin. "Balik baca" (`pop(ReaderReturn.reading)`) =
      // sheet-nya ikut ditutup, langsung ke halaman.
      onChat: (g, translation) async {
        final result = await _openChat(group: g, translation: translation);
        if (result == ReaderReturn.reading && mounted) {
          Navigator.of(context).pop();
        }
      },
      onBreakdown: (g) async {
        final read = await _pushOffReader<ReaderReturn>(
          Routes.breakdown(widget.bookId, g.chapterId, g.groupIndex),
          extra: _chatContext(),
        );
        if (read == ReaderReturn.reading && mounted) {
          Navigator.of(context).pop();
        }
      },
    );
    group.dispose();
    if (!mounted) return;
    await text.unpinGroup();
    if (!mounted) return;
    setState(() => _openGroup = null);
    if (opened == 1) {
      await text.scrollBack(before);
    } else {
      text.reportPosition();
    }
  }

  /// Buka sheet dari kapsul: kapsul dimunculin & tombolnya kuning selama
  /// sheet kebuka.
  Future<T?> _withSheet<T>(
    ReaderSheet sheet,
    Future<T?> Function() open,
  ) async {
    _chrome.show();
    setState(() {
      _sheetOpen = true;
      _lastSheet = sheet;
    });
    final result = await open();
    if (mounted) setState(() => _sheetOpen = false);
    return result;
  }

  /// Sekali aja: buka di chapter & paragraf tersimpan (atau bab 1).
  void _start(ReaderBook book, ReadingPosition? saved) {
    final source = widget.sourceVisit?.anchors.first;
    if (source != null) {
      saved = (
        chapterId: source.chapterId,
        paragraphIndex: source.paragraphIndex,
        paragraphOffset: 0,
      );
    }
    final i = saved == null
        ? -1
        : book.chapters.indexWhere((c) => c.id == saved!.chapterId);
    _chapter = i < 0 ? 0 : i;
    _chapterId = book.chapters[_chapter!].id;
    if (i < 0) return;
    _spot = (index: saved!.paragraphIndex, offset: saved.paragraphOffset);
    _restoreTo = _spot;
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(readerBookProvider(widget.bookId));
    final saved = ref.watch(readingPositionProvider(widget.bookId));
    _chrome.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    ref.listen(readerPrefsProvider, (_, _) => _ui.sync());
    return Scaffold(
      body: Listener(
        // Scroll & tap sama-sama mulai dari sini.
        onPointerDown: (_) {
          if (widget.sourceVisit == null) _clock.interact(_now());
        },
        child: switch ((book, saved)) {
          (AsyncData(value: final b?), AsyncData(value: final pos))
              when b.chapters.isNotEmpty =>
            () {
              _book = b;
              final source = widget.sourceVisit;
              if (source != null &&
                  source.anchors.any(
                    (a) =>
                        a.book !=
                            (
                              bookId: b.id,
                              contentRevision: b.contentRevision,
                            ) ||
                        !b.chapters.any((c) => c.id == a.chapterId),
                  )) {
                return _bare('Sumber ini udah gak tersedia.');
              }
              if (_chapter == null) _start(b, pos);
              final i = _chapter!;
              if (_finished) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: SafeArea(
                        bottom: false,
                        child: BookEndView(
                          book: b,
                          onClose: () => context.pop(),
                          onRestart: () => _goTo(b, 0),
                        ),
                      ),
                    ),
                    if (_prefs.showProgressLine)
                      const ReaderProgressLine(progress: 1),
                  ],
                );
              }
              final ch = b.chapters[i];
              final original = widget.sourceVisit == null
                  ? pos
                  : widget.sourceOriginalPosition;
              final savedChapter = original == null
                  ? null
                  : b.chapters
                        .where((chapter) => chapter.id == original.chapterId)
                        .firstOrNull;
              final savedLabel = savedChapter == null
                  ? 'Lagi ngintip · belum ada progres baca'
                  : 'Lagi ngintip · progres masih ${savedChapter.title} · Paragraf ${(original?.paragraphIndex ?? 0) + 1}';
              final content = ref.watch(chapterParagraphsProvider(ch.id));
              final chatReady = content.asData?.value.isNotEmpty ?? false;
              if (chatReady) _showChatHintOnce();
              return Stack(
                children: [
                  Positioned.fill(
                    child: ChapterText(
                      key: _text,
                      book: b,
                      index: i,
                      fraction: _fraction,
                      chrome: _chrome,
                      prefs: _prefs,
                      restoreTo: _restoreTo,
                      sourceVisit: widget.sourceVisit,
                      onPosition: (spot) {
                        _spot = spot;
                        if (widget.sourceVisit == null) {
                          _saveLater?.cancel();
                          _saveLater = Timer(
                            _saveDelay,
                            () => _save().ignore(),
                          );
                        }
                      },
                      onParagraphTap: _openMeaning,
                      openGroup: _openGroup,
                      search: _search == null
                          ? null
                          : SearchMarks(
                              query: _search!.query,
                              chapterId:
                                  _search!.hits[_search!.index].hit.chapterId,
                              paragraph: _search!
                                  .hits[_search!.index]
                                  .hit
                                  .paragraphIndex,
                            ),
                      flashSearch: _search != null,
                      onScrollActive: _onScrollActive,
                      onSearchRead: _onSearchRead,
                      onNext: i + 1 < b.chapters.length
                          ? () => _goTo(b, i + 1)
                          : () {
                              if (widget.sourceVisit != null) {
                                context.pop();
                                return;
                              }
                              // Posisi tersimpan = ujung buku, rak: "Kelar!".
                              final last = _text.currentState?.lastParagraph;
                              if (last != null) {
                                _spot = (index: last.index, offset: 1);
                              }
                              _save()
                                  .ignore(); // waktu baca terbaru buat rekapnya
                              _progress.markFinished(widget.bookId).ignore();
                              _chrome.show(); // status bar balik
                              setState(() => _finished = true);
                            },
                    ),
                  ),
                  Positioned.fill(
                    child: ReaderOverlay(
                      book: b,
                      chapter: ch,
                      fraction: _fraction,
                      chrome: _chrome,
                      prefs: _prefs,
                      sheetOpen: _sheetOpen,
                      lastSheet: _lastSheet,
                      search: _search,
                      scrolling: _scrolling,
                      chatReady: chatReady,
                      chatHintVisible: _chatHintVisible,
                      isVisit: widget.sourceVisit != null,
                      visitLabel: savedLabel,
                      onBack: () => context.pop(),
                      onToc: () => _openToc(b),
                      onMore: () => _openMenu(b),
                      onChat: () => _openChat(),
                      onStepSearch: (delta) => _stepSearch(b, delta),
                      onOpenSearch: () => _openSearch(b),
                      onCloseSearch: _closeSearch,
                      onContinueReading: widget.onContinueReading,
                    ),
                  ),
                ],
              );
            }(),
          (AsyncLoading(), _) || (_, AsyncLoading()) => _bare(),
          _ => _bare('Yah, bukunya gagal kebuka'),
        },
      ),
    );
  }

  /// Belum ada buku buat ditampilin: kapsul atas buat balik doang.
  Widget _bare([String? message]) => Stack(
    children: [
      if (message != null)
        Center(
          child: Text(
            message,
            style: StabiloType.body.copyWith(color: context.stabilo.ink2),
          ),
        ),
      Positioned.fill(
        child: ReaderCapsules(
          chrome: _chrome,
          top: ReaderTopCapsule(title: '', onBack: () => context.pop()),
        ),
      ),
    ],
  );
}
