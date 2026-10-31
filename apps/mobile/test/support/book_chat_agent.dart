import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// #143 live evidence: records every paid request through the production
/// pipeline (chat completions and embeddings), settles with provider usage,
/// and stops the run when the experiment ceiling is reached. Pricing comes
/// from the live /models metadata, never from a snapshot table.
class AgentLedger {
  AgentLedger(this.file, {this.maxUsd = 5}) {
    if (file.existsSync()) {
      final body = jsonDecode(file.readAsStringSync()) as Map;
      rows.addAll(
        (body['requests'] as List).map(
          (r) => Map<String, Object?>.from(r as Map),
        ),
      );
    }
  }
  final File file;
  final double maxUsd;
  final rows = <Map<String, Object?>>[];

  double get heldUsd =>
      rows.fold(0, (sum, r) => sum + ((r['heldUsd'] as num?) ?? 0).toDouble());

  int reserve(Map<String, Object?> row, double boundUsd) {
    if (heldUsd + boundUsd > maxUsd) {
      throw StateError('Experiment ceiling reached: held ${heldUsd}USD');
    }
    rows.add({...row, 'boundUsd': boundUsd, 'heldUsd': boundUsd});
    save();
    return rows.length - 1;
  }

  void settle(
    int index,
    Map<String, dynamic>? usage,
    Map<String, Object?> extra,
  ) {
    final row = rows[index];
    final cost = usage?['cost'];
    if (cost is num && cost.isFinite && cost >= 0) row['heldUsd'] = cost;
    row['usage'] = usage;
    row['state'] = usage == null ? 'usage_unknown' : 'completed';
    row.addAll(extra);
    save();
  }

  void save() {
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({'requests': rows}),
      flush: true,
    );
    temp.renameSync(file.path);
  }
}

/// Wraps the real adapter: one ledger row per HTTP request, usage parsed from
/// the SSE/JSON body. Both chat and embeddings are allowed and measured.
class AgentAdapter implements HttpClientAdapter {
  AgentAdapter(this.inner, this.ledger, this.pricing, {this.onRow});
  final HttpClientAdapter inner;
  final AgentLedger ledger;

  /// model id → {prompt, completion} USD per token.
  final Map<String, ({double prompt, double completion})> pricing;
  final void Function(Map<String, Object?> row)? onRow;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data;
    if (options.method != 'POST' || body is! Map) {
      return inner.fetch(options, requestStream, cancelFuture);
    }
    final model = body['model'] as String;
    // Embedding models are missing from /models: hold a generous bound,
    // flagged, and settle with the provider's actual usage.cost.
    final price = pricing[model] ?? (prompt: 1e-7, completion: 1e-6);
    final input = utf8.encode(jsonEncode(body)).length;
    final maxTokens = (body['max_tokens'] as int?) ?? 0;
    // Conservative: input tokens ≤ bytes/2 for prose, output ≤ max_tokens.
    final bound = input / 2 * price.prompt + maxTokens * price.completion;
    final row = <String, Object?>{
      'path': options.path,
      'model': model,
      'inputBytes': input,
      'maxTokens': maxTokens,
      'state': 'reserved',
      'priceKnown': pricing.containsKey(model),
      'at': DateTime.now().toIso8601String(),
    };
    if (body['messages'] is List) {
      row['system'] = (body['messages'] as List).first['content'];
      row['user'] = (body['messages'] as List).last['content'];
    }
    final index = ledger.reserve(row, bound);
    final watch = Stopwatch()..start();
    try {
      final response = await inner.fetch(options, requestStream, cancelFuture);
      return ResponseBody(
        _observe(response.stream, index, watch, response.statusCode),
        response.statusCode,
        headers: response.headers,
      );
    } catch (e) {
      ledger.settle(index, null, {'error': '$e'});
      onRow?.call(ledger.rows[index]);
      rethrow;
    }
  }

  Stream<Uint8List> _observe(
    Stream<Uint8List> stream,
    int index,
    Stopwatch watch,
    int status,
  ) async* {
    final bytes = <int>[];
    try {
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        yield chunk;
      }
    } finally {
      Map<String, dynamic>? usage;
      var answer = '';
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('data:') || text.contains('\ndata:')) {
        for (final line in text.split('\n')) {
          if (!line.startsWith('data: ') ||
              line.substring(6).trim() == '[DONE]') {
            continue;
          }
          try {
            final event = jsonDecode(line.substring(6)) as Map;
            if (event['usage'] is Map) {
              usage = Map<String, dynamic>.from(event['usage'] as Map);
            }
            final choices = event['choices'];
            if (choices is List && choices.isNotEmpty) {
              final content = choices.first['delta']?['content'];
              if (content is String) answer += content;
            }
          } on FormatException {
            /* partial transport = unknown usage */
          }
        }
      } else {
        try {
          final event = jsonDecode(text) as Map;
          if (event['usage'] is Map) {
            usage = Map<String, dynamic>.from(event['usage'] as Map);
          }
        } on FormatException {
          /* non-JSON */
        }
      }
      ledger.settle(index, usage, {
        'httpStatus': status,
        'raw': answer,
        'totalMs': watch.elapsedMilliseconds,
      });
      onRow?.call(ledger.rows[index]);
    }
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// Live price per token for every model this run may touch.
Future<Map<String, ({double prompt, double completion})>> agentPricing(
  Dio dio,
  Iterable<String> models,
) async {
  final metadata = await dio.get<Map<String, dynamic>>('/models');
  final rows = metadata.data!['data'] as List;
  final byId = {for (final m in rows) m['id']: m as Map};
  return {
    for (final id in models)
      if (byId[id] case final info?)
        id: (
          prompt: double.parse('${(info['pricing'] as Map)['prompt']}'),
          completion: double.parse('${(info['pricing'] as Map)['completion']}'),
        ),
  };
}

Future<Map<String, dynamic>> agentModelInfo(Dio dio, String model) async {
  final metadata = await dio.get<Map<String, dynamic>>('/models');
  return Map<String, dynamic>.from(
    (metadata.data!['data'] as List).firstWhere((m) => m['id'] == model) as Map,
  );
}
