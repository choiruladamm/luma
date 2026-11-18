import 'package:flutter/animation.dart';

import '../../../core/scroll_run.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// Hides the header (title + X) and the buttons (Salin / Lanjut) of the Artinya
/// sheet as the finger scrolls (board Ngumpet · Opsi A). Thresholds in [ScrollRun].
///
/// - Header: follows the content 1:1 while scrolling down, gone after
///   [Layout.artinyaHeader]. Scrolling up ≥ 12pt: comes back down from the top
///   following the finger, and on release in the middle snaps to the nearest end.
///   It only returns by scrolling up, or at the very top.
/// - Buttons: slide out after scrolling down ≥ 24pt, return on scrolling up ≥ 12pt
///   or at the bottom.
///
/// Never hides when [enabled] is false, or when all content fits.
/// Reduce motion: no sliding and no following the finger, fade only.
class MeaningChrome {
  MeaningChrome({required TickerProvider vsync})
    : header = AnimationController(vsync: vsync, duration: Motion.sheetChrome),
      actions = AnimationController(vsync: vsync, duration: Motion.sheetChrome);

  /// 0 = visible, 1 = hidden.
  final AnimationController header;
  final AnimationController actions;

  /// false = never hides (non-result states, VoiceOver).
  bool enabled = true;
  bool reduceMotion = false;

  final _run = ScrollRun();

  /// Scrolling up while the header follows the finger.
  bool _following = false;

  /// Visible reading height in a sheet of [sheetHeight]: the sheet minus the visible
  /// chrome (board: 335 with full chrome, 516 when hidden).
  double readHeight(double sheetHeight) {
    final top =
        Layout.artinyaGrabberZone +
        (Layout.artinyaHeader - Layout.artinyaGrabberZone) * (1 - header.value);
    final bottom = Layout.artinyaActions * (1 - actions.value);
    return sheetHeight - top - bottom;
  }

  /// Scroll from the finger. [delta] > 0 = scrolling down.
  void scrolled({
    required double pixels,
    required double max,
    required double delta,
  }) {
    if (!enabled || max <= 0 || pixels <= 0) {
      if (!enabled || max <= 0 || header.value != 0 || actions.value != 0) {
        show();
      }
      return;
    }
    final intent = _run.add(delta);
    if (delta > 0) _following = false;
    if (intent == ChromeIntent.show) _following = true;

    if (reduceMotion) {
      if (intent == ChromeIntent.hide) _animate(header, 1);
      if (intent == ChromeIntent.show) _animate(header, 0);
    } else if (delta > 0 || _following) {
      header.value = (header.value + delta / Layout.artinyaHeader).clamp(
        0.0,
        1.0,
      );
    }

    if (pixels >= max - 1 || intent == ChromeIntent.show) {
      _animate(actions, 0);
    } else if (intent == ChromeIntent.hide) {
      _animate(actions, 1);
    }
  }

  /// Finger released / scroll stopped: a header left hanging mid-way snaps to the
  /// nearest end (only once past the header zone).
  void release(double pixels) {
    _following = false;
    if (reduceMotion || pixels < Layout.artinyaHeader) return;
    if (header.value > 0 && header.value < 1) {
      _animate(header, header.value < 0.5 ? 0 : 1);
    }
  }

  void show() {
    _run.reset();
    _following = false;
    _animate(header, 0);
    _animate(actions, 0);
  }

  void _animate(AnimationController c, double to) {
    if (c.value == to && !c.isAnimating) return;
    c.animateTo(
      to,
      duration: reduceMotion ? Motion.reducedFade : Motion.sheetChrome,
      curve: Curves.easeOut,
    );
  }

  void dispose() {
    header.dispose();
    actions.dispose();
  }
}
