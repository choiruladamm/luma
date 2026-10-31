import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../reader/views/reader_capsule.dart';
import 'chat_context_card.dart';
import '../view_models/chat_view_model.dart';
import 'chat_composer.dart';
import 'chat_copy.dart';
import 'chat_history.dart';
import 'chat_source_label.dart';
import 'chat_source_sheet.dart';
import 'chat_sessions_view.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.bookId, this.launch});
  final int bookId;
  final ChatLaunchContext? launch;
  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView>
    with SingleTickerProviderStateMixin {
  late final _chrome = ReaderChrome(vsync: this);
  final _footerKey = GlobalKey();
  final _headerKey = GlobalKey();
  double _headerHeight = Layout.chatHeader;
  double _footerHeight = Layout.chatComposer;
  bool _scrolled = false;

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  void _measureFooter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _footerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final height = box.size.height;
      final header =
          _headerKey.currentContext?.findRenderObject() as RenderBox?;
      final headerHeight = header != null && header.hasSize
          ? header.size.height
          : _headerHeight;
      if ((height - _footerHeight).abs() > 0.5 ||
          (headerHeight - _headerHeight).abs() > 0.5) {
        setState(() {
          _footerHeight = height;
          _headerHeight = headerHeight;
        });
      }
    });
  }

  bool _scroll(ScrollNotification n) {
    if (n.depth != 0 || MediaQuery.accessibleNavigationOf(context)) {
      return false;
    }
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      final scrolled = n.metrics.pixels > n.metrics.minScrollExtent + 4;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    }
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _chrome.scrolled(n.scrollDelta ?? 0, dragging: true);
      if (n.metrics.pixels <= n.metrics.minScrollExtent) _chrome.show();
    }
    if (n is ScrollEndNotification) _chrome.release();
    return false;
  }

  Future<void> _readQuote(ChatQuote quote) async {
    if (_sourceOpen) return;
    setState(() => _sourceOpen = true);
    try {
      final result = await context.push<ReaderReturn>(
        Routes.chatQuote(widget.bookId),
        extra: quote,
      );
      if (result == ReaderReturn.reading && mounted) {
        await _navigate(() => _back(reading: true));
      }
    } finally {
      if (mounted) setState(() => _sourceOpen = false);
    }
  }

  void _back({bool reading = false}) {
    if (context.canPop()) {
      context.pop(reading ? ReaderReturn.reading : null);
    } else {
      context.go(Routes.reader(widget.bookId));
    }
  }

  bool _leaving = false;
  bool _sourceOpen = false;
  ({int turnId, String sourceId})? _selectedSource;
  ChatViewModel get _vm =>
      ref.read(chatViewModelProvider(widget.bookId).notifier);
  @override
  void initState() {
    super.initState();
    if (widget.launch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_vm.launch(widget.launch!));
      });
    }
  }

  Future<void> _navigate(VoidCallback action) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _vm.stop();
    if (!mounted) return;
    action();
    if (mounted) setState(() => _leaving = false);
  }

  Future<void> _source(ChatTurn turn, ChatSource source) async {
    if (_sourceOpen) return;
    setState(() {
      _sourceOpen = true;
      _selectedSource = (turnId: turn.id, sourceId: source.id);
    });
    try {
      final request = (
        bookId: widget.bookId,
        sessionId: turn.sessionId,
        turnId: turn.id,
        attempt: turn.attempt,
        sourceId: source.id,
      );
      final open = await showChatSourceSheet(
        context,
        request: request,
        snapshot: source,
      );
      if (open != true || !mounted) return;
      final result = await context.push<ReaderReturn>(
        Routes.chatSource(request),
      );
      if (result == ReaderReturn.reading && mounted) {
        await _navigate(() {
          if (context.canPop()) {
            context.pop(ReaderReturn.reading);
          } else {
            context.go(Routes.reader(widget.bookId));
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sourceOpen = false;
          _selectedSource = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatViewModelProvider(widget.bookId));
    final title = chatBookTitle(ref, widget.bookId);
    final pad = MediaQuery.paddingOf(context);
    _chrome.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _measureFooter();
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _scroll,
        child: AnimatedBuilder(
          animation: _chrome.hidden,
          builder: (context, _) {
            final hidden = MediaQuery.accessibleNavigationOf(context)
                ? 0.0
                : _chrome.hidden.value;
            final top = pad.top + _headerHeight + Space.s3;
            final bottom = pad.bottom + _footerHeight + Space.s4;
            return Stack(
              children: [
                Positioned.fill(
                  child: _body(
                    state,
                    padding: EdgeInsets.fromLTRB(
                      Layout.margin,
                      top,
                      Layout.margin,
                      bottom,
                    ),
                    topFade: EdgeFadeSide(
                      Space.s5,
                      clear: pad.top,
                      hold: _headerHeight * (1 - hidden),
                    ),
                    bottomFade: EdgeFadeSide(
                      Space.s5,
                      clear: bottom - Space.s2,
                    ),
                  ),
                ),
                Positioned(
                  left: Space.s3,
                  right: Space.s3,
                  top: pad.top,
                  child: IgnorePointer(
                    ignoring: hidden > 0.5,
                    child: ExcludeSemantics(
                      excluding: hidden > 0.5,
                      child: Transform.translate(
                        offset: Offset(0, -(pad.top + _headerHeight) * hidden),
                        child: Container(
                          key: _headerKey,
                          constraints: const BoxConstraints(
                            minHeight: Layout.chatHeader,
                          ),
                          decoration: BoxDecoration(
                            color: context.stabilo.canvas,
                            boxShadow: [
                              if (_scrolled && hidden < 0.5)
                                BoxShadow(
                                  color: context.stabilo.track,
                                  offset: const Offset(0, 1),
                                ),
                            ],
                          ),
                          child: Row(
                            spacing: Space.s2,
                            children: [
                              CircleButton(
                                semanticLabel:
                                    widget.launch?.origin.backLabel ??
                                    'Balik baca',
                                icon: AppIcons.back,
                                onPressed: _leaving
                                    ? null
                                    : () => _navigate(() => _back()),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Ngobrolin buku',
                                      style: StabiloType.titleXs.copyWith(
                                        fontSize: 15,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      title,
                                      style: StabiloType.caption.copyWith(
                                        color: context.stabilo.ink2,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.launch != null &&
                                  widget.launch!.origin !=
                                      ChatLaunchOrigin.reader)
                                CircleButton(
                                  semanticLabel: 'Balik baca',
                                  icon: AppIcons.book,
                                  onPressed: _leaving
                                      ? null
                                      : () => _navigate(
                                          () => _back(reading: true),
                                        ),
                                ),
                              CircleButton(
                                semanticLabel: 'Riwayat obrolan',
                                icon: AppIcons.history,
                                onPressed: _leaving
                                    ? null
                                    : () => _navigate(
                                        () => context.push(
                                          Routes.chatSessions(widget.bookId),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: Layout.margin,
                  right: Layout.margin,
                  bottom: pad.bottom + Space.s2,
                  child: NotificationListener<SizeChangedLayoutNotification>(
                    onNotification: (_) {
                      _measureFooter();
                      return false;
                    },
                    child: SizeChangedLayoutNotifier(
                      child: Column(
                        key: _footerKey,
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.s2,
                        children: [
                          if (state.archived ||
                              state.activeSession?.invalid == true) ...[
                            Container(
                              padding: const EdgeInsets.all(Space.s1),
                              decoration: BoxDecoration(
                                color: context.stabilo.sheet,
                                borderRadius: BorderRadius.circular(Radii.full),
                                border: Border.all(
                                  color: context.stabilo.capsuleLine,
                                  width: Layout.outline,
                                ),
                              ),
                              child: Row(
                                spacing: Space.s2,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: Space.s3,
                                      ),
                                      child: Text(
                                        state.archived
                                            ? 'Arsip · cuma bisa dibaca'
                                            : 'Riwayat ini gak bisa dilanjutkan.',
                                        style: StabiloType.caption,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  AppButton.primary(
                                    label: 'Obrolan baru',
                                    height: Layout.touch,
                                    onPressed: () =>
                                        unawaited(_vm.newSession()),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (!state.readOnly)
                            ChatComposer(
                              draft: state.draft,
                              hint: state.selectedQuote == null
                                  ? 'Tanya soal buku ini…'
                                  : 'Tanya soal kutipan ini…',
                              canSend: state.canSend,
                              running: state.phase?.isRunning ?? false,
                              enabled: !state.loading && !state.busy,
                              onChanged: _vm.setDraft,
                              onSend: () {
                                _chrome.show();
                                unawaited(_vm.send());
                              },
                              onStop: () => unawaited(_vm.stop()),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _actions(ChatState state) {
    final phase = state.phase ?? state.turns.lastOrNull?.phase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.s2,
      children: [
        if (state.problem != null)
          Text(state.problem!, style: StabiloType.caption),
        if (state.error != null)
          Semantics(
            liveRegion: true,
            child: Text(state.error!.chatMessage, style: StabiloType.caption),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            if (phase != null && !phase.isRunning && phase != ChatPhase.done)
              Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    if (phase.isFailure)
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: context.stabilo.pink,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.alertCircle,
                            size: 14,
                            color: context.stabilo.onPink,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        state.turns.lastOrNull?.draftLabel(phase) ??
                            phase.label,
                        style: StabiloType.caption.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: context.stabilo.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (state.error?.needsSettings ?? false)
              AppButton.secondary(
                label: 'Buka Pengaturan',
                height: Layout.touch,
                onPressed: () => _navigate(() => context.push(Routes.settings)),
              ),
            if (state.canContinue)
              AppButton.secondary(
                label: 'Lanjutkan',
                height: Layout.touch,
                onPressed: () => unawaited(_vm.continueExploration()),
              ),
            if (state.canRetry && !state.canContinue)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => unawaited(_vm.retry()),
                child: SizedBox(
                  height: Layout.touch,
                  child: Center(
                    widthFactor: 1,
                    child: AppButton.secondary(
                      label: 'Coba lagi',
                      icon: AppIcons.retry,
                      height: 36,
                      onPressed: () => unawaited(_vm.retry()),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _body(
    ChatState state, {
    required EdgeInsets padding,
    required EdgeFadeSide topFade,
    required EdgeFadeSide bottomFade,
  }) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    final quote = state.selectedQuote ?? state.turns.firstOrNull?.quote;
    final card = quote == null
        ? null
        : ChatContextCard(
            key: ValueKey(quote.anchors.first.paragraphHash),
            quote: quote,
            collapseOn: state.turns.length,
            onRead: state.archived ? null : () => _readQuote(quote),
          );
    if (state.turns.isNotEmpty) {
      return ChatHistory(
        preview: state.preview,
        indexLabel: state.indexLabel,
        key: ValueKey(state.activeSession?.id),
        turns: state.turns,
        anchor: state.scrollAnchor,
        phase: state.phase,
        onAnchor: _vm.setScrollAnchor,
        onSource: _source,
        suspended: _sourceOpen,
        selectedSource: _selectedSource,
        padding: padding,
        topFade: topFade,
        bottomFade: bottomFade,
        contextCard: card,
        lastActions: _actions(state),
        reserveAnswerSpace: true,
        chapterNumbers: ref
            .watch(chatChapterNumbersProvider(widget.bookId))
            .asData
            ?.value,
      );
    }
    final plain = state.book != null && quote == null;
    var prompt = 'Mau ngobrolin apa soal bukunya?';
    if (state.book == null) {
      prompt = 'Buku ini gak tersedia.';
    } else if (quote != null) {
      prompt = 'Mau tanya apa soal kutipan ini?';
    }
    final hint = switch ((quote != null, state.book != null)) {
      (true, _) => 'Tulis pertanyaan lo di bawah. Kutipan sama terjemahannya ikut kebaca sebagai konteks.',
      (_, true) =>
        'Tanya apa aja soal ${chatBookName(ref, widget.bookId)}. Jawabannya selalu ada sitasi ke bagian bukunya.',
      _ => null,
    };
    return EdgeFadeScroll(
      top: topFade,
      bottom: bottomFade,
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s6,
          children: [
            const ChatNotice(),
            ?card,
            Padding(
              padding: EdgeInsets.only(top: plain ? Space.s8 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Text(
                    prompt,
                    style: StabiloType.titleLg.copyWith(
                      fontSize: plain ? 24 : 22,
                      height: 1.2,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: StabiloType.body.copyWith(
                        fontSize: plain ? 15 : 14.5,
                        height: 1.45,
                        color: context.stabilo.ink2,
                      ),
                    ),
                ],
              ),
            ),
            _actions(state),
          ],
        ),
      ),
    );
  }
}
