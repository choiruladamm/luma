import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/breakdown_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/breakdown.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/pacing.dart';
import '../../../../domain/stream_text.dart';
import '../../../../routing/router.dart';
import '../../../core/scroll_run.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/ai_status.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/tag.dart';
import '../../../core/widgets/toast.dart';
import '../../reader/view_models/breakdown_view_model.dart';

/// Layar Bedahin (board "Terpilih · Bedahin · Opsi C · layar bedah" + "Spek ·
/// Bedahin · state"). Di-push dari sheet Artinya: balik = ke sheet, "Balik
/// baca" = `pop(true)`, sheet-nya ikut ditutup sama yang manggil. Ditutup di
/// tengah proses = request dibatalin (provider autoDispose).
class BreakdownView extends ConsumerStatefulWidget {
  const BreakdownView({super.key, required this.group});

  final GroupRef group;

  @override
  ConsumerState<BreakdownView> createState() => _BreakdownViewState();
}

class _BreakdownViewState extends ConsumerState<BreakdownView> {
  /// Naik tiap Coba lagi: ritme nulis mulai dari nol.
  int _attempt = 0;
  bool _copied = false;

  void _retry() {
    ref.invalidate(breakdownStreamProvider(widget.group));
    setState(() => _attempt++);
  }

  /// Abis key diisi di Pengaturan, Bedahin langsung jalan lagi.
  Future<void> _settings() async {
    await context.push(Routes.settings);
    if (mounted) _retry();
  }

  Future<void> _copy(BreakdownInput input, Breakdown result) async {
    await Clipboard.setData(ClipboardData(text: breakdownCopy(input, result)));
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
    final state = ref.watch(breakdownStreamProvider(widget.group));
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    return Scaffold(
      body: _Screen(
        key: ValueKey(_attempt),
        state: state,
        typo: ReaderTypography(prefs, Theme.of(context).brightness),
        copied: _copied,
        onBack: () => context.pop(),
        onDone: () => context.pop(true),
        onRetry: _retry,
        onSettings: _settings,
        onCopy: _copy,
      ),
    );
  }
}

/// Isi Salin (board state, "Isi Salin"): teks polos, baris pertama sumbernya.
/// Tanpa terjemahan dan Nyambung ke. Satu bagian = tanpa nomor dan judul.
String breakdownCopy(BreakdownInput input, Breakdown b) {
  final numbered = b.sections.length >= 2;
  return [
    '${input.book.title} · ${_chapterLabel(input)} (dibedah di Luma)',
    for (final (i, s) in b.sections.indexed)
      [
        if (numbered) '${i + 1}. ${s.title}',
        'Maksudnya: ${s.meaning}',
        'Logikanya: ${s.logic}',
      ].join('\n'),
    if (b.terms.isNotEmpty)
      [
        'Tokoh & istilah',
        for (final t in b.terms) '- ${t.label}: ${t.explanation}',
      ].join('\n'),
    if (b.practice != null) 'Praktekinnya gini\n${b.practice}',
  ].join('\n\n');
}

String _chapterLabel(BreakdownInput input) {
  final title = input.book.chapter.trim();
  return title.isEmpty ? 'Bab ${input.chapter}' : title;
}

/// Isi yang boleh tampil sekarang + bagian yang lagi ditulis.
typedef _Visible = ({Breakdown draft, int tail});

/// Teks bedahan urut tampil, buat ritme nulis: per bagian judul, maksud,
/// logika; tiap istilah label + penjelasan; tiap nyambung judul + kenapa;
/// praktek. Indeks di sini = indeks "ujung" di [_Visible].
List<String> _fields(Breakdown b) => [
  for (final s in b.sections) ...[s.title, s.meaning, s.logic],
  for (final t in b.terms) ...[t.label, t.explanation],
  for (final l in b.links) ...[l.title, l.why],
  ?b.practice,
];

int _length(Breakdown b) => _fields(b).fold(0, (n, f) => n + f.length);

