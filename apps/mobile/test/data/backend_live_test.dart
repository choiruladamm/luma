import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/backend_client.dart';

/// Panggil Worker env dev beneran (`make backend-live`). Tanpa
/// `LUMA_BACKEND_LIVE=1` di-skip, jadi `make test` gak nyentuh jaringan.
void main() {
  final live = Platform.environment['LUMA_BACKEND_LIVE'] == '1';

  test('dev Worker answers /v1/health', () async {
    final client = BackendClient(baseUrl: backendBaseUrl('dev', override: ''));

    final health = await client.health();

    expect(health.status, 'ok');
    expect(health.env, 'dev');
  }, skip: live ? false : 'set LUMA_BACKEND_LIVE=1 (make backend-live)');
}
