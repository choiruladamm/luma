import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/edge_fade.dart';
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
import 'chapter_end.dart';
import 'paragraph_text.dart';
import 'reader_overlay.dart';
import 'chapter_heading.dart';
import 'reader_types.dart';
import 'scrim_hole.dart';

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
  var _text = GlobalKey<_ChapterTextState>();

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
    _chrome.visible.addListener(_syncStatusBar);
    _fraction.addListener(_anchor);
    if (_android && widget.sourceVisit == null) {
      // Bar yang kebuka swipe tepi ngumpet lagi sesudah jeda, kalau memang
      // harusnya ngumpet.
      SystemChrome.setSystemUIChangeCallback((visible) async {
        if (!visible || !mounted) return;
        _rehide?.cancel();
        _rehide = Timer(const Duration(seconds: 2), _syncStatusBar);
      });
    }
  }

  int _offReader = 0;
  bool _openingChat = false;
  Future<void> _pendingSave = Future.value();
  Timer? _rehide;
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

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

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
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        _syncStatusBar();
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

  /// Status bar ngumpet bareng kapsul. Android: navbar ikut ngumpet
  /// (immersive sticky, muncul sebentar kalau di-swipe). iOS: bar bawah
  /// (home indicator) dibiarin.
  void _syncStatusBar() {
    if (_offReader > 0 || widget.sourceVisit != null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }
    final show = _chrome.visible.value || !_prefs.hideStatusBar;
    if (_android) {
      SystemChrome.setEnabledSystemUIMode(
        show ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
      return;
    }
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: show ? SystemUiOverlay.values : const [SystemUiOverlay.bottom],
    );
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
    _rehide?.cancel();
    _chatHintTimer?.cancel();
    _regrow?.cancel();
    _scrolling.dispose();
    if (_android && widget.sourceVisit == null) {
      SystemChrome.setSystemUIChangeCallback(null);
    }
    _save().ignore();
    WidgetsBinding.instance.removeObserver(this);
    if (_android) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
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
    ref.listen(readerPrefsProvider, (_, _) => _syncStatusBar());
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
                    child: _ChapterText(
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
                              final last =
                                  _text.currentState?._paras.lastOrNull;
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

class _ChapterText extends ConsumerStatefulWidget {
  const _ChapterText({
    super.key,
    required this.book,
    required this.index,
    required this.fraction,
    required this.chrome,
    required this.prefs,
    required this.restoreTo,
    required this.onPosition,
    required this.onParagraphTap,
    required this.onNext,
    this.openGroup,
    this.sourceVisit,
    this.search,
    this.flashSearch = false,
    this.onScrollActive,
    this.onSearchRead,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;
  final ReaderChrome chrome;
  final ReaderPrefs prefs;

  /// Titik yang langsung dituju pas kebuka (posisi tersimpan).
  final Spot? restoreTo;

  /// Titik paling atas yang keliatan, tiap user selesai scroll.
  final ValueChanged<Spot> onPosition;

  /// Tap paragraf → sheet Artinya.
  final ValueChanged<ReaderParagraph> onParagraphTap;

  /// Grup yang lagi dibuka di sheet Artinya: distabilo, scrim dibolongin di
  /// situ.
  final int? openGroup;
  final ChatSource? sourceVisit;
  final VoidCallback onNext;

  /// Mode Cari kata: kata cocok di-stabilo di semua paragraf bab ini.
  final SearchMarks? search;

  /// Lagi mode cari: kedatangan di [restoreTo] = lompat dari hasil (kedip
  /// paragraf), bukan "Lanjut baca".
  final bool flashSearch;

  /// Scroll jari mulai (true) / berhenti (false).
  final ValueChanged<bool>? onScrollActive;

  /// User udah scroll 1 layar dari paragraf hasil.
  final VoidCallback? onSearchRead;

  @override
  ConsumerState<_ChapterText> createState() => _ChapterTextState();
}

class _ChapterTextState extends ConsumerState<_ChapterText>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  /// Lanjut baca: kotak grup tempat posisi tersimpan (koordinat isi bab),
  /// dikasih kilatan stabilo sekali.
  Rect? _mark;
  final _contentKey = GlobalKey();
  late final _flash = AnimationController(vsync: this, duration: Motion.flash)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _mark = null);
    });
  Timer? _introTimer;
  Timer? _markTimer;

  /// 0 → 60% → 0 (board: tahan di puncak, turun pelan).
  static final _flashCurve = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 6),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween(1), weight: 40),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 42,
    ),
  ]);

  /// Satu key per paragraf (indeks paragraf di DB) buat ngukur & lompat.
  // ponytail: satu chapter dirender utuh (Column), bukan lazy. Aman buat
  // chapter ratusan paragraf; ganti ke list yang bisa lompat ke item kalau
  // ada buku dengan chapter raksasa yang kerasa berat.
  final _keys = <int, GlobalKey>{};
  bool _restored = false;

  /// Scroll dari jari (bukan lompatan restore) yang belum dilaporin.
  bool _userScrolled = false;

  /// Posisi scroll waktu lompat dari hasil cari; null = gak lagi nunggu.
  double? _searchAnchor;

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

  RenderBox? _box(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box : null;
  }

  /// Paragraf paling atas yang keliatan di bawah safe area atas, plus bagian
  /// paragraf itu yang udah lewat garis tersebut.
  Spot? _topSpot(List<ReaderParagraph> paras) {
    final area = context.findRenderObject() as RenderBox?;
    if (area == null || !area.hasSize || paras.isEmpty) return null;
    final line = math.max(
      area.localToGlobal(Offset.zero).dy,
      MediaQuery.paddingOf(context).top,
    );
    for (final p in paras) {
      final box = _box(p.index);
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      if (top + h > line + 0.5) {
        return (index: p.index, offset: ((line - top) / h).clamp(0.0, 1.0));
      }
    }
    // Udah lewat semua paragraf (kartu akhir bab): akhir paragraf terakhir.
    return (index: paras.last.index, offset: 1);
  }

  /// Kapsul ngikutin scroll dari jari. Awal bab (80pt pertama) & akhir bab
  /// (paragraf terakhir keliatan) kapsulnya muncul sendiri.
  void _moveChrome(ScrollUpdateNotification n, List<ReaderParagraph> paras) {
    final last = paras.isEmpty ? null : _box(paras.last.index);
    final atEnd =
        last != null &&
        last.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height;
    if (n.metrics.pixels < _chapterStart || atEnd) {
      widget.chrome.show();
    } else {
      widget.chrome.scrolled(
        n.scrollDelta ?? 0,
        dragging: n.dragDetails != null,
      );
    }
  }

  static const _chapterStart = 80.0;

  /// Tap paragraf → Artinya; selain itu (margin, sela, bawah teks terakhir,
  /// heading) → munculin/ngumpetin kapsul. Kotak paragraf selebar kolom,
  /// tapi area tap margin minimal [_minTapMargin]: di margin Sempit (16),
  /// 8pt pinggir kolom ikut diitung kosong.
  void _onTap(Offset point, List<ReaderParagraph> paras) {
    _introTimer?.cancel(); // udah pegang kendali sendiri
    final edge = math.max(0.0, _minTapMargin - widget.prefs.marginWidth);
    for (final p in paras) {
      if (p.type != ParagraphType.paragraph) continue;
      final box = _box(p.index);
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (Rect.fromLTRB(
        r.left + edge,
        r.top,
        r.right - edge,
        r.bottom,
      ).contains(point)) {
        widget.onParagraphTap(p);
        return;
      }
    }
    widget.chrome.toggle();
  }

  static const _minTapMargin = 24.0;

  /// Paragraf terakhir yang dirender, buat ngukur posisi pas setelan Aa
  /// diganti (layout lama masih ada di [didUpdateWidget]).
  List<ReaderParagraph> _paras = const [];

  @override
  void didUpdateWidget(_ChapterText old) {
    super.didUpdateWidget(old);
    final p = widget.prefs;
    final changed =
        p.fontSize != old.prefs.fontSize ||
        p.font != old.prefs.font ||
        p.lineHeight != old.prefs.lineHeight ||
        p.marginWidth != old.prefs.marginWidth;
    if (!changed || !_restored) return;
    // Tinggi paragraf berubah: titik yang lagi di garis atas tetep di situ.
    final spot = _topSpot(_paras);
    if (spot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _place(spot, MediaQuery.paddingOf(context).top);
      _track();
    });
  }

  /// Geser scroll sampe [spot] ada di [y] (global). Mentok di ujung scroll.
  bool _place(Spot spot, double y) {
    final box = _box(spot.index);
    if (box == null || !_scroll.hasClients) return false;
    final p = _scroll.position;
    final point =
        box.localToGlobal(Offset.zero).dy + spot.offset * box.size.height;
    _scroll.jumpTo(
      (p.pixels + point - y).clamp(p.minScrollExtent, p.maxScrollExtent),
    );
    return true;
  }

  /// Taruh titik tersimpan di ±⅓ tinggi layar, biar ada konteks di atasnya.
  void _restore(List<ReaderParagraph> paras) {
    final spot = widget.restoreTo;
    if (spot != null) {
      final source = widget.sourceVisit;
      var target = spot;
      var y = MediaQuery.sizeOf(context).height / 3;
      if (source != null) {
        final anchor = source.anchors.first;
        final box = _box(spot.index);
        if (box is RenderParagraph && box.size.height > 0) {
          final rects = box.getBoxesForSelection(
            TextSelection(baseOffset: anchor.start, extentOffset: anchor.end),
          );
          if (rects.isNotEmpty) {
            target = (
              index: spot.index,
              offset: rects.first.top / box.size.height,
            );
            if (rects.last.bottom - rects.first.top >
                MediaQuery.sizeOf(context).height / 2) {
              y = MediaQuery.paddingOf(context).top + Layout.touch + Space.s5;
            }
          }
        }
      }
      if (_place(target, y) && source == null) {
        if (widget.flashSearch) {
          flashParagraph(spot.index);
          _searchAnchor = _scroll.offset;
        } else {
          _greet(paras, spot);
        }
      }
    }
    if (_scroll.hasClients) _track();
    // Baru keliatan setelah di posisi yang bener (lihat AnimatedOpacity).
    setState(() => _restored = true);
  }

  /// Kotak paragraf-paragraf satu grup, di koordinat [ancestor] (null =
  /// global).
  Rect? _groupRect(int group, [RenderObject? ancestor]) {
    Rect? rect;
    for (final p in _paras.where((p) => p.groupIndex == group)) {
      final box = _box(p.index);
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
      rect = rect?.expandToInclude(r) ?? r;
    }
    return rect;
  }

  /// Blok stabilo grup: melebar setengah margin ke samping, 8pt atas-bawah.
  Rect _highlight(Rect group) {
    final side = widget.prefs.marginWidth / 2;
    return Rect.fromLTRB(
      group.left - side,
      group.top - Space.s2,
      group.right + side,
      group.bottom + Space.s2,
    );
  }

  /// Grup sesudah [group] di bab ini, null kalau udah yang terakhir.
  int? groupAfter(int group) => _paras
      .map((p) => p.groupIndex)
      .whereType<int>()
      .where((g) => g > group)
      .firstOrNull;

  double get pixels => _scroll.hasClients ? _scroll.offset : 0;

  /// Sheet Artinya: halaman ikut naik barengan sheet sampe bawah blok grup =
  /// atas sheet − 16. Grup kepanjangan: atas bloknya = safe area + 16.
  Future<void> showGroupAbove(int group, double sheetTop) async {
    final r = _groupRect(group);
    if (r == null || !_scroll.hasClients) return;
    final block = _highlight(r);
    final top = MediaQuery.paddingOf(context).top + Space.s4;
    final bottom = sheetTop - Space.s4;
    final delta = block.height <= bottom - top
        ? block.bottom - bottom
        : block.top - top;
    await _animateTo(pixels + delta, Motion.sheetOpen, Motion.sheetOpenCurve);
  }

  /// Sheet Artinya baru dibuka: atas blok grup = safe area, selalu. Grup
  /// rata-rata lebih tinggi dari ruang di atas sheet, jadi bawahnya ketutup
  /// sheet (sama kayak cabang grup kepanjangan di [showGroupAbove]).
  Future<void> showGroupAtTop(int group) async {
    final r = _groupRect(group);
    if (r == null || !_scroll.hasClients) return;
    final delta = _highlight(r).top - MediaQuery.paddingOf(context).top;
    await _animateTo(pixels + delta, Motion.rise(delta), Motion.riseCurve);
  }

  /// Card kuning pas sheet Artinya kebuka: jendela tetap di posisi grup (atas
  /// = safe area), isinya teks grup yang di-scroll ngikutin seberapa jauh
  /// terjemahan kebaca. Halaman di belakangnya gak geser. Dipasang cuma kalau
  /// grupnya kepanjangan (bawah teksnya ketutup sheet): yang muat gak ada yang
  /// perlu di-scroll.
  ({Rect rect, List<ReaderParagraph> paras})? _pin;
  final _pinScroll = ScrollController();
  final _pinView = GlobalKey();
  final _pinKeys = <int, GlobalKey>{};

  void pinGroup(int group, double sheetTop) {
    // Sheet bisa udah ditutup pas halaman masih naik.
    if (!mounted || widget.openGroup != group) return;
    final area = context.findRenderObject();
    final r = _groupRect(group, area);
    final paras = _paras.where((p) => p.groupIndex == group).toList();
    if (area is! RenderBox || r == null || paras.isEmpty) return;
    final block = _highlight(r);
    final sheetLocal = sheetTop - area.localToGlobal(Offset.zero).dy;
    // Teks (tanpa padding bawah blok) muat di atas sheet: gak ada yang di-scroll.
    if (block.bottom - Space.s2 <= sheetLocal - Layout.followGap) return;
    setState(() {
      // Kartu terus ke bawah sheet; yang kelihatan cuma sampe atas sheet.
      _pin = (
        rect: Rect.fromLTWH(
          block.left,
          block.top,
          block.width,
          math.max(0.0, sheetLocal - block.top),
        ),
        paras: paras,
      );
    });
  }

  Future<void>? _unpinning;

  /// Tutup card tetap: isinya balik ke awal dulu biar gak loncat ke teks
  /// halaman di bawahnya. Dipanggil dua kali (sheet mulai nutup, sheet udah
  /// hilang) nunggu proses yang sama.
  Future<void> unpinGroup({bool animate = true}) => _pin == null
      ? Future.value()
      : _unpinning ??= _unpin(animate).whenComplete(() => _unpinning = null);

  Future<void> _unpin(bool animate) async {
    if (animate && _pinScroll.hasClients && _pinScroll.offset > 0.5) {
      await _pinScroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.sheetClose,
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _pin = null);
  }

  /// Sinkron sheet → card: [progress] (0–1) = seberapa jauh terjemahan kebaca.
  /// 0 = posisi awal, 1 = bawah teks grup tepat [Layout.followGap] di atas
  /// sheet. Di antaranya linear, dikejar dengan animasi pendek.
  void followProgress(double progress, double sheetTop) {
    final view = _pinView.currentContext?.findRenderObject();
    final pin = _pin;
    final last = pin == null
        ? null
        : _pinKeys[pin.paras.last.index]?.currentContext?.findRenderObject();
    if (view is! RenderBox || last is! RenderBox || !_pinScroll.hasClients) {
      return;
    }
    final viewTop = view.localToGlobal(Offset.zero).dy;
    final shown =
        sheetTop - Layout.followGap - viewTop; // tinggi yang kelihatan
    final textBottom =
        last.localToGlobal(Offset.zero).dy -
        viewTop +
        _pinScroll.offset +
        last.size.height;
    final needed = math.max(0.0, textBottom - shown);
    final target = (progress * needed).clamp(
      0.0,
      _pinScroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _pinScroll.jumpTo(target);
      return;
    }
    // Dikejar halus, bukan loncat: tiap update restart animasi pendek dari
    // posisi sekarang, jadi fling di sheet gak bikin teks tersentak.
    unawaited(
      _pinScroll.animateTo(
        target,
        duration: Motion.follow,
        curve: Curves.easeOut,
      ),
    );
  }

  /// Balik ke posisi sebelum sheet dibuka.
  Future<void> scrollBack(double to) =>
      _animateTo(to, Motion.sheetClose, Motion.sheetCloseCurve);

  Future<void> _animateTo(double to, Duration d, Curve curve) {
    final p = _scroll.position;
    final target = to.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((target - p.pixels).abs() < 0.5) return Future.value();
    // Kurangi gerakan: langsung pindah (animateTo gak mau durasi nol).
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return Future.value();
    }
    return _scroll.animateTo(target, duration: d, curve: curve);
  }

  /// Simpen titik yang sekarang di atas (abis halaman digeser sheet).
  void stopAndReportPosition() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    reportPosition();
  }

  void reportPosition() {
    final spot = _topSpot(_paras);
    if (spot != null) widget.onPosition(spot);
  }

  /// Blok grup yang perlu digambar (dibuka + penanda udah diterjemahin), di
  /// koordinat isi bab. Diukur abis layout.
  Map<int, Rect> _groupRects = const {};

  /// Grup yang dibolongin di scrim Artinya.
  int? _scrimGroup;

  void _measureGroups(Set<int> groups) {
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox) return;
    final rects = {for (final g in groups) g: ?_groupRect(g, content)};
    if (!mapEquals(rects, _groupRects)) setState(() => _groupRects = rects);
  }

  /// Abis lanjut baca: kapsul muncul bentar buat orientasi terus ngumpet,
  /// grup tersimpan dikasih kilatan sekali (Kurangi gerakan: garis kiri 4pt).
  void _greet(List<ReaderParagraph> paras, Spot spot) {
    widget.chrome.show();
    _introTimer = Timer(Motion.capsuleIntro, widget.chrome.hide);

    final group = paras
        .where((p) => p.index == spot.index)
        .firstOrNull
        ?.groupIndex;
    final content = _contentKey.currentContext?.findRenderObject();
    if (group == null || content is! RenderBox) return;
    final rect = _groupRect(group, content);
    if (rect == null) return;
    _mark = Rect.fromLTRB(
      rect.left - Space.s3,
      rect.top - Space.s2,
      rect.right + Space.s3,
      rect.bottom + Space.s2,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _markTimer = Timer(Motion.flashReduced, () {
        if (mounted) setState(() => _mark = null);
      });
    } else {
      _flash.duration = Motion.flash;
      _flash.forward(from: 0);
    }
  }

  /// Kedip muted di paragraf hasil cari ([Motion.searchFlash]); Kurangi
  /// gerakan: garis kiri 4pt kayak "Lanjut baca".
  void flashParagraph(int index) {
    final content = _contentKey.currentContext?.findRenderObject();
    final box = _box(index);
    if (box == null || content is! RenderBox) return;
    final r = box.localToGlobal(Offset.zero, ancestor: content) & box.size;
    _markTimer?.cancel();
    _mark = Rect.fromLTRB(
      r.left - Space.s3,
      r.top - Space.s2,
      r.right + Space.s3,
      r.bottom + Space.s2,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _markTimer = Timer(Motion.flashReduced, () {
        if (mounted) setState(() => _mark = null);
      });
    } else {
      _flash.duration = Motion.searchFlash;
      _flash.forward(from: 0);
    }
  }

  /// Lompat dari hasil cari (bab ini): paragraf ke ±⅓ tinggi layar, kedip.
  /// Paragraf gak ada (mis. judul bab yang gak dirender dobel) = ke awal bab.
  void jumpToParagraph(int index) {
    if (!_scroll.hasClients) return;
    final placed = _place((
      index: index,
      offset: 0,
    ), MediaQuery.sizeOf(context).height / 3);
    if (!placed) _scroll.jumpTo(_scroll.position.minScrollExtent);
    _userScrolled = false;
    _track();
    _searchAnchor = _scroll.offset;
    setState(() => flashParagraph(index));
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _markTimer?.cancel();
    _flash.dispose();
    _scroll.dispose();
    _pinScroll.dispose();
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
    final reading = ReaderTypography(
      widget.prefs,
      Theme.of(context).brightness,
    ).style.copyWith(color: c.ink);
    final gap = reading.fontSize!; // 1em antar paragraf
    final pad = MediaQuery.paddingOf(context);
    final labelHeight = math.max(
      32.0,
      MediaQuery.textScalerOf(context).scale(12.5) * (18 / 13) + Space.s4,
    );
    final visitTop = math.max(Layout.chatHeader, 7 + labelHeight + Space.s2);
    final loaded = paragraphs is AsyncData;
    final paras = switch (paragraphs) {
      AsyncData(:final value) =>
        widget.sourceVisit == null
            ? _withoutTitleHeading(value, chapter.title)
            : value,
      _ => const <ReaderParagraph>[],
    };
    if (loaded && widget.sourceVisit != null) {
      try {
        for (final anchor in widget.sourceVisit!.anchors.where(
          (a) => a.chapterId == chapter.id,
        )) {
          final paragraph = paras
              .where((p) => p.index == anchor.paragraphIndex)
              .firstOrNull;
          if (paragraph == null) throw const FormatException('Sumber hilang');
          anchor.validate((
            book: (
              bookId: widget.book.id,
              contentRevision: widget.book.contentRevision,
            ),
            chapterId: chapter.id,
            paragraphIndex: paragraph.index,
            text: paragraph.text,
          ), anchor.book);
        }
      } on FormatException {
        return const Center(child: Text('Sumber ini udah gak tersedia.'));
      }
    }
    _paras = paras;
    final translated =
        ref.watch(translatedGroupsProvider(chapter.id)).value ?? const {};
    final open = widget.openGroup;
    final drawn = {...translated, ?open};
    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureGroups(drawn);
      });
    }
    final onOpen = reading.copyWith(color: c.onHighlight);
    // Inget grup terakhir biar bolongnya gak ilang pas scrim lagi fade out.
    if (open != null) _scrimGroup = open;

    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        // Lompat ke posisi tersimpan sekali; chapter pendek yang gak perlu
        // di-scroll langsung dianggap kebaca.
        _restored ? _track() : _restore(paras);
      });
    }

    // Isi disembunyiin sampe teksnya kebaca & udah lompat ke posisi
    // tersimpan, terus fade in. Tanpa ini keliatan kedip: mulai dari atas,
    // lompat ke tengah, kartu akhir bab nongol duluan.
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.contentFade;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _restored ? 1 : 0,
            duration: fade,
            curve: Curves.easeOut,
            child: AnimatedBuilder(
              animation: widget.chrome.hidden,
              // Tepi teks ikut varian kapsul ↔ imersif sepanjang animasi kapsul.
              builder: (context, child) {
                final edges = readerEdgeFade(
                  pad,
                  widget.chrome.hidden.value,
                  bottomHeight: readerDockHeight(context),
                );
                return EdgeFadeScroll(
                  top: widget.sourceVisit == null
                      ? edges.top
                      : EdgeFadeSide(
                          Space.s5,
                          clear: pad.top + visitTop - Space.s5,
                        ),
                  bottom: widget.sourceVisit == null
                      ? edges.bottom
                      : EdgeFadeSide(
                          Space.s5,
                          clear: pad.bottom + Layout.chatHeader + Space.s3,
                        ),
                  child: child!,
                );
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification &&
                      n.direction != ScrollDirection.idle) {
                    _userScrolled = true;
                    _introTimer?.cancel(); // udah pegang kendali sendiri
                    widget.onScrollActive?.call(true);
                  } else if (n is ScrollUpdateNotification &&
                      (_userScrolled || n.dragDetails != null)) {
                    _moveChrome(n, paras);
                  } else if (n is ScrollEndNotification && _userScrolled) {
                    _userScrolled = false;
                    widget.chrome.release();
                    widget.onScrollActive?.call(false);
                    final spot = _topSpot(paras);
                    if (spot != null) widget.onPosition(spot);
                    final anchor = _searchAnchor;
                    if (anchor != null &&
                        (_scroll.offset - anchor).abs() >=
                            MediaQuery.sizeOf(context).height) {
                      _searchAnchor = null;
                      widget.onSearchRead?.call();
                    }
                  }
                  return false;
                },
                // Tap area kosong (margin, sela, bawah teks terakhir) = munculin /
                // ngumpetin kapsul. Paragraf nangkep tap-nya sendiri.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d.globalPosition, paras),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      widget.prefs.marginWidth,
                      pad.top +
                          (widget.sourceVisit == null
                              ? readerTextTop
                              : visitTop),
                      widget.prefs.marginWidth,
                      pad.bottom +
                          readerTextBottom +
                          readerDockHeight(context) -
                          capsuleBottomHeight,
                    ),
                    child: Stack(
                      key: _contentKey,
                      // Penanda grup nongol di margin kiri, di luar kolom teks.
                      clipBehavior: Clip.none,
                      children: [
                        // Penanda grup yang udah diterjemahin: garis 4pt warna mark
                        // di tengah margin kiri, sepanjang grupnya.
                        for (final g in translated)
                          if (g != open && _groupRects[g] != null)
                            Positioned(
                              key: ValueKey('mark-$g'),
                              left: -widget.prefs.marginWidth / 2 - 2,
                              top: _groupRects[g]!.top + 5,
                              height: math.max(0, _groupRects[g]!.height - 10),
                              width: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.mark,
                                  borderRadius: BorderRadius.circular(
                                    Radii.full,
                                  ),
                                ),
                              ),
                            ),
                        if (open != null && _groupRects[open] != null)
                          Positioned.fromRect(
                            rect: _highlight(_groupRects[open]!),
                            child: Semantics(
                              label: 'Grup paragraf yang lagi dibuka',
                              child: DecoratedBox(
                                key: const ValueKey('open-group'),
                                decoration: BoxDecoration(
                                  color: c.highlight,
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                              ),
                            ),
                          ),
                        if (_mark != null)
                          Positioned.fromRect(
                            rect: _mark!,
                            child: _markWidget(c),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(bottom: gap),
                              child: ChapterHeading(
                                title: chapter.title,
                                number: widget.index + 1,
                                total: widget.book.chapters.length,
                                minutes: readingMinutes(chapter.chars),
                                reading: reading,
                              ),
                            ),
                            for (final p in paras)
                              Padding(
                                padding: EdgeInsets.only(bottom: gap),
                                // Key di isinya, bukan di sela bawah: offset = fraksi tinggi
                                // paragraf doang.
                                child: KeyedSubtree(
                                  key: _keys.putIfAbsent(
                                    p.index,
                                    GlobalKey.new,
                                  ),
                                  child: switch (p.type) {
                                    // Kotak paragraf selebar kolom, termasuk sisa baris
                                    // pendek. Sela antar paragraf & margin = area kosong.
                                    ParagraphType.paragraph => _paragraphText(
                                      p,
                                      p.groupIndex == open && open != null
                                          ? onOpen
                                          : reading,
                                    ),
                                    ParagraphType.heading => Semantics(
                                      header: true,
                                      child: _paragraphText(
                                        p,
                                        StabiloType.titleSm.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                    ParagraphType.sceneBreak => Center(
                                      child: Text(
                                        '* * *',
                                        semanticsLabel: 'Pemisah adegan',
                                        style: StabiloType.label.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ),
                                  },
                                ),
                              ),
                            // Kartu akhir bab baru muncul bareng teks, biar gak nongol di atas
                            // terus kedorong ke bawah.
                            if (loaded)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: ChapterEnd(
                                  chapterId: chapter.id,
                                  title: chapter.title,
                                  next: next,
                                  nextNumber: widget.index + 2,
                                  total: widget.book.chapters.length,
                                  onNext: widget.onNext,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Sheet Artinya: scrim nutup halaman kecuali blok grup yang dibuka
        // (grupnya kebaca di atas scrim). Ikut gerak pas halaman di-scroll.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: open == null ? 0 : 1,
              duration: open == null ? Motion.sheetClose : Motion.sheetOpen,
              child: CustomPaint(
                painter: ScrimHole(
                  color: c.scrim,
                  repaint: _scroll,
                  hole: () {
                    final g = _scrimGroup;
                    if (g == null) return null;
                    final r = _groupRect(g, context.findRenderObject());
                    return r == null ? null : _highlight(r);
                  },
                ),
              ),
            ),
          ),
        ),
        // Card kuning tetap (halaman gak geser): isinya yang di-scroll.
        if (_pin case final pin?)
          Positioned.fromRect(
            key: const ValueKey('pinned-group'),
            rect: pin.rect,
            child: IgnorePointer(
              child: ClipRRect(
                key: _pinView,
                // Bawahnya lurus: kartu terus ke bawah sheet, nyatu sama card
                // halaman, bukan kotak yang berhenti di atas sheet.
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Radii.md),
                ),
                // Canvas dulu: highlight gelap tembus pandang, tanpa ini teks
                // halaman di belakangnya kelihatan dobel.
                child: ColoredBox(
                  color: c.canvas,
                  child: ColoredBox(
                    color: c.highlight,
                    child: SingleChildScrollView(
                      controller: _pinScroll,
                      physics: const NeverScrollableScrollPhysics(),
                      // Bawah selebar jarak ke sheet: paragraf terakhir bisa naik
                      // sampe kelihatan penuh di atas sheet.
                      padding: EdgeInsets.fromLTRB(
                        widget.prefs.marginWidth / 2,
                        Space.s2,
                        widget.prefs.marginWidth / 2,
                        Layout.followGap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: gap,
                        children: [
                          for (final p in pin.paras)
                            KeyedSubtree(
                              key: _pinKeys.putIfAbsent(p.index, GlobalKey.new),
                              child: Text(p.text, style: onOpen),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _paragraphText(ReaderParagraph paragraph, TextStyle style) =>
      buildParagraphText(
        paragraph: paragraph,
        style: style,
        colors: context.stabilo,
        chapterId: widget.book.chapters[widget.index].id,
        search: widget.search,
        sourceVisit: widget.sourceVisit,
      );

  /// Penanda "terakhir lo baca di sini": kilatan stabilo, atau garis kiri
  /// kalau Kurangi gerakan nyala.
  Widget _markWidget(StabiloColors c) => Semantics(
    label: 'Terakhir lo baca di sini',
    child: MediaQuery.disableAnimationsOf(context)
        ? Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: c.mark,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
            ),
          )
        : AnimatedBuilder(
            animation: _flash,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: c.flash.withValues(
                  alpha: c.flash.a * _flashCurve.evaluate(_flash),
                ),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
  );

  /// Heading pertama yang isinya sama kayak judul chapter udah ditampilin di
  /// [ChapterHeading], gak usah dobel.
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
