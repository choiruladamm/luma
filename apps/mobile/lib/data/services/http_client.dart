import 'package:dio/dio.dart';

import '../../domain/models/backup.dart';

/// Identifies the client because gutenberg.org blocks user agents without contact details
/// (docs/discover.md, Network and notifications).
const lumaUserAgent = 'Luma/$appVersion (+mailto:work.adamm@gmail.com)';

/// Creates a client for external sources with contact details and a 15-second connect timeout.
/// [receiveTimeout] varies by caller: search 15 s, download 60 s, catalog dump 120 s.
Dio lumaDio({Duration receiveTimeout = const Duration(seconds: 15)}) => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: receiveTimeout,
    headers: {'User-Agent': lumaUserAgent},
  ),
);

/// Runs [request], retrying only 429 and 503 up to [attempts] times.
/// The delay is [delay] multiplied by the attempt number; other errors propagate.
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
