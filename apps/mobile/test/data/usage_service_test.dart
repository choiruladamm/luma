import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/usage_service.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/backend_fakes.dart';

void main() {
  test('sends the contract body and parses applied', () async {
    final fixture = contract('usage');
    final adapter = FakeAdapter()..queue.add(fromContract(fixture));
    final service = UsageService(
      BackendClient(
        baseUrl: 'https://luma.test',
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );

    final applied = await service.send('tok', const [
      UsageRow(
        day: '2026-11-12',
        feature: 'group',
        model: 'google/gemini-2.5-flash-lite',
        bookKey: '3539482a',
        bookTitle: 'Meditations',
        keySource: AiKeySource.subsidy,
        calls: 12,
        failed: 1,
        promptTokens: 9800,
        completionTokens: 2400,
        costUsd: 0.00194,
      ),
      UsageRow(
        day: '2026-11-12',
        feature: 'reading',
        bookKey: '3539482a',
        bookTitle: 'Meditations',
        readingSeconds: 1860,
      ),
    ]);

    expect(applied, 2);
    final req = adapter.requests.single;
    expect(req.method, 'POST');
    expect(req.uri.path, '/v2/usage');
    expect(req.headers['authorization'], 'Bearer tok');
    expect(req.data, (fixture['request']! as Map)['body']);
  });
}
