// Fake HTTP + fixture kontrak backend untuk test data Flutter.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Placeholder fixture (`<token>`, `<id>`, `<iso>`) diganti nilai contoh yang
/// realistis supaya client bisa parse respons dari fixture apa adanya.
Object? fillPlaceholders(Object? value) => switch (value) {
  '<token>' => 'tok123.sig456',
  '<id>' => 'user-1',
  '<iso>' => '2026-11-12T15:04:05.123Z',
  final List<Object?> list => list.map(fillPlaceholders).toList(),
  final Map<String, Object?> map => {
    for (final e in map.entries) e.key: fillPlaceholders(e.value),
  },
  _ => value,
};

/// Fixture kontrak bersama backend (apps/backend/test/fixtures/contract).
Map<String, Object?> contract(String name) => jsonDecode(
  File('../backend/test/fixtures/contract/$name.json').readAsStringSync(),
) as Map<String, Object?>;

class FakeAdapter implements HttpClientAdapter {
  final queue = <Object>[];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final next = queue.removeAt(0);
    if (next is ResponseBody) return next;
    if (next is DioExceptionType) {
      throw DioException(requestOptions: options, type: next);
    }
    throw next;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    for (final e in headers.entries) e.key.toLowerCase(): [e.value],
  },
);

/// Respons dari fixture kontrak, apa adanya.
ResponseBody fromContract(Map<String, Object?> fixture) {
  final res = fixture['response']! as Map<String, Object?>;
  final headers = (res['headers'] as Map<String, Object?>? ?? {})
      .cast<String, String>();
  return json(
    res['status']! as int,
    fillPlaceholders(res['body']),
    headers: headers.map((k, v) => MapEntry(k, fillPlaceholders(v)! as String)),
  );
}
