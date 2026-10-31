import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.draft,
    required this.canSend,
    required this.running,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    required this.onStop,
    this.hint = 'Tanyain isi buku ini…',
  });
  final String draft;
  final bool canSend, running, enabled;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend, onStop;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final _text = TextEditingController(text: widget.draft);
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});
  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.draft) {
      _text.value = TextEditingValue(
        text: widget.draft,
        selection: TextSelection.collapsed(offset: widget.draft.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.chatComposer),
        border: Border.all(
          color: _focus.hasFocus ? c.outline : c.capsuleLine,
          width: Layout.outline,
        ),
        boxShadow: Elevation.capsule(c, Theme.of(context).brightness),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s3,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.s2,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: StabiloType.body.copyWith(
                      height: 22 / 16,
                      color: c.ink,
                    ),
                    cursorColor: c.ink,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: StabiloType.body.copyWith(
                        height: 22 / 16,
                        color: c.ink3,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
              CircleButton(
                semanticLabel: widget.running
                    ? 'Hentikan jawaban'
                    : 'Kirim pertanyaan',
                icon: widget.running ? null : AppIcons.send,
                glyph: widget.running
                    ? Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: c.canvas,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                    : null,
                size: Layout.chatSend,
                active: widget.canSend,
                inverse: widget.running,
                onPressed: widget.running
                    ? widget.onStop
                    : (widget.canSend ? widget.onSend : null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
