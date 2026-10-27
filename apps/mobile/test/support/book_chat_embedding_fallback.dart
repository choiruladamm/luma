// Test-only model fallback; old frozen embedding helper stays unchanged.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'book_chat_dense.dart';
import 'book_chat_heldout.dart';
import 'book_chat_spike.dart';

const largeEmbeddingModel = 'openai/text-embedding-3-large';
const largeEmbeddingDimensions = 3072;

bool isEmbeddingProviderFailure(DioException e) {
  if ([
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  ].contains(e.type)) {
    return true;
  }
  final status = e.response?.statusCode;
  return e.type == DioExceptionType.badResponse &&
      status != null &&
      ([404, 408, 429].contains(status) || (status >= 500 && status <= 599));
}

String embeddingQueryForModel(String qwenQuery, String model) {
  if (model == heldoutEmbeddingModel) return qwenQuery;
  if (model != largeEmbeddingModel ||
      !qwenQuery.startsWith(heldoutQueryPrefix)) {
    throw ArgumentError('unknown model/query template');
  }
  return qwenQuery.substring(heldoutQueryPrefix.length);
}

/// Implements the existing test cache interface without mutating frozen v1 code.
class LargeEmbeddingCache implements EmbeddingCache {
  LargeEmbeddingCache(this.file) {
    if (!file.existsSync()) return;
    for (final line in file.readAsLinesSync()) {
      final row = jsonDecode(line) as Map<String, dynamic>;
      if (row['model'] != model || row['dimensions'] != dimensions) {
        throw const FormatException('incompatible Large cache');
      }
      final keys = (row['keys'] as List).cast<String>();
      final data = row['vectors'] as List;
      if (keys.length != data.length || keys.toSet().length != keys.length) {
        throw const FormatException('cache count');
      }
      for (var i = 0; i < keys.length; i++) {
        vectors[keys[i]] = normalizedVector(data[i], dimensions);
      }
      ledger.add(
        Map<String, dynamic>.from(row)
          ..remove('keys')
          ..remove('vectors'),
      );
    }
  }
  @override
  final File file;
  @override
  final String model = largeEmbeddingModel;
  @override
  final int dimensions = largeEmbeddingDimensions;
  @override
  final vectors = <String, Float32List>{};
  @override
  final ledger = <Map<String, dynamic>>[];
  @override
  int newRequests = 0;
  @override
  int newInputBytes = 0;
  @override
  String key(String text) => textHash('$model:$dimensions:$text');
  @override
  Float32List vector(String text) =>
      vectors[key(text)] ?? (throw StateError('Large embedding cache miss'));

  @override
  Future<void> fill(
    List<String> texts, {
    required bool live,
    required String? apiKey,
    required Dio dio,
  }) async {
    final missing = {
      for (final t in texts)
        if (!vectors.containsKey(key(t))) key(t): t,
    };
    if (missing.isEmpty) return;
    if (!live || apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('Large cache miss requires opt-in and key');
    }
    final entries = missing.entries.toList();
    final total = entries.fold<int>(0, (n, e) => n + bytes(e.value));
    // Input guard only; billing comes from API usage ($0.13/M-token listing).
    if (newInputBytes + total > 1500000 ||
        entries.any((e) => e.value.isEmpty || bytes(e.value) > 8000)) {
      throw StateError('Large input budget');
    }
    file.parent.createSync(recursive: true);
    var offset = 0;
    while (offset < entries.length) {
      final batch = entries
          .skip(offset)
          .take(newRequests == 0 ? 2 : 64)
          .toList();
      newRequests++;
      newInputBytes += batch.fold<int>(0, (n, e) => n + bytes(e.value));
      final watch = Stopwatch()..start();
      final audit = <String, dynamic>{'model': model, 'inputs': batch.length};
      try {
        final response = await dio.post<Object?>(
          '/embeddings',
          data: {
            'model': model,
            'input': batch.map((e) => e.value).toList(),
            'encoding_format': 'float',
          },
          options: Options(
            headers: {HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
          ),
        );
        final body = response.data;
        if (body is Map) {
          audit.addAll({
            'usage': body['usage'],
            'requestId': body['id'],
            'provider': body['provider'],
          });
        }
        File('${file.path}.last-response.json')
            .writeAsStringSync(jsonEncode(body));
        final responseModel = body is Map ? body['model'] : null;
        if (responseModel is! String ||
            ![
              model,
              'text-embedding-3-large',
            ].contains(responseModel.toLowerCase())) {
          throw const FormatException('unexpected Large response model');
        }
        final parsed = parseEmbeddings(
          body,
          batch.length,
          dimensions,
          model: responseModel,
        );
        final row = <String, dynamic>{
          ...audit,
          'dimensions': dimensions,
          'keys': batch.map((e) => e.key).toList(),
          'vectors': parsed.map((v) => v.toList()).toList(),
          'elapsedMs': watch.elapsedMilliseconds,
        };
        file.writeAsStringSync(
          '${jsonEncode(row)}\n',
          mode: FileMode.append,
          flush: true,
        );
        for (var i = 0; i < batch.length; i++) {
          vectors[batch[i].key] = parsed[i];
        }
        ledger.add(
          Map<String, dynamic>.from(row)
            ..remove('keys')
            ..remove('vectors'),
        );
      } on DioException catch (e) {
        audit['error'] = '${e.type.name}:${e.response?.statusCode ?? ''}';
        rethrow;
      } finally {
        File('${file.path}.usage.jsonl').writeAsStringSync(
          '${jsonEncode(audit)}\n',
          mode: FileMode.append,
          flush: true,
        );
      }
      offset += batch.length;
      // ignore: avoid_print
      print('Large embedding cached $offset/${entries.length} missing inputs');
    }
  }
}

Future<({EmbeddingCache cache, String? fallbackReason})>
fillWithEmbeddingFallback({
  required EmbeddingCache primary,
  required EmbeddingCache fallback,
  required List<String> documents,
  required List<String> primaryQueries,
  required List<String> fallbackQueries,
  required bool live,
  required String? apiKey,
  required Dio dio,
  bool primaryUnavailable = false,
}) async {
  String? reason = primaryUnavailable
      ? 'recorded_primary_provider_timeouts'
      : null;
  if (!primaryUnavailable) {
    try {
      await primary.fill(
        [...documents, ...primaryQueries],
        live: live,
        apiKey: apiKey,
        dio: dio,
      );
      return (cache: primary, fallbackReason: null);
    } on DioException catch (e) {
      if (!isEmbeddingProviderFailure(e)) rethrow;
      reason = '${e.type.name}:${e.response?.statusCode ?? ''}';
    }
  }
  // Rebuild every document and query in one model space, including primary cache hits.
  await fallback.fill(
    [...documents, ...fallbackQueries],
    live: live,
    apiKey: apiKey,
    dio: dio,
  );
  return (cache: fallback, fallbackReason: reason);
}
