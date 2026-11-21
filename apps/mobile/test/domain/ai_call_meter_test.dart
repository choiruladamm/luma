import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/ai_call_meter.dart';

void main() {
  test('sums reported usage; no report stays null, not zero', () {
    final meter = AiCallMeter();
    expect(meter.usage, isNull);
    expect(meter.firstTokenMs, isNull);
    meter
      ..add((promptTokens: 10, completionTokens: 2, cost: null))
      ..add((promptTokens: 5, completionTokens: 1, cost: 0.5));
    expect(meter.usage, (promptTokens: 15, completionTokens: 3, cost: 0.5));
  });

  test('the first token time is kept', () async {
    final meter = AiCallMeter()..firstToken();
    final first = meter.firstTokenMs;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    meter.firstToken();
    expect(meter.firstTokenMs, first);
    expect(meter.totalMs, greaterThanOrEqualTo(5));
  });
}
