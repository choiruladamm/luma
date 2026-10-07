import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/scroll_run.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';

// Halaman baca imersif (board Baca imersif · ReaderCapsule). Ukuran di sini
// diukur dari safe area (board: atas 54, bawah 34).

/// Kapsul atas: 6 di bawah safe area atas, tinggi 58.
const capsuleTopGap = 6.0;
const capsuleHeight = 58.0;

/// Kapsul bawah: 14 di atas safe area bawah, tinggi 40.
const capsuleBottomGap = 14.0;
const capsuleBottomHeight = 40.0;

/// Teks awal bab mulai di sini (board: 140), biar judulnya gak ketutup.
const readerTextTop = 86.0;

/// Ruang kosong di bawah teks terakhir (board: 100 dari tepi layar).
const readerTextBottom = 66.0;

/// Tepi teks baca (board EdgeFade · varian Baca). [t] = `ReaderChrome.hidden`
/// (0 kapsul keliatan, 1 imersif), jadi kekuatan fade ikut animasi kapsul.
/// Kapsul keliatan: status bar kosong, teks di belakang kapsul ±18% terus
/// sampe tepi bawah layar, 48pt dari tepi kapsul naik penuh. Imersif: gak ada
/// fade sama sekali, teks lewat di bawah garis progres sampe tepi.
({EdgeFadeSide top, EdgeFadeSide bottom}) readerEdgeFade(
  EdgeInsets pad,
  double t,
) {
  final behind = lerpDouble(0.18, 1, t)!;
  return (
    top: EdgeFadeSide(
      48,
      clear: pad.top,
      clearAlpha: t,
      hold: capsuleTopGap + capsuleHeight,
      floor: behind,
    ),
    bottom: EdgeFadeSide(
      48,
      hold: pad.bottom + capsuleBottomGap + capsuleBottomHeight,
      floor: behind,
    ),
  );
}

/// Ngumpet/munculin kapsul ngikutin scroll (ambang di [ScrollRun]): turun
/// ngumpet, naik muncul. Selama jari nge-drag, kapsul ngikutin 1:1 terus
/// snap pas dilepas.
class ReaderChrome {
  ReaderChrome({required TickerProvider vsync})
    : hidden = AnimationController(vsync: vsync, duration: Motion.capsule);

  /// Jarak geser buat ngikutin jari: kapsul atas sampe lewat tepi layar.
  static const _travel = 120.0;

  /// 0 = keliatan, 1 = ngumpet.
  final AnimationController hidden;

  /// Target sekarang; status bar ikut ini.
  final visible = ValueNotifier(true);

  bool reduceMotion = false;

  final _run = ScrollRun();

  /// [delta] > 0 = scroll turun (teks naik).
  void scrolled(double delta, {required bool dragging}) {
    if (delta == 0) return;
    if (dragging) {
      hidden.value = (hidden.value + delta / _travel).clamp(0.0, 1.0);
    }
    switch (_run.add(delta)) {
      case ChromeIntent.hide:
        _set(false, snap: !dragging);
      case ChromeIntent.show:
        _set(true, snap: !dragging);
      case null:
    }
  }

  /// Jari dilepas / scroll berhenti: geser ke target.
  void release() => _snap();

  void show() => _set(true);
  void hide() => _set(false);
  void toggle() => _set(!visible.value);

  void _set(bool show, {bool snap = true}) {
    visible.value = show;
    _run.reset();
    if (snap) _snap();
  }

  void _snap() {
    final target = visible.value ? 0.0 : 1.0;
    if (hidden.value == target && !hidden.isAnimating) return;
    hidden.animateTo(
      target,
      duration: reduceMotion ? Duration.zero : Motion.capsule,
      curve: Curves.easeOut,
    );
  }

  void dispose() {
    hidden.dispose();
    visible.dispose();
  }
}

