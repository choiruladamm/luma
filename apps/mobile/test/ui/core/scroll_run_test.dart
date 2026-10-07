import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/scroll_run.dart';

void main() {
  test('down 24pt hides, up 12pt shows, runs in the same direction add up', () {
    final run = ScrollRun();
    expect(run.add(10), isNull);
    expect(run.add(13), isNull); // 23
    expect(run.add(1), ChromeIntent.hide); // 24
    expect(run.add(-6), isNull);
    expect(run.add(-6), ChromeIntent.show); // 12
  });

  test('changing direction starts counting from zero', () {
    final run = ScrollRun();
    expect(run.add(20), isNull);
    expect(run.add(-5), isNull); // the 20 down is forgotten
    expect(run.add(10), isNull); // and the 5 up too
    expect(run.add(14), ChromeIntent.hide);
  });

  test('a decision resets the count; reset() clears it too', () {
    final run = ScrollRun();
    expect(run.add(30), ChromeIntent.hide);
    expect(run.add(10), isNull);
    run.reset();
    expect(run.add(23), isNull);
    expect(run.add(0), isNull);
  });
}
