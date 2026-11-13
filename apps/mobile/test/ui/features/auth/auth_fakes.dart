import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/repositories/local_data_repository.dart';
import 'package:luma/data/services/auth_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/google_auth.dart';
import 'package:luma/data/services/session_store.dart';

import '../../../support/backend_fakes.dart';

/// Google palsu: idToken tetap, batal (null), atau lempar error.
class FakeGoogle implements GoogleIdTokenSource {
  FakeGoogle([this.result = 'id-token']);

  Object? result;

  @override
  Future<String?> idToken() async {
    final r = result;
    if (r is Exception) throw r;
    return r as String?;
  }
}

class FakeLocalData extends Fake implements LocalDataRepository {
  int wipes = 0;

  @override
  Future<void> wipeBooks() async => wipes++;
}

/// Backend palsu lewat [FakeAdapter] + secure storage mock.
class AuthHarness {
  AuthHarness() {
    client = BackendClient(
      baseUrl: 'https://luma.test',
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (_) async {},
    );
    repo = AuthRepository(AuthService(client), store);
  }

  final adapter = FakeAdapter();
  final store = SessionStore();
  final google = FakeGoogle();
  final local = FakeLocalData();
  late final BackendClient client;
  late final AuthRepository repo;

  List<Override> get overrides => [
    authRepositoryProvider.overrideWithValue(repo),
    googleIdTokenSourceProvider.overrideWithValue(google),
    localDataRepositoryProvider.overrideWithValue(local),
  ];
}