/// [b] dipotong jadi [n] huruf pertama (urutan [_fields]). Item yang belum
/// kebagian huruf gak ikut.
_Visible _take(Breakdown b, int n) {
  var left = n;
  var index = 0;
  var tail = -1;
  String cut(String s) {
    final t = s.substring(0, math.min(left, s.length));
    left -= t.length;
    if (t.isNotEmpty) tail = index;
    index++;
    return t;
  }

  final sections = <BreakdownSection>[];
  for (final s in b.sections) {
    if (left <= 0) break;
    sections.add(
      BreakdownSection(
        from: s.from,
        to: s.to,
        title: cut(s.title),
        meaning: cut(s.meaning),
        logic: cut(s.logic),
      ),
    );
  }
  index = b.sections.length * 3;
  final terms = <BreakdownTerm>[];
  for (final t in b.terms) {
    if (left <= 0) break;
    terms.add(
      BreakdownTerm(
        label: cut(t.label),
        exact: t.exact,
        explanation: cut(t.explanation),
        sentence: t.sentence,
      ),
    );
  }
  index = b.sections.length * 3 + b.terms.length * 2;
  final links = <BreakdownLink>[];
  for (final l in b.links) {
    if (left <= 0) break;
    links.add(
      BreakdownLink(chapter: l.chapter, title: cut(l.title), why: cut(l.why)),
    );
  }
  index = b.sections.length * 3 + b.terms.length * 2 + b.links.length * 2;
  final practice = b.practice != null && left > 0 ? cut(b.practice!) : null;
  return (
    draft: Breakdown(
      sections: sections,
      terms: terms,
      links: links,
      practice: practice,
    ),
    tail: tail,
  );
}

/// Cuma bagian yang udah utuh: bagian terakhir masih ditulis, kecuali blok
/// sesudahnya udah mulai. Blok opsional dibuang.
Breakdown _whole(Breakdown b) {
  final later = b.terms.isNotEmpty || b.links.isNotEmpty || b.practice != null;
  final n = later ? b.sections.length : math.max(0, b.sections.length - 1);
  return Breakdown(sections: b.sections.take(n).toList());
}

/// Semua tahap di satu widget: nunggu → nulis → selesai tanpa loncatan layout.
///
/// - Teks penjelasan keluar ngikutin [Pacer]; 4 kata terakhir yang lagi
///   ditulis memudar. Kurangi gerakan: per bagian utuh, tanpa pudar.
/// - Panel atas langsung nampilin terjemahan (udah ada dari makna cepat).
///   Nomor bagian di teks muncul bareng penjelasannya, mulai ada 2 bagian.
/// - Layout ikut jumlah bagian: 1 bagian (selesai) = panel ikut ke-scroll +
///   kalimat asli; selain itu panel nempel di atas, maks 40% layar, scroll
///   sendiri kalau lebih.
/// - Tombol ngumpet pas scroll penjelasan (aturan [ScrollRun]), kecuali
///   selama proses atau VoiceOver nyala.
class _Screen extends StatefulWidget {
  const _Screen({
    super.key,
    required this.state,
    required this.typo,
    required this.copied,
    required this.onBack,
    required this.onDone,
    required this.onRetry,
    required this.onSettings,
    required this.onCopy,
  });

