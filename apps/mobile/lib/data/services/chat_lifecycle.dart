import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/chat_repository.dart';

/// Await chat writes before changing their source content or replacing SQLite.
class ChatLifecycle {
  final _stops = <Object, ({int bookId, Future<void> Function() stop})>{};
  final _paused = <int, int>{};
  bool _closed = false;

  bool canStart(int bookId) => !_closed && !_paused.containsKey(bookId);

  void Function() register(int bookId, Future<void> Function() stop) {
    final key = Object();
    _stops[key] = (bookId: bookId, stop: stop);
    return () => _stops.remove(key);
  }

  Future<void> _stop([int? bookId]) => Future.wait([
    for (final entry in _stops.values.toList())
      if (bookId == null || entry.bookId == bookId) entry.stop(),
  ]);

  Future<T> changeContent<T>(int bookId, Future<T> Function() change) async {
    if (_closed) throw StateError('Database sedang diganti');
    _paused.update(bookId, (n) => n + 1, ifAbsent: () => 1);
    try {
      await _stop(bookId);
      return await change();
    } finally {
      final remaining = _paused[bookId]! - 1;
      remaining == 0 ? _paused.remove(bookId) : _paused[bookId] = remaining;
    }
  }

  Future<void> close() async {
    _closed = true;
    await _stop();
  }
}

final chatLifecycleProvider = Provider<ChatLifecycle>((ref) {
  ref.watch(chatRepositoryProvider);
  return ChatLifecycle();
});
