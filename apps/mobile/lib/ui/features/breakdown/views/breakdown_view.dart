import 'package:luma/l10n/l10n.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/breakdown_prompt.dart';
import '../../../../domain/breakdown_sync.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book_chat.dart';
import '../../chat/view_models/chat_entry.dart';
import '../../reader/view_models/reader_view_model.dart';
import '../../../../domain/models/breakdown.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/pacing.dart';
import '../../../../domain/stream_text.dart';
import '../../../../routing/router.dart';
import '../../../core/scroll_run.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/ai_status.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/tag.dart';
import '../../../core/widgets/toast.dart';
import '../../reader/view_models/breakdown_view_model.dart';
import '../../../../data/repositories/ai_key_repository.dart';
import '../../../core/widgets/quota.dart';
import '../../settings/view_models/ai_quota_view_model.dart';
import '../../settings/views/ai_shared.dart';
import 'peek_sheet.dart';

/// The Bedahin screen (board "Terpilih · Bedahin · Opsi C · layar bedah" +
/// "Spek · Bedahin · state").
///
/// Pushed from the Artinya sheet: back returns to the sheet, and "Balik baca"
/// is `pop(ReaderReturn.reading)`, which the caller also uses to close the
/// sheet. Closing mid-process cancels the request (autoDispose provider). It
/// can stack: "Bedahin ini juga" from the peek pushes another Bedahin on top;
/// back pops one layer, and "Balik baca" from any layer keeps propagating
/// `pop(ReaderReturn.reading)` up to the page.
class BreakdownView extends ConsumerStatefulWidget {
  const BreakdownView({
    super.key,
    required this.bookId,
    required this.group,
    this.chatContext,
  });

  final ChatLaunchContext? chatContext;
  final int bookId;
  final GroupRef group;

  @override
  ConsumerState<BreakdownView> createState() => _BreakdownViewState();
}

class _BreakdownViewState extends ConsumerState<BreakdownView> {
  /// Increments on every retry so the writing rhythm restarts from zero.
  int _attempt = 0;
  bool _copied = false;

  void _retry() {
    ref.invalidate(breakdownStreamProvider(widget.group));
    setState(() => _attempt++);
  }

  /// Once the key is filled in on Pengaturan, Bedahin runs again immediately.
  Future<void> _settings() async {
    await context.push(Routes.settings);
    if (mounted) _retry();
  }

  /// A Nyambung ke card tap opens the peek sheet, then possibly one more layer.
  Future<void> _peek(BreakdownLink link, String where) async {
    final result = await showPeekSheet(
      context,
      peek: (from: widget.group, chapter: link.chapter),
      link: link,
      where: where,
    );
    if (!mounted) return;
    switch (result) {
      case PeekBreakdown(:final group):
        final read = await context.push<ReaderReturn>(
          Routes.breakdown(widget.bookId, group.chapterId, group.groupIndex),
          extra: widget.chatContext,
        );
        if (read == ReaderReturn.reading && mounted) {
          context.pop(ReaderReturn.reading);
        }
      case PeekSettings():
        await context.push(Routes.settings);
      case null:
    }
  }

  bool _openingChat = false;
  Future<void> _askChat() async {
    if (_openingChat) return;
    final state = ref.read(breakdownStreamProvider(widget.group));
    if (state.phase != BreakdownPhase.done || state.input == null) return;
    _openingChat = true;
    try {
      final quote = await ref.read(
        chatEntryQuoteProvider((bookId: widget.bookId, group: widget.group))
            .future,
      );
      final book = quote.anchors.first.book;
      final entry = widget.chatContext;
      if (entry != null && entry.book != book) {
        throw const FormatException('Book content changed');
      }
      if (quote.anchors.map((a) => a.snapshot).join('\n\n') !=
          state.input!.original.join('\n\n')) {
        throw const FormatException('Quote changed');
      }
      final position =
          entry?.returnPosition ??
          await ref.read(readingPositionProvider(widget.bookId).future);
      if (!mounted) return;
      final launch = ChatLaunchContext(
        book: book,
        quote: ChatQuote(
          anchors: quote.anchors,
          chapterTitle: quote.chapterTitle,
          translation: state.input!.translations.join('\n\n'),
        ),
        origin: ChatLaunchOrigin.breakdown,
        returnPosition:
            position ??
            (
              chapterId: widget.group.chapterId,
              paragraphIndex: quote.anchors.first.paragraphIndex,
              paragraphOffset: 0,
            ),
      );
      final result = await context.push<ReaderReturn>(
        Routes.chat(widget.bookId),
        extra: launch,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (result == ReaderReturn.reading && mounted) {
        context.pop(ReaderReturn.reading);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, context.l10n.breakdownCouldnTBringTheQuoteOver);
      }
    } finally {
      _openingChat = false;
    }
  }

