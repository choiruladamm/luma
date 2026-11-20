import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'http_client.dart';

/// Worker URL per flavor (docs/backend.md, Environments and bindings).
///
/// The prod environment exists only after the backend is merged to master
/// (`make backend-deploy e=prod`).
const backendUrls = {
  // Custom domain: some ISPs (XL) block `*.workers.dev`.
  'dev': 'https://luma-api-dev.chrl.cloud',
  'prod': 'https://luma-api.chrl.cloud',
};

/// Overrides the flavor URL via `--dart-define=BACKEND_URL=http://<ip>:8787`,
/// to reach `make backend-dev` from a device.
const _backendUrlOverride = String.fromEnvironment('BACKEND_URL');

/// Returns the Worker URL: flavor `dev` maps to env dev; anything else (prod or no flavor) maps to prod.
String backendBaseUrl(String? flavor, {String override = _backendUrlOverride}) {
  if (override.isNotEmpty) return override;
  if (flavor == 'dev') return backendUrls['dev']!;
  return backendUrls['prod']!;
}

/// Represents an error from the backend.
///
/// [code] is the server's `UPPER_SNAKE_CASE` code (`{"error": {"code", "message"}}`),
/// or `NETWORK` / `UNKNOWN` when the client produced it.
class BackendException implements Exception {
  const BackendException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final String code;
  final String message;
  final int? statusCode;

  /// Comes from the `Retry-After` header: the next automatic trigger waits at
  /// least this long (docs/budgets.md, Client request policy).
  final Duration? retryAfter;

  @override
  String toString() => 'BackendException($statusCode $code: $message)';
}

class BackendHealth {
  const BackendHealth({required this.status, required this.env});

  factory BackendHealth.fromJson(Map<String, Object?> json) => BackendHealth(
    status: json['status']! as String,
    env: json['env']! as String,
  );

  final String status;
  final String env;
}

/// Maximum attempts per call: the first try plus two retries.
const backendMaxAttempts = 3;

/// Returns the delay before attempt [attempt] + 1: 0.5 s, then 1 s.
Duration backendBackoff(int attempt) =>
    Duration(milliseconds: 500 * (1 << (attempt - 1)));

/// Returns true only for network drops/timeouts and 5xx without `Retry-After`.
///
/// 4xx, 429, and the 503 kill switch (which carries `Retry-After`) are thrown
/// immediately: automatic triggers wait for the next trigger instead of looping.
bool backendShouldRetry(DioException e) {
  final response = e.response;
  if (response == null) {
    return e.type != DioExceptionType.cancel &&
        e.type != DioExceptionType.badCertificate;
  }
  final status = response.statusCode ?? 0;
  return status >= 500 && response.headers.value('retry-after') == null;
}

BackendException backendExceptionFrom(DioException e) {
  final response = e.response;
  if (response == null) {
    return BackendException(code: 'NETWORK', message: e.message ?? e.type.name);
  }
  final retryAfter = int.tryParse(response.headers.value('retry-after') ?? '');
  final data = response.data;
  final error = data is Map ? data['error'] : null;
  return BackendException(
    code: error is Map ? '${error['code']}' : 'UNKNOWN',
    message: error is Map
        ? '${error['message']}'
        : 'HTTP ${response.statusCode}',
    statusCode: response.statusCode,
    retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
  );
}

/// HTTP client for the Luma Worker.
///
/// Never polls: calls come only from triggers (open/resume, user actions,
/// local changes).
class BackendClient {
  BackendClient({
    required String baseUrl,
    Dio? dio,
    this._sleep = Future<void>.delayed,
  }) : _dio = dio ?? lumaDio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 15);
  }

  /// The API version every path goes to (docs/backend.md, API versions).
  static const apiPrefix = '/v2';

  final Dio _dio;
  final Future<void> Function(Duration) _sleep;

  Future<BackendHealth> health() async {
    final res = await request('GET', '/health');
    return BackendHealth.fromJson(res.data!);
  }

  /// Sends one JSON call to the Worker; [token] becomes `Authorization: Bearer`.
  ///
  /// Pass [retry] false for actions that are unsafe to repeat (account
  /// sign-up): a request cut off midway may already have been processed.
  Future<Response<Map<String, Object?>>> request(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
    bool retry = true,
  }) => _send(
    () => _dio.request<Map<String, Object?>>(
      '$apiPrefix$path',
      data: body,
      options: Options(
        method: method,
        headers: {
          ...headers,
          if (token != null) 'authorization': 'Bearer $token',
        },
      ),
    ),
    retry: retry,
  );

  /// Uploads [file] as-is (`PUT`, streamed with `Content-Length`).
  ///
  /// Each retry reads the file from the start.
  Future<Map<String, Object?>> upload(
    String path,
    File file, {
    required String token,
    Map<String, String> headers = const {},
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    final res = await _send(
      () => _dio.put<Map<String, Object?>>(
        '$apiPrefix$path',
        data: file.openRead(),
        onSendProgress: onProgress,
        options: Options(
          headers: {
            ...headers,
            'authorization': 'Bearer $token',
            Headers.contentLengthHeader: length,
            Headers.contentTypeHeader: 'application/octet-stream',
          },
        ),
      ),
    );
    return res.data!;
  }

  /// Downloads the response body of [path] to [savePath].
  Future<void> download(
    String path,
    String savePath, {
    required String token,
  }) => _send(
    () => _dio.download(
      '$apiPrefix$path',
      savePath,
      options: Options(headers: {'authorization': 'Bearer $token'}),
    ),
  );

  Future<Response<T>> _send<T>(
    Future<Response<T>> Function() request, {
    bool retry = true,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await request();
      } on DioException catch (e) {
        if (!retry || attempt >= backendMaxAttempts || !backendShouldRetry(e)) {
          throw backendExceptionFrom(e);
        }
        await _sleep(backendBackoff(attempt));
      }
    }
  }
}

final backendClientProvider = Provider<BackendClient>(
  (ref) => BackendClient(baseUrl: backendBaseUrl(appFlavor)),
);
