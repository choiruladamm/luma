import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'http_client.dart';

/// URL Worker per flavor (docs/backend.md, Lingkungan). `SUBDOMAIN` diganti
/// subdomain workers.dev akun setelah deploy pertama (`make backend-deploy e=dev`).
const backendUrls = {
  'dev': 'https://luma-backend-dev.SUBDOMAIN.workers.dev',
  'prod': 'https://luma-backend.SUBDOMAIN.workers.dev',
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
    final res = await _send(() => _dio.get<Map<String, Object?>>('/v1/health'));
    return BackendHealth.fromJson(res.data!);
  }

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await request();
      } on DioException catch (e) {
        if (attempt >= backendMaxAttempts || !backendShouldRetry(e)) {
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