  Future<void> _copy(BreakdownInput input, Breakdown result) async {
    await Clipboard.setData(ClipboardData(text: breakdownCopy(input, result)));
    if (!mounted) return;
    setState(() => _copied = true);
    showOverlayToast(
      context,
      context.l10n.meaningCopiedReadyToPaste,
      bottom: MediaQuery.paddingOf(context).bottom + 68,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(breakdownStreamProvider(widget.group));
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    return Scaffold(
      body: _Screen(
        key: ValueKey(_attempt),
        group: widget.group,
        state: state,
        typo: ReaderTypography(prefs, Theme.of(context).brightness),
        copied: _copied,
        onBack: () => context.pop(),
        onDone: () => context.pop(ReaderReturn.reading),
        onRetry: _retry,
        onSettings: _settings,
        onCopy: _copy,
        onPeek: _peek,
        onChat: _askChat,
        subsidy: subsidyFailureOf(
          state.error,
          usingSubsidy: ref.watch(aiSourceProvider).value != AiSource.own,
        ),
        onUseOwnKey: () => openOwnKeySettings(context, ref),
      ),
    );
  }
}

/// Builds the Salin text (board state, "Isi Salin"): plain text with the source
/// on the first line.
///
/// It has no translation or Nyambung ke. A single section has no number or
/// title.
String breakdownCopy(BreakdownInput input, Breakdown b) {
  final numbered = b.sections.length >= 2;
  return [
    '${input.book.title} · ${_chapterLabel(input)} (dibedah di Luma)',
    for (final (i, s) in b.sections.indexed)
      [
        if (numbered) '${i + 1}. ${s.title}',
        'Maksudnya: ${s.meaning}',
        'Logikanya: ${s.logic}',
      ].join('\n'),
    if (b.terms.isNotEmpty)
      [
        'Tokoh & istilah',
        for (final t in b.terms) '- ${t.label}: ${t.explanation}',
      ].join('\n'),
    if (b.practice != null) 'Praktekinnya gini\n${b.practice}',
  ].join('\n\n');
}

String _chapterLabel(BreakdownInput input) {
  final title = input.book.chapter.trim();
  return title.isEmpty ? 'Bab ${input.chapter}' : title;
}

/// The content allowed to show now, plus the section currently being written.
typedef _Visible = ({Breakdown draft, int tail});

/// Breakdown text in display order, which paces the writing: per section the
/// title, intent and logic; per term a label and explanation; per link a title
/// and the reason; then practice. An index here is the "tip" index in
/// [_Visible].
List<String> _fields(Breakdown b) => [
  for (final s in b.sections) ...[s.title, s.meaning, s.logic],
  for (final t in b.terms) ...[t.label, t.explanation],
  for (final l in b.links) ...[l.title, l.why],
  ?b.practice,
];

int _length(Breakdown b) => _fields(b).fold(0, (n, f) => n + f.length);

/// [b] truncated to its first [n] letters (in [_fields] order). Items not yet
/// reached by any letters are left out.
_Visible _take(Breakdown b, int n) {
  var left = n;
  var index = 0;
  var tail = -1;
  String cut(String s) {
    final t = s.substring(0, math.min(left, s.length));
    left -= t.length;
    if (t.isNotEmpty) tail = index;
    index++;
    return t;
  }

  final sections = <BreakdownSection>[];
  for (final s in b.sections) {
    if (left <= 0) break;
    sections.add(
      BreakdownSection(
        from: s.from,
        to: s.to,
        title: cut(s.title),
        meaning: cut(s.meaning),
        logic: cut(s.logic),
      ),
    );
  }
  index = b.sections.length * 3;
  final terms = <BreakdownTerm>[];
  for (final t in b.terms) {
    if (left <= 0) break;
    terms.add(
      BreakdownTerm(
        label: cut(t.label),
        exact: t.exact,
        explanation: cut(t.explanation),
        sentence: t.sentence,
      ),
    );
  }
  index = b.sections.length * 3 + b.terms.length * 2;
  final links = <BreakdownLink>[];
  for (final l in b.links) {
    if (left <= 0) break;
    links.add(
      BreakdownLink(chapter: l.chapter, title: cut(l.title), why: cut(l.why)),
    );
  }
  index = b.sections.length * 3 + b.terms.length * 2 + b.links.length * 2;
  final practice = b.practice != null && left > 0 ? cut(b.practice!) : null;
  return (
    draft: Breakdown(
      sections: sections,
      terms: terms,
      links: links,
      practice: practice,
    ),
    tail: tail,
  );
}

/// Only the complete sections: the last section is still being written, unless
/// the following block has already started. Optional blocks are dropped.
Breakdown _whole(Breakdown b) {
  final later = b.terms.isNotEmpty || b.links.isNotEmpty || b.practice != null;
  final n = later ? b.sections.length : math.max(0, b.sections.length - 1);
  return Breakdown(sections: b.sections.take(n).toList());
}

/// Renders every stage in one widget: waiting → writing → done, with no layout
/// jumps.
///
/// - Explanation text follows the [Pacer]; the last 4 words being written fade.
///   Under reduce-motion it shows per complete section, without the fade.
///
/// - The top panel shows the translation right away (it already exists from the
///   quick meaning). Section numbers in the text appear together with their
///   explanation, from 2 sections on.
///
/// - Layout follows the section count: 1 section (done) = the panel scrolls
///   with the content, plus the original sentence; otherwise the panel is
///   pinned on top, at most 40% of the screen, and scrolls on its own if
///   longer.
///
/// - The button hides while the explanation scrolls ([ScrollRun] rule), except
///   during processing or when VoiceOver is on.
///
/// - Sync (≥ 2 sections): the block that crosses the reading line becomes
///   active ([activeBlock]), its section's sentence is highlighted in the
///   panel, and the panel scrolls there. Tapping a number / chip jumps. The
///   panel is folded by default; unfolding / folding comes only from taps
///   ([_folded]). While writing, the highlight already runs from section 1 and
///   follows scroll, without waiting for completion. Scrolling only changes
///   [_active]; the panel rebuilds only when the active block changes.
class _Screen extends StatefulWidget {
  const _Screen({
    super.key,
    required this.group,
    required this.state,
    required this.typo,
    required this.copied,
    required this.onBack,
    required this.onDone,
    required this.onRetry,
    required this.onSettings,
    required this.onCopy,
    required this.onPeek,
    required this.onChat,
    this.subsidy,
    this.onUseOwnKey,
  });

  final GroupRef group;
  final BreakdownState state;

