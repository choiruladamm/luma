import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/ai_status.dart';
import '../../../core/widgets/edge_fade.dart';
import 'chat_answer_blocks.dart';
import 'chat_copy.dart';
import 'chat_response.dart';
import 'chat_context_card.dart';
import 'chat_source_label.dart';

class ChatHistory extends StatefulWidget {
  const ChatHistory({
    super.key,
    required this.turns,
    required this.onAnchor,
    this.anchor,
    this.phase,
    this.preview,
    this.indexLabel,
    this.onSource,
    this.suspended = false,
    this.selectedSource,
    this.padding = EdgeInsets.zero,
    this.topFade = EdgeFadeSide.standard,
    this.bottomFade = EdgeFadeSide.standard,
    this.contextCard,
    this.lastActions,
    this.reserveAnswerSpace = false,
    this.chapterNumbers,
    this.typo,
  });
  final List<ChatTurn> turns;
  final ({int turnId, String sourceId})? selectedSource;
  final EdgeInsets padding;
  final EdgeFadeSide topFade, bottomFade;
  final Widget? contextCard, lastActions;
  final bool reserveAnswerSpace;
  final Map<int, int>? chapterNumbers;

  /// Tipografi Aa; kosong = default Aa.
  final ReaderTypography? typo;
  final bool suspended;
  final ChatScrollAnchor? anchor;
  final ChatPhase? phase;
  final ({ChatAttemptRef attempt, List<ChatAnswerBlock> blocks})? preview;
  final String? indexLabel;
  final void Function(ChatTurn, ChatSource)? onSource;
  final ValueChanged<ChatScrollAnchor> onAnchor;
  @override
  State<ChatHistory> createState() => _ChatHistoryState();
}