  final BreakdownState state;
  final ReaderTypography typo;
  final bool copied;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final VoidCallback onRetry;
  final VoidCallback onSettings;
  final void Function(BreakdownInput, Breakdown) onCopy;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> with TickerProviderStateMixin {
  final _pacer = Pacer();
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _shown = 0;

  /// Ujung teks: 0 = pudar, 1 = solid.
  late final _solid = AnimationController(
    vsync: this,
    duration: Motion.tailFade,
  );

  /// Tombol bawah: 0 keliatan, 1 ngumpet.
  late final _actions = AnimationController(
    vsync: this,
    duration: Motion.sheetChrome,
  );
  final _run = ScrollRun();
  bool _user = false;

  /// Lengkap dan semua hurufnya udah tampil.
  bool _finished = false;

  BreakdownState get _s => widget.state;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _busy => switch (_s.phase) {
    BreakdownPhase.waiting || BreakdownPhase.slow => true,
    BreakdownPhase.writing => true,
    BreakdownPhase.done => !_finished,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Screen old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Dari cache = langsung jadi. Kepotong = semua yang masuk, ticker berhenti.
  void _sync() {
    if (_finished) return;
    final available = _length(_s.draft);
    if (_s.cached) {
      _finished = true;
      _shown = available;
      _solid.value = 1;
      _ticker.stop();
      return;
    }
    if (_s.phase == BreakdownPhase.cut || _s.phase == BreakdownPhase.failed) {
      _pacer.finish(available);
      _shown = available;
      _ticker.stop();
      return;
    }
    if (available > 0 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final available = _length(_s.draft);
    final done = _s.phase == BreakdownPhase.done;
    final shown = _reduced ? available : _pacer.step(dt, available, done: done);
    final finished = done && shown >= available;
    if (shown == _shown && !finished) return;
    setState(() {
      _shown = shown;
      _finished = finished;
    });
    if (!finished) return;
    _ticker.stop();
    _solid.animateTo(1, duration: _reduced ? Duration.zero : Motion.tailFade);
    if (MediaQuery.accessibleNavigationOf(context)) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Bedahan udah lengkap, ${_countLabel(_s.draft.sections.length)}',
        TextDirection.ltr,
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _solid.dispose();
    _actions.dispose();
    super.dispose();
  }

  _Visible _visible() {
    final draft = _s.draft;
    if (_s.phase == BreakdownPhase.cut) return (draft: _whole(draft), tail: -1);
    if (_finished) return (draft: draft, tail: -1);
    if (_reduced) return (draft: _whole(draft), tail: -1);
    return _take(draft, _shown);
  }

  bool get _hideable =>
      !_busy &&
      _s.phase != BreakdownPhase.failed &&
      !MediaQuery.accessibleNavigationOf(context);

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || !_hideable) return false;
    switch (n) {
      case UserScrollNotification():
        _user = n.direction != ScrollDirection.idle;
      case ScrollUpdateNotification() when _user || n.dragDetails != null:
        final m = n.metrics;
        final intent = _run.add(n.scrollDelta ?? 0);
        if (m.pixels <= 0 ||
            m.pixels >= m.maxScrollExtent - 1 ||
            intent == ChromeIntent.show) {
          _animateActions(0);
        } else if (intent == ChromeIntent.hide) {
          _animateActions(1);
        }
      case ScrollEndNotification():
        _user = false;
      default:
    }
    return false;
  }

  void _animateActions(double to) {
    if (_actions.value == to && !_actions.isAnimating) return;
    _actions.animateTo(
      to,
      duration: _reduced ? Motion.reducedFade : Motion.sheetChrome,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hideable && _actions.value != 0) _actions.value = 0;
    final c = context.stabilo;
    final input = _s.input;
    final phase = _s.phase;
    final failed = phase == BreakdownPhase.failed;
    final cut = phase == BreakdownPhase.cut;
    final visible = _visible();
    final shown = visible.draft;
    final count = shown.sections.length;
    final numbered = count >= 2;
    final thinking = _busy && _length(_s.draft) == 0;
    // 1 bagian (selesai / kepotong): panel ikut ke-scroll + kalimat asli.
    final inline = !_busy && !failed && count == 1;
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final inset = math.max(0.0, widget.typo.margin - Layout.margin);

    final panel = input == null
        ? null
        : _TextPanel(
            input: input,
            sections: numbered ? shown.sections : const [],
            typo: widget.typo,
            inline: inline,
            inset: inset,
            maxHeight: screen.height * Layout.breakdownPanel,
          );

    final explanation = failed
        ? _failure(c)
        : _Explanation(
            visible: visible,
            input: input,
            numbered: numbered,
            typo: widget.typo,
            solid: _solid,
            writing: _busy && !cut,
            faded: !_reduced,
            placeholders: _busy && !cut ? _placeholders(input, shown) : 0,
            slow: phase == BreakdownPhase.slow,
            cut: cut,
            onCancel: widget.onBack,
            onRetry: widget.onRetry,
          );

    final pad = EdgeInsets.fromLTRB(
      Layout.margin + inset,
      inline ? Space.s6 : Space.s3,
      Layout.margin + inset,
      Layout.artinyaActions + Space.s4,
    );

    final Widget body;
    if (inline) {
      body = _scroll(
        frozen: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: panel,
            ),
            Padding(padding: pad, child: explanation),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (panel != null)
            Semantics(
              sortKey: const OrdinalSortKey(3),
              explicitChildNodes: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                child: panel,
              ),
            ),
          Expanded(
            child: Semantics(
              sortKey: const OrdinalSortKey(2),
              explicitChildNodes: true,
              child: _scroll(
                frozen: thinking || failed,
                child: Padding(padding: pad, child: explanation),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: top + Space.s2 + Layout.breakdownHeader + Space.s2,
          ),
          child: body,
        ),
        Positioned(
          top: top + Space.s2,
          left: Space.s4,
          right: Layout.margin,
          child: Semantics(
            sortKey: const OrdinalSortKey(1),
            explicitChildNodes: true,
            child: _Header(
              title: switch (phase) {
                _ when failed => 'Bedahin',
                BreakdownPhase.cut => 'Kepotong di tengah',
                _ when _busy => 'Lagi ngebedah...',
                _ => 'Udah dibedah nih',
              },
              subtitle: input == null
                  ? null
                  : [
                      input.book.title,
                      _chapterLabel(input),
                      if (cut) '$count bagian masuk',
                      if (_finished && !cut) _countLabel(count),
                    ].join(' · '),
              semanticLabel: _busy
                  ? 'Lagi ngebedah, tunggu ya'
                  : input == null
                  ? 'Bedahin'
                  : [
                      'Bedahin, ${input.book.title} ${_chapterLabel(input)}',
                      if (_finished && !cut) ...[
                        _countLabel(count),
                        'udah lengkap',
                      ],
                    ].join(', '),
              backLabel: _busy
                  ? 'Batalin, balik ke Artinya'
                  : 'Balik ke Artinya',
              onBack: widget.onBack,
            ),
          ),
        ),
        Positioned(
          left: Layout.margin,
          right: Layout.margin,
          bottom: Layout.sheetPadding.bottom,
          child: Semantics(
            sortKey: const OrdinalSortKey(4),
            explicitChildNodes: true,
            child: AnimatedBuilder(
              animation: _actions,
              builder: (context, child) {
                final v = _actions.value;
                return ExcludeSemantics(
                  excluding: v >= 1,
                  child: IgnorePointer(
                    ignoring: v > 0.5,
                    child: _reduced
                        ? Opacity(opacity: 1 - v, child: child)
                        : Transform.translate(
                            offset: Offset(0, Layout.artinyaActions * v),
                            child: child,
                          ),
                  ),
                );
              },
              child: Row(spacing: 10, children: _buttons(thinking)),
            ),
          ),
        ),
      ],
    );
  }