  /// Whether the failure was the free quota running out or being revoked (board
  /// Kuota AI 09, 12).
  final SubsidyFailure? subsidy;
  final VoidCallback? onUseOwnKey;
  final ReaderTypography typo;
  final bool copied;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final VoidCallback onChat;
  final VoidCallback onRetry;
  final VoidCallback onSettings;
  final void Function(BreakdownInput, Breakdown) onCopy;
  final void Function(BreakdownLink, String where) onPeek;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> with TickerProviderStateMixin {
  final _pacer = Pacer();
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _shown = 0;

  /// Opacity of the text tip: 0 = faded, 1 = solid.
  late final _solid = AnimationController(
    vsync: this,
    duration: Motion.tailFade,
  );

  /// Bottom button: 0 = visible, 1 = hidden.
  late final _actions = AnimationController(
    vsync: this,
    duration: Motion.sheetChrome,
  );
  final _run = ScrollRun();
  bool _user = false;

  // Sync between the explanation and the text panel.
  final _explain = ScrollController();
  final _viewport = GlobalKey();

  /// The active block: sections 0..n-1, then Tokoh & istilah, Praktekinnya
  /// gini.
  final _active = ValueNotifier(0);

  /// The tapped term: its exact word is highlighted in place of the section
  /// highlight.
  final _term = ValueNotifier<BreakdownTerm?>(null);

  /// Whether the text panel is folded. Folded by default in every state (the
  /// translation was already read in the Artinya sheet); unfolding / folding
  /// comes only from taps. Not remembered between screens.
  final _folded = ValueNotifier(true);

  /// After a jump, the active block isn't recomputed until the finger scrolls
  /// again.
  bool _locked = false;
  final _blocks = <GlobalKey>[];
  final _badges = <GlobalKey>[];
  int _sections = 0;
  int _blockCount = 0;

  /// Sync is on and touchable (≥ 2 sections, complete or cut off).
  bool _interactive = false;

  /// The highlight follows scroll (≥ 2 sections), including while writing.
  bool _following = false;

  /// Complete, with every letter already displayed.
  bool _finished = false;

  BreakdownState get _s => widget.state;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _busy => switch (_s.phase) {
    BreakdownPhase.waiting || BreakdownPhase.slow => true,
    BreakdownPhase.writing => true,
    BreakdownPhase.done => !_finished,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Screen old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// From cache = done immediately. Cut off = everything received so far, with
  /// the ticker stopped.
  void _sync() {
    if (_finished) return;
    final available = _length(_s.draft);
    if (_s.cached) {
      _finished = true;
      _shown = available;
      _solid.value = 1;
      _ticker.stop();
      return;
    }
    if (_s.phase == BreakdownPhase.cut || _s.phase == BreakdownPhase.failed) {
      _pacer.finish(available);
      _shown = available;
      _ticker.stop();
      return;
    }
    if (available > 0 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final available = _length(_s.draft);
    final done = _s.phase == BreakdownPhase.done;
    final shown = _reduced ? available : _pacer.step(dt, available, done: done);
    final finished = done && shown >= available;
    if (shown == _shown && !finished) return;
    setState(() {
      _shown = shown;
      _finished = finished;
    });
    if (!finished) return;
    _ticker.stop();
    _solid.animateTo(1, duration: _reduced ? Duration.zero : Motion.tailFade);
    if (MediaQuery.accessibleNavigationOf(context)) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.breakdownBreakdownComplete(
          _countLabel(context, _s.draft.sections.length),
        ),
        TextDirection.ltr,
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _solid.dispose();
    _actions.dispose();
    _explain.dispose();
    _active.dispose();
    _term.dispose();
    _folded.dispose();
    super.dispose();
  }

  _Visible _visible() {
    final draft = _s.draft;
    if (_s.phase == BreakdownPhase.cut) return (draft: _whole(draft), tail: -1);
    if (_finished) return (draft: draft, tail: -1);
    if (_reduced) return (draft: _whole(draft), tail: -1);
    return _take(draft, _shown);
  }

  bool get _hideable =>
      !_busy &&
      _s.phase != BreakdownPhase.failed &&
      !MediaQuery.accessibleNavigationOf(context);

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _locked = false;
      _term.value = null;
    }
    if (n is ScrollUpdateNotification) _follow(n.metrics);
    if (!_hideable) return false;
    switch (n) {
      case UserScrollNotification():
        _user = n.direction != ScrollDirection.idle;
      case ScrollUpdateNotification() when _user || n.dragDetails != null:
        final m = n.metrics;
        final intent = _run.add(n.scrollDelta ?? 0);
        if (m.pixels <= 0 ||
            m.pixels >= m.maxScrollExtent - 1 ||
            intent == ChromeIntent.show) {
          _animateActions(0);
        } else if (intent == ChromeIntent.hide) {
          _animateActions(1);
        }
      case ScrollEndNotification():
        _user = false;
      default:
    }
    return false;
  }

  static List<GlobalKey> _grow(List<GlobalKey> keys, int n) {
    while (keys.length < n) {
      keys.add(GlobalKey());
    }
    return keys;
  }

  double? _topOf(GlobalKey key) {
    final view = _viewport.currentContext?.findRenderObject();
    final box = key.currentContext?.findRenderObject();
    if (view is! RenderBox || box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: view).dy;
  }

  /// Recomputes the active block from each block's position relative to the
  /// reading line.
  void _follow(ScrollMetrics m) {
    if (!_following || _locked) return;
    final tops = <double>[];
    for (final key in _blocks.take(_blockCount)) {
      final top = _topOf(key);
      if (top == null) return;
      tops.add(top);
    }
    _setActive(
      activeBlock(
        tops,
        line: Layout.breakdownReadLine,
        current: _active.value,
        margin: Layout.breakdownSwitch,
        atEnd: m.maxScrollExtent > 0 && m.pixels >= m.maxScrollExtent - 1,
      ),
    );
  }

  void _setActive(int i) {
    if (i == _active.value) return;
    _active.value = i;
    if (i < _sections) _reveal(i);
  }

  /// Scrolls the text panel so section number [i] is visible.
  void _reveal(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final badge = i < _badges.length ? _badges[i].currentContext : null;
      if (badge == null || !badge.mounted) return;
      Scrollable.ensureVisible(
        badge,
        alignment: 0.1,
        duration: _reduced ? Duration.zero : Motion.jump,
        curve: Motion.riseCurve,
      );
    });
  }

  /// Handles a tap on a number / chip: the explanation jumps to block [i] and
  /// that block is locked as active (a short block at the end can't reach the
  /// reading line).
  void _jump(int i) {
    final top = _topOf(_blocks[i]);
    if (top == null || !_explain.hasClients) return;
    final p = _explain.position;
    final target = (p.pixels + top - Space.s3).clamp(0.0, p.maxScrollExtent);
    _locked = true;
    _term.value = null;
    _setActive(i);
    if (_reduced) {
      p.jumpTo(target);
    } else {
      p.animateTo(target, duration: Motion.jump, curve: Motion.riseCurve);
    }
  }

  /// Handles a tap on a term: its exact word is highlighted, and the panel
  /// opens if folded.
  void _focusTerm(BreakdownTerm t, int section) {
    _term.value = t;
    _folded.value = false;
    _reveal(section);
  }

