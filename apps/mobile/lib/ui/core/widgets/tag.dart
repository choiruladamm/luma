import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

enum TagTone { accent, pink, muted }

/// Small pill-shaped label (board Komponen 01, Tag & chip).
///
/// - [Tag.section]: section title in a sheet ("TERJEMAHAN"), CAPS.
/// - [Tag.status]: progress chip on a book tile ("72%", "Kelar!", "Baru").
class Tag extends StatelessWidget {
  const Tag.section(this.label, {super.key, this.tone = TagTone.accent})
    : _section = true,
      icon = null;

  const Tag.status(
    this.label, {
    super.key,
    this.tone = TagTone.muted,
    this.icon,
  }) : _section = false;

  final String label;

  /// Small icon before the text ("Kelar!" + check). [Tag.status] only.
  final List<List<dynamic>>? icon;
  final TagTone tone;
  final bool _section;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (bg, fg) = switch (tone) {
      TagTone.accent => (c.accent, c.onAccent),
      TagTone.pink => (c.pink, c.onPink),
      TagTone.muted => (c.muted, c.ink),
    };
    // Only as wide as its text, under any parent. Container & Align
    // `widthFactor` aren't enough in a Column(stretch): the parent's tight
    // constraints win. The outermost Align loosens the constraints first.
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        height: _section ? 24 : 22,
        padding: EdgeInsets.symmetric(horizontal: _section ? 10 : Space.s2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Align(
          widthFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.s1,
            children: [
              if (icon != null) AppIcon(icon!, size: 12, color: fg),
              Text(
                _section ? label.toUpperCase() : label,
                style: (_section ? StabiloType.tag : StabiloType.micro)
                    .copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
