import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/api_key.dart';
import '../../../../domain/models/ai_reply.dart';

/// State of the API key field in Settings.
enum KeyStatus {
  /// No key yet, or it can't be checked (offline): just a note about where it's
  /// stored, nothing alarming.
  idle,

  /// Settings just opened, the stored key is being re-read & re-checked. Held here
  /// so the text doesn't flip: idle → valid.
  checking,

  /// Accepted by OpenRouter (and saved).
  valid,

  /// The stored key was rejected (401/403), probably revoked.
  rejected,

  /// The newly entered key was rejected by OpenRouter, so it isn't saved.
  refused,

  /// The text isn't the shape of an OpenRouter API key, not saved.
  badFormat,
}

/// Last OpenRouter check result for the stored key. Lives while the app runs,
/// so reopening Settings shows the result at once without waiting for a
/// re-check.
class KeyVerdict {
  ({String key, bool ok})? last;
}

final keyVerdictProvider = Provider<KeyVerdict>((ref) => KeyVerdict());

/// API key field content: accepts text, checks its shape, asks OpenRouter, then
/// saves to secure storage. Garbage text and rejected keys never overwrite the
/// stored key. Empty = deleted.
class ApiKeyEntry extends Notifier<KeyStatus> {
  static const pause = Duration(milliseconds: 600);

  Timer? _later;

  /// Every keystroke / delete increments this; a late check result is discarded.
  int _round = 0;

  ApiKeyStore get _store => ref.read(apiKeyStoreProvider);

  @override
  KeyStatus build() {
    ref.onDispose(() {
      _later?.cancel();
      _round++; // a late check result must not touch dead state
    });
    unawaited(_checkStored());
    return switch (_verdict.last?.ok) {
      true => KeyStatus.valid,
      false => KeyStatus.rejected,
      null => KeyStatus.checking,
    };
  }

  KeyVerdict get _verdict => ref.read(keyVerdictProvider);

  /// Re-checks the stored key when Settings opens. If a previous result for the
  /// same key exists, the display stays and the re-check runs quietly (state
  /// only changes if the result differs).
  Future<void> _checkStored() async {
    final round = _round;
    final saved = await _store.read();
    if (round != _round) return;
    if (saved == null) {
      _verdict.last = null;
      state = KeyStatus.idle;
      return;
    }
    if (parseApiKey(saved) == null) {
      _verdict.last = null;
      state = KeyStatus.badFormat;
      return;
    }
    if (_verdict.last?.key != saved) {
      _verdict.last = null;
      state = KeyStatus.checking;
    }
    final ok = await _check(saved);
    if (round != _round) return;
    _remember(saved, ok);
    state = switch (ok) {
      true => KeyStatus.valid,
      false => KeyStatus.rejected,
      null => KeyStatus.idle,
    };
  }

  /// Field text changed (usually once, on paste).
  void edit(String text) {
    _later?.cancel();
    final round = ++_round;
    if (text.trim().isEmpty) {
      unawaited(_store.write(''));
      _verdict.last = null;
      state = KeyStatus.idle;
      return;
    }
    final key = parseApiKey(text);
    if (key == null) {
      state = KeyStatus.badFormat;
      return;
    }
    state = KeyStatus.idle;
    _later = Timer(pause, () async {
      final ok = await _check(key);
      if (round != _round) return;
      if (ok == false) {
        state = KeyStatus.refused;
        return;
      }
      // Right shape and not rejected (or offline): save.
      await _store.write(key);
      if (round != _round) return;
      _remember(key, ok);
      state = ok == true ? KeyStatus.valid : KeyStatus.idle;
    });
  }

  /// Offline (null) isn't recorded: there's no result to show.
  void _remember(String key, bool? ok) =>
      _verdict.last = ok == null ? null : (key: key, ok: ok);

  /// Delete button: the key in secure storage is deleted too.
  void clear() => edit('');

  /// true = accepted, false = rejected, null = can't check.
  Future<bool?> _check(String key) async {
    try {
      return await ref.read(openRouterServiceProvider).checkKey(key);
    } on AiException {
      return null;
    }
  }
}

final apiKeyEntryProvider =
    NotifierProvider.autoDispose<ApiKeyEntry, KeyStatus>(ApiKeyEntry.new);
