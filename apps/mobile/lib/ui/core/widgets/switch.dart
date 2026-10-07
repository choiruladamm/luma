import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';

/// Switch Stabilo 51 × 31 (board Komponen dasar). Nyala: kuning + garis ink,
/// knob krem bergaris. Mati: track pasir tanpa garis.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final track = value ? c.accent : c.track;
    final knob = light ? c.sheet : (value ? c.canvas : c.ink2);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: Motion.highlight,
          curve: Motion.highlightCurve,
          width: 51,
          height: 31,
          padding: const EdgeInsets.all(Layout.outline),
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(
              color: value ? c.accentBorder : track,
              width: Layout.outline,
            ),
          ),
          child: AnimatedAlign(
            duration: Motion.highlight,
            curve: Motion.highlightCurve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: knob,
                shape: BoxShape.circle,
                border: value && light
                    ? Border.all(color: c.outline, width: Layout.outline)
                    : null,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2E000000), // 18%
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
