import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

enum TagTone { accent, pink, muted }

/// Label kecil berbentuk pill (board Komponen 01, Tag & chip).
///
/// - [Tag.section]: judul section di sheet ("TERJEMAHAN"), CAPS.
/// - [Tag.status]: chip progres di tile buku ("72%", "Kelar!", "Baru").
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

  /// Ikon kecil di depan teks ("Kelar!" + centang). Cuma [Tag.status].
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
    // Selebar teksnya aja, di parent mana pun. Container & Align `widthFactor`
    // gak cukup di Column(stretch): constraint ketat dari parent menang. Align
    // terluar ngelonggarin constraint-nya dulu.
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