  /// Area scroll penjelasan: fade atas 20, fade bawah di atas tombol cuma
  /// selama tombolnya keliatan.
  Widget _scroll({required bool frozen, required Widget child}) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedBuilder(
          animation: _actions,
          builder: (context, scroll) {
            final away = _actions.value;
            return EdgeFadeScroll(
              bottom: EdgeFadeSide(
                20 * (1 - away),
                clear: (Layout.artinyaActions - Space.s4) * (1 - away),
              ),
              child: scroll!,
            );
          },
          child: SingleChildScrollView(
            physics: frozen
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: child,
          ),
        ),
      );

  /// Tebakan jumlah bagian yang belum ditulis (dari jumlah kalimat), minimal
  /// satu selama blok penutup belum mulai.
  int _placeholders(BreakdownInput? input, Breakdown shown) {
    if (shown.terms.isNotEmpty ||
        shown.links.isNotEmpty ||
        shown.practice != null) {
      return 0;
    }
    final sentences = input == null
        ? 12
        : input.sentences.fold(0, (n, p) => n + p.length);
    final guess = (sentences / 6).ceil().clamp(1, 6);
    return math.max(1, guess - shown.sections.length);
  }

  List<Widget> _buttons(bool thinking) {
    final s = _s;
    final reduced = _reduced;
    if (s.phase == BreakdownPhase.failed) {
      final f = _failureCopy(s.error);
      return [
        AppButton.secondary(label: 'Balik baca', onPressed: widget.onDone),
        Expanded(
          child: f.settings
              ? AppButton.primary(
                  label: 'Buka Pengaturan',
                  icon: AppIcons.next,
                  iconAfter: true,
                  onPressed: widget.onSettings,
                )
              : AppButton.primary(
                  label: 'Coba lagi',
                  icon: AppIcons.retry,
                  onPressed: widget.onRetry,
                ),
        ),
      ];
    }
    final cut = s.phase == BreakdownPhase.cut;
    final input = s.input;
    return [
      AnimatedSwitcher(
        duration: reduced ? Duration.zero : Motion.statusSwap,
        child: _busy && !cut
            ? StatusButton(
                key: ValueKey(thinking),
                label: thinking ? 'Lagi mikir' : 'Lagi nulis',
              )
            : AppButton.secondary(
                key: const ValueKey('copy'),
                label: widget.copied ? 'Disalin' : 'Salin',
                icon: widget.copied ? AppIcons.check : AppIcons.copy,
                onPressed: _finished && !cut && input != null
                    ? () => widget.onCopy(input, s.draft)
                    : null,
              ),
      ),
      Expanded(
        child: cut
            ? AppButton.secondary(label: 'Balik baca', onPressed: widget.onDone)
            : AppButton.primary(label: 'Balik baca', onPressed: widget.onDone),
      ),
    ];
  }

  /// Gagal sebelum ada isi: gantiin panel penjelasan (bentuk 06 Artinya ·
  /// error / 10 API key kosong). Panel teks tetep ada.
  Widget _failure(StabiloColors c) {
    final noKey = _s.error?.error == AiError.noApiKey;
    final f = _failureCopy(_s.error);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 14,
          children: [
            noKey
                ? IconTile(icon: AppIcons.key, bg: c.accent, fg: c.onAccent)
                : IconTile(icon: AppIcons.offline, bg: c.pink, fg: c.onPink),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s2,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    noKey ? 'Isi API key dulu yuk' : f.title,
                    style: StabiloType.titleMd,
                  ),
                ),
                Text(
                  noKey
                      ? 'Artinya udah kesimpen, tapi Bedahin butuh AI lewat '
                            'OpenRouter. API key lo udah gak ada di '
                            'Pengaturan, tempel lagi sekali aja.'
                      : f.body,
                  style: StabiloType.body.copyWith(color: c.ink2),
                ),
              ],
            ),
            if (noKey)
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Belum punya? Bikin dulu di '),
                    TextSpan(
                      text: 'openrouter.ai/keys',
                      style: StabiloType.mono.copyWith(
                        fontSize: 13,
                        color: c.ink,
                      ),
                    ),
                  ],
                ),
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w400,
                  color: c.ink2,
                ),
              )
            else
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Space.s2),
                ),
                child: Text(
                  f.code,
                  style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _countLabel(int sections) =>
    sections == 1 ? '1 gagasan' : '$sections bagian';

/// Copy per jenis error (tabel di board state). [settings]: tombol kuningnya
/// "Buka Pengaturan", bukan "Coba lagi". API key kosong punya layar sendiri.
({String title, String body, String code, bool settings}) _failureCopy(
  AiException? e,
) {
  const title = 'Yah, gagal ngebedah';
  const body =
      'Kayaknya koneksi lagi ngadat, atau AI-nya lagi sibuk. Tinggal coba lagi '
      'aja.';
  return switch (e) {
    AiException(error: AiError.noApiKey) => (
      title: '',
      body: '',
      code: '',
      settings: true,
    ),
    AiException(error: AiError.network) => (
      title: 'Lagi offline nih',
      body:
          'Bedahin butuh internet. Nyalain dulu, abis itu coba lagi. Bedahan '
          'yang udah kesimpen tetep bisa dibuka.',
      code: 'offline',
      settings: false,
    ),
    AiException(error: AiError.http, :final status)
        when status == 401 || status == 403 =>
      (
        title: 'API key-nya ditolak',
        body:
            'OpenRouter gak nerima key lo. Cek lagi di Pengaturan, siapa tau '
            'kepotong pas ditempel.',
        code: '$status · key ditolak',
        settings: true,
      ),
    AiException(error: AiError.http, status: 402) => (
      title: 'Saldo OpenRouter abis',
      body:
          'Isi saldo dulu di openrouter.ai, abis itu balik ke sini dan coba '
          'lagi.',
      code: '402 · saldo abis',
      settings: false,
    ),
    AiException(error: AiError.invalidResponse) => (
      title: 'Jawabannya berantakan',
      body:
          'AI-nya ngasih jawaban yang gak bisa dibaca Luma. Coba sekali lagi, '
          'biasanya beres.',
      code: 'format gak valid',
      settings: false,
    ),
    AiException(error: AiError.timeout) => (
      title: title,
      body: body,
      code: 'timeout · 30 detik',
      settings: false,
    ),
    AiException(error: AiError.http, :final status) => (
      title: title,
      body: body,
      code: 'HTTP $status',
      settings: false,
    ),
    _ => (title: title, body: body, code: 'error', settings: false),
  };
}

/// Balik + judul layar (status) + buku · bab · jumlah bagian.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.backLabel,
    required this.onBack,
  });

  final String title;
  final String? subtitle;
  final String semanticLabel;
  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Layout.breakdownHeader,
    child: Row(
      spacing: 10,
      children: [
        CircleButton(
          semanticLabel: backLabel,
          icon: AppIcons.back,
          onPressed: onBack,
        ),
        Expanded(
          child: Semantics(
            header: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: StabiloType.label.copyWith(fontSize: 17)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w400,
                      color: context.stabilo.ink2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Panel terjemahan. Nomor bagian di depan kalimat pertama tiap bagian
/// ([sections] kosong = tanpa nomor). Grup > 1 paragraf: jarak 12 + `¶n` di
/// kolom kiri. [inline]: setinggi teks + kalimat asli di bawahnya; kalau
/// nggak, maks [maxHeight] dan scroll sendiri.
class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.input,
    required this.sections,
    required this.typo,
    required this.inline,
    required this.inset,
    required this.maxHeight,
  });

  final BreakdownInput input;
  final List<BreakdownSection> sections;
  final ReaderTypography typo;
  final bool inline;
  final double inset;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final style = typo.style.copyWith(color: c.ink);
    final paragraphs = input.sentences;
    final many = paragraphs.length > 1;
    final starts = {for (final (i, s) in sections.indexed) s.from: i + 1};
    final badge = math.max(Layout.breakdownBadge, style.fontSize!);
    var k = 0;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        for (final (p, sentences) in paragraphs.indexed)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    for (final (i, s) in sentences.indexed) ...[
                      if (starts[++k] case final n?)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: Space.s1),
                            child: _Number(
                              n,
                              size: badge,
                              fontSize: badge * 0.6,
                              label: 'Bagian $n',
                            ),
                          ),
                        ),
                      TextSpan(text: i == sentences.length - 1 ? s : '$s '),
                    ],
                  ],
                ),
                style: style,
              ),
              if (many)
                Positioned(
                  left: -Layout.breakdownGutter,
                  top: 0,
                  height: typo.lineExtent,
                  child: ExcludeSemantics(
                    child: Center(
                      child: Text(
                        '¶${p + 1}',
                        style: StabiloType.micro.copyWith(color: c.ink3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
    final padding = EdgeInsets.fromLTRB(
      Space.s4 + inset + (many ? Layout.breakdownGutter - Space.s2 : 0),
      14,
      Space.s4 + inset,
      14,
    );
    final decoration = BoxDecoration(
      color: c.sheet,
      borderRadius: BorderRadius.circular(Radii.lg),
      border: Border.all(color: c.track),
    );
    final label = sections.isEmpty
        ? 'Teks terjemahan'
        : 'Teks terjemahan, ${sections.length} bagian';
    if (inline) {
      return Semantics(
        container: true,
        label: 'Teks yang dibedah',
        child: Container(
          padding: padding,
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              text,
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.track)),
                ),
                child: Text(
                  input.original.join('\n\n'),
                  style: style.copyWith(
                    fontSize: 15,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: c.ink2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: label,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: EdgeFadeScroll(
          child: SingleChildScrollView(padding: padding, child: text),
        ),
      ),
    );
  }
}

/// Bulatan nomor bagian (ink di atas canvas).
class _Number extends StatelessWidget {
  const _Number(
    this.n, {
    required this.size,
    required this.fontSize,
    required this.label,
  });

  final int n;
  final double size;
  final double fontSize;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
        child: Text(
          '$n',
          style: StabiloType.label.copyWith(
            fontSize: fontSize,
            height: 1,
            color: c.canvas,
          ),
        ),
      ),
    );
  }
}