  void _animateActions(double to) {
    if (_actions.value == to && !_actions.isAnimating) return;
    _actions.animateTo(
      to,
      duration: _reduced ? Motion.reducedFade : Motion.sheetChrome,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hideable && _actions.value != 0) _actions.value = 0;
    final c = context.stabilo;
    final input = _s.input;
    final phase = _s.phase;
    final failed = phase == BreakdownPhase.failed;
    final cut = phase == BreakdownPhase.cut;
    final visible = _visible();
    final shown = visible.draft;
    final count = shown.sections.length;
    final numbered = count >= 2;
    final thinking = _busy && _length(_s.draft) == 0;
    // 1 section (done or cut off): the panel scrolls with the content, plus the
    // original sentence.
    final inline = !_busy && !failed && count == 1;
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final inset = math.max(0.0, widget.typo.margin - Layout.margin);

    final sync = !inline && numbered && !failed;
    _interactive = sync && !_busy;
    _following = sync;
    _sections = count;
    final blocks = [
      for (var i = 0; i < count; i++) '${i + 1}',
      if (_interactive && shown.terms.isNotEmpty) context.l10n.breakdownTerms,
      if (_interactive && shown.practice != null)
        context.l10n.breakdownPractice,
    ];
    _blockCount = blocks.length;
    _grow(_blocks, _blockCount);
    _grow(_badges, count);

    // Rebuilt only when the active block, term, or manual open state changes.
    final panel = input == null
        ? null
        : ValueListenableBuilder(
            valueListenable: _active,
            builder: (context, active, _) => ListenableBuilder(
              listenable: Listenable.merge([_term, _folded]),
              builder: (context, _) {
                final term = _term.value;
                final text = _TextPanel(
                  input: input,
                  sections: numbered ? shown.sections : const [],
                  typo: widget.typo,
                  inline: inline,
                  inset: inset,
                  maxHeight: screen.height * Layout.breakdownPanel,
                  highlight: !sync || term != null
                      ? null
                      : active < count
                      ? active
                      : null,
                  term: term,
                  badges: _badges,
                  onNumber: _interactive ? (i) => _jump(i) : null,
                  onFold: () => _folded.value = true,
                );
                final child = _folded.value
                    ? _FoldedPanel(
                        count: _finished || cut
                            ? _countLabel(context, count)
                            : null,
                        onTap: () => _folded.value = false,
                      )
                    : text;
                return _reduced
                    ? child
                    : AnimatedSize(
                        duration: Motion.fold,
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: child,
                      );
              },
            ),
          );
    final chips = _interactive && count >= 3
        ? ValueListenableBuilder(
            valueListenable: _active,
            builder: (context, active, _) => _Chips(
              labels: blocks,
              sections: count,
              active: active,
              onTap: _jump,
            ),
          )
        : null;

    final explanation = failed
        ? _failure(c)
        : _Explanation(
            visible: visible,
            input: input,
            numbered: numbered,
            typo: widget.typo,
            solid: _solid,
            writing: _busy && !cut,
            faded: !_reduced,
            placeholders: _busy && !cut ? _placeholders(input, shown) : 0,
            blocks: _blocks,
            onTerm: _interactive ? _focusTerm : null,
            from: widget.group,
            onPeek: _busy ? null : widget.onPeek,
            slow: phase == BreakdownPhase.slow,
            cut: cut,
            onCancel: widget.onBack,
            onRetry: widget.onRetry,
          );

    final pad = EdgeInsets.fromLTRB(
      Layout.margin + inset,
      inline ? Space.s6 : Space.s3,
      Layout.margin + inset,
      Layout.artinyaActions + Space.s4,
    );

    final Widget body;
    if (inline) {
      body = _scroll(
        frozen: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: panel,
            ),
            Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s4,
                children: [
                  explanation,
                  if (_finished && !cut)
                    AppButton.secondary(
                      label: context.l10n.meaningAskAboutThis,
                      icon: AppIcons.chat,
                      onPressed: widget.onChat,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (panel != null)
            Semantics(
              sortKey: const OrdinalSortKey(3),
              explicitChildNodes: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                child: panel,
              ),
            ),
          if (chips != null)
            Semantics(
              sortKey: const OrdinalSortKey(2.5),
              explicitChildNodes: true,
              child: Padding(
                padding: const EdgeInsets.only(top: Space.s5),
                child: chips,
              ),
            ),
          Expanded(
            child: Semantics(
              sortKey: const OrdinalSortKey(2),
              explicitChildNodes: true,
              child: _scroll(
                frozen: thinking || failed,
                child: Padding(
                  padding: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.s4,
                    children: [
                      explanation,
                      if (_finished && !cut)
                        AppButton.secondary(
                          label: context.l10n.meaningAskAboutThis,
                          icon: AppIcons.chat,
                          onPressed: widget.onChat,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: top + Space.s2 + Layout.breakdownHeader + Space.s2,
          ),
          child: body,
        ),
        Positioned(
          top: top + Space.s2,
          left: Space.s4,
          right: Layout.margin,
          child: Semantics(
            sortKey: const OrdinalSortKey(1),
            explicitChildNodes: true,
            child: _Header(
              title: switch (phase) {
                _ when failed => context.l10n.breakdownBreakdown,
                BreakdownPhase.cut => context.l10n.breakdownCutOffHalfway,
                _ when _busy => context.l10n.breakdownBreakingItDown,
                _ => context.l10n.breakdownHereSTheBreakdown,
              },
              subtitle: input == null
                  ? null
                  : [
                      input.book.title,
                      _chapterLabel(input),
                      if (cut) context.l10n.breakdownSectionsReceived(count),
                      if (_finished && !cut) _countLabel(context, count),
                    ].join(' · '),
              semanticLabel: _busy
                  ? context.l10n.breakdownBreakingItDownHangOn
                  : input == null
                  ? context.l10n.breakdownBreakdown
                  : [
                      context.l10n.breakdownBreakdown2(
                        input.book.title,
                        _chapterLabel(input),
                      ),
                      if (_finished && !cut) ...[
                        _countLabel(context, count),
                        context.l10n.breakdownComplete,
                      ],
                    ].join(', '),
              backLabel: _busy
                  ? context.l10n.breakdownCancelBackToTranslation
                  : context.l10n.breakdownBackToTranslation,
              onBack: widget.onBack,
            ),
          ),
        ),
        Positioned(
          left: Layout.margin,
          right: Layout.margin,
          bottom: Layout.sheetPadding.bottom,
          child: Semantics(
            sortKey: const OrdinalSortKey(4),
            explicitChildNodes: true,
            child: AnimatedBuilder(
              animation: _actions,
              builder: (context, child) {
                final v = _actions.value;
                return ExcludeSemantics(
                  excluding: v >= 1,
                  child: IgnorePointer(
                    ignoring: v > 0.5,
                    child: _reduced
                        ? Opacity(opacity: 1 - v, child: child)
                        : Transform.translate(
                            offset: Offset(0, Layout.artinyaActions * v),
                            child: child,
                          ),
                  ),
                );
              },
              child: Row(spacing: 10, children: _buttons(thinking)),
            ),
          ),
        ),
      ],
    );
  }

  /// Scroll area of the explanation: top fade 20, bottom fade above the button
  /// only while the button is visible.
  Widget _scroll({required bool frozen, required Widget child}) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedBuilder(
          animation: _actions,
          builder: (context, scroll) {
            final away = _actions.value;
            return EdgeFadeScroll(
              bottom: EdgeFadeSide(
                20 * (1 - away),
                clear: (Layout.artinyaActions - Space.s4) * (1 - away),
              ),
              child: scroll!,
            );
          },
          child: SingleChildScrollView(
            key: _viewport,
            controller: _explain,
            physics: frozen
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: child,
          ),
        ),
      );

  /// Guess at how many sections are still unwritten (from the sentence count),
  /// at least one until the closing blocks start.
  int _placeholders(BreakdownInput? input, Breakdown shown) {
    if (shown.terms.isNotEmpty ||
        shown.links.isNotEmpty ||
        shown.practice != null) {
      return 0;
    }
    final sentences = input == null
        ? 12
        : input.sentences.fold(0, (n, p) => n + p.length);
    final guess = (sentences / 6).ceil().clamp(1, 6);
    return math.max(1, guess - shown.sections.length);
  }

  List<Widget> _buttons(bool thinking) {
    final s = _s;
    final reduced = _reduced;
    if (s.phase == BreakdownPhase.failed && widget.subsidy != null) {
      // The quota card has its own action ("Pakai key sendiri").
      return [
        Expanded(
          child: AppButton.secondary(
            label: context.l10n.chatBackToReading,
            onPressed: widget.onDone,
          ),
        ),
      ];
    }
    if (s.phase == BreakdownPhase.failed) {
      final f = _failureCopy(context, s.error);
      return [
        AppButton.secondary(
          label: context.l10n.chatBackToReading,
          onPressed: widget.onDone,
        ),
        Expanded(
          child: f.settings
              ? AppButton.primary(
                  label: context.l10n.meaningOpenSettings,
                  icon: AppIcons.next,
                  iconAfter: true,
                  onPressed: widget.onSettings,
                )
              : AppButton.primary(
                  label: context.l10n.meaningTryAgain,
                  icon: AppIcons.retry,
                  onPressed: widget.onRetry,
                ),
        ),
      ];
    }
    final cut = s.phase == BreakdownPhase.cut;
    final input = s.input;
    return [
      AnimatedSwitcher(
        duration: reduced ? Duration.zero : Motion.statusSwap,
        child: _busy && !cut
            ? StatusButton(
                key: ValueKey(thinking),
                label: thinking
                    ? context.l10n.meaningThinking
                    : context.l10n.meaningWriting,
              )
            : AppButton.secondary(
                key: const ValueKey('copy'),
                label: widget.copied
                    ? context.l10n.meaningCopied
                    : context.l10n.aiCopy,
                icon: widget.copied ? AppIcons.check : AppIcons.copy,
                onPressed: _finished && !cut && input != null
                    ? () => widget.onCopy(input, s.draft)
                    : null,
              ),
      ),
      Expanded(
        child: cut
            ? AppButton.secondary(
                label: context.l10n.chatBackToReading,
                onPressed: widget.onDone,
              )
            : AppButton.primary(
                label: context.l10n.chatBackToReading,
                onPressed: widget.onDone,
              ),
      ),
    ];
  }

  /// Failure before any content: replaces the explanation panel (shape 06
  /// Artinya · error / 10 empty API key). The text panel stays.
  Widget _failure(StabiloColors c) {
    if (widget.subsidy case final kind?) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: kind == SubsidyFailure.banned
            ? QuotaBannedCard(onUseOwnKey: widget.onUseOwnKey!)
            : QuotaExhaustedCard(
                now: DateTime.now(),
                onUseOwnKey: widget.onUseOwnKey!,
              ),
      );
    }
    final noKey = _s.error?.error == AiError.noApiKey;
    final f = _failureCopy(context, _s.error);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 14,
          children: [
            noKey
                ? IconTile(icon: AppIcons.key, bg: c.accent, fg: c.onAccent)
                : IconTile(icon: AppIcons.offline, bg: c.pink, fg: c.onPink),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s2,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    noKey ? context.l10n.meaningAddYourApiKeyFirst : f.title,
                    style: StabiloType.titleMd,
                  ),
                ),
                Text(
                  noKey
                      ? context.l10n.breakdownYourTranslationIsSavedButBreakdown
                      : f.body,
                  style: StabiloType.body.copyWith(color: c.ink2),
                ),
              ],
            ),
            if (noKey)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: context.l10n.meaningDonTHaveOneCreateIt),
                    TextSpan(
                      text: 'openrouter.ai/keys',
                      style: StabiloType.mono.copyWith(
                        fontSize: 13,
                        color: c.ink,
                      ),
                    ),
                  ],
                ),
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w400,
                  color: c.ink2,
                ),
              )
            else
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Space.s2),
                ),
                child: Text(
                  f.code,
                  style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _countLabel(BuildContext context, int sections) => sections == 1
    ? context.l10n.breakdownIdea
    : context.l10n.breakdownSections(sections);

/// Copy per error kind (table on the state board). [settings]: its yellow
/// button is "Buka Pengaturan", not "Coba lagi". An empty API key has its own
/// screen.
({String title, String body, String code, bool settings}) _failureCopy(
  BuildContext context,
  AiException? e,
) {
  final title = context.l10n.breakdownCouldnTBreakItDown;
  final body = context.l10n.meaningTheConnectionMightBeDownOr;
  return switch (e) {
    AiException(error: AiError.noApiKey) => (
      title: '',
      body: '',
      code: '',
      settings: true,
    ),
    AiException(error: AiError.network) => (
      title: context.l10n.breakdownYouReOffline,
      body: context.l10n.breakdownBreakdownNeedsInternetConnectAndTry,
      code: 'offline',
      settings: false,
    ),
    AiException(error: AiError.http, :final status)
        when status == 401 || status == 403 =>
      (
        title: context.l10n.peekApiKeyRejected,
        body: context.l10n.breakdownOpenrouterRejectedYourKeyCheckIt,
        code: context.l10n.breakdownKeyRejected(status ?? 0),
        settings: true,
      ),
    AiException(error: AiError.http, status: 402) => (
      title: context.l10n.peekOpenrouterCreditRanOut,
      body: context.l10n.breakdownTopUpAtOpenrouterAiThen,
      code: context.l10n.breakdownNoCredit,
      settings: false,
    ),
    AiException(error: AiError.invalidResponse) => (
      title: context.l10n.breakdownTheResponseFormatIsInvalid,
      body: context.l10n.breakdownTheAiReturnedSomethingLumaCan,
      code: context.l10n.breakdownInvalidFormat,
      settings: false,
    ),
    AiException(error: AiError.timeout) => (
      title: title,
      body: body,
      code: context.l10n.meaningTimeoutSeconds,
      settings: false,
    ),
    AiException(error: AiError.http, :final status) => (
      title: title,
      body: body,
      code: 'HTTP $status',
      settings: false,
    ),
    _ => (title: title, body: body, code: 'error', settings: false),
  };
}

/// Back button, screen title (status), and book · chapter · section count.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.backLabel,
    required this.onBack,
  });

  final String title;
  final String? subtitle;
  final String semanticLabel;
  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Layout.breakdownHeader,
    child: Row(
      spacing: 10,
      children: [
        CircleButton(
          semanticLabel: backLabel,
          icon: AppIcons.back,
          onPressed: onBack,
        ),
        Expanded(
          child: Semantics(
            header: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: StabiloType.label.copyWith(fontSize: 17)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w400,
                      color: context.stabilo.ink2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The translation panel.
///
/// Section numbers precede each section's first sentence ([sections] empty = no
/// numbers). A group of more than one paragraph gets spacing 12 and `¶n` in the
/// left column. [inline]: as tall as the text, with the original sentence below
/// it; otherwise at most [maxHeight] and it scrolls on its own. [highlight]
/// (section index) is highlighted yellow; [term] highlights the tapped term's
/// exact word instead of the section. [onNumber]: numbers are tappable (section
/// index).
class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.input,
    required this.sections,
    required this.typo,
    required this.inline,
    required this.inset,
    required this.maxHeight,
    this.highlight,
    this.term,
    this.badges = const [],
    this.onNumber,
    this.onFold,
  });

  final BreakdownInput input;
  final List<BreakdownSection> sections;
  final ReaderTypography typo;
  final bool inline;
  final double inset;
  final double maxHeight;
  final int? highlight;
  final BreakdownTerm? term;
  final List<GlobalKey> badges;
  final ValueChanged<int>? onNumber;

  /// Tapping the box (other than the number) or the bottom-corner chevron folds
  /// the panel.
  final VoidCallback? onFold;

  /// Sentence [s] (number [k]) with section / term-word highlighting.
  List<InlineSpan> _sentence(String s, int k, TextStyle marked) {
    final t = term;
    if (t != null && t.sentence == k && t.exact != null) {
      final at = s.toLowerCase().indexOf(t.exact!.toLowerCase());
      if (at >= 0) {
        final end = at + t.exact!.length;
        return [
          TextSpan(text: s.substring(0, at)),
          TextSpan(text: s.substring(at, end), style: marked),
          TextSpan(text: s.substring(end)),
        ];
      }
    }
    final h = highlight;
    final on =
        t == null &&
        h != null &&
        h < sections.length &&
        k >= sections[h].from &&
        k <= sections[h].to;
    return [TextSpan(text: s, style: on ? marked : null)];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final style = typo.style.copyWith(color: c.ink);
    final paragraphs = input.sentences;
    final many = paragraphs.length > 1;
    final starts = {for (final (i, s) in sections.indexed) s.from: i + 1};
    final badge = math.max(Layout.breakdownBadge, style.fontSize!);
    final marked = TextStyle(
      backgroundColor: c.highlight,
      color: c.onHighlight,
    );
    var k = 0;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        for (final (p, sentences) in paragraphs.indexed)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    for (final (i, s) in sentences.indexed) ...[
                      if (starts[++k] case final n?)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            key: n <= badges.length ? badges[n - 1] : null,
                            padding: const EdgeInsets.only(right: Space.s1),
                            child: GestureDetector(
                              onTap: onNumber == null
                                  ? null
                                  : () => onNumber!(n - 1),
                              child: _Number(
                                n,
                                size: badge,
                                fontSize: badge * 0.6,
                                label: context.l10n.breakdownSection(n),
                                onTap: onNumber == null
                                    ? null
                                    : () => onNumber!(n - 1),
                              ),
                            ),
                          ),
                        ),
                      ..._sentence(s, k, marked),
                      if (i < sentences.length - 1) const TextSpan(text: ' '),
                    ],
                  ],
                ),
                style: style,
              ),
              if (many)
                Positioned(
                  left: -Layout.breakdownGutter,
                  top: 0,
                  height: typo.lineExtent,
                  child: ExcludeSemantics(
                    child: Center(
                      child: Text(
                        '¶${p + 1}',
                        style: StabiloType.micro.copyWith(color: c.ink3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
    final padding = EdgeInsets.fromLTRB(
      Space.s4 + inset + (many ? Layout.breakdownGutter - Space.s2 : 0),
      14,
      Space.s4 + inset,
      14,
    );
    final decoration = BoxDecoration(
      color: c.sheet,
      borderRadius: BorderRadius.circular(Radii.lg),
      border: Border.all(color: c.track),
    );
    final label = sections.isEmpty
        ? context.l10n.breakdownTranslatedText
        : context.l10n.breakdownTranslatedTextSections(sections.length);
    // Box tip: signals it can be folded (the whole box folds too).
    final strip = onFold == null
        ? null
        : Semantics(
            button: true,
            label: context.l10n.breakdownCollapseTranslatedText,
            onTap: onFold,
            excludeSemantics: true,
            child: SizedBox(
              height: Layout.breakdownFoldStrip,
              child: Center(
                child: AppIcon(AppIcons.collapse, size: 18, color: c.ink2),
              ),
            ),
          );
    if (inline) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: context.l10n.breakdownTextBeingExplained,
        child: GestureDetector(
          onTap: onFold,
          child: Container(
            padding: strip == null ? padding : padding.copyWith(bottom: 0),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                text,
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.track)),
                  ),
                  child: Text(
                    input.original.join('\n\n'),
                    style: style.copyWith(
                      fontSize: 15,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                      color: c.ink2,
                    ),
                  ),
                ),
                ?strip,
              ],
            ),
          ),
        ),
      );
    }
    final scroll = EdgeFadeScroll(
      child: SingleChildScrollView(
        padding: onFold == null ? padding : padding.copyWith(bottom: 0),
        child: text,
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: GestureDetector(
        onTap: onFold,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: decoration,
          clipBehavior: Clip.antiAlias,
          child: onFold == null
              ? scroll
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: scroll),
                    strip!,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Section number circle (ink on canvas).
class _Number extends StatelessWidget {
  const _Number(
    this.n, {
    required this.size,
    required this.fontSize,
    required this.label,
    this.onTap,
  });

  final int n;
  final double size;
  final double fontSize;
  final String label;

  /// For VoiceOver only; finger taps are captured by the wrapper.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      label: label,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
        child: Text(
          '$n',
          style: StabiloType.label.copyWith(
            fontSize: fontSize,
            height: 1,
            color: c.canvas,
          ),
        ),
      ),
    );
  }
}

