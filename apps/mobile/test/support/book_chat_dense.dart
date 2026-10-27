// #113 test-only embedding transport/cache and in-memory retrieval.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'book_chat_spike.dart';

const embeddingModel = 'baai/bge-m3';
const embeddingDimensions = 1024;

Float32List normalizedVector(Object? value, int dimensions) {
  if (value is! List || value.length != dimensions) {
    throw const FormatException('embedding dimension');
  }
  final vector = Float32List(dimensions);
  var squared = 0.0;
  for (var i = 0; i < dimensions; i++) {
    final n = value[i];
    if (n is! num || !n.isFinite) {
      throw const FormatException('non-finite embedding');
    }
    squared += n * n;
    vector[i] = n.toDouble();
  }
  if (!squared.isFinite ||
      squared <= 0 ||
      vector.any((n) => !n.isFinite) ||
      vector.every((n) => n == 0)) {
    throw const FormatException('invalid embedding norm');
  }
  final norm = math.sqrt(squared);
  for (var i = 0; i < dimensions; i++) {
    vector[i] /= norm;
  }
  return vector;
}

List<Float32List> parseEmbeddings(
  Object? value,
  int count,
  int dimensions, {
  String model = embeddingModel,
}) {
  if (value is! Map ||
      value['model'] is! String ||
      !((value['model'] as String).toLowerCase() == model.toLowerCase() ||
          (model == embeddingModel &&
              value['model'] == 'parasail-bge-m3' &&
              value['provider'] == 'Parasail')) ||
      value['data'] is! List ||
      (value['data'] as List).length != count) {
    throw FormatException(
      'embedding response shape/model: type=${value.runtimeType}, model=${value is Map ? value["model"] : null}, count=${value is Map && value["data"] is List ? (value["data"] as List).length : null}',
    );
  }
  final vectors = List<Float32List?>.filled(count, null);
  for (final row in value['data'] as List) {
    if (row is! Map || row['index'] is! int) {
      throw const FormatException('embedding index');
    }
    final index = row['index'] as int;
    if (index < 0 || index >= count || vectors[index] != null) {
      throw const FormatException('embedding index duplicate/range');
    }
    vectors[index] = normalizedVector(row['embedding'], dimensions);
  }
  return vectors.cast<Float32List>();
}

class EmbeddingCache {
  EmbeddingCache(
    this.file, {
    this.model = embeddingModel,
    this.dimensions = embeddingDimensions,
  }) {
    if (!{
      embeddingModel: 1024,
      'qwen/qwen3-embedding-8b': 4096,
    }.entries.any((e) => e.key == model && e.value == dimensions)) {
      throw ArgumentError('unverified embedding model/dimensions');
    }
    if (!file.existsSync()) return;
    for (final line in file.readAsLinesSync()) {
      final row = jsonDecode(line) as Map<String, dynamic>;
      if (row['model'] != model || row['dimensions'] != dimensions) {
        throw const FormatException('incompatible embedding cache');
      }
      final keys = (row['keys'] as List).cast<String>();
      final data = row['vectors'] as List;
      if (keys.length != data.length || keys.toSet().length != keys.length) {
        throw const FormatException('cache length/duplicate');
      }
      for (var i = 0; i < keys.length; i++) {
        vectors[keys[i]] = normalizedVector(data[i], dimensions);
      }
      ledger.add(
        Map<String, dynamic>.from(row)
          ..remove('vectors')
          ..remove('keys'),
      );
    }
  }
  final File file;
  final String model;
  final int dimensions;
  final vectors = <String, Float32List>{};
  final ledger = <Map<String, dynamic>>[];
  int newRequests = 0;
  int newInputBytes = 0;

