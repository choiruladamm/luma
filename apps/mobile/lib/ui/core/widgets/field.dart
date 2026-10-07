import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Field input pengaturan (board Komponen 04, SecureField). [secret] =
/// disembunyiin + tombol liat; teks pake font mono.
class AppField extends StatefulWidget {
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.secret = false,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;
  final bool secret;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  late bool _hidden = widget.secret;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s2,
      children: [
        Text(
          widget.label,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: c.ink2,
          ),
        ),
        Container(
          height: 52,
          padding: const EdgeInsets.only(left: Space.s3, right: Space.s1),
          decoration: BoxDecoration(
            color: c.sheet,
            borderRadius: BorderRadius.circular(Radii.field),
            border: Border.all(color: c.fieldLine, width: Layout.outline),
          ),
          child: Row(
            spacing: Space.s1,
            children: [
              Expanded(
                child: Semantics(
                  label: widget.label,
                  child: TextField(
                    controller: widget.controller,
                    obscureText: _hidden,
                    autocorrect: !widget.secret,
                    enableSuggestions: !widget.secret,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: c.ink,
                    style: StabiloType.mono.copyWith(color: c.ink),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
              ),
              if (widget.secret)
                CircleButton(
                  size: 40,
                  semanticLabel: _hidden ? 'Liat key' : 'Sembunyiin key',
                  icon: _hidden ? AppIcons.show : AppIcons.hide,
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
            ],
          ),
        ),
        if (widget.helper != null)
          Text(
            widget.helper!,
            style: StabiloType.caption.copyWith(color: c.ink2),
          ),
      ],
    );
  }
}
