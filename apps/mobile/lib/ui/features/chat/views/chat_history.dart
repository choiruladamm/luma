import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import 'chat_copy.dart';
import 'chat_response.dart';

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
  });
  final List<ChatTurn> turns;
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
  ChatScrollAnchor? _lastAnchor;
  bool _restoring = true;
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
      } else if (!widget.turns.last.phase.isRunning) {
        _latest();
      }
      _restoring = false;
      _position();
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
          if (mounted) _latest();
        });
      }
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
          padding: const EdgeInsets.only(bottom: Space.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s4,
            children: [
              anchor(
                0,
                Container(
                  padding: const EdgeInsets.all(Space.s4),
                  decoration: BoxDecoration(
                    color: context.stabilo.muted,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.s2,
                    children: [
                      if (turn.quote != null)
                        Text(turn.quote!.text, style: StabiloType.caption),
                      Text(
                        turn.question,
                        style: StabiloType.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ChatResponse(
                key: ValueKey(turn.attemptRef),
                blocks: blocks,
                phase: phase,
                builder: (context, visible) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s5,
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      if (visible[i].text.isNotEmpty)
                        anchor(
                          i + 1,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: Space.s3,
                            children: [
                              SelectableText(
                                visible[i].text,
                                style: StabiloType.forBrightness(
                                  StabiloType.reading,
                                  Theme.of(context).brightness,
                                ),
                              ),
                              for (final source in visible[i].sources)
                                ChatSourceChip(
                                  source: source,
                                  onPressed: widget.onSource == null
                                      ? null
                                      : () => widget.onSource!(turn, source),
                                ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              if (answer != null && answer.note.isNotEmpty)
                Text(
                  answer.note,
                  style: StabiloType.body.copyWith(color: context.stabilo.ink2),
                ),
              if (phase == ChatPhase.done && turn.id == widget.turns.last.id)
                Semantics(
                  liveRegion: true,
                  label: phase.label,
                  child: const SizedBox.shrink(),
                ),
              if (phase != ChatPhase.done)
                Semantics(
                  liveRegion: true,
                  child: Text(label, style: StabiloType.caption),
                ),
            ],
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
    return Stack(
      key: _viewport,
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _position();
            return false;
          },
          child: EdgeFadeScroll(
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _turn(widget.turns[center - i - 1]),
                      childCount: center,
                    ),
                  ),
                  SliverList(
                    key: centerKey,
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _turn(widget.turns[center + i]),
                      childCount: widget.turns.length - center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_away)
          Positioned(
            right: 0,
            bottom: Space.s2,
            child: AppButton.secondary(
              label: 'Ke terbaru',
              icon: AppIcons.down,
              onPressed: () => _latest(),
            ),
          ),
      ],
    );
  }
}

/// Only verified complete blocks can supply a source action.
class ChatSourceChip extends StatelessWidget {
  const ChatSourceChip({super.key, required this.source, this.onPressed});
  final ChatSource source;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(Radii.sm),
    child: Container(
      constraints: const BoxConstraints(minHeight: Layout.touch),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: context.stabilo.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        spacing: Space.s2,
        children: [
          const AppIcon(AppIcons.book),
          Expanded(
            child: Text(source.chapterTitle, style: StabiloType.caption),
          ),
        ],
      ),
    ),
  );
}
