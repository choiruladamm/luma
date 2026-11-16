import 'package:flutter/material.dart';
import 'package:luma/l10n/l10n.dart';

import '../format.dart';
import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

/// Reset kuota harian OpenRouter: tengah malam UTC (07.00 WIB), dihitung lokal
/// tanpa jaringan (docs/backend.md, AI).
DateTime nextQuotaReset(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day + 1).toLocal();
}

/// Sisa waktu ke reset, dibulatkan ke menit.
({int hours, int minutes}) untilReset(DateTime now, DateTime reset) {
  final left = reset.difference(now);
  final minutes = left.isNegative ? 0 : (left.inSeconds / 60).ceil();
  return (hours: minutes ~/ 60, minutes: minutes % 60);
}

enum QuotaTone { normal, low, empty, loading }

/// 10 segmen kuota (board Kuota AI 01).
class QuotaSegments extends StatelessWidget {
  const QuotaSegments({
    super.key,
    required this.filled,
    this.tone = QuotaTone.normal,
  });

  final int filled;
  final QuotaTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final on = switch (tone) {
      QuotaTone.normal => c.ink,
      QuotaTone.low => c.pink,
      QuotaTone.empty || QuotaTone.loading => c.outline,
    };
    final off = tone == QuotaTone.loading ? c.muted : c.outline;
    return ExcludeSemantics(
      child: Row(
        spacing: Space.s1,
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: i < filled ? on : off,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pil kecil dengan ikon: "Reset 07.00", "OpenRouter", "Diblokir".
class QuotaPill extends StatelessWidget {
  const QuotaPill({
    super.key,
    required this.label,
    required this.icon,
    this.highlight = false,
    this.pink = false,
  });

  final String label;
  final List<List<dynamic>> icon;

  /// Kuning bergaris (kuota abis).
  final bool highlight;
  final bool pink;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: highlight
            ? c.accent
            : pink
            ? c.pink
            : c.muted,
        borderRadius: BorderRadius.circular(Radii.full),
        border: highlight ? Border.all(color: c.ink, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          AppIcon(
            icon,
            size: 14,
            color: highlight || pink ? c.onAccent : c.ink,
          ),
          Text(
            label,
            style: StabiloType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: highlight || pink ? c.onAccent : c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Isi meter kuota di pelat Ex libris (board Kuota AI 01, 7 state).
sealed class QuotaMeterData {
  const QuotaMeterData();
}

class QuotaMeterLoading extends QuotaMeterData {
  const QuotaMeterLoading();
}

class QuotaMeterFailed extends QuotaMeterData {
  const QuotaMeterFailed(this.onRetry);
  final VoidCallback onRetry;
}

class QuotaMeterOwnKey extends QuotaMeterData {
  const QuotaMeterOwnKey();
}

class QuotaMeterRevoked extends QuotaMeterData {
  const QuotaMeterRevoked();
}

class QuotaMeterValue extends QuotaMeterData {
  const QuotaMeterValue({
    required this.percent,
    required this.segments,
    required this.tapsLeft,
    required this.resetsAt,
    required this.now,
  });

  final int percent;
  final int segments;
  final int tapsLeft;
  final DateTime resetsAt;
  final DateTime now;

  bool get exhausted => percent == 0;
  bool get low => percent > 0 && percent < 20;
}

class QuotaMeter extends StatelessWidget {
  const QuotaMeter({super.key, required this.data});

  final QuotaMeterData data;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final label = StabiloType.caption.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink2,
    );
    final note = StabiloType.caption.copyWith(
      fontSize: 12.5,
      height: 1.35,
      color: c.ink2,
    );
    TextStyle big(Color color) =>
        StabiloType.display.copyWith(fontSize: 28, height: 1.05, color: color);

    Widget header(String title, Widget value, Widget? trailing) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: label),
              value,
            ],
          ),
        ),
        ?trailing,
      ],
    );

    final children = switch (data) {
      QuotaMeterLoading() => [
        Text(l.quotaToday, style: label),
        Container(
          width: 84,
          height: 26,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const QuotaSegments(filled: 0, tone: QuotaTone.loading),
        Text(l.quotaLoading, style: note),
      ],
      QuotaMeterFailed(:final onRetry) => [
        header(
          l.quotaToday,
          Text('—', style: big(c.ink)),
          TextButton.icon(
            onPressed: onRetry,
            icon: AppIcon(AppIcons.retry, size: 14, color: c.ink),
            label: Text(l.authTryAgain),
          ),
        ),
        const QuotaSegments(filled: 0, tone: QuotaTone.loading),
        Text(l.quotaLoadFailed, style: note),
      ],
      QuotaMeterOwnKey() => [
        header(
          l.quotaSource,
          Text(l.quotaOwnKey, style: big(c.ink)),
          const QuotaPill(label: 'OpenRouter', icon: AppIcons.key),
        ),
        Text(l.quotaOwnKeyNote, style: note),
      ],
      QuotaMeterRevoked() => [
        header(
          l.quotaFree,
          Text(l.quotaRevoked, style: big(c.danger)),
          QuotaPill(label: l.quotaBlocked, icon: AppIcons.lock, pink: true),
        ),
        Text(l.quotaRevokedNote, style: note),
      ],
      final QuotaMeterValue v => [
        header(
          l.quotaToday,
          Text('${v.percent}%', style: big(v.exhausted ? c.danger : c.ink)),
          QuotaPill(
            icon: AppIcons.sunrise,
            highlight: v.exhausted,
            label: v.exhausted
                ? l.quotaResetAtIn(
                    clockTime(v.resetsAt, locale: locale),
                    _countdown(l, v.now, v.resetsAt),
                  )
                : l.quotaResetAt(clockTime(v.resetsAt, locale: locale)),
          ),
        ),
        QuotaSegments(
          filled: v.segments,
          tone: v.exhausted
              ? QuotaTone.empty
              : v.low
              ? QuotaTone.low
              : QuotaTone.normal,
        ),
        if (v.exhausted)
          Text(l.quotaUsedUp, style: note)
        else if (v.low)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l.quotaLow,
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                ),
                TextSpan(text: ' · ${l.quotaTapsLeft(v.tapsLeft)}'),
              ],
            ),
            style: note,
          )
        else
          Text(l.quotaTapsLeft(v.tapsLeft), style: note),
      ],
    };
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s2,
        children: children,
      ),
    );
  }
}

