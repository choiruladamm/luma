import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai_prompt.dart';
import '../../domain/breakdown_prompt.dart';
import '../../domain/models/ai_reply.dart';

/// OpenRouter (API OpenAI-compatible, docs/llm.md).
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
  /// jumlah terjemahan gak cocok) dicoba ulang sampe total [attempts] kali.
  Future<AiReply> explain({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    int attempts = 2,
  }) async {
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    for (var attempt = 1; ; attempt++) {
      final content = await _complete(
        apiKey,
        model,
        aiUserPrompt(book: book, context: context, target: target),
      );
      try {
        return parseAiReply(content, target.length);
      } on AiException {
        if (attempt >= attempts) rethrow;
      }
    }
  }

  /// Jawaban format bersection ([aiStreamSystemPrompt]) potongan demi
  /// potongan, sampe `data: [DONE]`. Koneksi putus / ditutup sebelum itu →
  /// [AiError.network]; error di tengah stream → [AiError.http]. Validasi di
  /// pemanggil. [cancel] = tutup sheet / Lanjut.
  Stream<String> explainStream({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    CancelToken? cancel,
  }) => _stream(
    apiKey,
    model,
    aiStreamSystemPrompt,
    aiUserPrompt(book: book, context: context, target: target),
    cancel,
  );

  /// Bedahin satu grup, format bersection ([breakdownSystemPrompt]); sama
  /// kayak [explainStream], validasi ([parseBreakdown]) di pemanggil.
  Stream<String> breakdownStream({
    required String? apiKey,
    required String model,
    required BreakdownInput input,
    CancelToken? cancel,
  }) => _stream(
    apiKey,
    model,
    breakdownSystemPrompt,
    breakdownUserPrompt(input),
    cancel,
  );

  Stream<String> _stream(
    String? apiKey,
    String model,
    String system,
    String user,
    CancelToken? cancel,
  ) async* {
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    final res = await _post<ResponseBody>(
      apiKey,
      model,
      system,
      user,
      stream: true,
      cancel: cancel,
    );
    final sse = SseDecoder();
    try {
      await for (final chunk in utf8.decoder.bind(res.data!.stream)) {
        for (final data in sse.add(chunk)) {
          if (data == '[DONE]') return;
          final delta = _delta(data);
          if (delta.isNotEmpty) yield delta;
        }
      }
    } on DioException catch (e) {
      throw await _failure(e);
    } on AiException {
      rethrow;
    } catch (e) {
      // Socket ditutup di tengah jalan.
      throw AiException(AiError.network, detail: '$e');
    }
    throw const AiException(AiError.network, detail: 'stream ended early');
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
      throw await _failure(e);
    }
  }

  Future<String> _complete(String apiKey, String model, String user) async {
    final res = await _post<Object?>(apiKey, model, aiSystemPrompt, user);
    final content = switch (res.data) {
      {'choices': [{'message': {'content': final String c}}, ...]} => c,
      _ => null,
    };
    if (content == null) {
      throw const AiException(AiError.invalidResponse, detail: 'no content');
    }
    return content;
  }

  Future<Response<T>> _post<T>(
    String apiKey,
    String model,
    String system,
    String user, {
    bool stream = false,
    CancelToken? cancel,
    bool reasoningOff = true,
  }) async {
    try {
      return await _dio.post<T>(
        '/chat/completions',
        cancelToken: cancel,
        options: _auth(apiKey)
            .copyWith(responseType: stream ? ResponseType.stream : null),
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          // Token reasoning dihitung output dan bikin lambat: matiin. Model
          // yang gak bisa dimatiin dapet yang paling minim, gak ikut dibalikin.
          'reasoning': reasoningOff
              ? {'enabled': false}
              : {'effort': 'minimal', 'exclude': true},
          if (stream) 'stream': true,
          if (!stream) 'response_format': {'type': 'json_object'},
        },
      );
    } on DioException catch (e) {
      final failure = await _failure(e);
      if (reasoningOff && _reasoningMandatory(failure)) {
        return _post<T>(
          apiKey,
          model,
          system,
          user,
          stream: stream,
          cancel: cancel,
          reasoningOff: false,
        );
      }
      throw failure;
    }
  }

  /// Isi `delta.content` satu event SSE; event error → [AiError.http].
  static String _delta(String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      return '';
    }
    return switch (json) {
      {'error': final Object error} => throw AiException(
        AiError.http,
        status: switch (error) {
          {'code': final int code} => code,
          _ => null,
        },
        detail: '$error',
      ),
      {'choices': [{'delta': {'content': final String c}}, ...]} => c,
      _ => '',
    };
  }

  /// Sebagian model (mis. GLM 5.3 Flash) nolak reasoning dimatiin: 400
  /// "Reasoning is mandatory for this endpoint and cannot be disabled."
  static bool _reasoningMandatory(AiException e) =>
      e.status == 400 &&
      '${e.detail}'.toLowerCase().contains('reasoning is mandatory');

  static Options _auth(String apiKey) =>
      Options(headers: {'Authorization': 'Bearer $apiKey'});

  static Future<AiException> _failure(DioException e) async => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const AiException(AiError.timeout),
    DioExceptionType.badResponse => AiException(
      AiError.http,
      status: e.response?.statusCode,
      detail: await _body(e.response?.data),
    ),
    _ => AiException(AiError.network, detail: e.message),
  };

  /// Body error; request streaming dapetnya [ResponseBody] yang belum dibaca.
  static Future<String> _body(Object? data) async =>
      data is ResponseBody ? await utf8.decodeStream(data.stream) : '$data';
}

/// Pemotong Server-Sent Events: potongan teks masuk, isi baris `data:` yang
/// udah utuh keluar. Baris yang kepotong di batas chunk ditahan; baris
/// komentar (`: OPENROUTER PROCESSING`) dan field lain dibuang.
class SseDecoder {
  String _buffer = '';

  List<String> add(String chunk) {
    _buffer += chunk;
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();
    return [
      for (final line in lines)
        if (line.startsWith('data:')) line.substring(5).trim(),
    ];
  }
}

final openRouterServiceProvider = Provider<OpenRouterService>(
  (ref) => OpenRouterService(),
);
