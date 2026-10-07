import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/luma_logo.dart';
import 'package:luma/ui/features/splash/splash_overlay.dart';

Future<void> pumpGate(
  WidgetTester tester, {
  bool enabled = true,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: stabiloTheme(brightness),
      home: SplashGate(
        enabled: enabled,
        child: const Scaffold(body: Center(child: Text('rak'))),
      ),
    ),
  );
}

void main() {
  LumaLogo logo(WidgetTester tester) =>
      tester.widget<LumaLogo>(find.byType(LumaLogo));

  double wordmarkOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      )
      .opacity;

  testWidgets('disabled: no overlay at all', (tester) async {
    await pumpGate(tester, enabled: false);
    expect(find.byType(SplashOverlay), findsNothing);
    expect(find.text('rak'), findsOneWidget);
  });

  testWidgets('the stabilo is drawn, the dot pops, then it lands', (
    tester,
  ) async {
    await pumpGate(tester);
    expect(find.byType(SplashOverlay), findsOneWidget);
    // Wordmark and tagline come after the symbol is drawn, not before.
    expect(wordmarkOpacity(tester), 0);

    // 0 ms: nothing drawn yet, big (128), shadow on (light).
    expect(
      (logo(tester).draw, logo(tester).dot, logo(tester).size),
      (0, 0, 128),
    );
    expect(logo(tester).shadow, 1);
    expect(
      tester.getCenter(find.byType(LumaLogo)),
      const Offset(195, 844 / 2 - 15 - 183 / 2 + 64),
    );

    await tester.pump(const Duration(milliseconds: 225));
    expect(logo(tester).draw, inExclusiveRange(0, 1));
    expect(logo(tester).dot, 0);
    expect(wordmarkOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 225)); // 450
    expect(logo(tester).draw, 1);

    await tester.pump(const Duration(milliseconds: 150)); // 600: popping
    expect(logo(tester).dot, greaterThan(1)); // overshoots to 1.25 first
    expect(wordmarkOpacity(tester), inExclusiveRange(0, 1)); // rising in

    await tester.pump(const Duration(milliseconds: 100)); // 700
    expect(logo(tester).dot, closeTo(1, 0.01));
    expect(logo(tester).size, 128);
    expect(wordmarkOpacity(tester), closeTo(1, 0.01)); // fully in

    await tester.pump(const Duration(milliseconds: 150)); // 850: flying
    expect(logo(tester).size, inExclusiveRange(28, 128));
    expect(wordmarkOpacity(tester), inExclusiveRange(0, 1)); // fading out

    await tester.pump(const Duration(milliseconds: 150)); // 1000: landed
    // Header slot: 24 margin - 3, in the 60pt bar, 28 wide.
    expect(
      tester.getRect(find.byType(LumaLogo)),
      const Rect.fromLTWH(21, 16, 28, 28),
    );
    expect(logo(tester).shadow, 0);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(SplashOverlay), findsNothing);
    expect(find.text('rak'), findsOneWidget);
  });

  testWidgets('the shelf shows through while the logo glides', (tester) async {
    await pumpGate(tester);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 150));
    final bg = tester.widget<Opacity>(
      find
          .ancestor(of: find.byType(ColoredBox), matching: find.byType(Opacity))
          .first,
    );
    expect(bg.opacity, closeTo(0.5, 0.01)); // halfway through 700-1000
  });

  testWidgets('follows the iPhone, not the Aa theme (like the launch screen)', (
    tester,
  ) async {
    // Aa forced light, iPhone dark: the launch screen is dark, so is this.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpGate(tester); // MaterialApp theme: light
    final bg = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(bg.color, StabiloColors.dark.canvas);
    expect(logo(tester).shadow, 0); // dark: no shadow
    await tester.pump(const Duration(milliseconds: 1100));
  });

  testWidgets('dark iPhone: no shadow behind the stabilo', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpGate(tester, brightness: Brightness.dark);
    expect(logo(tester).shadow, 0);
    await tester.pump(const Duration(milliseconds: 1100));
  });

  testWidgets('reduce motion: static logo, 200 ms fade, no flight', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpGate(tester);
    expect(
      (logo(tester).draw, logo(tester).dot, logo(tester).size),
      (1, 1, 128),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(logo(tester).size, 128);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(SplashOverlay), findsNothing);
  });
}