/// Panel bawah: bagian-bagian, lalu Tokoh & istilah, Nyambung ke,
/// Praktekinnya gini (blok kosong gak tampil). Placeholder buat bagian yang
/// belum ditulis, kartu kelamaan di atas, banner kepotong di bawah.
class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.visible,
    required this.input,
    required this.numbered,
    required this.typo,
    required this.solid,
    required this.writing,
    required this.faded,
    required this.placeholders,
    required this.slow,
    required this.cut,
    required this.onCancel,
    required this.onRetry,
  });

  final _Visible visible;
  final BreakdownInput? input;
  final bool numbered;
  final ReaderTypography typo;
  final Animation<double> solid;
  final bool writing;
  final bool faded;
  final int placeholders;
  final bool slow;
  final bool cut;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = visible.draft;
    final style = typo.style.copyWith(color: c.ink);
    final count = b.sections.length;
    // Indeks field urut [_fields], buat nyari ujung yang lagi ditulis.
    final termsAt = b.sections.length * 3;
    final practiceAt = termsAt + b.terms.length * 2 + b.links.length * 2;

    /// Teks isi; yang lagi ditulis ujungnya pudar dan gak dibacain VoiceOver.
    Widget body(String t, int field) {
      if (!writing || field != visible.tail) return Text(t, style: style);
      return ExcludeSemantics(
        child: AnimatedBuilder(
          animation: solid,
          builder: (context, _) {
            if (!faded || solid.value >= 1) return Text(t, style: style);
            final split = splitTail(t);
            final alphas = tailAlphas.sublist(
              tailAlphas.length - split.tail.length,
            );
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: split.head),
                  for (final (i, w) in split.tail.indexed)
                    TextSpan(
                      text: w,
                      style: TextStyle(
                        color: c.ink.withValues(
                          alpha: alphas[i] + (1 - alphas[i]) * solid.value,
                        ),
                      ),
                    ),
                ],
              ),
              style: style,
            );
          },
        ),
      );
    }

    final paragraphOf = <int>[
      for (final (p, s) in (input?.sentences ?? const <List<String>>[]).indexed)
        for (final _ in s) p,
    ];
    final label = StabiloType.tag.copyWith(
      letterSpacing: 0.05 * 12,
      height: 18 / 12,
      color: c.ink2,
    );

    final sections = [
      for (final (i, s) in b.sections.indexed)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (numbered) ...[
              Semantics(
                header: true,
                label: 'Bagian ${i + 1} dari $count, ${s.title}',
                excludeSemantics: true,
                child: Row(
                  spacing: 10,
                  children: [
                    _Number(
                      i + 1,
                      size: Layout.breakdownNumber,
                      fontSize: 14,
                      label: 'Bagian ${i + 1}',
                    ),
                    Expanded(
                      child: Text(
                        s.title,
                        style: StabiloType.titleSm.copyWith(color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (_paragraphs(paragraphOf, s) case final range?)
                Tag.section(range, tone: TagTone.muted),
            ],
            if (s.meaning.isNotEmpty) ...[
              Text('MAKSUDNYA', style: label),
              body(s.meaning, i * 3 + 1),
            ],
            if (s.logic.isNotEmpty) ...[
              Text('LOGIKANYA', style: label),
              body(s.logic, i * 3 + 2),
            ],
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s6,
      children: [
        if (slow) _SlowCard(onCancel: onCancel, onRetry: onRetry),
        ...sections,
        for (var i = 0; i < placeholders; i++) _SectionPlaceholder(typo: typo),
        if (b.terms.isNotEmpty)
          _Block(
            tag: const Tag.section('Tokoh & istilah', tone: TagTone.muted),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, t) in b.terms.indexed)
                  Container(
                    padding: EdgeInsets.only(
                      top: i == 0 ? 0 : Space.s3,
                      bottom: i == b.terms.length - 1 ? 0 : Space.s3,
                    ),
                    decoration: i == b.terms.length - 1
                        ? null
                        : BoxDecoration(
                            border: Border(bottom: BorderSide(color: c.track)),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: t.label),
                              if (_sectionOf(b.sections, t.sentence)
                                  case final n? when numbered)
                                TextSpan(
                                  text: ' · bagian $n',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: c.ink2,
                                  ),
                                ),
                            ],
                          ),
                          style: StabiloType.label.copyWith(
                            fontSize: 16,
                            height: 1.4,
                            color: c.ink,
                          ),
                        ),
                        body(t.explanation, termsAt + i * 2 + 1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (b.links.isNotEmpty)
          _Block(
            tag: Text('NYAMBUNG KE', style: label),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final l in b.links) _LinkCard(link: l, input: input),
              ],
            ),
          ),
        if (b.practice case final practice?)
          _Block(
            tag: const Tag.section('Praktekinnya gini', tone: TagTone.pink),
            child: _PracticeText(
              practice,
              writing: writing && practiceAt == visible.tail,
            ),
          ),
        if (cut) _CutBanner(kept: count, onRetry: onRetry),
      ],
    );
  }

  /// `¶a–b` kalau bagian [s] nyebrang paragraf.
  static String? _paragraphs(List<int> paragraphOf, BreakdownSection s) {
    if (s.to > paragraphOf.length || s.from < 1) return null;
    final a = paragraphOf[s.from - 1] + 1;
    final b = paragraphOf[s.to - 1] + 1;
    return a == b ? null : '¶$a–$b';
  }

  /// Nomor bagian (mulai 1) yang memuat kalimat [sentence].
  static int? _sectionOf(List<BreakdownSection> sections, int? sentence) {
    if (sentence == null) return null;
    for (final (i, s) in sections.indexed) {
      if (sentence >= s.from && sentence <= s.to) return i + 1;
    }
    return null;
  }
}