  String key(String text) => textHash('$model:$dimensions:$text');
  Float32List vector(String text) =>
      vectors[key(text)] ?? (throw StateError('embedding cache miss'));

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
      throw StateError(
        'cache incomplete; paid command requires explicit opt-in and key',
      );
    }
    final entries = missing.entries.toList();
    final totalBytes = entries.fold<int>(0, (n, e) => n + bytes(e.value));
    // Conservative byte bound at the verified $0.01/M-token listing, not billing usage.
    if (newInputBytes + totalBytes > 1500000 ||
        entries.any((e) => bytes(e.value) > 8000)) {
      throw StateError('embedding input/cost guard');
    }
    file.parent.createSync(recursive: true);
    var offset = 0;
    while (offset < entries.length) {
      // Validate the endpoint with two inputs before submitting the corpus.
      final batch = entries
          .skip(offset)
          .take(newRequests == 0 ? 2 : 64)
          .toList();
      final watch = Stopwatch()..start();
      newRequests++;
      newInputBytes += batch.fold<int>(0, (n, e) => n + bytes(e.value));
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
      // Preserve API usage even if validation rejects a provider response.
      File('${file.path}.last-response.json')
          .writeAsStringSync(jsonEncode(response.data));
      final usageBody = response.data;
      File('${file.path}.usage.jsonl').writeAsStringSync(
        '${jsonEncode({'model': model, 'inputs': batch.length, 'status': response.statusCode, 'id': usageBody is Map ? usageBody['id'] : null, 'usage': usageBody is Map ? usageBody['usage'] : null})}\n',
        mode: FileMode.append,
        flush: true,
      );
      final parsed = parseEmbeddings(
        response.data,
        batch.length,
        dimensions,
        model: model,
      );
      final body = response.data as Map;
      final record = <String, dynamic>{
        'model': model,
        'dimensions': dimensions,
        'keys': batch.map((e) => e.key).toList(),
        'vectors': parsed.map((v) => v.toList()).toList(),
        'usage': body['usage'],
        'provider': body['provider'],
        'responseModel': body['model'],
        'requestId': body['id'],
        'elapsedMs': watch.elapsedMilliseconds,
        'inputs': batch.length,
      };
      file.writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
      for (var i = 0; i < batch.length; i++) {
        vectors[batch[i].key] = parsed[i];
      }
      ledger.add(
        Map<String, dynamic>.from(record)
          ..remove('vectors')
          ..remove('keys'),
      );
      offset += batch.length;
      // ignore: avoid_print
      print('embedding cached $offset/${entries.length} missing inputs');
    }
  }
}

List<Passage> denseSearch(
  List<Passage> corpus,
  EmbeddingCache cache,
  Float32List query,
  String book, {
  int revision = 1,
  int k = 40,
  String? quoteId,
}) {
  final scored = <({Passage passage, double score})>[];
  for (final p in corpus) {
    if (p.book != book || p.revision != revision) continue;
    final vector = cache.vector(p.text);
    if (query.length != vector.length) {
      throw const FormatException('query dimension');
    }
    var score = 0.0;
    for (var i = 0; i < query.length; i++) {
      score += query[i] * vector[i];
    }
    scored.add((passage: p, score: p.id == quoteId ? double.infinity : score));
  }
  scored.sort((a, b) {
    final order = b.score.compareTo(a.score);
    return order == 0 ? a.passage.id.compareTo(b.passage.id) : order;
  });
  return scored.take(k).map((s) => s.passage).toList();
}

/// RRF on BM25 top20 + dense top20, with one vote per ID per list.
List<Passage> fuseRanks(
  List<Passage> lexical,
  List<Passage> dense, {
  String? quoteId,
}) {
  final scores = <String, double>{};
  final passages = <String, Passage>{};
  for (final list in [lexical, dense]) {
    final seen = <String>{};
    for (final (i, p) in list.indexed) {
      if (!seen.add(p.id)) continue;
      passages[p.id] = p;
      scores.update(
        p.id,
        (v) => v + 1 / (60 + i + 1),
        ifAbsent: () => 1 / (60 + i + 1),
      );
    }
  }
  final ids = scores.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == quoteId) return -1;
      if (b == quoteId) return 1;
      final order = scores[b]!.compareTo(scores[a]!);
      return order == 0 ? a.compareTo(b) : order;
    });
  return ids.map((id) => passages[id]!).toList();
}
