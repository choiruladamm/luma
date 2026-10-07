import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/tag.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/reader_view_model.dart';

/// Sheet Artinya (board 04 loading, 05 hasil, 06 error, 09 udah disalin,
/// 10 API key kosong). [group] = grup yang lagi dibuka; "Lanjut" manggil
/// [onNext] yang mindahin [group] ke grup berikutnya. [onHeight] tiap tinggi
/// sheet berubah (state ganti), biar halaman di belakang bisa nyesuain.
/// Barrier transparan: scrim (yang bolongin grup) digambar halaman baca.
Future<void> showMeaningSheet(
  BuildContext context, {
  required ValueListenable<GroupRef> group,
  required bool Function(GroupRef) hasNext,
  required VoidCallback onNext,
  required ValueChanged<double> onHeight,
  required VoidCallback onSettings,
}) => showAppSheet<void>(
  context,
  barrierColor: Colors.transparent,
  builder: (_) => _ReportHeight(
    onHeight: onHeight,
    child: ValueListenableBuilder(
      valueListenable: group,
      builder: (context, g, _) => MeaningSheet(
        key: ValueKey(g),
        group: g,
        onNext: hasNext(g) ? onNext : null,
        onSettings: onSettings,
      ),
    ),
  ),
);

class MeaningSheet extends ConsumerStatefulWidget {
  const MeaningSheet({
    super.key,
    required this.group,
    required this.onNext,
    required this.onSettings,
  });

  final GroupRef group;

  /// Null = grup terakhir di bab ini.
  final VoidCallback? onNext;
  final VoidCallback onSettings;

  @override
  ConsumerState<MeaningSheet> createState() => _MeaningSheetState();
}

class _MeaningSheetState extends ConsumerState<MeaningSheet> {
  bool _copied = false;

  void _close() => Navigator.of(context).pop();

  Future<void> _copy(AiReply reply) async {
    await Clipboard.setData(
      ClipboardData(text: reply.translations.join('\n\n')),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    showOverlayToast(
      context,
      'Udah disalin, tinggal paste',
      bottom: MediaQuery.paddingOf(context).bottom + 68,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(groupAiProvider(widget.group));
    // Teks isi ikut Aa; ganti pengaturan langsung kebawa tanpa nutup sheet.
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final typo = ReaderTypography(prefs, Theme.of(context).brightness);
    // Lagi (ulang) loading → loading, walaupun ada error lama.
    if (ai.isLoading) return _Loading(typo: typo, onClose: _close);
    return switch (ai) {
      AsyncData(:final value) => _Result(
        typo: typo,
        reply: value,
        copied: _copied,
        onCopy: () => _copy(value),
        onNext: widget.onNext,
        onClose: _close,
      ),
      AsyncError(error: AiException(error: AiError.noApiKey)) => _NoKey(
        onClose: _close,
        onSettings: widget.onSettings,
      ),
      AsyncError(:final error) => _Failed(
        code: _errorCode(error),
        onClose: _close,
        onRetry: () => ref.invalidate(groupAiProvider(widget.group)),
      ),
      _ => _Loading(typo: typo, onClose: _close),
    };
  }

  /// Kode kecil buat debug di state error.
  static String _errorCode(Object error) => switch (error) {
    AiException(error: AiError.timeout) => 'timeout · 30 detik',
    AiException(error: AiError.network) => 'offline / gak nyambung',
    AiException(error: AiError.http, :final status)
        when status == 401 || status == 403 =>
      'HTTP $status · key ditolak',
    AiException(error: AiError.http, status: 402) => 'HTTP 402 · saldo abis',
    AiException(error: AiError.http, :final status) => 'HTTP $status',
    AiException(error: AiError.invalidResponse) => 'jawaban AI gak valid',
    _ => 'error',
  };
}

/// Rangka sheet: grabber, header, isi yang bisa scroll (tepinya mudar),
/// tombol nempel di bawah.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.header,
    required this.content,
    required this.actions,
    this.gap = Space.s4,
    this.margin = 0,
  });

  final Widget header;
  final List<Widget> content;
  final List<Widget> actions;
  final double gap;

  /// Margin teks Aa. Padding dasar sheet (24) jadi batas bawahnya; isi cuma
  /// dilebarin kalau margin-nya lebih besar (Lega 32).
  final double margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Layout.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap,
        children: [
          const SheetGrabber(),
          header,
          Flexible(
            child: EdgeFadeScroll(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: math.max(0, margin - Layout.sheetPadding.left),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: content,
                ),
              ),
            ),
          ),
          Row(spacing: 10, children: actions),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(
    this.text, {
    this.leading,
    required this.closeLabel,
    required this.onClose,
  });

  final String text;
  final Widget? leading;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    spacing: Space.s3,
    children: [
      ?leading,
      Expanded(
        child: Semantics(
          header: true,
          child: Text(text, style: StabiloType.titleMd),
        ),
      ),
      CircleButton(
        semanticLabel: closeLabel,
        icon: AppIcons.close,
        onPressed: onClose,
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.tag, required this.child});

  final Widget tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.s2,
    children: [tag, child],
  );
}

class _Result extends StatelessWidget {
  const _Result({
    required this.typo,
    required this.reply,
    required this.copied,
    required this.onCopy,
    required this.onNext,
    required this.onClose,
  });

