import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_key_repository.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/services/ai_key_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/quota.dart';
import 'package:luma/ui/features/settings/view_models/ai_quota_view_model.dart';

class FakeAuth extends Fake implements AuthRepository {
  @override
  Future<String?> token() async => 't';
}

class FakeAiKeys extends Fake implements AiKeyService {
  int calls = 0;
  bool banned = false;

  @override
  Future<AiUsage> usage(String token) async {
    calls++;
    if (banned) {
      throw const BackendException(code: aiBannedCode, message: 'banned');
    }
    return AiUsage(
      dailyLimitUsd: 0.02,
      remainingUsd: 0.003,
      usedTodayUsd: 0.017,
      resetsAt: DateTime.utc(2026, 11, 14),
    );
  }
}

AiUsage usage(double remaining) => AiUsage(
  dailyLimitUsd: 0.02,
  remainingUsd: remaining,
  usedTodayUsd: 0.02 - remaining,
  resetsAt: DateTime.utc(2026, 11, 14),
);

void main() {
  test('QuotaState: percent, segments, taps, low, exhausted', () {
    final low = QuotaState(usage: usage(0.003));
    expect(low.percent, 15);
    expect(low.segments, 2);
    expect(low.tapsLeft, 6);
    expect(low.low, isTrue);
    expect(low.exhausted, isFalse);
    final empty = QuotaState(usage: usage(0));
    expect(empty.exhausted, isTrue);
    expect(empty.low, isFalse);
    expect(const QuotaState().exhausted, isFalse); // not loaded yet
  });

  group('AiQuotaController', () {
    late FakeAiKeys keys;
    late DateTime now;
    late ProviderContainer c;

    setUp(() {
      keys = FakeAiKeys();
      now = DateTime(2026, 11, 13, 10);
      c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuth()),
          aiKeyServiceProvider.overrideWithValue(keys),
          quotaClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
    });

    test(
      'refresh hits the server at most once an hour unless forced',
      () async {
        expect((await c.read(aiQuotaProvider.future)).percent, 15);
        await c.read(aiQuotaProvider.notifier).refresh();
        expect(keys.calls, 1);
        await c.read(aiQuotaProvider.notifier).refresh(force: true);
        expect(keys.calls, 2);
        now = now.add(const Duration(minutes: 61));
        await c.read(aiQuotaProvider.notifier).refresh();
        expect(keys.calls, 3);
      },
    );

    test('AI_BANNED becomes a banned state, not an error', () async {
      keys.banned = true;
      expect((await c.read(aiQuotaProvider.future)).banned, isTrue);
    });
  });

  group('QuotaMeter', () {
    Future<void> pump(WidgetTester tester, QuotaMeterData data) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(Brightness.light),
          home: Scaffold(body: QuotaMeter(data: data)),
        ),
      );
    }

    final now = DateTime(2026, 11, 13, 10);
    final reset = DateTime(2026, 11, 14, 7);
    QuotaMeterValue value(int percent, int taps) => QuotaMeterValue(
      percent: percent,
      segments: (percent / 10).ceil(),
      tapsLeft: taps,
      resetsAt: reset,
      now: now,
    );

    final cases = <String, (QuotaMeterData, String)>{
      'loading': (const QuotaMeterLoading(), 'Lagi dimuat…'),
      'failed': (QuotaMeterFailed(() {}), 'Gak bisa ngecek sisa kuota.'),
      'own key': (const QuotaMeterOwnKey(), 'Key sendiri'),
      'revoked': (const QuotaMeterRevoked(), 'Dicabut'),
      'normal': (value(70, 28), '± 28 tap lagi'),
      'low': (value(15, 6), '15%'),
      'exhausted': (value(0, 0), 'Kuota gratis hari ini udah kepakai semua.'),
    };
    for (final MapEntry(key: name, value: (data, text)) in cases.entries) {
      testWidgets(name, (tester) async {
        await pump(tester, data);
        expect(find.textContaining(text, findRichText: true), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('failed: retry calls back', (tester) async {
      var retried = 0;
      await pump(tester, QuotaMeterFailed(() => retried++));
      await tester.tap(find.byType(TextButton));
      expect(retried, 1);
    });
  });
}
