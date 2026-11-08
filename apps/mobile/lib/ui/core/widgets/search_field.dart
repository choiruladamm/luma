import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Kolom cari pill 44 (board Cari kata 1–5). Diam: latar muted. Fokus:
/// garis tinta 1,5 + cincin kuning 4. Tombol × muncul selama ada isi.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.clearLabel,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? clearLabel;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final focused = _focus.hasFocus;
    return Semantics(
      container: true,
      child: Container(
        height: Layout.searchField,
        padding: const EdgeInsets.only(left: 14, right: Space.s3),
        decoration: BoxDecoration(
          color: focused ? c.sheet : c.muted,
          borderRadius: BorderRadius.circular(Radii.full),
          border: focused
              ? Border.all(color: c.ink, width: Layout.outline)
              : null,
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.55),
                    spreadRadius: Layout.searchRing,
                  ),
                ]
              : null,
        ),
        child: Row(
          spacing: Space.s2,
          children: [
            AppIcon(AppIcons.search, size: 18, color: c.ink2),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                cursorColor: c.ink,
                style: StabiloType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: StabiloType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink2,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: widget.controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : Semantics(
                      button: true,
                      label: widget.clearLabel ?? context.l10n.searchClearField,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.controller.clear();
                          widget.onChanged?.call('');
                        },
                        child: Container(
                          width: Layout.searchClear,
                          height: Layout.searchClear,
                          decoration: BoxDecoration(
                            color: c.track,
                            shape: BoxShape.circle,
                          ),
                          // Center: tanpa ini constraint ketat Container maksa
                          // ikon sebesar lingkarannya.
                          child: Center(
                            child: AppIcon(
                              AppIcons.close,
                              size: 12,
                              color: c.ink2,
                              strokeWidth: Layout.iconStroke,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