  final ReaderTypography typo;
  final AiReply reply;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final text = typo.style.copyWith(color: c.ink);
    return _Frame(
      margin: typo.margin,
      header: _Title('Artinya gini nih', closeLabel: 'Tutup', onClose: onClose),
      content: [
        _Section(
          tag: const Tag.section('Terjemahan'),
          // Satu blok per paragraf, biar jeda dialognya sama kayak aslinya.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s2,
            children: [
              for (final t in reply.translations) Text(t, style: text),
            ],
          ),
        ),
        _Section(
          tag: const Tag.section(
            'Maksud penulisnya tuh...',
            tone: TagTone.pink,
          ),
          child: Text(reply.meaning, style: text),
        ),
      ],
      actions: [
        AppButton.secondary(
          label: copied ? 'Disalin' : 'Salin',
          icon: copied ? AppIcons.check : AppIcons.copy,
          onPressed: onCopy,
        ),
        Expanded(
          child: AppButton.primary(
            label: 'Lanjut',
            icon: AppIcons.down,
            iconAfter: true,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.typo, required this.onClose});

  final ReaderTypography typo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Artinya, lagi dimuat',
      child: _Frame(
        margin: typo.margin,
        header: _Title(
          'Bentar, lagi mikir...',
          leading: const _PulseDot(),
          closeLabel: 'Batalin',
          onClose: onClose,
        ),
        content: [
          _Section(
            tag: const Tag.section('Terjemahan'),
            child: _Skeleton(
              widths: const [1, 0.93, 0.58],
              lineExtent: typo.lineExtent,
            ),
          ),
          _Section(
            tag: const Tag.section(
              'Maksud penulisnya tuh...',
              tone: TagTone.pink,
            ),
            child: _Skeleton(
              widths: const [1, 0.93, 0.97, 0.58],
              lineExtent: typo.lineExtent,
            ),
          ),
        ],
        // Tetep ada tapi mati, biar layout gak loncat pas hasilnya dateng.
        actions: const [
          AppButton.secondary(
            label: 'Salin',
            icon: AppIcons.copy,
            onPressed: null,
          ),
          Expanded(
            child: AppButton.primary(
              label: 'Lanjut',
              icon: AppIcons.down,
              iconAfter: true,
              onPressed: null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak ikon 52 di pojok state error / API key kosong.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.bg, required this.fg});

  final List<List<dynamic>> icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(Radii.menu),
    ),
    child: Center(child: AppIcon(icon, size: 26, color: fg)),
  );
}

/// Header state error / API key kosong: kotak ikon kiri, tutup kanan.
class _TileHeader extends StatelessWidget {
  const _TileHeader({required this.tile, required this.onClose});

  final Widget tile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      tile,
      CircleButton(
        semanticLabel: 'Tutup',
        icon: AppIcons.close,
        onPressed: onClose,
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.s2,
    children: [
      Semantics(header: true, child: Text(title, style: StabiloType.titleMd)),
      Text(body, style: StabiloType.body.copyWith(color: context.stabilo.ink2)),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.code,
    required this.onClose,
    required this.onRetry,
  });

  final String code;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      label: 'Gagal ngambil artinya',
      child: _Frame(
        gap: 14,
        header: _TileHeader(
          tile: _IconTile(icon: AppIcons.offline, bg: c.pink, fg: c.onPink),
          onClose: onClose,
        ),
        content: [
          const _Message(
            title: 'Yah, gagal nih',
            body:
                'Kayaknya koneksi lagi ngadat, atau AI-nya lagi sibuk. Tinggal '
                'coba lagi aja.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Space.s2),
              ),
              child: Text(
                code,
                style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
              ),
            ),
          ),
        ],
        actions: [
          AppButton.secondary(label: 'Nanti aja', onPressed: onClose),
          Expanded(
            child: AppButton.primary(
              label: 'Coba lagi',
              icon: AppIcons.retry,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoKey extends StatelessWidget {
  const _NoKey({required this.onClose, required this.onSettings});

  final VoidCallback onClose;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return _Frame(
      gap: 14,
      header: _TileHeader(
        tile: _IconTile(icon: AppIcons.key, bg: c.accent, fg: c.onAccent),
        onClose: onClose,
      ),
      content: [
        const _Message(
          title: 'Isi API key dulu yuk',
          body:
              'Artinya dibikin AI lewat OpenRouter. Tempel API key lo sekali '
              'aja di Pengaturan, abis itu tinggal tap-tap paragraf.',
        ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Belum punya? Bikin dulu di '),
              TextSpan(
                text: 'openrouter.ai/keys',
                style: StabiloType.mono.copyWith(fontSize: 13, color: c.ink),
              ),
            ],
          ),
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w400,
            color: c.ink2,
          ),
        ),
      ],
      actions: [
        AppButton.secondary(label: 'Nanti aja', onPressed: onClose),
        Expanded(
          child: AppButton.primary(
            label: 'Buka Pengaturan',
            icon: AppIcons.next,
            iconAfter: true,
            onPressed: onSettings,
          ),
        ),
      ],
    );
  }
}

/// Titik kuning berdenyut di judul loading. Kurangi gerakan: diem.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: Motion.thinkingDots,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context)
        ? _pulse.stop()
        : _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final t = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: 1 - 0.5 * t.value,
        child: Transform.scale(scale: 1 - 0.4 * t.value, child: child),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle,
          border: Border.all(color: c.accentBorder, width: Layout.outline),
        ),
      ),
    );
  }
}

/// Baris skeleton 12pt di tengah baris teks setinggi [lineExtent] (ikut Aa,
/// biar gak loncat pas hasilnya muncul), shimmer 1,4 detik. Kurangi gerakan:
/// diem.
class _Skeleton extends StatefulWidget {
  const _Skeleton({required this.widths, required this.lineExtent});

  /// Lebar tiap baris, fraksi lebar kolom.
  final List<double> widths;
  final double lineExtent;

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
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

/// Lapor tinggi anak tiap berubah (abis layout).
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderReportHeight r) =>
      r.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