/// Bottom panel: the sections, then Tokoh & istilah, Nyambung ke, Praktekinnya
/// gini (empty blocks aren't shown). Placeholders stand in for sections not yet
/// written, the card lingers on top, and the cut-off banner sits at the bottom.
class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.visible,
    required this.input,
    required this.numbered,
    required this.typo,
    required this.solid,
    required this.writing,
    required this.faded,
    required this.placeholders,
    required this.blocks,
    required this.onTerm,
    required this.from,
    required this.onPeek,
    required this.slow,
    required this.cut,
    required this.onCancel,
    required this.onRetry,
  });

  final _Visible visible;
  final BreakdownInput? input;
  final bool numbered;
  final ReaderTypography typo;
  final Animation<double> solid;
  final bool writing;
  final bool faded;
  final int placeholders;

  /// Position key of each block for sync: sections, Tokoh & istilah, Praktek.
  final List<GlobalKey> blocks;

  /// Called when a term is tapped (with its source section index). Null = not
  /// tappable.
  final void Function(BreakdownTerm, int section)? onTerm;

  /// The group being broken down; locates the target of Nyambung ke cards.
  final GroupRef from;

  /// Called when a card is tapped. Null = cards aren't tappable yet
  /// (processing).
  final void Function(BreakdownLink, String where)? onPeek;
  final bool slow;
  final bool cut;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = visible.draft;
    // Keys exist only when sync is on (installed by [_ScreenState]).
    GlobalKey? key(int i) => i < blocks.length ? blocks[i] : null;
    final termsBlock = b.sections.length;
    final practiceBlock = termsBlock + (b.terms.isNotEmpty ? 1 : 0);
    final style = typo.style.copyWith(color: c.ink);
    final count = b.sections.length;
    // Index into the ordered [_fields]; locates the tip being written.
    final termsAt = b.sections.length * 3;
    final practiceAt = termsAt + b.terms.length * 2 + b.links.length * 2;

    /// Body text; the tip being written fades and isn't read by VoiceOver.
    Widget body(String t, int field) {
      if (!writing || field != visible.tail) return Text(t, style: style);
      return ExcludeSemantics(
        child: AnimatedBuilder(
          animation: solid,
          builder: (context, _) {
            if (!faded || solid.value >= 1) return Text(t, style: style);
            final split = splitTail(t);
            final alphas = tailAlphas.sublist(
              tailAlphas.length - split.tail.length,
            );
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: split.head),
                  for (final (i, w) in split.tail.indexed)
                    TextSpan(
                      text: w,
                      style: TextStyle(
                        color: c.ink.withValues(
                          alpha: alphas[i] + (1 - alphas[i]) * solid.value,
                        ),
                      ),
                    ),
                ],
              ),
              style: style,
            );
          },
        ),
      );
    }

    final paragraphOf = <int>[
      for (final (p, s) in (input?.sentences ?? const <List<String>>[]).indexed)
        for (final _ in s) p,
    ];
    final label = StabiloType.tag.copyWith(
      letterSpacing: 0.05 * 12,
      height: 18 / 12,
      color: c.ink2,
    );

    final sections = [
      for (final (i, s) in b.sections.indexed)
        Column(
          key: key(i),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (numbered) ...[
              Semantics(
                header: true,
                label: context.l10n.breakdownSectionOf(i + 1, count, s.title),
                excludeSemantics: true,
                child: Row(
                  spacing: 10,
                  children: [
                    _Number(
                      i + 1,
                      size: Layout.breakdownNumber,
                      fontSize: 14,
                      label: context.l10n.breakdownSection(i + 1),
                    ),
                    Expanded(
                      child: Text(
                        s.title,
                        style: StabiloType.titleSm.copyWith(color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (_paragraphs(paragraphOf, s) case final range?)
                Tag.section(range, tone: TagTone.muted),
            ],
            if (s.meaning.isNotEmpty) ...[
              Text(context.l10n.breakdownMeaning, style: label),
              body(s.meaning, i * 3 + 1),
            ],
            if (s.logic.isNotEmpty) ...[
              Text(context.l10n.breakdownLogic, style: label),
              body(s.logic, i * 3 + 2),
            ],
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s6,
      children: [
        if (slow) _SlowCard(onCancel: onCancel, onRetry: onRetry),
        ...sections,
        for (var i = 0; i < placeholders; i++) _SectionPlaceholder(typo: typo),
        if (b.terms.isNotEmpty)
          _Block(
            key: key(termsBlock),
            tag: Tag.section(
              context.l10n.breakdownPeopleTerms,
              tone: TagTone.muted,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, t) in b.terms.indexed)
                  _TermTap(
                    onTap:
                        onTerm != null &&
                            t.exact != null &&
                            _sectionOf(b.sections, t.sentence) != null
                        ? () => onTerm!(
                            t,
                            _sectionOf(b.sections, t.sentence)! - 1,
                          )
                        : null,
                    label: t.label,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: i == 0 ? 0 : Space.s3,
                        bottom: i == b.terms.length - 1 ? 0 : Space.s3,
                      ),
                      decoration: i == b.terms.length - 1
                          ? null
                          : BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: c.track),
                              ),
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: t.label),
                                if (_sectionOf(b.sections, t.sentence)
                                    case final n? when numbered)
                                  TextSpan(
                                    text: context.l10n.breakdownSection2(n),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      color: c.ink2,
                                    ),
                                  ),
                              ],
                            ),
                            style: StabiloType.label.copyWith(
                              fontSize: 16,
                              height: 1.4,
                              color: c.ink,
                            ),
                          ),
                          body(t.explanation, termsAt + i * 2 + 1),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (b.links.isNotEmpty)
          _Block(
            tag: Text(context.l10n.breakdownConnectsTo, style: label),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final l in b.links)
                  _LinkCard(link: l, input: input, from: from, onTap: onPeek),
              ],
            ),
          ),
        if (b.practice case final practice?)
          _Block(
            key: key(practiceBlock),
            tag: Tag.section(
              context.l10n.breakdownPuttingItIntoPractice,
              tone: TagTone.pink,
            ),
            child: _PracticeText(
              practice,
              writing: writing && practiceAt == visible.tail,
            ),
          ),
        if (cut) _CutBanner(kept: count, onRetry: onRetry),
      ],
    );
  }

  /// Returns `¶a–b` when section [s] crosses paragraphs.
  static String? _paragraphs(List<int> paragraphOf, BreakdownSection s) {
    if (s.to > paragraphOf.length || s.from < 1) return null;
    final a = paragraphOf[s.from - 1] + 1;
    final b = paragraphOf[s.to - 1] + 1;
    return a == b ? null : '¶$a–$b';
  }

  /// Returns the section number (1-based) that contains [sentence].
  static int? _sectionOf(List<BreakdownSection> sections, int? sentence) {
    if (sentence == null) return null;
    for (final (i, s) in sections.indexed) {
      if (sentence >= s.from && sentence <= s.to) return i + 1;
    }
    return null;
  }
}

