import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import 'chat_copy.dart';

class ChatHistory extends StatefulWidget {
  const ChatHistory({
    super.key,
    required this.turns,
    required this.onAnchor,
    this.anchor,
    this.phase,
    this.indexLabel,
  });
  final List<ChatTurn> turns;
  final ChatScrollAnchor? anchor;
  final ChatPhase? phase;
  final String? indexLabel;
  final ValueChanged<ChatScrollAnchor> onAnchor;
  @override
  State<ChatHistory> createState() => _ChatHistoryState();
}

class _ChatHistoryState extends State<ChatHistory> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _blocks = <({int turnId, int blockIndex}), GlobalKey>{};
  late final int _centerId;
  bool _away = false;
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
      } else {
        _latest();
      }
      _restoring = false;
      _position();
    });
  }

  @override
  void didUpdateWidget(ChatHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_away &&
        (oldWidget.turns != widget.turns || oldWidget.phase != widget.phase)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _latest();
      });
    }
  }

  void _latest() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _position() {
    if (!_scroll.hasClients) return;
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
        widget.onAnchor((
          turnId: entry.key.turnId,
          blockIndex: entry.key.blockIndex,
          alignment: (y / viewport.size.height).clamp(0, 1),
        ));
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
    final phase = turn.id == widget.turns.last.id
        ? widget.phase ?? turn.phase
        : turn.phase;
    return Padding(
      key: ValueKey(turn.id),
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
          if (answer != null)
            for (var i = 0; i < answer.blocks.length; i++)
              anchor(
                i + 1,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s3,
                  children: [
                    SelectableText(
                      answer.blocks[i].text,
                      style: StabiloType.forBrightness(
                        StabiloType.reading,
                        Theme.of(context).brightness,
                      ),
                    ),
                    for (final source in answer.blocks[i].sources)
                      ChatSourceChip(source: source),
                  ],
                ),
              ),
          if (answer != null && answer.note.isNotEmpty)
            Text(
              answer.note,
              style: StabiloType.body.copyWith(color: context.stabilo.ink2),
            ),
          if (phase != ChatPhase.done)
            Semantics(
              liveRegion: true,
              child: Text(
                turn.id == widget.turns.last.id
                    ? widget.indexLabel ?? phase.label
                    : phase.label,
                style: StabiloType.caption,
              ),
            ),
        ],
      ),
    );
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
                if (!_restoring &&
                    !_away &&
                    notification.depth == 0 &&
                    notification.metrics.extentAfter > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_away) _latest();
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
              onPressed: _latest,
            ),
          ),
      ],
    );
  }
}

/// Snapshot label only; verified preview/reader navigation belongs to #122.
class ChatSourceChip extends StatelessWidget {
  const ChatSourceChip({super.key, required this.source});
  final ChatSource source;
  @override
  Widget build(BuildContext context) => Container(
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
        Expanded(child: Text(source.chapterTitle, style: StabiloType.caption)),
      ],
    ),
  );
}
