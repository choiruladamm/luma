import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/auth/views/login_view.dart';
import 'package:luma/ui/features/auth/views/session_banner.dart';

import '../../../support/backend_fakes.dart';
import 'auth_fakes.dart';

void main() {
  late AuthHarness h;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    h = AuthHarness();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool dev = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...h.overrides, devLoginProvider.overrideWithValue(dev)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(brightness),
          home: const LoginView(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Panggilan backend (secure storage + dio palsu) butuh event loop asli:
  /// gantian jalanin event loop dan pump sampai layarnya tenang.
  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      // Dio jalan di zona jam palsu: timer internalnya ikut dimajuin.
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('release build (Google)', () {
    testWidgets('title page with three chapters and the Google button', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Satu akun buat semua bacaan lo'), findsOneWidget);
      expect(find.text('BAB I'), findsOneWidget);
      expect(find.text('Kuota AI gratis'), findsOneWidget);
      expect(find.text('Backup ke cloud'), findsOneWidget);
      expect(find.text('Sync antar HP'), findsOneWidget);
      expect(find.text('Masuk pakai Google'), findsOneWidget);
      expect(find.text('Kebijakan privasi'), findsOneWidget);
    });

    testWidgets('network failure shows the footnote and "Coba lagi"', (
      tester,
    ) async {
      h.adapter.queue.add(DioExceptionType.connectionError);
      await pump(tester);

      await tapAndWait(tester, find.text('Masuk pakai Google'));

      expect(find.textContaining('Gak bisa nyambung'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets('rejection offers another account', (tester) async {
      h.adapter.queue.add(
        json(403, {
          'error': {'code': 'FORBIDDEN', 'message': 'x'},
        }),
      );
      await pump(tester);

      await tapAndWait(tester, find.text('Masuk pakai Google'));

      expect(find.textContaining('Login-nya ditolak'), findsOneWidget);
      expect(find.text('Pakai akun lain'), findsOneWidget);
    });

    testWidgets('renders in dark theme', (tester) async {
      await pump(tester, brightness: Brightness.dark);
      expect(find.text('Masuk pakai Google'), findsOneWidget);
    });
  });

  group('dev build (email)', () {
    testWidgets('fill-in-the-blank form, buttons enabled once filled', (
      tester,
    ) async {
      await pump(tester, dev: true);

      expect(find.text('Isi yang kosong.'), findsOneWidget);
      expect(find.text('Build developer'), findsOneWidget);
      final signIn = find.widgetWithText(InkWell, 'Masuk');
      expect(find.text('Masuk pakai Google'), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), 'adam@luma.test');
      await tester.enterText(
        find.byType(TextField).at(1),
        'rahasia-banget-123',
      );
      await tester.pump();

      expect(signIn, findsWidgets);
    });

    testWidgets(
      'sign-up without a code opens the invite screen; used code shows its note',
      (tester) async {
        h.adapter.queue
          ..add(fromContract(contract('error-invite-code-required')))
          ..add(fromContract(contract('error-invite-code-used')));
        await pump(tester, dev: true);
        await tester.enterText(find.byType(TextField).at(0), 'baru@luma.test');
        await tester.enterText(
          find.byType(TextField).at(1),
          'rahasia-banget-123',
        );
        await tester.pump();

        await tapAndWait(tester, find.text('Daftar'));

        expect(find.text('Kode undangan gua:'), findsOneWidget);
        expect(find.text('baru@luma.test'), findsOneWidget);
        expect(find.text('Ganti'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'LUMA-4HJP');
        await tester.pump();
        await tapAndWait(tester, find.text('Lanjut'));

        expect(find.textContaining('Kode ini udah dipakai'), findsOneWidget);
        expect(find.text('CATATAN'), findsOneWidget);
      },
    );

    testWidgets('wrong password shows its footnote', (tester) async {
      h.adapter.queue.add(fromContract(contract('error-invalid-credentials')));
      await pump(tester, dev: true);
      await tester.enterText(find.byType(TextField).at(0), 'adam@luma.test');
      await tester.enterText(find.byType(TextField).at(1), 'salah-banget');
      await tester.pump();

      await tapAndWait(tester, find.text('Masuk'));

      expect(
        find.textContaining('Email atau kata sandinya salah'),
        findsOneWidget,
      );
    });
  });

  group('switch account dialog', () {
    testWidgets('different account asks before clearing the phone', (
      tester,
    ) async {
      await h.store.writeLastUserId('akun-lama');
      await h.store.writeLastUserEmail('lama@luma.test');
      h.adapter.queue.add(fromContract(contract('auth-sign-in-email')));
      await pump(tester, dev: true);
      await tester.enterText(find.byType(TextField).at(0), 'adam@luma.test');
      await tester.enterText(
        find.byType(TextField).at(1),
        'rahasia-banget-123',
      );
      await tester.pump();

      await tapAndWait(tester, find.text('Masuk'));
      await tester.pump();

      expect(find.text('Ganti ke akun lain?'), findsOneWidget);
      expect(find.text('lama@luma.test'), findsOneWidget);
      expect(find.text('adam@luma.test'), findsWidgets);

      await tapAndWait(tester, find.text('Hapus isi HP & lanjut'));
      await tester.pump();

      expect(h.local.wipes, 1);
      expect(await h.repo.hasSession(), isTrue);
    });
  });

  testWidgets('session banner: sign in again + close', (tester) async {
    var signIn = 0;
    var close = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('id'),
        theme: stabiloTheme(Brightness.light),
        home: Scaffold(
          body: SessionExpiredBanner(
            onSignIn: () => signIn++,
            onClose: () => close++,
          ),
        ),
      ),
    );

    expect(find.text('Sesi lo habis'), findsOneWidget);
    expect(
      find.text('Baca tetap jalan; backup & sync nunggu dulu.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Login lagi'));
    await tester.tap(find.byTooltip('Tutup'));
    expect((signIn, close), (1, 1));
  });
}
