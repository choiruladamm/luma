import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/breakdown.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/stream_text.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/ai_status.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/sheet.dart';
import '../../reader/view_models/breakdown_view_model.dart';
import '../../reader/view_models/reader_view_model.dart';

/// Hasil sheet intip: mau ngapain abis ditutup.
sealed class PeekResult {
  const PeekResult();
}

/// "Bedahin ini juga": push Bedahin [group] di atas yang sekarang.
class PeekBreakdown extends PeekResult {
  const PeekBreakdown(this.group);

  final GroupRef group;
}

/// Link "Buka Pengaturan" di baris error Artiin.
class PeekSettings extends PeekResult {
  const PeekSettings();
}

/// Sheet intip kartu Nyambung ke (board "Bedahin · Nyambung ke · intip"
/// 1a–1d, state C3/C4). [where] = label kartu ("XVII" / "Lanjutan V").
Future<PeekResult?> showPeekSheet(
  BuildContext context, {
  required PeekKey peek,
  required BreakdownLink link,
  required String where,
}) => showAppSheet<PeekResult>(
  context,
  builder: (_) => PeekSheet(peek: peek, link: link, where: where),
);

/// Teks asli grup tujuan selalu ada (lokal, aman offline); terjemahan kalau
/// udah pernah diartiin. Belum: "Artiin" nge-stream lewat
/// `groupAiStreamProvider` grup tujuan (hasilnya masuk cache biasa), status
/// di tombol Artiin, ujung 4 kata memudar. "Bedahin ini juga" butuh makna
/// cepat dulu: belum diartiin = diartiin dulu, selesai langsung lanjut.
class PeekSheet extends ConsumerStatefulWidget {
  const PeekSheet({
    super.key,
    required this.peek,
    required this.link,
    required this.where,
  });

  final PeekKey peek;
  final BreakdownLink link;
  final String where;

