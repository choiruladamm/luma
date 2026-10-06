import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A typo'd family silently falls back to the system font.
  test('every Stabilo font family is bundled', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final families = {for (final f in manifest) f['family'] as String};
    expect(
      families,
      containsAll([
        StabiloType.ui,
        StabiloType.readingFont,
        StabiloType.bookFont,
      ]),
    );
  });

  test('dark mode adds 0.05 to reading line height', () {
    expect(
      StabiloType.forBrightness(StabiloType.reading, Brightness.dark).height,
      closeTo(1.7, 1e-9),
    );
    expect(
      StabiloType.forBrightness(StabiloType.reading, Brightness.light),
      StabiloType.reading,
    );
  });
}
