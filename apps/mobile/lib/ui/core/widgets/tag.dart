import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';

enum TagTone { accent, pink, muted }

/// Label kecil berbentuk pill (board Komponen 01, Tag & chip).
///
/// - [Tag.section]: judul section di sheet ("TERJEMAHAN"), CAPS.
/// - [Tag.status]: chip progres di tile buku ("72%", "Kelar!", "Baru").
class Tag extends StatelessWidget {
  const Tag.section(this.label, {super.key, this.tone = TagTone.accent})
    : _section = true;

  const Tag.status(this.label, {super.key, this.tone = TagTone.muted})
    : _section = false;

  final String label;
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
    return Container(
      height: _section ? 24 : 22,
      padding: EdgeInsets.symmetric(horizontal: _section ? 10 : Space.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      // Selebar teksnya aja. (`alignment` di Container bikin dia melebar
      // ngisi semua lebar yang dikasih parent.)
      child: Align(
        widthFactor: 1,
        child: Text(
          _section ? label.toUpperCase() : label,
          style: (_section ? StabiloType.tag : StabiloType.micro).copyWith(
            color: fg,
          ),
        ),
      ),
    );
  }
}