  @override
  ConsumerState<PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends ConsumerState<PeekSheet> {
  /// Artiin udah di-tap: stream grup tujuan ditonton (dan jalan).
  bool _asked = false;

  /// "Bedahin ini juga" ditap sebelum diartiin: lanjut pas selesai.
  bool _thenBreakdown = false;

  void _artiin({bool thenBreakdown = false}) {
    final target = ref.read(breakdownPeekProvider(widget.peek)).value?.group;
    if (target == null) return;
    if (_asked) ref.invalidate(groupAiStreamProvider(target));
    setState(() {
      _asked = true;
      _thenBreakdown = thenBreakdown;
    });
  }

  void _breakdown(GroupRef target) =>
      Navigator.of(context).pop(PeekBreakdown(target));

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final peek = ref.watch(breakdownPeekProvider(widget.peek)).value;
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final typo = ReaderTypography(prefs, Theme.of(context).brightness);
    if (peek == null) return const SizedBox.shrink();
    final target = peek.group;
    final ai = _asked && peek.translations == null
        ? ref.watch(groupAiStreamProvider(target))
        : null;
    if (ai != null) {
      ref.listen(groupAiStreamProvider(target), (_, next) {
        if (next.phase != AiPhase.done) return;
        // Card / buka lagi: sekarang "udah diartiin".
        ref.invalidate(breakdownPeekProvider(widget.peek));
        if (_thenBreakdown) _breakdown(target);
      });
    }
    final translations = peek.translations ?? ai?.draft.translations;
    final streaming = switch (ai?.phase) {
      AiPhase.waiting || AiPhase.slow => true,
      AiPhase.translating || AiPhase.meaning => true,
      _ => false,
    };
    final failed = ai?.phase == AiPhase.failed || ai?.phase == AiPhase.cut;
    final translated = peek.translations != null || ai?.phase == AiPhase.done;
    final reading = typo.style.copyWith(color: c.ink);
    final original = Text(
      peek.original.join('\n\n'),
      locale: const Locale('en'),
      style: translations == null || translations.isEmpty
          ? reading
          : reading.copyWith(
              fontSize: 15,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: c.ink2,
            ),
    );
    final label = StabiloType.tag.copyWith(
      letterSpacing: 0.05 * 12,
      height: 18 / 12,
      color: c.ink2,
    );
    final lanjutan = widget.link.chapter == null;

    return Padding(
      padding: Layout.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s4,
        children: [
          const SheetGrabber(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s3,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        (lanjutan
                                ? '${widget.where} · grup berikutnya'
                                : 'Nyambung ke · awal ${widget.where}')
                            .toUpperCase(),
                        style: label,
                      ),
                      Text(widget.link.title, style: StabiloType.titleMd),
                    ],
                  ),
                ),
              ),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Flexible(
            child: EdgeFadeScroll(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    if (widget.link.why.isNotEmpty)
                      Text(
                        widget.link.why,
                        style: StabiloType.body.copyWith(
                          fontSize: 15,
                          height: 1.5,
                          color: c.ink2,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s4,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: BorderRadius.circular(Radii.menu),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          if (translations != null && translations.isNotEmpty)
                            _Translation(
                              translations,
                              style: reading,
                              fading: streaming,
                            ),
                          if (translations != null && translations.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.only(top: 10),
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: c.track)),
                              ),
                              child: original,
                            )
                          else
                            original,
                        ],
                      ),
                    ),
                    if (failed && ai != null)
                      _ErrorRow(
                        stream: ai,
                        onSettings: () =>
                            Navigator.of(context).pop(const PeekSettings()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Row(
              spacing: 10,
              children: [
                if (!translated)
                  Expanded(
                    child: streaming
                        ? StatusButton(
                            action: 'Artiin',
                            label: switch (ai?.phase) {
                              AiPhase.translating ||
                              AiPhase.meaning => 'Lagi nulis',
                              _ => 'Lagi mikir',
                            },
                          )
                        : failed
                        ? AppButton.secondary(
                            label: 'Coba artiin lagi',
                            icon: AppIcons.retry,
                            onPressed: _artiin,
                          )
                        : AppButton.secondary(
                            label: 'Artiin',
                            onPressed: _artiin,
                          ),
                  ),
                Expanded(
                  child: AppButton.secondary(
                    label: 'Bedahin ini juga',
                    icon: translated ? AppIcons.list : null,
                    onPressed: translated
                        ? () => _breakdown(target)
                        : streaming
                        ? null
                        : () => _artiin(thenBreakdown: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Terjemahan grup tujuan; selama di-stream 4 kata terakhir memudar.
// ponytail: tanpa ritme `Pacer` kayak sheet Artinya, teks muncul per token.
// Pindahin pacing `_Answer` ke widget shared kalau keliatan patah-patah.
class _Translation extends StatelessWidget {
  const _Translation(
    this.translations, {
    required this.style,
    required this.fading,
  });

  final List<String> translations;
  final TextStyle style;
  final bool fading;

  @override
  Widget build(BuildContext context) {
    final text = translations.join('\n\n');
    if (!fading || MediaQuery.disableAnimationsOf(context)) {
      return Text(text, style: style);
    }
    final split = splitTail(text);
    final alphas = tailAlphas.sublist(tailAlphas.length - split.tail.length);
    return ExcludeSemantics(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: split.head),
            for (final (i, w) in split.tail.indexed)
              TextSpan(
                text: w,
                style: TextStyle(
                  color: style.color!.withValues(alpha: alphas[i]),
                ),
              ),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// Artiin gagal / kepotong: baris pink kecil di bawah teks, bukan layar
/// error penuh (teks asli tetep isi utamanya). Key / saldo: link Pengaturan.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.stream, required this.onSettings});

  final AiStream stream;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (title, body, settings) = switch (stream) {
      AiStream(phase: AiPhase.cut) => (
        'Yah, kepotong di tengah',
        'Yang udah masuk tetep di sini, tapi gak disimpen.',
        false,
      ),
      AiStream(error: AiException(error: AiError.noApiKey)) => (
        'Isi API key dulu yuk',
        'Artiin butuh API key OpenRouter.',
        true,
      ),
      AiStream(error: AiException(error: AiError.http, :final status))
          when status == 401 || status == 403 =>
        (
          'API key-nya ditolak',
          'OpenRouter gak nerima key lo. Cek lagi di Pengaturan.',
          true,
        ),
      AiStream(error: AiException(error: AiError.http, status: 402)) => (
        'Saldo OpenRouter abis',
        'Isi saldo dulu di openrouter.ai, abis itu coba lagi.',
        true,
      ),
      _ => (
        'Yah, gagal ngartiin',
        'Koneksi lagi ngadat. Teks aslinya tetep bisa dibaca.',
        false,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.pinkSoft,
          borderRadius: BorderRadius.circular(Radii.field),
          border: Border.all(color: c.pink, width: Layout.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s3,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.pink,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Center(
                child: AppIcon(AppIcons.offline, size: 18, color: c.onPink),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: StabiloType.label.copyWith(color: c.ink)),
                  Text(
                    body,
                    style: StabiloType.caption.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                      color: c.ink2,
                    ),
                  ),
                  if (settings)
                    GestureDetector(
                      onTap: onSettings,
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.s1),
                        child: Semantics(
                          link: true,
                          child: Text(
                            'Buka Pengaturan',
                            style: StabiloType.label.copyWith(
                              fontSize: 14,
                              color: c.ink,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