/// Praktekinnya gini: teks UI tebal 20, bukan teks bacaan.
class _PracticeText extends StatelessWidget {
  const _PracticeText(this.text, {required this.writing});

  final String text;
  final bool writing;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: writing,
    child: Text(
      text,
      style: StabiloType.titleSm.copyWith(
        fontSize: 20,
        height: 1.35,
        letterSpacing: -0.01 * 20,
        color: context.stabilo.ink,
      ),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.tag, required this.child});

  final Widget tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.s3,
    children: [tag, child],
  );
}

/// Kartu Nyambung ke. Belum bisa di-tap (intip = #65).
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link, required this.input});

  final BreakdownLink link;
  final BreakdownInput? input;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final chapters = input?.chapters ?? const <String>[];
    final where = switch (link.chapter) {
      null => 'Lanjutannya',
      final n when n <= chapters.length && chapters[n - 1].trim().isNotEmpty =>
        chapters[n - 1].trim(),
      final n => 'Bab $n',
    };
    final text = link.why.isEmpty ? link.title : '${link.title}: ${link.why}';
    return Semantics(
      label: 'Nyambung ke $where, ${link.title}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.menu),
          border: Border.all(color: c.outline, width: Layout.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Text(
              where.toUpperCase(),
              style: StabiloType.tag.copyWith(
                letterSpacing: 0.05 * 12,
                height: 18 / 12,
                color: c.ink2,
              ),
            ),
            Text(
              text,
              style: StabiloType.body.copyWith(height: 1.4, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bagian yang belum ditulis: bulatan + judul + baris, setinggi teks Aa.
class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.typo});

  final ReaderTypography typo;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s1,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                width: Layout.breakdownNumber,
                height: Layout.breakdownNumber,
                decoration: BoxDecoration(
                  color: c.track,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(
                width: 170,
                child: Skeleton(
                  widths: [1],
                  lineExtent: Layout.breakdownNumber,
                ),
              ),
            ],
          ),
          Skeleton(widths: const [1, 1, 0.62], lineExtent: typo.lineExtent),
        ],
      ),
    );
  }
}

