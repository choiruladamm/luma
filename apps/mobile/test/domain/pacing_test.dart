import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/pacing.dart';

/// Runs a [Pacer] at 60 fps over [arrivals] (seconds → letters that came in
/// by then). Returns the worst lag (seconds) and how long it ran past [done].
({double lag, double tail}) run(
  List<(double, int)> arrivals, {
  required double done,
}) {
  const dt = 1 / 60;
  final pacer = Pacer();
  final total = arrivals.last.$2;
  var t = arrivals.first.$1, lag = 0.0;
  while (pacer.shown < total) {
    final available = arrivals.lastWhere((a) => a.$1 <= t).$2;
    final shown = pacer.step(dt, available, done: t >= done);
    // When did the last shown letter arrive?
    final came = arrivals.firstWhere((a) => a.$2 >= shown).$1;
    if (shown > 0 && t - came > lag) lag = t - came;
    t += dt;
  }
  return (lag: lag, tail: t - done);
}

/// Letters arriving at [cps] from t=1 until [count].
List<(double, int)> steady(double cps, int count) => [
  for (var i = 0; i * 0.05 * cps < count; i++)
    (1 + i * 0.05, (i * 0.05 * cps).round().clamp(0, count)),
  (1 + count / cps, count),
];

void main() {
  test('a fast model never falls more than about a second behind', () {
    // 250 letters/s, like the median model in spike #34.
    final r = run(steady(250, 1000), done: 5);
    expect(r.lag, lessThan(1.2));
    expect(r.tail, lessThanOrEqualTo(Pacer.drain + 0.05));
  });

  test('a slow trickle shows as it comes, at least the baseline', () {
    final r = run(steady(30, 300), done: 11);
    expect(r.lag, lessThan(0.2));
  });

  test('the rest of the buffer goes within drain time once done', () {
    final r = run([(1, 10), (3, 900)], done: 3);
    expect(r.tail, lessThanOrEqualTo(Pacer.drain + 0.05));
  });

  test('an answer complete within 1.5 s shows at once', () {
    final pacer = Pacer();
    pacer.step(0.5, 100, done: false);
    expect(pacer.step(0.016, 800, done: true), 800);
  });

  test('nothing to show stays at zero; never past what arrived', () {
    final pacer = Pacer();
    expect(pacer.step(1, 0, done: false), 0);
    expect(pacer.step(10, 20, done: false), 20);
    // The answer got replaced by a shorter one (non-streaming retry).
    expect(pacer.step(0.016, 5, done: true), 5);
  });

  test('finish shows everything', () {
    final pacer = Pacer()..step(0.1, 2, done: false);
    pacer.finish(500);
    expect(pacer.shown, 500);
  });
}