String _countdown(AppLocalizations l, DateTime now, DateTime reset) {
  final left = untilReset(now, reset);
  return l.quotaCountdown(left.hours, left.minutes);
}

/// Kartu "Kuota gratis hari ini abis" (board Kuota AI 08–11). [large] =
/// sheet Artinya / layar Bedahin (hitung mundur gede); kecil = intip / chat.
class QuotaExhaustedCard extends StatelessWidget {
  const QuotaExhaustedCard({
    super.key,
    required this.now,
    required this.onUseOwnKey,
    this.onOk,
    this.large = true,
    this.tapsPerDay = 40,
    this.peek = false,
  });

  final DateTime now;
  final VoidCallback onUseOwnKey;
  final VoidCallback? onOk;
  final bool large;

  /// "0 dari ± N tap".
  final int tapsPerDay;

  /// Sheet intip: teks aslinya tetap kebaca, isi kartu beda.
  final bool peek;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final reset = nextQuotaReset(now);
    final left = untilReset(now, reset);
    final time = clockTime(reset, locale: locale);
    final zone = reset.timeZoneName;
    final digits = StabiloType.display.copyWith(
      fontSize: 44,
      height: 1,
      color: c.ink,
    );
    final unit = StabiloType.titleSm.copyWith(color: c.ink2);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          if (large) ...[
            Text(
              l.quotaResetIn,
              style: StabiloType.caption.copyWith(color: c.ink2),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: Space.s1,
              children: [
                Text('${left.hours}', style: digits),
                Text(l.quotaHoursUnit, style: unit),
                const SizedBox(width: Space.s2),
                Text('${left.minutes}', style: digits),
                Text(l.quotaMinutesUnit, style: unit),
                const Spacer(),
                QuotaPill(label: '$time $zone', icon: AppIcons.sunrise),
              ],
            ),
            const QuotaSegments(filled: 0, tone: QuotaTone.empty),
            Text(
              l.quotaTapsOf(tapsPerDay),
              style: StabiloType.caption.copyWith(color: c.ink2),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.quotaTapsOfShort(tapsPerDay),
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.ink2,
                    ),
                  ),
                ),
                QuotaPill(
                  label: l.quotaResetAtIn(
                    time,
                    l.quotaCountdown(left.hours, left.minutes),
                  ),
                  icon: AppIcons.sunrise,
                  highlight: true,
                ),
              ],
            ),
            const QuotaSegments(filled: 0, tone: QuotaTone.empty),
          ],
          Text(
            l.quotaExhaustedTitle,
            style: StabiloType.titleSm.copyWith(color: c.ink),
          ),
          Text(
            peek
                ? l.quotaPeekBody(time)
                : l.quotaExhaustedBody(time, left.hours, left.minutes),
            style: StabiloType.body.copyWith(color: c.ink2),
          ),
          _QuotaActions(onUseOwnKey: onUseOwnKey, onOk: onOk),
        ],
      ),
    );
  }
}

/// Kartu "Akses AI gratis lo dicabut" (board Kuota AI 12).
class QuotaBannedCard extends StatelessWidget {
  const QuotaBannedCard({super.key, required this.onUseOwnKey, this.onOk});

  final VoidCallback onUseOwnKey;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: QuotaPill(
              label: l.quotaBannedPill,
              icon: AppIcons.lock,
              pink: true,
            ),
          ),
          Text(
            l.quotaBannedTitle,
            style: StabiloType.titleSm.copyWith(color: c.ink),
          ),
          Text(
            l.quotaBannedBody,
            style: StabiloType.body.copyWith(color: c.ink2),
          ),
          _QuotaActions(onUseOwnKey: onUseOwnKey, onOk: onOk),
        ],
      ),
    );
  }
}

class _QuotaActions extends StatelessWidget {
  const _QuotaActions({required this.onUseOwnKey, this.onOk});

  final VoidCallback onUseOwnKey;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(
      spacing: 10,
      children: [
        if (onOk != null)
          Expanded(
            child: AppButton.secondary(label: l.quotaOk, onPressed: onOk),
          ),
        Expanded(
          flex: 2,
          child: AppButton.primary(
            label: l.quotaUseOwnKey,
            icon: AppIcons.key,
            onPressed: onUseOwnKey,
          ),
        ),
      ],
    );
  }
}
