import 'package:flutter/material.dart';

import '../../core/theme/stabilo_theme.dart';
import '../../core/theme/stabilo_tokens.dart';
import '../../core/theme/stabilo_type.dart';
import '../../core/widgets/luma_logo.dart';

/// Splash → shelf animation duration (board Splash → Rak · transisi): "Stabilo
/// kegores" 0–450, "Nyala!" 450–700, glides to the title 700–1000.
const splashDuration = Duration(milliseconds: 1000);

/// With Reduce Motion on: logo stays still, 200 ms fade to the shelf.
const splashReducedDuration = Duration(milliseconds: 200);

/// Splash layer above the app, once per start. The iOS launch screen is static
/// (the finished logo); the animation runs here once Flutter is up.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  late bool _done = !widget.enabled;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (!_done)
        Positioned.fill(
          child: SplashOverlay(onDone: () => setState(() => _done = true)),
        ),
    ],
  );
}

class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  // `preserve`: Reduce Motion must not skip its own 200 ms fade (the default
  // controller runs 20× faster when animations are disabled).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _ctrl
      ..duration = _reduced ? splashReducedDuration : splashDuration
      ..forward().whenComplete(widget.onDone);
  }

  bool _reduced = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Maps [from]..[to] (ms from the start) to 0..1.
  static double _span(double ms, double from, double to) =>
      ((ms - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => Theme(
    // Follows the iPhone, not the Aa theme: the iOS launch screen also follows
    // the iPhone, and the Aa theme is only read a few frames after start. The
    // shelf below is fully covered until the animation is released.
    data: stabiloTheme(MediaQuery.platformBrightnessOf(context)),
    child: Builder(builder: _frames),
  );

  Widget _frames(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;

    // The logo group (symbol 128 + 18 + wordmark 37 = 183) is centered on screen,
    // but the board Splash's margin-top −30 raises its center by 15.
    final symbolTop = screen.height / 2 - 15 - 183 / 2;
    final start = Offset(screen.width / 2, symbolTop + 64);
    // Lands in the shelf header's symbol slot.
    final end = Offset(
      Layout.margin - 3 + 14,
      top + (Layout.topBar - 28) / 2 + 14,
    );

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final ms = _ctrl.value * (_reduced ? 200 : 1000);
        // Stroke curve from the board Splash: cubic-bezier(.3, .7, .2, 1).
        final draw = _reduced
            ? 1.0
            : const Cubic(.3, .7, .2, 1).transform(_span(ms, 0, 450));
        final pop = _span(ms, 450, 700);
        final dot = _reduced
            ? 1.0
            : ms <= 0
            ? 0.0
            : pop < 0.6
            ? 1.25 * pop / 0.6
            : 1.25 - 0.25 * (pop - 0.6) / 0.4;
        final leave = _reduced ? 0.0 : _span(ms, 700, 1000);
        final fly = Curves.easeInOut.transform(leave);
        final fade = _reduced ? _span(ms, 0, 200) : leave;
        // Wordmark + tagline rise slowly with the dot (450–700), then fade as the
        // symbol glides away. Absent before the symbol is done.
        final word = _reduced
            ? 1.0
            : Curves.easeOut.transform(pop) * (1 - leave);
        final size = 128 + (28 - 128) * fly;
        final center = Offset.lerp(start, end, fly)!;

        return IgnorePointer(
          ignoring: fade >= 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 1 - fade,
                  child: ColoredBox(color: c.canvas),
                ),
              ),
              Positioned(
                left: start.dx - 103.6 / 2,
                // Rises 8 → 0 slowly with the fade in.
                top: symbolTop + 146 + (_reduced ? 0 : 8 * (1 - pop)),
                width: 103.6,
                child: Opacity(
                  opacity: word * (1 - (_reduced ? fade : 0)),
                  child: Image.asset(
                    'assets/brand/wordmark.png',
                    color: c.ink,
                    colorBlendMode: BlendMode.srcIn,
                    semanticLabel: 'luma',
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 58,
                child: Opacity(
                  opacity: word * (1 - (_reduced ? fade : 0)),
                  child: Text(
                    'See beyond the words.',
                    textAlign: TextAlign.center,
                    style: StabiloType.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: c.ink2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: center.dx - size / 2,
                top: center.dy - size / 2,
                child: Opacity(
                  // With Reduce Motion the symbol fades with the background.
                  opacity: _reduced ? 1 - fade : 1,
                  child: LumaLogo(
                    size: size,
                    draw: draw,
                    dot: dot,
                    shadow: light ? 1 - fly : 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