/// Praktekinnya gini: teks UI tebal 20, bukan teks bacaan.
class _PracticeText extends StatelessWidget {
  const _PracticeText(this.text, {required this.writing});

  final String text;
  final bool writing;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: writing,
    child: Text(
      text,
      style: StabiloType.titleSm.copyWith(
        fontSize: 20,
        height: 1.35,
        letterSpacing: -0.01 * 20,
        color: context.stabilo.ink,
      ),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.tag, required this.child});

  final Widget tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.s3,
    children: [tag, child],
  );
}

/// Nyambung ke card. When the target is found it shows a line + chevron and a
/// tap opens the peek; otherwise it is plain text.
class _LinkCard extends ConsumerWidget {
  const _LinkCard({
    required this.link,
    required this.input,
    required this.from,
    required this.onTap,
  });

  final BreakdownLink link;
  final BreakdownInput? input;
  final GroupRef from;
  final void Function(BreakdownLink, String where)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final chapters = input?.chapters ?? const <String>[];
    final where = switch (link.chapter) {
      null =>
        input == null
            ? context.l10n.breakdownContinuation
            : context.l10n.breakdownContinuationOf(_chapterLabel(input!)),
      final n when n <= chapters.length && chapters[n - 1].trim().isNotEmpty =>
        chapters[n - 1].trim(),
      final n => context.l10n.breakdownChapter(n),
    };
    final found =
        ref
            .watch(breakdownPeekProvider((from: from, chapter: link.chapter)))
            .value !=
        null;
    final tap = found && onTap != null ? () => onTap!(link, where) : null;
    final text = link.why.isEmpty ? link.title : '${link.title}: ${link.why}';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Text(
          where.toUpperCase(),
          style: StabiloType.tag.copyWith(
            letterSpacing: 0.05 * 12,
            height: 18 / 12,
            color: c.ink2,
          ),
        ),
        Text(text, style: StabiloType.body.copyWith(height: 1.4, color: c.ink)),
      ],
    );
    if (!found) {
      return Semantics(
        label: context.l10n.breakdownConnectsTo2(where, link.title),
        excludeSemantics: true,
        child: body,
      );
    }
    return Semantics(
      button: true,
      label: context.l10n.breakdownConnectsToDoubleTapToPreview(
        where,
        link.title,
      ),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.menu),
          side: BorderSide(color: c.outline, width: Layout.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s3,
            ),
            child: Row(
              spacing: Space.s3,
              children: [
                Expanded(child: body),
                AppIcon(AppIcons.chevron, size: 18, color: c.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An unwritten section: circle + title + lines, as tall as the Aa text.
class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.typo});

  final ReaderTypography typo;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s1,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                width: Layout.breakdownNumber,
                height: Layout.breakdownNumber,
                decoration: BoxDecoration(
                  color: c.track,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(
                width: 170,
                child: Skeleton(
                  widths: [1],
                  lineExtent: Layout.breakdownNumber,
                ),
              ),
            ],
          ),
          Skeleton(widths: const [1, 1, 0.62], lineExtent: typo.lineExtent),
        ],
      ),
    );
  }
}

