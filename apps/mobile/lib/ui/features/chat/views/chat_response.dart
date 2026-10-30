import 'package:flutter/material.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../domain/pacing.dart';

/// Paces only safe text; transport completion and persistence remain independent.
class ChatResponse extends StatefulWidget {
  const ChatResponse({
    super.key,
    required this.blocks,
    required this.phase,
    required this.builder,
  });

  final List<ChatAnswerBlock> blocks;
  final ChatPhase phase;
  final Widget Function(BuildContext, List<ChatAnswerBlock>) builder;

  @override
  State<ChatResponse> createState() => _ChatResponseState();
}

class _ChatResponseState extends State<ChatResponse>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _pacer = Pacer();
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  late bool _live;
  int _shown = 0;
  bool _foreground = true;
  List<List<String>> _characters = const [];
  int get _available => _characters.fold(0, (n, text) => n + text.length);

  @override
  void initState() {
    super.initState();
    _live = widget.phase.isRunning;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ChatResponse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _characters = [
      for (final block in widget.blocks) block.text.characters.toList(),
    ];
    if (!_foreground ||
        !_live ||
        MediaQuery.disableAnimationsOf(context) ||
        !widget.phase.isRunning && widget.phase != ChatPhase.done) {
      _reveal();
    } else if (_shown < _available && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _reveal() {
    _pacer.finish(_available);
    _shown = _available;
    _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    if (dt <= 0) return;
    final shown = _pacer.step(
      dt,
      _available,
      done: widget.phase == ChatPhase.done,
    );
    if (shown != _shown) setState(() => _shown = shown);
    if (shown >= _available) _ticker.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) setState(_reveal);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var remaining = _shown;
    final visible = <ChatAnswerBlock>[];
    for (var i = 0; i < widget.blocks.length; i++) {
      final block = widget.blocks[i];
      final characters = _characters[i];
      final whole = remaining >= characters.length;
      visible.add(
        ChatAnswerBlock(
          text: whole ? block.text : characters.take(remaining).join(),
          kind: block.kind,
          sources: whole ? block.sources : const [],
        ),
      );
      remaining = (remaining - characters.length).clamp(0, _shown);
    }
    return widget.builder(context, visible);
  }
}