/// 15 detik belum ada token: request tetep jalan, token masuk = ilang sendiri.
/// Satu layar satu kuning ("Balik baca"), jadi tombol kartunya muted.
class _SlowCard extends StatelessWidget {
  const _SlowCard({required this.onCancel, required this.onRetry});

  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.sheet,
        line: c.track,
        tile: c.muted,
        icon: AppIcons.clock,
        iconColor: c.ink,
        title: 'Agak lama nih...',
        body: 'AI-nya lagi rame. Tungguin bentar, atau coba minta ulang.',
        actions: [
          Expanded(
            child: AppButton.secondary(
              label: 'Batal',
              height: 40,
              onPressed: onCancel,
            ),
          ),
          Expanded(
            child: AppButton.secondary(
              label: 'Coba lagi',
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// Putus di tengah: bagian yang udah utuh ([kept]) tetep di atasnya.
class _CutBanner extends StatelessWidget {
  const _CutBanner({required this.kept, required this.onRetry});

  final int kept;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.pinkSoft,
        line: c.pink,
        tile: c.pink,
        icon: AppIcons.offline,
        iconColor: c.onPink,
        title: 'Yah, kepotong di tengah',
        body: switch (kept) {
          0 => 'Koneksinya putus pas lagi ngebedah.',
          1 => 'Koneksinya putus pas lagi ngebedah. Bagian 1 tetep di sini.',
          _ =>
            'Koneksinya putus pas lagi ngebedah. Bagian 1–$kept tetep di sini.',
        },
        actions: [
          Expanded(
            child: AppButton.primary(
              label: 'Coba lagi dari awal',
              icon: AppIcons.retry,
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}