class _ChatHistoryState extends State<ChatHistory> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _blocks = <({int turnId, int blockIndex}), GlobalKey>{};
  final _rendered =
      <
        int,
        ({
          ChatTurn turn,
          ChatPhase phase,
          List<ChatAnswerBlock> blocks,
          String label,
          Widget child,
        })
      >{};
  late final int _centerId;
  bool _away = false;
  double _turnHeight = 0;
  ChatScrollAnchor? _lastAnchor;
  bool _restoring = true;

  /// Isi baru keliatan setelah posisi awal kepasang *dan* fade tepi atas udah
  /// nyala: fade-nya cuma hidup kalau udah di-scroll, jadi tanpa ini teks di
  /// belakang status bar/header keliatan sebentar pas layar baru kebuka.
  bool _revealed = false;
  Timer? _reveal;
  @override
  void initState() {
    super.initState();
    _centerId = widget.anchor?.turnId ?? widget.turns.first.id;
    _scroll.addListener(_position);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = widget.anchor;
      final target = anchor == null
          ? null
          : _blocks[(turnId: anchor.turnId, blockIndex: anchor.blockIndex)]
                ?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: anchor!.alignment.clamp(0, 1),
        );
      } else if (widget.reserveAnswerSpace &&
          widget.turns.last.phase.isRunning) {
        _question();
      } else if (!widget.turns.last.phase.isRunning) {
        _latest();
      }
      _restoring = false;
      _position();
      _reveal = Timer(Motion.edgeFade * 2, () {
        if (mounted) setState(() => _revealed = true);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered.clear();
  }

  @override
  void didUpdateWidget(ChatHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rendered.remove(widget.turns.last.id);
    if (oldWidget.selectedSource != widget.selectedSource ||
        oldWidget.chapterNumbers != widget.chapterNumbers ||
        oldWidget.typo != widget.typo) {
      _rendered.clear();
    }
    if (oldWidget.suspended && !widget.suspended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _position();
      });
    }
    if (oldWidget.turns.last.id != widget.turns.last.id) {
      _rendered.remove(oldWidget.turns.last.id);
      if (widget.turns.length > oldWidget.turns.length &&
          widget.turns.last.phase.isRunning) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _question();
        });
      }
    }
  }

  void _question([int remaining = 8]) {
    if (!_scroll.hasClients || widget.suspended) return;
    final target =
        _blocks[(turnId: widget.turns.last.id, blockIndex: 0)]?.currentContext;
    if (target == null) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (remaining > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _question(remaining - 1);
        });
      }
      return;
    }
    final box = target.findRenderObject() as RenderBox;
    final root = _viewport.currentContext!.findRenderObject() as RenderBox;
    final offset =
        _scroll.offset +
        box.localToGlobal(Offset.zero, ancestor: root).dy -
        widget.padding.top;
    final destination = offset.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(destination);
    } else {
      _scroll.animateTo(
        destination,
        duration: Motion.jump,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _latest([int remaining = 8]) {
    if (!_scroll.hasClients || widget.suspended) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    // Lazy slivers refine their extent after a jump; only a requested jump retries.
    if (remaining > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _scroll.position.extentAfter > 0) {
          _latest(remaining - 1);
        }
      });
    }
  }

  void _position() {
    if (!_scroll.hasClients || widget.suspended) return;
    final away = _scroll.position.extentAfter > Layout.chatFollowDistance;
    if (away != _away) setState(() => _away = away);
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    for (final entry in _blocks.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy - top;
      if (y + box.size.height > 0 && y < viewport.size.height) {
        final ChatScrollAnchor anchor = (
          turnId: entry.key.turnId,
          blockIndex: entry.key.blockIndex,
          alignment: (y / viewport.size.height).clamp(0, 1),
        );
        if (anchor != _lastAnchor) {
          _lastAnchor = anchor;
          widget.onAnchor(anchor);
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Widget _turn(ChatTurn turn) {
    Widget anchor(int index, Widget child) => KeyedSubtree(
      key: _blocks.putIfAbsent((
        turnId: turn.id,
        blockIndex: index,
      ), GlobalKey.new),
      child: child,
    );
    final typo =
        widget.typo ??
        ReaderTypography(const ReaderPrefs(), Theme.of(context).brightness);
    final answer = turn.answer;
    final active = widget.preview;
    final blocks =
        answer?.blocks ??
        (active?.attempt == turn.attemptRef ? active!.blocks : turn.preview);
    final phase = turn.id == widget.turns.last.id
        ? widget.phase ?? turn.phase
        : turn.phase;
    final label = turn.id == widget.turns.last.id
        ? widget.indexLabel ?? turn.draftLabel(phase)
        : turn.draftLabel(phase);
    final cached = _rendered[turn.id];
    if (cached != null &&
        identical(cached.turn, turn) &&
        cached.phase == phase &&
        identical(cached.blocks, blocks) &&
        cached.label == label) {
      return cached.child;
    }
    final child = Center(
      key: ValueKey(turn.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.chatTextWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.s8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: turn.id == widget.turns.last.id ? _turnHeight : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s4,
              children: [
                anchor(
                  0,
                  Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: Layout.chatBubbleFraction,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: Layout.chatBubblePadding,
                          decoration: BoxDecoration(
                            color: context.stabilo.muted,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(Radii.lg),
                              topRight: Radius.circular(Radii.lg),
                              bottomLeft: Radius.circular(Radii.lg),
                              bottomRight: Radius.circular(Radii.chatTail),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Space.s2,
                            children: [
                              Text(
                                turn.question,
                                style: StabiloType.body.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (blocks.isNotEmpty || phase.isRunning)
                  ChatResponse(
                    key: ValueKey(turn.attemptRef),
                    blocks: blocks,
                    phase: phase,
                    builder: (context, visible) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: typo.paragraphGap,
                      children: [
                        if (phase.isRunning &&
                            visible.every((b) => b.text.isEmpty))
                          Row(
                            spacing: Space.s2,
                            children: [
                              WritingDots(color: context.stabilo.ink2),
                              Flexible(
                                child: Text(label, style: StabiloType.caption),
                              ),
                            ],
                          ),
                        ChatAnswerBlocks(
                          blocks: visible,
                          typo: typo,
                          running: phase.isRunning,
                          anchor: anchor,
                          chip: (source) => ChatSourceChip(
                            source: source,
                            label: chatSourceLabel(
                              source,
                              widget.chapterNumbers,
                            ),
                            selected:
                                widget.selectedSource ==
                                (turnId: turn.id, sourceId: source.id),
                            onPressed: widget.onSource == null
                                ? null
                                : () => widget.onSource!(turn, source),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (answer != null && answer.note.isNotEmpty)
                  Text(
                    answer.note,
                    style: StabiloType.body.copyWith(
                      color: context.stabilo.ink2,
                    ),
                  ),
                if (phase == ChatPhase.done && turn.id == widget.turns.last.id)
                  Semantics(
                    liveRegion: true,
                    label: phase.label,
                    child: const SizedBox.shrink(),
                  ),
                if (phase != ChatPhase.done &&
                    (phase.isRunning ||
                        turn.id != widget.turns.last.id ||
                        widget.lastActions == null) &&
                    !(phase.isRunning && blocks.every((b) => b.text.isEmpty)))
                  Semantics(
                    liveRegion: true,
                    child: Text(label, style: StabiloType.caption),
                  ),
                if (turn.id == widget.turns.last.id &&
                    widget.lastActions != null)
                  widget.lastActions!,
              ],
            ),
          ),
        ),
      ),
    );
    _rendered[turn.id] = (
      turn: turn,
      phase: phase,
      blocks: blocks,
      label: label,
      child: child,
    );
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final found = widget.turns.indexWhere((t) => t.id == _centerId);
    final center = found < 0 ? 0 : found;
    const centerKey = ValueKey('chat-history-center');
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.reserveAnswerSpace
            ? (constraints.maxHeight - widget.padding.vertical - Space.s8)
                  .clamp(0.0, double.infinity)
            : 0.0;
        if (height != _turnHeight) {
          _turnHeight = height;
          _rendered.clear();
        }
        return Stack(
          key: _viewport,
          children: [
            NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _position();
                return false;
              },
              // Disembunyiin sampai posisi awal kepasang, biar gak keliatan loncat.
              child: AnimatedOpacity(
                opacity: _revealed ? 1 : 0,
                duration: Motion.edgeFade,
                child: EdgeFadeScroll(
                  top: widget.topFade,
                  bottom: widget.bottomFade,
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      if (!widget.suspended &&
                          !_restoring &&
                          notification.depth == 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _position();
                        });
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      controller: _scroll,
                      center: centerKey,
                      slivers: [
                        if (center > 0) SliverToBoxAdapter(child: _intro()),
                        SliverPadding(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.padding.left,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _turn(widget.turns[center - i - 1]),
                              childCount: center,
                            ),
                          ),
                        ),
                        SliverPadding(
                          key: centerKey,
                          padding: EdgeInsets.fromLTRB(
                            widget.padding.left,
                            center == 0 ? widget.padding.top : 0,
                            widget.padding.right,
                            widget.padding.bottom,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                if (center == 0 && i == 0) {
                                  return _intro(padded: false);
                                }
                                return _turn(
                                  widget.turns[center +
                                      i -
                                      (center == 0 ? 1 : 0)],
                                );
                              },
                              childCount:
                                  widget.turns.length -
                                  center +
                                  (center == 0 ? 1 : 0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_away)
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.padding.bottom,
                child: Center(
                  child: ChatJumpButton(
                    writing: widget.turns.last.phase.isRunning,
                    onPressed: () => _latest(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _intro({bool padded = true}) => Padding(
    padding: padded
        ? EdgeInsets.fromLTRB(
            widget.padding.left,
            widget.padding.top,
            widget.padding.right,
            Space.s8,
          )
        : const EdgeInsets.only(bottom: Space.s8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s4,
      children: [
        const ChatNotice(),
        if (widget.contextCard != null) widget.contextCard!,
      ],
    ),
  );
}

/// Only verified complete blocks can supply a source action.
class ChatSourceChip extends StatelessWidget {
  const ChatSourceChip({
    super.key,
    required this.source,
    required this.label,
    this.onPressed,
    this.selected = false,
  });
  final ChatSource source;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) => Transform.translate(
    // Naik 2pt dari garis dasar teks, seperti di board.
    offset: const Offset(0, -2),
    child: Semantics(
      button: true,
      label:
          '${source.chapterTitle}, paragraf ${source.anchors.first.paragraphIndex + 1}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // Area tap melebar 2pt ke samping; tinggi dijaga 20 biar baris teks gak melar.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? context.stabilo.accent : context.stabilo.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            // widthFactor: Container beralignment ngisi lebar penuh di WidgetSpan.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: StabiloType.caption.copyWith(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? context.stabilo.onAccent
                      : context.stabilo.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Kapsul ↓ di atas composer; titik kuning = jawaban lagi ditulis.
class ChatJumpButton extends StatelessWidget {
  const ChatJumpButton({
    super.key,
    required this.writing,
    required this.onPressed,
  });
  final bool writing;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      label: 'Ke terbaru',
      child: GestureDetector(
        onTap: onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: Layout.touch,
              height: Layout.touch,
              decoration: BoxDecoration(
                color: c.sheet,
                shape: BoxShape.circle,
                border: Border.all(color: c.outline, width: Layout.outline),
                boxShadow: Elevation.capsule(c, Theme.of(context).brightness),
              ),
              child: Center(child: AppIcon(AppIcons.down, color: c.ink)),
            ),
            if (writing)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.outline, width: Layout.outline),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
