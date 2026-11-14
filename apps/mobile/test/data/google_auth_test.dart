import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/google_auth.dart';

void main() {
  group('googleSourceFor', () {
    test('dev flavor signs in natively with the dev clients', () {
      final source = googleSourceFor('dev');

      expect(source, isA<NativeGoogle>());
      final google = source as NativeGoogle;
      expect(google.serverClientId, googleClients['dev']!.server);
      expect(google.iosClientId, googleClients['dev']!.ios);
    });

    test('prod uses its own iOS client and the shared web client', () {
      final google = googleSourceFor('prod') as NativeGoogle;
      expect(google.serverClientId, googleClients['dev']!.server);
      expect(google.iosClientId, isNot(googleClients['dev']!.ios));
    });

    test('unflavored builds stay unconfigured', () {
      expect(googleSourceFor(null), isA<UnconfiguredGoogle>());
    });
  });

  group('googleCanceledOrThrow', () {
    test('closing the Google sheet is a quiet null', () {
      const e = GoogleSignInException(code: GoogleSignInExceptionCode.canceled);

      expect(googleCanceledOrThrow(e), isNull);
    });

    test('other failures become a backend error', () {
      const e = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'bad SHA-1',
      );

      expect(
        () => googleCanceledOrThrow(e),
        throwsA(
          isA<BackendException>()
              .having((x) => x.code, 'code', googleSignInFailed)
              .having((x) => x.message, 'message', contains('bad SHA-1')),
        ),
      );
    });
  });
}
