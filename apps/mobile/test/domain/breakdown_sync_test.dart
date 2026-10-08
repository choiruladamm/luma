import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/breakdown_sync.dart';

void main() {
  // Blocks 200pt apart, scrolled by [s]: tops move up.
  List<double> at(double s) => [for (var i = 0; i < 4; i++) i * 200 - s];
  int pick(double s, int current) =>
      activeBlock(at(s), line: 100, current: current);

  test('starts at the first block', () {
    expect(pick(0, 0), 0);
  });

  test('moves on only once the next top is well past the line', () {
    expect(pick(110, 0), 0); // block 1 top at 90: past, but within 24
    expect(pick(124, 0), 1); // top at 76
  });

  test('goes back only once the active top is well below the line', () {
    expect(pick(110, 1), 1); // top at 90, still active
    expect(pick(80, 1), 1); // top at 120: within 24
    expect(pick(70, 1), 0); // top at 130
  });

  test('a fast scroll skips straight to the right block', () {
    expect(pick(500, 0), 2);
    expect(pick(0, 3), 0);
  });

  test('at the end: the last block, however short', () {
    expect(activeBlock(at(300), line: 100, current: 1, atEnd: true), 3);
  });

  test('no blocks: 0; current out of range falls back', () {
    expect(activeBlock(const [], line: 100, current: 2), 0);
    expect(activeBlock(const [0, 400], line: 100, current: 5), 0);
  });
}
