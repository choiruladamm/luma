import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/backend_client.dart';

/// Calls the real dev Worker (`make backend-live`). Without
/// `LUMA_BACKEND_LIVE=1` it is skipped, so `make test` never touches the network.
void main() {
  final live = Platform.environment['LUMA_BACKEND_LIVE'] == '1';

  test('dev Worker answers /v2/health', () async {
    final client = BackendClient(baseUrl: backendBaseUrl('dev'));

    final health = await client.health();

    expect(health.status, 'ok');
    expect(health.env, 'dev');
  }, skip: live ? false : 'set LUMA_BACKEND_LIVE=1 (make backend-live)');
}
