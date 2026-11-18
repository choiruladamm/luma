import 'package:luma/l10n/l10n.dart';
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
import '../../../../data/repositories/ai_key_repository.dart';
import '../../../core/widgets/quota.dart';
import '../../settings/view_models/ai_quota_view_model.dart';
import '../../settings/views/ai_shared.dart';

/// Result of the peek sheet: what to do after it closes.
sealed class PeekResult {
  const PeekResult();
}

/// "Bedahin ini juga": pushes Bedahin for [group] on top of the current one.
class PeekBreakdown extends PeekResult {
  const PeekBreakdown(this.group);

  final GroupRef group;
}

/// The "Buka Pengaturan" link in the Artiin error row.
class PeekSettings extends PeekResult {
  const PeekSettings();
}

/// Shows the peek sheet for a Nyambung ke card (board "Bedahin · Nyambung ke ·
/// intip" 1a–1d, states C3/C4).
///
/// [where] is the card label ("XVII" / "Lanjutan V").
Future<PeekResult?> showPeekSheet(
  BuildContext context, {
  required PeekKey peek,
  required BreakdownLink link,
  required String where,
}) => showAppSheet<PeekResult>(
  context,
  builder: (_) => PeekSheet(peek: peek, link: link, where: where),
);

/// Peek sheet for the target group of a Nyambung ke card.
///
/// The target's original text is always shown (local, safe offline); the
/// translation shows only if it was already translated. If not, "Artiin"
/// streams through the target group's `groupAiStreamProvider` (the result lands
/// in the normal cache), status shows on the Artiin button, and the last 4
/// words fade. "Bedahin ini juga" needs the meaning first: an untranslated
/// group is translated first, then the breakdown continues right after.
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
  Widget _quotaCard(SubsidyFailure kind) {
    void useOwnKey() {
      ref.read(ownKeyRequestProvider.notifier).request();
      Navigator.of(context).pop(const PeekSettings());
    }

    void ok() => Navigator.of(context).pop();
    return kind == SubsidyFailure.banned
        ? QuotaBannedCard(onUseOwnKey: useOwnKey, onOk: ok)
        : QuotaExhaustedCard(
            now: DateTime.now(),
            large: false,
            peek: true,
            onUseOwnKey: useOwnKey,
            onOk: ok,
          );
  }

  /// Whether Artiin was tapped: the target group's stream is watched (and runs).
  bool _asked = false;

  /// Whether "Bedahin ini juga" was tapped before translating: continue once it finishes.
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
        // Reopening the card now finds it already translated.
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
                                ? context.l10n.peekNextGroup(widget.where)
                                : context.l10n.peekConnectsToStartOf(
                                    widget.where,
                                  ))
                            .toUpperCase(),
                        style: label,
                      ),
                      Text(widget.link.title, style: StabiloType.titleMd),
                    ],
                  ),
                ),
              ),
              CircleButton(
                semanticLabel: context.l10n.sheetClose,
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
                      switch (subsidyFailureOf(
                        ai.error,
                        usingSubsidy:
                            ref.watch(aiSourceProvider).value != AiSource.own,
                      )) {
                        // Quota used up or revoked (board Kuota AI 10, 12): the
                        // original text stays readable above the card.
                        final kind? => _quotaCard(kind),
                        null => _ErrorRow(
                          stream: ai,
                          onSettings: () =>
                              Navigator.of(context).pop(const PeekSettings()),
                        ),
                      },
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
                            action: context.l10n.peekTranslate,
                            label: switch (ai?.phase) {
                              AiPhase.translating ||
                              AiPhase.meaning => context.l10n.meaningWriting,
                              _ => context.l10n.meaningThinking,
                            },
                          )
                        : failed
                        ? AppButton.secondary(
                            label: context.l10n.peekTryTranslatingAgain,
                            icon: AppIcons.retry,
                            onPressed: _artiin,
                          )
                        : AppButton.secondary(
                            label: context.l10n.peekTranslate,
                            onPressed: _artiin,
                          ),
                  ),
                Expanded(
                  child: AppButton.secondary(
                    label: context.l10n.peekBreakThisDownToo,
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

/// Translation of the target group; the last 4 words fade while streaming.
// ponytail: no `Pacer` rhythm like the Artinya sheet, so text appears per
// token. Move the `_Answer` pacing into a shared widget if it looks choppy.
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

/// Artiin failed or was cut off: a small pink row under the text rather than a
/// full error screen (the original text stays the main content).
///
/// Key or balance errors link to Pengaturan.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.stream, required this.onSettings});

  final AiStream stream;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (title, body, settings) = switch (stream) {
      AiStream(phase: AiPhase.cut) => (
        context.l10n.meaningCutOffHalfway,
        context.l10n.peekWhatCameThroughIsStillHere,
        false,
      ),
      AiStream(error: AiException(error: AiError.noApiKey)) => (
        context.l10n.meaningAddYourApiKeyFirst,
        context.l10n.peekTranslationNeedsAnOpenrouterApiKey,
        true,
      ),
      AiStream(error: AiException(error: AiError.http, :final status))
          when status == 401 || status == 403 =>
        (
          context.l10n.peekApiKeyRejected,
          context.l10n.peekOpenrouterRejectedYourKeyCheckIt,
          true,
        ),
      AiStream(error: AiException(error: AiError.http, status: 402)) => (
        context.l10n.peekOpenrouterCreditRanOut,
        context.l10n.peekTopUpAtOpenrouterAiThen,
        true,
      ),
      _ => (
        context.l10n.peekCouldnTTranslate,
        context.l10n.peekTheConnectionIsHavingTroubleYou,
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
                            context.l10n.meaningOpenSettings,
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
