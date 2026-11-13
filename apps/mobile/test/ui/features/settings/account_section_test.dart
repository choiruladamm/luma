import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/auth_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/auth/view_models/auth_view_model.dart';
import 'package:luma/ui/features/auth/views/login_view.dart';
import 'package:luma/ui/features/settings/views/account_section.dart';

/// Sesi palsu: catat Keluar / Hapus akun tanpa backend.
class FakeAuthController extends AuthController {
  FakeAuthController(this.initial, {this.deleteFails = false});

  final AuthState initial;
  final bool deleteFails;
  int signOuts = 0;
  int deletes = 0;

  @override
  Future<AuthState> build() async => initial;

  @override
  Future<void> signOut() async {
    signOuts++;
    state = const AsyncData(AuthState(AuthStatus.signedOut));
  }

  @override
  Future<void> deleteAccount() async {
    deletes++;
    if (deleteFails) {
      throw const BackendException(code: 'NETWORK', message: 'offline');
    }
    state = const AsyncData(AuthState(AuthStatus.signedOut));
  }
}

const rara = AuthUser(
  id: 'u1',
  name: 'Rara Putri',
  email: 'rara.putri@gmail.com',
);

void main() {
  late FakeAuthController auth;

  Future<void> pump(
    WidgetTester tester, {
    AuthState? state,
    bool deleteFails = false,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = FakeAuthController(
      state ?? const AuthState(AuthStatus.signedIn, user: rara),
      deleteFails: deleteFails,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          devLoginProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(child: AccountSection()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ex libris plate shows name, email and sign-in method', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Akun'), findsOneWidget);
    expect(find.text('EX LIBRIS'), findsOneWidget);
    expect(find.text('Rara Putri'), findsOneWidget);
    expect(find.text('rara.putri@gmail.com'), findsOneWidget);
    expect(find.text('Masuk lewat Google'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
  });

  testWidgets('hidden when signed out', (tester) async {
    await pump(tester, state: const AuthState(AuthStatus.signedOut));
    expect(find.text('EX LIBRIS'), findsNothing);
  });

  testWidgets('sign out asks first, then signs out with a toast', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari akun?'), findsOneWidget);

    await tester.tap(find.text('Keluar').last);
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    expect(find.text('Udah keluar. Buku di HP ini tetap ada.'), findsOneWidget);
  });

  testWidgets('delete needs all three boxes ticked', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Hapus akun'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus akun selamanya?'), findsOneWidget);
    expect(find.text('Akun rara.putri@gmail.com kehapus'), findsOneWidget);

    await tester.tap(find.text('Hapus akun selamanya'));
    await tester.pumpAndSettle();
    expect(auth.deletes, 0);

    for (final box in find.byType(Checkbox).evaluate().toList()) {
      await tester.tap(find.byWidget(box.widget));
      await tester.pump();
    }
    await tester.tap(find.text('Hapus akun selamanya'));
    await tester.pumpAndSettle();

    expect(auth.deletes, 1);
    expect(find.text('Akun lo udah dihapus.'), findsOneWidget);
  });

  testWidgets('failed delete offers a retry', (tester) async {
    await pump(tester, deleteFails: true);

    await tester.tap(find.text('Hapus akun'));
    await tester.pumpAndSettle();
    for (final box in find.byType(Checkbox).evaluate().toList()) {
      await tester.tap(find.byWidget(box.widget));
      await tester.pump();
    }
    await tester.tap(find.text('Hapus akun selamanya'));
    await tester.pumpAndSettle();

    expect(find.text('Gagal hapus akun. Gak ada internet.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
  });
}
