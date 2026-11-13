import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';

/// Sumber idToken Google untuk `POST /v1/auth/sign-in/social`.
abstract interface class GoogleIdTokenSource {
  /// Null = user nutup / batal di jendela Google (balik ke layar Masuk tanpa
  /// pesan error, board Akun copy & aturan).
  Future<String?> idToken();
}

/// Kode error saat login Google belum bisa dipakai di build ini.
const googleNotConfigured = 'GOOGLE_NOT_CONFIGURED';

/// Placeholder sampai OAuth Client ID Google diisi (#211): diganti
/// implementasi `google_sign_in` dengan `serverClientId` = web client ID.
class UnconfiguredGoogle implements GoogleIdTokenSource {
  const UnconfiguredGoogle();

  @override
  Future<String?> idToken() async => throw const BackendException(
    code: googleNotConfigured,
    message: 'Google sign-in is not configured in this build',
  );
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => const UnconfiguredGoogle(),
);
