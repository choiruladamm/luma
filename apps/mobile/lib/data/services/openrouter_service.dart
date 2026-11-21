import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai_prompt.dart';
import '../../domain/breakdown_prompt.dart';
import '../../domain/chat_budget.dart';
import '../../domain/chat_prompt.dart';
import '../../domain/chat_retrieval.dart';
import '../../domain/models/book_chat.dart';

import '../../domain/models/ai_reply.dart';
import '../repositories/ai_key_repository.dart';

/// Calls the OpenAI-compatible OpenRouter API (docs/llm.md).
class OpenRouterService {
  /// Calls [onKeyRejected] on a 401 so the subsidized key rotates on the next read
  /// (docs/backend.md, AI).
  OpenRouterService([Dio? dio, void Function(String apiKey)? onKeyRejected])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://openrouter.ai/api/v1',
              connectTimeout: _timeout,
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
            ),
          ) {
    if (onKeyRejected == null) return;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          final auth = e.requestOptions.headers['Authorization'];
          if (e.response?.statusCode == 401 && auth is String) {
            onKeyRejected(auth.replaceFirst('Bearer ', ''));
          }
          handler.next(e);
        },
      ),
    );
  }

  final Dio _dio;
  static const _timeout = Duration(seconds: 30);

  /// Translates [target] paragraphs and explains their meaning.
  /// [context] supplies 2–3 preceding paragraphs for context only. Invalid
  /// responses are retried up to [attempts] times; [onUsage] receives each
  /// attempt's reported usage.
  Future<AiReply> explain({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    int attempts = 2,
    void Function(ChatUsage usage)? onUsage,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    for (var attempt = 1; ; attempt++) {
      final content = await _complete(
        apiKey,
        model,
        aiUserPrompt(book: book, context: context, target: target),
        onUsage,
      );
      try {
        return parseAiReply(content, target.length);
      } on AiException {
        if (attempt >= attempts) rethrow;
      }
    }
  }

  /// Streams a sectioned answer ([aiStreamSystemPrompt]) until `data: [DONE]`.
  /// A premature disconnect yields [AiError.network]; stream errors yield
  /// [AiError.http]. The caller validates output and [cancel] closes the stream.
  /// [onUsage] receives the final SSE usage when available.
  Stream<String> explainStream({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    CancelToken? cancel,
    void Function(ChatUsage usage)? onUsage,
  }) => _stream(
    apiKey,
    model,
    aiStreamSystemPrompt,
    aiUserPrompt(book: book, context: context, target: target),
    cancel,
    onUsage: onUsage,
  );

  /// Streams a sectioned group breakdown ([breakdownSystemPrompt]).
  /// As with [explainStream], the caller validates it with [parseBreakdown].
  Stream<String> breakdownStream({
    required String? apiKey,
    required String model,
    required BreakdownInput input,
    CancelToken? cancel,
    void Function(ChatUsage usage)? onUsage,
  }) => _stream(
    apiKey,
    model,
    breakdownSystemPrompt,
    breakdownUserPrompt(input),
    cancel,
    onUsage: onUsage,
  );

  /// Streams chat, rewrite, or selector output with bounded reasoning fallback.
  /// History can be supplied as native user/assistant messages. [inputBytes]
  /// limits request message bytes; [onUsage] receives final SSE usage when available.
  Stream<String> chatStream({
    required String? apiKey,
    required String model,
    required String system,
    required String user,
    List<Map<String, String>> history = const [],
    int maxTokens = chatAnswerMaxTokens,
    int inputBytes = chatSelectorBytes,
    void Function(ChatUsage usage)? onUsage,
    CancelToken? cancel,
  }) {
    final messages = [
      {'role': 'system', 'content': system},
      ...history,
      {'role': 'user', 'content': user},
    ];
    if (maxTokens <= 0 ||
        maxTokens > chatAnswerMaxTokens ||
        history.any(
          (m) =>
              !['user', 'assistant'].contains(m['role']) ||
              m['content'] == null,
        ) ||
        utf8.encode(jsonEncode(messages)).length >
            (inputBytes > chatRequestInputBytes
                ? chatRequestInputBytes
                : inputBytes)) {
      throw const AiException(
        AiError.invalidResponse,
        detail: 'chat input budget',
      );
    }
    return _stream(
      apiKey,
      model,
      system,
      user,
      cancel,
      messages: messages,
      maxTokens: maxTokens,
      jsonOutput: true,
      onUsage: onUsage,
    );
  }

  /// Fetches free provider model metadata without a key.
  /// Returns null on failure so callers can use a conservative fallback.
  Future<ChatModelInfo?> modelInfo(String model, {CancelToken? cancel}) async {
    try {
      final res = await _dio.get<Object?>('/models', cancelToken: cancel);
      final rows = (res.data as Map)['data'] as List;
      final info = rows.firstWhere((m) => m is Map && m['id'] == model) as Map;
      final context = info['context_length'];
      if (context is! int || context <= 0) return null;
      return (id: model, contextTokens: context, fromProvider: true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      return null;
    } on Object {
      return null;
    }
  }

  Future<List<Float32List>> embeddings({
    required String? apiKey,
    required ChatEmbeddingModel model,
    required List<String> input,
    void Function(ChatUsage usage)? onUsage,
    CancelToken? cancel,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    if (input.isEmpty ||
        input.length > 64 ||
        input.any(
          (t) =>
              t.isEmpty || !chatValidUnicode(t) || utf8.encode(t).length > 8000,
        )) {
      throw const AiException(
        AiError.invalidResponse,
        detail: 'embedding input budget',
      );
    }
    try {
      final res = await _dio.post<Object?>(
        '/embeddings',
        cancelToken: cancel,
        options: _auth(apiKey),
        data: {'model': model.id, 'input': input, 'encoding_format': 'float'},
      );
      final usage = res.data is Map
          ? parseChatUsage((res.data as Map)['usage'])
          : null;
      if (usage != null) onUsage?.call(usage);
      return parseChatEmbeddings(res.data, input.length, model);
    } on DioException catch (e) {
      // Preserve cancel/certificate/unknown so these never trigger provider fallback.
      if (e.type == DioExceptionType.cancel ||
          e.type == DioExceptionType.badCertificate ||
          e.type == DioExceptionType.unknown) {
        rethrow;
      }
      throw await _failure(e);
    } on FormatException catch (e) {
      throw AiException(AiError.invalidResponse, detail: e.message);
    }
  }

  Stream<String> _stream(
    String? apiKey,
    String model,
    String system,
    String user,
    CancelToken? cancel, {
    List<Map<String, String>>? messages,
    int? maxTokens,
    bool jsonOutput = false,
    void Function(ChatUsage usage)? onUsage,
  }) async* {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    final res = await _post<ResponseBody>(
      apiKey,
      model,
      system,
      user,
      stream: true,
      cancel: cancel,
      messages: messages,
      maxTokens: maxTokens,
      jsonOutput: jsonOutput,
      includeUsage: onUsage != null,
    );
    final sse = SseDecoder();
    try {
      await for (final chunk in utf8.decoder.bind(res.data!.stream)) {
        for (final data in sse.add(chunk)) {
          if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
          if (data == '[DONE]') return;
          final event = _event(data);
          if (event.usage != null) onUsage?.call(event.usage!);
          if (event.delta.isNotEmpty) yield event.delta;
        }
      }
    } on DioException catch (e) {
      throw await _failure(e);
    } on AiException {
      rethrow;
    } catch (e) {
      // The socket closed midstream.
      throw AiException(AiError.network, detail: '$e');
    }
    throw const AiException(AiError.network, detail: 'stream ended early');
  }

  /// Returns whether OpenRouter accepts the key; throws [AiException] for other errors.
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

  Future<String> _complete(
    String apiKey,
    String model,
    String user,
    void Function(ChatUsage usage)? onUsage,
  ) async {
    final res = await _post<Object?>(apiKey, model, aiSystemPrompt, user);
    final usage = res.data is Map
        ? parseChatUsage((res.data as Map)['usage'])
        : null;
    if (usage != null) onUsage?.call(usage);
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
    List<Map<String, String>>? messages,
    int? maxTokens,
    bool jsonOutput = false,
    bool includeUsage = false,
  }) async {
    try {
      return await _dio.post<T>(
        '/chat/completions',
        cancelToken: cancel,
        options: _auth(apiKey)
            .copyWith(responseType: stream ? ResponseType.stream : null),
        data: {
          'model': model,
          'messages':
              messages ??
              [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
          // Reasoning counts as output and adds latency; disable it or request the minimum.
          'reasoning': reasoningOff
              ? {'enabled': false}
              : {'effort': 'minimal', 'exclude': true},
          if (stream) 'stream': true,
          if (stream && includeUsage) 'stream_options': {'include_usage': true},
          'max_tokens': ?maxTokens,
          if (jsonOutput) 'temperature': 0,
          if (!stream || jsonOutput) 'response_format': {'type': 'json_object'},
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
          messages: messages,
          maxTokens: maxTokens,
          jsonOutput: jsonOutput,
          includeUsage: includeUsage,
        );
      }
      throw failure;
    }
  }

  /// Extracts `delta.content` from an SSE event; errors yield [AiError.http].
  static ({String delta, ChatUsage? usage}) _event(String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      return (delta: '', usage: null);
    }
    final delta = switch (json) {
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
    return (
      delta: delta,
      usage: json is Map ? parseChatUsage(json['usage']) : null,
    );
  }

  /// Detects providers that require reasoning despite a request to disable it.
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

  /// Reads an error body, including unread streaming [ResponseBody] instances.
  static Future<String> _body(Object? data) async =>
      data is ResponseBody ? await utf8.decodeStream(data.stream) : '$data';
}

/// Splits Server-Sent Events into complete `data:` lines.
/// Holds partial lines across chunks and discards comments and other fields.
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
  (ref) => OpenRouterService(
    null,
    (key) => ref.read(aiKeyRepositoryProvider).markRejected(key),
  ),
);