/// Shown when no token has arrived after 15 seconds: the request keeps running,
/// and this clears itself once a token arrives. One yellow button per screen
/// ("Balik baca"), so the card button is muted.
class _SlowCard extends StatelessWidget {
  const _SlowCard({required this.onCancel, required this.onRetry});

  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.sheet,
        line: c.track,
        tile: c.muted,
        icon: AppIcons.clock,
        iconColor: c.ink,
        title: context.l10n.meaningTakingALittleLonger,
        body: context.l10n.breakdownTheAiIsBusyGiveIt,
        actions: [
          Expanded(
            child: AppButton.secondary(
              label: context.l10n.dialogCancel,
              height: 40,
              onPressed: onCancel,
            ),
          ),
          Expanded(
            child: AppButton.secondary(
              label: context.l10n.meaningTryAgain,
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cut off midway: the complete sections ([kept]) stay above it.
class _CutBanner extends StatelessWidget {
  const _CutBanner({required this.kept, required this.onRetry});

  final int kept;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.pinkSoft,
        line: c.pink,
        tile: c.pink,
        icon: AppIcons.offline,
        iconColor: c.onPink,
        title: context.l10n.meaningCutOffHalfway,
        body: switch (kept) {
          0 => context.l10n.breakdownTheConnectionDroppedDuringTheBreakdown,
          1 => context.l10n.breakdownTheConnectionDroppedDuringTheBreakdown2,
          _ => context.l10n.breakdownTheConnectionDroppedDuringTheBreakdown3(
            kept,
          ),
        },
        actions: [
          Expanded(
            child: AppButton.primary(
              label: context.l10n.breakdownTryAgainFromTheStart,
              icon: AppIcons.retry,
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable term: highlights its exact word in the text panel.
class _TermTap extends StatelessWidget {
  const _TermTap({
    required this.onTap,
    required this.label,
    required this.child,
  });

  final VoidCallback? onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => onTap == null
      ? child
      : Semantics(
          button: true,
          hint: context.l10n.breakdownHighlightInTheText(label),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          ),
        );
}

/// The folded text panel (default): one row, tap to open.
class _FoldedPanel extends StatelessWidget {
  const _FoldedPanel({required this.count, required this.onTap});

  /// "4 bagian" / "1 gagasan"; null = not yet known (processing, error).
  final String? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      label: [context.l10n.breakdownOpenTranslatedText, ?count].join(', '),
      excludeSemantics: true,
      child: Material(
        color: c.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: c.track),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: Layout.breakdownFolded,
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: context.l10n.breakdownTranslatedText),
                        if (count != null)
                          TextSpan(
                            text: ' · $count',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: c.ink2,
                            ),
                          ),
                      ],
                    ),
                    style: StabiloType.label.copyWith(color: c.ink),
                  ),
                ),
                AppIcon(AppIcons.expand, size: 18, color: c.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Jump chips (3+ sections): a 44 round number, plus Istilah / Praktek pills.
/// The active one is ink. If they don't fit they scroll sideways and the right
/// edge fades.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.labels,
    required this.sections,
    required this.active,
    required this.onTap,
  });

  final List<String> labels;
  final int sections;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return SizedBox(
      height: Layout.touch,
      child: EdgeFadeScroll(
        axis: Axis.horizontal,
        top: EdgeFadeSide.none,
        bottom: const EdgeFadeSide(Layout.margin),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
          itemCount: labels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final on = i == active;
            final number = i < sections;
            return Semantics(
              button: true,
              selected: on,
              label: number
                  ? context.l10n.breakdownJumpToSectionOf(i + 1, sections)
                  : context.l10n.breakdownJumpTo(
                      labels[i] == context.l10n.breakdownTerms
                          ? context.l10n.breakdownPeopleTerms
                          : context.l10n.breakdownPuttingItIntoPractice,
                    ),
              excludeSemantics: true,
              child: Material(
                color: on ? c.ink : c.muted,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: Layout.touch),
                    padding: EdgeInsets.symmetric(horizontal: number ? 0 : 14),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: StabiloType.label.copyWith(
                        fontSize: number ? 15 : 14,
                        color: on ? c.canvas : c.ink,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
