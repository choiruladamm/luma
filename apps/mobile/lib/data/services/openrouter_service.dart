import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai_prompt.dart';
import '../../domain/models/ai_reply.dart';

/// OpenRouter (API OpenAI-compatible, docs bagian 9).
class OpenRouterService {
  OpenRouterService([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://openrouter.ai/api/v1',
              connectTimeout: _timeout,
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
            ),
          );

  final Dio _dio;
  static const _timeout = Duration(seconds: 30);

  /// Terjemahan per paragraf [target] + maknanya. [context] = 2–3 paragraf
  /// sebelumnya, cuma buat bantu paham. Jawaban yang gak valid (bukan JSON,
  /// jumlah terjemahan gak cocok) dicoba ulang sekali.
  Future<AiReply> explain({
    required String? apiKey,
    required String model,
    required List<String> context,
    required List<String> target,
  }) async {
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    for (var attempt = 1; ; attempt++) {
      final content = await _complete(apiKey, model, context, target);
      try {
        return parseAiReply(content, target.length);
      } on AiException {
        if (attempt == 2) rethrow;
      }
    }
  }

  /// true = key diterima OpenRouter, false = ditolak (401/403). Masalah lain
  /// (offline, timeout) dilempar sebagai [AiException].
  Future<bool> checkKey(String apiKey) async {
    try {
      await _dio.get<Object?>('/key', options: _auth(apiKey));
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return false;
      throw _failure(e);
    }
  }

  Future<String> _complete(
    String apiKey,
    String model,
    List<String> context,
    List<String> target,
  ) async {
    final Response<Object?> res;
    try {
      res = await _dio.post<Object?>(
        '/chat/completions',
        options: _auth(apiKey),
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': aiSystemPrompt},
            {
              'role': 'user',
              'content': aiUserPrompt(context: context, target: target),
            },
          ],
          // Token reasoning dihitung output dan bikin lambat.
          'reasoning': {'enabled': false},
          'response_format': {'type': 'json_object'},
        },
      );
    } on DioException catch (e) {
      throw _failure(e);
    }
    final content = switch (res.data) {
      {'choices': [{'message': {'content': final String c}}, ...]} => c,
      _ => null,
    };
    if (content == null) {
      throw const AiException(AiError.invalidResponse, detail: 'no content');
    }
    return content;
  }

  static Options _auth(String apiKey) =>
      Options(headers: {'Authorization': 'Bearer $apiKey'});

  static AiException _failure(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const AiException(AiError.timeout),
    DioExceptionType.badResponse => AiException(
      AiError.http,
      status: e.response?.statusCode,
    ),
    _ => AiException(AiError.network, detail: e.message),
  };
}

final openRouterServiceProvider = Provider<OpenRouterService>(
  (ref) => OpenRouterService(),
);
