import 'package:dio/dio.dart';

import '../../domain/models/backup.dart';

/// Kebijakan gutenberg.org: UA tanpa kontak diblok IP (docs/discover.md,
/// Kebijakan jaringan).
const lumaUserAgent = 'Luma/$appVersion (+mailto:work.adamm@gmail.com)';

/// Dio buat sumber luar: UA kontak, connect 15 s, [receiveTimeout] per
/// pemakai (search 15 s, download 60 s, dump katalog 120 s).
Dio lumaDio({Duration receiveTimeout = const Duration(seconds: 15)}) => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: receiveTimeout,
    headers: {'User-Agent': lumaUserAgent},
  ),
);

/// Jalanin [request], ulang sampe [attempts]× cuma buat 429/503 (jeda
/// [delay] × percobaan). Error lain langsung lempar.
Future<T> retryOnBusy<T>(
  Future<T> Function() request, {
  int attempts = 3,
  Duration delay = const Duration(seconds: 2),
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await request();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (attempt >= attempts || (status != 429 && status != 503)) rethrow;
      await Future<void>.delayed(delay * attempt);
    }
  }
}
