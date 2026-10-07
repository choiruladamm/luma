import 'package:flutter/animation.dart';

import '../../../core/scroll_run.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// Header (judul + X) dan tombol (Salin / Lanjut) sheet Artinya ngumpet
/// ngikutin scroll jari (board Ngumpet · Opsi A). Ambang di [ScrollRun].
///
/// - Header: ikut isi 1:1 pas turun, ilang setelah [Layout.artinyaHeader].
///   Naik ≥ 12pt: turun lagi ngikut jari dari atas, dilepas di tengah snap ke
///   yang terdekat. Cuma balik lewat scroll naik, atau balik ke paling atas.
/// - Tombol: geser keluar setelah turun ≥ 24pt, balik pas naik ≥ 12pt atau
///   mentok bawah.
///
/// Gak pernah ngumpet kalau [enabled] false, atau isinya muat semua.
/// Kurangi gerakan: gak geser dan gak ngikutin jari, cuma fade.
class MeaningChrome {
  MeaningChrome({required TickerProvider vsync})
    : header = AnimationController(vsync: vsync, duration: Motion.sheetChrome),
      actions = AnimationController(vsync: vsync, duration: Motion.sheetChrome);

  /// 0 = keliatan, 1 = ngumpet.
  final AnimationController header;
  final AnimationController actions;

  /// false = gak pernah ngumpet (state non-hasil, VoiceOver).
  bool enabled = true;
  bool reduceMotion = false;

  final _run = ScrollRun();

  /// Lagi naik dan header ngikutin jari.
  bool _following = false;

  /// Tinggi area baca yang keliatan di sheet setinggi [sheetHeight]: sheet
  /// dikurangi chrome yang keliatan (board: 335 lengkap, 516 pas ngumpet).
  double readHeight(double sheetHeight) {
    final top =
        Layout.artinyaGrabberZone +
        (Layout.artinyaHeader - Layout.artinyaGrabberZone) * (1 - header.value);
    final bottom = Layout.artinyaActions * (1 - actions.value);
    return sheetHeight - top - bottom;
  }

  /// Scroll dari jari. [delta] > 0 = turun.
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

  /// Jari dilepas / scroll berhenti: header yang ngegantung di tengah snap ke
  /// yang terdekat (cuma pas udah lewat zona header).
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
