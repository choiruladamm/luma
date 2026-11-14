import 'dart:io' show Platform;

import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'backend_client.dart';

/// Sumber idToken Google untuk `POST /v1/auth/sign-in/social`.
abstract interface class GoogleIdTokenSource {
  /// Null = user nutup / batal di jendela Google (balik ke layar Masuk tanpa
  /// pesan error, board Akun copy & aturan).
  Future<String?> idToken();
}

/// Kode error saat login Google belum bisa dipakai di build ini.
const googleNotConfigured = 'GOOGLE_NOT_CONFIGURED';

/// Kode error saat SDK Google gagal (bukan batal): konfigurasi client, jaringan.
const googleSignInFailed = 'GOOGLE_SIGN_IN_FAILED';

/// Client ID OAuth Google per flavor (publik, bukan secret; docs/backend.md,
/// Auth). `server` = web client ID, jadi `aud` idToken yang dicek Worker.
/// iOS butuh client ID-nya sendiri + URL scheme `GOOGLE_REVERSED_CLIENT_ID`
/// (build setting per konfigurasi Xcode). Android cukup `server`, client
/// Android dicocokkan Google lewat package + SHA-1.
/// Web client (`server`) dipakai bersama dev dan prod.
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

/// Placeholder untuk build tanpa client ID Google (tanpa flavor).
class UnconfiguredGoogle implements GoogleIdTokenSource {
  const UnconfiguredGoogle();

  @override
  Future<String?> idToken() async => throw const BackendException(
    code: googleNotConfigured,
    message: 'Google sign-in is not configured in this build',
  );
}

/// Login Google native lewat `google_sign_in` (v7): Credential Manager di
/// Android, GoogleSignIn SDK di iOS.
class NativeGoogle implements GoogleIdTokenSource {
  NativeGoogle({required this.serverClientId, required this.iosClientId});

  final String serverClientId;
  final String iosClientId;

  Future<void>? _init;

  /// `initialize` wajib sekali per proses; gagal → boleh dicoba lagi.
  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance
      .initialize(
        clientId: Platform.isIOS ? iosClientId : null,
        serverClientId: serverClientId,
      )
      .catchError((Object e) {
        _init = null;
        throw e;
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

/// Batal → null (balik ke layar Masuk tanpa pesan). Lainnya → error.
/// Catatan Android: sebagian salah konfigurasi (SHA-1 / package) juga dilapor
/// Credential Manager sebagai `canceled`, plugin gak bisa bedain.
String? googleCanceledOrThrow(GoogleSignInException e) {
  if (e.code == GoogleSignInExceptionCode.canceled) return null;
  throw BackendException(
    code: googleSignInFailed,
    message: 'Google sign-in failed: ${e.code.name} ${e.description ?? ''}',
  );
}

/// Sumber idToken untuk flavor build ini.
GoogleIdTokenSource googleSourceFor(String? flavor) {
  final client = googleClients[flavor];
  if (client == null) return const UnconfiguredGoogle();
  return NativeGoogle(serverClientId: client.server, iosClientId: client.ios);
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => googleSourceFor(appFlavor),
);
