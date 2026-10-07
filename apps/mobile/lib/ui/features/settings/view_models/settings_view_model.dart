import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/models/ai_reply.dart';

/// API key diterima OpenRouter? null = belum ada key, lagi offline, atau
/// gagal ngecek (gak usah bikin panik).
final apiKeyCheckProvider = FutureProvider.autoDispose<bool?>((ref) async {
  final key = await ref.watch(apiKeyProvider.future);
  if (key == null) return null;
  try {
    return await ref.watch(openRouterServiceProvider).checkKey(key);
  } on AiException {
    return null;
  }
});
