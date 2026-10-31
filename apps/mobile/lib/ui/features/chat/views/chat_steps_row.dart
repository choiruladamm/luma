import 'package:flutter/material.dart';

import '../../../../domain/chat_steps.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import 'chat_copy.dart';

/// Label bab "Book I › III: Of Providence": pemisah " › " jadi ikon chevron
/// kecil (board Langkah AI), bukan karakter. [color] = warna ikon.
InlineSpan chatLabelSpan(String text, Color color) {
  final parts = text.split(' › ');
  return TextSpan(
    children: [
      for (final (i, part) in parts.indexed) ...[
        if (i > 0)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AppIcon(AppIcons.chevron, size: 12, color: color),
            ),
          ),
        TextSpan(text: part),
      ],
    ],
  );
}

/// Langkah AI (#153, board "Langkah AI · baris status di atas jawaban"):
/// baris status 40pt (dot kuning berdenyut + "Lagi baca …" + "Langkah 7" +
/// chevron saat jalan; centang + "12 langkah selesai" setelah selesai), dan
/// daftar langkah yang bisa dibuka/ditutup per turn. Default terbuka saat
/// jalan, tertutup setelah selesai; toggle user menang sampai turn-nya ganti.
class ChatStepsRow extends StatefulWidget {
  const ChatStepsRow({super.key, required this.steps, required this.running});
  final List<ChatStep> steps;
  final bool running;

  static const visibleSteps = 6;

  @override
  State<ChatStepsRow> createState() => _ChatStepsRowState();
}

class _ChatStepsRowState extends State<ChatStepsRow> {
  bool? _expanded;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final steps = widget.steps;
    final expanded = _expanded ?? widget.running;
    final last = steps.lastOrNull;
    final title = widget.running && last != null
        ? last.statusLabel
        : '${steps.length} langkah selesai';
    final hidden = steps.length - ChatStepsRow.visibleSteps;
    final shown = _all || hidden <= 0
        ? steps
        : steps.take(ChatStepsRow.visibleSteps).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: title,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !expanded),
            child: SizedBox(
              height: Layout.chatSteps,
              child: Row(
                spacing: 10,
                children: [
                  SizedBox(
                    width: 14,
                    child: Center(
                      child: widget.running
                          ? _PulseDot(color: c.accent, outline: c.outline)
                          : AppIcon(AppIcons.check, size: 12, color: c.ink3),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      chatLabelSpan(title, widget.running ? c.ink : c.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: widget.running ? c.ink : c.ink2,
                      ),
                    ),
                  ),
                  if (widget.running)
                    Text(
                      'Langkah ${steps.length}',
                      style: StabiloType.caption.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: c.ink3,
                      ),
                    ),
                  RotatedBox(
                    quarterTurns: expanded ? 2 : 0,
                    child: AppIcon(AppIcons.expand, size: 14, color: c.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final step in shown) _StepLine(step),
                if (!_all && hidden > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _all = true),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 18),
                          child: SizedBox(
                            height: 36,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'lihat $hidden lagi',
                                style: StabiloType.caption.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.step);
  final ChatStep step;
  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final skipped = step.status == ChatStepStatus.skipped;
    final style = StabiloType.caption.copyWith(
      fontSize: 13,
      height: 19 / 13,
      fontWeight: FontWeight.w500,
      color: skipped ? c.ink3 : c.ink2,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SizedBox(
            width: 12,
            height: 19,
            child: Center(
              child: skipped
                  ? Text('–', style: style.copyWith(color: c.ink3))
                  : AppIcon(AppIcons.check, size: 12, color: c.ink3),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  chatLabelSpan(step.label, skipped ? c.ink3 : c.ink2),
                  if (step.detail != null)
                    TextSpan(
                      text: ' · ${step.detail}',
                      style: style.copyWith(color: c.ink3),
                    ),
                ],
              ),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dot 8pt accent dengan garis outline 1,5; denyut 1,2 dtk (skala 1 ↔ 0,6,
/// opasitas 1 ↔ 0,5). Kurangi gerakan: diam.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.outline});
  final Color color, outline;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: Motion.stepPulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) {
      final t = Curves.easeInOut.transform(_pulse.value);
      return Opacity(
        opacity: 1 - 0.5 * t,
        child: Transform.scale(
          scale: 1 - 0.4 * t,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: widget.outline, width: Layout.outline),
            ),
          ),
        ),
      );
    },
  );
}

/// Blok "CATATAN SEMENTARA" bagian bawah: tombol teks "Jawab sekarang →" dan
/// caption jumlah catatan. Catatannya sendiri dirender sebagai preview turn.
class ChatAnswerNow extends StatelessWidget {
  const ChatAnswerNow({
    super.key,
    required this.notes,
    required this.onPressed,
  });
  final int notes;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Jawab sekarang',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox(
              height: Layout.chatSteps,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    'Jawab sekarang',
                    style: StabiloType.label.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  AppIcon(AppIcons.chevron, size: 14, color: c.ink),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Pakai $notes catatan yang udah masuk, sisa buku gak dibaca.',
          style: StabiloType.caption.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}
