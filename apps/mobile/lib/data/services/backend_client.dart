import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'http_client.dart';

/// URL Worker per flavor (docs/backend.md, Lingkungan). Env prod baru ada
/// setelah backend di-merge ke master (`make backend-deploy e=prod`).
const backendUrls = {
  // Custom domain: `*.workers.dev` diblok sebagian ISP (XL).
  'dev': 'https://luma-api-dev.chrl.cloud',
  'prod': 'https://luma-api.chrl.cloud',
};

/// `--dart-define=BACKEND_URL=http://<ip>:8787` menimpa URL flavor, buat
/// nyobain ke `make backend-dev` dari device.
const _backendUrlOverride = String.fromEnvironment('BACKEND_URL');

/// Flavor `dev` → Worker env dev; lainnya (prod / tanpa flavor) → prod.
String backendBaseUrl(String? flavor, {String override = _backendUrlOverride}) {
  if (override.isNotEmpty) return override;
  if (flavor == 'dev') return backendUrls['dev']!;
  return backendUrls['prod']!;
}

/// Error dari backend, `code` = kode `UPPER_SNAKE_CASE` server
/// (`{"error": {"code", "message"}}`) atau `NETWORK` / `UNKNOWN` dari client.
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

  /// Dari header `Retry-After`: pemicu otomatis berikutnya nunggu minimal
  /// selama ini (docs/backend.md, Aturan client).
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

/// Maksimal percobaan per pemanggilan (1 + 2 ulang).
const backendMaxAttempts = 3;

/// Jeda sebelum percobaan ke-[attempt] + 1: 0,5 s lalu 1 s.
Duration backendBackoff(int attempt) =>
    Duration(milliseconds: 500 * (1 << (attempt - 1)));

/// Ulang cuma jaringan putus/timeout dan 5xx tanpa `Retry-After`. 4xx, 429,
/// dan 503 saklar darurat (bawa `Retry-After`) langsung dilempar: pemicu
/// otomatis nunggu pemicu berikutnya, bukan loop.
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

/// Client HTTP ke Worker Luma. Tanpa polling: dipanggil cuma dari pemicu
/// (buka/resume, aksi user, perubahan lokal).
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

  final Dio _dio;
  final Future<void> Function(Duration) _sleep;

  Future<BackendHealth> health() async {
    final res = await request('GET', '/v1/health');
    return BackendHealth.fromJson(res.data!);
  }

  /// Satu panggilan JSON ke Worker. [token] → `Authorization: Bearer`.
  /// [retry] false untuk aksi yang gak aman diulang (daftar akun): request yang
  /// putus di tengah bisa aja udah diproses server.
  Future<Response<Map<String, Object?>>> request(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
    bool retry = true,
  }) => _send(
    () => _dio.request<Map<String, Object?>>(
      path,
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

  /// Upload isi [file] apa adanya (`PUT`, di-stream dengan `Content-Length`).
  /// Tiap percobaan ulang baca file dari awal.
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
        path,
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

  /// Download body [path] ke [savePath].
  Future<void> download(
    String path,
    String savePath, {
    required String token,
  }) => _send(
    () => _dio.download(
      path,
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
