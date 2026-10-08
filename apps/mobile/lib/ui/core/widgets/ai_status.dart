import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

// Potongan UI jawaban AI yang dipake sheet Artinya dan layar Bedahin.

/// Salin yang lagi nunggu jawaban: tiga titik berdenyut + "Lagi mikir" /
/// "Lagi nulis". Nonaktif, warna ink2 di atas muted.
class StatusButton extends StatelessWidget {
  const StatusButton({super.key, required this.label, this.action = 'Salin'});

  final String label;

  /// Tombol yang lagi nunggu (VoiceOver: "Salin, belum bisa: lagi mikir").
  final String action;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      enabled: false,
      label: '$action, belum bisa: ${label.toLowerCase()}',
      excludeSemantics: true,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // Dibentang (mis. di Expanded): isinya di tengah.
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 9,
          children: [
            _WritingDots(color: c.ink2),
            Text(
              label,
              style: StabiloType.label.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiga titik 4pt, opasitas 30 ↔ 85% tiap [Motion.writingDots], bergiliran.
/// Kurangi gerakan: diem.
class _WritingDots extends StatefulWidget {
  const _WritingDots({required this.color});

  final Color color;

  @override
  State<_WritingDots> createState() => _WritingDotsState();
}

class _WritingDotsState extends State<_WritingDots>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: Motion.writingDots,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context) ? _pulse.stop() : _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        for (var i = 0; i < 3; i++)
          Opacity(
            opacity: _pulse.isAnimating
                ? 0.3 +
                      0.55 *
                          (0.5 -
                              0.5 *
                                  math.cos(
                                    2 * math.pi * (_pulse.value - i * 0.16),
                                  ))
                : 0.6,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Kartu status di dalam isi scroll (board perilaku): kotak ikon 36, judul,
/// keterangan, tombol 40.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.color,
    required this.line,
    required this.tile,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.actions,
  });

  final Color color, line, tile, iconColor;
  final List<List<dynamic>> icon;
  final String title, body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Radii.menu),
        border: Border.all(color: line, width: Layout.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s3,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tile,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Center(child: AppIcon(icon, color: iconColor)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      style: StabiloType.label.copyWith(
                        fontSize: 16,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      body,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(spacing: 10, children: actions),
        ],
      ),
    );
  }
}

/// Kotak ikon di pojok state error / API key kosong.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  static const size = 52.0;

  final List<List<dynamic>> icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    width: IconTile.size,
    height: IconTile.size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(Radii.menu),
    ),
    child: Center(child: AppIcon(icon, size: 26, color: fg)),
  );
}

/// Baris skeleton 12pt di tengah baris teks setinggi [lineExtent] (ikut Aa,
/// biar gak loncat pas hasilnya muncul), shimmer 1,4 detik. Kurangi gerakan:
/// diem.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.widths, required this.lineExtent});

  /// Lebar tiap baris, fraksi lebar kolom.
  final List<double> widths;
  final double lineExtent;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _shimmer = AnimationController(
    vsync: this,
    duration: Motion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context)
        ? _shimmer.stop()
        : _shimmer.repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        // Sorot geser dari kanan ke kiri.
        final x = 1 - 2 * _shimmer.value;
        final gradient = LinearGradient(
          begin: Alignment(x - 1, 0),
          end: Alignment(x + 1, 0),
          colors: [c.track, c.muted, c.track],
        );
        return Column(
          children: [
            for (final w in widget.widths)
              SizedBox(
                height: widget.lineExtent,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
