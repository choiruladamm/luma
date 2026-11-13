import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/auth_repository.dart';
import 'package:luma/data/services/auth_service.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/session_store.dart';

import '../support/backend_fakes.dart';

void main() {
  late FakeAdapter adapter;
  late SessionStore store;
  late AuthRepository repo;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    adapter = FakeAdapter();
    store = SessionStore();
    final client = BackendClient(
      baseUrl: 'https://luma.test',
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (_) async {},
    );
    repo = AuthRepository(AuthService(client), store);
  });

  Map<String, Object?> sentBody(int i) =>
      jsonDecode(jsonEncode(adapter.requests[i].data)) as Map<String, Object?>;

  group('sign-up / sign-in (contract)', () {
    test('sign-up sends name, email, password and the invite header', () async {
      final fixture = contract('auth-sign-up-email');
      adapter.queue.add(fromContract(fixture));

      final result = await repo.signUpEmail(
        name: ' Adam ',
        email: ' adam@luma.test ',
        password: 'rahasia-banget-123',
        inviteCode: ' BETA-0001 ',
      );

      final req = fixture['request']! as Map<String, Object?>;
      final sent = adapter.requests.single;
      expect(sent.method, req['method']);
      expect(sent.uri.path, req['path']);
      expect(sent.headers['x-invite-code'], 'BETA-0001');
      expect(sentBody(0), req['body']);
      expect(result.user.email, 'adam@luma.test');
      expect(result.switchedAccount, isFalse);
      expect(await store.readToken(), 'tok123.sig456');
      expect(await repo.hasSession(), isTrue);
    });

    test('sign-in stores the token from set-auth-token', () async {
      adapter.queue.add(fromContract(contract('auth-sign-in-email')));

      await repo.signInEmail(
        email: 'adam@luma.test',
        password: 'rahasia-banget-123',
      );

      expect(await store.readToken(), 'tok123.sig456');
      expect(await store.readLastUserId(), 'user-1');
    });

    test(
      'wrong password surfaces the server code and stores nothing',
      () async {
        adapter.queue.add(fromContract(contract('error-invalid-credentials')));

        await expectLater(
          repo.signInEmail(email: 'adam@luma.test', password: 'salah'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.code,
              'code',
              AuthErrorCode.invalidCredentials,
            ),
          ),
        );
        expect(await repo.hasSession(), isFalse);
      },
    );

    test('bad invite code surfaces INVALID_INVITE_CODE', () async {
      adapter.queue.add(fromContract(contract('error-invalid-invite-code')));

      await expectLater(
        repo.signUpEmail(
          name: 'A',
          email: 'a@luma.test',
          password: 'x' * 10,
          inviteCode: 'SALAH',
        ),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', AuthErrorCode.invalidInvite)
              .having((e) => e.statusCode, 'status', 403),
        ),
      );
    });

    test('sign-up is never retried after a dropped connection', () async {
      adapter.queue.add(DioExceptionType.connectionError);

      await expectLater(
        repo.signUpEmail(
          name: 'A',
          email: 'a@luma.test',
          password: 'x' * 10,
          inviteCode: 'X',
        ),
        throwsA(
          isA<BackendException>().having((e) => e.code, 'code', 'NETWORK'),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test(
      'a different account than last time is flagged and not saved yet',
      () async {
        await store.writeLastUserId('akun-lama');
        await store.writeLastUserEmail('lama@luma.test');
        adapter.queue.add(fromContract(contract('auth-sign-in-email')));

        final result = await repo.signInEmail(
          email: 'adam@luma.test',
          password: 'p' * 10,
        );

        expect(result.switchedAccount, isTrue);
        expect(result.previousEmail, 'lama@luma.test');
        expect(await repo.hasSession(), isFalse);
        expect(await store.readLastUserId(), 'akun-lama');
      },
    );

    test('commit saves the switched session as the new owner', () async {
      await store.writeLastUserId('akun-lama');
      adapter.queue.add(fromContract(contract('auth-sign-in-email')));
      final result = await repo.signInEmail(
        email: 'adam@luma.test',
        password: 'p' * 10,
      );

      await repo.commit(result.session);

      expect(await store.readToken(), 'tok123.sig456');
      expect(await store.readLastUserId(), 'user-1');
      expect(await store.readLastUserEmail(), 'adam@luma.test');
    });

    test('discard signs the new session out and keeps the old owner', () async {
      await store.writeLastUserId('akun-lama');
      adapter.queue
        ..add(fromContract(contract('auth-sign-in-email')))
        ..add(json(200, {'success': true}));
      final result = await repo.signInEmail(
        email: 'adam@luma.test',
        password: 'p' * 10,
      );

      await repo.discard(result.session);

      expect(adapter.requests.last.uri.path, '/v1/auth/sign-out');
      expect(
        adapter.requests.last.headers['authorization'],
        'Bearer tok123.sig456',
      );
      expect(await repo.hasSession(), isFalse);
      expect(await store.readLastUserId(), 'akun-lama');
    });

    test('Google sign-in sends the idToken and the invite header', () async {
      adapter.queue.add(fromContract(contract('auth-sign-in-email')));

      await repo.signInGoogle(
        idToken: 'id-token-google',
        inviteCode: 'LUMA-7Q2K',
      );

      final req = adapter.requests.single;
      expect(req.uri.path, '/v1/auth/sign-in/social');
      expect(req.headers['x-invite-code'], 'LUMA-7Q2K');
      expect(req.data, {
        'provider': 'google',
        'idToken': {'token': 'id-token-google'},
      });
    });

    test(
      'a new account without a code surfaces INVITE_CODE_REQUIRED (contract)',
      () async {
        adapter.queue.add(fromContract(contract('error-invite-code-required')));

        await expectLater(
          repo.signUpEmail(name: 'A', email: 'a@luma.test', password: 'x' * 10),
          throwsA(
            isA<BackendException>().having(
              (e) => e.code,
              'code',
              AuthErrorCode.inviteRequired,
            ),
          ),
        );
        expect(
          adapter.requests.single.headers.containsKey('x-invite-code'),
          isFalse,
        );
      },
    );
  });

  group('session', () {
    test('hasSession reads storage only, no network', () async {
      expect(await repo.hasSession(), isFalse);
      await store.writeToken('tok');
      expect(await repo.hasSession(), isTrue);
      expect(adapter.requests, isEmpty);
    });

    test(
      'currentUser parses /v1/me with the bearer token (contract)',
      () async {
        await store.writeToken('tok123.sig456');
        adapter.queue.add(fromContract(contract('me')));

        final user = await repo.currentUser();

        expect(user?.id, 'user-1');
        expect(user?.image, isNull);
        expect(
          adapter.requests.single.headers['authorization'],
          'Bearer tok123.sig456',
        );
      },
    );

    test(
      '401 from /v1/me keeps the token so the app stays open (contract)',
      () async {
        await store.writeToken('mati');
        adapter.queue.add(fromContract(contract('error-unauthorized')));

        await expectLater(
          repo.currentUser(),
          throwsA(
            isA<BackendException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(await repo.hasSession(), isTrue);
      },
    );

    test(
      'signOut clears the token even when offline, keeps last account',
      () async {
        await store.writeToken('tok');
        await store.writeLastUserId('user-1');
        adapter.queue.addAll(List.filled(3, DioExceptionType.connectionError));

        await repo.signOut();

        expect(await repo.hasSession(), isFalse);
        expect(await store.readLastUserId(), 'user-1');
      },
    );
  });

  group('deleteAccount', () {
    test(
      'clears token and last account once the server says deleted (contract)',
      () async {
        await store.writeToken('tok');
        await store.writeLastUserId('user-1');
        adapter.queue
          ..add(json(202, {'status': 'pending'}))
          ..add(fromContract(contract('me-delete')));

        await repo.deleteAccount();

        expect(adapter.requests, hasLength(2));
        expect(adapter.requests.first.method, 'DELETE');
        expect(await repo.hasSession(), isFalse);
        expect(await store.readLastUserId(), isNull);
      },
    );

    test('gives up after a bounded number of pending answers', () async {
      await store.writeToken('tok');
      adapter.queue.addAll(
        List.generate(
          AuthRepository.deleteAttempts,
          (_) => json(202, {'status': 'pending'}),
        ),
      );

      await expectLater(
        repo.deleteAccount(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'DELETE_PENDING',
          ),
        ),
      );
      expect(adapter.requests, hasLength(AuthRepository.deleteAttempts));
      expect(await repo.hasSession(), isTrue);
    });
  });
}