/// Dua kapsul, geser keluar layar ngikutin [ReaderChrome.hidden]. Overlay:
/// teks di bawahnya gak loncat; tepinya dimudarin [readerEdgeFade].
class ReaderCapsules extends StatelessWidget {
  const ReaderCapsules({
    super.key,
    required this.chrome,
    required this.top,
    this.bottom,
  });

  final ReaderChrome chrome;
  final Widget top;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final topTravel = pad.top + capsuleTopGap + capsuleHeight + Space.s6;
    final bottomTravel =
        pad.bottom + capsuleBottomGap + capsuleBottomHeight + Space.s6;
    return AnimatedBuilder(
      animation: chrome.hidden,
      builder: (context, _) {
        final t = chrome.hidden.value;
        return IgnorePointer(
          ignoring: t > 0.5,
          child: Stack(
            children: [
              Positioned(
                left: Layout.margin,
                right: Layout.margin,
                top: pad.top + capsuleTopGap,
                child: Transform.translate(
                  offset: Offset(0, -t * topTravel),
                  child: top,
                ),
              ),
              if (bottom != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: pad.bottom + capsuleBottomGap,
                  child: Transform.translate(
                    offset: Offset(0, t * bottomTravel),
                    child: Center(child: bottom),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.height,
    required this.padding,
    required this.child,
  });

  final double height;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: c.capsuleLine, width: Layout.outline),
        boxShadow: Elevation.capsule(c, Theme.of(context).brightness),
      ),
      child: child,
    );
  }
}

/// Kapsul atas: balik · judul + bab · daftar isi · Aa.
class ReaderTopCapsule extends StatelessWidget {
  const ReaderTopCapsule({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBack,
    this.onToc,
    this.onAa,
    this.tocOpen = false,
    this.aaOpen = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  /// Null = daftar isi belum bisa dibuka (buku belum kebaca).
  final VoidCallback? onToc;

  /// Null = buku belum kebaca.
  final VoidCallback? onAa;

  /// Sheet daftar isi / Aa lagi kebuka: tombolnya kuning.
  final bool tocOpen;
  final bool aaOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      container: true,
      label: 'Menu baca',
      child: _Pill(
        height: capsuleHeight,
        // Tombol 44 pas di tengah tinggi 58 (dikurangi garis).
        padding: const EdgeInsets.symmetric(horizontal: 5.5),
        child: Row(
          spacing: 6,
          children: [
            CircleButton(
              semanticLabel: 'Balik ke rak',
              icon: AppIcons.back,
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 1,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.label.copyWith(
                      fontSize: 14.5,
                      height: 1.15,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                ],
              ),
            ),
            CircleButton(
              semanticLabel: 'Daftar isi',
              icon: AppIcons.toc,
              active: tocOpen,
              onPressed: onToc,
            ),
            CircleButton(
              semanticLabel: 'Atur tampilan teks',
              text: 'Aa',
              active: aaOpen,
              onPressed: onAa,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kapsul bawah: persen + bar + sisa waktu. Cuma info, gak bisa di-tap.
class ReaderBottomCapsule extends StatelessWidget {
  const ReaderBottomCapsule({
    super.key,
    required this.progress,
    required this.label,
  });

  /// Progres buku 0..1.
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return _Pill(
      height: capsuleBottomHeight,
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Text(
            '${(progress * 100).floor()}%',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          SizedBox(
            width: 88,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.full),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: c.track,
                color: c.progressFill,
              ),
            ),
          ),
          Text(label, style: StabiloType.caption.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}

/// Garis progres 2pt selebar layar, duduk tepat di atas safe area bawah.
class ReaderProgressLine extends StatelessWidget {
  const ReaderProgressLine({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom,
      height: 2,
      child: Semantics(
        label: 'Progres buku',
        value: '${(progress * 100).floor()}%',
        child: ColoredBox(
          color: c.progressLineTrack,
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: math.max(6, progress.clamp(0.0, 1.0) * box.maxWidth),
                child: ColoredBox(color: c.progressLine),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
