import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/features/reader/views/meaning_chrome.dart';

void main() {
  late MeaningChrome chrome;
  setUp(() => chrome = MeaningChrome(vsync: const TestVSync()));
  tearDown(() => chrome.dispose());

  // Board Ngumpet · Opsi A: sheet 528, area baca 335 lengkap, 516 ngumpet.
  test('visible reading height: 335 with everything, 516 with nothing', () {
    expect(chrome.readHeight(528), closeTo(335, 1e-9));
    chrome.header.value = 1;
    chrome.actions.value = 1;
    expect(chrome.readHeight(528), closeTo(516, 1e-9));
  });

  test('only the buttons away gives the 102 back, only the header away 79', () {
    chrome.actions.value = 1;
    expect(chrome.readHeight(528), closeTo(335 + 102, 1e-9));
    chrome.actions.value = 0;
    chrome.header.value = 1;
    expect(chrome.readHeight(528), closeTo(335 + 79, 1e-9));
  });

  test('half-way header counts half of its 79pt', () {
    chrome.header.value = 0.5;
    expect(chrome.readHeight(528), closeTo(335 + 39.5, 1e-9));
  });
}
