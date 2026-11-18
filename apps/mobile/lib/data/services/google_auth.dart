import 'dart:io' show Platform;

import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'backend_client.dart';

/// Source of the Google ID token for `POST /v1/auth/sign-in/social`.
abstract interface class GoogleIdTokenSource {
  /// Returns the ID token, or null when the user closed or cancelled the Google
  /// window (back to the Masuk screen without an error message, board Akun
  /// copy & aturan).
  Future<String?> idToken();
}

/// Error code for when Google sign-in is not usable in this build.
const googleNotConfigured = 'GOOGLE_NOT_CONFIGURED';

/// Error code for when the Google SDK fails (not a cancel): client configuration or network.
const googleSignInFailed = 'GOOGLE_SIGN_IN_FAILED';

/// Google OAuth client IDs per flavor (public, not secrets;
/// docs/operations.md, Google OAuth clients).
///
/// `server` is the web client ID, so it is the `aud` of the ID token the Worker
/// checks. iOS needs its own client ID plus the URL scheme
/// `GOOGLE_REVERSED_CLIENT_ID` (a build setting per Xcode configuration).
/// Android needs only `server`; Google matches the Android client by package
/// name and SHA-1. The web client (`server`) is shared by dev and prod.
const googleClients = {
  'dev': (
    server: '366577823040-vhr2h7toc53pb891v0qoc1m62pps2v41.apps.googleusercontent.com',
    ios: '366577823040-iado5q8njuvdienlc83al1ed2he5u3c0.apps.googleusercontent.com',
  ),
  'prod': (
    server: '366577823040-vhr2h7toc53pb891v0qoc1m62pps2v41.apps.googleusercontent.com',
    ios: '366577823040-4t2j2h8h8c300c1r1fc9olhov42p4ora.apps.googleusercontent.com',
  ),
};

/// Placeholder source for builds without a Google client ID (no flavor).
class UnconfiguredGoogle implements GoogleIdTokenSource {
  const UnconfiguredGoogle();

  @override
  Future<String?> idToken() async => throw const BackendException(
    code: googleNotConfigured,
    message: 'Google sign-in is not configured in this build',
  );
}

/// Signs in with Google natively through `google_sign_in` (v7).
///
/// Uses Credential Manager on Android and the GoogleSignIn SDK on iOS.
class NativeGoogle implements GoogleIdTokenSource {
  NativeGoogle({required this.serverClientId, required this.iosClientId});

  final String serverClientId;
  final String iosClientId;

  Future<void>? _init;

  // `initialize` must run once per process; a failure may be retried.
  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance
      .initialize(
        clientId: Platform.isIOS ? iosClientId : null,
        serverClientId: serverClientId,
      )
      .catchError((Object e, StackTrace st) {
        _init = null;
        Error.throwWithStackTrace(e, st);
      });

  @override
  Future<String?> idToken() async {
    try {
      await _ensureInit();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw const BackendException(
          code: googleSignInFailed,
          message: 'Google returned no idToken',
        );
      }
      return token;
    } on GoogleSignInException catch (e) {
      return googleCanceledOrThrow(e);
    }
  }
}

/// Returns null on cancel (back to the Masuk screen without a message) and
/// throws for any other error.
///
/// On Android, Credential Manager also reports some misconfigurations (SHA-1,
/// package name) as `canceled`, and the plugin cannot tell them apart.
String? googleCanceledOrThrow(GoogleSignInException e) {
  if (e.code == GoogleSignInExceptionCode.canceled) return null;
  throw BackendException(
    code: googleSignInFailed,
    message: 'Google sign-in failed: ${e.code.name} ${e.description ?? ''}',
  );
}

/// Returns the ID token source for this build's flavor.
///
/// Without a flavor (iOS `make release`, where the Runner scheme is the prod
/// bundle) the prod client is used, matching the backend URL.
GoogleIdTokenSource googleSourceFor(String? flavor) {
  final client = googleClients[flavor ?? 'prod'];
  if (client == null) return const UnconfiguredGoogle();
  return NativeGoogle(serverClientId: client.server, iosClientId: client.ios);
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => googleSourceFor(appFlavor),
);
