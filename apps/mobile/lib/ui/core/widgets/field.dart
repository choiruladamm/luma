import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.hint,
    this.error,
    this.mono = true,
    this.secret = false,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.keyboardType,
    this.focusNode,
    this.onClear,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;

  /// Placeholder waktu kosong.
  final String? hint;

  /// Non-null = garis merah + pesan (ikon alert) gantiin [helper].
  final String? error;

  /// false = teks biasa (judul, nama), bukan font mono kayak API key.
  final bool mono;
  final bool secret;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;

  /// Ada = tombol hapus nongol selama field ada isinya.
  final VoidCallback? onClear;

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
            border: Border.all(
              color: widget.error != null ? c.danger : c.fieldLine,
              width: Layout.outline,
            ),
          ),
          child: Row(
            spacing: Space.s1,
            children: [
              Expanded(
                child: Semantics(
                  label: widget.label,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    obscureText: _hidden,
                    autocorrect: !widget.secret,
                    enableSuggestions: !widget.secret,
                    inputFormatters: widget.inputFormatters,
                    keyboardType: widget.keyboardType,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: c.ink,
                    style: (widget.mono ? StabiloType.mono : StabiloType.body)
                        .copyWith(
                          color: c.ink,
                          fontWeight: widget.mono ? null : FontWeight.w600,
                        ),
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint ?? '',
                      hintStyle: TextStyle(color: c.ink3),
                    ),
                  ),
                ),
              ),
              if (widget.onClear != null)
                ValueListenableBuilder(
                  valueListenable: widget.controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : CircleButton(
                          size: 40,
                          semanticLabel: 'Hapus ${widget.label}',
                          icon: AppIcons.close,
                          onPressed: widget.onClear,
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
        if (widget.error != null)
          Semantics(
            liveRegion: true,
            child: Row(
              spacing: Space.s1 + 2,
              children: [
                AppIcon(AppIcons.alert, size: 16, color: c.danger),
                Expanded(
                  child: Text(
                    widget.error!,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.danger,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (widget.helper != null)
          Text(
            widget.helper!,
            style: StabiloType.caption.copyWith(color: c.ink2),
          ),
      ],
    );
  }
}
